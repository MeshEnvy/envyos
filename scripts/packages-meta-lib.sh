#!/usr/bin/env bash
# packages-meta/ helpers — upstream-evN versioning (sourced by version.sh).
set -euo pipefail

PACKAGES_META_ROOT="${PACKAGES_META_ROOT:-$OTA_ROOT/packages-meta}"

package_meta_dir() {
  printf '%s/%s' "$PACKAGES_META_ROOT" "$1"
}

# Immutable shipped versions for a bundled package (packages-meta/<pkg>/RELEASES).
package_releases_file() {
  printf '%s/RELEASES' "$(package_meta_dir "$1")"
}

# Map legacy registry / component ids to packages-meta package names.
package_meta_id() {
  case "$1" in
    firmware | meshcore) printf '%s' meshcore ;;
    bootloader) printf '%s' bootloader ;;
    motatool) printf '%s' motatool ;;
    mcmt-gateway) printf '%s' mcmt-gateway ;;
    peaky) printf '%s' peaky ;;
    *) printf '%s' "$1" ;;
  esac
}

append_package_release() {
  local pkg=$1 ver=$2
  local file line
  pkg="$(package_meta_id "$pkg")"
  file="$(package_releases_file "$pkg")"
  [[ -f "$file" ]] || {
    echo "error: missing $file" >&2
    return 1
  }
  ver="$(normalize_component_version "$ver" 2>/dev/null || normalize_version "$ver" 2>/dev/null || printf '%s' "$ver")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    if [[ "$(normalize_version "$line" 2>/dev/null || normalize_component_version "$line" 2>/dev/null || printf '%s' "$line")" == "$ver" ]]; then
      return 0
    fi
  done <"$file"
  printf '%s\n' "$ver" >>"$file"
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
component_firmware_stamp() {
  local v="${1#v}"
  if [[ "$v" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-ev([0-9]+)$ ]]; then
    printf '%s.%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  printf '%s' "$v"
}

package_firmware_stamp() {
  component_firmware_stamp "$(read_package_version "${1:-meshcore}")"
}

sync_manifest_from_meta() {
  local pkg=$1 key=$2 ver
  ver="$(read_package_version "$pkg")"
  write_manifest_key "$key" "$ver"
}

write_manifest_key() {
  local key=$1 val=$2
  case "$key" in
    firmware) key=meshcore ;;
  esac
  python3 "${MANIFEST_PY:-$OTA_ROOT/scripts/manifest.py}" "${MANIFEST_JSON:-$OTA_ROOT/MANIFEST.json}" \
    --packages-meta "${PACKAGES_META_ROOT:-$OTA_ROOT/packages-meta}" \
    set-version "$key" "${val#v}"
}

bump_package_ev() {
  local pkg=$1 env_key=${2:-$pkg}
  local ev new_ver
  ev="$(read_package_meta_key "$pkg" ev)"
  ev=$((ev + 1))
  write_package_meta_key "$pkg" ev "$ev"
  new_ver="$(read_package_version "$pkg")"
  write_manifest_key "$env_key" "$new_ver"
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
  case "$pkg" in
    meshcore)
      repo="MeshEnvy/meshcore-firmware"
      sha="$(manifest_py get meshcore sha 2>/dev/null || true)"
      sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}"
      ;;
    bootloader)
      repo="MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX"
      sha="$(manifest_py get bootloader sha 2>/dev/null || true)"
      sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}"
      ;;
    motatool)
      repo="MeshEnvy/motatool"
      sha="$(manifest_py get motatool sha 2>/dev/null || true)"
      sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}"
      ;;
    mcmt-gateway)
      repo="Imperator4422/mcmt-gateway"
      sha="$(manifest_py get mcmt-gateway sha 2>/dev/null || true)"
      sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}"
      ;;
    meshcore-open)
      repo="MeshEnvy/meshcore-open"
      sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}"
      ;;
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

# Bench directory suffix: firmware-v0.1.2 (semver) or firmware-1.16.0-ev1 (overlay).
package_bench_component_label() {
  local ver=$1
  if normalize_package_version "$ver" >/dev/null 2>&1; then
    ver="$(normalize_package_version "$ver")"
    if [[ "$ver" =~ -ev[0-9]+$ ]]; then
      printf '%s' "$ver"
    else
      normalize_version "$ver"
    fi
    return 0
  fi
  normalize_version "$ver"
}

package_to_bench_id() {
  case "$1" in
    meshcore | firmware) printf '%s' firmware ;;
    *) printf '%s' "$1" ;;
  esac
}
