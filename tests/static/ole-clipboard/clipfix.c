/* Clipboard fixture: does what mstscax.dll's clipboard redirection (rdpclip client) does.
 *   clipfix.exe probe        WIL feature probe, then GlobalAlloc + GetLastError (EXP-048);
 *                            no names for predefined formats (EXP-049)
 *   clipfix.exe set SECONDS  OleSetClipboard with a delayed-render IDataObject offering
 *                            CF_UNICODETEXT ("remote" data), keep it for SECONDS
 *   clipfix.exe get          OleGetClipboard, print CF_UNICODETEXT as UTF-8 ("local" data)
 * Output lines are parsed by run.sh. */
#define COBJMACROS
#include <windows.h>
#include <ole2.h>
#include <shlobj.h>
#include <stdio.h>

static const WCHAR remote_text[] = L"remote \x00c4\x00d6\x00fc \x20ac \x4e2d\x6587\r\nline 2";

/* ---- a minimal delayed-render data object (one format, rendered on request) ---- */
typedef struct { IDataObject IDataObject_iface; LONG ref; int renders; } dataobj;
static dataobj obj;

static HRESULT WINAPI d_QueryInterface(IDataObject *i, REFIID riid, void **out)
{
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IDataObject)) { *out = i; IDataObject_AddRef(i); return S_OK; }
    *out = NULL; return E_NOINTERFACE;
}
static ULONG WINAPI d_AddRef(IDataObject *i) { return InterlockedIncrement(&obj.ref); }
static ULONG WINAPI d_Release(IDataObject *i) { return InterlockedDecrement(&obj.ref); }
static HRESULT WINAPI d_GetData(IDataObject *i, FORMATETC *fe, STGMEDIUM *med)
{
    HGLOBAL h; void *p;
    if (fe->cfFormat != CF_UNICODETEXT || !(fe->tymed & TYMED_HGLOBAL)) return DV_E_FORMATETC;
    obj.renders++;
    h = GlobalAlloc(GMEM_MOVEABLE, sizeof(remote_text));
    p = GlobalLock(h); memcpy(p, remote_text, sizeof(remote_text)); GlobalUnlock(h);
    med->tymed = TYMED_HGLOBAL; med->hGlobal = h; med->pUnkForRelease = NULL;
    printf("RENDER %d\n", obj.renders); fflush(stdout);
    return S_OK;
}
static HRESULT WINAPI d_GetDataHere(IDataObject *i, FORMATETC *fe, STGMEDIUM *med) { return E_NOTIMPL; }
static HRESULT WINAPI d_QueryGetData(IDataObject *i, FORMATETC *fe)
{ return fe->cfFormat == CF_UNICODETEXT ? S_OK : DV_E_FORMATETC; }
static HRESULT WINAPI d_GetCanonicalFormatEtc(IDataObject *i, FORMATETC *a, FORMATETC *b) { return E_NOTIMPL; }
static HRESULT WINAPI d_SetData(IDataObject *i, FORMATETC *fe, STGMEDIUM *m, BOOL r) { return E_NOTIMPL; }
static HRESULT WINAPI d_EnumFormatEtc(IDataObject *i, DWORD dir, IEnumFORMATETC **e)
{
    static FORMATETC fe = { CF_UNICODETEXT, NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
    return dir == DATADIR_GET ? SHCreateStdEnumFmtEtc(1, &fe, e) : E_NOTIMPL;
}
static HRESULT WINAPI d_DAdvise(IDataObject *i, FORMATETC *f, DWORD a, IAdviseSink *s, DWORD *c) { return OLE_E_ADVISENOTSUPPORTED; }
static HRESULT WINAPI d_DUnadvise(IDataObject *i, DWORD c) { return OLE_E_ADVISENOTSUPPORTED; }
static HRESULT WINAPI d_EnumDAdvise(IDataObject *i, IEnumSTATDATA **e) { return OLE_E_ADVISENOTSUPPORTED; }
static IDataObjectVtbl vtbl = { d_QueryInterface, d_AddRef, d_Release, d_GetData, d_GetDataHere,
    d_QueryGetData, d_GetCanonicalFormatEtc, d_SetData, d_EnumFormatEtc, d_DAdvise, d_DUnadvise, d_EnumDAdvise };

static int probe(void)
{
    typedef LONG (WINAPI *query_fn)(ULONG, int, ULONGLONG *, void *);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    query_fn query;
    ULONGLONG stamp = ~0ull;
    BYTE config[12];
    HGLOBAL h;
    DWORD err;
    LONG status;
    int fail = 0;

    /* wil::details::FeatureStateManager resolves these on every feature check */
    SetLastError(0);
    query = (query_fn)GetProcAddress(ntdll, "RtlQueryFeatureConfiguration");
    err = GetLastError();
    printf("RtlQueryFeatureConfiguration %s lasterror %lu\n", query ? "present" : "missing", err);
    if (!query || err) fail = 1;
    if (!GetProcAddress(ntdll, "RtlRegisterFeatureConfigurationChangeNotification")) { printf("RtlRegisterFeatureConfigurationChangeNotification missing\n"); fail = 1; }
    if (!GetProcAddress(ntdll, "RtlUnregisterFeatureConfigurationChangeNotification")) { printf("RtlUnregisterFeatureConfigurationChangeNotification missing\n"); fail = 1; }
    if (query)
    {
        status = query(0x1234567, 1 /* runtime */, &stamp, config);
        printf("query status %#lx stamp %#llx\n", status, stamp);
        if (status != (LONG)0xc0000225 /* STATUS_NOT_FOUND: no override, use the default */) fail = 1;
    }
    /* mstscax's clipboard code: allocate, then treat any last error as failure */
    h = GlobalAlloc(GMEM_ZEROINIT, 4);
    err = GetLastError();
    printf("GlobalAlloc %p lasterror %lu\n", h, err);
    if (!h || err) fail = 1;
    GlobalFree(h);
    /* cliprdr format lists carry GetClipboardFormatNameW names; predefined formats have none */
    {
        WCHAR name[64];
        int len = GetClipboardFormatNameW(CF_UNICODETEXT, name, 64);
        printf("GetClipboardFormatNameW(CF_UNICODETEXT) %d\n", len);
        if (len) fail = 1;
    }
    printf(fail ? "PROBE FAIL\n" : "PROBE OK\n");
    return fail;
}

static int set(int seconds)
{
    DWORD end = GetTickCount() + seconds * 1000;
    HRESULT hr;
    MSG msg;
    obj.IDataObject_iface.lpVtbl = &vtbl; obj.ref = 1;
    OleInitialize(NULL);
    hr = OleSetClipboard(&obj.IDataObject_iface);
    printf("OleSetClipboard %#lx\n", hr); fflush(stdout);
    if (FAILED(hr)) return 1;
    printf("OleIsCurrentClipboard %#lx\n", OleIsCurrentClipboard(&obj.IDataObject_iface)); fflush(stdout);
    while ((LONG)(end - GetTickCount()) > 0)
    {
        MsgWaitForMultipleObjects(0, NULL, FALSE, 100, QS_ALLINPUT);
        while (PeekMessageW(&msg, 0, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    }
    OleSetClipboard(NULL);
    OleUninitialize();
    return 0;
}

static int get(void)
{
    FORMATETC fe = { CF_UNICODETEXT, NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
    IDataObject *data;
    STGMEDIUM med;
    HRESULT hr;
    char *utf8;
    int n;
    OleInitialize(NULL);
    if (FAILED(hr = OleGetClipboard(&data))) { printf("OleGetClipboard %#lx\n", hr); return 1; }
    if (FAILED(hr = IDataObject_GetData(data, &fe, &med))) { printf("GetData %#lx\n", hr); return 1; }
    n = WideCharToMultiByte(CP_UTF8, 0, GlobalLock(med.hGlobal), -1, NULL, 0, NULL, NULL);
    utf8 = malloc(n);
    WideCharToMultiByte(CP_UTF8, 0, GlobalLock(med.hGlobal), -1, utf8, n, NULL, NULL);
    printf("TEXT ");
    for (int i = 0; utf8[i]; i++) printf("%02x", (unsigned char)utf8[i]);
    printf("\n");
    GlobalUnlock(med.hGlobal);
    ReleaseStgMedium(&med);
    IDataObject_Release(data);
    OleUninitialize();
    return 0;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc > 1 && !strcmp(argv[1], "probe")) return probe();
    if (argc > 2 && !strcmp(argv[1], "set")) return set(atoi(argv[2]));
    if (argc > 1 && !strcmp(argv[1], "get")) return get();
    return 2;
}
