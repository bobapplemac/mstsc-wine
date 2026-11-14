#!/usr/bin/env python3
"""Minimal RDP endpoint for testing the client's server-certificate check offline.

Answers the X.224 Connection Request selecting PROTOCOL_SSL ([MS-RDPBCGR] 2.2.1.2),
completes TLS with the given certificate, then only logs what the client sends.
A client that checks the certificate must stop (or prompt) before sending the MCS
Connect Initial (TPKT, first byte 0x03).  No RDP session is ever served.

  fake-rdp-tls.py PORT CERT KEY [SECONDS]
"""
import socket, ssl, sys, time

port, cert, key = int(sys.argv[1]), sys.argv[2], sys.argv[3]
deadline = time.time() + (float(sys.argv[4]) if len(sys.argv) > 4 else 60)
t0 = time.time()
def log(msg): print(f"[{time.time()-t0:6.2f}] {msg}", flush=True)

srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port)); srv.listen(4); srv.settimeout(1)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(cert, key)
ctx.minimum_version = ssl.TLSVersion.TLSv1_2

while time.time() < deadline:
    try: c, _ = srv.accept()
    except socket.timeout: continue
    c.settimeout(10)
    try:
        cr = c.recv(4096)
        req = None
        if len(cr) >= 19 and cr[-8] == 0x01:            # RDP_NEG_REQ at the end of the CR
            req = int.from_bytes(cr[-4:], "little")
        log(f"X.224 CR {len(cr)} bytes, requestedProtocols={req}")
        if req is None or not req & 1:
            log("client did not offer TLS; closing"); c.close(); continue
        # TPKT + X.224 CC + RDP_NEG_RSP(selectedProtocol = PROTOCOL_SSL)
        c.sendall(bytes([3, 0, 0, 19, 14, 0xD0, 0, 0, 0x12, 0x34, 0,
                         2, 0, 8, 0, 1, 0, 0, 0]))
        t = ctx.wrap_socket(c, server_side=True)
        log(f"TLS established {t.version()} {t.cipher()[0]}")
        t.settimeout(max(1, deadline - time.time()))
        try:
            d = t.recv(65536)
            if d: log(f"CLIENT CONTINUED: {len(d)} bytes after TLS, first byte {d[0]:#04x} (MCS Connect Initial = 0x03)")
            else: log("client closed TLS without sending data")
        except (socket.timeout, TimeoutError): log("no data from client (waiting/prompting)")
        t.close()
    except Exception as e:
        log(f"connection ended: {type(e).__name__}: {e}")
log("done")
