#!/usr/bin/env bash
# EnvyOS distro manifest + publish helpers. Component builds live in sibling repos.
set -euo pipefail

OTA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVYOS_VERSIONS_FILE="$OTA_ROOT/ENVYOS_VERSIONS"
RELEASED_VERSIONS_FILE="$OTA_ROOT/RELEASED_VERSIONS"
COMPONENTS_LOCK_FILE="$OTA_ROOT/COMPONENTS.lock"
PACKAGES_ROOT="$OTA_ROOT/packages"
PACKAGES_META_ROOT="$OTA_ROOT/packages-meta"

MESHENVY_ROOT="$(cd "$OTA_ROOT/../.." && pwd)"
MESHCORE_ROOT="${MESHCORE_ROOT:-$PACKAGES_ROOT/meshcore}"
BOOTLOADER_SRC="${BOOTLOADER_SRC:-$PACKAGES_ROOT/bootloader}"
MCMT_ROOT="${MCMT_ROOT:-$PACKAGES_ROOT/mcmt-gateway}"
MOTATOOL_ROOT="${MOTATOOL_ROOT:-$PACKAGES_ROOT/motatool}"
MESHCORE_OPEN_ROOT="${MESHCORE_OPEN_ROOT:-$PACKAGES_ROOT/meshcore-open}"
PEAKY_ROOT="${PEAKY_ROOT:-$MESHENVY_ROOT/peaky_finders}"

BUILD_ROOT="$OTA_ROOT/build"
PEAKY_GITHUB_REPO="${PEAKY_GITHUB_REPO:-MeshEnvy/peaky-finders}"
RELEASED_FIRMWARE_FILE="$OTA_ROOT/RELEASED_FIRMWARE"
RELEASED_BOOTLOADER_FILE="$OTA_ROOT/RELEASED_BOOTLOADER"

export ENVYOS_ROOT="$OTA_ROOT"
export RELEASED_VERSIONS_FILE
export MESHCORE_ROOT BOOTLOADER_SRC MOTATOOL_ROOT MESHCORE_OPEN_ROOT PEAKY_ROOT PACKAGES_ROOT PACKAGES_META_ROOT
# Back-compat alias


# shellcheck source=scripts/packages-meta-lib.sh
source "$OTA_ROOT/scripts/packages-meta-lib.sh"

normalize_version() {
  local v="${1#v}"
  if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid version '$1' (want vMAJOR.MINOR.PATCH)" >&2
    return 1
  fi
  printf 'v%s' "$v"
}

read_envyos_version_key() {
  local key=$1
  local line k val
  [[ -f "$ENVYOS_VERSIONS_FILE" ]] || {
    echo "error: missing $ENVYOS_VERSIONS_FILE" >&2
    return 1
  }
  case "$key" in
    firmware) key=meshcore ;;
  esac
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue
    k="${line%%=*}"
    k="${k%"${k##*[![:space:]]}"}"
    [[ "$k" == "$key" ]] || continue
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    case "$key" in
      meshcore | bootloader | motatool)
        normalize_package_version "$val"
        ;;
      *)
        normalize_version "$val"
        ;;
    esac
    return 0
  done <"$ENVYOS_VERSIONS_FILE"
  echo "error: missing key '$key' in $ENVYOS_VERSIONS_FILE" >&2
  return 1
}

# Optional manifest keys (peaky, mcmt-gateway) — absent until pinned for a distro bundle.
read_optional_envyos_version_key() {
  local key=$1
  local line k val
  [[ -f "$ENVYOS_VERSIONS_FILE" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue
    k="${line%%=*}"
    k="${k%"${k##*[![:space:]]}"}"
    [[ "$k" == "$key" ]] || continue
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    [[ -n "$val" ]] || return 1
    normalize_version "$val"
    return 0
  done <"$ENVYOS_VERSIONS_FILE"
  return 1
}

read_distro_version() { read_envyos_version_key distro; }
read_meshcore_version() { read_envyos_version_key meshcore; }
read_firmware_version() { read_meshcore_version; }
read_bootloader_version() { read_envyos_version_key bootloader; }
read_motatool_version() { read_envyos_version_key motatool; }
read_peaky_version() { read_optional_envyos_version_key peaky; }

# Back-compat aliases used by build scripts.
read_version_file() { read_distro_version; }
read_bootloader_version_file() { read_bootloader_version; }

list_envyos_versions() {
  local key ver
  for key in distro meshcore bootloader motatool; do
    printf '%s=%s\n' "$key" "$(read_envyos_version_key "$key")"
  done
  if ver="$(read_optional_envyos_version_key mcmt-gateway 2>/dev/null)"; then
    printf 'mcmt-gateway=%s\n' "${ver#v}"
  fi
  if ver="$(read_optional_envyos_version_key peaky 2>/dev/null)"; then
    printf 'peaky=%s\n' "${ver#v}"
  fi
}

# Match firmware CLI display: "6 Jun 2026" (no leading zero on day).
format_firmware_build_date() {
  local d
  d="$(LC_TIME=C date '+%d %b %Y')"
  printf '%s' "${d#0}"
}

# version.txt: line 1 = distro tag, line 2 = build date.
write_mota_version_txt() {
  local dir=$1 ver=$2 build_date=$3 git_sha=${4:-}
  if [[ -n "$git_sha" ]]; then
    printf '%s\n%s\n%s\n' "$ver" "$build_date" "$git_sha" >"$dir/version.txt"
  else
    printf '%s\n%s\n' "$ver" "$build_date" >"$dir/version.txt"
  fi
}

verify_firmware_version_sync() {
  return 0
}

verify_motatool_version_sync() {
  return 0
}

verify_peaky_version_sync() {
  local expected="${1#v}"
  local cargo="$PEAKY_ROOT/Cargo.toml"
  [[ -f "$cargo" ]] || return 0
  local actual
  actual="$(awk '/^\[workspace.package\]/{f=1;next} /^\[/{if(f) exit} f && /^version = /{gsub(/^version = "|"$/,""); print; exit}' "$cargo")"
  [[ "$actual" == "$expected" ]] || {
    echo "error: peaky_finders/Cargo.toml version ($actual) != ENVYOS_VERSIONS peaky ($expected)" >&2
    return 1
  }
}

peaky_host_rust_target() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os-$arch" in
    Linux-x86_64) printf '%s' 'x86_64-unknown-linux-gnu' ;;
    Linux-aarch64 | Linux-arm64) printf '%s' 'aarch64-unknown-linux-gnu' ;;
    Darwin-arm64) printf '%s' 'aarch64-apple-darwin' ;;
    Darwin-x86_64) printf '%s' 'x86_64-apple-darwin' ;;
    *)
      echo "error: unsupported host for peaky local build: $os $arch" >&2
      return 1
      ;;
  esac
}

