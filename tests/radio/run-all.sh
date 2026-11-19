#!/bin/bash
# Offline checks for the radio-uplift Fase 0 (no GCP, no terraform state): terraform validate in a throw-away copy
# with -backend=false, bash -n, shellcheck, python tests. Usage: tests/radio/run-all.sh   (env TERRAFORM=/path/terraform)
set -u; R=$(cd "$(dirname "$0")/../.." && pwd); TF=${TERRAFORM:-terraform}; rc=0
PATH=$PATH:$HOME/.local/bin
echo "== bash -n"; for f in "$R"/infra/gcp/sa/*.sh "$R"/infra/gcp/sesi-d/zeek-taps.sh; do bash -n "$f" || rc=1; done
echo "== shellcheck"; if command -v shellcheck >/dev/null; then shellcheck -S warning "$R"/infra/gcp/sa/nr-*.sh "$R"/infra/gcp/sa/zmq-pair-lib.sh "$R"/infra/gcp/sa/sa-run.sh "$R"/infra/gcp/sa/core-load-ueransim.sh "$R"/infra/gcp/sa/sa-up.sh "$R"/infra/gcp/sa/oai-*.sh "$R"/infra/gcp/sesi-d/zeek-taps.sh || rc=1; else echo "shellcheck missing"; rc=1; fi
echo "== python tests"; python3 -m unittest discover -s "$R/tests/radio" -p 'test_*.py' || rc=1
echo "== terraform validate (copy, -backend=false)"
T=$(mktemp -d); mkdir -p "$T/infra/gcp"; cp -r "$R/infra/gcp/terraform" "$R/infra/gcp/startup" "$R/infra/gcp/sa" "$T/infra/gcp/" 2>/dev/null
for d in vnc sesi-a sesi-b sesi-c sesi-d day1 scripts prebuild; do cp -r "$R/infra/gcp/$d" "$T/infra/gcp/" 2>/dev/null; done
( cd "$T/infra/gcp/terraform" && rm -f terraform.tfstate* terraform.tfvars && $TF init -backend=false -input=false >/dev/null && $TF fmt -check && $TF validate ) || rc=1
for a in "emu_enabled=false" "nr_pairs=3" "nr_pairs=4" ; do ( cd "$T/infra/gcp/terraform" && echo 'local.vcpu_total' | $TF console -var project_id=x -var enable_obs=false $( [ "${a%=*}" = nr_pairs ] && echo "-var ran_mode=sa-srsran" ) -var "$a" >/dev/null 2>&1 ) || { echo "console $a failed"; rc=1; }; done
( cd "$T/infra/gcp/terraform" && echo 'var.nr_pairs' | $TF console -var project_id=x -var nr_pairs=5 2>&1 ) | grep -q "nr_pairs harus" || { echo "nr_pairs=5 not rejected"; rc=1; }
( cd "$T/infra/gcp/terraform" && echo 'local.vcpu_total' | $TF console -var project_id=x -var core_machine_type=n2-standard-8 -var emu_machine_type=n2-standard-4 -var enable_obs=false 2>&1 ) | grep -qx 12 || { echo "8+4 != 12 vCPU"; rc=1; }
# core platform default: Ice Lake for sa-srsran (radio), GCP default otherwise, "" forces GCP default
pf() { ( cd "$T/infra/gcp/terraform" && echo 'local.core_cpu_platform == null ? "NULL" : local.core_cpu_platform' | $TF console -var project_id=x "$@" 2>&1 | tr -d '"' ); }
[ "$(pf -var ran_mode=sa-srsran)" = "Intel Ice Lake" ] || { echo "sa-srsran platform != Ice Lake"; rc=1; }
[ "$(pf)" = NULL ] || { echo "default ran_mode platform not GCP default"; rc=1; }
[ "$(pf -var ran_mode=sa-srsran -var core_min_cpu_platform=)" = NULL ] || { echo "\"\" does not force GCP default"; rc=1; }
# sa-oai: Ice Lake auto, images pinned by digest, metadata only for sa-oai
[ "$(pf -var ran_mode=sa-oai)" = "Intel Ice Lake" ] || { echo "sa-oai platform != Ice Lake"; rc=1; }
( cd "$T/infra/gcp/terraform" && echo 'var.oai_gnb_image' | $TF console -var project_id=x -var oai_gnb_image=oai-gnb:latest 2>&1 ) | grep -q "dipin dengan @sha256" || { echo "unpinned oai image not rejected"; rc=1; }
( cd "$T/infra/gcp/terraform" && echo 'var.ran_mode' | $TF console -var project_id=x -var ran_mode=sa-oai 2>&1 ) | grep -q sa-oai || { echo "ran_mode=sa-oai rejected"; rc=1; }
rm -rf "$T"; [ $rc = 0 ] && echo "ALL OK" || echo "FAILED"; exit $rc
