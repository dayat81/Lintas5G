#!/usr/bin/env python3
"""Fan-in the Sesi D 3 taps onto one veth, tagged with the VLAN IDs pktlat2.zeek v2.1 already understands.

  n3  (lo, typically Ethernet + GTP-U :2152) -> VLAN 102  -> field ow_s1u / seg=s1u
  ue  (tun_srsue in netns ue1, raw IPv4)     -> VLAN 105  -> field ow_s5s8 / seg=s5s8
                                                 LAB LABEL: this is the UE tap, NOT S5/S8
                                                 (Open5GS-in-one-box has no separate S5/S8 tap).
  n6  (ogstun, raw IPv4; includes MGLT :9001)-> VLAN 109  -> field ow_sgi / seg=sgi
                                                 probe_vlan=109 so probes are processed once, at SGi.

Stock pktlat2.zeek is not forked. Analysis relabels s1u->n3, s5s8->ue, sgi->n6.

usage:
  pktlat-mirror.py encode --in-pcap IN --tap ue|n3|n6 --out-pcap OUT   # unit test / offline
  pktlat-mirror.py encode-frame --tap ue|n3|n6   < raw frame > tagged frame (length-prefixed? no: one raw test)
  # live (root, vm-core-ran): started by pktlat2-taps.sh
  pktlat-mirror.py run --out-iface pktlat1 --ue tun_srsue --n3 lo --n6 ogstun --ue-netns ue1
"""
from __future__ import annotations

import argparse, os, select, socket, struct, sys

ETH_P_ALL = 0x0003
ETH_P_IP = 0x0800
ETH_P_IPV6 = 0x86DD
ETH_P_8021Q = 0x8100
VLAN = {"ue": 105, "n3": 102, "n6": 109}
SRC_MAC = b"\x02\x00\x00\x00\x00\x01"
DST_MAC = b"\x02\x00\x00\x00\x00\x02"


def _u16(b: bytes, o: int) -> int:
    return struct.unpack_from("!H", b, o)[0]


def encapsulate(frame: bytes, tap: str) -> bytes:
    """Return Ethernet + VLAN + IPv4/IPv6. Accept raw IP or Ethernet (+ optional VLAN).

    IPv6 fan-in is best-effort (app v0.10.1 forces IPv4 probes). Raw IPv6 TUN
    frames (version nibble 6) get ETH_P_IPV6; Ethernet IPv6 already had a tag path.
    """
    if tap not in VLAN:
        raise ValueError(f"tap must be ue|n3|n6, got {tap}")
    vid = VLAN[tap]
    if not frame:
        return frame
    # Raw IPv4 (TUN / ogstun) — IHL 5 is common; any IPv4 is handled below too.
    if frame[0] == 0x45:
        return DST_MAC + SRC_MAC + struct.pack("!HH", ETH_P_8021Q, (vid & 0xFFF)) + struct.pack("!H", ETH_P_IP) + frame
    # Raw IPv6 (TUN)
    if (frame[0] >> 4) == 6 and len(frame) >= 40:
        return DST_MAC + SRC_MAC + struct.pack("!HH", ETH_P_8021Q, (vid & 0xFFF)) + struct.pack("!H", ETH_P_IPV6) + frame
    if len(frame) < 14:
        return frame
    et = _u16(frame, 12)
    if et == ETH_P_8021Q:
        # replace VLAN id, keep PCP/DEI=0
        return frame[:14] + struct.pack("!H", vid & 0xFFF) + frame[16:]
    if et == ETH_P_IP or et == ETH_P_IPV6:
        return frame[:12] + struct.pack("!HH", ETH_P_8021Q, vid & 0xFFF) + frame[12:]
    # lo GTP sometimes delivered as raw IP even on "lo" depending on capture
    if frame[0] >> 4 == 4 and len(frame) >= 20:
        return DST_MAC + SRC_MAC + struct.pack("!HH", ETH_P_8021Q, (vid & 0xFFF)) + struct.pack("!H", ETH_P_IP) + frame
    return frame


def vlan_id(frame: bytes) -> int:
    if len(frame) >= 16 and _u16(frame, 12) == ETH_P_8021Q:
        return _u16(frame, 14) & 0xFFF
    return -1


def _open_packet(iface: str, netns: str | None = None) -> socket.socket:
    if netns:
        # Child is already in the netns when called from a forked helper.
        pass
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    s.bind((iface, 0))
    s.setblocking(False)
    return s


