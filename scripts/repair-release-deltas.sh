#!/usr/bin/env bash
# Build missing delta .motas on an already-published distro release and refresh GitHub assets.
#
# Usage:
#   ./scripts/repair-release-deltas.sh v0.1.3 [--base v0.1.2] [--no-upload]
#
# Restores released firmware trees from GitHub when needed, rebuilds missing deltas,
# refreshes build/<ver>/release/, verifies the matrix, and re-uploads (--release-only).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
unset MANIFEST_JSON MANIFEST_PY OTA_ROOT MESHCORE_ROOT BOOTLOADER_SRC MOTATOOL_ROOT 2>/dev/null || true
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"
# shellcheck source=scripts/targets-lib.sh
source "$ROOT/scripts/targets-lib.sh"

TARGETS_FILE="$ROOT/scripts/targets.txt"

usage() {
  cat >&2 <<EOF
usage: $0 vX.Y.Z [--base vA.B.C] [--no-upload]

  vX.Y.Z       Published distro tag (must exist in MANIFEST.json releases)
  --base       Build deltas from one base only (default: every missing base in RELEASES)
  --no-upload  Refresh local release/ only; skip GitHub re-upload
EOF
  exit 2
}

DISTRO_VER=""
BASE_VER=""
UPLOAD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      [[ $# -ge 2 ]] || usage
      BASE_VER="$(normalize_version "$2")" || usage
      shift 2
      ;;
    --no-upload)
      UPLOAD=0
      shift
      ;;
    -h | --help)
      usage
      ;;
    v* | [0-9]*)
      [[ -z "$DISTRO_VER" ]] || usage
      DISTRO_VER="$(normalize_version "$1")" || usage
      shift
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$DISTRO_VER" ]] || usage
is_released_version "$DISTRO_VER" || {
  echo "error: $DISTRO_VER is not a published release in MANIFEST.json" >&2
  exit 1
}

FW_VER="$(manifest_component_version firmware "$DISTRO_VER")"
FW_VER="$(normalize_component_version "$FW_VER")"
MT_VER="$(manifest_component_version motatool "$DISTRO_VER")"
MT_VER="$(normalize_component_version "$MT_VER")"

list_repair_bases() {
  if [[ -n "$BASE_VER" ]]; then
    printf '%s\n' "$BASE_VER"
    return 0
  fi
  list_delta_base_versions "$DISTRO_VER"
}

delta_from_base_present() {
  local slug=$1 base_ver=$2
  local dir f base_label
  dir="$(firmware_slug_dir "$DISTRO_VER" "$FW_VER" "$slug")"
  base_label="${base_ver#v}"
  shopt -s nullglob
  for f in \
    "$dir"/fw-"${slug}"-"${FW_VER}"-delta-from-"${base_ver}"-*.mota \
    "$dir"/fw-"${slug}"-"${FW_VER}"-delta-from-"${base_label}"-*.mota \
    "$dir"/fw-"${slug}"-delta-from-"${base_ver}"-*.mota \
    "$dir"/fw-"${slug}"-delta-from-"${base_label}"-*.mota \
    "$dir"/delta_from_"${base_ver}"*.mota \
    "$dir"/delta_from_"${base_label}"*.mota; do
    [[ -f "$f" ]] && { shopt -u nullglob; return 0; }
  done
  shopt -u nullglob
  return 1
}

ensure_target_tree() {
  local slug=$1
  local out
  out="$(firmware_slug_dir "$DISTRO_VER" "$FW_VER" "$slug")"
  if resolve_firmware_image_in_dir "$out" "$slug" "$FW_VER" >/dev/null 2>&1; then
    return 0
  fi
  echo "==> restore target firmware $DISTRO_VER ($slug)"
  "$ROOT/scripts/restore-firmware.sh" --force "$DISTRO_VER"
  resolve_firmware_image_in_dir "$out" "$slug" "$FW_VER" >/dev/null 2>&1
}

