/* Keyboard probe: logs what Wine delivers to a Windows application for each key press,
 * the way a terminal-services client sees it (EXP-074).
 *   kbdprobe.exe [seconds]
 * Prints, flushed line by line:
 *   LAYOUT hkl=XXXXXXXX name=XXXXXXXX count=N list=...
 *   READY
 *   LL  down|up vk=XX scan=XX ext=0|1 inj=0|1        (WH_KEYBOARD_LL, as an RDP client hooks it)
 *   MSG WM_KEYDOWN|WM_KEYUP|WM_SYSKEYDOWN|WM_SYSKEYUP vk=XX scan=XX ext=0|1
 *   CHAR U+XXXX                                   (WM_CHAR / WM_SYSCHAR)
 *   DEAD U+XXXX                                   (WM_DEADCHAR / WM_SYSDEADCHAR)
 *   IME msg=XXXX wp=XXXX                          (WM_IME_CHAR / composition messages)
 *   MAP vk=XX scan=XX   for every vk whose MapVirtualKey(VK_TO_VSC) is non-zero (at start)
 * The window takes focus itself so that X key events reach it. */
#include <windows.h>
#include <stdio.h>

static HHOOK hook;

static LRESULT CALLBACK ll_proc( int code, WPARAM wp, LPARAM lp )
{
    if (code == HC_ACTION)
    {
        KBDLLHOOKSTRUCT *k = (KBDLLHOOKSTRUCT *)lp;
        printf( "LL  %s vk=%02lx scan=%02lx ext=%d inj=%d\n",
                (k->flags & LLKHF_UP) ? "up" : "down", k->vkCode, k->scanCode,
                !!(k->flags & LLKHF_EXTENDED), !!(k->flags & LLKHF_INJECTED) );
        fflush( stdout );
    }
    return CallNextHookEx( hook, code, wp, lp );
}

static const char *msg_name( UINT msg )
{
    switch (msg)
    {
    case WM_KEYDOWN: return "WM_KEYDOWN";
    case WM_KEYUP: return "WM_KEYUP";
    case WM_SYSKEYDOWN: return "WM_SYSKEYDOWN";
    case WM_SYSKEYUP: return "WM_SYSKEYUP";
    }
    return NULL;
}

static LRESULT CALLBACK wnd_proc( HWND hwnd, UINT msg, WPARAM wp, LPARAM lp )
{
    const char *name = msg_name( msg );
    if (name)
    {
        printf( "MSG %s vk=%02x scan=%02x ext=%d\n", name, (unsigned)wp,
                (unsigned)((lp >> 16) & 0xff), (int)((lp >> 24) & 1) );
        fflush( stdout );
        return 0;  /* swallow, so that Alt/F10 do not enter menu mode */
    }
    if (msg == WM_CHAR || msg == WM_SYSCHAR)
    {
        printf( "CHAR U+%04X\n", (unsigned)wp );
        fflush( stdout );
        return 0;
    }
    if (msg == WM_DEADCHAR || msg == WM_SYSDEADCHAR)
    {
        printf( "DEAD U+%04X\n", (unsigned)wp );
        fflush( stdout );
        return 0;
    }
    if (msg == WM_IME_CHAR || msg == WM_IME_COMPOSITION || msg == WM_IME_STARTCOMPOSITION)
    {
        printf( "IME msg=%04x wp=%04X\n", msg, (unsigned)wp );
        fflush( stdout );
    }
    if (msg == WM_DESTROY) PostQuitMessage( 0 );
    return DefWindowProcW( hwnd, msg, wp, lp );
}

int main( int argc, char **argv )
{
    WNDCLASSW wc = { 0 };
    WCHAR name[KL_NAMELENGTH];
    HKL list[32];
    int seconds = argc > 1 ? atoi( argv[1] ) : 20, i, n;
    unsigned vk;
    HWND hwnd;
    MSG m;

    GetKeyboardLayoutNameW( name );
    n = GetKeyboardLayoutList( 32, list );
    printf( "LAYOUT hkl=%08lx name=%ls count=%d list=", (ULONG)(ULONG_PTR)GetKeyboardLayout( 0 ), name, n );
    for (i = 0; i < n; i++) printf( "%s%08lx", i ? "," : "", (ULONG)(ULONG_PTR)list[i] );
    printf( "\n" );
    for (vk = 1; vk < 256; vk++)
    {
        UINT scan = MapVirtualKeyW( vk, MAPVK_VK_TO_VSC_EX );
        if (scan) printf( "MAP vk=%02x scan=%04x\n", vk, scan );
    }

    wc.lpfnWndProc = wnd_proc;
    wc.hInstance = GetModuleHandleW( NULL );
    wc.lpszClassName = L"kbdprobe";
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    RegisterClassW( &wc );
    hwnd = CreateWindowW( L"kbdprobe", L"kbdprobe", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                          0, 0, 400, 300, NULL, NULL, wc.hInstance, NULL );
    hook = SetWindowsHookExW( WH_KEYBOARD_LL, ll_proc, wc.hInstance, 0 );
    SetForegroundWindow( hwnd );
    SetFocus( hwnd );
    SetTimer( hwnd, 1, seconds * 1000, NULL );
    /* let the window manager map and focus the window */
    for (i = 0; i < 20; i++)
    {
        while (PeekMessageW( &m, NULL, 0, 0, PM_REMOVE )) { TranslateMessage( &m ); DispatchMessageW( &m ); }
        Sleep( 50 );
    }
    printf( "READY\n" );
    fflush( stdout );
    while (GetMessageW( &m, NULL, 0, 0 ))
    {
        if (m.message == WM_TIMER) break;
        TranslateMessage( &m );
        DispatchMessageW( &m );
    }
    UnhookWindowsHookEx( hook );
    return 0;
}
