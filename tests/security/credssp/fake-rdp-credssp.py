#!/usr/bin/env python3
"""Minimal NLA (CredSSP) RDP endpoint for testing the client offline.

Answers the X.224 Connection Request selecting PROTOCOL_HYBRID ([MS-RDPBCGR] 2.2.1.2),
then runs the server side of [MS-CSSP] with pyspnego (Debian: python3-pyspnego):
TLS with CERT/KEY, NTLM authentication against a test account, public-key binding,
and receipt of the delegated credentials. Then it logs whether the client continues
with the RDP connection sequence (MCS Connect Initial). No RDP session is served.

  NTLM_USER_FILE=FILE fake-rdp-credssp.py PORT CERT KEY [SECONDS]
FILE holds one "DOMAIN:USER:PASSWORD" line. Only test accounts, never real ones.
Logs the delegated user name and whether the password matched FILE, never the password.
"""
import os, select, socket, ssl, sys, time
import importlib.util, sys, types
# Kerberos (KRB5_KTNAME = server keytab): pyspnego loads GSSAPI only together with the
# python "krb5" module, which it needs for client passwords, not for accepting. Debian
# has no package for it, so give the acceptor a stand-in when it is missing.
if os.environ.get("KRB5_KTNAME") and importlib.util.find_spec("krb5") is None:
    sys.modules["krb5"] = types.ModuleType("krb5")
import logging, spnego, spnego.tls
if os.environ.get("FAKE_RDP_DEBUG"): logging.basicConfig(level=logging.DEBUG)

# Windows verifies the NTLMv2 proof over the client's blob exactly as received; pyspnego
# re-serializes it and appends 4 zero bytes, which rejects clients such as Samba's
# ntlm_auth (used by Wine) that send the blob without that padding.
import spnego._ntlm as _ntlm
from spnego._ntlm_raw.crypto import hmac_md5
from spnego._ntlm_raw.messages import Authenticate
_raw_blob = {}
_orig_unpack = Authenticate.unpack
def _unpack(data, *args, **kwargs):
    auth = _orig_unpack(data, *args, **kwargs)
    if auth.nt_challenge_response and len(auth.nt_challenge_response) > 24:
        _raw_blob["temp"] = auth.nt_challenge_response[16:]
    return auth
Authenticate.unpack = staticmethod(_unpack)
def _compute_response_v2(nt_hash, server_challenge, client_challenge, time, av_pairs):
    temp = _raw_blob.pop("temp")
    proof = hmac_md5(nt_hash, server_challenge + temp)
    return proof + temp, hmac_md5(nt_hash, server_challenge + client_challenge) + client_challenge, hmac_md5(nt_hash, proof)
_ntlm.compute_response_v2 = _compute_response_v2

# A Windows server reports a failed logon in TSRequest.errorCode as the NTSTATUS
# STATUS_LOGON_FAILURE (EXP-030); pyspnego sends the HRESULT SEC_E_LOGON_DENIED instead.
import spnego._credssp as _cssp
_TSRequest = _cssp.TSRequest
class _WindowsTSRequest(_TSRequest):
    def __init__(self, *args, error_code=None, **kwargs):
        if error_code is not None and error_code & 0xFFFFFFFF == 0x8009030C: error_code = -0x3FFFFF93  # 0xC000006D, signed like pyspnego
        super().__init__(*args, error_code=error_code, **kwargs)
_cssp.TSRequest = _WindowsTSRequest

port, cert, key = int(sys.argv[1]), sys.argv[2], sys.argv[3]
deadline = time.time() + (float(sys.argv[4]) if len(sys.argv) > 4 else 60)
expected = open(os.environ["NTLM_USER_FILE"]).read().strip().split(":", 2)
t0 = time.time()
def log(msg): print(f"[{time.time()-t0:6.2f}] {msg}", flush=True)

