#include <windows.h>
#include <mmreg.h>
#include <msacm.h>
#include <stdio.h>

#ifndef WAVE_FORMAT_MPEG4_AAC
#define WAVE_FORMAT_MPEG4_AAC 0xa106
#endif

struct state
{
    unsigned int pcm_drivers;
    unsigned int false_accepts;
};

static BOOL CALLBACK check_driver(HACMDRIVERID id, DWORD_PTR instance, DWORD support)
{
    struct state *state = (struct state *)instance;
    ACMDRIVERDETAILSW details = {0};
    WAVEFORMATEX src = {0}, dst = {0};
    HACMDRIVER driver;
    HACMSTREAM stream = NULL;
    MMRESULT result;

    details.cbStruct = sizeof(details);
    if (acmDriverDetailsW(id, &details, 0) != MMSYSERR_NOERROR ||
        details.wMid != MM_MICROSOFT || details.wPid != MM_MSFT_ACM_PCM)
        return TRUE;
    if (acmDriverOpen(&driver, id, 0) != MMSYSERR_NOERROR)
        return TRUE;

    state->pcm_drivers++;
    src.wFormatTag = WAVE_FORMAT_MPEG4_AAC;
    src.nChannels = 2;
    src.nSamplesPerSec = 44100;
    src.nAvgBytesPerSec = 24000;
    src.nBlockAlign = 4;
    src.wBitsPerSample = 16;
    dst.wFormatTag = WAVE_FORMAT_PCM;
    dst.nChannels = 2;
    dst.nSamplesPerSec = 44100;
    dst.nAvgBytesPerSec = 176400;
    dst.nBlockAlign = 4;
    dst.wBitsPerSample = 16;

    result = acmStreamOpen(&stream, driver, &src, &dst, NULL, 0, 0,
                           ACM_STREAMOPENF_QUERY);
    printf("PCM_QUERY result=%u\n", result);
    if (result == MMSYSERR_NOERROR)
        state->false_accepts++;
    acmDriverClose(driver, 0);
    return TRUE;
}

int main(void)
{
    struct state state = {0};

    if (acmDriverEnum(check_driver, (DWORD_PTR)&state, 0) != MMSYSERR_NOERROR)
        return 2;
    printf("PCM_DRIVERS=%u FALSE_ACCEPTS=%u\n", state.pcm_drivers,
           state.false_accepts);
    return state.pcm_drivers == 1 && state.false_accepts == 0 ? 0 : 1;
}
