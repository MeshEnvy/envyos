#!/usr/bin/env bash
# Publish a deployed EnvyOS distro release: stage, finalize, upload.
#
# Usage:
#   ./scripts/publish.sh [version] [--dry-run] [--no-tag]
#   ./scripts/publish.sh --stage [version]
#   ./scripts/publish.sh --finalize [version] [--no-tag]
#   ./scripts/publish.sh --upload [version]
#
# Workflow:
#   ./envyos publish --dry-run       # verify + list planned assets (no writes)
#   ./envyos publish stage           # copy flat files to build/releases/<distro>/
#   ./envyos publish finalize        # lock RELEASED_* + RELEASE_MANIFEST + git tag
#   ./envyos publish upload vX.Y.Z   # GitHub Release from staged files
#   ./envyos publish                 # stage + finalize + upload

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 [version] [--dry-run] [--no-tag]
       $0 --stage [version]
       $0 --finalize [version] [--no-tag]
       $0 --upload [version]

  Publish a shipped EnvyOS distro release (does not change ENVYOS_VERSIONS).

options:
  --dry-run       Verify and list planned assets; no file writes
  --stage         Copy flat release files to build/releases/<distro>/ + ASSETS
  --finalize      Lock release (RELEASED_*, manifest, git tag); requires prior stage
  --upload        Upload staged files to GitHub; requires prior finalize
  --no-tag        Skip git tag (finalize / full publish only)

examples:
  $0 --dry-run
  $0 --stage
  $0 --finalize
  $0 --upload v0.1.2
  $0                              # stage + finalize + upload
EOF
  exit 2
}

GIT_TAG=1
DRY_RUN=0
STAGE_ONLY=0
FINALIZE_ONLY=0
UPLOAD_ONLY=0
PUBLISH_VER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --stage)
      STAGE_ONLY=1
      shift
      ;;
    --finalize)
      FINALIZE_ONLY=1
      shift
      ;;
    --upload)
      UPLOAD_ONLY=1
      shift
      ;;
    --no-tag)
      GIT_TAG=0
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

action_count=$((DRY_RUN + STAGE_ONLY + FINALIZE_ONLY + UPLOAD_ONLY))
if [[ "$action_count" -gt 1 ]]; then
  echo "error: choose one of --dry-run, --stage, --finalize, --upload" >&2
  exit 1
fi

if [[ -z "$PUBLISH_VER" ]]; then
  if [[ "$UPLOAD_ONLY" -eq 1 ]]; then
    echo "error: upload requires a version (e.g. ./envyos publish upload v0.1.2)" >&2
    usage
  fi
  PUBLISH_VER="$(read_distro_version)" || usage
fi

publish_finalize() {
  local distro_ver=$1
  require_changelog_section "$distro_ver" || return 1
  append_released_distro "$distro_ver"
  lock_release_components "$distro_ver"
  if [[ "$GIT_TAG" -eq 1 ]]; then
    if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
      if git -C "$ROOT" rev-parse "$distro_ver" >/dev/null 2>&1; then
        echo "git tag:  $distro_ver already exists locally"
      else
        git -C "$ROOT" tag -a "$distro_ver" -m "EnvyOS $distro_ver distro release"
        echo "git tag:  $distro_ver (local)"
      fi
    fi
  fi
}

publish_stage_assets() {
  local distro_ver=$1
  local -a staged=()
  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    staged+=("$asset")
  done < <(collect_distro_release_assets "$distro_ver")
  for asset in "${staged[@]}"; do
    echo "stage:    $(basename "$asset")"
  done
  ((${#staged[@]} > 0)) || return 1
}

if [[ "$UPLOAD_ONLY" -eq 1 ]]; then
  is_released_distro "$PUBLISH_VER" || {
    echo "error: $PUBLISH_VER is not in RELEASED_DISTROS — run ./envyos publish finalize first" >&2
    exit 1
  }
  ensure_release_manifest_for_backfill "$PUBLISH_VER"
  ASSETS=()
  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    ASSETS+=("$asset")
  done < <(read_distro_release_asset_paths "$PUBLISH_VER")
  ((${#ASSETS[@]} > 0)) || exit 1
  for asset in "${ASSETS[@]}"; do
    echo "upload:   $(basename "$asset")"
  done
  publish_github_release "$PUBLISH_VER" "${ASSETS[@]}"
  exit 0
fi

if [[ "$FINALIZE_ONLY" -eq 1 ]]; then
  if is_released_distro "$PUBLISH_VER"; then
    echo "error: $PUBLISH_VER is already finalized (listed in RELEASED_DISTROS)" >&2
    exit 1
  fi
  [[ -f "$(release_assets_manifest_path "$PUBLISH_VER")" ]] || {
    echo "error: no staged release — run ./envyos publish stage first" >&2
    exit 1
  }
  echo "finalize: distro $PUBLISH_VER"
  publish_finalize "$PUBLISH_VER"
  echo ""
  echo "Done. Upload: ./envyos publish upload ${PUBLISH_VER}"
  exit 0
fi

if is_released_distro "$PUBLISH_VER" && [[ "$DRY_RUN" -eq 0 && "$STAGE_ONLY" -eq 0 ]]; then
  echo "error: $PUBLISH_VER is already finalized (listed in RELEASED_DISTROS)" >&2
  exit 1
fi

echo "publish:  distro $PUBLISH_VER"
list_envyos_versions | sed 's/^/  manifest /'

verify_release_components "$PUBLISH_VER"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  plan_distro_release "$PUBLISH_VER"
  echo ""
  echo "### Changelog"
  changelog_notes_for_distro "$PUBLISH_VER" 1 | sed 's/^/  /'
  echo ""
  echo "Dry run OK. Stage: ./envyos publish stage"
  echo "Promote CHANGELOG.md Unreleased to ## [${PUBLISH_VER}] before finalize."
  exit 0
fi

publish_stage_assets "$PUBLISH_VER"

if [[ "$STAGE_ONLY" -eq 1 ]]; then
  echo ""
  echo "Done. Inspect build/releases/${PUBLISH_VER}/, then: ./envyos publish finalize"
  exit 0
fi

publish_finalize "$PUBLISH_VER"

ASSETS=()
while IFS= read -r asset || [[ -n "$asset" ]]; do
  [[ -n "$asset" ]] || continue
  ASSETS+=("$asset")
done < <(read_distro_release_asset_paths "$PUBLISH_VER")
((${#ASSETS[@]} > 0)) || exit 1

publish_github_release "$PUBLISH_VER" "${ASSETS[@]}"

echo ""
echo "Done. Commit release changes. Bump distro when ready: ./envyos bump patch distro"
