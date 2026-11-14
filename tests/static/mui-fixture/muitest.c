/* MUI satellite resource regression test.
 * Exit 0 when LoadStringW finds the string that only exists in en-US\muitest.exe.mui
 * (and, with "expect-missing", when it is NOT found). */
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    WCHAR buf[128];
    int expect_missing = argc > 1 && !strcmp(argv[1], "expect-missing");
    int len = LoadStringW(NULL, 100, buf, ARRAYSIZE(buf));
    HRSRC rsrc = FindResourceW(NULL, MAKEINTRESOURCEW(100 / 16 + 1), (LPCWSTR)RT_STRING);

    printf("LoadStringW len=%d FindResource=%p\n", len, rsrc);
    if (expect_missing) return len == 0 && !rsrc ? 0 : 1;
    if (len && !wcscmp(buf, L"Hello from MUI \x00e9\x4e2d")) { printf("PASS\n"); return 0; }
    printf("FAIL\n");
    return 1;
}
