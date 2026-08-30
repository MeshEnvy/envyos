#!/usr/bin/env bash
# Distro changelog gate — pin sections must exist for bundled packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: changelog.sh check [vX.Y.Z]
       changelog.sh delta [vX.Y.Z]

  check   Distro Unreleased (or named tag) is non-empty, and each bundled
          package with a changelog has a section for its pin
  delta   Print package version deltas (last shipped → releases.next)
EOF
  exit 2
}

package_pin_for_check() {
  local pkg=$1
  case "$pkg" in
    meshcore | firmware) read_package_version meshcore ;;
    bootloader | adafruit-nrf52-bootloader) read_package_version adafruit-nrf52-bootloader ;;
    motatool) read_package_version motatool ;;
    peaky) read_optional_manifest_key peaky ;;
    envybot) read_optional_manifest_key envybot ;;
    mcmt-gateway) read_optional_manifest_key mcmt-gateway ;;
    *) return 1 ;;
  esac
}

cmd_check() {
  local distro_ver="${1:-}"
  local section file ver pkg
  if [[ -n "$distro_ver" ]]; then
    distro_ver="$(normalize_version "$distro_ver")"
    section="$(changelog_section_body "$distro_ver")"
    if ! changelog_text_nonempty "$section"; then
      section="$(changelog_section_body "v${distro_ver#v}")"
    fi
  else
    section="$(changelog_unreleased_body)"
    distro_ver="Unreleased"
  fi
  if ! changelog_text_nonempty "$section"; then
    echo "error: distro CHANGELOG.md missing or empty ## [$distro_ver]" >&2
    exit 1
  fi
  echo "changelog: distro $distro_ver OK"

  for pkg in meshcore adafruit-nrf52-bootloader motatool peaky envybot mcmt-gateway; do
    ver="$(package_pin_for_check "$pkg" 2>/dev/null || true)"
    [[ -n "$ver" ]] || continue
    file="$(package_overlay_changelog_file "$pkg")"
    [[ -n "$file" && -f "$file" ]] || continue
    grep -q '^## \[' "$file" || continue
    if ! changelog_version_section_body "$ver" "$file" >/dev/null; then
      echo "error: $file missing ## [$ver] / ## [v${ver#v}]" >&2
      exit 1
    fi
    echo "changelog: $pkg $ver OK ($file)"
  done
}

cmd_delta() {
  local last
  last="$(latest_released_distro_version 2>/dev/null || true)"
  echo "package deltas (last shipped ${last:-none} → next):"
  local pkg last_ver cur_ver
  for pkg in meshcore adafruit-nrf52-bootloader motatool peaky envybot mcmt-gateway; do
    last_ver=""
    cur_ver=""
    if [[ -n "$last" ]]; then
      last_ver="$(read_release_manifest_key "$last" "$pkg" 2>/dev/null || true)"
    fi
    cur_ver="$(package_pin_for_check "$pkg" 2>/dev/null || true)"
    [[ -n "$last_ver" || -n "$cur_ver" ]] || continue
    if [[ -z "$last_ver" ]]; then
      printf '  %-12s (new) → %s\n' "$pkg" "$cur_ver"
    elif [[ -z "$cur_ver" ]]; then
      printf '  %-12s %s → (dropped)\n' "$pkg" "$last_ver"
    elif [[ "$last_ver" == "$cur_ver" ]]; then
      printf '  %-12s %s\n' "$pkg" "$cur_ver"
    else
      printf '  %-12s %s → %s\n' "$pkg" "$last_ver" "$cur_ver"
    fi
  done
}

case "${1:-}" in
  check)
    shift
    cmd_check "${1:-}"
    ;;
  delta)
    shift
    cmd_delta
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage
    ;;
esac
