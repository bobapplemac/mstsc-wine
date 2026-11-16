/* CredSSP (NLA) client test against tests/security/credssp/fake-rdp-credssp.py.
 *   cssclient.exe PORT USER DOMAIN PASSWORD [packed|saved]
 * Negotiates PROTOCOL_HYBRID and runs the CREDSSP package as the Remote Desktop client
 * does (TERMSRV/ target, delegation, mutual authentication requested). Like mstsc:
 *  - a server authenticated by neither Kerberos nor a trusted certificate makes the first
 *    attempt fail with SEC_E_MUTUAL_AUTH_FAILED before any credentials are delegated;
 *    SECPKG_ATTR_SERVER_AUTH_FLAGS is 0 and the trust status names the untrusted root
 *    (mstsc warns here); the client then connects again without mutual authentication
 *    ("Yes" in the warning) and delegates;
 *  - a Kerberos logon authenticates the server (flags CREDSSP_SERVER_AUTH_NEGOTIATE):
 *    no second attempt.
 * Prints "server auth flags 0x..". Then sends one RDP-like PDU through the channel.  "packed" passes the credentials the way mstsc does:
 * CredsspSubmitBufferBoth with a packed KERB_INTERACTIVE_UNLOCK_LOGON.  "saved" stores them
 * as mstsc's "Remember my password" does (CredWriteW, TERMSRV/localhost) and passes no
 * credentials to CredSSP, which must delegate the saved ones (EXP-036).
 * Exit 0 on success. Test accounts only. */
#define SECURITY_WIN32
#include <winsock2.h>
#include <windows.h>
#include <sspi.h>
#include <schannel.h>
#include <ntsecapi.h>
#include <wincred.h>
#include <winternl.h>

NTSTATUS NTAPI RtlGetLastNtStatus(void);
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { ULONG Type; void *pSchannelCred; void *pSpnegoCred; } CREDSSP_CRED_;
#define SERVER_AUTH_FLAGS 0x80000083
#define CERT_TRUST_STATUS_ATTR 0x80000084
#ifndef SEC_E_MUTUAL_AUTH_FAILED
#define SEC_E_MUTUAL_AUTH_FAILED ((SECURITY_STATUS)0x80090363)
#endif

static int recv_some(SOCKET s, char *buf, int *len, int cap)
{
    int n = recv(s, buf + *len, cap - *len, 0);
    if (n <= 0) return 0;
    *len += n; return 1;
}

static BYTE *pack(const WCHAR *user, const WCHAR *domain, const WCHAR *pass)
{
    size_t lu = wcslen(user) * 2, ld = wcslen(domain) * 2, lp = wcslen(pass) * 2;
    KERB_INTERACTIVE_UNLOCK_LOGON *l = calloc(1, sizeof(*l) + lu + ld + lp);
    BYTE *p = (BYTE *)(l + 1);
    l->Logon.MessageType = KerbInteractiveLogon;
#define S(f, str, n) l->Logon.f.Length = l->Logon.f.MaximumLength = (USHORT)n; \
    l->Logon.f.Buffer = (WCHAR *)(ULONG_PTR)(p - (BYTE *)l); memcpy(p, str, n); p += n;
    S(LogonDomainName, domain, ld) S(UserName, user, lu) S(Password, pass, lp)
    return (BYTE *)l;
}

