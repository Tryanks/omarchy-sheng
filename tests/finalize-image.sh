#!/usr/bin/env bash
# Real ext4 regression: never fsck/shrink a busy, still-mounted release image.
set -euo pipefail
(( EUID == 0 )) || { echo 'Run as root on Linux.' >&2; exit 1; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
holder=''
cleanup() {
  if [[ -n $holder ]]; then kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true; fi
  mountpoint -q "$work/mount" && umount "$work/mount" || true
  rm -rf "$work"
}
trap cleanup EXIT
truncate -s 64M "$work/rootfs.img"
mkfs.ext4 -F -q "$work/rootfs.img"
mkdir "$work/mount"
mount -o loop "$work/rootfs.img" "$work/mount"
bash -c 'cd "$1"; exec sleep 120' bash "$work/mount" &
holder=$!
# Wait for the fixture to actually hold a cwd on this mount.
for _ in {1..50}; do
  [[ $(readlink "/proc/$holder/cwd") == "$work/mount" ]] && break
  sleep 0.02
done
[[ $(readlink "/proc/$holder/cwd") == "$work/mount" ]]
before=$(stat -c%s "$work/rootfs.img")
if bash "$repo/scripts/host/04-finalize-image.sh" "$work/rootfs.img" "$work/mount" > "$work/busy.log" 2>&1; then
  echo 'FAIL: finalized a busy image' >&2; exit 1
fi
mountpoint -q "$work/mount"
[[ $(stat -c%s "$work/rootfs.img") == "$before" ]]
grep -q 'Cannot unmount rootfs' "$work/busy.log"
echo 'PASS: busy image rejected without changing its size'
kill "$holder"
wait "$holder" 2>/dev/null || true
holder=''
bash "$repo/scripts/host/04-finalize-image.sh" "$work/rootfs.img" "$work/mount"
e2fsck -fn "$work/rootfs.img"
echo 'PASS: idle image unmounted, shrunk and verified clean'
