#!/usr/bin/env python3
# Verifikasi WebSocket /websockify lewat public URL dengan basic auth (password dari env WEBPW, tidak dicetak).
import os, ssl, socket, base64, struct, sys
url=sys.argv[1]; host=url.split('//')[1].strip('/')
auth=base64.b64encode(f"lab:{os.environ['WEBPW']}".encode()).decode()
def frame(payload):  # client frame, binary, masked
    m=os.urandom(4); h=bytes([0x82]); n=len(payload)
    h+=bytes([0x80|n]) if n<126 else bytes([0x80|126])+struct.pack('>H',n)
    return h+m+bytes(b^m[i%4] for i,b in enumerate(payload))
def recv_frame(s):
    h=s.recv(2); n=h[1]&0x7f
    if n==126: n=struct.unpack('>H',s.recv(2))[0]
    d=b''
    while len(d)<n: d+=s.recv(n-len(d))
    return d
def ws(with_auth):
    s=ssl.create_default_context().wrap_socket(socket.create_connection((host,443),15),server_hostname=host)
    req=(f"GET /websockify HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
         f"Sec-WebSocket-Key: {base64.b64encode(os.urandom(16)).decode()}\r\nSec-WebSocket-Version: 13\r\n"
         f"Sec-WebSocket-Protocol: binary\r\n" + (f"Authorization: Basic {auth}\r\n" if with_auth else "") + "\r\n")
    s.send(req.encode()); resp=b''
    while b'\r\n\r\n' not in resp: resp+=s.recv(1)
    status=resp.split(b'\r\n')[0].decode(); print(f"ws auth={with_auth}: {status}")
    if ' 101 ' in status:
        banner=recv_frame(s); print("  RFB banner:", banner)
        s.send(frame(b"RFB 003.008\n")); d=recv_frame(s)
        print("  security types:", list(d[1:1+d[0]]), "(2 = VNC password masih diminta)")
    s.close()
ws(False); ws(True)
