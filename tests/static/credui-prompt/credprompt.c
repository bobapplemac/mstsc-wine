/* Shows CredUIPromptForWindowsCredentialsW as the Remote Desktop client does (caption
 * "Enter your credentials", save check box) and prints what the caller gets back:
 *   USER <name>   user name from the packed buffer, unpacked without a domain buffer as mstsc does
 *   SAVE <0|1>    state of the "Remember" check box
 *   MESSAGE <FITS|CLIPPED>  whether the dialog shows the whole message text
 * "credprompt reprompt" asks again after a failed logon, as mstsc does: it passes the old
 * user name and password back with the error, prints PASSWORD <EMPTY|FILLED> for the
 * password field (Windows leaves it empty, EXP-039) and cancels the dialog.
 * A user name typed without a domain must come back unchanged (EXP-035). The message is
 * mstsc's re-prompt text for a long host name; the dialog must show all of it, wrapped,
 * without covering the fields below it (EXP-039). */
#include <windows.h>
#include <wincred.h>
#include <stdio.h>
#include <wchar.h>

#ifndef SEC_E_LOGON_DENIED
#define SEC_E_LOGON_DENIED ((LONG)0x8009030C)
#endif

#ifndef CREDUIWIN_CHECKBOX
#define CREDUIWIN_CHECKBOX 0x2
#endif

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define IDC_MESSAGE  103   /* credui's classic dialog */
#define IDC_USERNAME 101
#define IDC_PASSWORD 102

static const WCHAR caption[] = L"Enter your credentials";

/* Find the dialog, then compare the text the message control needs with its size. */
static DWORD WINAPI measure( void *arg )
{
    BOOL reprompt = arg != NULL;
    HWND dlg = NULL, msg, user, ok;
    RECT rc, need, rmsg, ruser, rok, rdlg;
    WCHAR text[1024];
    HFONT old;
    HDC dc;
    int i, fits;

    for (i = 0; i < 300 && !(dlg = FindWindowW( NULL, caption )); i++) Sleep( 100 );
    if (!dlg || !(msg = GetDlgItem( dlg, IDC_MESSAGE ))) { printf("MESSAGE NODIALOG\n"); return 0; }
    user = GetDlgItem( dlg, IDC_USERNAME );
    ok = GetDlgItem( dlg, IDOK );
    GetWindowTextW( msg, text, ARRAY_SIZE(text) );
    GetClientRect( msg, &rc );
    need = rc;
    dc = GetDC( msg );
    old = SelectObject( dc, (HFONT)SendMessageW( msg, WM_GETFONT, 0, 0 ) );
    DrawTextW( dc, text, -1, &need, DT_CALCRECT | DT_WORDBREAK | DT_EXPANDTABS );
    SelectObject( dc, old );
    ReleaseDC( msg, dc );
    GetWindowRect( msg, &rmsg );
    GetWindowRect( user, &ruser );
    GetWindowRect( ok, &rok );
    GetClientRect( dlg, &rdlg );
    MapWindowPoints( dlg, NULL, (POINT *)&rdlg, 2 );
    fits = need.bottom <= rc.bottom && need.right <= rc.right && rmsg.bottom <= ruser.top &&
           rok.bottom <= rdlg.bottom;
    printf("MESSAGE %s\n", fits ? "FITS" : "CLIPPED");
    if (!fits) printf("# need %ldx%ld, have %ldx%ld; message bottom %ld, user top %ld; ok bottom %ld, dialog bottom %ld\n",
                      need.right, need.bottom, rc.right, rc.bottom, rmsg.bottom, ruser.top, rok.bottom, rdlg.bottom);
    if (reprompt)
    {
        printf("PASSWORD %s\n", GetWindowTextLengthW( GetDlgItem( dlg, IDC_PASSWORD ) ) ? "FILLED" : "EMPTY");
        PostMessageW( dlg, WM_COMMAND, IDCANCEL, 0 );
    }
    fflush( stdout );
    return 0;
}

int wmain(int argc, WCHAR **argv)
{
    BOOL reprompt = argc > 1 && !wcscmp( argv[1], L"reprompt" );
    CREDUI_INFOW info = { sizeof(info), NULL,
        L"The credentials that were used to connect to rdp-gateway-01.branch-office.example.com did not work. Please enter new credentials.",
        caption, NULL };
    HANDLE thread = CreateThread( NULL, 0, measure, reprompt ? (void *)1 : NULL, 0, NULL );
    BYTE in[1024];
    DWORD in_size = sizeof(in);
    WCHAR user[256], pass[256];
    DWORD lu = 256, lp = 256, ret;
    ULONG package = 0, size = 0;
    void *out = NULL;
    BOOL save = FALSE;

    if (reprompt)
    {
        if (!CredPackAuthenticationBufferW( 0, (WCHAR *)L"Administrator", (WCHAR *)L"old-pass-1", in, &in_size ))
        { printf("FAIL pack %lu\n", GetLastError()); return 1; }
        ret = CredUIPromptForWindowsCredentialsW( &info, SEC_E_LOGON_DENIED, &package, in, in_size, &out, &size,
                                                  &save, CREDUIWIN_CHECKBOX );
        WaitForSingleObject( thread, 5000 );
        printf("REPROMPT %lu\n", ret);
        return 0;
    }
    ret = CredUIPromptForWindowsCredentialsW( &info, 0, &package, NULL, 0, &out, &size, &save, CREDUIWIN_CHECKBOX );
    if (ret) { printf("FAIL prompt %lu\n", ret); return 1; }
    if (!CredUnPackAuthenticationBufferW( 0, out, size, user, &lu, NULL, NULL, pass, &lp ))
    { printf("FAIL unpack %lu\n", GetLastError()); return 1; }
    WaitForSingleObject( thread, 5000 );
    printf("USER %ls\nSAVE %d\n", user, save);
    SecureZeroMemory( pass, sizeof(pass) );
    CoTaskMemFree( out );
    return 0;
}
