/* Reproduces the genuine mstsc "Show Options" expansion (EXP-042):
 * a dialog without WS_CLIPCHILDREN is grown in steps by SetWindowPos from a second
 * thread (SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_NOSENDCHANGING); its
 * WM_WINDOWPOSCHANGED handler moves a bottom button with SWP_NOSIZE|SWP_NOZORDER.
 * Afterwards a large child panel is hidden and another one shown.  The button must
 * still be visible: prints "BUTTON visible" or "BUTTON blank" and exits 0/1. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static HWND dlg, button, panel, panel2;
static int steps[] = { 300, 370, 443, 477, 493, 494 };

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_WINDOWPOSCHANGED && hwnd == dlg && button)
    {
        RECT rc; GetClientRect(hwnd, &rc);
        SetWindowPos(button, 0, 242, rc.bottom - 31, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static int button_pixels(int *total)
{
    RECT r; GetWindowRect(button, &r); MapWindowPoints(0, dlg, (POINT *)&r, 2);
    HDC hdc = GetDC(dlg);
    COLORREF bg = GetPixel(hdc, r.left - 3, r.top + 5);
    int other = 0; *total = 0;
    for (int y = r.top + 1; y < r.bottom - 1; y++)
        for (int x = r.left + 1; x < r.right - 1; x++, (*total)++)
            if (GetPixel(hdc, x, y) != bg) other++;
    ReleaseDC(dlg, hdc);
    return other;
}

static void pump(DWORD ms)
{
    DWORD end = GetTickCount() + ms; MSG msg;
    do
    {
        while (PeekMessageW(&msg, 0, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
        if (ms) Sleep(10);
    } while (GetTickCount() < end);
}

static DWORD WINAPI grow(void *arg)
{
    for (int i = 0; i < ARRAYSIZE(steps); i++)
    {
        SetWindowPos(dlg, 0, 0, 0, 411, steps[i], SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE |
                     (i < ARRAYSIZE(steps) - 1 ? SWP_NOSENDCHANGING : 0));
        if (arg) pump(15); else Sleep(15);
        if (getenv("STEPLOG")) { int tot, n = button_pixels(&tot); RECT u;
            printf("step %d h=%d button pixels %d/%d pending %d\n", i, steps[i], n, tot, GetUpdateRect(button, &u, FALSE)); }
    }
    return 0;
}

int main(void)
{
    WNDCLASSW wc = { 0, wndproc, 0, 0, GetModuleHandleW(0), 0, LoadCursorW(0, (LPCWSTR)IDC_ARROW),
                     (HBRUSH)(COLOR_BTNFACE + 1), 0, L"expand_dlg" };
    RegisterClassW(&wc);
    dlg = CreateWindowExW(0, L"expand_dlg", L"expand", WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_VISIBLE,
                          100, 100, 411, 268, 0, 0, 0, 0);
    panel = CreateWindowExW(0, L"static", L"collapsed", WS_CHILD | WS_VISIBLE, 6, 81, 392, 120, dlg, 0, 0, 0);
    panel2 = CreateWindowExW(0, L"static", L"expanded", WS_CHILD, 6, 81, 392, 341, dlg, 0, 0, 0);
    button = CreateWindowExW(0, L"button", L"Connect", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 242, 205, 75, 23, dlg, 0, 0, 0);
    SetWindowPos(dlg, 0, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_FRAMECHANGED);
    pump(500);
    if (getenv("STEPLOG")) { int tot, n = button_pixels(&tot); printf("initial button pixels %d/%d\n", n, tot); }

    if (getenv("SAME_THREAD")) grow(getenv("PUMP") ? (void *)1 : NULL);
    else
    {
        HANDLE t = CreateThread(0, 0, grow, 0, 0, 0);
        while (MsgWaitForMultipleObjects(1, &t, FALSE, INFINITE, QS_ALLINPUT) != WAIT_OBJECT_0) pump(0);
    }
    if (getenv("CHECK_BEFORE_HIDE")) pump(800);
    else if (!getenv("NO_HIDE"))
    {
        ShowWindow(panel, SW_HIDE);
        ShowWindow(panel2, SW_SHOW);
    }
    pump(800);

    /* the button face is drawn: its rectangle must contain more than the dialog background */
    int total, other = button_pixels(&total);
    RECT r; GetWindowRect(button, &r); MapWindowPoints(0, dlg, (POINT *)&r, 2);
    RECT u; BOOL pending = GetUpdateRect(button, &u, FALSE);
    printf("button at (%ld,%ld) non-background pixels %d/%d update pending %d\n", r.left, r.top, other, total, pending);
    printf(other > total / 20 ? "BUTTON visible\n" : "BUTTON blank\n");
    DestroyWindow(dlg);
    return other > total / 20 ? 0 : 1;
}
