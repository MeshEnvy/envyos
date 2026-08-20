#!/usr/bin/env bash
# Upstream PR registry checks — docs/upstream-prs.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: upstream-prs.sh check [vX.Y.Z]
       upstream-prs.sh list

  check   Fail if any upstreamable row for the release is not submitted/merged
  list    Print release sections and blocking rows

Registry: docs/upstream-prs.md
EOF
  exit 2
}

upstream_prs_check() {
  local distro_ver="${1:-}"
  if [[ -z "$distro_ver" ]]; then
    distro_ver="$(read_distro_version)" || {
      echo "error: pass vX.Y.Z or set distro= in ENVYOS_VERSIONS" >&2
      return 1
    }
  fi
  distro_ver="$(normalize_version "$distro_ver")" || return 1
  check_upstream_prs_for_distro "$distro_ver"
}

upstream_prs_list() {
  list_upstream_prs_blockers
}

case "${1:-}" in
  check)
    shift
    upstream_prs_check "${1:-}"
    ;;
  list)
    upstream_prs_list
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage
    ;;
esac