/* one connection: X.224 negotiation, then the CredSSP handshake with the given flags */
static SECURITY_STATUS handshake(int port, CredHandle *cred, CtxtHandle *ctx, SOCKET *s, ULONG req)
{
    static char in[65536];
    static const BYTE cr[] = { 3,0,0,19, 14,0xe0,0,0,0,0,0, 1,0,8,0, 3,0,0,0 };
    struct sockaddr_in addr = {0};
    SECURITY_STATUS st; ULONG attrs; TimeStamp ts;
    int in_len = 0, first = 1;

    *s = socket(AF_INET, SOCK_STREAM, 0);
    addr.sin_family = AF_INET; addr.sin_port = htons((u_short)port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(*s, (struct sockaddr *)&addr, sizeof(addr))) { printf("FAIL connect\n"); return -3; }
    send(*s, (const char *)cr, sizeof(cr), 0);
    if (!recv_some(*s, in, &in_len, 19) || in_len < 19 || in[15] != 2) { printf("FAIL server did not select HYBRID\n"); return -3; }
    in_len = 0;


    for (;;)
    {
        SecBuffer ib[2], ob[1];
        SecBufferDesc ind = { SECBUFFER_VERSION, 2, ib }, outd = { SECBUFFER_VERSION, 1, ob };
        ib[0].BufferType = SECBUFFER_TOKEN; ib[0].cbBuffer = in_len; ib[0].pvBuffer = in;
        ib[1].BufferType = SECBUFFER_EMPTY; ib[1].cbBuffer = 0; ib[1].pvBuffer = NULL;
        ob[0].BufferType = SECBUFFER_TOKEN; ob[0].cbBuffer = 0; ob[0].pvBuffer = NULL;
        st = InitializeSecurityContextW(cred, first ? NULL : ctx, (WCHAR *)L"TERMSRV/localhost", req,
                                        0, 0, first ? NULL : &ind, 0, ctx, &outd, &attrs, &ts);
        first = 0;
        if (ob[0].cbBuffer && ob[0].pvBuffer) { send(*s, ob[0].pvBuffer, ob[0].cbBuffer, 0); FreeContextBuffer(ob[0].pvBuffer); }
        if (st == SEC_E_OK) return SEC_E_OK;
        if (st == SEC_I_CONTINUE_NEEDED || st == SEC_E_INCOMPLETE_MESSAGE)
        {
            if (st == SEC_I_CONTINUE_NEEDED)
            {
                if (ib[1].BufferType == SECBUFFER_EXTRA && ib[1].cbBuffer)
                { memmove(in, in + in_len - ib[1].cbBuffer, ib[1].cbBuffer); in_len = ib[1].cbBuffer; continue; }
                in_len = 0;
            }
            if (!recv_some(*s, in, &in_len, sizeof(in))) { printf("FAIL connection closed\n"); return -1; }
            continue;
        }
        return st;
    }

}

#define REQ (ISC_REQ_DELEGATE | ISC_REQ_REPLAY_DETECT | ISC_REQ_SEQUENCE_DETECT | ISC_REQ_CONFIDENTIALITY | \
             ISC_REQ_ALLOCATE_MEMORY | ISC_REQ_EXTENDED_ERROR | ISC_REQ_STREAM)