def tls_context():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.options |= ssl.OP_NO_COMPRESSION
    ctx.load_cert_chain(cert, key)
    der = ssl.PEM_cert_to_DER_cert(open(cert).read())
    return spnego.tls.CredSSPTLSContext(ctx, spnego.tls.get_certificate_public_key(der))

def recv_burst(c, first_timeout):
    """Read everything the client sends in one flight."""
    data = b""
    r, _, _ = select.select([c], [], [], first_timeout)
    if not r: return None
    while True:
        chunk = c.recv(65536)
        if not chunk: return data or b""
        data += chunk
        r, _, _ = select.select([c], [], [], 0.3)
        if not r: return data

def split_records(data):
    recs, i = [], 0
    while i + 5 <= len(data):
        n = 5 + int.from_bytes(data[i + 3:i + 5], "big")
        if i + n > len(data): break
        recs.append(data[i:i + n]); i += n
    if i < len(data): recs.append(data[i:])
    return recs

srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port)); srv.listen(4); srv.settimeout(1)

while time.time() < deadline:
    try: c, _ = srv.accept()
    except socket.timeout: continue
    try:
        cr = c.recv(4096)
        req = int.from_bytes(cr[-4:], "little") if len(cr) >= 19 and cr[-8] == 0x01 else None
        log(f"X.224 CR {len(cr)} bytes, requestedProtocols={req}")
        if req is None or not req & 2:
            log("client did not offer HYBRID; closing"); c.close(); continue
        c.sendall(bytes([3, 0, 0, 19, 14, 0xD0, 0, 0, 0x12, 0x34, 0, 2, 0, 8, 0, 2, 0, 0, 0]))
        ctx = spnego.server(protocol="credssp", credssp_tls_context=tls_context())
        step = 0; leftover = b""
        while not ctx.complete:
            data = recv_burst(c, max(1, deadline - time.time()))
            if data is None: log("timeout waiting for client"); break
            if not data: log("client closed during CredSSP"); break
            # feed one TLS record at a time: pyspnego drops plaintext that follows a
            # TSRequest, and the client may send its first RDP PDU in the same flight
            tls = getattr(ctx, "_tls_object", None)
            recs = split_records(data) if tls is not None and tls.version() else [data]
            for i, rec in enumerate(recs):
                out = ctx.step(rec)
                if out: c.sendall(out)
                if ctx.complete:
                    leftover = b"".join(recs[i + 1:]); break
            step += 1
            log(f"CredSSP step {step}: in {len(data)} bytes ({len(recs)} records)")
        if not ctx.complete: c.close(); continue
        cred = ctx.get_extra_info("client_credential")
        user = getattr(cred, "username", None); pw = getattr(cred, "password", None)
        mech = getattr(getattr(ctx, "_auth_context", None), "negotiated_protocol", None)
        log(f"CREDSSP COMPLETE: version {ctx.get_extra_info('protocol_version')}, mechanism {mech}, "
            f"delegated user {user!r}, password {'matches' if pw == expected[2] else 'DOES NOT MATCH'}")
        plain = ctx.unwrap(leftover).data if leftover else b""
        if not plain:
            data = recv_burst(c, max(1, deadline - time.time()))
            if data: plain = ctx.unwrap(data).data
        if plain:
            log(f"CLIENT CONTINUED: {len(plain)} bytes after CredSSP, first byte {plain[0]:#04x} (MCS Connect Initial = 0x03)")
        else: log("no data from client after CredSSP")
        # keep the connection open (without answering) so client-side prompts can be observed
        hold = min(float(os.environ.get("FAKE_RDP_HOLD", "15")), max(0, deadline - time.time()))
        while hold > 0:
            t1 = time.time(); more = recv_burst(c, hold)
            if more is None: break
            if not more: log("client closed the connection"); break
            log(f"client sent {len(more)} more bytes")
            hold -= time.time() - t1
        c.close()
    except Exception as e:
        log(f"connection ended: {type(e).__name__}: {e}")
log("done")
