#!/usr/bin/env bash
# Shared build/publish helpers for envyos (sourced by version.sh).
set -euo pipefail

# --- paths: build/<branch-slot>/bench during dev; build/<vX.Y.Z>/ at publish ---

init_build_paths() {
  BUILD_ROOT="${BUILD_ROOT:-$OTA_ROOT/build}"
  RELEASED_FIRMWARE_FILE="${RELEASED_FIRMWARE_FILE:-$OTA_ROOT/RELEASED_FIRMWARE}"
  RELEASED_BOOTLOADER_FILE="${RELEASED_BOOTLOADER_FILE:-$OTA_ROOT/RELEASED_BOOTLOADER}"
  TARGETS_FILE="${TARGETS_FILE:-$OTA_ROOT/scripts/targets.txt}"
  export BUILD_ROOT
}

init_build_paths

sanitize_build_slot() {
  local raw=$1
  raw="${raw//\//-}"
  raw="$(printf '%s' "$raw" | tr -cs 'A-Za-z0-9._-' '-')"
  raw="${raw#-}"
  raw="${raw%-}"
  [[ -n "$raw" ]] || raw="unknown"
  printf '%s' "$raw"
}

read_git_branch_name() {
  local branch
  branch="$(git -C "$OTA_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || {
    printf 'unknown'
    return 0
  }
  if [[ "$branch" == "HEAD" ]]; then
    branch="$(git -C "$OTA_ROOT" describe --tags --exact-match 2>/dev/null || git -C "$OTA_ROOT" rev-parse --short HEAD 2>/dev/null || echo detached)"
  fi
  printf '%s' "$branch"
}

read_build_slot() {
  if [[ -n "${ENVYOS_BUILD_SLOT:-}" ]]; then
    sanitize_build_slot "$ENVYOS_BUILD_SLOT"
    return 0
  fi
  sanitize_build_slot "$(read_git_branch_name)"
}

is_version_tree_key() {
  normalize_version "$1" >/dev/null 2>&1
}

normalize_tree_key() {
  local key=$1
  if normalize_version "$key" >/dev/null 2>&1; then
    normalize_version "$key"
  else
    sanitize_build_slot "$key"
  fi
}

read_bench_tree_key() {
  read_build_slot
}

distro_tree_root() {
  printf '%s/%s' "$BUILD_ROOT" "$(normalize_tree_key "$1")"
}

distro_bench_root() {
  printf '%s/bench' "$(distro_tree_root "$1")"
}

distro_release_root() {
  printf '%s/release' "$(distro_tree_root "$1")"
}

release_manifest_path() {
  printf '%s/RELEASE_MANIFEST' "$(distro_tree_root "$1")"
}

package_bench_root() {
  local tree_key=$1 package=$2 pkg_ver=$3
  tree_key="$(normalize_tree_key "$tree_key")"
  pkg_ver="$(package_bench_version_label "$pkg_ver")"
  printf '%s/%s-%s' "$(distro_bench_root "$tree_key")" "$package" "$pkg_ver"
}

firmware_bench_root() {
  local tree_key=${1:-$(read_bench_tree_key)}
  local fw_ver=${2:-$(read_firmware_version 2>/dev/null || echo v0.0.0)}
  package_bench_root "$tree_key" meshcore "$fw_ver"
}