# Classic BPF (Ethernet/lo): accept only IPv4 UDP (non-fragment) with sport or dport 2152 (GTP-U).
# Without it the n3 socket on `lo` also receives the srsRAN ZMQ I/Q stream (~200 GB / 12 M pkts per lab session): the
# Python reader drops frames and pktlat2 reports miss:s1u for 20-45% of packets (v0.10.1 recheck).
# (code, jt, jf, k)
BPF_GTPU = [
    (0x28, 0, 0, 12),          # 0  ldh [12]
    (0x15, 0, 10, 0x0800),     # 1  jeq IPv4 else reject
    (0x30, 0, 0, 23),          # 2  ldb [23] (proto)
    (0x15, 0, 8, 17),          # 3  jeq UDP else reject
    (0x28, 0, 0, 20),          # 4  ldh [20] (flags/frag)
    (0x45, 6, 0, 0x1FFF),      # 5  jset frag offset -> reject
    (0xB1, 0, 0, 14),          # 6  ldxb 4*([14]&0xf)
    (0x48, 0, 0, 14),          # 7  ldh [x+14] sport
    (0x15, 2, 0, 2152),        # 8  jeq 2152 -> accept
    (0x48, 0, 0, 16),          # 9  ldh [x+16] dport
    (0x15, 0, 1, 2152),        # 10 jeq 2152 -> accept else reject
    (0x06, 0, 0, 262144),      # 11 accept
    (0x06, 0, 0, 0),           # 12 reject
]


def bpf_run(prog, frame: bytes) -> int:
    """Tiny classic-BPF interpreter (only the opcodes used above) for unit tests. Returns the ret value."""
    a = x = pc = 0
    while True:
        code, jt, jf, k = prog[pc]
        pc += 1
        if code == 0x28:
            a = _u16(frame, k) if k + 2 <= len(frame) else None
        elif code == 0x30:
            a = frame[k] if k < len(frame) else None
        elif code == 0x48:
            a = _u16(frame, x + k) if x + k + 2 <= len(frame) else None
        elif code == 0xB1:
            x = (frame[k] & 0xF) * 4 if k < len(frame) else None
        elif code == 0x15:
            pc += jt if a == k else jf
        elif code == 0x45:
            pc += jt if (a is not None and a & k) else jf
        elif code == 0x06:
            return k
        if a is None or x is None:
            return 0


def attach_gtpu_filter(sock: socket.socket) -> None:
    import ctypes
    n = len(BPF_GTPU)
    arr = (ctypes.c_ubyte * (8 * n))()
    for i, (c, jt, jf, k) in enumerate(BPF_GTPU):
        struct.pack_into("=HBBI", arr, 8 * i, c, jt, jf, k)
    prog = struct.pack("=H6xQ", n, ctypes.addressof(arr))
    sock.setsockopt(socket.SOL_SOCKET, 26, prog)  # SO_ATTACH_FILTER


def _enter_netns(name: str) -> None:
    fd = os.open(f"/var/run/netns/{name}", os.O_RDONLY)
    try:
        # Linux setns(2); CLONE_NEWNET = 0x40000000
        import ctypes
        if ctypes.CDLL("libc.so.6", use_errno=True).setns(fd, 0x40000000) != 0:
            raise OSError(ctypes.get_errno(), "setns")
    finally:
        os.close(fd)


def run_live(out_iface: str, ue: str, n3: str, n6: str, ue_netns: str, bpf_hint: bool = True) -> None:
    """Capture 3 taps and write VLAN-tagged frames to out_iface (veth peer)."""
    out = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    out.bind((out_iface, 0))
    socks = {}

    def add(tap, iface, netns=None):
        pid = os.fork() if netns else 0
        if netns and pid == 0:
            try:
                _enter_netns(netns)
                s = _open_packet(iface)
                # pipe frames to parent via a pre-created socketpair? simpler: child writes to out_iface
                # out_iface is in the host netns; after setns we cannot write to it.
                # So child must use a socketpair. Parent creates pairs first.
            except Exception as e:
                sys.stderr.write(f"ue netns capture failed: {e}\n")
                os._exit(1)
            # This branch is replaced below — see run_live_pipes.
            os._exit(0)
        if not netns:
            socks[tap] = (_open_packet(iface), iface)
        return pid

    # Host-netns taps
    socks["n3"] = (_open_packet(n3), n3)
    try:
        attach_gtpu_filter(socks["n3"][0])
    except Exception as e:  # keep running; _looks_gtpu() still filters in user space
        sys.stderr.write(f"pktlat-mirror: BPF attach failed ({e}); n3 unfiltered\n")
    socks["n6"] = (_open_packet(n6), n6)
    # UE tap in netns: socketpair + child
    r, w = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM)
    pid = os.fork()
    if pid == 0:
        r.close()
        out.close()
        for s, _ in socks.values():
            s.close()
        try:
            _enter_netns(ue_netns)
            s = _open_packet(ue)
            while True:
                try:
                    data = s.recv(65535)
                except BlockingIOError:
                    select.select([s], [], [])
                    continue
                if data:
                    w.send(data)
        except Exception as e:
            sys.stderr.write(f"pktlat-mirror ue: {e}\n")
            os._exit(1)
        os._exit(0)
    w.close()
    r.setblocking(False)
    socks["ue"] = (r, ue)

    sys.stderr.write(f"pktlat-mirror running -> {out_iface} ue={ue}@{ue_netns} n3={n3} n6={n6}\n")
    try:
        while True:
            ready, _, _ = select.select([s for s, _ in socks.values()], [], [], 1.0)
            for tap, (s, _) in list(socks.items()):
                if s not in ready:
                    continue
                try:
                    data = s.recv(65535)
                except BlockingIOError:
                    continue
                if not data:
                    continue
                # n3: only GTP-U (udp 2152) is useful; skip other lo noise
                if tap == "n3" and not _looks_gtpu(data):
                    continue
                tagged = encapsulate(data, tap)
                try:
                    out.send(tagged)
                except OSError as e:
                    sys.stderr.write(f"pktlat-mirror send: {e}\n")
    finally:
        os.kill(pid, 15)
        os.waitpid(pid, 0)


