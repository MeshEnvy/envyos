#!/usr/bin/env bash
# Verify sibling component repos match releases.next SHAs in MANIFEST.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

verify_components_lock