firmware_slug_dir() {
  local distro_ver=$1 fw_ver=$2 slug=$3
  if [[ $# -eq 2 ]]; then
    slug="$fw_ver"
    fw_ver="$distro_ver"
  fi
  printf '%s/%s' "$(firmware_bench_root "$distro_ver" "$fw_ver")" "$slug"
}

bootloader_bench_root() {
  local tree_key=${1:-$(read_bench_tree_key)}
  local bl_ver=${2:-$(read_bootloader_version 2>/dev/null || echo v0.0.0)}
  package_bench_root "$tree_key" adafruit-nrf52-bootloader "$bl_ver"
}

motatool_bench_root() {
  local tree_key=${1:-$(read_bench_tree_key)}
  local mt_ver=${2:-$(read_motatool_version 2>/dev/null || echo v0.0.0)}
  package_bench_root "$tree_key" motatool "$mt_ver"
}

peaky_bench_root() {
  local tree_key=${1:-$(read_bench_tree_key)}
  local pk_ver=${2:-$(read_peaky_version 2>/dev/null || echo v0.0.0)}
  package_bench_root "$tree_key" peaky "$pk_ver"
}

envybot_bench_root() {
  local tree_key=${1:-$(read_bench_tree_key)}
  local eb_ver=${2:-$(read_envybot_version 2>/dev/null || echo v0.0.0)}
  package_bench_root "$tree_key" envybot "$eb_ver"
}

envybot_wheel_basename() {
  local ver=${1:-$(read_envybot_version 2>/dev/null || echo v0.0.0)}
  printf 'envybot-%s-py3-none-any.whl' "${ver#v}"
}

mcmt_gateway_bench_root() {
  local tree_key=${1:-$(read_bench_tree_key)}
  local mcmt_ver=${2:-$(read_mcmt_gateway_version 2>/dev/null || echo v0.0.0)}
  package_bench_root "$tree_key" mcmt-gateway "$mcmt_ver"
}

mcmt_gateway_wheel_basename() {
  local ver=${1:-$(read_mcmt_gateway_version 2>/dev/null || echo v0.0.0)}
  printf 'mcmt_gateway-%s-py3-none-any.whl' "${ver#v}"
}

migrate_motatool_package_tree() {
  local tree_key=$1 mt_ver=$2
  local dest src
  tree_key="$(normalize_tree_key "$tree_key")"
  mt_ver="$(normalize_package_version "$mt_ver")"
  dest="$(motatool_bench_root "$tree_key" "$mt_ver")"
  [[ -d "$dest" ]] && return 0
  for src in \
    "$(distro_bench_root "$tree_key")/motatool" \
    "$(motatool_bench_root "$tree_key" "$mt_ver")"; do
    [[ -d "$src" ]] || continue
    [[ "$src" == "$dest" ]] && continue
    echo "==> migrate motatool package tree: $src → $dest"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src/." "$dest/"
    return 0
  done
  return 1
}

maybe_migrate_version_bench_to_slot() {
  local slot=$1 draft src dest
  slot="$(normalize_tree_key "$slot")"
  is_version_tree_key "$slot" && return 0
  draft="$(latest_published_distro_tag 2>/dev/null || return 0)"
  is_version_tree_key "$draft" || return 0
  src="$(distro_bench_root "$draft")"
  dest="$(distro_bench_root "$slot")"
  [[ -d "$src" ]] || return 0
  [[ -d "$dest" ]] && return 0
  echo "==> migrate bench tree: $src → $dest"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

promote_bench_to_release_tree() {
  local from_slot=$1 to_ver=$2 force=${3:-0}
  from_slot="$(normalize_tree_key "$from_slot")"
  to_ver="$(normalize_version "$to_ver")"
  local src dest rel_src rel_dest

  [[ "$from_slot" == "$to_ver" ]] && return 0

  src="$(distro_bench_root "$from_slot")"
  dest="$(distro_bench_root "$to_ver")"

  [[ -d "$src" ]] || {
    echo "error: no bench tree at $src — run ./envyos build first" >&2
    return 1
  }

  if [[ -d "$dest" ]]; then
    if ((force == 1)); then
      rm -rf "$dest"
    else
      echo "error: release bench tree already exists at $dest" >&2
      return 1
    fi
  fi

  echo "==> promote bench: $src → $dest"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"

  rel_src="$(distro_release_root "$from_slot")"
  rel_dest="$(distro_release_root "$to_ver")"
  if [[ -d "$rel_src" ]]; then
    rm -rf "$rel_dest"
    mkdir -p "$(dirname "$rel_dest")"
    cp -a "$rel_src" "$rel_dest"
  fi
}

maybe_populate_distro_release() {
  [[ "${ENVYOS_SKIP_RELEASE:-0}" == 1 ]] && return 0
  populate_distro_release
}

# Full ./envyos build --clean: empty the working slot (bench + release + manifest).
# Does not touch other slots (e.g. build/v0.1.x/) or published build/vX.Y.Z/ trees.
clean_distro_working_slot() {
  local tree_key=$1
  local bench release manifest
  tree_key="$(normalize_tree_key "$tree_key")"
  bench="$(distro_bench_root "$tree_key")"
  release="$(distro_release_root "$tree_key")"
  manifest="$(release_manifest_path "$tree_key")"
  if [[ -d "$bench" || -d "$release" || -f "$manifest" ]]; then
    echo "==> clean slot $tree_key: wipe bench + release"
    rm -rf "$bench" "$release"
    rm -f "$manifest"
  fi
}

# --- git / registry ---

git_short_sha() {
  local repo=$1
  git -C "$repo" rev-parse --short HEAD 2>/dev/null || printf 'unknown'
}

submodule_git_sha() {
  local name=$1
  local path
  case "$name" in
    meshcore) path="$MESHCORE_ROOT" ;;
    bootloader | adafruit-nrf52-bootloader) path="$BOOTLOADER_SRC" ;;
    motatool) path="$MOTATOOL_ROOT" ;;
    mcmt-gateway) path="$MCMT_ROOT" ;;
    meshcore-open) path="$MESHCORE_OPEN_ROOT" ;;
    *)
      echo "?"
      return 0
      ;;
  esac
  git_short_sha "$path"
}

read_registry_versions() {
  local file=$1
  [[ -f "$file" ]] || return 0
  local line ver
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    ver="$(normalize_version "$line" 2>/dev/null)" || continue
    printf '%s\n' "$ver"
  done <"$file"
}

# True when ver is listed in packages-meta/meshcore/RELEASES (shipped distro semver firmware).
is_released_firmware_version() {
  local ver want pkg
  pkg="$(normalize_package_version "$1" 2>/dev/null || true)"
  if [[ "$pkg" == *-ev* ]]; then
    return 1
  fi
  ver="$(normalize_version "$1")" || return 1
  while IFS= read -r want || [[ -n "$want" ]]; do
    [[ "$want" == "$ver" ]] && return 0
  done < <(read_registry_versions "$RELEASED_FIRMWARE_FILE")
  return 1
}

list_released_firmware_versions() {
  read_registry_versions "$RELEASED_FIRMWARE_FILE"
}

is_released_bootloader_version() {
  local ver want
  ver="$(normalize_version "$1")" || return 1
  while IFS= read -r want || [[ -n "$want" ]]; do
    [[ "$want" == "$ver" ]] && return 0
  done < <(read_registry_versions "$RELEASED_BOOTLOADER_FILE")
  return 1
}

list_released_bootloader_versions() {
  read_registry_versions "$RELEASED_BOOTLOADER_FILE"
}

list_released_distros() {
  manifest_py releases list 2>/dev/null || true
}

firmware_version_tree_present() {
  local ver=$1 distro fw_ver
  ver="$(normalize_package_version "$ver")"
  if normalize_version "$ver" >/dev/null 2>&1; then
    distro="$(normalize_version "$ver")"
  else
    distro="$(read_bench_tree_key 2>/dev/null || printf '%s' main)"
  fi
  fw_ver="$ver"
  [[ -d "$(firmware_bench_root "$distro" "$fw_ver")" ]]
}

