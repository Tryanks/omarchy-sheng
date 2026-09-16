#!/usr/bin/env bash
# Upstream settings' scriptlet overwrites these on non-Apple ARM devices.
# Keep ALARM identity/authentication and the sheng Plymouth configuration.
set -euo pipefail
state=/var/lib/omarchy-sheng/settings-transaction
paths=(etc/os-release etc/nsswitch.conf etc/security/faillock.conf etc/plymouth/plymouthd.conf
  etc/skel/.config/hypr/monitors.lua etc/skel/.config/hypr/autostart.lua)
case "${1:-}" in
  save)
    # Do not replace the recovery copy if an earlier transaction was interrupted.
    [[ ! -d $state ]] || exit 0
    install -d -m700 "$state"
    for path in "${paths[@]}"; do
      if [[ -e /$path || -L /$path ]]; then
        cp -a --parents "/$path" "$state/"
      else
        printf '%s\n' "$path" >> "$state/absent"
      fi
    done
    ;;
  restore)
    [[ -d $state ]] || exit 0
    for path in "${paths[@]}"; do
      if [[ -e $state/$path || -L $state/$path ]]; then
        rm -f "/$path"
        cp -a "$state/$path" "/$path"
      elif [[ -f $state/absent ]] && grep -qxF "$path" "$state/absent"; then
        rm -f "/$path"
      fi
    done
    rm -rf "$state"
    ;;
  *) echo 'Usage: preserve-system.sh save|restore' >&2; exit 2 ;;
esac
