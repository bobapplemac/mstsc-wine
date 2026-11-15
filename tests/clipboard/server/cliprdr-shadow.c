/*
 * Test RDP *server* with a clipboard (cliprdr) channel, for driving the genuine mstsc
 * client offline.  Only the server side is FreeRDP; the client under test is always the
 * genuine mstsc.exe on Wine (spec: never substitute the client).
 *
 * It is the FreeRDP shadow server (X11 subsystem, sharing a private Xvfb) with a cliprdr
 * server context attached to every client.  The shadow server has no clipboard of its own.
 *
 *   cliprdr-shadow CTL_FIFO OUT_DIR [/port:N] [/bind-address:ADDR] [/sam-file:SAM]
 *
 * Commands, one per line, written to CTL_FIFO (the "remote" side copies something):
 *   text <utf-8 text, \n and \\ escaped>   announce CF_UNICODETEXT
 *   file <name> <path>                     announce FileGroupDescriptorW with one file
 *   dib <path>                             announce CF_DIB with the bytes of <path>
 * Results in OUT_DIR (the "remote" side pastes what the client copied):
 *   events.log        one line per protocol event
 *   text.txt          last CF_UNICODETEXT received, as UTF-8 (written atomically)
 *   dib.bin           last CF_DIB received
 *   files/<name>      files received through FileGroupDescriptorW + FileContents
 */
#include <freerdp/server/shadow.h>
#include <freerdp/server/cliprdr.h>
#include <winpr/wtsapi.h>
#include <winpr/string.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>

#define CF_TEXT_ 1
#define CF_DIB_ 8
#define CF_UNICODETEXT_ 13
#define FGD_ID 0xC0A0 /* our id for FileGroupDescriptorW; the client maps names, not ids */

static const char* ctl_path;
static char out_dir[1024];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static CliprdrServerContext* cur; /* latest connected client */

/* what the "remote" clipboard holds */
static BYTE* srv_data;     static size_t srv_len;
static UINT32 srv_format;
static char srv_file_name[256]; static char srv_file_path[1024];

/* client clipboard state */
static UINT32 cli_fgd_id;            /* client's id for FileGroupDescriptorW */
static int cli_nfiles, cli_file_idx;
static char cli_names[64][520];
static UINT64 cli_sizes[64], cli_got;
static int cli_size_phase;
static FILE* cli_fp;
static enum { REQ_NONE, REQ_TEXT, REQ_DIB, REQ_FGD } pending;
static int want_dib, paste_text;
static UINT32 paste_fgd;
static UINT64 paste_due;

static UINT64 now_ms(void)
{
	struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000ull + ts.tv_nsec / 1000000;
}

static void logev(const char* fmt, ...)
{
	char p[1100]; snprintf(p, sizeof p, "%s/events.log", out_dir);
	FILE* f = fopen(p, "a");
	if (!f) return;
	va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
	fputc('\n', f); fclose(f);
}

static void write_file(const char* name, const BYTE* d, size_t n)
{
	char p[1100], t[1110];
	snprintf(p, sizeof p, "%s/%s", out_dir, name); snprintf(t, sizeof t, "%s.tmp", p);
	FILE* f = fopen(t, "wb");
	if (!f) return;
	fwrite(d, 1, n, f); fclose(f); rename(t, p);
}

static char* utf16_to_utf8(const BYTE* d, size_t n)
{
	size_t wn = n / 2;
	while (wn && !((const WCHAR*)d)[wn - 1]) wn--;   /* drop trailing NULs */
	char* s = ConvertWCharNToUtf8Alloc((const WCHAR*)d, wn, NULL);
	return s ? s : strdup("");
}

static UINT request(CliprdrServerContext* c, UINT32 id)
{
	CLIPRDR_FORMAT_DATA_REQUEST r = { 0 };
	r.common.msgType = CB_FORMAT_DATA_REQUEST;
	r.requestedFormatId = id;
	return c->ServerFormatDataRequest(c, &r);
}

static UINT32 lock_id; /* clipDataId of the client data being pasted, as rdpclip locks it */

