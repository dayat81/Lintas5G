# Emulator TAP networking baseline (20 Nov 2026)

Goal: Ookla inside the Android emulator on the lab VM above 100 Mbps. SLIRP (the emulator's default user-mode net) caps at ~80-86 Mbps.

## Numbers (FAKTA, measured)
| Path | Result |
|---|---|
| SLIRP, guest <- local server in container (nc) | 80-86 Mbps, QEMU `MainLoopThread` at 99.9% CPU |
| SLIRP, Ookla in emulator (Jakarta server) | DL 55.8-63.5 / UL 12.8-32.3 Mbps (user's own run: 52) |
| TAP, guest <- host 10.0.2.2 (nc) | 1414 Mbps |
| TAP, Ookla run 1 | DL 1913 / UL 344 Mbps |
| TAP, Ookla run 2 | DL 2005 / UL 413 Mbps |
| Host (vm-emu itself), Ookla CLI to Jakarta servers | ~860-950 Mbps |
Ookla's server sat inside the same cloud region area, so these numbers show the emulator path, not 5G. VM: n2-standard-8, emulator 6 cores / 8 GB, swiftshader.

## Reproduce
1. Terraform: `terraform apply -var-file=pixel.tfvars $(cat targets)` (emulator VM only, no core; `gui_session=false`).
2. Build image on the VM: `EMU_API=36 EMU_IMG_TYPE=google_apis_playstore bash emu-image-build.sh` (from the lab VNC package).
3. `01-host-tap.sh`, then `02-emulator-container.sh`, then `03-keepalive-and-apks.sh`.
4. Measure: `local-throughput.sh` (python http server on 10.0.2.2), `ot.sh <tag>` / `r.sh <tag>` for Ookla via UI automation (`d.sh` helper).

## Cautions
- Never run `sysctl --system` on the VM: it reset `net.ipv4.ip_forward` to 0 and cut emulator internet. Use `sysctl -w`.
- The Play Store image has no `adb root`: a second NIC (eth1) cannot be configured. Use `-net-tap` so the TAP replaces the main NIC (eth0, static 10.0.2.15, gw 10.0.2.2, dns 10.0.2.3).
- Disable the guest Wi-Fi (`svc wifi disable`): wlan0 still uses SLIRP and hijacks 10.0.2.x routes.
- `--network host` exposes 5900/6080/5555 on all interfaces: keep the INPUT DROP rule, reach noVNC only via loopback + tunnel.
- The AVD (and any Google login) lives in the container layer: `docker commit` before recreating, never `-wipe-data`.
- `docker-android` deletes the root line of /etc/passwd on start; restore it (done in step 2) after a commit or restart.
- Ookla shows a "Never miss a result" dialog and ads: dismiss before starting (`ot.sh` does).
- Tap/iptables/dnsmasq are not persistent across VM reboot.
- Next (5G): same TAP design, then route tap0 into the UE netns via GRE (see DESIGN-5g-tcp-direct.md).
