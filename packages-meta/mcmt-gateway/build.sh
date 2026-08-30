#!/usr/bin/env bash
# mcmt-gateway recipe — stage the host wheel from packages/mcmt-gateway.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../scripts/version.sh
source "$ROOT/scripts/version.sh"

ver="$(read_mcmt_gateway_version)" || {
  echo "error: mcmt-gateway= not set in MANIFEST.json" >&2
  exit 1
}

verify_mcmt_gateway_version_sync "${ver#v}" || exit 1
ensure_mcmt_gateway_wheel "$ver"

echo "==> mcmt-gateway done $ver"
echo "    $(mcmt_gateway_bench_root "" "$ver")"
maybe_populate_distro_release
