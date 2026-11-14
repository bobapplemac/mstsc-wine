/* .mun (SystemResources) regression test.
 * Exit 0 when FindResourceW finds IMAGE #200, which exists only in
 * %windir%\SystemResources\<exe name>.mun, with the expected contents
 * (and, with "expect-missing", when it is NOT found). */
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    static const char expect[] = "mun image payload";
    int expect_missing = argc > 1 && !strcmp(argv[1], "expect-missing");
    HRSRC rsrc = FindResourceW(NULL, MAKEINTRESOURCEW(200), L"IMAGE");
    HGLOBAL h = rsrc ? LoadResource(NULL, rsrc) : NULL;
    const void *data = h ? LockResource(h) : NULL;
    DWORD size = rsrc ? SizeofResource(NULL, rsrc) : 0;

    printf("FindResource=%p data=%p size=%lu\n", rsrc, data, size);
    if (expect_missing) return rsrc ? 1 : 0;
    if (data && size >= sizeof(expect) - 1 && !memcmp(data, expect, sizeof(expect) - 1)) { printf("PASS\n"); return 0; }
    printf("FAIL\n");
    return 1;
}
