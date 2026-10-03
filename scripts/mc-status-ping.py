#!/usr/bin/env python3
"""Minecraft server-list ping tester.

Usage: mc-status-ping.py HOST PORT
Prints the status JSON (favicon shortened). Use it to check the chain:
  127.0.0.1 25565        -> ATM10 directly (loopback)
  play.ethbra.com 25565  -> through TCPShield and Velocity
Note: pinging Velocity at 192.168.1.22 from the LAN is dropped on purpose
(RealIP + firewall only accept TCPShield).
"""
import socket, struct, sys, json
def vi(n):
    b = b""
    while True:
        t = n & 0x7F; n >>= 7
        b += bytes([t | (0x80 if n else 0)])
        if not n: return b
def rvi(s):
    n = 0
    for i in range(5):
        b = s.recv(1)[0]; n |= (b & 0x7F) << (7*i)
        if not b & 0x80: return n
host, port = sys.argv[1], int(sys.argv[2])
s = socket.create_connection((host, port), timeout=10)
h = host.encode()
pk = vi(0) + vi(767) + vi(len(h)) + h + struct.pack(">H", port) + vi(1)
s.sendall(vi(len(pk)) + pk); s.sendall(vi(1) + vi(0))
rvi(s); rvi(s); sl = rvi(s); d = b""
while len(d) < sl: d += s.recv(sl - len(d))
j = json.loads(d)
j["favicon"] = (j.get("favicon","")[:30] + "...") if j.get("favicon") else None
print(json.dumps(j, indent=1)[:900])
