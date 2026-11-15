/* Shows CredUIPromptForWindowsCredentialsW as the Remote Desktop client does (caption
 * "Enter your credentials", save check box) and prints what the caller gets back:
 *   USER <name>   user name from the packed buffer, unpacked without a domain buffer as mstsc does
 *   SAVE <0|1>    state of the "Remember" check box
 * A user name typed without a domain must come back unchanged (EXP-035). */
#include <windows.h>
#include <wincred.h>
#include <stdio.h>

#ifndef CREDUIWIN_CHECKBOX
#define CREDUIWIN_CHECKBOX 0x2
#endif

int main(void)
{
    CREDUI_INFOW info = { sizeof(info), NULL, L"Fixture: these credentials are not used.", L"Enter your credentials", NULL };
    WCHAR user[256], pass[256];
    DWORD lu = 256, lp = 256, ret;
    ULONG package = 0, size = 0;
    void *out = NULL;
    BOOL save = FALSE;

    ret = CredUIPromptForWindowsCredentialsW( &info, 0, &package, NULL, 0, &out, &size, &save, CREDUIWIN_CHECKBOX );
    if (ret) { printf("FAIL prompt %lu\n", ret); return 1; }
    if (!CredUnPackAuthenticationBufferW( 0, out, size, user, &lu, NULL, NULL, pass, &lp ))
    { printf("FAIL unpack %lu\n", GetLastError()); return 1; }
    printf("USER %ls\nSAVE %d\n", user, save);
    SecureZeroMemory( pass, sizeof(pass) );
    CoTaskMemFree( out );
    return 0;
}
