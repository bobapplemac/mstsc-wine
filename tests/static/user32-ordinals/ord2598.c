/* Calls user32 ordinal 2598 the way mstsc.exe 10.0.20348 does: looked up with
 * GetProcAddress after LoadLibraryW, called with no arguments, result ignored.
 * Unmodified Wine 11.0 exports it as an unimplemented stub, which aborts the
 * process.  Exit 0 = callable. */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    HMODULE user32 = LoadLibraryW(L"user32.dll");
    BOOL (WINAPI *fn)(void) = (void *)GetProcAddress(user32, MAKEINTRESOURCEA(2598));
    if (!fn) { printf("ordinal 2598 not exported\n"); return 1; }
    fn();
    printf("ordinal 2598 returned\n");
    return 0;
}