ensure_base_trees() {
  local -a slugs=()
  local slug
  while IFS= read -r slug || [[ -n "$slug" ]]; do
    [[ -n "$slug" ]] || continue
    slugs+=("$slug")
  done < <(list_release_target_slugs_from_file "$TARGETS_FILE")
  ensure_firmware_bases_for_build "$DISTRO_VER" "${slugs[@]}"
}

resolve_motatool() {
  local path try_ver
  for try_ver in "$MT_VER" "0.1.1-ev1" "v0.1.1-ev1"; do
    if path="$(resolve_motatool_bin "$try_ver" 2>/dev/null)"; then
      printf '%s' "$path"
      return 0
    fi
  done
  path="$(motatool_bench_root main 0.1.1-ev1)/motatool-$(host_motatool_platform_slug)"
  if [[ -x "$path" ]]; then
    printf '%s' "$path"
    return 0
  fi
  ensure_motatool_release_cache "$MT_VER" >&2 || true
  if path="$(resolve_motatool_bin "$MT_VER" 2>/dev/null)"; then
    printf '%s' "$path"
    return 0
  fi
  echo "error: motatool not found for $MT_VER — run ./envyos build motatool" >&2
  exit 1
}

read_fw_stamp() {
  local root ver_txt ver_line
  root="$(firmware_bench_root "$DISTRO_VER" "$FW_VER")"
  ver_txt="$root/version.txt"
  if [[ -f "$ver_txt" ]]; then
    ver_line="$(head -1 "$ver_txt" | tr -d '[:space:]')"
    component_firmware_stamp "$ver_line"
    return 0
  fi
  component_firmware_stamp "$FW_VER"
}

build_missing_delta() {
  local mt=$1 slug=$2 base_ver=$3
  local out base_hex fw_hex fw_stamp
  out="$(firmware_slug_dir "$DISTRO_VER" "$FW_VER" "$slug")"
  base_hex="$(resolve_base_image "$slug" "$base_ver")" || {
    echo "error: no base image for $slug $base_ver" >&2
    return 1
  }
  fw_hex="$(resolve_firmware_image_in_dir "$out" "$slug" "$FW_VER")" || {
    echo "error: no target image for $slug $FW_VER in $out" >&2
    return 1
  }
  fw_stamp="$(read_fw_stamp)"
  echo "==> delta ($slug) $base_ver → $FW_VER"
  echo "    base: $base_hex"
  echo "    fw:   $fw_hex"
  "$mt" build --base "$base_hex" --fw "$fw_hex" --fw-version "$fw_stamp" \
    --patch-type in-place --name-stem "fw-${slug}-${FW_VER}" --base-version "${base_ver#v}" \
    --out-dir "$out"
}

echo "repair:   $DISTRO_VER (firmware $FW_VER)"
MT_BIN="$(resolve_motatool)"
echo "motatool: $MT_BIN"

ensure_base_trees

built=0
while IFS= read -r slug || [[ -n "$slug" ]]; do
  [[ -n "$slug" ]] || continue
  is_debug_target_slug "$slug" && continue
  ensure_target_tree "$slug"
  while IFS= read -r base_ver || [[ -n "$base_ver" ]]; do
    [[ -n "$base_ver" ]] || continue
    resolve_base_image "$slug" "$base_ver" >/dev/null || continue
    if delta_from_base_present "$slug" "$base_ver"; then
      echo "    skip $slug $base_ver → $FW_VER (delta present)"
      continue
    fi
    build_missing_delta "$MT_BIN" "$slug" "$base_ver"
    built=$((built + 1))
  done < <(list_repair_bases)
done < <(list_release_target_slugs_from_file "$TARGETS_FILE")

echo "==> built $built delta(s)"
verify_release_delta_matrix "$DISTRO_VER" "$TARGETS_FILE"
populate_distro_release "$DISTRO_VER"

if [[ "$UPLOAD" -eq 1 ]]; then
  exec "$ROOT/scripts/publish.sh" --release-only "$DISTRO_VER"
fi

echo "Done. Local release tree: $(distro_release_root "$DISTRO_VER")"
