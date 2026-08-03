#!/usr/bin/env bash
# Lock a deployed EnvyOS release: mark immutable, zip artifacts, bump dev version.
#
# Usage:
#   ./scripts/lock.sh [version] [--no-tag]
#
#   version   Distro tag to lock (default: ENVYOS_VERSIONS distro). Use an explicit tag
#             when the fleet build used ./scripts/build-mota.sh vX.Y.Z override.
#
# Steps:
#   1. Append version to RELEASED_VERSIONS
#   2. Write build/motas/<ver>/.released marker
#   3. Create <ver>.zip at repo root (same layout as v0.1.0.zip)
#   4. Bump ENVYOS_VERSIONS, envycore/envyos/VERSION, motatool/Cargo.toml to next patch
#   5. Optionally git tag v<ver> (use --no-tag to skip)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 [version] [--no-tag]

  Lock a shipped EnvyOS release and advance the working version by one patch.

examples:
  $0 v0.1.1          # lock deployed v0.1.1, bump dev to v0.1.2
  $0                 # lock ENVYOS_VERSIONS distro, bump to next patch
  $0 v0.1.1 --no-tag # lock without creating a git tag
EOF
  exit 2
}

GIT_TAG=1
LOCK_VER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-tag)
      GIT_TAG=0
      shift
      ;;
    -h | --help)
      usage
      ;;
    v* | [0-9]*)
      [[ -z "$LOCK_VER" ]] || usage
      LOCK_VER="$(normalize_version "$1")" || usage
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$LOCK_VER" ]]; then
  LOCK_VER="$(read_distro_version)" || usage
fi

MOTA_DIR="$MOTAS_ROOT/$LOCK_VER"
[[ -d "$MOTA_DIR" ]] || {
  echo "error: $MOTA_DIR not found — build fleet motas before locking" >&2
  exit 1
}

if is_released_version "$LOCK_VER"; then
  echo "error: $LOCK_VER is already released (listed in RELEASED_VERSIONS)" >&2
  exit 1
fi

NEXT_VER="$(next_patch_version "$LOCK_VER")"

echo "locking:  $LOCK_VER"
echo "next dev: $NEXT_VER"

append_released_version "$LOCK_VER"
write_released_marker "$LOCK_VER"
ZIP="$(create_release_zip "$LOCK_VER")"
echo "zip:      $ZIP"

write_envyos_versions "$NEXT_VER"
write_firmware_version_file "$NEXT_VER"
write_motatool_cargo_version "$NEXT_VER"

echo ""
echo "ENVYOS_VERSIONS → $NEXT_VER"
list_envyos_versions | sed 's/^/  /'

if [[ "$GIT_TAG" -eq 1 ]]; then
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$ROOT" rev-parse "$LOCK_VER" >/dev/null 2>&1; then
      echo "git tag:  $LOCK_VER already exists — skipped"
    else
      git -C "$ROOT" tag -a "$LOCK_VER" -m "EnvyOS $LOCK_VER fleet release"
      echo "git tag:  $LOCK_VER (not pushed)"
    fi
  fi
fi

echo ""
echo "Done. Development version is $NEXT_VER — rebuild with ./scripts/build-mota.sh"
