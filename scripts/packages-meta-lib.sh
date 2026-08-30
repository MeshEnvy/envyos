#!/usr/bin/env bash
# packages-meta/ helpers — upstream-evN versioning (sourced by version.sh).
set -euo pipefail

PACKAGES_META_ROOT="${PACKAGES_META_ROOT:-$OTA_ROOT/packages-meta}"

package_meta_dir() {
  printf '%s/%s' "$PACKAGES_META_ROOT" "$(package_meta_id "$1")"
}

# Immutable shipped versions for a bundled package (packages-meta/<pkg>/RELEASES).
package_releases_file() {
  printf '%s/RELEASES' "$(package_meta_dir "$1")"
}

# Adafruit nRF52 / OTAFIX bootloader. CLI aliases: bootloader, bl.
# Shipped MANIFEST tags keep the key "bootloader"; releases.next uses this id.
NRF52_BOOTLOADER_ID=adafruit-nrf52-bootloader

# Map legacy registry / CLI ids to packages-meta package names.
package_meta_id() {
  case "$1" in
    firmware | meshcore) printf '%s' meshcore ;;
    bootloader | bl | adafruit-nrf52-bootloader) printf '%s' "$NRF52_BOOTLOADER_ID" ;;
    motatool) printf '%s' motatool ;;
    mcmt-gateway) printf '%s' mcmt-gateway ;;
    peaky) printf '%s' peaky ;;
    envybot) printf '%s' envybot ;;
    *) printf '%s' "$1" ;;
  esac
}

is_nrf52_bootloader_id() {
  case "$1" in
    bootloader | bl | adafruit-nrf52-bootloader) return 0 ;;
    *) return 1 ;;
  esac
}

# True if want and have name the same package (firmware/meshcore, bootloader aliases).
release_key_matches() {
  local want=$1 have=$2
  [[ "$want" == "$have" ]] && return 0
  case "$want" in
    firmware | meshcore)
      [[ "$have" == firmware || "$have" == meshcore ]]
      ;;
    bootloader | bl | adafruit-nrf52-bootloader)
      [[ "$have" == bootloader || "$have" == adafruit-nrf52-bootloader || "$have" == bl ]]
      ;;
    *) return 1 ;;
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
  ver="$(normalize_package_version "$ver" 2>/dev/null || normalize_version "$ver" 2>/dev/null || printf '%s' "$ver")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    if [[ "$(normalize_version "$line" 2>/dev/null || normalize_package_version "$line" 2>/dev/null || printf '%s' "$line")" == "$ver" ]]; then
      return 0
    fi
  done <"$file"
  printf '%s\n' "$ver" >>"$file"
}

# Read key=value from packages-meta/<pkg>/PACKAGE (no error if missing).
read_package_file_key() {
  local pkg=$1 key=$2
  local file line k val
  pkg="$(package_meta_id "$pkg")"
  file="$(package_meta_dir "$pkg")/PACKAGE"
  [[ -f "$file" ]] || return 1
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
  return 1
}

# Public home for a package: PACKAGE homepage=, else GitHub from fork_repo/repo.
package_home_url() {
  local pkg=$1 repo
  pkg="$(package_meta_id "$pkg")"
  repo="$(read_package_file_key "$pkg" homepage 2>/dev/null || true)"
  if [[ -n "$repo" ]]; then
    printf '%s' "$repo"
    return 0
  fi
  repo="$(read_package_file_key "$pkg" fork_repo 2>/dev/null || true)"
  [[ -n "$repo" ]] || repo="$(read_package_file_key "$pkg" repo 2>/dev/null || true)"
  [[ -n "$repo" ]] || return 1
  case "$repo" in
    https://* | http://*) printf '%s' "$repo" ;;
    *) printf 'https://github.com/%s' "$repo" ;;
  esac
}

# Human name for notes and docs. PACKAGE title=, else package id.
package_title() {
  local pkg=$1 title
  pkg="$(package_meta_id "$pkg")"
  title="$(read_package_file_key "$pkg" title 2>/dev/null || true)"
  if [[ -n "$title" ]]; then
    printf '%s' "$title"
    return 0
  fi
  printf '%s' "$pkg"
}

# Markdown label for release notes: [Title](home) or plain title.
package_notes_link() {
  local id=$1
  local label url
  label="$(package_title "$id")"
  if url="$(package_home_url "$id")"; then
    printf '[%s](%s)' "$label" "$url"
  else
    printf '%s' "$label"
  fi
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
firmware_stamp_from_version() {
  local v="${1#v}"
  if [[ "$v" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-ev([0-9]+)$ ]]; then
    printf '%s.%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  printf '%s' "$v"
}

package_firmware_stamp() {
  firmware_stamp_from_version "$(read_package_version "${1:-meshcore}")"
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
    bootloader | bl) key=$NRF52_BOOTLOADER_ID ;;
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
  printf '%s\n' meshcore "$NRF52_BOOTLOADER_ID" motatool
}

package_checkout_dir() {
  local pkg=$1
  pkg="$(package_meta_id "$pkg")"
  printf '%s' "$OTA_ROOT/packages/$pkg"
}

fetch_package_checkout() {
  local pkg=$1 sha repo dest
  pkg="$(package_meta_id "$pkg")"
  dest="$(package_checkout_dir "$pkg")"
  case "$pkg" in
    meshcore)
      repo="MeshEnvy/meshcore-firmware"
      sha="$(manifest_py get meshcore sha 2>/dev/null || true)"
      sha="${sha:-$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)}"
      ;;
    adafruit-nrf52-bootloader)
      repo="MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX"
      sha="$(manifest_py get "$NRF52_BOOTLOADER_ID" sha 2>/dev/null || true)"
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
    envybot)
      dest="$ENVYBOT_ROOT"
      if [[ -d "$dest/.git" ]]; then
        echo "fetch: envybot already present at $dest ($(git -C "$dest" rev-parse --short HEAD))"
        return 0
      fi
      echo "fetch: cloning MeshEnvy/envybot into $dest"
      mkdir -p "$(dirname "$dest")"
      git clone "https://github.com/MeshEnvy/envybot.git" "$dest"
      return 0
      ;;
    peaky)
      dest="$PEAKY_ROOT"
      if [[ -d "$dest/.git" ]]; then
        echo "fetch: peaky already present at $dest ($(git -C "$dest" rev-parse --short HEAD))"
        return 0
      fi
      echo "fetch: cloning MeshEnvy/peaky-finders into $dest"
      mkdir -p "$(dirname "$dest")"
      git clone "https://github.com/MeshEnvy/peaky-finders.git" "$dest"
      return 0
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

# Bench directory suffix: package semver (0.1.0) or overlay (1.16.0-ev1). Distro tags stay vX.Y.Z.
package_bench_version_label() {
  local ver=$1
  if normalize_package_version "$ver" >/dev/null 2>&1; then
    normalize_package_version "$ver"
    return 0
  fi
  normalize_version "$ver"
}

package_to_bench_id() {
  case "$1" in
    meshcore | firmware | fw) printf '%s' meshcore ;;
    bootloader | bl | adafruit-nrf52-bootloader) printf '%s' "$NRF52_BOOTLOADER_ID" ;;
    *) printf '%s' "$1" ;;
  esac
}