list_known_mota_versions() {
  local tmp=() ver d
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    tmp+=("$ver")
  done < <(read_registry_versions "$RELEASED_FIRMWARE_FILE")
  if [[ -f "$MANIFEST_JSON" ]]; then
    while IFS= read -r ver || [[ -n "$ver" ]]; do
      [[ -n "$ver" ]] || continue
      tmp+=("$ver")
    done < <(manifest_py releases list 2>/dev/null || true)
  fi
  if [[ -d "$BUILD_ROOT" ]]; then
    for d in "$BUILD_ROOT"/v[0-9]*.[0-9]*.[0-9]*/bench/meshcore-v*; do
      [[ -d "$d" ]] || continue
      ver="$(basename "$d")"
      ver="${ver#meshcore-}"
      ver="$(normalize_version "$ver" 2>/dev/null)" || continue
      tmp+=("$ver")
    done
    for d in "$BUILD_ROOT"/*/bench/meshcore-*; do
      [[ -d "$d" ]] || continue
      ver="$(basename "$d")"
      ver="${ver#meshcore-}"
      ver="$(normalize_package_version "$ver" 2>/dev/null)" || continue
      tmp+=("$ver")
    done
  fi
  ((${#tmp[@]} == 0)) && return 0
  sort_versions "${tmp[@]}"
}

latest_released_distro() {
  local ver last=""
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    last="$ver"
  done < <(list_known_mota_versions)
  [[ -n "$last" ]] && printf '%s' "$last"
}

# --- firmware artifact names ---

# Filename-safe version label (1.16.0-ev1 or 0.1.2 — no leading v).
firmware_artifact_ver_label() {
  local ver=$1
  ver="$(normalize_package_version "$ver")"
  printf '%s' "${ver#v}"
}

firmware_artifact_name() {
  local slug=$1 ver=$2 kind=$3
  ver="$(firmware_artifact_ver_label "$ver")"
  case "$kind" in
    hex) printf 'meshcore-%s-%s.hex' "$slug" "$ver" ;;
    uf2) printf 'meshcore-%s-%s.uf2' "$slug" "$ver" ;;
    zip) printf 'meshcore-%s-%s.zip' "$slug" "$ver" ;;
    bin) printf 'meshcore-%s-%s.bin' "$slug" "$ver" ;;
    *)
      echo "error: unknown firmware artifact kind: $kind" >&2
      return 1
      ;;
  esac
}

github_full_mota_name() {
  local slug=$1 ver=$2
  ver="$(firmware_artifact_ver_label "$ver")"
  printf 'meshcore-%s-%s-full-*.mota' "$slug" "$ver"
}

bootloader_flat_slug() {
  local board=$1
  case "$board" in
    wismesh_tag) printf '%s' wismesh-tag ;;
    rak4631) printf '%s' rak4631 ;;
    sensecap_solar_p1) printf '%s' sensecap-solar-p1 ;;
    *) tr '_' '-' <<<"$board" ;;
  esac
}

# Bench tree names under build/<slot>/bench/adafruit-nrf52-bootloader-<ver>/.
bootloader_bench_board_name() {
  local board=$1
  case "$board" in
    wiscore_rak4631_board) printf '%s' rak4631 ;;
    *) printf '%s' "$board" ;;
  esac
}

bootloader_bench_uf2_name() {
  local board=$1 bl_ver=$2
  bl_ver="$(normalize_package_version "$bl_ver")"
  printf '%s_bootloader-%s.uf2' "$(bootloader_bench_board_name "$board")" "${bl_ver#v}"
}

bootloader_bench_recovery_name() {
  local board=$1 bl_ver=$2
  bl_ver="$(normalize_package_version "$bl_ver")"
  printf '%s_bootloader-%s.recovery.zip' "$(bootloader_bench_board_name "$board")" "${bl_ver#v}"
}

bootloader_flat_uf2_name() {
  local board=$1 bl_ver=$2
  bl_ver="$(normalize_package_version "$bl_ver")"
  printf 'adafruit-nrf52-bootloader-%s-%s.uf2' "$(bootloader_flat_slug "$board")" "$bl_ver"
}

bootloader_flat_recovery_name() {
  local board=$1 bl_ver=$2
  bl_ver="$(normalize_package_version "$bl_ver")"
  printf 'adafruit-nrf52-bootloader-%s-recovery-%s.zip' "$(bootloader_flat_slug "$board")" "$bl_ver"
}

# GitHub release assets: gzip large binary artifacts (.mota, .uf2).
stage_gzip_named() {
  local src=$1 stage_dir=$2 publish_name=$3
  local dst="$stage_dir/${publish_name}.gz"
  gzip -cn9 "$src" >"$dst"
  printf '%s' "$dst"
}

release_asset_basename_uncompressed() {
  local name=$1
  if [[ "$name" == *.gz ]]; then
    printf '%s' "${name%.gz}"
    return 0
  fi
  printf '%s' "$name"
}

materialize_release_download() {
  local src=$1 dest_dir=$2 dest_name=${3:-}
  local base out_name
  base="$(basename "$src")"
  out_name="${dest_name:-$(release_asset_basename_uncompressed "$base")}"
  if [[ "$base" == *.mota.gz || "$base" == *.uf2.gz ]]; then
    gunzip -c "$src" >"$dest_dir/$out_name"
  else
    cp -f "$src" "$dest_dir/$out_name"
  fi
}

# --- mota payload extract (shared with restore) ---

extract_full_mota_payload() {
  local mota=$1 out=$2
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

resolve_firmware_image_in_dir() {
  local dir=$1 slug=$2 ver=$3
  local hex bin mota
  hex="$dir/$(firmware_artifact_name "$slug" "$ver" hex)"
  bin="$dir/$(firmware_artifact_name "$slug" "$ver" bin)"
  if [[ -f "$hex" ]]; then
    printf '%s' "$hex"
    return 0
  fi
  if [[ -f "$bin" ]]; then
    printf '%s' "$bin"
    return 0
  fi
  for mota in \
    "$dir"/meshcore-"${slug}"-*-full-*.mota \
    "$dir"/meshcore-"${slug}"-full-*.mota; do
    [[ -f "$mota" ]] || continue
    extract_full_mota_payload "$mota" "$bin"
    printf '%s' "$bin"
    return 0
  done
  return 1
}

_resolve_base_image_in_dir() {
  local dir=$1 slug=$2 base_ver=$3
  local p mota
  for p in \
    "$(firmware_artifact_name "$slug" "$base_ver" hex)" \
    "$(firmware_artifact_name "$slug" "$base_ver" bin)"; do
    if [[ -f "$dir/$p" ]]; then
      printf '%s' "$dir/$p"
      return 0
    fi
  done
  for mota in \
    "$dir"/meshcore-"${slug}"-*-full-*.mota \
    "$dir"/meshcore-"${slug}"-full-*.mota; do
    [[ -f "$mota" ]] || continue
    extract_full_mota_payload "$mota" "$dir/$(firmware_artifact_name "$slug" "$base_ver" bin)"
    printf '%s' "$dir/$(firmware_artifact_name "$slug" "$base_ver" bin)"
    return 0
  done
  return 1
}

resolve_base_image() {
  local slug=$1 base_ver=$2
  local dir slot label
  base_ver="$(normalize_package_version "$base_ver")"
  label="$(package_bench_version_label "$base_ver")"

  dir="$(firmware_slug_dir "$base_ver" "$base_ver" "$slug")"
  _resolve_base_image_in_dir "$dir" "$slug" "$base_ver" && return 0

  slot="$(read_bench_tree_key 2>/dev/null || true)"
  if [[ -n "$slot" ]]; then
    dir="$(firmware_slug_dir "$slot" "$base_ver" "$slug")"
    _resolve_base_image_in_dir "$dir" "$slug" "$base_ver" && return 0
  fi

  for dir in "$BUILD_ROOT"/*/bench/meshcore-"$label"/"$slug"; do
    [[ -d "$dir" ]] || continue
    _resolve_base_image_in_dir "$dir" "$slug" "$base_ver" && return 0
  done
  return 1
}

