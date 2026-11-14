/* Fullscreen -> windowed transition, as mstsc does when "Restore" is clicked on the
 * connection bar.  Prints phase markers; run.sh checks the X pointer grab in each phase.
 *   fsclip.exe [SECONDS_PER_PHASE]  */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static void pump(DWORD ms)
{
    DWORD end = GetTickCount() + ms;
    MSG msg;
    while ((LONG)(end - GetTickCount()) > 0)
    {
        MsgWaitForMultipleObjects(0, NULL, FALSE, 50, QS_ALLINPUT);
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    }
}

int main(int argc, char **argv)
{
    DWORD phase = (argc > 1 ? atoi(argv[1]) : 4) * 1000;
    int cx = GetSystemMetrics(SM_CXSCREEN), cy = GetSystemMetrics(SM_CYSCREEN);
    WNDCLASSW wc = {0};
    RECT clip;
    HWND hwnd;

    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.hbrBackground = GetStockObject(GRAY_BRUSH);
    wc.lpszClassName = L"fsclip";
    RegisterClassW(&wc);

    /* fullscreen: borderless popup covering the monitor */
    hwnd = CreateWindowExW(0, L"fsclip", L"fsclip", WS_POPUP | WS_VISIBLE, 0, 0, cx, cy,
                           NULL, NULL, wc.hInstance, NULL);
    SetForegroundWindow(hwnd);
    pump(1500);  /* win32u ignores fullscreen clipping requests for 1s after a reset */
    /* a click activates fullscreen clipping, as when the user clicks into the session */
    SetCursorPos(cx / 2, cy / 2);
    mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
    mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
    pump(500);
    GetClipCursor(&clip);
    printf("FULLSCREEN %dx%d clip %ld,%ld-%ld,%ld\n", cx, cy, clip.left, clip.top, clip.right, clip.bottom);
    fflush(stdout);
    pump(phase);

    /* restore: becomes a normal overlapped window, still visible and foreground */
    SetWindowLongW(hwnd, GWL_STYLE, WS_OVERLAPPEDWINDOW | WS_VISIBLE);
    SetWindowPos(hwnd, HWND_TOP, 40, 40, cx / 2, cy / 2, SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    pump(500);
    GetClipCursor(&clip);
    printf("WINDOWED clip %ld,%ld-%ld,%ld foreground %d\n", clip.left, clip.top, clip.right, clip.bottom,
           GetForegroundWindow() == hwnd);
    fflush(stdout);
    pump(phase);

    /* an application's own clip rectangle must survive the same transition */
    SetWindowLongW(hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
    SetWindowPos(hwnd, HWND_TOP, 0, 0, cx, cy, SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    pump(500);
    SetRect(&clip, 10, 10, cx / 2, cy / 2);
    ClipCursor(&clip);
    SetWindowLongW(hwnd, GWL_STYLE, WS_OVERLAPPEDWINDOW | WS_VISIBLE);
    SetWindowPos(hwnd, HWND_TOP, 40, 40, cx / 2, cy / 2, SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    pump(500);
    GetClipCursor(&clip);
    printf("APPCLIP clip %ld,%ld-%ld,%ld\n", clip.left, clip.top, clip.right, clip.bottom);
    fflush(stdout);
    pump(phase);
    ClipCursor(NULL);
    DestroyWindow(hwnd);
    printf("DONE\n");
    return 0;
}
