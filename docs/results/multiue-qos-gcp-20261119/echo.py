#!/usr/bin/env python3
# echo.py <bind_ip> <port>: UDP echo server (app-level RTT probe server)
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
s.bind((sys.argv[1], int(sys.argv[2])))
while True:
    d, a = s.recvfrom(2048); s.sendto(d, a)