# True when a locally present released firmware tree already has this slug.
# Used to skip GitHub restore for new targets (e.g. heltec) that were never in v0.1.x zips.
slug_in_any_released_firmware_tree() {
  local slug=$1
  local ver
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    resolve_base_image "$slug" "$ver" >/dev/null 2>&1 && return 0
  done < <(read_registry_versions "$RELEASED_FIRMWARE_FILE")
  return 1
}

any_released_firmware_tree_present() {
  local ver
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    firmware_version_tree_present "$ver" && return 0
  done < <(read_registry_versions "$RELEASED_FIRMWARE_FILE")
  return 1
}

ensure_firmware_bases_for_build() {
  local target_ver=$1
  shift
  local slugs=("$@")
  local base_ver slug
  local need_restore=0
  local have_released_trees=0
  if any_released_firmware_tree_present; then
    have_released_trees=1
  fi
  for base_ver in $(list_delta_base_versions "$target_ver"); do
    for slug in "${slugs[@]}"; do
      is_debug_target_slug "$slug" && continue
      resolve_base_image "$slug" "$base_ver" >/dev/null 2>&1 && continue
      if ((have_released_trees == 1)) && ! slug_in_any_released_firmware_tree "$slug"; then
        continue
      fi
      need_restore=1
      break 2
    done
  done
  if ((need_restore == 0)); then
    return 0
  fi
  echo "==> restoring released firmware bases for delta matrix"
  local bases=()
  while IFS= read -r base_ver || [[ -n "$base_ver" ]]; do
    [[ -n "$base_ver" ]] || continue
    bases+=("$base_ver")
  done < <(list_delta_base_versions "$target_ver")
  "$OTA_ROOT/scripts/restore-firmware.sh" "${bases[@]}"
}

mota_target_id_for_env() {
  local env_name=$1
  python3 - "$env_name" <<'PY'
import hashlib
import struct
import sys

env = sys.argv[1]
tid = int.from_bytes(hashlib.sha256(env.encode()).digest()[:4], "little")
print(tid)
PY
}

firmware_target8_for_slug() {
  local slug=$1
  local env
  env="$(target_env_for_slug "$slug" "$TARGETS_FILE" 2>/dev/null)" || return 1
  python3 - "$env" <<'PY'
import hashlib
import sys

env = sys.argv[1]
print(hashlib.sha256(env.encode()).digest()[:4].hex())
PY
}

# --- motatool platform helpers ---

normalize_motatool_platform_slug() {
  local p=$1
  case "$p" in
    darwin-aarch64 | darwin-x86_64 | linux-aarch64 | linux-x86_64) printf '%s' "$p" ;;
    macos-aarch64 | macos-arm64) printf '%s' darwin-aarch64 ;;
    macos-x86_64 | macos-amd64) printf '%s' darwin-x86_64 ;;
    linux-amd64 | linux-x64) printf '%s' linux-x86_64 ;;
    linux-arm64) printf '%s' linux-aarch64 ;;
    *)
      echo "error: unknown motatool platform: $p" >&2
      return 1
      ;;
  esac
}

motatool_platform_os() {
  case "$(normalize_motatool_platform_slug "$1")" in
    darwin-*) printf '%s' darwin ;;
    linux-*) printf '%s' linux ;;
  esac
}

motatool_platform_to_rust_triple() {
  case "$(normalize_motatool_platform_slug "$1")" in
    darwin-aarch64) printf '%s' aarch64-apple-darwin ;;
    darwin-x86_64) printf '%s' x86_64-apple-darwin ;;
    linux-aarch64) printf '%s' aarch64-unknown-linux-gnu ;;
    linux-x86_64) printf '%s' x86_64-unknown-linux-gnu ;;
  esac
}

host_motatool_platform_slug() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os-$arch" in
    Darwin-arm64) printf '%s' darwin-aarch64 ;;
    Darwin-x86_64) printf '%s' darwin-x86_64 ;;
    Linux-x86_64) printf '%s' linux-x86_64 ;;
    Linux-aarch64 | Linux-arm64) printf '%s' linux-aarch64 ;;
    *)
      echo "error: unsupported host for motatool: $os $arch" >&2
      return 1
      ;;
  esac
}

list_motatool_release_platforms() {
  printf '%s\n' darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64
}

