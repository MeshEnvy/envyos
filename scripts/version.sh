#!/usr/bin/env bash
# Version helpers for ota repo build scripts.
set -euo pipefail

OTA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVYOS_VERSIONS_FILE="$OTA_ROOT/ENVYOS_VERSIONS"
RELEASED_VERSIONS_FILE="$OTA_ROOT/RELEASED_VERSIONS"
BUILD_ROOT="$OTA_ROOT/build"
MOTAS_ROOT="$BUILD_ROOT/motas"
BOOTLOADER_ROOT="$BUILD_ROOT/bootloader"
MOTATOOL_ROOT="$BUILD_ROOT/motatool"

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

# Back-compat aliases used by build scripts.
read_version_file() { read_distro_version; }
read_bootloader_version_file() { read_bootloader_version; }

list_envyos_versions() {
  local key
  for key in distro firmware bootloader motatool; do
    printf '%s=%s\n' "$key" "$(read_envyos_version_key "$key")"
  done
}

# Match firmware CLI display: "6 Jun 2026" (no leading zero on day).
format_firmware_build_date() {
  local d
  d="$(LC_TIME=C date '+%d %b %Y')"
  printf '%s' "${d#0}"
}

# version.txt: line 1 = distro tag, line 2 = build date.
write_mota_version_txt() {
  local dir=$1 ver=$2 build_date=$3
  printf '%s\n%s\n' "$ver" "$build_date" >"$dir/version.txt"
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

stage_motatool_binary() {
  local bin=$1
  local ver out
  ver="$(read_motatool_version)"
  out="$MOTATOOL_ROOT/$ver"
  mkdir -p "$out"
  cp -f "$bin" "$out/motatool"
  printf '%s\n' "$ver" >"$out/version.txt"
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
  if is_released_version "$ver"; then
    echo "error: $ver is a released EnvyOS version — $MOTAS_ROOT/$ver/ is immutable" >&2
    echo "       (listed in RELEASED_VERSIONS; this is the only shipped copy)" >&2
    exit 1
  fi
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
  cat >"$ENVYOS_VERSIONS_FILE" <<EOF
# EnvyOS component versions (MAJOR.MINOR.PATCH). Bump together on /freshen.
# Git release tag: v<distro>
distro=$ver
firmware=$ver
bootloader=$ver
motatool=$ver
EOF
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

append_released_version() {
  local ver="$1"
  if is_released_version "$ver"; then
    echo "error: $ver is already listed in RELEASED_VERSIONS" >&2
    return 1
  fi
  printf '%s\n' "$ver" >>"$RELEASED_VERSIONS_FILE"
}

write_released_marker() {
  local ver="$1"
  local dir="$MOTAS_ROOT/$ver"
  local today
  today="$(date '+%Y-%m-%d')"
  cat >"$dir/.released" <<EOF
EnvyOS $ver — released $today. Do not delete or rebuild this directory.
Listed in RELEASED_VERSIONS; build-mota.sh refuses to overwrite released versions.
EOF
}

create_release_zip() {
  local ver="$1"
  local src="$MOTAS_ROOT/$ver"
  local zip="$OTA_ROOT/${ver}.zip"
  [[ -d "$src" ]] || {
    echo "error: missing $src" >&2
    return 1
  }
  rm -f "$zip"
  (
    cd "$MOTAS_ROOT"
    zip -rq "$zip" "$ver" -x "*.DS_Store" -x "*/.DS_Store"
  )
  echo "$zip"
}
