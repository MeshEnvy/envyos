#!/usr/bin/env bash
# Restore released firmware trees under build/firmware/<ver>/ from GitHub Releases.
#
# Usage:
#   ./scripts/restore-firmware.sh                  # all RELEASED_FIRMWARE versions
#   ./scripts/restore-firmware.sh v0.1.0 v0.1.1
#   ./scripts/restore-firmware.sh --force v0.1.2
#
# Legacy releases (v0.1.0, v0.1.1): firmware-vX.Y.Z.zip with per-slug firmware.hex trees.
# Flat releases: keep GitHub .mota basenames. v0.2.0+ is motatool-native
#   fw-<slug>-<ver>-full-<mid8>.mota /
#   fw-<slug>-<ver>-delta-from-<base>-<base8>.mota. v0.1.2 used
#   fw-<slug>-full-<ver>.mota / fw-<slug>-delta-from-<base>.mota.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"
# shellcheck source=scripts/targets-lib.sh
source "$ROOT/scripts/targets-lib.sh"

TARGETS_FILE="$ROOT/scripts/targets.txt"
FORCE=0
SELECTED=()

usage() {
  cat >&2 <<EOF
usage: $0 [--force] [vX.Y.Z]…

  (default)     Restore every version listed in RELEASED_FIRMWARE
  vX.Y.Z        Restore one or more explicit firmware versions
  --force       Re-download and replace existing slug trees

Requires: gh (GitHub CLI), unzip, python3
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

RELEASE_ASSET_CACHE_VER=""
RELEASE_ASSET_CACHE=()

load_release_assets() {
  local ver="$1"
  local name
  [[ "$RELEASE_ASSET_CACHE_VER" == "$ver" && ${#RELEASE_ASSET_CACHE[@]} -gt 0 ]] && return 0
  RELEASE_ASSET_CACHE_VER="$ver"
  RELEASE_ASSET_CACHE=()
  while IFS= read -r name || [[ -n "$name" ]]; do
    [[ -n "$name" ]] || continue
    RELEASE_ASSET_CACHE+=("$name")
  done < <(gh release view "$ver" --json assets --jq '.assets[].name' 2>/dev/null)
}

release_has_asset() {
  local ver="$1"
  local pattern="$2"
  local name
  load_release_assets "$ver"
  for name in "${RELEASE_ASSET_CACHE[@]}"; do
    [[ "$name" == "$pattern" ]] && return 0
  done
  return 1
}

firmware_slug_has_base_image() {
  local slug="$1"
  local ver="$2"
  resolve_base_image "$slug" "$ver" >/dev/null 2>&1
}

# Release .mota names for a slug: current, plus v0.1.2 GitHub fallbacks.
release_mota_assets_for_slug() {
  local ver="$1" slug="$2"
  local t8="" name
  t8="$(firmware_target8_for_slug "$slug" 2>/dev/null || true)"
  load_release_assets "$ver"
  for name in "${RELEASE_ASSET_CACHE[@]}"; do
    [[ "$name" == *.mota ]] || continue
    if [[ "$name" == fw-${slug}-${ver}-full-*.mota ]] \
      || [[ "$name" == fw-${slug}-${ver}-delta-from-*.mota ]] \
      || [[ "$name" == "$(github_full_mota_name "$slug" "$ver")" ]] \
      || [[ "$name" == fw-${slug}-delta-from-*.mota ]]; then
      printf '%s\n' "$name"
      continue
    fi
    if [[ -n "$t8" && "$name" == *_${t8}_${ver}_full_*.mota ]] \
      || [[ -n "$t8" && "$name" == *_${t8}_${ver}_ipdelta_*.mota ]]; then
      printf '%s\n' "$name"
    fi
  done
}

firmware_slug_restore_complete() {
  local slug="$1"
  local ver="$2"
  local asset

  firmware_slug_has_base_image "$slug" "$ver" || return 1
  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    [[ -f "$FIRMWARE_ROOT/$ver/$slug/$asset" ]] || return 1
  done < <(release_mota_assets_for_slug "$ver" "$slug")
  return 0
}

firmware_version_needs_restore() {
  local ver="$1"
  local slug
  while IFS= read -r slug || [[ -n "$slug" ]]; do
    [[ -n "$slug" ]] || continue
    if firmware_slug_restore_complete "$slug" "$ver"; then
      continue
    fi
    if release_has_asset "$ver" "firmware-${ver}.zip"; then
      return 0
    fi
    if [[ -n "$(release_mota_assets_for_slug "$ver" "$slug")" ]]; then
      return 0
    fi
  done < <(list_target_slugs_from_file "$TARGETS_FILE")
  return 1
}

extract_full_mota_payload() {
  local mota="$1"
  local out="$2"
  python3 - "$mota" "$out" <<'PY'
import struct
import sys

path, out = sys.argv[1], sys.argv[2]
data = open(path, "rb").read()
if len(data) < 8 + 197 or data[:4] != b"mOTA":
    raise SystemExit(f"not a .mota file: {path}")
mo = 8
codec_id = data[mo + 56]
if codec_id != 0:
    raise SystemExit(f"expected full .mota (codec 0), got codec {codec_id}: {path}")
payload_size = struct.unpack_from("<I", data, mo + 15)[0]
block_size = 1 << data[mo + 19]
block_count = (payload_size + block_size - 1) // block_size
payload_off = mo + 197 + block_count * 4
payload = data[payload_off : payload_off + payload_size]
if len(payload) != payload_size:
    raise SystemExit(f"truncated payload in {path}")
open(out, "wb").write(payload)
PY
}

restore_slug_from_flat_assets() {
  local ver="$1"
  local slug="$2"
  local out="$FIRMWARE_ROOT/$ver/$slug"
  local tmp asset_uf2 asset
  local -a dl_patterns=()

  if [[ "$FORCE" -eq 0 ]] && firmware_slug_restore_complete "$slug" "$ver"; then
    echo "    skip $ver/$slug (complete)"
    return 0
  fi

  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    if [[ "$FORCE" -eq 0 && -f "$out/$asset" ]]; then
      continue
    fi
    dl_patterns+=(-p "$asset")
  done < <(release_mota_assets_for_slug "$ver" "$slug")

  asset_uf2="$(firmware_artifact_name "$slug" "$ver" uf2)"
  if release_has_asset "$ver" "$asset_uf2"; then
    if [[ "$FORCE" -eq 1 || ! -f "$out/$asset_uf2" ]]; then
      dl_patterns+=(-p "$asset_uf2")
    fi
  fi

  if ((${#dl_patterns[@]} == 0)); then
    if firmware_slug_has_base_image "$slug" "$ver"; then
      echo "    skip $ver/$slug (complete)"
      return 0
    fi
    echo "    skip $ver/$slug (no .mota assets on release $ver)" >&2
    return 0
  fi

  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  echo "    restore $ver/$slug from flat release assets"
  gh release download "$ver" "${dl_patterns[@]}" -D "$tmp"
  mkdir -p "$out"

  for asset in "$tmp"/*; do
    [[ -f "$asset" ]] || continue
    cp -f "$asset" "$out/$(basename "$asset")"
    echo "    → $out/$(basename "$asset")"
  done

  if [[ "$FORCE" -eq 1 ]] || ! firmware_slug_has_base_image "$slug" "$ver"; then
    while IFS= read -r asset || [[ -n "$asset" ]]; do
      [[ -n "$asset" && -f "$out/$asset" ]] || continue
      if [[ "$asset" == *-full-*.mota || "$asset" == *_full_*.mota || "$asset" == fw-${slug}-full-*.mota ]]; then
        extract_full_mota_payload "$out/$asset" "$out/$(firmware_artifact_name "$slug" "$ver" bin)"
        echo "    → $out/$(firmware_artifact_name "$slug" "$ver" bin)"
        break
      fi
    done < <(release_mota_assets_for_slug "$ver" "$slug")
  fi
}

restore_from_legacy_zip() {
  local ver="$1"
  local zip_name="firmware-${ver}.zip"
  local tmp dest_root

  if [[ "$FORCE" -eq 0 ]] && ! firmware_version_needs_restore "$ver"; then
    echo "==> $ver already present (use --force to replace)"
    return 0
  fi

  echo "==> restore $ver from $zip_name"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  gh release download "$ver" -p "$zip_name" -D "$tmp"
  unzip -q "$tmp/$zip_name" -d "$tmp/extract"
  dest_root="$FIRMWARE_ROOT/$ver"
  mkdir -p "$dest_root"

  if [[ -d "$tmp/extract/$ver" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      rm -rf "$dest_root"
      mkdir -p "$dest_root"
    fi
    cp -a "$tmp/extract/$ver/." "$dest_root/"
  else
    echo "error: $zip_name missing top-level $ver/ directory" >&2
    return 1
  fi

  echo "    → $dest_root/"
  ls -la "$dest_root"
}

restore_from_flat_release() {
  local ver="$1"
  local slug restored=0

  load_release_assets "$ver"
  echo "==> restore $ver from flat GitHub release assets"
  while IFS= read -r slug || [[ -n "$slug" ]]; do
    [[ -n "$slug" ]] || continue
    restore_slug_from_flat_assets "$ver" "$slug"
    restored=1
  done < <(list_target_slugs_from_file "$TARGETS_FILE")

  if ((restored == 0)); then
    echo "error: no restorable slugs found for $ver" >&2
    return 1
  fi
}

restore_firmware_version() {
  local ver="$1"
  ver="$(normalize_version "$ver")" || return 1

  if [[ "$FORCE" -eq 0 ]] && ! firmware_version_needs_restore "$ver"; then
    echo "==> $ver already present (use --force to replace)"
    return 0
  fi

  if release_has_asset "$ver" "firmware-${ver}.zip"; then
    restore_from_legacy_zip "$ver"
    return 0
  fi

  restore_from_flat_release "$ver"
}

list_restore_versions() {
  if ((${#SELECTED[@]} > 0)); then
    local v
    for v in "${SELECTED[@]}"; do
      normalize_version "$v"
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

vers=()
while IFS= read -r ver || [[ -n "$ver" ]]; do
  [[ -n "$ver" ]] || continue
  vers+=("$ver")
done < <(list_restore_versions)

((${#vers[@]} > 0)) || {
  echo "error: no firmware versions to restore" >&2
  exit 1
}

echo "restore firmware → $FIRMWARE_ROOT"
for ver in "${vers[@]}"; do
  restore_firmware_version "$ver"
done

echo "==> restore complete"