static UINT request_contents(CliprdrServerContext* c, UINT32 idx, UINT32 flags, UINT64 pos, UINT32 cb)
{
	CLIPRDR_FILE_CONTENTS_REQUEST r = { 0 };
	r.haveClipDataId = TRUE; r.clipDataId = lock_id;
	r.common.msgType = CB_FILECONTENTS_REQUEST;
	r.streamId = idx + 1; r.listIndex = idx; r.dwFlags = flags;
	r.nPositionLow = (UINT32)pos; r.nPositionHigh = (UINT32)(pos >> 32); r.cbRequested = cb;
	return c->ServerFileContentsRequest(c, &r);
}

/* ---- client -> server ---- */

static UINT on_client_caps(CliprdrServerContext* c, const CLIPRDR_CAPABILITIES* caps)
{
	for (UINT32 i = 0; i < caps->cCapabilitiesSets; i++)
	{
		const CLIPRDR_CAPABILITY_SET* s = &caps->capabilitySets[i];
		if (s->capabilitySetType == CB_CAPSTYPE_GENERAL)
		{
			const CLIPRDR_GENERAL_CAPABILITY_SET* g = (const CLIPRDR_GENERAL_CAPABILITY_SET*)s;
			logev("client-caps version=%u flags=0x%x", g->version, g->generalFlags);
		}
	}
	return CHANNEL_RC_OK;
}

static UINT on_client_format_list(CliprdrServerContext* c, const CLIPRDR_FORMAT_LIST* fl)
{
	char buf[4096]; size_t o = 0;
	UINT32 text = 0, dib = 0;
	cli_fgd_id = 0;
	for (UINT32 i = 0; i < fl->numFormats; i++)
	{
		const CLIPRDR_FORMAT* f = &fl->formats[i];
		o += snprintf(buf + o, sizeof buf - o > 0 ? sizeof buf - o : 0, "%s%u:%s", i ? "," : "",
		              f->formatId, f->formatName ? f->formatName : "");
		if (o >= sizeof buf) o = sizeof buf - 1;
		if (f->formatId == CF_UNICODETEXT_) text = 1;
		if (f->formatId == CF_DIB_) dib = 1;
		if (f->formatName && !strcmp(f->formatName, "FileGroupDescriptorW")) cli_fgd_id = f->formatId;
	}
	logev("client-formats %s", buf);
	CLIPRDR_FORMAT_LIST_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_LIST_RESPONSE; resp.common.msgFlags = CB_RESPONSE_OK;
	c->ServerFormatListResponse(c, &resp);
	/* "paste" once the client's format lists settle, as a user would; a client may
	 * announce the same clipboard more than once */
	pthread_mutex_lock(&lock);
	paste_text = text; want_dib = dib; paste_fgd = cli_fgd_id;
	paste_due = (text || dib || cli_fgd_id) ? now_ms() + 700 : 0;
	pthread_mutex_unlock(&lock);
	return CHANNEL_RC_OK;
}

static void next_file(CliprdrServerContext* c)
{
	if (cli_fp) { fclose(cli_fp); cli_fp = NULL; }
	while (++cli_file_idx < cli_nfiles)
	{
		char* name = utf16_to_utf8((const BYTE*)cli_names[cli_file_idx], 520);
		char p[1700]; snprintf(p, sizeof p, "%s/files/%s", out_dir, name);
		for (char* q = p + strlen(out_dir) + 7; *q; q++) if (*q == '\\') *q = '/';
		char* sl = strrchr(p, '/'); if (sl) { *sl = 0; char cmd[1800]; snprintf(cmd, sizeof cmd, "mkdir -p '%s'", p); system(cmd); *sl = '/'; }
		free(name);
		cli_fp = fopen(p, "wb"); cli_got = 0; cli_size_phase = 1;
		if (!cli_fp) { logev("cannot create %s", p); continue; }
		request_contents(c, cli_file_idx, FILECONTENTS_SIZE, 0, 8);
		return;
	}
	logev("client-files-done %d", cli_nfiles);
}

