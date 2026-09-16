#!/usr/bin/env bash
# Run on an actual Omarchy rootfs (or in its native ARM64 chroot).
# Reproduce the environment that sudo gives the package-update helper.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ulimit -c 0
result=$(env -u XDG_RUNTIME_DIR bash "$repo/scripts/omarchy/verify.sh")
grep -q 'Omarchy ARM payload and runtime linkage verified.' <<< "$result"
echo 'PASS: post-update validation works with XDG_RUNTIME_DIR unset'
