#!/usr/bin/env bash
# Restore released EnvyBoot trees under build/bootloader/<ver>/ from GitHub Releases.
#
# Usage:
#   ./scripts/restore-bootloader.sh                  # all RELEASED_BOOTLOADER versions
#   ./scripts/restore-bootloader.sh v0.1.0
#   ./scripts/restore-bootloader.sh --force v0.1.0
#
# Legacy releases: bootloader-vX.Y.Z.zip (per-distro upload on early releases).
# Flat releases: bl-<board>-vX.Y.Z.uf2 + bl-<board>-recovery-vX.Y.Z.zip on distro tags.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

FORCE=0
SELECTED=()

usage() {
  cat >&2 <<EOF
usage: $0 [--force] [vX.Y.Z]…

  (default)     Restore every version listed in RELEASED_BOOTLOADER
  vX.Y.Z        Restore one or more explicit bootloader versions
  --force       Re-download and replace existing trees

Requires: gh (GitHub CLI), unzip
EOF
  exit 2
}

require_gh() {
  command -v gh >/dev/null 2>&1 || {
    echo "error: gh not found (install GitHub CLI)" >&2
    exit 1
  }
  gh auth status >/dev/null 2>&1 || {
    echo "error: gh not authenticated (run: gh auth login)" >&2
    exit 1
  }
}

release_has_asset() {
  local tag="$1"
  local pattern="$2"
  gh release view "$tag" --json assets --jq '.assets[].name' 2>/dev/null | grep -qxF "$pattern"
}

bootloader_tree_present() {
  local ver="$1"
  local dir="$BOOTLOADER_ROOT/$ver"
  [[ -d "$dir" ]] || return 1
  local n
  n="$(find "$dir" -maxdepth 1 -name '*_bootloader-*.uf2' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$n" -gt 0 ]]
}

release_board_slug_to_otafix_board() {
  case "$1" in
    wismesh-tag) printf '%s' wismesh_tag ;;
    wiscore-rak4631-board | rak4631) printf '%s' rak4631 ;;
    sensecap-solar-p1) printf '%s' sensecap_solar_p1 ;;
    *) tr '-' '_' <<<"$1" ;;
  esac
}

flat_asset_to_build_name() {
  local asset="$1"
  local bl_ver="$2"
  local base="${asset%.uf2}"
  base="${base%.zip}"
  local ver_no_v="${bl_ver#v}"
  local slug board

  if [[ "$asset" == bl-*-recovery-${bl_ver}.zip ]]; then
    slug="${asset#bl-}"
    slug="${slug%-recovery-${bl_ver}.zip}"
    board="$(release_board_slug_to_otafix_board "$slug")"
    printf '%s_bootloader-%s.recovery.zip' "$board" "$ver_no_v"
    return 0
  fi

  if [[ "$asset" == bl-*-${bl_ver}.uf2 ]]; then
    slug="${asset#bl-}"
    slug="${slug%-${bl_ver}.uf2}"
    board="$(release_board_slug_to_otafix_board "$slug")"
    printf '%s_bootloader-%s.uf2' "$board" "$ver_no_v"
    return 0
  fi

  return 1
}

list_distro_tags_for_bootloader_restore() {
  local ver tmp=()
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    tmp+=("$ver")
  done < <(list_released_distros)
  # v0.1.2 shipped on GitHub with flat bl assets before RELEASED_DISTROS was updated.
  tmp+=(v0.1.2)
  sort_versions "${tmp[@]}"
}

