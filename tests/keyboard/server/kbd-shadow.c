/*
 * Local RDP test server for the genuine mstsc client (EXP-074).  FreeRDP is used only
 * on the server side.  Records what the client advertises and sends for the keyboard:
 *   client-keyboard layout=XXXXXXXX type=N subtype=N fkeys=N codepage=N
 *   key down|up scan=XX ext=0|1 [ext1]       (TS_KEYBOARD_EVENT, scancode input)
 *   unicode down|up U+XXXX                  (TS_UNICODE_KEYBOARD_EVENT)
 *   sync flags=0xN                          (TS_SYNC_EVENT, lock key state)
 * Input events are not forwarded to the shadowed X display.
 *   kbd-shadow OUT_DIR [/port:N] [/bind-address:ADDR] [/sam-file:FILE]
 */
#include <freerdp/server/shadow.h>
#include <freerdp/server/server-common.h>
#include <freerdp/settings.h>
#include <freerdp/input.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static char out_dir[1024];

static void logev(const char* fmt, ...)
{
    char path[1100];
    FILE* f;
    va_list ap;

    snprintf(path, sizeof(path), "%s/events.log", out_dir);
    if (!(f = fopen(path, "a"))) return;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

extern int ShadowSubsystemEntry(RDP_SHADOW_ENTRY_POINTS*);
static pfnShadowSubsystemNew orig_new;
static pfnShadowClientConnect orig_connect;

static BOOL my_connect(rdpShadowSubsystem* subsystem, rdpShadowClient* client)
{
    BOOL ok = orig_connect ? orig_connect(subsystem, client) : TRUE;
    const rdpSettings* s = client->context.settings;

    logev("client-keyboard layout=%08X type=%u subtype=%u fkeys=%u codepage=%u",
          freerdp_settings_get_uint32(s, FreeRDP_KeyboardLayout),
          freerdp_settings_get_uint32(s, FreeRDP_KeyboardType),
          freerdp_settings_get_uint32(s, FreeRDP_KeyboardSubType),
          freerdp_settings_get_uint32(s, FreeRDP_KeyboardFunctionKey),
          freerdp_settings_get_uint32(s, FreeRDP_KeyboardCodePage));
    return ok;
}

static BOOL my_sync(rdpShadowSubsystem* subsystem, rdpShadowClient* client, UINT32 flags)
{
    (void)subsystem; (void)client;
    logev("sync flags=0x%x", flags);
    return TRUE;
}

static BOOL my_key(rdpShadowSubsystem* subsystem, rdpShadowClient* client, UINT16 flags, UINT8 code)
{
    (void)subsystem; (void)client;
    logev("key %s scan=%02x ext=%d%s", (flags & KBD_FLAGS_RELEASE) ? "up" : "down", code,
          !!(flags & KBD_FLAGS_EXTENDED), (flags & KBD_FLAGS_EXTENDED1) ? " ext1" : "");
    return TRUE;
}

static BOOL my_unicode(rdpShadowSubsystem* subsystem, rdpShadowClient* client, UINT16 flags, UINT16 code)
{
    (void)subsystem; (void)client;
    logev("unicode %s U+%04X", (flags & KBD_FLAGS_RELEASE) ? "up" : "down", code);
    return TRUE;
}

static rdpShadowSubsystem* my_new(void)
{
    rdpShadowSubsystem* subsystem = orig_new();
    if (!subsystem) return NULL;
    orig_connect = subsystem->ClientConnect;
    subsystem->ClientConnect = my_connect;
    subsystem->SynchronizeEvent = my_sync;
    subsystem->KeyboardEvent = my_key;
    subsystem->UnicodeKeyboardEvent = my_unicode;
    return subsystem;
}

static int my_entry(RDP_SHADOW_ENTRY_POINTS* entry)
{
    int rc = ShadowSubsystemEntry(entry);
    orig_new = entry->New;
    entry->New = my_new;
    return rc;
}

int main(int argc, char** argv)
{
    rdpShadowServer* server;
    if (argc < 2)
    {
        fprintf(stderr, "usage: %s OUT_DIR [shadow options]\n", argv[0]);
        return 2;
    }
    snprintf(out_dir, sizeof(out_dir), "%s", argv[1]);
    mkdir(out_dir, 0755);
    shadow_subsystem_set_entry(my_entry);
    if (!(server = shadow_server_new())) return 1;
    for (int i = 2; i < argc; i++)
    {
        if (!strncmp(argv[i], "/port:", 6)) server->port = strtoul(argv[i] + 6, NULL, 10);
        else if (!strncmp(argv[i], "/bind-address:", 14))
        {
            char binding[256];
            snprintf(binding, sizeof(binding), "bind-address,%s", argv[i] + 14);
            free(server->ipcSocket);
            server->ipcSocket = strdup(binding);
        }
        else if (!strncmp(argv[i], "/sam-file:", 10))
            freerdp_settings_set_string(server->settings, FreeRDP_NtlmSamFile, argv[i] + 10);
        else
        {
            fprintf(stderr, "unknown option %s\n", argv[i]);
            return 2;
        }
    }
    if (shadow_server_init(server) < 0) return 1;
    if (shadow_server_start(server) < 0) return 1;
    logev("listening");
    WaitForSingleObject(server->thread, INFINITE);
    shadow_server_stop(server);
    shadow_server_uninit(server);
    shadow_server_free(server);
    return 0;
}
