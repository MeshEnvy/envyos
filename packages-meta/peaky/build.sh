#!/usr/bin/env bash
# peaky recipe — stage all peaky platform binaries from the release cache.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../scripts/version.sh
source "$ROOT/scripts/version.sh"

ver="$(read_peaky_version)" || {
  echo "error: peaky= not set in MANIFEST.json" >&2
  exit 1
}

verify_peaky_version_sync "${ver#v}" || exit 1
ensure_peaky_release_cache "$ver"

echo "==> peaky done $ver"
while IFS= read -r triple || [[ -n "$triple" ]]; do
  [[ -n "$triple" ]] || continue
  printf '    %s\n' "$(peaky_staged_binary_dir "$ver" "$triple")/peaky"
done < <(list_peaky_release_triples)
maybe_populate_distro_release
