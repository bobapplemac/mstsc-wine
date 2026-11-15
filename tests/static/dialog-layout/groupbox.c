/* Themed group box caption (EXP-047): on Windows the frame line stops 2-3 pixels before and
 * after the caption ("Logon settings"); Wine ran it up to the text.  Draws a v6 group box with
 * a non-antialiased MS Shell Dlg caption and measures the gaps on the frame's top line.
 * Prints "GAP OK" (exit 0) or "GAP TOO SMALL" (exit 1).  Needs the v6 manifest and theming. */
#include <windows.h>
#include <commctrl.h>
#include <uxtheme.h>
#include <stdio.h>
#include <stdlib.h>

static int lum(COLORREF c) { return (GetRValue(c) + GetGValue(c) + GetBValue(c)) / 3; }

int main(int argc, char **argv)
{
    if (argc > 1) AddFontResourceExA(argv[1], FR_PRIVATE, 0);
    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_STANDARD_CLASSES };
    InitCommonControlsEx(&icc);
    if (!IsThemeActive()) { printf("SKIP visual styles are off\n"); return 0; }
    HWND parent = CreateWindowExW(0, L"static", L"", WS_POPUP | WS_VISIBLE, 50, 50, 300, 120, 0, 0, 0, 0);
    HWND gb = CreateWindowExW(0, L"button", L"Logon settings", WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
                              10, 10, 250, 80, parent, 0, 0, 0);
    LOGFONTW lf = { -11 };
    if (getenv("GBAA")) lf.lfQuality = DEFAULT_QUALITY; else lf.lfQuality = NONANTIALIASED_QUALITY;
    lstrcpyW(lf.lfFaceName, argc > 1 ? L"Microsoft Sans Serif" : L"MS Shell Dlg");
    SendMessageW(gb, WM_SETFONT, (WPARAM)CreateFontIndirectW(&lf), TRUE);
    RedrawWindow(gb, 0, 0, RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW);

    HDC hdc = GetDC(gb);
    /* the top line: the row where the far right of the box is a horizontal run of one colour
     * that differs from the rows above and below */
    int line = -1;
    for (int y = 1; y < 20 && line < 0; y++)
    {
        COLORREF c = GetPixel(hdc, 200, y);
        BOOL run = TRUE;
        for (int x = 200; x < 240; x++) if (GetPixel(hdc, x, y) != c) run = FALSE;
        if (run && c != GetPixel(hdc, 200, y - 1) && c != GetPixel(hdc, 200, y + 1)) line = y;
    }
    COLORREF line_c = line >= 0 ? GetPixel(hdc, 220, line) : 0;
    /* caption ink: dark columns in the caption rows */
    int first = -1, last = -1;
    for (int x = 0; x < 250; x++)
        for (int y = 0; y < 16; y++)
            if (lum(GetPixel(hdc, x, y)) < 100) { if (first < 0) first = x; last = x; break; }
    int left_end = -1, right_start = -1;
    for (int x = first - 1; x >= 0 && line >= 0; x--) if (GetPixel(hdc, x, line) == line_c) { left_end = x; break; }
    for (int x = last + 1; x < 250 && line >= 0; x++) if (GetPixel(hdc, x, line) == line_c) { right_start = x; break; }
    if (getenv("GBDEBUG"))
        for (int y = 0; y < 16; y++)
        {
            for (int x = 0; x < 100; x++)
            {
                COLORREF c = GetPixel(hdc, x, y);
                putchar(c == line_c ? '-' : lum(c) < 100 ? '#' : lum(c) < 230 ? '+' : '.');
            }
            putchar('\n');
        }
    ReleaseDC(gb, hdc);
    int gap_left = first - left_end - 1, gap_right = right_start - last - 1;
    printf("line row %d, caption ink %d..%d, line ends %d / starts %d, gaps %d / %d\n",
           line, first, last, left_end, right_start, gap_left, gap_right);
    BOOL ok = line >= 0 && first > 0 && gap_left >= 2 && gap_right >= 2;
    printf(ok ? "GAP OK\n" : "GAP TOO SMALL\n");
    DestroyWindow(parent);
    return ok ? 0 : 1;
}
