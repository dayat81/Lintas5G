#!/bin/bash
# Sesi C runner (systemd-run, tahan putus SSH): reps -> STR -> GBR. Log: /var/log/lab5g/sesi-c-run.log
E=${1:?emu_ip}; S=/opt/lab5g/sesi-c
echo "RUN_START $(date -u +%FT%TZ)"
bash $S/p99-reps.sh $E 3
bash $S/str-test.sh $E
bash $S/gbr-test.sh $E
echo "RUN_END $(date -u +%FT%TZ)"