int main(int argc, char **argv)
{
    WCHAR user[128], domain[128], pass[128];
    SEC_WINNT_AUTH_IDENTITY_W id = {0};
    SCHANNEL_CRED schan = { SCHANNEL_CRED_VERSION };
    CREDSSP_CRED_ cc = { 2, &schan, &id };
    SecPkgContext_StreamSizes sizes;
    SecPkgContext_Flags flags;
    CredHandle cred; CtxtHandle ctx;
    WSADATA wsa; SOCKET s; TimeStamp ts;
    SECURITY_STATUS st;
    int n;

    if (argc < 5) return 2;
    MultiByteToWideChar(CP_UTF8, 0, argv[2], -1, user, 128);
    MultiByteToWideChar(CP_UTF8, 0, argv[3], -1, domain, 128);
    MultiByteToWideChar(CP_UTF8, 0, argv[4], -1, pass, 128);
    id.User = (unsigned short *)user; id.UserLength = wcslen(user);
    id.Domain = (unsigned short *)domain; id.DomainLength = wcslen(domain);
    id.Password = (unsigned short *)pass; id.PasswordLength = wcslen(pass);
    id.Flags = SEC_WINNT_AUTH_IDENTITY_UNICODE;
    if (argc > 5 && !strcmp(argv[5], "packed")) { cc.Type = 50; cc.pSpnegoCred = pack(user, domain, pass); }
    if (argc > 5 && !strcmp(argv[5], "saved"))
    {
        WCHAR name[260];
        CREDENTIALW c = {0};
        swprintf(name, 260, L"%ls\\%ls", domain, user);
        c.Type = CRED_TYPE_DOMAIN_PASSWORD;
        c.TargetName = (WCHAR *)L"TERMSRV/localhost";
        c.UserName = name;
        c.CredentialBlob = (BYTE *)pass;
        c.CredentialBlobSize = wcslen(pass) * sizeof(WCHAR);
        c.Persist = CRED_PERSIST_LOCAL_MACHINE;
        if (!CredWriteW(&c, 0)) { printf("FAIL CredWriteW %lu\n", GetLastError()); return 4; }
        cc.Type = 51; cc.pSpnegoCred = NULL;   /* as mstsc passes it when credentials are saved */
    }
    schan.grbitEnabledProtocols = SP_PROT_TLS1_2_CLIENT;

    WSAStartup(MAKEWORD(2, 2), &wsa);
    st = AcquireCredentialsHandleW(NULL, (WCHAR *)L"CREDSSP", SECPKG_CRED_OUTBOUND, NULL, &cc, NULL, NULL, &cred, &ts);
    if (st) { printf("FAIL AcquireCredentialsHandle(CREDSSP) %#lx\n", st); return 4; }

    st = handshake(atoi(argv[1]), &cred, &ctx, &s, REQ | ISC_REQ_MUTUAL_AUTH);
    if (st == SEC_E_MUTUAL_AUTH_FAILED)
    {
        CERT_TRUST_STATUS trust = {0};
        st = QueryContextAttributesW(&ctx, SERVER_AUTH_FLAGS, &flags);
        if (st || flags.Flags) { printf("FAIL SERVER_AUTH_FLAGS %#lx flags %#lx after SEC_E_MUTUAL_AUTH_FAILED\n", st, flags.Flags); return 5; }
        st = QueryContextAttributesW(&ctx, CERT_TRUST_STATUS_ATTR, &trust);
        if (st || !(trust.dwErrorStatus & CERT_TRUST_IS_UNTRUSTED_ROOT))
        { printf("FAIL CERT_TRUST_STATUS %#lx error status %#lx\n", st, trust.dwErrorStatus); return 5; }
        printf("PASS unauthenticated server refused before delegation (untrusted root %#lx)\n", trust.dwErrorStatus);
        DeleteSecurityContext(&ctx); closesocket(s);
        /* the user accepted the warning: mstsc connects again without mutual authentication */
        st = handshake(atoi(argv[1]), &cred, &ctx, &s, REQ);
    }
    if (st)
    {
        /* mstsc tells a failed logon (re-prompt) from a server without NLA (retry
         * without it) by the thread's last NTSTATUS, which Windows leaves set */
        printf("FAIL InitializeSecurityContext %#lx, last status %#lx\n", st, RtlGetLastNtStatus());
        return 1;
    }

    st = QueryContextAttributesW(&ctx, SERVER_AUTH_FLAGS, &flags);
    if (st) { printf("FAIL SERVER_AUTH_FLAGS %#lx\n", st); return 5; }
    printf("server auth flags %#lx\n", flags.Flags);
    QueryContextAttributesW(&ctx, SECPKG_ATTR_STREAM_SIZES, &sizes);
    {
        static const char pdu[] = "\x03\x00\x00\x09hello";
        char *rec = malloc(sizes.cbHeader + sizes.cbMaximumMessage + sizes.cbTrailer);
        SecBuffer b[4]; SecBufferDesc d = { SECBUFFER_VERSION, 4, b };
        b[0].BufferType = SECBUFFER_STREAM_HEADER; b[0].cbBuffer = sizes.cbHeader; b[0].pvBuffer = rec;
        b[1].BufferType = SECBUFFER_DATA; b[1].cbBuffer = 9; b[1].pvBuffer = rec + sizes.cbHeader;
        b[2].BufferType = SECBUFFER_STREAM_TRAILER; b[2].cbBuffer = sizes.cbTrailer; b[2].pvBuffer = rec + sizes.cbHeader + 9;
        b[3].BufferType = SECBUFFER_EMPTY; b[3].cbBuffer = 0; b[3].pvBuffer = NULL;
        memcpy(b[1].pvBuffer, pdu, 9);
        if ((st = EncryptMessage(&ctx, 0, &d, 0))) { printf("FAIL EncryptMessage %#lx\n", st); return 6; }
        n = b[0].cbBuffer + b[1].cbBuffer + b[2].cbBuffer;
        send(s, rec, n, 0);
    }
    Sleep(500);
    printf("PASS CredSSP complete\n");
    DeleteSecurityContext(&ctx); FreeCredentialsHandle(&cred);
    if (argc > 5 && !strcmp(argv[5], "saved")) CredDeleteW(L"TERMSRV/localhost", CRED_TYPE_DOMAIN_PASSWORD, 0);
    closesocket(s);
    return 0;
}
