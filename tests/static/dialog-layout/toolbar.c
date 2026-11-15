/* mstsc's "Show Options" expander (EXP-042): a TBSTYLE_LIST toolbar with TB_SETPADDING
 * cx = 0 and one BTNS_AUTOSIZE button with a 21x17 bitmap and text.  The button is sized
 * for its text, so the text must be drawn in full, not cut off with an ellipsis.
 * Draws the button twice (autosized, then 200 pixels wide) and compares the text ink.
 * Prints "TEXT FULL" (exit 0) or "TEXT CUT" (exit 1). */
#include <windows.h>
#include <commctrl.h>
#include <stdio.h>
#include <stdlib.h>

static HWND make_toolbar(HWND parent, int cx)
{
    HWND tb = CreateWindowExW(0, TOOLBARCLASSNAMEW, L"Expando", WS_CHILD | WS_VISIBLE | TBSTYLE_LIST |
                              CCS_NORESIZE | CCS_NODIVIDER | CCS_NOPARENTALIGN,
                              10, 10, 300, 23, parent, (HMENU)5017, 0, 0);
    HIMAGELIST il = ImageList_Create(21, 17, ILC_COLOR32, 1, 1);
    HDC hdc = GetDC(0), mem = CreateCompatibleDC(hdc);
    HBITMAP bmp = CreateCompatibleBitmap(hdc, 21, 17);
    HGDIOBJ old = SelectObject(mem, bmp);
    RECT r = { 0, 0, 21, 17 };
    FillRect(mem, &r, GetStockObject(WHITE_BRUSH));
    SelectObject(mem, old); DeleteDC(mem); ReleaseDC(0, hdc);
    ImageList_Add(il, bmp, 0);
    /* MS Shell Dlg 8pt as in mstsc, without antialiasing so both drawings compare exactly */
    LOGFONTW lf = { -11 };
    lf.lfQuality = NONANTIALIASED_QUALITY;
    lstrcpyW(lf.lfFaceName, L"MS Shell Dlg");
    SendMessageW(tb, WM_SETFONT, (WPARAM)CreateFontIndirectW(&lf), 0);
    SendMessageW(tb, TB_BUTTONSTRUCTSIZE, sizeof(TBBUTTON), 0);
    SendMessageW(tb, TB_SETPADDING, 0, MAKELPARAM(0, 6));
    SendMessageW(tb, TB_SETIMAGELIST, 0, (LPARAM)il);
    TBBUTTON b = { 0, 5018, TBSTATE_ENABLED, BTNS_AUTOSIZE | BTNS_SHOWTEXT, {0}, 0, (INT_PTR)L"Show &Options " };
    SendMessageW(tb, TB_ADDBUTTONSW, 1, (LPARAM)&b);
    if (cx)
    {
        TBBUTTONINFOW info = { sizeof(info), TBIF_SIZE };
        info.cx = cx;
        SendMessageW(tb, TB_SETBUTTONINFOW, 5018, (LPARAM)&info);
    }
    return tb;
}

/* dark enough to be part of a glyph; repaints of the transparent toolbar change the
 * antialiasing intensity, not which pixels are ink */
static int ink(COLORREF c)
{
    return GetRValue(c) + GetGValue(c) + GetBValue(c) < 3 * 128;
}

static void capture(HWND tb, COLORREF *px, int w, int h)
{
    RedrawWindow(tb, 0, 0, RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW);
    HDC hdc = GetDC(tb);
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) px[y * w + x] = GetPixel(hdc, x, y);
    ReleaseDC(tb, hdc);
}

int main(void)
{
    static COLORREF a[300 * 23], b[300 * 23];
    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_BAR_CLASSES };
    InitCommonControlsEx(&icc);
    HWND parent = CreateWindowExW(0, L"static", L"", WS_POPUP | WS_VISIBLE, 50, 50, 340, 60, 0, 0, 0, 0);
    HWND tb = make_toolbar(parent, 0);
    RECT r; SendMessageW(tb, TB_GETITEMRECT, 0, (LPARAM)&r);
    capture(tb, a, 300, 23);
    DestroyWindow(tb);
    tb = make_toolbar(parent, 200);
    capture(tb, b, 300, 23);
    /* compare the autosized button's text area (right of the bitmap) */
    int diff = 0;
    for (int y = r.top; y < r.bottom && y < 23; y++)
        for (int x = 2 + 21; x < r.right - 2; x++) if (ink(a[y * 300 + x]) != ink(b[y * 300 + x]))
        {
            if (getenv("TBDEBUG") && diff < 10) printf("diff at %d,%d %06lx %06lx\n", x, y, a[y * 300 + x], b[y * 300 + x]);
            diff++;
        }
    if (getenv("TBDEBUG"))
        for (int y = 0; y < 23; y++)
        {
            for (int x = 0; x < 110; x++) putchar(ink(a[y * 300 + x]) ? '#' : '.');
            putchar(' ');
            for (int x = 0; x < 110; x++) putchar(ink(b[y * 300 + x]) ? '#' : '.');
            putchar('\n');
        }
    printf("autosized button %ld..%ld, differing text ink pixels %d\n", r.left, r.right, diff);
    printf(diff ? "TEXT CUT\n" : "TEXT FULL\n");
    DestroyWindow(parent);
    return diff ? 1 : 0;
}
