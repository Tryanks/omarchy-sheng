#!/usr/bin/env bash
# gpio-keys also reports tablet mode: confirm SW_LID through logind first.
# Both switch edges call this helper. Opening the cover never unlocks it.
set -euo pipefail
case "${1:-}" in close|open) ;; *) exit 2 ;; esac
expected=false
[[ $1 != close ]] || expected=true
for _attempt in 1 2 3 4 5; do
  state=$(timeout 1s busctl get-property org.freedesktop.login1 \
    /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed) || exit 1
  [[ $state == "b $expected" ]] && break
  sleep 0.1
done
[[ $state == "b $expected" ]] || exit 0
if [[ $1 == close ]]; then
  # Reuse the bounded secure-lock check without requesting system sleep.
  omarchy-system-sleep-lock
  # A quick reopen can happen while the compositor is securing the session.
  state=$(timeout 1s busctl get-property org.freedesktop.login1 \
    /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed) || exit 1
  if [[ $state == "b true" ]]; then
    omarchy-brightness-keyboard off
    omarchy-brightness-display off
  else
    omarchy-system-wake
  fi
else
  omarchy-system-wake
fi
