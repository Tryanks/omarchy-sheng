#!/usr/bin/env bash
# Reviewed AUR tcode-bin recipe, packaged for pacman rather than unpacked in /opt.
set -euo pipefail
(( EUID == 0 )) || { echo 'Run as root.' >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { echo 'Native aarch64 required.' >&2; exit 1; }
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT
cp "$HERE/tcode/PKGBUILD" "$HERE/tcode/LICENSE" "$cache/"
if [[ -n ${TCODE_ARCHIVE:-} ]]; then
  cp "$TCODE_ARCHIVE" "$cache/tcode-0.1.52-linux-arm64.tar.gz"
fi
# No build scripts run as root. Dependencies are part of the image's package list.
chown -R nobody:nobody "$cache"
# $1 belongs to the unprivileged child shell.
# shellcheck disable=SC2016
runuser -u nobody -- env HOME="$cache" BUILDDIR="$cache" PKGDEST="$cache" \
  SRCDEST="$cache" bash -c 'cd "$1" || exit; makepkg --noconfirm --nocheck' bash "$cache"
mapfile -t packages < <(find "$cache" -maxdepth 1 -name 'tcode-bin-*.pkg.tar.*' ! -name '*.sig')
(( ${#packages[@]} == 1 )) || { echo 'Expected one tcode-bin package.' >&2; exit 1; }
pacman -U --noconfirm "${packages[0]}"
update-desktop-database /usr/share/applications