static UINT on_client_data_response(CliprdrServerContext* c, const CLIPRDR_FORMAT_DATA_RESPONSE* r)
{
	const BYTE* d = r->requestedFormatData; UINT32 n = r->common.dataLen;
	int ok = r->common.msgFlags & CB_RESPONSE_OK;
	int what = pending; pending = REQ_NONE;
	if (!ok) { logev("client-data-fail req=%d", what); return CHANNEL_RC_OK; }
	if (what == REQ_TEXT)
	{
		char* s = utf16_to_utf8(d, n);
		write_file("text.txt", (const BYTE*)s, strlen(s));
		logev("client-text bytes=%zu", strlen(s));
		free(s);
		if (want_dib) { pending = REQ_DIB; request(c, CF_DIB_); }
	}
	else if (what == REQ_DIB)
	{
		write_file("dib.bin", d, n);
		logev("client-dib bytes=%u", n);
	}
	else if (what == REQ_FGD)
	{
		UINT32 cnt = n >= 4 ? *(const UINT32*)d : 0;
		if (cnt > 64 || 4 + cnt * 592ull > n) { logev("client-fgd bad count=%u len=%u", cnt, n); return CHANNEL_RC_OK; }
		cli_nfiles = 0;
		for (UINT32 i = 0; i < cnt; i++)
		{
			const BYTE* fd = d + 4 + i * 592;
			UINT32 attrs = *(const UINT32*)(fd + 36);
			memcpy(cli_names[cli_nfiles], fd + 72, 520);
			cli_sizes[cli_nfiles] = ((UINT64)*(const UINT32*)(fd + 64) << 32) | *(const UINT32*)(fd + 68);
			char* name = utf16_to_utf8(fd + 72, 520);
			logev("client-fgd %u: %s attrs=0x%x size=%llu", i, name, attrs, (unsigned long long)cli_sizes[cli_nfiles]);
			if (attrs & 0x10) /* FILE_ATTRIBUTE_DIRECTORY */
			{
				char cmd[1800]; snprintf(cmd, sizeof cmd, "mkdir -p '%s/files/%s'", out_dir, name);
				for (char* q = cmd; *q; q++) if (*q == '\\') *q = '/';
				system(cmd);
			}
			else cli_nfiles++;
			free(name);
		}
		char p[1100]; snprintf(p, sizeof p, "%s/files", out_dir); mkdir(p, 0755);
		cli_file_idx = -1; next_file(c);
	}
	return CHANNEL_RC_OK;
}

static UINT on_client_contents_response(CliprdrServerContext* c, const CLIPRDR_FILE_CONTENTS_RESPONSE* r)
{
	if (!(r->common.msgFlags & CB_RESPONSE_OK))
	{
		logev("client-contents-fail index=%d", cli_file_idx);
		next_file(c);
		return CHANNEL_RC_OK;
	}
	if (!cli_fp) return CHANNEL_RC_OK;
	if (cli_size_phase)
	{
		/* FILECONTENTS_SIZE reply: the 64-bit size */
		cli_size_phase = 0;
		cli_sizes[cli_file_idx] = r->cbRequested >= 8 ? *(const UINT64*)r->requestedData : 0;
		logev("client-contents-size %d %llu", cli_file_idx, (unsigned long long)cli_sizes[cli_file_idx]);
	}
	else
	{
		fwrite(r->requestedData, 1, r->cbRequested, cli_fp);
		cli_got += r->cbRequested;
		if (!r->cbRequested) cli_sizes[cli_file_idx] = cli_got; /* short file: stop */
	}
	if (cli_got < cli_sizes[cli_file_idx])
	{
		UINT64 left = cli_sizes[cli_file_idx] - cli_got;
		return request_contents(c, cli_file_idx, FILECONTENTS_RANGE, cli_got, left > 65536 ? 65536 : (UINT32)left);
	}
	logev("client-file %d bytes=%llu", cli_file_idx, (unsigned long long)cli_got);
	next_file(c);
	return CHANNEL_RC_OK;
}

