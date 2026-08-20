#!/usr/bin/env bash
# Version helpers for ota repo build scripts.
set -euo pipefail

OTA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVYOS_VERSIONS_FILE="$OTA_ROOT/ENVYOS_VERSIONS"
CHANGELOG_FILE="$OTA_ROOT/CHANGELOG.md"
GUCP_FILE="$OTA_ROOT/docs/good-upstream-contributor-policy.md"
RELEASED_DISTROS_FILE="$OTA_ROOT/RELEASED_DISTROS"
RELEASED_FIRMWARE_FILE="$OTA_ROOT/RELEASED_FIRMWARE"
RELEASED_BOOTLOADER_FILE="$OTA_ROOT/RELEASED_BOOTLOADER"
RELEASE_MANIFESTS_DOC="$OTA_ROOT/docs/release-manifests.md"
BUILD_ROOT="$OTA_ROOT/build"
FIRMWARE_ROOT="$BUILD_ROOT/firmware"
RELEASES_ROOT="$BUILD_ROOT/releases"
BOOTLOADER_ROOT="$BUILD_ROOT/bootloader"
MOTATOOL_ROOT="$BUILD_ROOT/motatool"

# Back-compat alias (deprecated).
MOTAS_ROOT="$FIRMWARE_ROOT"

# shellcheck source=scripts/targets-lib.sh
source "$OTA_ROOT/scripts/targets-lib.sh"

# v0.1.0 or 0.1.0 → v0.1.0
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
    normalize_version "$val"
    return 0
  done <"$ENVYOS_VERSIONS_FILE"
  echo "error: missing key '$key' in $ENVYOS_VERSIONS_FILE" >&2
  return 1
}

read_distro_version() { read_envyos_version_key distro; }
read_firmware_version() { read_envyos_version_key firmware; }
read_bootloader_version() { read_envyos_version_key bootloader; }
read_motatool_version() { read_envyos_version_key motatool; }

read_version_file() { read_firmware_version; }
read_bootloader_version_file() { read_bootloader_version; }

list_envyos_versions() {
  local key
  for key in distro firmware bootloader motatool; do
    printf '%s=%s\n' "$key" "$(read_envyos_version_key "$key")"
  done
}

write_envyos_version_key() {
  local key="$1"
  local ver="${2#v}"
  local line k tmp
  [[ -f "$ENVYOS_VERSIONS_FILE" ]] || {
    echo "error: missing $ENVYOS_VERSIONS_FILE" >&2
    return 1
  }
  tmp="$(mktemp "${TMPDIR:-/tmp}/envyos-versions.XXXXXX")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line//[[:space:]]/}" ]]; then
      printf '%s\n' "$line" >>"$tmp"
      continue
    fi
    k="${line%%=*}"
    k="${k%"${k##*[![:space:]]}"}"
    if [[ "$k" == "$key" ]]; then
      printf '%s=%s\n' "$key" "$ver" >>"$tmp"
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$ENVYOS_VERSIONS_FILE"
  mv "$tmp" "$ENVYOS_VERSIONS_FILE"
}

# Match firmware CLI display: "13 Aug 2026 05:00 UTC" (no leading zero on day).
format_firmware_build_date() {
  local d
  d="$(LC_TIME=C date -u '+%d %b %Y')"
  d="${d#0}"
  printf '%s %s' "$d" "$(LC_TIME=C date -u '+%H:%M UTC')"
}

# Short git SHA for the tree that produced firmware (default: envycore submodule).
git_short_sha() {
  local dir="${1:-$OTA_ROOT/envycore}"
  git -C "$dir" rev-parse --short HEAD 2>/dev/null || printf 'unknown'
}

# PlatformIO env name → MOTA_TARGET_ID (sha256:4 little-endian), same as envycore/build.sh.
mota_target_id_for_env() {
  python3 -c "import hashlib,sys;print('0x%08x'%int.from_bytes(hashlib.sha256(sys.argv[1].encode()).digest()[:4],'little'))" "$1" 2>/dev/null || echo "0x00000000"
}

# version.txt: line 1 = semver, line 2 = build stamp, line 3 = envycore git sha.
write_mota_version_txt() {
  local dir=$1 ver=$2 build_date=$3 git_sha=$4
  if [[ -n "$git_sha" ]]; then
    printf '%s\n%s\n%s\n' "$ver" "$build_date" "$git_sha" >"$dir/version.txt"
  else
    printf '%s\n%s\n' "$ver" "$build_date" >"$dir/version.txt"
  fi
}

verify_firmware_version_sync() {
  local expected="${1#v}"
  local submod="$OTA_ROOT/envycore/envyos/VERSION"
  [[ -f "$submod" ]] || return 0
  local actual
  actual="$(tr -d '[:space:]' <"$submod")"
  [[ "$actual" == "$expected" ]] || {
    echo "error: envycore/envyos/VERSION ($actual) != ENVYOS_VERSIONS firmware ($expected)" >&2
    return 1
  }
}

verify_motatool_version_sync() {
  local expected="${1#v}"
  local cargo="$OTA_ROOT/motatool/Cargo.toml"
  [[ -f "$cargo" ]] || return 0
  local actual
  actual="$(sed -n 's/^version = "\(.*\)"/\1/p' "$cargo" | head -1)"
  [[ "$actual" == "$expected" ]] || {
    echo "error: motatool/Cargo.toml version ($actual) != ENVYOS_VERSIONS motatool ($expected)" >&2
    return 1
  }
}

# Platform slug for staged motatool binaries: darwin-aarch64, linux-x86_64, …
normalize_motatool_platform_slug() {
  local slug="$1"
  slug="${slug// /}"
  slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')"
  case "$slug" in
    darwin-aarch64 | darwin-arm64 | macos-aarch64 | macos-arm64) printf 'darwin-aarch64' ;;
    darwin-x86_64 | darwin-amd64 | macos-x86_64) printf 'darwin-x86_64' ;;
    linux-aarch64 | linux-arm64) printf 'linux-aarch64' ;;
    linux-x86_64 | linux-amd64) printf 'linux-x86_64' ;;
    *)
      echo "error: unknown motatool platform '$1' (want darwin-aarch64, darwin-x86_64, linux-aarch64, linux-x86_64)" >&2
      return 1
      ;;
  esac
}

host_motatool_platform_slug() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *)
      echo "error: unsupported host OS for motatool build: $os" >&2
      return 1
      ;;
  esac
  case "$arch" in
    arm64 | aarch64) arch=aarch64 ;;
    x86_64 | amd64) arch=x86_64 ;;
    *)
      echo "error: unsupported host CPU for motatool build: $arch" >&2
      return 1
      ;;
  esac
  normalize_motatool_platform_slug "${os}-${arch}"
}

motatool_platform_to_rust_triple() {
  local platform
  platform="$(normalize_motatool_platform_slug "$1")" || return 1
  case "$platform" in
    darwin-aarch64) printf 'aarch64-apple-darwin' ;;
    darwin-x86_64) printf 'x86_64-apple-darwin' ;;
    linux-aarch64) printf 'aarch64-unknown-linux-gnu' ;;
    linux-x86_64) printf 'x86_64-unknown-linux-gnu' ;;
  esac
}

# darwin | linux
motatool_platform_os() {
  normalize_motatool_platform_slug "$1" | cut -d- -f1
}

motatool_binary_name() {
  local platform
  platform="$(normalize_motatool_platform_slug "${1:-$(host_motatool_platform_slug)}")" || return 1
  printf 'motatool-%s' "$platform"
}

motatool_staged_binary_path() {
  local ver=$1 platform=$2
  ver="$(normalize_version "$ver")" || return 1
  platform="$(normalize_motatool_platform_slug "${2:-$(host_motatool_platform_slug)}")" || return 1
  printf '%s/%s/%s' "$MOTATOOL_ROOT" "$ver" "$(motatool_binary_name "$platform")"
}

