#!/usr/bin/env bash
# envybot recipe — stage the host wheel from the sibling checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../scripts/version.sh
source "$ROOT/scripts/version.sh"

ver="$(read_envybot_version)" || {
  echo "error: envybot= not set in MANIFEST.json" >&2
  exit 1
}

verify_envybot_version_sync "${ver#v}" || exit 1
ensure_envybot_wheel "$ver"

echo "==> envybot done $ver"
echo "    $(envybot_bench_root "" "$ver")"
maybe_populate_distro_release