def _looks_gtpu(frame: bytes) -> bool:
    """True if Ethernet or IPv4 frame looks like UDP 2152."""
    off = 0
    if frame and frame[0] == 0x45:
        off = 0
    elif len(frame) >= 14:
        et = _u16(frame, 12)
        off = 14
        if et == ETH_P_8021Q:
            et = _u16(frame, 16)
            off = 18
        if et != ETH_P_IP:
            return False
    else:
        return False
    if len(frame) < off + 28 or frame[off + 9] != 17:
        return False
    ihl = (frame[off] & 15) * 4
    l4 = off + ihl
    if len(frame) < l4 + 4:
        return False
    return _u16(frame, l4) == 2152 or _u16(frame, l4 + 2) == 2152


def _read_pcap(path: str) -> list[bytes]:
    import struct as st
    pkts = []
    with open(path, "rb") as f:
        magic = f.read(4)
        if magic not in (b"\xd4\xc3\xb2\xa1", b"\xa1\xb2\xc3\xd4", b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d"):
            raise ValueError("not a pcap")
        le = magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1")
        ns = magic in (b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d")
        hdr = "<" if le else ">"
        f.read(20)  # rest of global header
        while True:
            h = f.read(16)
            if len(h) < 16:
                break
            ts_sec, ts_frac, incl, orig = st.unpack(hdr + "IIII", h)
            data = f.read(incl)
            if len(data) < incl:
                break
            pkts.append(data)
            _ = (ts_sec, ts_frac, orig, ns)
    return pkts


def _write_pcap(path: str, frames: list[bytes], linktype: int = 1) -> None:
    import struct as st, time
    with open(path, "wb") as f:
        f.write(st.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, linktype))
        for i, fr in enumerate(frames):
            f.write(st.pack("<IIII", i, 0, len(fr), len(fr)))
            f.write(fr)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("encode")
    e.add_argument("--in-raw", help="file with a single raw frame (or use --hex)")
    e.add_argument("--hex", help="raw frame as hex")
    e.add_argument("--tap", required=True, choices=list(VLAN))
    e.add_argument("--out")
    r = sub.add_parser("run")
    r.add_argument("--out-iface", required=True)
    r.add_argument("--ue", default="tun_srsue")
    r.add_argument("--n3", default="lo")
    r.add_argument("--n6", default="ogstun")
    r.add_argument("--ue-netns", default="ue1")
    v = sub.add_parser("vlan-of")
    v.add_argument("--hex", required=True)
    args = ap.parse_args(argv)
    if args.cmd == "encode":
        if args.hex:
            raw = bytes.fromhex(args.hex.replace(":", "").replace(" ", ""))
        elif args.in_raw:
            raw = open(args.in_raw, "rb").read()
        else:
            raw = sys.stdin.buffer.read()
        out = encapsulate(raw, args.tap)
        if args.out:
            open(args.out, "wb").write(out)
        sys.stdout.write(f"vlan={vlan_id(out)} len={len(out)} hex={out[:32].hex()}...\n" if len(out) > 32 else f"vlan={vlan_id(out)} len={len(out)} hex={out.hex()}\n")
        return 0
    if args.cmd == "vlan-of":
        raw = bytes.fromhex(args.hex.replace(":", "").replace(" ", ""))
        sys.stdout.write(f"{vlan_id(raw)}\n")
        return 0
    run_live(args.out_iface, args.ue, args.n3, args.n6, args.ue_netns)
    return 0


if __name__ == "__main__":
    sys.exit(main())
