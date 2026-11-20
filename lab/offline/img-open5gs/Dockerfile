# lintas5g/open5gs:2.8.0-qosrel = lab core (srs-lab snapshot: Open5GS 2.8.0~jammy5 + oaishim + lab configs) overlaid with
# Open5GS v2.8.0 rebuilt from source + UPF stale-QFI patch (patches/open5gs-v2.8.0-upf-stale-qfi.diff),
# pcf.yaml qos_profiles (CAMARA QOS_E/S/M/L/7) and /opt/lintas5g/core-up.sh. Single layer (box uses the vfs driver).
FROM lintas5g/n5-core-base:tmp
COPY overlay/ /
LABEL org.lintas5g.patch="open5gs v2.8.0 + upf-stale-qfi-no-error-indication"
CMD ["sleep","infinity"]