static UINT on_client_data_request(CliprdrServerContext* c, const CLIPRDR_FORMAT_DATA_REQUEST* r)
{
	CLIPRDR_FORMAT_DATA_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_DATA_RESPONSE;
	pthread_mutex_lock(&lock);
	logev("client-request format=%u", r->requestedFormatId);
	BYTE* fgd = NULL;
	if (r->requestedFormatId == srv_format && srv_format != FGD_ID && srv_data)
	{
		resp.common.msgFlags = CB_RESPONSE_OK; resp.common.dataLen = srv_len; resp.requestedFormatData = srv_data;
	}
	else if (r->requestedFormatId == FGD_ID && srv_format == FGD_ID)
	{
		struct stat st; stat(srv_file_path, &st);
		fgd = calloc(1, 4 + 592);
		*(UINT32*)fgd = 1;
		BYTE* fd = fgd + 4;
		*(UINT32*)fd = 0x4040 | 0x4; /* FD_FILESIZE | FD_PROGRESSUI | FD_ATTRIBUTES */
		*(UINT32*)(fd + 36) = 0x20;  /* FILE_ATTRIBUTE_ARCHIVE */
		*(UINT32*)(fd + 64) = (UINT32)((UINT64)st.st_size >> 32);
		*(UINT32*)(fd + 68) = (UINT32)st.st_size;
		ConvertUtf8ToWChar(srv_file_name, (WCHAR*)(fd + 72), 259);
		resp.common.msgFlags = CB_RESPONSE_OK; resp.common.dataLen = 4 + 592; resp.requestedFormatData = fgd;
	}
	else if (r->requestedFormatId == FGD_ID + 2 && srv_format == FGD_ID)
	{
		static UINT32 effect = 1; /* DROPEFFECT_COPY */
		resp.common.msgFlags = CB_RESPONSE_OK; resp.common.dataLen = 4; resp.requestedFormatData = (BYTE*)&effect;
	}
	else resp.common.msgFlags = CB_RESPONSE_FAIL;
	UINT rc = c->ServerFormatDataResponse(c, &resp);
	pthread_mutex_unlock(&lock);
	free(fgd);
	return rc;
}

static UINT on_client_contents_request(CliprdrServerContext* c, const CLIPRDR_FILE_CONTENTS_REQUEST* r)
{
	CLIPRDR_FILE_CONTENTS_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FILECONTENTS_RESPONSE; resp.streamId = r->streamId;
	BYTE* buf = NULL; UINT64 pos = ((UINT64)r->nPositionHigh << 32) | r->nPositionLow;
	FILE* f = r->listIndex == 0 ? fopen(srv_file_path, "rb") : NULL;
	if (f && (r->dwFlags & FILECONTENTS_SIZE))
	{
		fseek(f, 0, SEEK_END); UINT64 sz = ftell(f);
		buf = malloc(8); memcpy(buf, &sz, 8); resp.cbRequested = 8;
		resp.common.msgFlags = CB_RESPONSE_OK;
	}
	else if (f)
	{
		buf = malloc(r->cbRequested ? r->cbRequested : 1);
		fseek(f, (long)pos, SEEK_SET);
		resp.cbRequested = fread(buf, 1, r->cbRequested, f);
		resp.common.msgFlags = CB_RESPONSE_OK;
	}
	else resp.common.msgFlags = CB_RESPONSE_FAIL;
	logev("client-contents-request index=%u flags=0x%x pos=%llu cb=%u -> %u", r->listIndex, r->dwFlags,
	      (unsigned long long)pos, r->cbRequested, resp.cbRequested);
	resp.requestedData = buf;
	if (f) fclose(f);
	UINT rc = c->ServerFileContentsResponse(c, &resp);
	free(buf);
	return rc;
}

static UINT on_client_format_list_response(CliprdrServerContext* c, const CLIPRDR_FORMAT_LIST_RESPONSE* r)
{
	logev("client-format-list-response %s", (r->common.msgFlags & CB_RESPONSE_OK) ? "ok" : "fail");
	return CHANNEL_RC_OK;
}

static UINT on_client_temp_dir(CliprdrServerContext* c, const CLIPRDR_TEMP_DIRECTORY* t)
{
	logev("client-temp-dir"); return CHANNEL_RC_OK;
}
static UINT on_client_lock(CliprdrServerContext* c, const CLIPRDR_LOCK_CLIPBOARD_DATA* l)
{ logev("client-lock %u", l->clipDataId); return CHANNEL_RC_OK; }
static UINT on_client_unlock(CliprdrServerContext* c, const CLIPRDR_UNLOCK_CLIPBOARD_DATA* l)
{ logev("client-unlock %u", l->clipDataId); return CHANNEL_RC_OK; }

static UINT request(CliprdrServerContext* c, UINT32 id);

