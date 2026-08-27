#!/usr/bin/env bash
# packages-meta/ helpers — upstream-evN versioning (sourced by version.sh).
set -euo pipefail

PACKAGES_META_ROOT="${PACKAGES_META_ROOT:-$OTA_ROOT/packages-meta}"

package_meta_dir() {
  printf '%s/%s' "$PACKAGES_META_ROOT" "$1"
}

read_package_meta_key() {
  local pkg=$1 key=$2
  local file line k val
  file="$(package_meta_dir "$pkg")/VERSION"
  [[ -f "$file" ]] || {
    echo "error: missing $file" >&2
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
    printf '%s' "$val"
    return 0
  done <"$file"
  echo "error: missing key '$key' in $file" >&2
  return 1
}

write_package_meta_key() {
  local pkg=$1 key=$2 val=$3
  local file tmp
  file="$(package_meta_dir "$pkg")/VERSION"
  [[ -f "$file" ]] || {
    echo "error: missing $file" >&2
    return 1
  }
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" '
    BEGIN { done=0 }
    /^[[:space:]]*#/ || !/=/ { print; next }
    {
      key=$0; sub(/=.*/, "", key); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == k) { print k "=" v; done=1; next }
      print
    }
    END { if (!done) print k "=" v }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

# Canonical display: 1.16.0-ev1 (no leading v).
normalize_package_version() {
  local v="${1#v}"
  if [[ "$v" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-ev([0-9]+)$ ]]; then
    printf '%s-ev%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "$v"
    return 0
  fi
  echo "error: invalid package version '$1' (want X.Y.Z-evN or X.Y.Z)" >&2
  return 1
}

# Read packages-meta and format display version.
read_package_version() {
  local pkg=$1 upstream ev ver
  if ver="$(read_package_meta_key "$pkg" version 2>/dev/null)"; then
    normalize_package_version "$ver"
    return 0
  fi
  upstream="$(read_package_meta_key "$pkg" upstream)"
  ev="$(read_package_meta_key "$pkg" ev)"
  normalize_package_version "${upstream}-ev${ev}"
}

# FIRMWARE_VERSION stamp: 1.16.0.1 (fourth byte = ev).
package_firmware_stamp() {
  local pkg=${1:-meshcore} upstream ev
  upstream="$(read_package_meta_key "$pkg" upstream)"
  ev="$(read_package_meta_key "$pkg" ev)"
  printf '%s.%s' "$upstream" "$ev"
}

sync_envyos_version_from_meta() {
  local pkg=$1 key=$2 ver
  ver="$(read_package_version "$pkg")"
  write_envyos_version_key "$key" "$ver"
}

write_envyos_version_key() {
  local key=$1 val=$2
  local line k tmp
  [[ -f "$ENVYOS_VERSIONS_FILE" ]] || return 1
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ ! "$line" =~ = ]]; then
      printf '%s\n' "$line"
      continue
    fi
    k="${line%%=*}"
    k="${k#"${k%%[![:space:]]*}"}"
    k="${k%"${k##*[![:space:]]}"}"
    if [[ "$k" == "$key" ]]; then
      printf '%s=%s\n' "$key" "$val"
    else
      printf '%s\n' "$line"
    fi
  done <"$ENVYOS_VERSIONS_FILE" >"$tmp"
  mv "$tmp" "$ENVYOS_VERSIONS_FILE"
}

bump_package_ev() {
  local pkg=$1 env_key=${2:-$pkg}
  local ev new_ver
  ev="$(read_package_meta_key "$pkg" ev)"
  ev=$((ev + 1))
  write_package_meta_key "$pkg" ev "$ev"
  new_ver="$(read_package_version "$pkg")"
  write_envyos_version_key "$env_key" "$new_ver"
  printf '%s\n' "$new_ver"
}

list_patched_packages() {
  printf '%s\n' meshcore bootloader motatool
}

package_checkout_dir() {
  local pkg=$1
  printf '%s/packages/%s' "$OTA_ROOT" "$pkg"
}

fetch_package_checkout() {
  local pkg=$1 sha repo
  local dest
  dest="$(package_checkout_dir "$pkg")"
  sha="$(read_components_lock_key firmware_sha 2>/dev/null || read_components_lock_key meshcore_sha 2>/dev/null || true)"
  case "$pkg" in
    meshcore)
      repo="MeshEnvy/meshcore-firmware"
      sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}"
      ;;
    bootloader) repo="MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX"; sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}" ;;
    motatool) repo="MeshEnvy/motatool"; sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}" ;;
    mcmt-gateway) repo="Imperator4422/mcmt-gateway"; sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}" ;;
    *)
      echo "error: unknown package '$pkg'" >&2
      return 1
      ;;
  esac
  if [[ -d "$dest/.git" ]]; then
    echo "fetch: $pkg already present at $dest ($(git -C "$dest" rev-parse --short HEAD))"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  echo "fetch: cloning $repo into $dest"
  git clone "https://github.com/$repo.git" "$dest"
}

bases_root() {
  printf '%s/bases' "$BUILD_ROOT"
}

legacy_mota_base_dir() {
  local ver=$1
  local bases legacy
  bases="$(bases_root)/$ver"
  [[ -d "$bases" ]] && { printf '%s' "$bases"; return 0; }
  legacy="$MESHCORE_ROOT/build/motas/$ver"
  [[ -d "$legacy" ]] && { printf '%s' "$legacy"; return 0; }
  return 1
}

normalize_component_version() {
  if normalize_package_version "$1" >/dev/null 2>&1; then
    normalize_package_version "$1"
    return 0
  fi
  normalize_version "$1"
}

package_to_bench_id() {
  case "$1" in
    meshcore | firmware) printf '%s' firmware ;;
    *) printf '%s' "$1" ;;
  esac
}