motatool_cargo_release_path() {
  local platform=$1 triple host
  platform="$(normalize_motatool_platform_slug "$1")" || return 1
  host="$(host_motatool_platform_slug)" || return 1
  if [[ "$platform" == "$host" ]]; then
    printf '%s/motatool/target/release/motatool' "$OTA_ROOT"
    return 0
  fi
  triple="$(motatool_platform_to_rust_triple "$platform")" || return 1
  printf '%s/motatool/target/%s/release/motatool' "$OTA_ROOT" "$triple"
}

record_motatool_platform_staged() {
  local ver=$1 platform=$2 dir file tmp
  ver="$(normalize_version "$ver")" || return 1
  platform="$(normalize_motatool_platform_slug "$2")" || return 1
  dir="$MOTATOOL_ROOT/$ver"
  file="$dir/platforms.txt"
  mkdir -p "$dir"
  if [[ -f "$file" ]] && grep -qx "$platform" "$file"; then
    return 0
  fi
  printf '%s\n' "$platform" >>"$file"
}

stage_motatool_binary() {
  local bin=$1 platform ver out name
  platform="${2:-$(host_motatool_platform_slug)}"
  platform="$(normalize_motatool_platform_slug "$platform")" || return 1
  ver="$(read_motatool_version)"
  assert_component_tree_not_released motatool "$ver"
  out="$MOTATOOL_ROOT/$ver"
  mkdir -p "$out"
  name="$(motatool_binary_name "$platform")"
  cp -f "$bin" "$out/$name"
  chmod +x "$out/$name"
  rm -f "$out/motatool"
  printf '%s\n' "$ver" >"$out/version.txt"
  record_motatool_platform_staged "$ver" "$platform"
}

resolve_motatool_bin() {
  local ver platform path legacy
  ver="${1:-$(read_motatool_version)}"
  platform="$(host_motatool_platform_slug)" || return 1
  path="$(motatool_staged_binary_path "$ver" "$platform")"
  if [[ -x "$path" ]]; then
    printf '%s' "$path"
    return 0
  fi
  legacy="$MOTATOOL_ROOT/$(normalize_version "$ver")/motatool"
  if [[ -x "$legacy" ]]; then
    printf '%s' "$legacy"
    return 0
  fi
  echo "error: motatool not found for host $platform at $path (run ./envyos build motatool)" >&2
  return 1
}

list_staged_motatool_platforms() {
  local ver=$1 dir f base
  ver="$(normalize_version "$ver")" || return 1
  dir="$MOTATOOL_ROOT/$ver"
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
  if [[ -x "$dir/motatool" ]]; then
    host_motatool_platform_slug
  fi
}

# Platforms shipped in every motatool-<ver>.zip / required at publish.
list_motatool_release_platforms() {
  printf '%s\n' darwin-aarch64 darwin-x86_64 linux-aarch64 linux-x86_64
}

verify_motatool_release_platforms() {
  local ver=$1 platform path missing=0
  ver="$(normalize_version "$ver")" || return 1
  while IFS= read -r platform || [[ -n "$platform" ]]; do
    [[ -n "$platform" ]] || continue
    path="$(motatool_staged_binary_path "$ver" "$platform")"
    if [[ ! -x "$path" ]]; then
      echo "error: missing $path (required for publish)" >&2
      missing=1
    fi
  done < <(list_motatool_release_platforms)
  [[ "$missing" -eq 0 ]]
}

# v0.1.1 → 0 1 1 (stdout: major minor patch)
parse_version() {
  local v="${1#v}"
  local major minor patch
  IFS=. read -r major minor patch <<<"$v"
  printf '%s %s %s' "$major" "$minor" "$patch"
}

