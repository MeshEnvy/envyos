#!/usr/bin/env bash
# GUCP checks — docs/good-upstream-contributor-policy.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: gucp.sh check [vX.Y.Z]
       gucp.sh list
       gucp.sh audit [vX.Y.Z] [N]

  check   Fail if any upstreamable row for the release is not submitted/merged
  list    Print release sections and blocking rows
  audit   Show candidate/extracting rows + last N envycore commits (default 20)

Policy: docs/good-upstream-contributor-policy.md (GUCP)
EOF
  exit 2
}

gucp_check() {
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

gucp_list() {
  list_upstream_prs_blockers
}

gucp_audit() {
  audit_gucp "${1:-}" "${2:-20}"
}

case "${1:-}" in
  check)
    shift
    gucp_check "${1:-}"
    ;;
  list)
    gucp_list
    ;;
  audit)
    shift
    gucp_audit "${1:-}" "${2:-20}"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage
    ;;
esac