motatool_cargo_release_path() {
  local platform=$1 host triple rel
  platform="$(normalize_motatool_platform_slug "$platform")"
  host="$(host_motatool_platform_slug 2>/dev/null || true)"
  rel="$MOTATOOL_ROOT/target/release/motatool"
  if [[ "$platform" == "$host" ]]; then
    printf '%s' "$rel"
    return 0
  fi
  triple="$(motatool_platform_to_rust_triple "$platform")"
  printf '%s' "$MOTATOOL_ROOT/target/$triple/release/motatool"
}

motatool_staged_binary_path() {
  local platform=$1 distro=${2:-$(read_bench_tree_key)} mt_ver=${3:-$(read_motatool_version)}
  platform="$(normalize_motatool_platform_slug "$platform")"
  printf '%s/motatool-%s' "$(motatool_bench_root "$distro" "$mt_ver")" "$platform"
}

_motatool_bin_in_slot() {
  local ver=$1 distro=$2 platform path
  platform="$(host_motatool_platform_slug)"
  path="$(motatool_staged_binary_path "$platform" "$distro" "$ver")"
  if [[ -x "$path" ]]; then
    printf '%s' "$path"
    return 0
  fi
  path="$(motatool_bench_root "$distro" "$ver")/motatool"
  if [[ -x "$path" ]]; then
    printf '%s' "$path"
    return 0
  fi
  return 1
}

resolve_motatool_bin() {
  local ver=$1 path distro branch
  if [[ -n "${MOTATOOL:-}" ]]; then
    if [[ -x "$MOTATOOL" ]]; then
      printf '%s' "$MOTATOOL"
      return 0
    fi
    echo "error: MOTATOOL=$MOTATOOL is not an executable" >&2
    return 1
  fi
  ver="$(normalize_package_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  if path="$(_motatool_bin_in_slot "$ver" "$distro")"; then
    printf '%s' "$path"
    return 0
  fi
  # Custom ENVYOS_BUILD_SLOT is for firmware trees. Reuse motatool from the git-branch bench.
  if [[ -n "${ENVYOS_BUILD_SLOT:-}" ]]; then
    branch="$(sanitize_build_slot "$(read_git_branch_name)")"
    if [[ "$branch" != "$distro" ]] && path="$(_motatool_bin_in_slot "$ver" "$branch")"; then
      printf '%s' "$path"
      return 0
    fi
  fi
  return 1
}

list_staged_motatool_platforms() {
  local ver=$1 dir distro f base
  ver="$(normalize_package_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dir="$(motatool_bench_root "$distro" "$ver")"
  [[ -d "$dir" ]] || return 0
  if [[ -f "$dir/platforms.txt" ]]; then
    cat "$dir/platforms.txt"
    return 0
  fi
  for f in "$dir"/motatool-*; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    printf '%s\n' "${base#motatool-}"
  done
}

stage_motatool_binary_for_platform() {
  local bin=$1 platform=$2 ver out dir distro
  platform="$(normalize_motatool_platform_slug "$platform")"
  ver="$(read_motatool_version)"
  distro="$(read_bench_tree_key)"
  assert_package_tree_not_released motatool "$ver"
  out="$(motatool_staged_binary_path "$platform" "$distro")"
  dir="$(dirname "$out")"
  mkdir -p "$dir"
  cp -f "$bin" "$out"
  chmod +x "$out" 2>/dev/null || true
  printf '%s\n' "$ver" >"$dir/version.txt"
  if [[ -f "$dir/platforms.txt" ]]; then
    grep -qxF "$platform" "$dir/platforms.txt" 2>/dev/null || echo "$platform" >>"$dir/platforms.txt"
  else
    printf '%s\n' "$platform" >"$dir/platforms.txt"
  fi
}

# Override legacy single-binary stager used by older callers.
stage_motatool_binary() {
  local bin=$1 platform=${2:-}
  if [[ -z "$platform" ]]; then
    platform="$(host_motatool_platform_slug)"
  fi
  stage_motatool_binary_for_platform "$bin" "$platform"
}

motatool_platform_from_triple() {
  case "$1" in
    aarch64-apple-darwin) printf '%s' darwin-aarch64 ;;
    x86_64-apple-darwin) printf '%s' darwin-x86_64 ;;
    aarch64-unknown-linux-gnu) printf '%s' linux-aarch64 ;;
    x86_64-unknown-linux-gnu) printf '%s' linux-x86_64 ;;
    *)
      echo "error: unknown motatool triple: $1" >&2
      return 1
      ;;
  esac
}

