#!/bin/bash
# Sesi C runner lanjutan setelah link ZMQ jatuh di rep 2: rep 1 valid dipertahankan, ulang rep 2-3, lalu STR dan GBR.
E=${1:?emu_ip}; S=/opt/lab5g/sesi-c
echo "RUN2_START $(date -u +%FT%TZ)"
bash $S/p99-reps.sh $E "2 3"
bash $S/str-test.sh $E
bash $S/gbr-test.sh $E
echo "RUN_END $(date -u +%FT%TZ)"