peaky_cache_has_binary() {
  local ver=$1 dir sub distro
  ver="$(normalize_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dir="$(peaky_bench_root "$distro" "$ver")"
  [[ -d "$dir" ]] || return 1
  if [[ -x "$dir/peaky" ]]; then
    return 0
  fi
  for sub in "$dir"/peaky-*; do
    [[ -d "$sub" ]] || continue
    [[ -x "$sub/peaky" ]] && return 0
  done
  return 1
}

build_peaky_local() {
  local ver=$1 target ver_plain staging bin distro
  ver="$(normalize_version "$ver")"
  ver_plain="${ver#v}"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  target="$(peaky_host_rust_target)" || return 1
  staging="$(peaky_staged_binary_dir "$ver" "$target" "$distro")"
  mkdir -p "$staging"
  echo "peaky: cargo build --release -p peaky ($target)"
  (
    cd "$PEAKY_ROOT"
    cargo build --locked --release -p peaky --target "$target"
  )
  bin="$PEAKY_ROOT/target/$target/release/peaky"
  [[ -x "$bin" ]] || {
    echo "error: peaky build did not produce $bin" >&2
    return 1
  }
  cp -f "$bin" "$staging/peaky"
  if command -v strip >/dev/null 2>&1; then
    strip "$staging/peaky" 2>/dev/null || true
  fi
  printf '%s\n' "$ver" >"$(peaky_bench_root "$distro" "$ver")/version.txt"
  echo "peaky: staged $staging/peaky"
}

download_peaky_release_assets() {
  local ver=$1 missing_only=${2:-0}
  local dir tag tgz sub distro
  ver="$(normalize_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dir="$(peaky_bench_root "$distro" "$ver")"
  mkdir -p "$dir"
  tag="${ver#v}"
  tag="v$tag"
  echo "peaky: downloading $tag from $PEAKY_GITHUB_REPO into $dir"
  gh release download "$tag" -R "$PEAKY_GITHUB_REPO" -D "$dir" || {
    echo "error: gh release download failed for $PEAKY_GITHUB_REPO $tag" >&2
    return 1
  }
  for tgz in "$dir"/*.tar.gz; do
    [[ -f "$tgz" ]] || continue
    sub="${tgz%.tar.gz}"
    sub="${sub##*/}"
    if ((missing_only == 1)) && [[ -x "$dir/$sub/peaky" ]]; then
      rm -f "$tgz"
      continue
    fi
    mkdir -p "$dir/$sub"
    tar -xzf "$tgz" -C "$dir/$sub"
    rm -f "$tgz"
  done
  printf '%s\n' "$ver" >"$dir/version.txt"
}

# v0.1.1 → 0 1 1 (stdout: major minor patch)
parse_version() {
  local v="${1#v}"
  local major minor patch
  IFS=. read -r major minor patch <<<"$v"
  printf '%s %s %s' "$major" "$minor" "$patch"
}

