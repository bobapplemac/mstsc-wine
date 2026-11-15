/* credseed TARGET USER PASSWORD: store a saved Remote Desktop credential as mstsc does after
 * "Remember my password" (CredWriteW, CRED_TYPE_DOMAIN_PASSWORD, CRED_PERSIST_LOCAL_MACHINE).
 * Test accounts only. */
#include <windows.h>
#include <wincred.h>
#include <stdio.h>
int wmain(int argc, WCHAR **argv)
{
    CREDENTIALW c = {0};
    if (argc < 4) return 2;
    c.Type = CRED_TYPE_DOMAIN_PASSWORD;
    c.TargetName = argv[1];
    c.UserName = argv[2];
    c.CredentialBlob = (BYTE *)argv[3];
    c.CredentialBlobSize = lstrlenW(argv[3]) * sizeof(WCHAR);
    c.Persist = CRED_PERSIST_LOCAL_MACHINE;
    if (!CredWriteW(&c, 0)) { printf("CredWriteW failed %lu\n", GetLastError()); return 1; }
    printf("SEEDED\n");
    return 0;
}
