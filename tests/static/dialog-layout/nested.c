/* mstsc's General tab (EXP-045): a property page with EnableThemeDialogTexture(ETDT_ENABLETAB)
 * holds a nested DS_CONTROL child dialog ("Credentials") with themed controls, so comctl32 marks
 * it ETDT_ENABLE.  On Windows Server 2022 the nested dialog shows the page's tab texture (white),
 * not the plain dialog colour.  Compares the background of both and the brush the nested dialog
 * gives its static control.  Prints "NESTED TEXTURED" (exit 0) or "NESTED PLAIN" (exit 1).
 * Runs on Windows too (needs visual styles on). */
#include <windows.h>
#include <commctrl.h>
#include <uxtheme.h>
#include <stdio.h>

static INT_PTR CALLBACK dlgproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    return msg == WM_INITDIALOG;
}

static HWND make_dialog(HWND parent, DWORD style, int x, int y, int cx, int cy)
{
    struct { DLGTEMPLATE t; WORD menu, cls, title; } tpl = {{ style, 0, 0, x, y, cx, cy }};
    return CreateDialogIndirectParamW(GetModuleHandleW(0), &tpl.t, parent, dlgproc, 0);
}

static void pump(DWORD ms)
{
    DWORD end = GetTickCount() + ms; MSG msg;
    do { while (PeekMessageW(&msg, 0, 0, 0, PM_REMOVE)) DispatchMessageW(&msg); Sleep(10); }
    while (GetTickCount() < end);
}

int main(void)
{
    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_STANDARD_CLASSES };
    InitCommonControlsEx(&icc);
    if (!IsThemeActive()) { printf("SKIP visual styles are off\n"); return 0; }

    HWND top = make_dialog(0, WS_POPUP | WS_CAPTION | WS_VISIBLE | DS_SETFONT, 20, 20, 260, 200);
    HWND page = make_dialog(top, WS_CHILD | WS_VISIBLE | DS_CONTROL, 5, 5, 250, 190);
    EnableThemeDialogTexture(page, ETDT_ENABLETAB);
    CreateWindowExW(0, L"button", L"Save", WS_CHILD | WS_VISIBLE, 10, 250, 80, 24, page, 0, 0, 0);
    HWND nested = make_dialog(page, WS_CHILD | WS_VISIBLE | DS_CONTROL, 30, 20, 200, 80);
    HWND label = CreateWindowExW(0, L"static", L"User name:", WS_CHILD | WS_VISIBLE, 5, 5, 80, 16, nested, 0, 0, 0);
    CreateWindowExW(0, L"button", L"Always ask", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 5, 60, 150, 18, nested, 0, 0, 0);
    pump(300);
    RedrawWindow(top, 0, 0, RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW);
    pump(500);

    POINT in_page = { 10, 10 }, in_nested = { 150, 90 };
    MapWindowPoints(nested, page, &in_nested, 1);
    HDC hdc = GetDC(page);
    COLORREF page_px = GetPixel(hdc, in_page.x, in_page.y), nested_px = GetPixel(hdc, in_nested.x, in_nested.y);
    ReleaseDC(page, hdc);

    HDC lhdc = GetDC(label);
    HBRUSH page_brush = (HBRUSH)SendMessageW(page, WM_CTLCOLORSTATIC, (WPARAM)lhdc, (LPARAM)label);
    HBRUSH nested_brush = (HBRUSH)SendMessageW(nested, WM_CTLCOLORSTATIC, (WPARAM)lhdc, (LPARAM)label);
    ReleaseDC(label, lhdc);

    {
        HDC mem = CreateCompatibleDC(0); HBITMAP bmp = CreateCompatibleBitmap(GetDC(0), 4, 4);
        RECT r = { 0, 0, 4, 4 }; SelectObject(mem, bmp); FillRect(mem, &r, page_brush);
        printf("page brush colour %06lx (brush %s)\n", GetPixel(mem, 1, 1),
               page_brush == GetSysColorBrush(COLOR_BTNFACE) ? "COLOR_BTNFACE" : "texture");
        DeleteDC(mem); DeleteObject(bmp);
        HDC t = GetDC(page);
        printf("page pixels:"); for (int y = 5; y < 200; y += 40) printf(" %06lx", GetPixel(t, 100, y)); printf("\n");
        ReleaseDC(page, t);
    }
    printf("page texture %d nested texture %d\n", IsThemeDialogTextureEnabled(page), IsThemeDialogTextureEnabled(nested));
    printf("page background %06lx, nested background %06lx, COLOR_BTNFACE %06lx\n",
           page_px, nested_px, GetSysColor(COLOR_BTNFACE));
    printf("nested WM_CTLCOLORSTATIC brush %s\n", nested_brush == GetSysColorBrush(COLOR_BTNFACE) ? "COLOR_BTNFACE" :
           nested_brush == page_brush ? "same as page" : "other");
    BOOL ok = nested_px == page_px && nested_brush != GetSysColorBrush(COLOR_BTNFACE);
    printf(ok ? "NESTED TEXTURED\n" : "NESTED PLAIN\n");
    DestroyWindow(top);
    return ok ? 0 : 1;
}
