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
  assert_component_tree_not_released motatool "$ver"
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

# All known distro versions: RELEASED_VERSIONS + build/motas/v* dirs.
list_known_mota_versions() {
  local line ver d
  local tmp=()
  if [[ -f "$RELEASED_VERSIONS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -n "$line" ]] || continue
      ver="$(normalize_version "$line" 2>/dev/null)" || continue
      tmp+=("$ver")
    done <"$RELEASED_VERSIONS_FILE"
  fi
  if [[ -d "$MOTAS_ROOT" ]]; then
    for d in "$MOTAS_ROOT"/v[0-9]*.[0-9]*.[0-9]*; do
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

# Every base B where B < target (for delta matrix into target's mota tree).
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

resolve_base_hex() {
  local slug="$1"
  local base_ver="$2"
  local candidates=(
    "$MOTAS_ROOT/$base_ver/$slug/firmware.hex"
  )
  if [[ "$slug" == "wismesh-tag-repeater" ]]; then
    candidates+=(
      "$MOTAS_ROOT/$base_ver/repeater/firmware.hex"
      "$MOTAS_ROOT/$base_ver/firmware.hex"
    )
  fi
  local p
  for p in "${candidates[@]}"; do
    if [[ -f "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# Fail publish when a released base has hex for slug but delta is missing.
verify_release_delta_matrix() {
  local ver="$1"
  local targets_file="$2"
  local line slug base_ver delta base_hex
  local missing=0

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

    while IFS= read -r base_ver || [[ -n "$base_ver" ]]; do
      [[ -n "$base_ver" ]] || continue
      resolve_base_hex "$slug" "$base_ver" >/dev/null || continue
      delta="$MOTAS_ROOT/$ver/$slug/delta_from_${base_ver}.mota"
      if [[ ! -f "$delta" ]]; then
        echo "error: missing $delta (base hex exists for $base_ver/$slug)" >&2
        missing=1
      fi
    done < <(list_delta_base_versions "$ver")
  done <"$targets_file"

  [[ "$missing" -eq 0 ]]
}

write_released_marker() {
  local ver="$1"
  local dir="$MOTAS_ROOT/$ver"
  local today
  today="$(date '+%Y-%m-%d')"
  cat >"$dir/.released" <<EOF
EnvyOS $ver — released $today. Do not delete or rebuild this directory.
Listed in RELEASED_VERSIONS; build-mota.sh refuses to overwrite released versions.
Includes delta_from_<base>.mota for every prior version with base hex (fleet jump updates).
EOF
}

# Distro release bundles these components (extend list when adding packages).
list_release_component_ids() {
  printf '%s\n' firmware bootloader motatool
}

component_build_root() {
  case "$1" in
    firmware) printf '%s' "$MOTAS_ROOT" ;;
    bootloader) printf '%s' "$BOOTLOADER_ROOT" ;;
    motatool) printf '%s' "$MOTATOOL_ROOT" ;;
    *)
      echo "error: unknown release component: $1" >&2
      return 1
      ;;
  esac
}

# Component version at publish time (before ENVYOS_VERSIONS bump).
component_version_at_publish() {
  local id=$1 distro_ver=$2
  case "$id" in
    firmware) printf '%s' "$distro_ver" ;;
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

component_zip_basename() {
  local id=$1 ver=$2
  case "$id" in
    firmware) printf 'firmware-%s.zip' "$ver" ;;
    bootloader) printf 'bootloader-%s.zip' "$ver" ;;
    motatool) printf 'motatool-%s.zip' "$ver" ;;
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
  local dir today
  dir="$MOTAS_ROOT/$distro_ver"
  today="$(date '+%Y-%m-%d')"
  mkdir -p "$dir"
  cat >"$dir/RELEASE_MANIFEST" <<EOF
# EnvyOS distro release manifest (immutable snapshot at publish)
distro=$distro_ver
firmware=$firmware_ver
bootloader=$bootloader_ver
motatool=$motatool_ver
published=$today
EOF
}

read_release_manifest_key() {
  local distro_ver=$1 key=$2
  local file line k val
  file="$MOTAS_ROOT/$distro_ver/RELEASE_MANIFEST"
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
    if [[ "$key" == "published" ]]; then
      printf '%s' "$val"
    else
      normalize_version "$val"
    fi
    return 0
  done <"$file"
  return 1
}

manifest_component_version() {
  local id=$1 distro_ver=$2
  local from_manifest ver legacy
  if from_manifest="$(read_release_manifest_key "$distro_ver" "$id" 2>/dev/null)"; then
    printf '%s' "$from_manifest"
    return 0
  fi
  ver="$(normalize_version "$distro_ver")"
  if [[ -d "$(component_build_dir "$id" "$ver")" ]]; then
    printf '%s' "$ver"
    return 0
  fi
  if [[ "$id" != firmware ]]; then
    while IFS= read -r legacy || [[ -n "$legacy" ]]; do
      [[ -n "$legacy" ]] || continue
      if version_lt "$legacy" "$distro_ver" && [[ -d "$(component_build_dir "$id" "$legacy")" ]]; then
        printf '%s' "$legacy"
        return 0
      fi
    done < <(list_known_mota_versions)
  fi
  component_version_at_publish "$id" "$distro_ver"
}

