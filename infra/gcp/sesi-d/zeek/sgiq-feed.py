#!/usr/bin/env python3
"""sgiq feeder: re-frame the shaper-side captures so pkthash.zeek (DLT_EN10MB on a veth) can read them.

Why: the DL pre-HTB copy (tc mirred -> dummy 'sgiq') and the UL post-HTB point (ifb0 TX) carry raw IP packets
(ogstun is an L3 tun device, no MAC header) on Ethernet-type devices. libpcap labels them Ethernet, so Zeek would
misparse every frame. This script sniffs OUTGOING frames on --src (AF_PACKET, SOCK_RAW), prepends a fake
Ethernet header (ethertype from the IP version nibble) and sends them to --out (a veth peer that Zeek listens on).
Timestamps are those of the veth receive (~tens of microseconds after the shaper point, same host clock).

usage: sgiq-feed.py --src sgiq --out sgiqd0
"""
from __future__ import annotations

import argparse, socket, struct

ETH_P_ALL, ETH_P_IP, ETH_P_IPV6 = 0x0003, 0x0800, 0x86DD
PACKET_OUTGOING = 4
DST = b"\x02\x00\x00\x00\x00\x12"
SRC = b"\x02\x00\x00\x00\x00\x11"


def reframe(frame: bytes) -> bytes | None:
    """Raw IP packet -> fake Ethernet frame. Returns None for non-IP data."""
    if not frame:
        return None
    ver = frame[0] >> 4
    if ver == 4 and len(frame) >= 20:
        return DST + SRC + struct.pack("!H", ETH_P_IP) + frame
    if ver == 6 and len(frame) >= 40:
        return DST + SRC + struct.pack("!H", ETH_P_IPV6) + frame
    return None


def run(src: str, out: str) -> None:
    rx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    rx.bind((src, 0))
    tx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    tx.bind((out, 0))
    while True:
        data, addr = rx.recvfrom(65535)
        if addr[2] != PACKET_OUTGOING:   # only the egress tap (post-shaper on ifb0; mirror copy on sgiq)
            continue
        fr = reframe(data)
        if fr is not None:
            try:
                tx.send(fr)
            except OSError:
                pass


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    run(a.src, a.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
