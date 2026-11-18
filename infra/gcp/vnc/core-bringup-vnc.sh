#!/bin/bash
# Deprecated (18 Nov 2026 session): replaced by gui-core-up.sh (no QoD/HTB shaping, MTU/MSS fix, watchdog, collector).
exec bash "$(dirname "$0")/gui-core-up.sh" "$@"
