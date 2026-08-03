#!/usr/bin/env bash
# Publish a deployed EnvyOS release: lock artifacts, zip, GitHub Release, bump dev version.
#
# Usage:
#   ./scripts/publish.sh [version] [--no-tag] [--no-release]
#   ./scripts/publish.sh --release-only [version]
#
#   version   Distro tag to publish (default: ENVYOS_VERSIONS distro). Use an explicit tag
#             when the fleet build used ./scripts/build-mota.sh vX.Y.Z override.
#
# Steps (default):
#   1. Append version to RELEASED_VERSIONS (immutable)
#   2. Write build/motas/<ver>/.released marker
#   3. Create <ver>.zip at repo root
#   4. Git tag v<ver>, push tag, publish GitHub Release with zip asset
#   5. Bump ENVYOS_VERSIONS, envycore/envyos/VERSION, motatool/Cargo.toml to next patch

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 [version] [--no-tag] [--no-release]
       $0 --release-only [version]

  Publish a shipped EnvyOS release and advance the working version by one patch.

options:
  --release-only  Re-upload GitHub Release for an already-published version
  --no-tag        Skip creating a local git tag
  --no-release    Skip GitHub Release upload (zip is still created)

examples:
  $0 v0.1.2                 # publish, tag, GitHub release, bump dev to v0.1.3
  $0                          # publish ENVYOS_VERSIONS distro
  $0 --release-only v0.1.0    # backfill GitHub release asset only
  $0 v0.1.2 --no-release      # lock + zip locally without GitHub upload
EOF
  exit 2
}

GIT_TAG=1
GITHUB_RELEASE=1
RELEASE_ONLY=0
PUBLISH_VER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-tag)
      GIT_TAG=0
      shift
      ;;
    --no-release)
      GITHUB_RELEASE=0
      shift
      ;;
    --release-only)
      RELEASE_ONLY=1
      shift
      ;;
    -h | --help)
      usage
      ;;
    v* | [0-9]*)
      [[ -z "$PUBLISH_VER" ]] || usage
      PUBLISH_VER="$(normalize_version "$1")" || usage
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$PUBLISH_VER" ]]; then
  if [[ "$RELEASE_ONLY" -eq 1 ]]; then
    echo "error: --release-only requires a version" >&2
    usage
  fi
  PUBLISH_VER="$(read_distro_version)" || usage
fi

if [[ "$RELEASE_ONLY" -eq 1 ]]; then
  is_released_version "$PUBLISH_VER" || {
    echo "error: $PUBLISH_VER is not in RELEASED_VERSIONS — publish it first" >&2
    exit 1
  }
  MOTA_DIR="$MOTAS_ROOT/$PUBLISH_VER"
  [[ -d "$MOTA_DIR" ]] || {
    echo "error: $MOTA_DIR not found" >&2
    exit 1
  }
  ZIP="$(release_zip_path "$PUBLISH_VER")"
  if [[ ! -f "$ZIP" ]]; then
    ZIP="$(create_release_zip "$PUBLISH_VER")"
    echo "zip:      $ZIP"
  else
    echo "zip:      $ZIP (existing)"
  fi
  if [[ "$GITHUB_RELEASE" -eq 1 ]]; then
    publish_github_release "$PUBLISH_VER" "$ZIP"
  fi
  exit 0
fi

MOTA_DIR="$MOTAS_ROOT/$PUBLISH_VER"
[[ -d "$MOTA_DIR" ]] || {
  echo "error: $MOTA_DIR not found — build fleet motas before publishing" >&2
  exit 1
}

if is_released_version "$PUBLISH_VER"; then
  echo "error: $PUBLISH_VER is already published (listed in RELEASED_VERSIONS)" >&2
  exit 1
fi

NEXT_VER="$(next_patch_version "$PUBLISH_VER")"

echo "publish:  $PUBLISH_VER"
echo "next dev: $NEXT_VER"

append_released_version "$PUBLISH_VER"
write_released_marker "$PUBLISH_VER"
ZIP="$(create_release_zip "$PUBLISH_VER")"
echo "zip:      $ZIP"

write_envyos_versions "$NEXT_VER"
write_firmware_version_file "$NEXT_VER"
write_motatool_cargo_version "$NEXT_VER"

echo ""
echo "ENVYOS_VERSIONS → $NEXT_VER"
list_envyos_versions | sed 's/^/  /'

if [[ "$GIT_TAG" -eq 1 ]]; then
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$ROOT" rev-parse "$PUBLISH_VER" >/dev/null 2>&1; then
      echo "git tag:  $PUBLISH_VER already exists locally"
    else
      git -C "$ROOT" tag -a "$PUBLISH_VER" -m "EnvyOS $PUBLISH_VER fleet release"
      echo "git tag:  $PUBLISH_VER (local)"
    fi
  fi
fi

if [[ "$GITHUB_RELEASE" -eq 1 ]]; then
  publish_github_release "$PUBLISH_VER" "$ZIP"
fi

echo ""
echo "Done. Commit release changes, then rebuild dev at $NEXT_VER:"
echo "  ./scripts/build-mota.sh"
