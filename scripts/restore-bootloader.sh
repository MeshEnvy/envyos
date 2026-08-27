#!/usr/bin/env bash
# Restore released EnvyBoot trees under build/<ver>/bench/bootloader/ from GitHub Releases.
#
# Usage:
#   ./scripts/restore-bootloader.sh                  # every distro in meshcore RELEASES
#   ./scripts/restore-bootloader.sh v0.1.2
#   ./scripts/restore-bootloader.sh --force v0.1.2
#
# Legacy releases (v0.1.0, v0.1.1): bootloader-vX.Y.Z.zip on the distro tag.
# Transitional flat (v0.1.2): bl-<board>-vX.Y.Z.uf2 + recovery zip on the distro tag.
#   Asset filenames use the pinned bootloader version (often v0.1.0), not the distro tag.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

FORCE=0
SELECTED=()

usage() {
  cat >&2 <<EOF
usage: $0 [--force] [vX.Y.Z]…

  (default)     Restore bootloaders for every firmware release in packages-meta/meshcore/RELEASES
  vX.Y.Z        Restore one or more explicit distro tags
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
  local distro_ver="$1"
  local bl_ver="${2:-$(manifest_component_version bootloader "$distro_ver" 2>/dev/null || read_bootloader_version)}"
  local dir
  migrate_bootloader_package_tree "$distro_ver" "$bl_ver" || true
  dir="$(bootloader_bench_root "$distro_ver" "$bl_ver")"
  [[ -d "$dir" ]] || return 1
  local n
  n="$(find "$dir" -maxdepth 1 -name '*_bootloader-*.uf2' -o -name 'update-*_bootloader-*.uf2' 2>/dev/null | wc -l | tr -d ' ')"
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
  base="${base%.gz}"
  local ver_no_v="${bl_ver#v}"
  local slug board

  if [[ "$asset" == bl-*-recovery-${bl_ver}.zip ]]; then
    slug="${asset#bl-}"
    slug="${slug%-recovery-${bl_ver}.zip}"
    board="$(release_board_slug_to_otafix_board "$slug")"
    printf '%s_bootloader-%s.recovery.zip' "$board" "$ver_no_v"
    return 0
  fi

  if [[ "$asset" == bl-*-${bl_ver}.uf2.gz || "$asset" == bl-*-${bl_ver}.uf2 ]]; then
    slug="${asset#bl-}"
    slug="${slug%-${bl_ver}.uf2.gz}"
    slug="${slug%-${bl_ver}.uf2}"
    board="$(release_board_slug_to_otafix_board "$slug")"
    printf '%s_bootloader-%s.uf2' "$board" "$ver_no_v"
    return 0
  fi

  return 1
}

# Bootloader version embedded in flat bl-* release asset names (may differ from distro tag).
infer_bootloader_version_from_release_assets() {
  local tag="$1"
  local asset ver_no_v
  tag="$(normalize_version "$tag")" || return 1
  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    case "$asset" in
      bl-*-recovery-v*.zip)
        ver_no_v="${asset#bl-}"
        ver_no_v="${ver_no_v##*-recovery-v}"
        ver_no_v="${ver_no_v%.zip}"
        normalize_version "v$ver_no_v"
        return 0
        ;;
      bl-*-v*.uf2 | bl-*-v*.uf2.gz)
        ver_no_v="${asset#bl-}"
        ver_no_v="${ver_no_v##*-v}"
        ver_no_v="${ver_no_v%.uf2.gz}"
        ver_no_v="${ver_no_v%.uf2}"
        normalize_version "v$ver_no_v"
        return 0
        ;;
    esac
  done < <(gh release view "$tag" --json assets --jq '.assets[].name' 2>/dev/null)
  return 1
}

resolve_bootloader_version_for_distro() {
  local distro_ver="$1"
  local inferred manifest_bl
  distro_ver="$(normalize_version "$distro_ver")" || return 1
  if inferred="$(infer_bootloader_version_from_release_assets "$distro_ver" 2>/dev/null)"; then
    printf '%s' "$inferred"
    return 0
  fi
  manifest_bl="$(manifest_component_version bootloader "$distro_ver" 2>/dev/null || true)"
  if [[ -n "$manifest_bl" ]]; then
    normalize_version "$manifest_bl"
    return 0
  fi
  printf '%s' "$distro_ver"
}

release_has_flat_bootloader_assets() {
  local tag="$1"
  infer_bootloader_version_from_release_assets "$tag" >/dev/null 2>&1
}