motatool_triple_from_archive_basename() {
  local base=$1
  base="${base%.tar.gz}"
  if [[ "$base" =~ ^motatool-[0-9]+\.[0-9]+\.[0-9]+-(.+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

motatool_platform_has_binary() {
  local ver=$1 platform=$2
  [[ -x "$(motatool_staged_binary_path "$platform")" ]]
}

motatool_all_platforms_present() {
  local ver=$1 platform
  ver="$(normalize_package_version "$ver")"
  while IFS= read -r platform || [[ -n "$platform" ]]; do
    [[ -n "$platform" ]] || continue
    motatool_platform_has_binary "$ver" "$platform" || return 1
  done < <(list_motatool_release_platforms)
}

motatool_release_archive_basename() {
  local ver=$1 platform=$2 triple
  ver="$(normalize_package_version "$ver")"
  platform="$(normalize_motatool_platform_slug "$platform")"
  triple="$(motatool_platform_to_rust_triple "$platform")"
  printf 'motatool-%s-%s.tar.gz' "${ver#v}" "$triple"
}

motatool_release_archive_path() {
  local ver=$1 platform=$2 distro=${3:-$(read_bench_tree_key)}
  printf '%s/%s' "$(distro_release_root "$distro")" "$(motatool_release_archive_basename "$ver" "$platform")"
}

create_motatool_platform_archive() {
  local ver=$1 platform=$2 dest_dir=${3:-}
  local bin archive staging distro
  ver="$(normalize_package_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  platform="$(normalize_motatool_platform_slug "$platform")"
  dest_dir="${dest_dir:-$(distro_release_root "$distro")}"
  bin="$(motatool_staged_binary_path "$platform" "$distro")"
  [[ -x "$bin" ]] || return 1
  archive="$dest_dir/$(motatool_release_archive_basename "$ver" "$platform")"
  staging="$(mktemp -d)"
  cp -f "$bin" "$staging/motatool"
  chmod +x "$staging/motatool"
  rm -f "$archive"
  tar -C "$staging" -czf "$archive" motatool
  rm -rf "$staging"
  printf '%s' "$archive"
}

stage_motatool_release_archives() {
  local dest_dir=$1 ver=$2
  local platform archive missing=0
  ver="$(normalize_package_version "$ver")"
  mkdir -p "$dest_dir"
  while IFS= read -r platform || [[ -n "$platform" ]]; do
    [[ -n "$platform" ]] || continue
    if archive="$(create_motatool_platform_archive "$ver" "$platform" "$dest_dir" 2>/dev/null)"; then
      :
    else
      echo "warning: skip motatool $ver $platform — no staged binary" >&2
      missing=1
    fi
  done < <(list_motatool_release_platforms)
  [[ "$missing" -eq 0 ]]
}

collect_motatool_release_assets() {
  local ver=$1 dest_dir=${2:-}
  local distro
  ver="$(normalize_package_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dest_dir="${dest_dir:-$(distro_release_root "$distro")}"
  stage_motatool_release_archives "$dest_dir" "$ver"
}

record_motatool_platform_staged() {
  local ver=$1 platform=$2 dir distro
  ver="$(normalize_package_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  platform="$(normalize_motatool_platform_slug "$platform")"
  dir="$(motatool_bench_root "$distro" "$ver")"
  mkdir -p "$dir"
  if [[ -f "$dir/platforms.txt" ]]; then
    grep -qxF "$platform" "$dir/platforms.txt" 2>/dev/null || echo "$platform" >>"$dir/platforms.txt"
  else
    printf '%s\n' "$platform" >"$dir/platforms.txt"
  fi
  printf '%s\n' "$ver" >"$dir/version.txt"
}

# --- peaky platform helpers (match peaky-finders release.yml triples) ---

list_peaky_release_triples() {
  printf '%s\n' x86_64-unknown-linux-gnu aarch64-apple-darwin x86_64-apple-darwin
}

peaky_staged_binary_dir() {
  local ver=$1 triple=$2 distro=${3:-$(read_bench_tree_key)}
  ver="$(normalize_version "$ver")"
  printf '%s/peaky-%s-%s' "$(peaky_bench_root "$distro" "$ver")" "${ver#v}" "$triple"
}

peaky_platform_has_binary() {
  local ver=$1 triple=$2
  [[ -x "$(peaky_staged_binary_dir "$ver" "$triple")/peaky" ]]
}

peaky_all_platforms_present() {
  local ver=$1 triple
  ver="$(normalize_version "$ver")"
  while IFS= read -r triple || [[ -n "$triple" ]]; do
    [[ -n "$triple" ]] || continue
    peaky_platform_has_binary "$ver" "$triple" || return 1
  done < <(list_peaky_release_triples)
}

peaky_release_archive_basename() {
  local ver=$1 triple=$2
  ver="$(normalize_version "$ver")"
  printf 'peaky-%s-%s.tar.gz' "${ver#v}" "$triple"
}

peaky_release_archive_path() {
  local ver=$1 triple=$2 distro=${3:-$(read_bench_tree_key)}
  printf '%s/%s' "$(distro_release_root "$distro")" "$(peaky_release_archive_basename "$ver" "$triple")"
}

create_peaky_platform_archive() {
  local ver=$1 triple=$2 dest_dir=${3:-}
  local dir archive staging distro
  ver="$(normalize_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dest_dir="${dest_dir:-$(distro_release_root "$distro")}"
  dir="$(peaky_staged_binary_dir "$ver" "$triple" "$distro")"
  [[ -x "$dir/peaky" ]] || return 1
  archive="$dest_dir/$(peaky_release_archive_basename "$ver" "$triple")"
  staging="$(mktemp -d)"
  cp -f "$dir/peaky" "$staging/peaky"
  chmod +x "$staging/peaky"
  rm -f "$archive"
  tar -C "$staging" -czf "$archive" peaky
  rm -rf "$staging"
  printf '%s' "$archive"
}

stage_peaky_release_archives() {
  local dest_dir=$1 ver=$2
  local triple missing=0
  ver="$(normalize_version "$ver")"
  mkdir -p "$dest_dir"
  while IFS= read -r triple || [[ -n "$triple" ]]; do
    [[ -n "$triple" ]] || continue
    if create_peaky_platform_archive "$ver" "$triple" "$dest_dir" >/dev/null 2>&1; then
      :
    else
      echo "warning: skip peaky $ver $triple — no staged binary" >&2
      missing=1
    fi
  done < <(list_peaky_release_triples)
  [[ "$missing" -eq 0 ]]
}

collect_peaky_release_assets() {
  local ver=$1 dest_dir=${2:-}
  local distro
  ver="$(normalize_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dest_dir="${dest_dir:-$(distro_release_root "$distro")}"
  stage_peaky_release_archives "$dest_dir" "$ver"
}

# --- distro helpers ---

package_artifact_status() {
  local id=$1 ver=$2 dir
  ver="$(normalize_package_version "$ver")"
  dir="$(package_build_dir "$id" "$ver")"
  if [[ ! -d "$dir" ]]; then
    printf '%smissing'
    return 0
  fi
  if is_package_tree_released "$id" "$ver"; then
    printf '%sreleased'
    return 0
  fi
  printf '%sready'
}

bump_package() {
  local id=$1 level=$2
  local old new major minor patch
  case "$id" in
    firmware) id=meshcore ;;
    meshcore | bootloader | adafruit-nrf52-bootloader | motatool | mcmt-gateway | peaky | envybot) ;;
    distro)
      echo "error: fleet tags live in MANIFEST.json releases — use ./envyos publish vX.Y.Z" >&2
      return 1
      ;;
    *)
      echo "error: unknown package '$id'" >&2
      return 1
      ;;
  esac
  old="$(read_manifest_key "$id" 2>/dev/null || read_optional_manifest_key "$id")" || return 1
  read -r major minor patch <<<"$(parse_version "$old")"
  case "$level" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *)
      echo "error: bump level must be patch, minor, or major" >&2
      return 1
      ;;
  esac
  new="v${major}.${minor}.${patch}"
  case "$id" in
    firmware) id=meshcore ;;
    bootloader | bl) id=adafruit-nrf52-bootloader ;;
  esac
  manifest_py set-version "$id" "${new#v}"
  printf '%s %s\n' "$old" "$new"
}

