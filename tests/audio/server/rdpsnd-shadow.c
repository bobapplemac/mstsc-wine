/*
 * Local RDP test server for the genuine mstsc client.  FreeRDP is used only on
 * the server side.  Once rdpsnd negotiation completes, send a deterministic
 * 440 Hz stereo PCM tone and record the formats advertised by the client.
 */
#include <freerdp/server/shadow.h>
#include <freerdp/server/server-common.h>
#include <freerdp/settings.h>
#include <math.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

static char out_dir[1024];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static rdpShadowClient* audio_client;
static int stop_audio;
static pthread_t audio_thread;
static int audio_thread_started;

static void logev(const char* fmt, ...)
{
    char path[1100];
    FILE* f;
    va_list ap;

    snprintf(path, sizeof(path), "%s/events.log", out_dir);
    f = fopen(path, "a");
    if (!f) return;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

static void log_format(const char* side, size_t index, const AUDIO_FORMAT* f)
{
    logev("%s-format %zu tag=%u channels=%u rate=%u avg=%u align=%u bits=%u extra=%u",
          side, index, f->wFormatTag, f->nChannels, f->nSamplesPerSec,
          f->nAvgBytesPerSec, f->nBlockAlign, f->wBitsPerSample, f->cbSize);
}

static void* send_tone(void* unused)
{
    enum { RATE = 44100, CHANNELS = 2, FRAMES = 882 };
    INT16 samples[FRAMES * CHANNELS];
    unsigned phase = 0;
    UINT16 timestamp = 0;
    int announced = 0;
    (void)unused;

    for (;;)
    {
        rdpShadowClient* client;
        RdpsndServerContext* r;
        pthread_mutex_lock(&lock);
        client = audio_client;
        if (stop_audio || !client)
        {
            pthread_mutex_unlock(&lock);
            break;
        }
        r = client->rdpsnd;
        pthread_mutex_unlock(&lock);

        if (!r || !r->num_client_formats || !r->src_format)
        {
            usleep(20000);
            continue;
        }
        if (!announced)
        {
            logev("client-audio version=%u flags=0x%x quality=%u formats=%u selected=%u",
                  r->clientVersion, r->capsFlags, r->qualityMode,
                  r->num_client_formats, r->selected_client_format);
            for (size_t i = 0; i < r->num_client_formats; i++)
                log_format("client", i, &r->client_formats[i]);
            log_format("source", 0, r->src_format);
            announced = 1;
        }

        for (size_t i = 0; i < FRAMES; i++, phase++)
        {
            const double t = (double)phase / RATE;
            const INT16 sample = (INT16)(sin(2.0 * 3.141592653589793 * 440.0 * t) * 12000.0);
            samples[i * 2] = sample;
            samples[i * 2 + 1] = sample;
        }
        {
            UINT rc = r->SendSamples(r, samples, FRAMES, timestamp);
            if (rc != CHANNEL_RC_OK)
            {
                logev("send-failed rc=%u", rc);
                break;
            }
        }
        timestamp += 20;
        if ((phase % RATE) < FRAMES) logev("sent-frames total=%u", phase);
        usleep(20000);
    }
    logev("audio-thread-stopped");
    return NULL;
}

extern int ShadowSubsystemEntry(RDP_SHADOW_ENTRY_POINTS*);
static pfnShadowSubsystemNew orig_new;
static pfnShadowClientConnect orig_connect;
static pfnShadowClientDisconnect orig_disconnect;

static BOOL my_connect(rdpShadowSubsystem* subsystem, rdpShadowClient* client)
{
    BOOL ok = orig_connect ? orig_connect(subsystem, client) : TRUE;

    pthread_mutex_lock(&lock);
    audio_client = client;
    stop_audio = 0;
    pthread_mutex_unlock(&lock);
    logev("client-connected rdpsnd=%s", client->rdpsnd ? "ready" : "pending");
    if (!audio_thread_started && !pthread_create(&audio_thread, NULL, send_tone, NULL))
        audio_thread_started = 1;
    return ok;
}

static void my_disconnect(rdpShadowSubsystem* subsystem, rdpShadowClient* client)
{
    pthread_mutex_lock(&lock);
    stop_audio = 1;
    audio_client = NULL;
    pthread_mutex_unlock(&lock);
    if (audio_thread_started)
    {
        pthread_join(audio_thread, NULL);
        audio_thread_started = 0;
    }
    logev("client-disconnected");
    if (orig_disconnect) orig_disconnect(subsystem, client);
}

static rdpShadowSubsystem* my_new(void)
{
    rdpShadowSubsystem* subsystem = orig_new();
    if (!subsystem) return NULL;
    /* The Debian X11 shadow backend has no host-audio capture source and therefore
     * supplies no rdpsnd formats.  This fixture generates its own PCM samples. */
    if (!subsystem->nRdpsndFormats)
    {
        AUDIO_FORMAT* format = calloc(1, sizeof(*format));
        if (!format) return NULL;
        format->wFormatTag = WAVE_FORMAT_PCM;
        format->nChannels = 2;
        format->nSamplesPerSec = 44100;
        format->wBitsPerSample = 16;
        format->nBlockAlign = 4;
        format->nAvgBytesPerSec = 176400;
        subsystem->rdpsndFormats = format;
        subsystem->nRdpsndFormats = 1;
    }
    orig_connect = subsystem->ClientConnect;
    orig_disconnect = subsystem->ClientDisconnect;
    subsystem->ClientConnect = my_connect;
    subsystem->ClientDisconnect = my_disconnect;
    logev("server-formats %zu", subsystem->nRdpsndFormats);
    for (size_t i = 0; i < subsystem->nRdpsndFormats; i++)
        log_format("server", i, &subsystem->rdpsndFormats[i]);
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
    server = shadow_server_new();
    if (!server) return 1;
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