restore_from_legacy_zip() {
  local distro_ver="$1"
  local bl_ver="$2"
  local tag="$3"
  local zip_name="bootloader-${bl_ver}.zip"
  local tmp dest_root

  echo "==> restore $bl_ver (distro $distro_ver) from $tag/$zip_name"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  gh release download "$tag" -p "$zip_name" -D "$tmp"
  unzip -q "$tmp/$zip_name" -d "$tmp/extract"
  dest_root="$(bootloader_bench_root "$distro_ver" "$bl_ver")"
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
  local distro_ver="$1"
  local bl_ver="$2"
  local tag="$3"
  local out
  out="$(bootloader_bench_root "$distro_ver" "$bl_ver")"
  local tmp asset local_name downloaded=0

  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  mkdir -p "$out"
  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    [[ "$asset" == bl-*-${bl_ver}.uf2.gz || "$asset" == bl-*-${bl_ver}.uf2 || "$asset" == bl-*-recovery-${bl_ver}.zip ]] || continue
    local_name="$(flat_asset_to_build_name "$asset" "$bl_ver")" || continue
    if [[ "$FORCE" -eq 0 && -f "$out/$local_name" ]]; then
      echo "    skip $local_name (present)"
      continue
    fi
    echo "    restore $tag/$asset → $local_name"
    gh release download "$tag" -p "$asset" -D "$tmp"
    materialize_release_download "$tmp/$asset" "$out" "$local_name"
    echo "    → $out/$local_name"
    downloaded=1
  done < <(gh release view "$tag" --json assets --jq '.assets[].name' 2>/dev/null)

  if ((downloaded == 0)); then
    return 1
  fi

  printf '%s\n' "$bl_ver" >"$out/version.txt"
  echo "    → $out/"
}

restore_bootloader_for_distro() {
  local distro_ver="$1"
  local bl_ver="$2"
  distro_ver="$(normalize_version "$distro_ver")" || return 1
  bl_ver="$(normalize_component_version "$bl_ver")" || return 1

  if release_has_flat_bootloader_assets "$distro_ver"; then
    if [[ "$FORCE" -eq 0 ]]; then
      migrate_bootloader_package_tree "$distro_ver" "$bl_ver" || true
      if bootloader_tree_present "$distro_ver" "$bl_ver"; then
        echo "==> $distro_ver bootloader already present (use --force to replace)"
        return 0
      fi
    else
      rm -rf "$(bootloader_bench_root "$distro_ver" "$bl_ver")"
    fi
    echo "==> restore bootloader $bl_ver for distro $distro_ver from flat GitHub release assets"
    restore_from_flat_release "$distro_ver" "$bl_ver" "$distro_ver"
    ls -la "$(bootloader_bench_root "$distro_ver" "$bl_ver")"
    return 0
  fi

  migrate_bootloader_package_tree "$distro_ver" "$bl_ver" || true

  if [[ "$FORCE" -eq 0 ]] && bootloader_tree_present "$distro_ver" "$bl_ver"; then
    echo "==> $distro_ver bootloader already present (use --force to replace)"
    return 0
  fi

  if release_has_asset "$distro_ver" "bootloader-${bl_ver}.zip"; then
    restore_from_legacy_zip "$distro_ver" "$bl_ver" "$distro_ver"
    return 0
  fi

  if release_has_asset "$bl_ver" "bootloader-${bl_ver}.zip"; then
    restore_from_legacy_zip "$distro_ver" "$bl_ver" "$bl_ver"
    return 0
  fi

  for tag in v0.1.0 v0.1.1; do
    if release_has_asset "$tag" "bootloader-${bl_ver}.zip"; then
      restore_from_legacy_zip "$distro_ver" "$bl_ver" "$tag"
      return 0
    fi
  done

  echo "error: no bootloader assets found for distro $distro_ver (bootloader $bl_ver)" >&2
  return 1
}

list_restore_distros() {
  if ((${#SELECTED[@]} > 0)); then
    local v
    for v in "${SELECTED[@]}"; do
      printf '%s\n' "$(normalize_version "$v")"
    done
    return 0
  fi
  list_released_firmware_versions
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

distros=()
while IFS= read -r ver || [[ -n "$ver" ]]; do
  [[ -n "$ver" ]] || continue
  distros+=("$ver")
done < <(list_restore_distros)

((${#distros[@]} > 0)) || {
  echo "error: no distro tags to restore bootloaders for" >&2
  exit 1
}

echo "restore bootloader → build/*/bench/bootloader-*"
for distro in "${distros[@]}"; do
  bl_ver="$(resolve_bootloader_version_for_distro "$distro")"
  restore_bootloader_for_distro "$distro" "$bl_ver"
done

echo "==> restore complete"