static void* paste_thread(void* arg)
{
	for (;;)
	{
		usleep(50000);
		pthread_mutex_lock(&lock);
		CliprdrServerContext* c = cur;
		int go = c && paste_due && now_ms() >= paste_due;
		int text = paste_text, dib = want_dib; UINT32 fgd = paste_fgd;
		if (go) paste_due = 0;
		pthread_mutex_unlock(&lock);
		if (!go) continue;
		if (fgd)
		{
			/* rdpclip locks the client's data before it asks for file contents */
			CLIPRDR_LOCK_CLIPBOARD_DATA l = { 0 };
			l.common.msgType = CB_LOCK_CLIPDATA; l.clipDataId = ++lock_id;
			c->ServerLockClipboardData(c, &l);
			pending = REQ_FGD; request(c, fgd);
		}
		else if (text) { pending = REQ_TEXT; request(c, CF_UNICODETEXT_); }
		else if (dib) { pending = REQ_DIB; request(c, CF_DIB_); }
	}
	return NULL;
}

/* ---- server -> client: commands ---- */

static void announce(UINT32 id, const char* name)
{
	CliprdrServerContext* c = cur;
	if (!c) { logev("announce: no client"); return; }
	/* files go with FileContents and Preferred DropEffect, as rdpclip announces them */
	CLIPRDR_FORMAT f[3] = { { id, (char*)name }, { FGD_ID + 1, "FileContents" },
		                    { FGD_ID + 2, "Preferred DropEffect" } };
	CLIPRDR_FORMAT_LIST fl = { 0 };
	fl.common.msgType = CB_FORMAT_LIST; fl.numFormats = id == FGD_ID ? 3 : 1; fl.formats = f;
	UINT rc = c->ServerFormatList(c, &fl);
	logev("server-formats %u:%s rc=%u", id, name ? name : "", rc);
}

static void* ctl_thread(void* arg)
{
	for (;;)
	{
		FILE* f = fopen(ctl_path, "r");
		if (!f) { sleep(1); continue; }
		char line[65536];
		while (fgets(line, sizeof line, f))
		{
			line[strcspn(line, "\n")] = 0;
			pthread_mutex_lock(&lock);
			if (!strncmp(line, "text ", 5))
			{
				char* s = line + 5, *o = s;
				for (char* p = s; *p; p++)
				{
					if (*p == '\\' && p[1] == 'n') { *o++ = '\r'; *o++ = '\n'; p++; }
					else if (*p == '\\' && p[1] == '\\') { *o++ = '\\'; p++; }
					else *o++ = *p;
				}
				*o = 0;
				size_t wn = 0;
				WCHAR* w = ConvertUtf8ToWCharAlloc(s, &wn);
				free(srv_data); srv_data = (BYTE*)w; srv_len = (wn + 1) * 2; srv_format = CF_UNICODETEXT_;
				pthread_mutex_unlock(&lock);
				announce(CF_UNICODETEXT_, NULL);
				continue;
			}
			if (!strncmp(line, "file ", 5))
			{
				char* sp = strchr(line + 5, ' ');
				if (sp) { *sp = 0; snprintf(srv_file_name, sizeof srv_file_name, "%s", line + 5); snprintf(srv_file_path, sizeof srv_file_path, "%s", sp + 1); }
				srv_format = FGD_ID;
				pthread_mutex_unlock(&lock);
				announce(FGD_ID, "FileGroupDescriptorW");
				continue;
			}
			if (!strncmp(line, "dib ", 4))
			{
				FILE* d = fopen(line + 4, "rb");
				if (d)
				{
					fseek(d, 0, SEEK_END); srv_len = ftell(d); fseek(d, 0, SEEK_SET);
					free(srv_data); srv_data = malloc(srv_len); fread(srv_data, 1, srv_len, d); fclose(d);
					srv_format = CF_DIB_;
				}
				pthread_mutex_unlock(&lock);
				announce(CF_DIB_, NULL);
				continue;
			}
			pthread_mutex_unlock(&lock);
			logev("unknown command");
		}
		fclose(f);
	}
	return NULL;
}

/* ---- shadow subsystem wrapper ---- */

extern int ShadowSubsystemEntry(RDP_SHADOW_ENTRY_POINTS* pEntryPoints);
static pfnShadowSubsystemNew orig_new;
static pfnShadowClientConnect orig_connect;
static pfnShadowClientDisconnect orig_disconnect;