# True when ver is listed in RELEASED_VERSIONS (shipped, immutable mota tree).
is_released_version() {
  local ver line
  ver="$(normalize_version "$1")" || return 1
  [[ -f "$RELEASED_VERSIONS_FILE" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    if [[ "$(normalize_version "$line")" == "$ver" ]]; then
      return 0
    fi
  done <"$RELEASED_VERSIONS_FILE"
  return 1
}

assert_version_not_released() {
  local ver="$1"
  if is_released_firmware_version "$ver" || is_released_version "$ver"; then
    echo "error: $ver is released — $(firmware_bench_root "$ver" "$ver") is immutable" >&2
    echo "       (listed in RELEASED_FIRMWARE or RELEASED_VERSIONS)" >&2
    exit 1
  fi
}

# Zero-padded key for portable version sort (macOS sort lacks -V).
version_sort_key() {
  local major minor patch
  read -r major minor patch <<<"$(parse_version "$1")"
  printf '%03d.%03d.%03d' "$major" "$minor" "$patch"
}

# Print unique versions sorted ascending (args: v0.1.0 v0.1.2 …).
sort_versions() {
  local v seen=""
  for v in "$@"; do
    case "$seen" in
      *"|$v|"*) continue ;;
    esac
    seen="${seen}|$v|"
    printf '%s\t%s\n' "$(version_sort_key "$v")" "$v"
  done | sort -t $'\t' -k1,1 | cut -f2-
}

# True when ver_a < ver_b (both normalized vMAJOR.MINOR.PATCH).
version_lt() {
  local a b
  a="$(normalize_version "$1")" || return 1
  b="$(normalize_version "$2")" || return 1
  local am aj ap bm bj bp
  read -r am aj ap <<<"$(parse_version "$a")"
  read -r bm bj bp <<<"$(parse_version "$b")"
  if (( am != bm )); then
    (( am < bm ))
    return
  fi
  if (( aj != bj )); then
    (( aj < bj ))
    return
  fi
  (( ap < bp ))
}

# list_known_mota_versions, resolve_base_image, verify_release_delta_matrix → build-lib.sh

list_delta_base_versions() {
  local target ver
  target="$(normalize_version "$1")" || return 1
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    if version_lt "$ver" "$target"; then
      printf '%s\n' "$ver"
    fi
  done < <(list_known_mota_versions)
}

# v0.1.1 → v0.1.0; v0.1.0 → (empty)
previous_patch_version() {
  local ver="$1"
  local major minor patch
  read -r major minor patch <<<"$(parse_version "$ver")"
  if [[ "$patch" -eq 0 ]]; then
    return 0
  fi
  printf 'v%s.%s.%s' "$major" "$minor" "$((patch - 1))"
}

# v0.1.1 → v0.1.2
next_patch_version() {
  local ver="$1"
  local major minor patch
  read -r major minor patch <<<"$(parse_version "$ver")"
  printf 'v%s.%s.%s' "$major" "$minor" "$((patch + 1))"
}

write_envyos_versions() {
  local ver="${1#v}"
  local meshcore bootloader motatool mcmt peaky
  meshcore="$(read_meshcore_version 2>/dev/null || echo 1.16.0-ev1)"
  bootloader="$(read_bootloader_version 2>/dev/null || echo 0.9.2-ev1)"
  motatool="$(read_motatool_version 2>/dev/null || echo 0.1.1-ev1)"
  mcmt="$(read_optional_envyos_version_key mcmt-gateway 2>/dev/null || true)"
  peaky="$(read_optional_envyos_version_key peaky 2>/dev/null || true)"
  cat >"$ENVYOS_VERSIONS_FILE" <<EOF
# EnvyOS package versions — see docs/distro-packaging.md
distro=$ver
meshcore=$meshcore
bootloader=$bootloader
motatool=$motatool
EOF
  if [[ -n "$mcmt" ]]; then
    printf 'mcmt-gateway=%s\n' "${mcmt#v}" >>"$ENVYOS_VERSIONS_FILE"
  fi
  if [[ -n "$peaky" ]]; then
    printf 'peaky=%s\n' "${peaky#v}" >>"$ENVYOS_VERSIONS_FILE"
  fi
}

write_firmware_version_file() {
  return 0
}

write_motatool_cargo_version() {
  return 0
}

append_released_version() {
  local ver="$1"
  if is_released_version "$ver"; then
    echo "error: $ver is already listed in RELEASED_VERSIONS" >&2
    return 1
  fi
  printf '%s\n' "$ver" >>"$RELEASED_VERSIONS_FILE"
}

read_mcmt_gateway_version() { read_envyos_version_key mcmt-gateway; }

read_components_lock_key() {
  local key=$1
  local line k val
  [[ -f "$COMPONENTS_LOCK_FILE" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue
    k="${line%%=*}"
    k="${k%"${k##*[![:space:]]}"}"
    [[ "$k" == "$key" ]] || continue
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    printf '%s' "$val"
    return 0
  done <"$COMPONENTS_LOCK_FILE"
  return 1
}

write_components_lock() {
  local firmware_sha=$1 bootloader_sha=$2 mcmt_sha=${3:-}
  cat >"$COMPONENTS_LOCK_FILE" <<EOF
# Git component pins — updated at publish; dev branch tracks integration heads
firmware_repo=MeshEnvy/meshcore-firmware
firmware_sha=$firmware_sha
bootloader_repo=MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX
bootloader_sha=$bootloader_sha
mcmt_gateway_repo=MeshEnvy/mcmt-gateway
mcmt_gateway_sha=${mcmt_sha:-}
EOF
}

verify_sibling_sha() {
  local repo_path=$1 expected_sha=$2 label=$3
  [[ -n "$expected_sha" ]] || return 0
  local actual
  actual="$(git -C "$repo_path" rev-parse HEAD 2>/dev/null)" || {
    echo "error: cannot read HEAD for $label at $repo_path" >&2
    return 1
  }
  [[ "$actual" == "$expected_sha" ]] || {
    echo "error: $label HEAD ($actual) != COMPONENTS.lock ($expected_sha)" >&2
    return 1
  }
}

verify_components_lock() {
  local fw bl mcmt
  fw="$(read_components_lock_key firmware_sha 2>/dev/null || true)"
  bl="$(read_components_lock_key bootloader_sha 2>/dev/null || true)"
  mcmt="$(read_components_lock_key mcmt_gateway_sha 2>/dev/null || true)"
  verify_sibling_sha "$MESHCORE_ROOT" "$fw" meshcore || return 1
  verify_sibling_sha "$BOOTLOADER_SRC" "$bl" bootloader || return 1
  if [[ -n "$mcmt" ]]; then
    verify_sibling_sha "$MCMT_ROOT" "$mcmt" mcmt-gateway || return 1
  fi
}

component_in_distro_bundle() {
  local id=$1 distro_ver=$2
  case "$id" in
    mcmt-gateway)
      read_optional_envyos_version_key mcmt-gateway >/dev/null 2>&1 && return 0
      is_version_tree_key "$distro_ver" || return 1
      local major minor patch
      read -r major minor patch <<<"$(parse_version "$distro_ver")"
      (( major > 0 || minor >= 2 ))
      ;;
    peaky)
      read_optional_envyos_version_key peaky >/dev/null 2>&1
      ;;
    *) return 0 ;;
  esac
}

ensure_motatool_release_cache() {
  local ver=$1
  ver="$(normalize_version "$ver")"
  local dir distro
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dir="$(motatool_bench_root "$distro" "$ver")"

  if motatool_all_platforms_present "$ver"; then
    return 0
  fi

  if is_component_tree_released motatool "$ver"; then
    echo "error: motatool $ver is a released tree — $dir is immutable" >&2
    return 1
  fi

  local host
  host="$(host_motatool_platform_slug 2>/dev/null || true)"
  if [[ -n "$host" ]] && ! motatool_platform_has_binary "$ver" "$host"; then
    if [[ -d "$MOTATOOL_ROOT" ]] && command -v cargo >/dev/null 2>&1; then
      "$OTA_ROOT/packages-meta/motatool/build.sh" --host-only || true
    fi
  fi

  if command -v gh >/dev/null 2>&1; then
    download_motatool_release_assets "$ver" 1 || true
  fi

  if motatool_all_platforms_present "$ver"; then
    return 0
  fi

  if command -v gh >/dev/null 2>&1; then
    download_motatool_release_assets "$ver" 0 || true
  fi

  motatool_all_platforms_present "$ver" || {
    echo "error: motatool $ver missing platform binaries under $dir" >&2
    echo "       need: $(list_motatool_release_platforms | paste -sd' ' -)" >&2
    echo "       run: ./envyos build motatool" >&2
    return 1
  }
}

download_motatool_release_assets() {
  local ver=$1 missing_only=${2:-0}
  local dir tag tgz base triple platform tmp out distro
  ver="$(normalize_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dir="$(motatool_bench_root "$distro" "$ver")"
  mkdir -p "$dir"
  tag="${ver#v}"
  tag="v$tag"
  echo "motatool: downloading $tag from MeshEnvy/motatool into $dir"
  gh release download "$tag" -R MeshEnvy/motatool -D "$dir" || {
    echo "error: gh release download failed for MeshEnvy/motatool $tag" >&2
    return 1
  }
  for tgz in "$dir"/motatool-*.tar.gz; do
    [[ -f "$tgz" ]] || continue
    base="$(basename "$tgz")"
    triple="$(motatool_triple_from_archive_basename "$base")" || continue
    platform="$(motatool_platform_from_triple "$triple")" || continue
    out="$(motatool_staged_binary_path "$platform")"
    if ((missing_only == 1)) && [[ -x "$out" ]]; then
      rm -f "$tgz"
      continue
    fi
    tmp="$(mktemp -d)"
    tar -xzf "$tgz" -C "$tmp"
    [[ -x "$tmp/motatool" ]] || {
      rm -rf "$tmp"
      rm -f "$tgz"
      continue
    }
    mkdir -p "$(dirname "$out")"
    cp -f "$tmp/motatool" "$out"
    chmod +x "$out"
    rm -rf "$tmp" "$tgz"
    record_motatool_platform_staged "$ver" "$platform"
  done
}

ensure_peaky_release_cache() {
  local ver=$1
  ver="$(normalize_version "$ver")"
  local dir distro
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dir="$(peaky_bench_root "$distro" "$ver")"

  if peaky_all_platforms_present "$ver"; then
    return 0
  fi

  [[ -d "$PEAKY_ROOT" ]] || {
    echo "error: peaky repo not found at $PEAKY_ROOT" >&2
    return 1
  }

  if is_component_tree_released peaky "$ver"; then
    echo "error: peaky $ver is a released tree — $dir is immutable" >&2
    return 1
  fi

  local host_triple triple
  host_triple="$(peaky_host_rust_target 2>/dev/null || true)"
  if [[ -n "$host_triple" ]] && ! peaky_platform_has_binary "$ver" "$host_triple"; then
    if command -v cargo >/dev/null 2>&1; then
      build_peaky_local "$ver" || true
    fi
  fi

  if command -v gh >/dev/null 2>&1; then
    download_peaky_release_assets "$ver" 1 || true
  fi

  if peaky_all_platforms_present "$ver"; then
    return 0
  fi

  if command -v gh >/dev/null 2>&1; then
    download_peaky_release_assets "$ver" 0 || true
  fi

  peaky_all_platforms_present "$ver" || {
    echo "error: peaky $ver missing platform binaries under $dir" >&2
    echo "       need: $(list_peaky_release_triples | paste -sd' ' -)" >&2
    return 1
  }
}

write_released_marker() {
  local ver="$1"
  local dir
  dir="$(firmware_bench_root "$ver" "$ver")"
  local today
  today="$(date '+%Y-%m-%d')"
  cat >"$dir/.released" <<EOF
EnvyOS $ver — released $today. Do not delete or rebuild this directory.
Listed in RELEASED_VERSIONS; the meshcore recipe refuses to overwrite released versions.
Includes delta_from_<base>.mota for every prior version with base hex (fleet jump updates).
EOF
}

# Distro release bundles these components (extend list when adding packages).
list_release_component_ids() {
  local distro_ver="${1:-}"
  if [[ -z "$distro_ver" ]]; then
    distro_ver="$(read_distro_version 2>/dev/null || echo v0.0.0)"
  fi
  printf '%s\n' firmware bootloader motatool
  if component_in_distro_bundle mcmt-gateway "$distro_ver"; then
    printf '%s\n' mcmt-gateway
  fi
  if component_in_distro_bundle peaky "$distro_ver"; then
    printf '%s\n' peaky
  fi
}

component_build_root() {
  local id=$1 distro_ver=${2:-}
  distro_ver="${distro_ver:-$(read_bench_tree_key 2>/dev/null || echo dev)}"
  case "$id" in
    firmware | bootloader | motatool | peaky) distro_bench_root "$distro_ver" ;;
    mcmt-gateway) printf '%s/dist' "$MCMT_ROOT" ;;
    *)
      echo "error: unknown release component: $1" >&2
      return 1
      ;;
  esac
}

