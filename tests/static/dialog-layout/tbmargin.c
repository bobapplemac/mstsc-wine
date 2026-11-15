/* mstsc's "Show Options" expander with comctl32 v6 (EXP-046): a TBSTYLE_LIST |
 * TBSTYLE_TRANSPARENT toolbar (not TBSTYLE_FLAT) as tall as its 23-pixel button.  On Windows
 * the button, and so its hot-tracking frame, fills the toolbar; Wine put it 2 pixels down
 * (the comctl32 v5 top margin), so the bottom of the frame was cut off.
 * Prints "BUTTON FITS" (exit 0) or "BUTTON CLIPPED" (exit 1).  Needs the v6 manifest. */
#include <windows.h>
#include <commctrl.h>
#include <stdio.h>

int main(void)
{
    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_BAR_CLASSES };
    InitCommonControlsEx(&icc);
    HWND parent = CreateWindowExW(0, L"static", L"", WS_POPUP | WS_VISIBLE, 50, 50, 300, 60, 0, 0, 0, 0);
    HWND tb = CreateWindowExW(0, TOOLBARCLASSNAMEW, L"Expando", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS |
                              TBSTYLE_LIST | TBSTYLE_TRANSPARENT | CCS_NORESIZE | CCS_NODIVIDER | CCS_NOPARENTALIGN,
                              10, 10, 135, 23, parent, (HMENU)5017, 0, 0);
    HIMAGELIST il = ImageList_Create(21, 17, ILC_COLOR32, 1, 1);
    SendMessageW(tb, TB_BUTTONSTRUCTSIZE, sizeof(TBBUTTON), 0);
    SendMessageW(tb, TB_SETPADDING, 0, MAKELPARAM(0, 6));
    SendMessageW(tb, TB_SETIMAGELIST, 0, (LPARAM)il);
    TBBUTTON b = { 0, 5018, TBSTATE_ENABLED, BTNS_AUTOSIZE | BTNS_SHOWTEXT, {0}, 0, (INT_PTR)L"Show &Options " };
    SendMessageW(tb, TB_ADDBUTTONSW, 1, (LPARAM)&b);
    SendMessageW(tb, TB_SETBUTTONSIZE, 0, MAKELPARAM(135, 23));
    RECT item, client;
    SendMessageW(tb, TB_GETITEMRECT, 0, (LPARAM)&item);
    GetClientRect(tb, &client);
    printf("toolbar version %ld, client %ldx%ld, button (%ld,%ld)-(%ld,%ld)\n",
           (long)SendMessageW(tb, CCM_GETVERSION, 0, 0), client.right, client.bottom,
           item.left, item.top, item.right, item.bottom);
    BOOL fits = item.top >= 0 && item.bottom <= client.bottom;
    printf(fits ? "BUTTON FITS\n" : "BUTTON CLIPPED\n");
    DestroyWindow(parent);
    return fits ? 0 : 1;
}
