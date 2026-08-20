#!/usr/bin/env bash
# Change-management gate — docs/change-management.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: changelog.sh check [vX.Y.Z]
       changelog.sh delta [vX.Y.Z]

  check   Fail unless the release section has a Packages table and every
          bumped package has a matching section in its package changelog
  delta   Print package version deltas (previous release → this release)

Policy: docs/change-management.md
EOF
  exit 2
}

resolve_ver() {
  local ver="${1:-}"
  if [[ -z "$ver" ]]; then
    ver="$(read_distro_version)" || {
      echo "error: pass vX.Y.Z or set distro= in ENVYOS_VERSIONS" >&2
      return 1
    }
  fi
  normalize_version "$ver"
}

case "${1:-}" in
  check)
    shift
    ver="$(resolve_ver "${1:-}")" || exit 1
    check_changelog_packages_for_distro "$ver"
    ;;
  delta)
    shift
    ver="$(resolve_ver "${1:-}")" || exit 1
    echo "package deltas for $ver:"
    while IFS=$'\t' read -r id prev_ver new_ver state; do
      printf '  %-12s %s → %s  (%s)\n' "$id" "$prev_ver" "$new_ver" "$state"
    done < <(changelog_package_delta "$ver")
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage
    ;;
esac