# Component version pinned in ENVYOS_VERSIONS (or equals distro tag after publish).
component_version_at_publish() {
  local id=$1 distro_ver=$2
  case "$id" in
    firmware) read_firmware_version ;;
    bootloader) read_bootloader_version ;;
    motatool) read_motatool_version ;;
    mcmt-gateway) read_mcmt_gateway_version ;;
    peaky) read_peaky_version ;;
    *)
      echo "error: unknown release component: $id" >&2
      return 1
      ;;
  esac
}

component_build_dir() {
  local id=$1 ver=$2 distro_ver=${3:-}
  distro_ver="${distro_ver:-$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")}"
  case "$id" in
    firmware) firmware_bench_root "$distro_ver" "$ver" ;;
    bootloader) bootloader_bench_root "$distro_ver" "$ver" ;;
    motatool) motatool_bench_root "$distro_ver" "$ver" ;;
    peaky) peaky_bench_root "$distro_ver" "$ver" ;;
    mcmt-gateway) printf '%s/%s' "$MCMT_ROOT/dist" "$ver" ;;
    *)
      echo "error: unknown release component: $id" >&2
      return 1
      ;;
  esac
}

component_zip_basename() {
  local id=$1 ver=$2
  case "$id" in
    firmware) printf 'firmware-%s.zip' "$ver" ;;
    bootloader) printf 'bootloader-%s.zip' "$ver" ;;
    motatool) printf 'motatool-%s.zip' "$ver" ;;
    mcmt-gateway) printf 'mcmt-gateway-%s.zip' "$ver" ;;
    peaky) printf 'peaky-%s.zip' "$ver" ;;
  esac
}