version_in_list_file() {
  local file="$1" want="$2"
  local ver line
  ver="$(normalize_version "$want")" || return 1
  [[ -f "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    if [[ "$(normalize_version "$line")" == "$ver" ]]; then
      return 0
    fi
  done <"$file"
  return 1
}

is_released_distro() {
  version_in_list_file "$RELEASED_DISTROS_FILE" "$1"
}

is_released_firmware() {
  local ver="$1"
  if version_in_list_file "$RELEASED_FIRMWARE_FILE" "$ver"; then
    return 0
  fi
  [[ -f "$FIRMWARE_ROOT/$(normalize_version "$ver")/.released" ]]
}

# Back-compat alias.
is_released_version() { is_released_distro "$1"; }

assert_firmware_not_released() {
  local ver="$1"
  if is_released_firmware "$ver"; then
    echo "error: $ver is a released firmware version — $FIRMWARE_ROOT/$(normalize_version "$ver")/ is immutable" >&2
    echo "       (listed in RELEASED_FIRMWARE or marked .released)" >&2
    exit 1
  fi
}

assert_version_not_released() { assert_firmware_not_released "$1"; }

# Zero-padded key for portable version sort (macOS sort lacks -V).
version_sort_key() {
  local major minor patch
  read -r major minor patch <<<"$(parse_version "$1")"
  printf '%03d.%03d.%03d' "$major" "$minor" "$patch"
}

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

list_known_firmware_versions() {
  local line ver d
  local tmp=()
  if [[ -f "$RELEASED_FIRMWARE_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -n "$line" ]] || continue
      ver="$(normalize_version "$line" 2>/dev/null)" || continue
      tmp+=("$ver")
    done <"$RELEASED_FIRMWARE_FILE"
  fi
  if [[ -d "$FIRMWARE_ROOT" ]]; then
    for d in "$FIRMWARE_ROOT"/v[0-9]*.[0-9]*.[0-9]*; do
      [[ -d "$d" ]] || continue
      ver="$(normalize_version "$(basename "$d")" 2>/dev/null)" || continue
      tmp+=("$ver")
    done
  fi
  if [[ ${#tmp[@]} -eq 0 ]]; then
    return 0
  fi
  sort_versions "${tmp[@]}"
}

list_known_mota_versions() { list_known_firmware_versions; }

list_delta_base_versions() {
  local target ver
  target="$(normalize_version "$1")" || return 1
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    if version_lt "$ver" "$target"; then
      printf '%s\n' "$ver"
    fi
  done < <(list_known_firmware_versions)
}

list_released_distros() {
  local line ver
  [[ -f "$RELEASED_DISTROS_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    ver="$(normalize_version "$line" 2>/dev/null)" || continue
    printf '%s\n' "$ver"
  done <"$RELEASED_DISTROS_FILE"
}

latest_released_distro() {
  local tmp=()
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    tmp+=("$ver")
  done < <(list_released_distros)
  ((${#tmp[@]} == 0)) && return 0
  sort_versions "${tmp[@]}" | tail -1
}

previous_patch_version() {
  local ver="$1"
  local major minor patch
  read -r major minor patch <<<"$(parse_version "$ver")"
  if [[ "$patch" -eq 0 ]]; then
    return 0
  fi
  printf 'v%s.%s.%s' "$major" "$minor" "$((patch - 1))"
}

next_patch_version() {
  local ver="$1"
  local major minor patch
  read -r major minor patch <<<"$(parse_version "$ver")"
  printf 'v%s.%s.%s' "$major" "$minor" "$((patch + 1))"
}

bump_version() {
  local ver="$1" level="$2"
  local major minor patch
  read -r major minor patch <<<"$(parse_version "$ver")"
  case "$level" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      echo "error: bump level must be major, minor, or patch (got '$level')" >&2
      return 1
      ;;
  esac
  printf 'v%s.%s.%s' "$major" "$minor" "$patch"
}

sync_component_sidecars() {
  local id="$1" ver="$2"
  case "$id" in
    firmware) write_firmware_version_file "$ver" ;;
    motatool) write_motatool_cargo_version "$ver" ;;
  esac
}

bump_component() {
  local id="$1" level="$2"
  local old new
  case "$id" in
    distro | firmware | bootloader | motatool) ;;
    *)
      echo "error: unknown component '$id' (want distro, firmware, bootloader, motatool)" >&2
      return 1
      ;;
  esac
  old="$(read_envyos_version_key "$id")" || return 1
  if [[ "$id" != distro ]]; then
    assert_component_tree_not_released "$id" "$old"
  fi
  new="$(bump_version "$old" "$level")" || return 1
  write_envyos_version_key "$id" "$new"
  sync_component_sidecars "$id" "$new"
  printf '%s\n' "$old" "$new"
}

write_envyos_versions() {
  local ver="${1#v}"
  cat >"$ENVYOS_VERSIONS_FILE" <<EOF
# EnvyOS dev HEAD — independent component semver (MAJOR.MINOR.PATCH).
# distro: next bundle to publish (git tag v<distro>). Bump via envyos bump.
# firmware/bootloader/motatool: bump independently via envyos bump.
distro=$ver
firmware=$ver
bootloader=$ver
motatool=$ver
EOF
  sync_component_sidecars firmware "$ver"
  sync_component_sidecars motatool "$ver"
}

write_firmware_version_file() {
  local ver="${1#v}"
  local f="$OTA_ROOT/envycore/envyos/VERSION"
  [[ -f "$f" ]] || return 0
  printf '%s\n' "$ver" >"$f"
}

write_motatool_cargo_version() {
  local ver="${1#v}"
  local cargo="$OTA_ROOT/motatool/Cargo.toml"
  [[ -f "$cargo" ]] || return 0
  sed -i '' "s/^version = \".*\"/version = \"$ver\"/" "$cargo"
}

append_released_distro() {
  local ver="$1"
  if is_released_distro "$ver"; then
    echo "error: $ver is already listed in RELEASED_DISTROS" >&2
    return 1
  fi
  printf '%s\n' "$ver" >>"$RELEASED_DISTROS_FILE"
}

append_released_firmware() {
  local ver="$1"
  if version_in_list_file "$RELEASED_FIRMWARE_FILE" "$ver"; then
    return 0
  fi
  printf '%s\n' "$ver" >>"$RELEASED_FIRMWARE_FILE"
}

append_released_version() { append_released_distro "$1"; }

submodule_git_sha() {
  local subpath="$1"
  git -C "$OTA_ROOT" submodule status "$subpath" 2>/dev/null | awk '{print $1}' | sed 's/^[+-U]//'
}

list_released_firmware_versions() {
  local line ver
  [[ -f "$RELEASED_FIRMWARE_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    ver="$(normalize_version "$line" 2>/dev/null)" || continue
    printf '%s\n' "$ver"
  done <"$RELEASED_FIRMWARE_FILE"
}

list_released_bootloader_versions() {
  local line ver
  [[ -f "$RELEASED_BOOTLOADER_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    ver="$(normalize_version "$line" 2>/dev/null)" || continue
    printf '%s\n' "$ver"
  done <"$RELEASED_BOOTLOADER_FILE"
}

is_released_bootloader() {
  version_in_list_file "$RELEASED_BOOTLOADER_FILE" "$1"
}

append_released_bootloader() {
  local ver="$1"
  ver="$(normalize_version "$ver")" || return 1
  if version_in_list_file "$RELEASED_BOOTLOADER_FILE" "$ver"; then
    return 0
  fi
  printf '%s\n' "$ver" >>"$RELEASED_BOOTLOADER_FILE"
}

# Flash (USB / delta base): fw-<slug>-vX.Y.Z.<ext>
# Motas: fw-<slug>-<ver>-full-<mid8>.mota
#        fw-<slug>-<ver>-delta-from-<base>-<base8>.mota
firmware_artifact_name() {
  local slug="$1" ver="$2" ext="$3"
  ver="$(normalize_version "$ver")" || return 1
  printf 'fw-%s-%s.%s' "$slug" "$ver" "$ext"
}

firmware_target8_for_slug() {
  local slug="$1"
  local env id
  if ! type target_env_for_slug >/dev/null 2>&1; then
    # shellcheck source=scripts/targets-lib.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/targets-lib.sh"
  fi
  env="$(target_env_for_slug "$slug")" || return 1
  id="$(mota_target_id_for_env "$env")"
  printf '%08X' "$((id))"
}

firmware_mota_glob() {
  local slug="$1" ver="$2" kind="$3"
  ver="$(normalize_version "$ver")" || return 1
  case "$kind" in
    full) printf 'fw-%s-%s-full-*.mota' "$slug" "$ver" ;;
    delta | ipdelta) printf 'fw-%s-%s-delta-from-*.mota' "$slug" "$ver" ;;
    *)
      echo "error: unknown mota kind: $kind" >&2
      return 1
      ;;
  esac
}

list_firmware_motas_in_dir() {
  local dir="$1" slug="$2" ver="$3" kind="$4"
  local g f
  g="$(firmware_mota_glob "$slug" "$ver" "$kind")" || return 1
  shopt -s nullglob
  for f in "$dir"/$g; do
    printf '%s\n' "$f"
  done
}

count_firmware_motas_in_dir() {
  local n=0
  while IFS= read -r _ || [[ -n "$_" ]]; do
    [[ -n "$_" ]] || continue
    n=$((n + 1))
  done < <(list_firmware_motas_in_dir "$@")
  printf '%s' "$n"
}

# v0.1.2 GitHub names (restore fallback only).
github_full_mota_name() {
  local slug="$1" ver="$2"
  ver="$(normalize_version "$ver")" || return 1
  printf 'fw-%s-full-%s.mota' "$slug" "$ver"
}

github_delta_mota_name() {
  local slug="$1" base_ver="$2"
  base_ver="$(normalize_version "$base_ver")" || return 1
  printf 'fw-%s-delta-from-%s.mota' "$slug" "$base_ver"
}

resolve_firmware_image_in_dir() {
  local dir="$1" slug="$2" ver="$3"
  local p
  for p in \
    "$dir/$(firmware_artifact_name "$slug" "$ver" hex)" \
    "$dir/$(firmware_artifact_name "$slug" "$ver" bin)" \
    "$dir/firmware.hex" \
    "$dir/firmware.bin"; do
    if [[ -f "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

resolve_firmware_uf2_in_dir() {
  local dir="$1" slug="$2" ver="$3"
  local p
  for p in \
    "$dir/$(firmware_artifact_name "$slug" "$ver" uf2)" \
    "$dir/firmware.uf2"; do
    if [[ -f "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

firmware_version_tree_present() {
  local ver="$1"
  ver="$(normalize_version "$ver")" || return 1
  [[ -d "$FIRMWARE_ROOT/$ver" ]]
}

resolve_base_image() {
  local slug="$1"
  local base_ver="$2"
  if is_debug_target_slug "$slug"; then
    slug="${slug%-debug}"
  fi
  local dir="$FIRMWARE_ROOT/$base_ver/$slug"
  if resolve_firmware_image_in_dir "$dir" "$slug" "$base_ver"; then
    return 0
  fi
  if [[ "$slug" == "wismesh-tag-repeater" ]]; then
    resolve_firmware_image_in_dir "$FIRMWARE_ROOT/$base_ver/repeater" "$slug" "$base_ver" && return 0
    resolve_firmware_image_in_dir "$FIRMWARE_ROOT/$base_ver" "$slug" "$base_ver" && return 0
  fi
  return 1
}

resolve_base_hex() {
  resolve_base_image "$@"
}

ensure_firmware_bases_for_build() {
  local target_ver="$1"
  shift
  local slugs=("$@")
  local base_ver
  local -a need_restore=()
  local seen="|"

  [[ ${#slugs[@]} -gt 0 ]] || return 0

  while IFS= read -r base_ver || [[ -n "$base_ver" ]]; do
    [[ -n "$base_ver" ]] || continue
    is_released_firmware "$base_ver" || continue
    firmware_version_tree_present "$base_ver" && continue
    case "$seen" in
      *"|$base_ver|"*) continue ;;
    esac
    seen="${seen}${base_ver}|"
    need_restore+=("$base_ver")
  done < <(list_delta_base_versions "$target_ver")

  ((${#need_restore[@]} == 0)) && return 0

  echo "==> missing delta base images for: ${need_restore[*]}"
  echo "    restoring released firmware from GitHub Releases"
  local ver
  for ver in "${need_restore[@]}"; do
    "$OTA_ROOT/scripts/restore-firmware.sh" "$ver"
  done
}

verify_release_delta_matrix() {
  local firmware_ver="$1"
  local targets_file="$2"
  local line slug base_ver
  local missing=0 need=0 have=0

  firmware_ver="$(normalize_version "$firmware_ver")" || return 1
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
    need=0

    while IFS= read -r base_ver || [[ -n "$base_ver" ]]; do
      [[ -n "$base_ver" ]] || continue
      resolve_base_hex "$slug" "$base_ver" >/dev/null || continue
      need=$((need + 1))
    done < <(list_delta_base_versions "$firmware_ver")
    have="$(count_firmware_motas_in_dir "$FIRMWARE_ROOT/$firmware_ver/$slug" "$slug" "$firmware_ver" ipdelta)"
    if ((have < need)); then
      echo "error: $firmware_ver/$slug has $have ipdelta .mota, need $need (one per prior base with an image)" >&2
      missing=1
    fi
  done <"$targets_file"

  [[ "$missing" -eq 0 ]]
}

write_firmware_released_marker() {
  local firmware_ver="$1" distro_ver="$2"
  local dir today
  firmware_ver="$(normalize_version "$firmware_ver")"
  dir="$FIRMWARE_ROOT/$firmware_ver"
  today="$(date '+%Y-%m-%d')"
  cat >"$dir/.released" <<EOF
EnvyOS firmware $firmware_ver — published in distro $distro_ver on $today.
Do not delete or rebuild this directory.
Includes fw-<slug>-<ver>-delta-from-<base>-<base8>.mota for every prior released firmware with a base image.
EOF
}

list_release_component_ids() {
  printf '%s\n' firmware bootloader motatool
}

component_build_root() {
  case "$1" in
    firmware) printf '%s' "$FIRMWARE_ROOT" ;;
    bootloader) printf '%s' "$BOOTLOADER_ROOT" ;;
    motatool) printf '%s' "$MOTATOOL_ROOT" ;;
    *)
      echo "error: unknown release component: $1" >&2
      return 1
      ;;
  esac
}

component_version_at_publish() {
  local id=$1 _distro_ver=$2
  case "$id" in
    firmware) read_firmware_version ;;
    bootloader) read_bootloader_version ;;
    motatool) read_motatool_version ;;
    *)
      echo "error: unknown release component: $id" >&2
      return 1
      ;;
  esac
}

component_build_dir() {
  local id=$1 ver=$2
  printf '%s/%s' "$(component_build_root "$id")" "$ver"
}

release_dir() {
  printf '%s/%s' "$RELEASES_ROOT" "$(normalize_version "$1")"
}

release_assets_manifest_path() {
  printf '%s/%s/ASSETS' "$RELEASES_ROOT" "$(normalize_version "$1")"
}

clear_release_flat_assets() {
  local release_dir=$1
  shopt -s nullglob
  rm -f "$release_dir"/fw-* "$release_dir"/bl-* "$release_dir"/motatool-*
  shopt -u nullglob
}

cleanup_legacy_release_layout() {
  local release_dir=$1
  rm -rf "$release_dir/assets" "$release_dir/firmware" "$release_dir/bootloader" "$release_dir/motatool"
}

file_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

file_size_bytes() {
  local size
  size="$(stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0)"
  printf '%s' "$size"
}

# otafix board slug for release filenames (rak4631 → rak4631, wismesh_tag → wismesh-tag).
normalize_release_board_slug() {
  tr '_' '-' <<<"$1"
}

stage_flat_release_asset() {
  local src=$1 dest_name=$2 release_dir=$3 manifest_file=$4
  local dest rel_src
  [[ -f "$src" ]] || {
    echo "error: missing release source: $src" >&2
    return 1
  }
  dest="$release_dir/$dest_name"
  cp -f "$src" "$dest"
  if [[ -x "$src" ]]; then
    chmod +x "$dest"
  fi
  rel_src="${src#"$OTA_ROOT"/}"
  printf 'asset=%s sha256=%s size=%s source=%s\n' \
    "$dest_name" "$(file_sha256 "$dest")" "$(file_size_bytes "$dest")" "$rel_src" >>"$manifest_file"
  printf '%s\n' "$dest"
}

stage_firmware_release_assets() {
  local firmware_ver=$1 firmware_root=$2 release_dir=$3 manifest_file=$4
  local targets_file slug f name uf2
  # shellcheck source=scripts/targets-lib.sh
  source "$OTA_ROOT/scripts/targets-lib.sh"
  targets_file="$OTA_ROOT/scripts/targets.txt"
  firmware_ver="$(normalize_version "$firmware_ver")"
  [[ -d "$firmware_root" ]] || {
    echo "error: missing firmware tree $firmware_root" >&2
    return 1
  }

  while IFS= read -r slug || [[ -n "$slug" ]]; do
    [[ -n "$slug" ]] || continue
    [[ -d "$firmware_root/$slug" ]] || {
      echo "error: missing firmware target dir $firmware_root/$slug" >&2
      return 1
    }
    if uf2="$(resolve_firmware_uf2_in_dir "$firmware_root/$slug" "$slug" "$firmware_ver")"; then
      name="$(firmware_artifact_name "$slug" "$firmware_ver" uf2)"
      stage_flat_release_asset "$uf2" "$name" "$release_dir" "$manifest_file"
    fi
    shopt -s nullglob
    for f in "$firmware_root/$slug"/*.mota; do
      [[ -f "$f" ]] || continue
      name="$(basename "$f")"
      stage_flat_release_asset "$f" "$name" "$release_dir" "$manifest_file"
    done
    shopt -u nullglob
  done < <(list_release_target_slugs_from_file "$targets_file")
}

stage_bootloader_release_assets() {
  local bl_ver=$1 bl_root=$2 release_dir=$3 manifest_file=$4
  local uf2 zip base board name
  bl_ver="$(normalize_version "$bl_ver")"
  [[ -d "$bl_root" ]] || {
    echo "error: missing bootloader tree $bl_root" >&2
    return 1
  }

  shopt -s nullglob
  for uf2 in "$bl_root"/*_bootloader-*.uf2; do
    base="$(basename "$uf2" .uf2)"
    board="${base%_bootloader-*}"
    name="bl-$(normalize_release_board_slug "$board")-${bl_ver}.uf2"
    stage_flat_release_asset "$uf2" "$name" "$release_dir" "$manifest_file"
  done
  for zip in "$bl_root"/*_bootloader-*.recovery.zip; do
    base="$(basename "$zip" .recovery.zip)"
    board="${base%_bootloader-*}"
    name="bl-$(normalize_release_board_slug "$board")-recovery-${bl_ver}.zip"
    stage_flat_release_asset "$zip" "$name" "$release_dir" "$manifest_file"
  done
  shopt -u nullglob
}

stage_motatool_release_assets() {
  local mt_ver=$1 mt_root=$2 release_dir=$3 manifest_file=$4
  local platform path name
  mt_ver="$(normalize_version "$mt_ver")"
  [[ -d "$mt_root" ]] || {
    echo "error: missing motatool tree $mt_root" >&2
    return 1
  }
  while IFS= read -r platform || [[ -n "$platform" ]]; do
    [[ -n "$platform" ]] || continue
    path="$mt_root/$(motatool_binary_name "$platform")"
    [[ -x "$path" ]] || {
      echo "error: missing $path" >&2
      return 1
    }
    name="motatool-${platform}-${mt_ver}"
    stage_flat_release_asset "$path" "$name" "$release_dir" "$manifest_file"
  done < <(list_motatool_release_platforms)
}

write_release_assets_manifest_header() {
  local distro_ver=$1 manifest_file=$2
  cat >"$manifest_file" <<EOF
# EnvyOS flat release assets (GitHub upload names + integrity)
# Staged under build/releases/<distro>/ (flat; ASSETS is local-only)
distro=$(normalize_version "$distro_ver")
EOF
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

release_manifest_path() {
  printf '%s/%s/RELEASE_MANIFEST' "$RELEASES_ROOT" "$(normalize_version "$1")"
}

write_release_manifest() {
  local distro_ver=$1 firmware_ver=$2 bootloader_ver=$3 motatool_ver=$4
  local dir today envycore_sha bootloader_sha motatool_sha
  distro_ver="$(normalize_version "$distro_ver")"
  firmware_ver="$(normalize_version "$firmware_ver")"
  bootloader_ver="$(normalize_version "$bootloader_ver")"
  motatool_ver="$(normalize_version "$motatool_ver")"
  dir="$RELEASES_ROOT/$distro_ver"
  today="$(date '+%Y-%m-%d')"
  envycore_sha="$(submodule_git_sha envycore)"
  bootloader_sha="$(submodule_git_sha bootloader)"
  motatool_sha="$(submodule_git_sha motatool)"
  mkdir -p "$dir"
  cat >"$dir/RELEASE_MANIFEST" <<EOF
# EnvyOS distro release manifest (immutable snapshot at publish)
distro=$distro_ver
firmware=$firmware_ver
bootloader=$bootloader_ver
motatool=$motatool_ver
published=$today
envycore_sha=$envycore_sha
bootloader_sha=$bootloader_sha
motatool_sha=$motatool_sha
EOF
}

read_release_manifest_key() {
  local distro_ver=$1 key=$2
  local file line k val
  file="$(release_manifest_path "$distro_ver")"
  if [[ ! -f "$file" ]]; then
    file="$FIRMWARE_ROOT/$(normalize_version "$distro_ver")/RELEASE_MANIFEST"
  fi
  if [[ ! -f "$file" ]]; then
    file="$MOTAS_ROOT/$(normalize_version "$distro_ver")/RELEASE_MANIFEST"
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
      case "$key" in
        published | envycore_sha | bootloader_sha | motatool_sha)
          printf '%s' "$val"
          ;;
        *)
          normalize_version "$val"
          ;;
      esac
      return 0
    done <"$file"
  fi
  read_archived_release_manifest_key "$distro_ver" "$key"
}

# docs/release-manifests.md — committed pins for published distros
read_archived_release_manifest_key() {
  local distro_ver=$1 key=$2
  local heading val
  heading="$(normalize_version "$distro_ver")" || return 1
  [[ -f "$RELEASE_MANIFESTS_DOC" ]] || return 1
  val="$(awk -v heading="$heading" -v key="$key" '
    $0 == "## " heading { in_section = 1; next }
    in_section && /^## / { exit }
    in_section {
      line = $0
      sub(/^[ \t]+|[ \t]+$/, "", line)
      if (index(line, key "=") != 1) next
      print substr(line, length(key) + 2)
      exit
    }
  ' "$RELEASE_MANIFESTS_DOC")"
  [[ -n "$val" ]] || return 1
  case "$key" in
    published) printf '%s' "$val" ;;
    *) normalize_version "$val" ;;
  esac
}

manifest_component_version() {
  local id=$1 distro_ver=$2
  local from_manifest ver legacy
  if from_manifest="$(read_release_manifest_key "$distro_ver" "$id" 2>/dev/null)"; then
    printf '%s' "$from_manifest"
    return 0
  fi
  ver="$(normalize_version "$distro_ver")"
  if [[ "$id" == firmware ]] && [[ -d "$(component_build_dir firmware "$ver")" ]]; then
    printf '%s' "$ver"
    return 0
  fi
  if [[ "$id" == firmware ]]; then
    while IFS= read -r legacy || [[ -n "$legacy" ]]; do
      [[ -n "$legacy" ]] || continue
      if version_lt "$legacy" "$distro_ver" && [[ -d "$(component_build_dir firmware "$legacy")" ]]; then
        printf '%s' "$legacy"
        return 0
      fi
    done < <(list_known_firmware_versions)
  fi
  component_version_at_publish "$id" "$distro_ver"
}

ensure_release_manifest_for_backfill() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver published
  distro_ver="$(normalize_version "$distro_ver")"
  [[ -f "$(release_manifest_path "$distro_ver")" ]] && return 0
  firmware_ver="$(manifest_component_version firmware "$distro_ver")"
  bootloader_ver="$(manifest_component_version bootloader "$distro_ver")"
  motatool_ver="$(manifest_component_version motatool "$distro_ver")"
  published="$(date '+%Y-%m-%d')"
  if [[ -f "$FIRMWARE_ROOT/$distro_ver/.released" ]]; then
    published="$(sed -n 's/.*released \([0-9-]*\).*/\1/p' "$FIRMWARE_ROOT/$distro_ver/.released" | head -1)"
    [[ -n "$published" ]] || published="$(date '+%Y-%m-%d')"
  elif [[ -f "$MOTAS_ROOT/$distro_ver/.released" ]]; then
    published="$(sed -n 's/.*released \([0-9-]*\).*/\1/p' "$MOTAS_ROOT/$distro_ver/.released" | head -1)"
    [[ -n "$published" ]] || published="$(date '+%Y-%m-%d')"
  fi
  write_release_manifest "$distro_ver" "$firmware_ver" "$bootloader_ver" "$motatool_ver"
}

verify_release_components() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver
  local id ver dir

  distro_ver="$(normalize_version "$distro_ver")" || return 1
  if [[ "$distro_ver" != "$(read_distro_version)" ]]; then
    echo "error: publish version $distro_ver != ENVYOS_VERSIONS distro ($(read_distro_version))" >&2
    return 1
  fi

  firmware_ver="$(read_firmware_version)" || return 1
  bootloader_ver="$(read_bootloader_version)" || return 1
  motatool_ver="$(read_motatool_version)" || return 1

  verify_firmware_version_sync "${firmware_ver#v}" || return 1
  verify_motatool_version_sync "$motatool_ver" || return 1

  while IFS= read -r id || [[ -n "$id" ]]; do
    ver="$(component_version_at_publish "$id" "$distro_ver")" || return 1
    dir="$(component_build_dir "$id" "$ver")"
    [[ -d "$dir" ]] || {
      echo "error: missing $id artifacts at $dir — run ./envyos build first" >&2
      return 1
    }
    if [[ -f "$dir/version.txt" ]]; then
      local actual
      actual="$(head -1 "$dir/version.txt" | tr -d '[:space:]')"
      [[ "$(normalize_version "$actual")" == "$ver" ]] || {
        echo "error: $dir/version.txt ($actual) != expected $ver" >&2
        return 1
      }
    fi
  done < <(list_release_component_ids)

  if ! verify_motatool_release_platforms "$motatool_ver"; then
    echo "hint: run ./envyos build motatool (builds all release platforms)" >&2
    return 1
  fi

  verify_release_delta_matrix "$firmware_ver" "$OTA_ROOT/scripts/targets.txt"
}

lock_release_components() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver

  firmware_ver="$(read_firmware_version)"
  bootloader_ver="$(read_bootloader_version)"
  motatool_ver="$(read_motatool_version)"

  write_release_manifest "$distro_ver" "$firmware_ver" "$bootloader_ver" "$motatool_ver"
  if ! is_released_firmware "$firmware_ver"; then
    write_firmware_released_marker "$firmware_ver" "$distro_ver"
    append_released_firmware "$firmware_ver"
  fi
  if ! is_component_tree_released bootloader "$bootloader_ver"; then
    write_component_released_marker bootloader "$bootloader_ver" "$distro_ver"
    append_released_bootloader "$bootloader_ver"
  fi
  if ! is_component_tree_released motatool "$motatool_ver"; then
    write_component_released_marker motatool "$motatool_ver" "$distro_ver"
  fi
}

plan_firmware_release_assets() {
  local firmware_ver=$1 firmware_root=$2
  local targets_file slug f base delta_base name rel_src uf2
  # shellcheck source=scripts/targets-lib.sh
  source "$OTA_ROOT/scripts/targets-lib.sh"
  targets_file="$OTA_ROOT/scripts/targets.txt"
  firmware_ver="$(normalize_version "$firmware_ver")"
  [[ -d "$firmware_root" ]] || {
    echo "error: missing firmware tree $firmware_root" >&2
    return 1
  }

  while IFS= read -r slug || [[ -n "$slug" ]]; do
    [[ -n "$slug" ]] || continue
    [[ -d "$firmware_root/$slug" ]] || {
      echo "error: missing firmware target dir $firmware_root/$slug" >&2
      return 1
    }
    if uf2="$(resolve_firmware_uf2_in_dir "$firmware_root/$slug" "$slug" "$firmware_ver")"; then
      name="$(firmware_artifact_name "$slug" "$firmware_ver" uf2)"
      rel_src="${uf2#"$OTA_ROOT"/}"
      printf '  asset: %s  source: %s\n' "$name" "$rel_src"
    fi
    shopt -s nullglob
    for f in "$firmware_root/$slug"/*.mota; do
      [[ -f "$f" ]] || continue
      name="$(basename "$f")"
      rel_src="${f#"$OTA_ROOT"/}"
      printf '  asset: %s  source: %s\n' "$name" "$rel_src"
    done
    shopt -u nullglob
  done < <(list_release_target_slugs_from_file "$targets_file")
}

plan_bootloader_release_assets() {
  local bl_ver=$1 bl_root=$2
  local uf2 zip base board name rel_src
  bl_ver="$(normalize_version "$bl_ver")"
  [[ -d "$bl_root" ]] || {
    echo "error: missing bootloader tree $bl_root" >&2
    return 1
  }

  shopt -s nullglob
  for uf2 in "$bl_root"/*_bootloader-*.uf2; do
    base="$(basename "$uf2" .uf2)"
    board="${base%_bootloader-*}"
    name="bl-$(normalize_release_board_slug "$board")-${bl_ver}.uf2"
    rel_src="${uf2#"$OTA_ROOT"/}"
    printf '  asset: %s  source: %s\n' "$name" "$rel_src"
  done
  for zip in "$bl_root"/*_bootloader-*.recovery.zip; do
    base="$(basename "$zip" .recovery.zip)"
    board="${base%_bootloader-*}"
    name="bl-$(normalize_release_board_slug "$board")-recovery-${bl_ver}.zip"
    rel_src="${zip#"$OTA_ROOT"/}"
    printf '  asset: %s  source: %s\n' "$name" "$rel_src"
  done
  shopt -u nullglob
}

plan_motatool_release_assets() {
  local mt_ver=$1 mt_root=$2
  local platform path name rel_src
  mt_ver="$(normalize_version "$mt_ver")"
  [[ -d "$mt_root" ]] || {
    echo "error: missing motatool tree $mt_root" >&2
    return 1
  }
  while IFS= read -r platform || [[ -n "$platform" ]]; do
    [[ -n "$platform" ]] || continue
    path="$mt_root/$(motatool_binary_name "$platform")"
    [[ -x "$path" ]] || {
      echo "error: missing $path" >&2
      return 1
    }
    name="motatool-${platform}-${mt_ver}"
    rel_src="${path#"$OTA_ROOT"/}"
    printf '  asset: %s  source: %s\n' "$name" "$rel_src"
  done < <(list_motatool_release_platforms)
}

plan_distro_release() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver fw_root bl_root mt_root
  local -i asset_count=0

  distro_ver="$(normalize_version "$distro_ver")" || return 1
  firmware_ver="$(read_firmware_version)" || return 1
  bootloader_ver="$(read_bootloader_version)" || return 1
  motatool_ver="$(read_motatool_version)" || return 1
  fw_root="$(component_build_dir firmware "$firmware_ver")"
  bl_root="$(component_build_dir bootloader "$bootloader_ver")"
  mt_root="$(component_build_dir motatool "$motatool_ver")"

  echo "  bundle:   firmware=$firmware_ver bootloader=$bootloader_ver motatool=$motatool_ver"
  echo "  output:   build/releases/${distro_ver}/"
  echo "  steps:"
  echo "    stage    copy flat files + ASSETS (./envyos publish stage)"
  echo "    finalize lock RELEASED_* + RELEASE_MANIFEST + git tag (./envyos publish finalize)"
  echo "    upload   GitHub Release (./envyos publish upload ${distro_ver})"
  echo "  assets:"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    printf '%s\n' "$line"
    asset_count+=1
  done < <(
    plan_firmware_release_assets "$firmware_ver" "$fw_root"
    plan_bootloader_release_assets "$bootloader_ver" "$bl_root"
    plan_motatool_release_assets "$motatool_ver" "$mt_root"
  )
  ((asset_count > 0)) || {
    echo "error: no release assets planned for $distro_ver" >&2
    return 1
  }
  echo "  total:    $asset_count asset(s)"
}

read_distro_release_asset_paths() {
  local distro_ver=$1
  local release_dir manifest_file line name path
  release_dir="$(release_dir "$distro_ver")"
  manifest_file="$(release_assets_manifest_path "$distro_ver")"
  [[ -f "$manifest_file" ]] || {
    echo "error: missing staged release at $manifest_file — run ./envyos publish stage first" >&2
    return 1
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" == asset=* ]] || continue
    name="${line#asset=}"
    name="${name%% *}"
    path="$release_dir/$name"
    [[ -f "$path" ]] || {
      echo "error: staged asset missing: $path" >&2
      return 1
    }
    printf '%s\n' "$path"
  done <"$manifest_file"
}

collect_distro_release_assets() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver release_dir manifest_file
  local fw_root bl_root mt_root
  local -a staged=()

  distro_ver="$(normalize_version "$distro_ver")" || return 1
  firmware_ver="$(manifest_component_version firmware "$distro_ver")" || return 1
  bootloader_ver="$(manifest_component_version bootloader "$distro_ver")" || return 1
  motatool_ver="$(manifest_component_version motatool "$distro_ver")" || return 1

  fw_root="$(component_build_dir firmware "$firmware_ver")"
  bl_root="$(component_build_dir bootloader "$bootloader_ver")"
  mt_root="$(component_build_dir motatool "$motatool_ver")"

  release_dir="$(release_dir "$distro_ver")"
  manifest_file="$(release_assets_manifest_path "$distro_ver")"
  mkdir -p "$release_dir"
  cleanup_legacy_release_layout "$release_dir"
  clear_release_flat_assets "$release_dir"
  write_release_assets_manifest_header "$distro_ver" "$manifest_file"

  echo "==> stage release ${distro_ver} → ${release_dir#"$OTA_ROOT"/}"

  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    staged+=("$asset")
  done < <(stage_firmware_release_assets "$firmware_ver" "$fw_root" "$release_dir" "$manifest_file")

  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    staged+=("$asset")
  done < <(stage_bootloader_release_assets "$bootloader_ver" "$bl_root" "$release_dir" "$manifest_file")

  while IFS= read -r asset || [[ -n "$asset" ]]; do
    [[ -n "$asset" ]] || continue
    staged+=("$asset")
  done < <(stage_motatool_release_assets "$motatool_ver" "$mt_root" "$release_dir" "$manifest_file")

  ((${#staged[@]} > 0)) || {
    echo "error: no release assets staged for $distro_ver" >&2
    return 1
  }

  printf '%s\n' "${staged[@]}"
}

list_distro_release_asset_names() {
  local distro_ver=$1 manifest_file line name
  manifest_file="$(release_assets_manifest_path "$distro_ver")"
  [[ -f "$manifest_file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" == asset=* ]] || continue
    name="${line#asset=}"
    name="${name%% *}"
    printf '%s\n' "$name"
  done <"$manifest_file"
}

# Body of ## [heading] in CHANGELOG.md (heading itself omitted). heading is vX.Y.Z or Unreleased.
changelog_section() {
  local heading=$1
  local body
  [[ -f "$CHANGELOG_FILE" ]] || {
    echo "error: missing $CHANGELOG_FILE" >&2
    return 1
  }
  body="$(awk -v heading="$heading" '
    index($0, "## [" heading "]") == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
    END { if (!found) exit 2 }
  ' "$CHANGELOG_FILE")" || {
    if [[ $? -eq 2 ]]; then
      echo "error: CHANGELOG.md missing ## [${heading}] section" >&2
    fi
    return 1
  }
  body="$(printf '%s\n' "$body" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
  [[ -n "$body" ]] || {
    echo "error: CHANGELOG.md ## [${heading}] section is empty" >&2
    return 1
  }
  printf '%s\n' "$body"
}

# Finalize/upload require ## [vX.Y.Z]. Dry-run may fall back to Unreleased.
changelog_notes_for_distro() {
  local distro_ver=$1
  local allow_unreleased=${2:-0}
  local body
  if body="$(changelog_section "$distro_ver" 2>/dev/null)"; then
    printf '%s\n' "$body"
    return 0
  fi
  if [[ "$allow_unreleased" -eq 1 ]]; then
    echo "warning: CHANGELOG.md has no ## [${distro_ver}] yet; using Unreleased" >&2
    changelog_section Unreleased
    return
  fi
  echo "error: promote CHANGELOG.md Unreleased to ## [${distro_ver}] - YYYY-MM-DD before publish" >&2
  return 1
}

require_changelog_section() {
  changelog_notes_for_distro "$1" 0 >/dev/null
}

# --- GUCP (docs/good-upstream-contributor-policy.md) ---

_upstream_prs_allowed_status() {
  case "$1" in
    submitted | merged | envyos-only | declined) return 0 ;;
    *) return 1 ;;
  esac
}

_upstream_prs_valid_status() {
  case "$1" in
    candidate | extracting | submitted | merged | envyos-only | declined) return 0 ;;
    *) return 1 ;;
  esac
}

# Parse ## Release vX.Y.Z table rows. Prints: status<TAB>feature<TAB>branch
_upstream_prs_rows_for_distro() {
  local distro_ver=$1
  local heading="Release ${distro_ver}"
  [[ -f "$GUCP_FILE" ]] || {
    echo "error: missing $GUCP_FILE" >&2
    return 1
  }
  awk -v heading="$heading" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    function strip_ticks(s) {
      gsub(/^`+|`+$/, "", s)
      return s
    }
    $0 == "## " heading { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && /^\|/ {
      if ($0 ~ /^\|[[:space:]]*-/) next
      n = split($0, cells, "|")
      feature = trim(cells[2])
      branch = strip_ticks(trim(cells[4]))
      status = tolower(trim(cells[7]))
      if (feature == "" || feature == "Feature") next
      printf "%s\t%s\t%s\n", status, feature, branch
    }
  ' "$GUCP_FILE"
}

check_upstream_prs_for_distro() {
  local distro_ver=$1
  local -a blockers=()
  local row status feature branch rows
  [[ -f "$GUCP_FILE" ]] || {
    echo "error: missing $GUCP_FILE" >&2
    return 1
  }
  if ! grep -qE "^## Release ${distro_ver//./\\.}[[:space:]]*$" "$GUCP_FILE"; then
    echo "error: docs/good-upstream-contributor-policy.md has no '## Release ${distro_ver}' section" >&2
    echo "Assign Unreleased rows to this release (or add an empty table stating envyos-only)." >&2
    echo "See .cursor/skills/envyos-good-upstream-contributor/SKILL.md" >&2
    return 1
  fi
  rows="$(_upstream_prs_rows_for_distro "$distro_ver")" || return 1
  if [[ -z "$rows" ]]; then
    echo "error: docs/good-upstream-contributor-policy.md '## Release ${distro_ver}' has no table rows" >&2
    echo "Every release needs at least one row (use envyos-only when nothing is upstreamable)." >&2
    return 1
  fi
  while IFS=$'\t' read -r status feature branch; do
    [[ -n "$status" ]] || continue
    if _upstream_prs_allowed_status "$status"; then
      continue
    fi
    if ! _upstream_prs_valid_status "$status"; then
      blockers+=("unknown status '$status': $feature (${branch:-no branch})")
      continue
    fi
    blockers+=("$status: $feature (${branch:-no branch})")
  done <<<"$rows"

  if [[ ${#blockers[@]} -eq 0 ]]; then
    echo "GUCP: $distro_ver OK (all upstreamable rows submitted, merged, envyos-only, or declined)"
    return 0
  fi

  echo "error: docs/good-upstream-contributor-policy.md ## Release $distro_ver has upstreamable work not submitted:" >&2
  for row in "${blockers[@]}"; do
    echo "  - $row" >&2
  done
  echo "Open cross-fork PRs and set status to submitted (or merged / envyos-only / declined)." >&2
  echo "See docs/good-upstream-contributor-policy.md and .cursor/skills/envyos-good-upstream-contributor/SKILL.md" >&2
  return 1
}

require_upstream_prs_for_distro() {
  check_upstream_prs_for_distro "$1"
}

# --- Per-package changelog gate (docs/change-management.md) ---

component_changelog_file() {
  case "$1" in
    firmware) printf '%s' "$OTA_ROOT/envycore/envyos/CHANGELOG.md" ;;
    bootloader) printf '%s' "$OTA_ROOT/bootloader/CHANGELOG.md" ;;
    motatool) printf '%s' "$OTA_ROOT/motatool/CHANGELOG.md" ;;
    *)
      echo "error: unknown component '$1'" >&2
      return 1
      ;;
  esac
}

# ## [X.Y.Z] or ## [vX.Y.Z] heading present?
component_changelog_has_version() {
  local file=$1 ver=$2
  local bare
  bare="$(normalize_version "$ver")" || return 1
  bare="${bare#v}"
  [[ -f "$file" ]] || return 1
  grep -qE "^## \[v?${bare//./\\.}\]" "$file"
}

# Component version for a distro: RELEASE_MANIFEST / docs/release-manifests.md, else dev HEAD for in-progress only.
resolve_component_version_for_distro() {
  local id=$1 distro_ver=$2
  local v dev_distro
  if v="$(read_release_manifest_key "$distro_ver" "$id" 2>/dev/null)" && [[ -n "$v" ]]; then
    normalize_version "$v"
    return
  fi
  dev_distro="$(read_distro_version 2>/dev/null || true)"
  if [[ "$(normalize_version "$distro_ver")" == "$(normalize_version "$dev_distro")" ]]; then
    normalize_version "$(read_envyos_version_key "$id")"
    return
  fi
  if [[ "$id" == firmware ]] && [[ -d "$(component_build_dir firmware "$(normalize_version "$distro_ver")")" ]]; then
    normalize_version "$distro_ver"
    return
  fi
  echo "error: no component version for ${id} in distro ${distro_ver} (hydrate manifest or add docs/release-manifests.md)" >&2
  return 1
}

# Latest released distro strictly below the given version.
previous_released_distro() {
  local distro_ver=$1 ver prev=""
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    version_lt "$ver" "$distro_ver" || continue
    if [[ -z "$prev" ]] || version_lt "$prev" "$ver"; then
      prev="$ver"
    fi
  done < <(list_released_distros)
  [[ -n "$prev" ]] || return 1
  printf '%s' "$prev"
}

# Prints: component<TAB>prev-version-or-—<TAB>new-version<TAB>changed|unchanged
changelog_package_delta() {
  local distro_ver=$1
  local prev_distro="" id prev_ver new_ver state
  prev_distro="$(previous_released_distro "$distro_ver" 2>/dev/null || true)"
  for id in firmware bootloader motatool; do
    new_ver="$(resolve_component_version_for_distro "$id" "$distro_ver")" || return 1
    prev_ver=""
    if [[ -n "$prev_distro" ]]; then
      prev_ver="$(manifest_component_version "$id" "$prev_distro" 2>/dev/null || true)"
      prev_ver="$(normalize_version "$prev_ver" 2>/dev/null || true)"
    fi
    if [[ -n "$prev_ver" && "$prev_ver" == "$new_ver" ]]; then
      state=unchanged
    else
      state=changed
    fi
    printf '%s\t%s\t%s\t%s\n' "$id" "${prev_ver:-—}" "$new_ver" "$state"
  done
}

check_changelog_packages_for_distro() {
  local distro_ver=$1
  local body id prev_ver new_ver state file
  local -a errors=()

  body="$(changelog_notes_for_distro "$distro_ver" 1)" || return 1

  if ! printf '%s\n' "$body" | grep -q '^### Packages'; then
    errors+=("root CHANGELOG.md ${distro_ver} section is missing '### Packages' version-delta table")
  fi

  while IFS=$'\t' read -r id prev_ver new_ver state; do
    [[ -n "$id" ]] || continue
    if ! printf '%s\n' "$body" | grep -qE "^\| *${id} *\|"; then
      errors+=("'### Packages' table has no row for ${id}")
    fi
    if [[ "$state" == changed ]]; then
      file="$(component_changelog_file "$id")"
      if ! component_changelog_has_version "$file" "$new_ver"; then
        errors+=("${id} bumped ${prev_ver} → ${new_ver} but ${file#"$OTA_ROOT"/} has no ## [${new_ver#v}] section")
      fi
    fi
  done < <(changelog_package_delta "$distro_ver") || return 1

  if [[ ${#errors[@]} -eq 0 ]]; then
    echo "changelog: $distro_ver OK (Packages table + package changelog sections present)"
    return 0
  fi

  echo "error: change-management gate failed for $distro_ver:" >&2
  local err
  for err in "${errors[@]}"; do
    echo "  - $err" >&2
  done
  echo "See docs/change-management.md" >&2
  return 1
}

require_changelog_packages_for_distro() {
  check_changelog_packages_for_distro "$1"
}

list_upstream_prs_blockers() {
  local section heading distro_ver row status feature branch
  [[ -f "$GUCP_FILE" ]] || {
    echo "error: missing $GUCP_FILE" >&2
    return 1
  }
  while IFS= read -r section; do
    [[ "$section" == "## Release v"* ]] || continue
    heading="${section### }"
    distro_ver="${heading#Release }"
    echo "$distro_ver"
    while IFS=$'\t' read -r status feature branch; do
      [[ -n "$status" ]] || continue
      if _upstream_prs_allowed_status "$status"; then
        continue
      fi
      echo "  BLOCKED  $status  $feature  (${branch:-—})"
    done < <(_upstream_prs_rows_for_distro "$distro_ver" 2>/dev/null || true)
  done <"$GUCP_FILE"
}

# Print candidate/extracting rows and recent envycore commits for triage.
audit_gucp() {
  local distro_ver="${1:-}"
  local commit_limit="${2:-20}"

  echo "GUCP audit — register upstreamable work as candidate; PRs open at release prep"
  echo "Policy: docs/good-upstream-contributor-policy.md"
  echo ""

  if [[ -n "$distro_ver" ]]; then
    distro_ver="$(normalize_version "$distro_ver")" || return 1
    echo "## Release $distro_ver"
    local found=0
    while IFS=$'\t' read -r status feature branch; do
      [[ -n "$status" ]] || continue
      case "$status" in
        candidate | extracting)
          echo "  $status  $feature  (${branch:-—})"
          found=1
          ;;
      esac
    done < <(_upstream_prs_rows_for_distro "$distro_ver" 2>/dev/null || true)
    [[ "$found" -eq 1 ]] || echo "  (no candidate/extracting rows)"
    echo ""
  else
    distro_ver="$(read_distro_version 2>/dev/null || true)"
    if [[ -n "$distro_ver" ]]; then
      audit_gucp "$distro_ver" "$commit_limit"
      return $?
    fi
  fi

  echo "## Unreleased"
  if [[ -f "$GUCP_FILE" ]]; then
    awk '
      $0 == "## Unreleased" { in_section = 1; next }
      in_section && /^## / { exit }
      in_section && /^\|/ {
        if ($0 ~ /^\|[[:space:]]*-/) next
        n = split($0, c, "|")
        f = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", f)
        s = tolower(c[7]); gsub(/^[ \t]+|[ \t]+$/, "", s)
        if (f == "" || f == "Feature") next
        if (s == "candidate" || s == "extracting") {
          printf "  %s  %s\n", s, f
          found = 1
        }
      }
      END { if (!found) print "  (no candidate/extracting rows)" }
    ' "$GUCP_FILE"
  fi
  echo ""

  local envycore="$OTA_ROOT/envycore"
  if [[ -d "$envycore/.git" ]]; then
    echo "Recent envycore commits on envyos/main (last $commit_limit — triage each logical unit):"
    git -C "$envycore" log --oneline -n "$commit_limit" envyos/main 2>/dev/null | sed 's/^/  /' || echo "  (could not read envycore log)"
  else
    echo "envycore/ submodule not checked out — skip commit log"
  fi
  echo ""
  echo "Next: add/update GUCP rows (candidate OK), then at release prep extract branches and ./envyos gucp check vX.Y.Z"
}

release_notes_for_distro() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver published asset_name notes
  firmware_ver="$(manifest_component_version firmware "$distro_ver")"
  bootloader_ver="$(manifest_component_version bootloader "$distro_ver")"
  motatool_ver="$(manifest_component_version motatool "$distro_ver")"
  published="$(read_release_manifest_key "$distro_ver" published 2>/dev/null || date '+%Y-%m-%d')"
  notes="$(changelog_notes_for_distro "$distro_ver" 0)" || return 1

  cat <<EOF
EnvyOS distro release **${distro_ver}** (${published}).

${notes}

| Component | Version |
|-----------|---------|
| firmware | ${firmware_ver} |
| bootloader | ${bootloader_ver} |
| motatool | ${motatool_ver} |

### Assets

Flat per-artifact files in \`build/releases/${distro_ver}/\` (see local \`ASSETS\` manifest for sha256).

- \`fw-<slug>-${firmware_ver}.uf2\` — initial flash per target in \`scripts/targets.txt\`
- \`fw-<slug>-${firmware_ver}-full-<mid8>.mota\` — OTA full image
- \`fw-<slug>-${firmware_ver}-delta-from-vX.Y.Z-<base8>.mota\` — in-place deltas (release version + base full-mota merkle)
- \`bl-<board>-${bootloader_ver}.uf2\` — EnvyBoot bootloader update
- \`bl-<board>-recovery-${bootloader_ver}.zip\` — bootloader recovery package (when built)
- \`motatool-<platform>-${motatool_ver}\` — bench CLI (\`serve\`, pack, verify)
EOF

  while IFS= read -r asset_name || [[ -n "$asset_name" ]]; do
    [[ -n "$asset_name" ]] || continue
    printf -- '- `%s`\n' "$asset_name"
  done < <(list_distro_release_asset_names "$distro_ver" 2>/dev/null || true)
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

motatool_tree_has_binaries() {
  local ver=$1 dir f
  ver="$(normalize_version "$ver")" || return 1
  dir="$(component_build_dir motatool "$ver")"
  [[ -d "$dir" ]] || return 1
  shopt -s nullglob
  local bins=("$dir"/motatool-*)
  shopt -u nullglob
  ((${#bins[@]} > 0)) && return 0
  [[ -x "$dir/motatool" ]]
}

component_artifact_status() {
  local id="$1" ver="$2"
  local dir
  ver="$(normalize_version "$ver")" || return 1
  dir="$(component_build_dir "$id" "$ver")"
  if [[ "$id" == motatool ]]; then
    if ! motatool_tree_has_binaries "$ver"; then
      printf 'missing'
      return 0
    fi
    if is_component_tree_released "$id" "$ver"; then
      printf 'released'
      return 0
    fi
    if verify_motatool_release_platforms "$ver" >/dev/null 2>&1; then
      printf 'ok'
    else
      printf 'incomplete'
    fi
    return 0
  fi
  if [[ ! -d "$dir" ]]; then
    printf 'missing'
    return 0
  fi
  if is_component_tree_released "$id" "$ver" || { [[ "$id" == firmware ]] && is_released_firmware "$ver"; }; then
    printf 'released'
    return 0
  fi
  printf 'ok'
}

write_released_marker() { write_firmware_released_marker "$1" "$1"; }
