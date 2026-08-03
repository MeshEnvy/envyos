#!/usr/bin/env bash
# Publish a deployed EnvyOS distro release: lock all components, zip, GitHub Release, bump dev.
#
# Usage:
#   ./scripts/publish.sh [version] [--no-tag] [--no-release]
#   ./scripts/publish.sh --release-only [version]
#
# Each distro release bundles firmware (motas), bootloader (OTAFIX), and motatool at the
# versions in ENVYOS_VERSIONS. Run ./scripts/build.sh before publishing.
#
# Steps (default):
#   1. Verify all component trees exist (motas, bootloader, motatool)
#   2. Verify delta matrix for firmware
#   3. Lock RELEASED_VERSIONS + .released markers + RELEASE_MANIFEST
#   4. Zip each component → firmware-<ver>.zip, bootloader-<ver>.zip, motatool-<ver>.zip
#   5. Git tag v<ver>, push tag, GitHub Release with all assets
#   6. Bump ENVYOS_VERSIONS and submodule version files to next patch

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 [version] [--no-tag] [--no-release]
       $0 --release-only [version]

  Publish a shipped EnvyOS distro release and advance all component versions by one patch.

options:
  --release-only  Re-upload GitHub Release assets for an already-published distro
  --no-tag        Skip creating a local git tag
  --no-release    Skip GitHub Release upload (zips are still created)

examples:
  $0 v0.1.2                 # publish all components, bump dev to v0.1.3
  $0                          # publish ENVYOS_VERSIONS distro
  $0 --release-only v0.1.0    # backfill GitHub release assets
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
  ensure_release_manifest_for_backfill "$PUBLISH_VER"
  ASSETS=()
  while IFS= read -r zip || [[ -n "$zip" ]]; do
    [[ -n "$zip" ]] || continue
    ASSETS+=("$zip")
  done < <(collect_distro_release_assets "$PUBLISH_VER")
  for zip in "${ASSETS[@]}"; do
    echo "zip:      $zip"
  done
  if [[ "$GITHUB_RELEASE" -eq 1 ]]; then
    publish_github_release "$PUBLISH_VER" "${ASSETS[@]}"
  fi
  exit 0
fi

if is_released_version "$PUBLISH_VER"; then
  echo "error: $PUBLISH_VER is already published (listed in RELEASED_VERSIONS)" >&2
  exit 1
fi

NEXT_VER="$(next_patch_version "$PUBLISH_VER")"

echo "publish:  $PUBLISH_VER"
echo "next dev: $NEXT_VER"
list_envyos_versions | sed 's/^/  manifest /'

verify_release_components "$PUBLISH_VER"

append_released_version "$PUBLISH_VER"
lock_release_components "$PUBLISH_VER"

ASSETS=()
while IFS= read -r zip || [[ -n "$zip" ]]; do
  [[ -n "$zip" ]] || continue
  ASSETS+=("$zip")
done < <(collect_distro_release_assets "$PUBLISH_VER")
for zip in "${ASSETS[@]}"; do
  echo "zip:      $zip"
done

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
      git -C "$ROOT" tag -a "$PUBLISH_VER" -m "EnvyOS $PUBLISH_VER distro release"
      echo "git tag:  $PUBLISH_VER (local)"
    fi
  fi
fi

if [[ "$GITHUB_RELEASE" -eq 1 ]]; then
  publish_github_release "$PUBLISH_VER" "${ASSETS[@]}"
fi

echo ""
echo "Done. Commit release changes, then rebuild dev at $NEXT_VER:"
echo "  ./scripts/build.sh"