component_zip_path() {
  local id=$1 ver=$2
  printf '%s/%s' "$OTA_ROOT" "$(component_zip_basename "$id" "$ver")"
}

is_component_tree_released() {
  local id=$1 ver=$2
  [[ -f "$(component_build_dir "$id" "$ver")/.released" ]]
}

assert_component_tree_not_released() {
  local id=$1 ver=$2
  if is_component_tree_released "$id" "$ver"; then
    echo "error: $ver is a released $id tree — $(component_build_dir "$id" "$ver") is immutable" >&2
    exit 1
  fi
}

write_component_released_marker() {
  local id=$1 ver=$2 distro_ver=$3
  local dir today
  dir="$(component_build_dir "$id" "$ver")"
  today="$(date '+%Y-%m-%d')"
  cat >"$dir/.released" <<EOF
EnvyOS component $id $ver — published in distro $distro_ver on $today.
Do not delete or rebuild this directory.
EOF
}

write_release_manifest() {
  local distro_ver=$1 firmware_ver=$2 bootloader_ver=$3 motatool_ver=$4
  local dir today peaky_ver mcmt_ver
  dir="$(distro_tree_root "$distro_ver")"
  today="$(date '+%Y-%m-%d')"
  mkdir -p "$dir"
  cat >"$(release_manifest_path "$distro_ver")" <<EOF
# EnvyOS distro release manifest (immutable snapshot at publish)
distro=$distro_ver
firmware=$firmware_ver
bootloader=$bootloader_ver
motatool=$motatool_ver
published=$today
EOF
  if component_in_distro_bundle mcmt-gateway "$distro_ver"; then
    mcmt_ver="$(read_mcmt_gateway_version)"
    printf 'mcmt-gateway=%s\n' "$mcmt_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
  if component_in_distro_bundle peaky "$distro_ver"; then
    peaky_ver="$(read_peaky_version)"
    printf 'peaky=%s\n' "$peaky_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
}

