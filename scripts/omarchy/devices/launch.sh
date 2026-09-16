#!/usr/bin/env bash
set -euo pipefail
case "${1:-pen}" in
  pen|fingerprint) view=${1:-pen} ;;
  *) echo 'Usage: omarchy-sheng-devices [pen|fingerprint]' >&2; exit 2 ;;
esac
exec omarchy-shell shell summon sheng.devices "{\"view\":\"$view\"}"
