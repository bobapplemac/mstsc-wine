#include <windows.h>
#include <evntrace.h>
#include <stdio.h>

static const GUID provider =
    {0x12345678, 0x1234, 0x5678, {0x90, 0xab, 0xcd, 0xef, 0x01, 0x02, 0x03, 0x04}};

static ULONG WINAPI control_callback(WMIDPREQUESTCODE code, void *context, ULONG *size,
                                     void *buffer)
{
    TRACEHANDLE handle = GetTraceLoggerHandle(buffer);

    printf("CALLBACK code=%u handle=%llx flags=%lx level=%u\n", code,
           (unsigned long long)handle, GetTraceEnableFlags(handle),
           GetTraceEnableLevel(handle));
    return ERROR_SUCCESS;
}

int main(void)
{
    TRACEHANDLE registration;
    DWORD value = 0x80004005;

    if (RegisterTraceGuidsW(control_callback, NULL, &provider, 0, NULL, NULL, NULL,
                            &registration) != ERROR_SUCCESS)
        return 1;
    TraceMessage(registration, TRACE_MESSAGE_GUID | TRACE_MESSAGE_SEQUENCE, &provider, 42,
                 &value, sizeof(value), NULL, 0);
    return 0;
}