read_release_manifest_key() {
  local distro_ver=$1 key=$2
  local file line k val from_gh
  file="$(release_manifest_path "$distro_ver")"
  if [[ ! -f "$file" ]]; then
    file="$(firmware_bench_root "$distro_ver" "$distro_ver")/RELEASE_MANIFEST"
  fi
  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      [[ -n "$line" ]] || continue
      k="${line%%=*}"
      k="${k%"${k##*[![:space:]]}"}"
      [[ "$k" == "$key" ]] || continue
      val="${line#*=}"
      val="${val#"${val%%[![:space:]]*}"}"
      val="${val%"${val##*[![:space:]]}"}"
      if [[ "$key" == "published" ]]; then
        printf '%s' "$val"
      else
        normalize_version "$val"
      fi
      return 0
    done <"$file"
  fi
  from_gh="$(read_release_manifest_key_from_github "$distro_ver" "$key" 2>/dev/null || true)"
  [[ -n "$from_gh" ]] || return 1
  if [[ "$key" == "published" ]]; then
    printf '%s' "$from_gh"
  else
    normalize_version "$from_gh"
  fi
}

read_release_manifest_key_from_github() {
  local distro_ver=$1 key=$2
  command -v gh >/dev/null 2>&1 || return 1
  gh release view "$distro_ver" --json body -q .body 2>/dev/null | awk -v want="$key" '
    /^\|/ && $0 !~ /Component/ && $0 !~ /---/ {
      n = split($0, cells, "|")
      for (i = 1; i <= n; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", cells[i])
      }
      if (cells[2] == want && cells[3] != "") {
        print cells[3]
        exit 0
      }
    }
  '
}

manifest_component_version() {
  local id=$1 distro_ver=$2
  local from_manifest ver legacy
  if from_manifest="$(read_release_manifest_key "$distro_ver" "$id" 2>/dev/null)"; then
    printf '%s' "$from_manifest"
    return 0
  fi
  ver=""
  if is_version_tree_key "$distro_ver"; then
    ver="$(normalize_version "$distro_ver")"
  fi
  if [[ -n "$ver" && -d "$(component_build_dir "$id" "$ver" "$distro_ver")" ]]; then
    printf '%s' "$ver"
    return 0
  fi
  if [[ "$id" == firmware ]]; then
    ver="$(read_firmware_version 2>/dev/null || true)"
    if [[ -n "$ver" && -d "$(component_build_dir "$id" "$ver" "$distro_ver")" ]]; then
      printf '%s' "$ver"
      return 0
    fi
  fi
  if [[ "$id" != firmware ]]; then
    while IFS= read -r legacy || [[ -n "$legacy" ]]; do
      [[ -n "$legacy" ]] || continue
      if version_lt "$legacy" "$distro_ver" && [[ -d "$(component_build_dir "$id" "$legacy" "$distro_ver")" ]]; then
        printf '%s' "$legacy"
        return 0
      fi
    done < <(list_known_mota_versions)
  fi
  component_version_at_publish "$id" "$distro_ver"
}

ensure_release_manifest_for_backfill() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver published mcmt_ver peaky_ver
  [[ -f "$(release_manifest_path "$distro_ver")" ]] && return 0
  [[ -f "$(firmware_bench_root "$distro_ver" "$distro_ver")/RELEASE_MANIFEST" ]] && return 0
  [[ -f "$(distro_bench_root "$distro_ver")/firmware/RELEASE_MANIFEST" ]] && return 0
  firmware_ver="$(manifest_component_version firmware "$distro_ver")"
  bootloader_ver="$(manifest_component_version bootloader "$distro_ver")"
  motatool_ver="$(manifest_component_version motatool "$distro_ver")"
  published="$(date '+%Y-%m-%d')"
  if [[ -f "$(distro_tree_root "$distro_ver")/.released" ]]; then
    published="$(sed -n 's/.*released \([0-9-]*\).*/\1/p' "$(distro_tree_root "$distro_ver")/.released" | head -1)"
    [[ -n "$published" ]] || published="$(date '+%Y-%m-%d')"
  fi
  mkdir -p "$(distro_tree_root "$distro_ver")"
  cat >"$(release_manifest_path "$distro_ver")" <<EOF
# EnvyOS distro release manifest (backfilled at asset upload)
distro=$distro_ver
firmware=$firmware_ver
bootloader=$bootloader_ver
motatool=$motatool_ver
published=$published
EOF
  if component_in_distro_bundle mcmt-gateway "$distro_ver"; then
    mcmt_ver="$(manifest_component_version mcmt-gateway "$distro_ver")"
    printf 'mcmt-gateway=%s\n' "$mcmt_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
  if component_in_distro_bundle peaky "$distro_ver"; then
    peaky_ver="$(manifest_component_version peaky "$distro_ver")"
    printf 'peaky=%s\n' "$peaky_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
}

verify_release_components() {
  local distro_ver=$1
  local motatool_ver
  local id ver dir

  motatool_ver="$(read_motatool_version)" || return 1

  ensure_motatool_release_cache "$motatool_ver"

  while IFS= read -r id || [[ -n "$id" ]]; do
    ver="$(component_version_at_publish "$id" "$distro_ver")" || return 1
    if [[ "$id" == motatool ]]; then
      ensure_motatool_release_cache "$ver" || return 1
    fi
    if [[ "$id" == peaky ]]; then
      verify_peaky_version_sync "$ver" || return 1
      ensure_peaky_release_cache "$ver" || return 1
    fi
    dir="$(component_build_dir "$id" "$ver" "$distro_ver")"
    [[ -d "$dir" ]] || {
      echo "error: missing $id artifacts at $dir — run ./envyos build first" >&2
      return 1
    }
    if [[ -f "$dir/version.txt" ]]; then
      local actual
      actual="$(head -1 "$dir/version.txt" | tr -d '[:space:]]')"
      [[ "$(normalize_component_version "$actual")" == "$ver" ]] || {
        echo "error: $dir/version.txt ($actual) != expected $ver" >&2
        return 1
      }
    fi
  done < <(list_release_component_ids "$distro_ver")

  verify_components_lock || true
  verify_release_delta_matrix "$distro_ver" "$OTA_ROOT/scripts/targets.txt"
}

create_component_zip() {
  local id=$1 ver=$2
  local src zip base
  src="$(component_build_dir "$id" "$ver")"
  zip="$(component_zip_path "$id" "$ver")"
  base="$(basename "$src")"
  [[ -d "$src" ]] || {
    echo "error: missing $src" >&2
    return 1
  }
  rm -f "$zip"
  (
    cd "$(component_build_root "$id")"
    zip -rq "$zip" "$base" -x "*.DS_Store" -x "*/.DS_Store"
  )
  echo "$zip"
}

lock_release_components() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver id ver

  firmware_ver="$(normalize_version "$distro_ver")"
  bootloader_ver="$(read_bootloader_version)"
  motatool_ver="$(read_motatool_version)"

  write_release_manifest "$distro_ver" "$firmware_ver" "$bootloader_ver" "$motatool_ver"
  write_released_marker "$firmware_ver"
  write_component_released_marker bootloader "$bootloader_ver" "$distro_ver"
  write_component_released_marker motatool "$motatool_ver" "$distro_ver"
  if component_in_distro_bundle mcmt-gateway "$distro_ver"; then
    local mcmt_ver mcmt_sha
    mcmt_ver="$(read_mcmt_gateway_version)"
    mcmt_sha="$(git -C "$MCMT_ROOT" rev-parse HEAD)"
    write_component_released_marker mcmt-gateway "$mcmt_ver" "$distro_ver"
  fi
  if component_in_distro_bundle peaky "$distro_ver"; then
    local peaky_ver
    peaky_ver="$(read_peaky_version)"
    write_component_released_marker peaky "$peaky_ver" "$distro_ver"
  fi
  write_components_lock "$(git -C "$MESHCORE_ROOT" rev-parse HEAD)" "$(git -C "$BOOTLOADER_SRC" rev-parse HEAD)" "$(git -C "$MCMT_ROOT" rev-parse HEAD 2>/dev/null || true)"
}

