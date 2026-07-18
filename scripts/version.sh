#!/usr/bin/env bash
# Version helpers for ota repo build scripts.
set -euo pipefail

OTA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$OTA_ROOT/VERSION"

# v0.1.0 or 0.1.0 → v0.1.0
normalize_version() {
  local v="${1#v}"
  if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid version '$1' (want vMAJOR.MINOR.PATCH)" >&2
    return 1
  fi
  printf 'v%s' "$v"
}

# Read canonical version from ota repo root VERSION file.
read_version_file() {
  [[ -f "$VERSION_FILE" ]] || {
    echo "error: missing $VERSION_FILE" >&2
    return 1
  }
  normalize_version "$(tr -d '[:space:]' <"$VERSION_FILE")"
}

# v0.1.1 → 0 1 1 (stdout: major minor patch)
parse_version() {
  local v="${1#v}"
  local major minor patch
  IFS=. read -r major minor patch <<<"$v"
  printf '%s %s %s' "$major" "$minor" "$patch"
}

# v0.1.1 → v0.1.0; v0.1.0 → (empty)
previous_patch_version() {
  local ver="$1"
  local major minor patch
  read -r major minor patch <<<"$(parse_version "$ver")"
  if [[ "$patch" -eq 0 ]]; then
    return 0
  fi
  printf 'v%s.%s.%s' "$major" "$minor" "$((patch - 1))"
}