find_firmware_delta_motas() {
  local dir=$1 slug=$2 ver=$3
  local f
  shopt -s nullglob
  for f in \
    "$dir"/meshcore-"${slug}"-"${ver}"-delta-from-*.mota \
    "$dir"/meshcore-"${slug}"-delta-from-*.mota; do
    [[ -f "$f" ]] && printf '%s\n' "$(basename "$f")"
  done
  shopt -u nullglob
}

verify_release_delta_matrix() {
  local ver=$1
  local targets_file=$2
  local line slug base_ver base_image missing=0 delta_name
  local -a matrix_slugs=()

  [[ -f "$targets_file" ]] || {
    echo "error: targets file not found: $targets_file" >&2
    return 1
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue
    read -r slug _ <<<"$line"
    [[ -n "$slug" ]] || continue
    is_debug_target_slug "$slug" && continue
    matrix_slugs+=("$slug")
  done <"$targets_file"

  ensure_firmware_bases_for_build "$ver" "${matrix_slugs[@]}"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue
    read -r slug _ <<<"$line"
    [[ -n "$slug" ]] || continue
    is_debug_target_slug "$slug" && continue

    while IFS= read -r base_ver || [[ -n "$base_ver" ]]; do
      [[ -n "$base_ver" ]] || continue
      if ! resolve_base_image "$slug" "$base_ver" >/dev/null; then
        if is_released_firmware_version "$base_ver"; then
          echo "error: missing base image for $slug $base_ver (restore failed — cannot verify delta matrix)" >&2
          missing=1
        fi
        continue
      fi
      delta_name=""
      while IFS= read -r delta_name || [[ -n "$delta_name" ]]; do
        [[ -n "$delta_name" ]] && break
      done < <(find_firmware_delta_motas "$(firmware_slug_dir "$ver" "$ver" "$slug")" "$slug" "$ver")
      if [[ -z "$delta_name" ]]; then
        echo "error: missing delta for $slug $base_ver → $ver (base image exists)" >&2
        missing=1
      fi
    done < <(list_delta_base_versions "$ver")
  done <"$targets_file"

  [[ "$missing" -eq 0 ]]
}

# Archive entire distro bench (all firmware slugs, bootloader, motatool platforms, optional peaky/mcmt).
create_distro_full_tgz() {
  local distro_ver=${1:-}
  local root_name bench_dir release_dir tgz_path staging manifest notes id ver src pkg_name
  local -a included=()

  if [[ -z "$distro_ver" ]]; then
    distro_ver="$(read_bench_tree_key)"
  else
    distro_ver="$(normalize_tree_key "$distro_ver")"
  fi

  root_name="envyos-${distro_ver#v}-full"
  bench_dir="$(distro_bench_root "$distro_ver")"
  release_dir="$(distro_release_root "$distro_ver")"
  tgz_path="$release_dir/${root_name}.tgz"

  [[ -d "$bench_dir" ]] || {
    echo "error: missing bench tree at $bench_dir — run ./envyos build first" >&2
    return 1
  }

  staging="$(mktemp -d "${TMPDIR:-/tmp}/envyos-full.XXXXXX")"
  mkdir -p "$staging/$root_name/bench"

  shopt -s nullglob
  for src in "$bench_dir"/*; do
    [[ -d "$src" ]] || continue
    pkg_name="$(basename "$src")"
    [[ "$pkg_name" == .* ]] && continue
    cp -a "$src" "$staging/$root_name/bench/$pkg_name"
    included+=("$pkg_name")
  done
  shopt -u nullglob

  if package_in_distro_bundle mcmt-gateway "$distro_ver"; then
    ver="$(read_mcmt_gateway_version 2>/dev/null || true)"
    if [[ -n "$ver" ]]; then
      src="$(package_build_dir mcmt-gateway "$ver" "$distro_ver")"
      if [[ -d "$src" ]]; then
        pkg_name="$(basename "$src")"
        [[ -d "$staging/$root_name/bench/$pkg_name" ]] || {
          cp -a "$src" "$staging/$root_name/bench/$pkg_name"
          included+=("$pkg_name")
        }
      fi
    fi
  fi

  ((${#included[@]} > 0)) || {
    echo "error: no bench packages under $bench_dir — run ./envyos build first" >&2
    rm -rf "$staging"
    return 1
  }

  manifest="$(release_manifest_path "$distro_ver")"
  [[ -f "$manifest" ]] && cp "$manifest" "$staging/$root_name/RELEASE_MANIFEST"
  [[ -f "$MANIFEST_JSON" ]] && cp "$MANIFEST_JSON" "$staging/$root_name/MANIFEST.json"
  notes="$(distro_release_notes_path "$release_dir")"
  [[ -f "$notes" ]] && cp "$notes" "$staging/$root_name/$DISTRO_RELEASE_NOTES_FILENAME"

  {
    echo "# EnvyOS full bundle — $distro_ver"
    echo "# Generated $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    list_manifest
    echo ""
    echo "# bench packages"
    for pkg_name in "${included[@]}"; do
      printf '%s\n' "$pkg_name"
    done
  } >"$staging/$root_name/BUNDLE.txt"

  rm -f "$tgz_path"
  tar -czf "$tgz_path" \
    --exclude='.DS_Store' \
    -C "$staging" "$root_name"
  rm -rf "$staging"

  echo "bundle:   $tgz_path ($(du -h "$tgz_path" | awk '{print $1}'))"
  printf '%s\n' "$tgz_path"
}

# --- release tree from bench (GitHub upload preview) ---

populate_distro_release() {
  local distro_ver=${1:-}
  local fw_ver bl_ver mt_ver peaky_ver mcmt_ver envybot_ver release_dir slug src dst f board uf2 zip wheel
  local notes_ver notes_preview notes_path
  local -a staged=()

  if [[ -z "$distro_ver" ]]; then
    distro_ver="$(read_bench_tree_key)"
  else
    distro_ver="$(normalize_tree_key "$distro_ver")"
  fi
  if is_released_version "$distro_ver" 2>/dev/null; then
    fw_ver="$(manifest_package_version firmware "$distro_ver")"
    bl_ver="$(manifest_package_version bootloader "$distro_ver")"
    mt_ver="$(manifest_package_version motatool "$distro_ver")"
  else
    fw_ver="$(read_firmware_version)"
    bl_ver="$(read_bootloader_version)"
    mt_ver="$(read_motatool_version)"
  fi
  fw_ver="$(normalize_package_version "$fw_ver")"
  bl_ver="$(normalize_package_version "$bl_ver")"
  mt_ver="$(normalize_package_version "$mt_ver")"

  release_dir="$(distro_release_root "$distro_ver")"
  rm -rf "$release_dir"
  mkdir -p "$release_dir"

  echo "==> release assets → $release_dir"

  if read -r notes_ver notes_preview < <(distro_release_notes_args "$distro_ver"); then
    notes_path="$(write_distro_release_notes "$notes_ver" "$release_dir" "$notes_preview")"
    echo "notes:    $notes_path"
    staged+=("$notes_path")
  fi

  while IFS= read -r slug || [[ -n "$slug" ]]; do
    [[ -n "$slug" ]] || continue
    src="$(firmware_slug_dir "$distro_ver" "$fw_ver" "$slug")"
    [[ -d "$src" ]] || continue
    for f in "$src"/*.mota "$src"/*.uf2; do
      [[ -f "$f" ]] || continue
      dst="$(stage_gzip_named "$f" "$release_dir" "$(basename "$f")")"
      staged+=("$dst")
    done
  done < <(list_release_target_slugs_from_file "$TARGETS_FILE")

  if [[ -d "$(bootloader_bench_root "$distro_ver" "$bl_ver")" ]]; then
    local bl_bench
    bl_bench="$(bootloader_bench_root "$distro_ver" "$bl_ver")"
    for uf2 in "$bl_bench"/*_bootloader-*.uf2; do
      [[ -f "$uf2" ]] || continue
      board="${uf2##*/}"
      board="${board%%_bootloader-*}"
      dst="$(stage_gzip_named "$uf2" "$release_dir" "$(bootloader_flat_uf2_name "$board" "$bl_ver")")"
      staged+=("$dst")
    done
    for zip in "$bl_bench"/*_bootloader-*.recovery.zip; do
      [[ -f "$zip" ]] || continue
      board="${zip##*/}"
      board="${board%%_bootloader-*}"
      dst="$release_dir/$(bootloader_flat_recovery_name "$board" "$bl_ver")"
      cp -f "$zip" "$dst"
      staged+=("$dst")
    done
  fi

  stage_motatool_release_archives "$release_dir" "$mt_ver" || true
  if peaky_ver="$(read_optional_manifest_key peaky 2>/dev/null)"; then
    stage_peaky_release_archives "$release_dir" "$peaky_ver" || true
  fi
  if package_in_distro_bundle mcmt-gateway "$distro_ver"; then
    mcmt_ver="$(read_mcmt_gateway_version)"
    wheel="$(mcmt_gateway_bench_root "$distro_ver" "$mcmt_ver")/$(mcmt_gateway_wheel_basename "$mcmt_ver")"
    if [[ -f "$wheel" ]]; then
      dst="$release_dir/$(basename "$wheel")"
      cp -f "$wheel" "$dst"
      staged+=("$dst")
    fi
  fi
  if envybot_ver="$(read_optional_manifest_key envybot 2>/dev/null)"; then
    wheel="$(envybot_bench_root "$distro_ver" "$envybot_ver")/$(envybot_wheel_basename "$envybot_ver")"
    if [[ -f "$wheel" ]]; then
      dst="$release_dir/$(basename "$wheel")"
      cp -f "$wheel" "$dst"
      staged+=("$dst")
    fi
  fi

  full_tgz=""
  full_tgz="$(create_distro_full_tgz "$distro_ver")"
  staged+=("$full_tgz")

  while IFS= read -r dst || [[ -n "$dst" ]]; do
    [[ -n "$dst" ]] || continue
    staged+=("$dst")
  done < <(find "$release_dir" -maxdepth 1 -type f ! -name MANIFEST.txt -print 2>/dev/null)

  {
    echo "# EnvyOS release assets for $distro_ver"
    echo "# Generated $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    list_manifest
    echo ""
    echo "# GitHub release assets"
    for dst in "${staged[@]}"; do
      printf '%s\n' "$(basename "$dst")"
    done | sort -u
  } >"$release_dir/MANIFEST.txt"

  echo ""
  echo "Release tree: $release_dir"
  echo "  $(find "$release_dir" -maxdepth 1 -type f ! -name MANIFEST.txt | wc -l | tr -d ' ') files — see MANIFEST.txt"
  ls -la "$release_dir"
}

# Back-compat alias (removed from CLI; scripts may still call it).
stage_distro_release_preview() {
  populate_distro_release "$@"
}