static BOOL my_connect(rdpShadowSubsystem* s, rdpShadowClient* client)
{
	BOOL ok = orig_connect ? orig_connect(s, client) : TRUE;
	if (!WTSVirtualChannelManagerIsChannelJoined(client->vcm, CLIPRDR_SVC_CHANNEL_NAME))
	{
		logev("cliprdr channel not joined");
		return ok;
	}
	CliprdrServerContext* c = cliprdr_server_context_new(client->vcm);
	c->rdpcontext = &client->context;
	c->useLongFormatNames = TRUE; c->streamFileClipEnabled = TRUE;
	c->fileClipNoFilePaths = TRUE; c->canLockClipData = TRUE;
	c->autoInitializationSequence = TRUE;
	c->ClientCapabilities = on_client_caps;
	c->ClientFormatList = on_client_format_list;
	c->ClientFormatListResponse = on_client_format_list_response;
	c->ClientFormatDataRequest = on_client_data_request;
	c->ClientFormatDataResponse = on_client_data_response;
	c->ClientFileContentsRequest = on_client_contents_request;
	c->ClientFileContentsResponse = on_client_contents_response;
	c->TempDirectory = on_client_temp_dir;
	c->ClientLockClipboardData = on_client_lock;
	c->ClientUnlockClipboardData = on_client_unlock;
	if (c->Start(c) != CHANNEL_RC_OK) { logev("cliprdr start failed"); return ok; }
	cur = c;
	logev("cliprdr started");
	return ok;
}

static void my_disconnect(rdpShadowSubsystem* s, rdpShadowClient* client)
{
	logev("client disconnected");
	if (cur && cur->rdpcontext == &client->context) { CliprdrServerContext* c = cur; cur = NULL; c->Stop(c); cliprdr_server_context_free(c); }
	if (orig_disconnect) orig_disconnect(s, client);
}

static rdpShadowSubsystem* my_new(void)
{
	rdpShadowSubsystem* s = orig_new();
	if (s)
	{
		orig_connect = s->ClientConnect; s->ClientConnect = my_connect;
		orig_disconnect = s->ClientDisconnect; s->ClientDisconnect = my_disconnect;
	}
	return s;
}

static int my_entry(RDP_SHADOW_ENTRY_POINTS* ep)
{
	int rc = ShadowSubsystemEntry(ep);
	orig_new = ep->New; ep->New = my_new;
	return rc;
}

int main(int argc, char** argv)
{
	if (argc < 3) { fprintf(stderr, "usage: %s CTL_FIFO OUT_DIR [shadow options]\n", argv[0]); return 2; }
	ctl_path = argv[1];
	snprintf(out_dir, sizeof out_dir, "%s", argv[2]);
	mkdir(out_dir, 0755);
	if (access(ctl_path, F_OK) && mkfifo(ctl_path, 0600)) { perror("mkfifo"); return 1; }
	pthread_t t; pthread_create(&t, NULL, ctl_thread, NULL);
	pthread_create(&t, NULL, paste_thread, NULL);
	shadow_subsystem_set_entry(my_entry);
	rdpShadowServer* server = shadow_server_new();
	if (!server) return 1;
	/* the shadow server's own option table lives in freerdp-shadow-cli, so parse the few
	 * options the tests need here */
	for (int i = 3; i < argc; i++)
	{
		if (!strncmp(argv[i], "/port:", 6)) server->port = strtoul(argv[i] + 6, NULL, 10);
		else if (!strncmp(argv[i], "/bind-address:", 14))
		{
			char b[256]; snprintf(b, sizeof b, "bind-address,%s", argv[i] + 14);
			free(server->ipcSocket); server->ipcSocket = strdup(b);
		}
		else if (!strncmp(argv[i], "/sam-file:", 10))
			freerdp_settings_set_string(server->settings, FreeRDP_NtlmSamFile, argv[i] + 10);
		else { fprintf(stderr, "unknown option %s\n", argv[i]); return 2; }
	}
	if (shadow_server_init(server) < 0) { fprintf(stderr, "init failed\n"); return 1; }
	if (shadow_server_start(server) < 0) { fprintf(stderr, "start failed\n"); return 1; }
	logev("listening");
	WaitForSingleObject(server->thread, INFINITE);
	shadow_server_stop(server); shadow_server_uninit(server); shadow_server_free(server);
	return 0;
}