collect_distro_release_assets() {
  local distro_ver=$1
  local release_dir f
  distro_ver="$(normalize_version "$distro_ver")"
  populate_distro_release "$distro_ver"
  release_dir="$(distro_release_root "$distro_ver")"
  while IFS= read -r f || [[ -n "$f" ]]; do
    [[ -n "$f" ]] || continue
    printf '%s\n' "$f"
  done < <(find "$release_dir" -maxdepth 1 -type f ! -name MANIFEST.txt | sort)
}

release_notes_for_distro() {
  local distro_ver=$1 preview=${2:-0}
  local firmware_ver bootloader_ver motatool_ver peaky_ver mcmt_ver published changelog_body

  distro_ver="$(normalize_version "$distro_ver")"

  if ((preview == 1)); then
    firmware_ver="$distro_ver"
    bootloader_ver="$(read_bootloader_version)"
    motatool_ver="$(read_motatool_version)"
    published="$(date '+%Y-%m-%d')"
  else
    firmware_ver="$(manifest_component_version firmware "$distro_ver")"
    bootloader_ver="$(manifest_component_version bootloader "$distro_ver")"
    motatool_ver="$(manifest_component_version motatool "$distro_ver")"
    published="$(read_release_manifest_key "$distro_ver" published 2>/dev/null || date '+%Y-%m-%d')"
  fi

  cat <<EOF
EnvyOS distro release **${distro_ver}** (${published}).

| Component | Version |
|-----------|---------|
| firmware | ${firmware_ver} |
| bootloader | ${bootloader_ver} |
| motatool | ${motatool_ver} |
EOF
  if component_in_distro_bundle mcmt-gateway "$distro_ver"; then
    if ((preview == 1)); then
      mcmt_ver="$(read_mcmt_gateway_version)"
    else
      mcmt_ver="$(manifest_component_version mcmt-gateway "$distro_ver")"
    fi
    printf '| mcmt-gateway | %s |\n' "$mcmt_ver"
  fi
  if component_in_distro_bundle peaky "$distro_ver"; then
    if ((preview == 1)); then
      peaky_ver="$(read_peaky_version)"
    else
      peaky_ver="$(manifest_component_version peaky "$distro_ver")"
    fi
    printf '| peaky | %s |\n' "$peaky_ver"
  fi

  if changelog_body="$(changelog_body_for_distro_release "$distro_ver" 2>/dev/null)"; then
    cat <<EOF

### Changes

${changelog_body}
EOF
  fi

  cat <<EOF

### Assets

- \`envyos-<ver>-full.tgz\` — **complete offline bundle** (all firmware variants, bootloader, motatool platforms, optional peaky/mcmt; uncompressed bench tree + manifests)
- \`fw-<slug>-<ver>-full-<id>.mota.gz\` / \`fw-<slug>-<ver>-delta-from-<base>-<id>.mota.gz\` — fleet OTA (pick one per node)
- \`fw-<slug>-<ver>.uf2.gz\` — bench UF2 flash
- \`bl-<board>-<ver>.uf2.gz\` / \`bl-<board>-recovery-<ver>.zip\` — EnvyBoot per board
- \`motatool-<ver>-<platform>.tar.gz\` — bench motatool (pick your OS/arch)
EOF
  if component_in_distro_bundle mcmt-gateway "$distro_ver"; then
    if ((preview == 1)); then
      mcmt_ver="$(read_mcmt_gateway_version)"
    else
      mcmt_ver="$(manifest_component_version mcmt-gateway "$distro_ver")"
    fi
    printf -- '- \`mcmt-gateway-%s.zip\` — Meshtastic ↔ MeshCore bridge\n' "$mcmt_ver"
  fi
  if component_in_distro_bundle peaky "$distro_ver"; then
    if ((preview == 1)); then
      peaky_ver="$(read_peaky_version)"
    else
      peaky_ver="$(manifest_component_version peaky "$distro_ver")"
    fi
    printf -- '- \`peaky-%s-<platform>.tar.gz\` — Peaky Finders \`peaky serve\` (pick Linux or macOS archive)\n' "${peaky_ver#v}"
  fi

  cat <<EOF

Restore released trees with \`./envyos restore\` (flat assets on v0.2.0+; legacy \`firmware-*.zip\` / \`bootloader-*.zip\` on v0.1.x).
EOF
}

create_release_zip() {
  create_component_zip firmware "$1"
}

release_zip_path() {
  component_zip_path firmware "$1"
}

publish_github_release() {
  local distro_ver=$1
  shift
  local assets=("$@")
  local repo notes

  command -v gh >/dev/null 2>&1 || {
    echo "warning: gh not installed — skipping GitHub release" >&2
    return 0
  }

  repo="$(github_repo)" || {
    echo "warning: could not resolve GitHub repo — skipping release" >&2
    return 0
  }

  ((${#assets[@]} > 0)) || {
    echo "error: no release assets to upload" >&2
    return 1
  }

  local asset
  for asset in "${assets[@]}"; do
    [[ -f "$asset" ]] || {
      echo "error: release asset not found: $asset" >&2
      return 1
    }
  done

  notes="$(release_notes_for_distro "$distro_ver")"

  if gh release view "$distro_ver" -R "$repo" >/dev/null 2>&1; then
    echo "github:   release $distro_ver exists — uploading assets"
    gh release upload "$distro_ver" "${assets[@]}" -R "$repo" --clobber
  else
    ensure_git_tag_on_remote "$distro_ver"
    echo "github:   creating release $distro_ver"
    gh release create "$distro_ver" "${assets[@]}" -R "$repo" \
      --title "EnvyOS ${distro_ver}" \
      --notes "$notes"
  fi
  echo "github:   https://github.com/${repo}/releases/tag/${distro_ver}"
}

github_repo() {
  command -v gh >/dev/null 2>&1 || return 1
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null
}

ensure_git_tag_on_remote() {
  local ver="$1"
  if git -C "$OTA_ROOT" ls-remote --tags origin "refs/tags/${ver}" 2>/dev/null | grep -q .; then
    return 0
  fi
  git -C "$OTA_ROOT" rev-parse "$ver" >/dev/null 2>&1 || {
    echo "error: tag $ver not found locally or on origin" >&2
    return 1
  }
  echo "git push: origin $ver"
  git -C "$OTA_ROOT" push origin "$ver"
}

# shellcheck source=scripts/targets-lib.sh
source "$OTA_ROOT/scripts/targets-lib.sh"
# shellcheck source=scripts/build-lib.sh
source "$OTA_ROOT/scripts/build-lib.sh"

list_distro_git_tags() {
  local tag
  git -C "$OTA_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null | while IFS= read -r tag || [[ -n "$tag" ]]; do
    [[ -n "$tag" ]] || continue
    normalize_version "$tag" 2>/dev/null || true
  done
}

latest_published_distro_tag() {
  local -a tmp=()
  local ver
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    tmp+=("$ver")
  done < <(list_released_distros)
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    tmp+=("$ver")
  done < <(list_distro_git_tags)
  ((${#tmp[@]} == 0)) && return 1
  sort_versions "${tmp[@]}" | tail -1
}

is_published_distro_tag() {
  local ver
  ver="$(normalize_version "$1")" || return 1
  is_released_version "$ver" && return 0
  git -C "$OTA_ROOT" rev-parse "$ver^{tag}" >/dev/null 2>&1
}

# shellcheck source=scripts/distro-semver.sh
source "$OTA_ROOT/scripts/distro-semver.sh"
