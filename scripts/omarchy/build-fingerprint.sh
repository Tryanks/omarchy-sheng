#!/usr/bin/env bash
# Optional native ARM64 build; does not install or restart the device service.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:?usage: build-fingerprint.sh OUTPUT_DIRECTORY}
mkdir -p "$output"
output=$(cd "$output" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone -q https://github.com/ianchb/xiaomi-sheng-fingerprint.git "$work/source"
git -C "$work/source" checkout -q 76e7301163b0e708f609c9864b3e5833e9f57402
# Add our driver patch after the pinned upstream patch has been applied.
python3 - "$work/source/scripts/build-libfprint.sh" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
anchor = '    < "$REPO_DIR/patches/libfprint/0001-libfprint-add-fpc1553.patch"\n'
assert s.count(anchor) == 1
p.write_text(s.replace(anchor, anchor + 'patch -d "$WORK_DIR/src" -p1 < "$FPC1553_MATCH_PATCH"\npython3 "$FPC1553_MATCH_TEST" "$WORK_DIR/src/libfprint/drivers/fpc1553.c"\n'))
PY
export FPC1553_MATCH_PATCH="$root/patches/fpc1553-report-match-immediately.patch"
export FPC1553_MATCH_TEST="$root/tests/fingerprint-driver.py"
make -C "$work/source" check
bash "$work/source/scripts/build-backend.sh" "$work/backend"
bash "$work/source/scripts/build-libfprint.sh" "$work/backend" "$output"
sha256sum "$output/libfprint-2.so.2.0.0"
