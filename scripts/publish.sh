#!/usr/bin/env bash
# Publish a deployed EnvyOS distro release: promote branch bench → version tree, lock, GitHub Release.
#
# Usage:
#   ./scripts/publish.sh [version] [--yes] [--dry-run] [--no-tag] [--no-release]
#   --dry-run writes build/<slot>/release/RELEASE.md (GitHub notes + upload asset).
#   ./scripts/publish.sh --release-only [version]
#
# Dev builds live under build/<branch>/bench/. Publish copies to build/<vX.Y.Z>/, locks, and uploads.
# Without [version], suggests the next tag from CHANGELOG + bundle policy (see docs/distro-semver.md).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 [version] [--yes] [--dry-run] [--no-tag] [--no-release]
       $0 --release-only [version]

  Publish a shipped EnvyOS distro release (promotes branch bench; locks artifacts).

options:
  --yes           Accept changelog-suggested version without prompting
  --dry-run       Print plan + write RELEASE.md (no promote/lock/upload)
  --release-only  Re-upload GitHub Release assets for an already-published distro
  --no-tag        Skip creating a local git tag
  --no-release    Skip GitHub Release upload (stage dir is still built)

examples:
  $0                          # suggest tag, prompt, promote, publish
  $0 v0.1.3 --yes             # publish explicit tag
  $0 --dry-run                # plan, pins, write RELEASE.md (no promote/upload)
  $0 --release-only v0.1.0    # backfill GitHub release assets
EOF
  exit 2
}

GIT_TAG=1
GITHUB_RELEASE=1
RELEASE_ONLY=0
AUTO_YES=0
DRY_RUN=0
PUBLISH_VER=""
BUILD_SLOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      AUTO_YES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
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

BUILD_SLOT="$(read_build_slot)"

resolve_publish_version() {
  local proposed input
  if [[ -n "$PUBLISH_VER" ]]; then
    return 0
  fi
  if [[ "$RELEASE_ONLY" -eq 1 ]]; then
    echo "error: --release-only requires a version" >&2
    usage
  fi
  if ((DRY_RUN == 1)); then
    proposed="$(propose_next_distro_version)"
    print_distro_publish_plan "$proposed" "$BUILD_SLOT" "$GIT_TAG" "$GITHUB_RELEASE" || true
    exit 0
  fi
  echo "Build slot: $BUILD_SLOT"
  print_distro_bump_summary
  proposed="$(propose_next_distro_version)"
  if ((AUTO_YES == 1)) || [[ ! -t 0 ]]; then
    PUBLISH_VER="$proposed"
    echo "Using: $PUBLISH_VER"
    return 0
  fi
  read -r -p "Publish version [$proposed]: " input
  PUBLISH_VER="$(normalize_version "${input:-$proposed}")" || usage
}

if [[ -z "$PUBLISH_VER" ]]; then
  resolve_publish_version
elif ((DRY_RUN == 1)); then
  print_distro_publish_plan "$PUBLISH_VER" "$BUILD_SLOT" "$GIT_TAG" "$GITHUB_RELEASE" || true
  exit 0
fi

if [[ "$RELEASE_ONLY" -eq 1 ]]; then
  is_released_version "$PUBLISH_VER" || {
    echo "error: $PUBLISH_VER is not in MANIFEST.json releases — publish it first" >&2
    exit 1
  }
  ensure_release_manifest_for_backfill "$PUBLISH_VER"
  ASSETS=()
  while IFS= read -r zip || [[ -n "$zip" ]]; do
    [[ -n "$zip" ]] || continue
    ASSETS+=("$zip")
  done < <(collect_distro_release_assets "$PUBLISH_VER")
  for zip in "${ASSETS[@]}"; do
    echo "asset:    $zip"
  done
  if [[ "$GITHUB_RELEASE" -eq 1 ]]; then
    publish_github_release "$PUBLISH_VER" "${ASSETS[@]}"
  fi
  exit 0
fi

if is_published_distro_tag "$PUBLISH_VER"; then
  echo "error: $PUBLISH_VER is already published (git tag or MANIFEST.json releases)" >&2
  exit 1
fi

echo "publish:  $PUBLISH_VER  (from slot $BUILD_SLOT)"
list_manifest | sed 's/^/  manifest /'

promote_bench_to_release_tree "$BUILD_SLOT" "$PUBLISH_VER"
populate_distro_release "$PUBLISH_VER"

verify_release_packages "$PUBLISH_VER"

append_released_version "$PUBLISH_VER"
lock_release_packages "$PUBLISH_VER"

ASSETS=()
while IFS= read -r zip || [[ -n "$zip" ]]; do
  [[ -n "$zip" ]] || continue
  ASSETS+=("$zip")
done < <(collect_distro_release_assets "$PUBLISH_VER")
for zip in "${ASSETS[@]}"; do
  echo "zip:      $zip"
done

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
echo "Done. Commit release changes (MANIFEST.json, CHANGELOG)."
echo "Next dev cycle: keep building on branch slot build/$BUILD_SLOT/ — bump pins in releases.next as needed."