ensure_release_manifest_for_backfill() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver published
  [[ -f "$MOTAS_ROOT/$distro_ver/RELEASE_MANIFEST" ]] && return 0
  firmware_ver="$(manifest_component_version firmware "$distro_ver")"
  bootloader_ver="$(manifest_component_version bootloader "$distro_ver")"
  motatool_ver="$(manifest_component_version motatool "$distro_ver")"
  published="$(date '+%Y-%m-%d')"
  if [[ -f "$MOTAS_ROOT/$distro_ver/.released" ]]; then
    published="$(sed -n 's/.*released \([0-9-]*\).*/\1/p' "$MOTAS_ROOT/$distro_ver/.released" | head -1)"
    [[ -n "$published" ]] || published="$(date '+%Y-%m-%d')"
  fi
  mkdir -p "$MOTAS_ROOT/$distro_ver"
  cat >"$MOTAS_ROOT/$distro_ver/RELEASE_MANIFEST" <<EOF
# EnvyOS distro release manifest (backfilled at asset upload)
distro=$distro_ver
firmware=$firmware_ver
bootloader=$bootloader_ver
motatool=$motatool_ver
published=$published
EOF
}

verify_release_components() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver
  local id ver dir

  firmware_ver="$(normalize_version "$distro_ver")"
  bootloader_ver="$(read_bootloader_version)" || return 1
  motatool_ver="$(read_motatool_version)" || return 1

  local fw_key="${firmware_ver#v}"
  verify_firmware_version_sync "$fw_key" || {
    echo "error: publish $distro_ver requires envycore/envyos/VERSION == firmware ($fw_key)" >&2
    return 1
  }
  verify_motatool_version_sync "$motatool_ver" || return 1

  while IFS= read -r id || [[ -n "$id" ]]; do
    ver="$(component_version_at_publish "$id" "$distro_ver")" || return 1
    dir="$(component_build_dir "$id" "$ver")"
    [[ -d "$dir" ]] || {
      echo "error: missing $id artifacts at $dir — run ./scripts/build.sh first" >&2
      return 1
    }
    if [[ -f "$dir/version.txt" ]]; then
      local actual
      actual="$(head -1 "$dir/version.txt" | tr -d '[:space:]]')"
      [[ "$(normalize_version "$actual")" == "$ver" ]] || {
        echo "error: $dir/version.txt ($actual) != expected $ver" >&2
        return 1
      }
    fi
  done < <(list_release_component_ids)

  if [[ "$firmware_ver" != "$(read_distro_version)" ]]; then
    echo "error: publish version $distro_ver != ENVYOS_VERSIONS distro ($(read_distro_version))" >&2
    return 1
  fi

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

  write_release_manifest "$firmware_ver" "$firmware_ver" "$bootloader_ver" "$motatool_ver"
  write_released_marker "$firmware_ver"
  write_component_released_marker bootloader "$bootloader_ver" "$distro_ver"
  write_component_released_marker motatool "$motatool_ver" "$distro_ver"
}

collect_distro_release_assets() {
  local distro_ver=$1
  local id ver zip assets=()
  while IFS= read -r id || [[ -n "$id" ]]; do
    ver="$(manifest_component_version "$id" "$distro_ver")" || continue
    if [[ -d "$(component_build_dir "$id" "$ver")" ]]; then
      zip="$(create_component_zip "$id" "$ver")"
      assets+=("$zip")
    else
      echo "warning: skip $id $ver — $(component_build_dir "$id" "$ver") missing" >&2
    fi
  done < <(list_release_component_ids)
  if ((${#assets[@]} > 0)); then
    printf '%s\n' "${assets[@]}"
  fi
}

release_notes_for_distro() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver published
  firmware_ver="$(manifest_component_version firmware "$distro_ver")"
  bootloader_ver="$(manifest_component_version bootloader "$distro_ver")"
  motatool_ver="$(manifest_component_version motatool "$distro_ver")"
  published="$(read_release_manifest_key "$distro_ver" published 2>/dev/null || date '+%Y-%m-%d')"

  cat <<EOF
EnvyOS distro release **${distro_ver}** (${published}).

| Component | Version |
|-----------|---------|
| firmware | ${firmware_ver} |
| bootloader | ${bootloader_ver} |
| motatool | ${motatool_ver} |

### Assets

- \`firmware-${firmware_ver}.zip\` — fleet firmware (\`.mota\`, hex, uf2; \`delta_from_<base>.mota\` for prior releases)
- \`bootloader-${bootloader_ver}.zip\` — OTAFIX UF2 (+ recovery zips) per board in \`targets.txt\`
- \`motatool-${motatool_ver}.zip\` — bench \`motatool\` binary (\`serve\`, pack, verify)

Extract zips under \`build/\` to match local bench layout (\`build/motas/\`, \`build/bootloader/\`, \`build/motatool/\`).
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
