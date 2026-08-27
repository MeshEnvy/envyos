#!/usr/bin/env bash
# Remove per-repo EnvyOS package harness from packages/* workbenches.
# Version/changelog/release identity lives in packages-meta/; builds use ./envyos at distro root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES_ROOT="${PACKAGES_ROOT:-$ROOT/packages}"

remove_file() {
  local path=$1
  if [[ -e "$path" ]]; then
    rm -rf "$path"
    echo "removed ${path#"$PACKAGES_ROOT/"}"
  fi
}

demote_pkg() {
  local pkg=$1
  local dir="$PACKAGES_ROOT/$pkg"
  if [[ ! -d "$dir" ]]; then
    echo "skip $pkg (no checkout under packages/)"
    return 0
  fi
  echo "=== $pkg ==="
  local rel=(
    envyos
    VERSION
    CHANGELOG.md
    RELEASED_VERSIONS
    RELEASED
    BACKLOG.md
    FRESHEN.lock
    scripts/envyos
    scripts/prepare.sh
    scripts/publish.sh
    scripts/package-lib.sh
    scripts/changelog.sh
    scripts/version.sh
    scripts/build.sh
    scripts/build-mota.sh
  )
  local f
  for f in "${rel[@]}"; do
    remove_file "$dir/$f"
  done
}

for pkg in meshcore motatool bootloader; do
  demote_pkg "$pkg"
done

echo "demote-package-harness: done"