restore_from_legacy_zip() {
  local bl_ver="$1"
  local tag="$2"
  local zip_name="bootloader-${bl_ver}.zip"
  local tmp dest_root

  echo "==> restore $bl_ver from $tag/$zip_name"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  gh release download "$tag" -p "$zip_name" -D "$tmp"
  unzip -q "$tmp/$zip_name" -d "$tmp/extract"
  dest_root="$BOOTLOADER_ROOT/$bl_ver"
  mkdir -p "$dest_root"

  if [[ -d "$tmp/extract/$bl_ver" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      rm -rf "$dest_root"
      mkdir -p "$dest_root"
    fi
    cp -a "$tmp/extract/$bl_ver/." "$dest_root/"
  else
    echo "error: $zip_name missing top-level $bl_ver/ directory" >&2
    return 1
  fi

  printf '%s\n' "$bl_ver" >"$dest_root/version.txt"
  echo "    → $dest_root/"
  ls -la "$dest_root"
}

restore_from_flat_release() {
  local bl_ver="$1"
  local tag="$2"
  local out="$BOOTLOADER_ROOT/$bl_ver"
  local tmp asset local_name downloaded=0

  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  mkdir -p "$out"
  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    [[ "$asset" == bl-*-${bl_ver}.uf2 || "$asset" == bl-*-recovery-${bl_ver}.zip ]] || continue
    local_name="$(flat_asset_to_build_name "$asset" "$bl_ver")" || continue
    if [[ "$FORCE" -eq 0 && -f "$out/$local_name" ]]; then
      echo "    skip $local_name (present)"
      continue
    fi
    echo "    restore $tag/$asset → $local_name"
    gh release download "$tag" -p "$asset" -D "$tmp"
    cp -f "$tmp/$asset" "$out/$local_name"
    downloaded=1
  done < <(gh release view "$tag" --json assets --jq '.assets[].name' 2>/dev/null)

  if ((downloaded == 0)); then
    return 1
  fi

  printf '%s\n' "$bl_ver" >"$out/version.txt"
  echo "    → $out/"
}

restore_bootloader_version() {
  local bl_ver="$1"
  bl_ver="$(normalize_version "$bl_ver")" || return 1

  if [[ "$FORCE" -eq 0 ]] && bootloader_tree_present "$bl_ver"; then
    echo "==> $bl_ver already present (use --force to replace)"
    return 0
  fi

  local tag
  if release_has_asset "$bl_ver" "bootloader-${bl_ver}.zip"; then
    restore_from_legacy_zip "$bl_ver" "$bl_ver"
    return 0
  fi

  for tag in v0.1.0 v0.1.1; do
    if release_has_asset "$tag" "bootloader-${bl_ver}.zip"; then
      restore_from_legacy_zip "$bl_ver" "$tag"
      return 0
    fi
  done

  echo "==> restore $bl_ver from flat GitHub release assets"
  local restored=0
  while IFS= read -r tag || [[ -n "$tag" ]]; do
    [[ -n "$tag" ]] || continue
    if restore_from_flat_release "$bl_ver" "$tag"; then
      restored=1
    fi
  done < <(list_distro_tags_for_bootloader_restore)

  if ((restored == 0)); then
    echo "error: no bootloader assets found for $bl_ver on GitHub releases" >&2
    return 1
  fi

  ls -la "$BOOTLOADER_ROOT/$bl_ver"
}

list_restore_versions() {
  if ((${#SELECTED[@]} > 0)); then
    local v
    for v in "${SELECTED[@]}"; do
      normalize_version "$v"
    done
    return 0
  fi
  list_released_bootloader_versions
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    -h | --help)
      usage
      ;;
    -*)
      usage
      ;;
    *)
      SELECTED+=("$1")
      shift
      ;;
  esac
done

require_gh

vers=()
while IFS= read -r ver || [[ -n "$ver" ]]; do
  [[ -n "$ver" ]] || continue
  vers+=("$ver")
done < <(list_restore_versions)

((${#vers[@]} > 0)) || {
  echo "error: no bootloader versions to restore" >&2
  exit 1
}

echo "restore bootloader → $BOOTLOADER_ROOT"
for ver in "${vers[@]}"; do
  restore_bootloader_version "$ver"
done

echo "==> restore complete"
