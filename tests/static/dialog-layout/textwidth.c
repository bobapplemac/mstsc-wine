/* Text width as Windows GDI measures it (EXP-042): GDI uses the advance widths of the
 * hinted glyphs.  mstsc's message "The computer name field is blank. Enter a full remote
 * computer" is set in MS Shell Dlg 8pt (Microsoft Sans Serif, -11 px) in a 294-pixel
 * control and fits on one line on Windows Server 2022 (it measures 294 pixels in the
 * reference screenshot).  Needs the genuine micross.ttf: textwidth.exe PATH.
 * Prints "WIDTH n" and "FITS" (exit 0) or "TOO WIDE" (exit 1); exit 2 if the font is missing. */
#include <windows.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    static const WCHAR text[] = L"The computer name field is blank. Enter a full remote computer";
    if (argc < 2 || !AddFontResourceExA(argv[1], FR_PRIVATE, 0)) { printf("NO FONT\n"); return 2; }
    LOGFONTW lf = { -11 };
    lf.lfCharSet = DEFAULT_CHARSET;
    lstrcpyW(lf.lfFaceName, L"Microsoft Sans Serif");
    HFONT font = CreateFontIndirectW(&lf);
    HDC hdc = GetDC(0);
    HGDIOBJ old = SelectObject(hdc, font);
    WCHAR face[LF_FACESIZE]; GetTextFaceW(hdc, LF_FACESIZE, face);
    SIZE sz; GetTextExtentPoint32W(hdc, text, lstrlenW(text), &sz);
    SIZE word; GetTextExtentPoint32W(hdc, L"computer", 8, &word);
    SelectObject(hdc, old); ReleaseDC(0, hdc);
    printf("FACE %ls\nWIDTH %ld (\"computer\" %ld)\n", face, sz.cx, word.cx);
    printf(sz.cx <= 294 ? "FITS\n" : "TOO WIDE\n");
    return sz.cx <= 294 ? 0 : 1;
}
