/* Schannel client handshake test.
 *   tlsclient.exe PORT
 * Connects to 127.0.0.1:PORT and completes a TLS 1.2 client handshake with the
 * credential flags the Remote Desktop client uses (manual certificate validation).
 * Exit 0 when the handshake completes.  Used with a server whose certificate has
 * keyUsage keyEncipherment only (like default RDP self-signed certificates). */
#define SECURITY_WIN32
#include <winsock2.h>
#include <windows.h>
#include <sspi.h>
#include <schannel.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    WSADATA wsa;
    SOCKET s;
    struct sockaddr_in addr = {0};
    SCHANNEL_CRED cred = {0};
    CredHandle hcred;
    CtxtHandle ctx;
    TimeStamp ts;
    SECURITY_STATUS st;
    static char in[65536];
    int in_len = 0, first = 1, n;
    ULONG attrs;

    if (argc < 2) return 2;
    WSAStartup(MAKEWORD(2, 2), &wsa);
    s = socket(AF_INET, SOCK_STREAM, 0);
    addr.sin_family = AF_INET;
    addr.sin_port = htons((u_short)atoi(argv[1]));
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(s, (struct sockaddr *)&addr, sizeof(addr))) { printf("connect failed %d\n", WSAGetLastError()); return 3; }

    cred.dwVersion = SCHANNEL_CRED_VERSION;
    cred.grbitEnabledProtocols = SP_PROT_TLS1_2_CLIENT;
    cred.dwFlags = SCH_CRED_MANUAL_CRED_VALIDATION | SCH_CRED_NO_DEFAULT_CREDS;
    st = AcquireCredentialsHandleW(NULL, (WCHAR *)UNISP_NAME_W, SECPKG_CRED_OUTBOUND, NULL, &cred, NULL, NULL, &hcred, &ts);
    if (st != SEC_E_OK) { printf("AcquireCredentialsHandle %#lx\n", st); return 4; }

    for (;;)
    {
        SecBuffer ib[2], ob[1];
        SecBufferDesc ind = { SECBUFFER_VERSION, 2, ib }, outd = { SECBUFFER_VERSION, 1, ob };

        ib[0].BufferType = SECBUFFER_TOKEN; ib[0].cbBuffer = in_len; ib[0].pvBuffer = in;
        ib[1].BufferType = SECBUFFER_EMPTY; ib[1].cbBuffer = 0; ib[1].pvBuffer = NULL;
        ob[0].BufferType = SECBUFFER_TOKEN; ob[0].cbBuffer = 0; ob[0].pvBuffer = NULL;

        st = InitializeSecurityContextW(&hcred, first ? NULL : &ctx, (WCHAR *)L"localhost",
                                        ISC_REQ_ALLOCATE_MEMORY | ISC_REQ_CONFIDENTIALITY | ISC_REQ_STREAM |
                                        ISC_REQ_SEQUENCE_DETECT | ISC_REQ_REPLAY_DETECT | ISC_REQ_MANUAL_CRED_VALIDATION,
                                        0, 0, first ? NULL : &ind, 0, &ctx, &outd, &attrs, &ts);
        first = 0;
        if (ob[0].cbBuffer && ob[0].pvBuffer)
        {
            send(s, ob[0].pvBuffer, ob[0].cbBuffer, 0);
            FreeContextBuffer(ob[0].pvBuffer);
        }
        if (st == SEC_E_OK) { printf("PASS handshake complete\n"); return 0; }
        if (st == SEC_E_INCOMPLETE_MESSAGE || st == SEC_I_CONTINUE_NEEDED)
        {
            if (st == SEC_I_CONTINUE_NEEDED)
            {
                if (ib[1].BufferType == SECBUFFER_EXTRA && ib[1].cbBuffer)
                {
                    memmove(in, in + in_len - ib[1].cbBuffer, ib[1].cbBuffer);
                    in_len = ib[1].cbBuffer;
                    continue;
                }
                in_len = 0;
            }
            n = recv(s, in + in_len, sizeof(in) - in_len, 0);
            if (n <= 0) { printf("FAIL connection closed (recv %d)\n", n); return 1; }
            in_len += n;
            continue;
        }
        printf("FAIL InitializeSecurityContext %#lx\n", st);
        return 1;
    }
}
