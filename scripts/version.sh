#!/usr/bin/env bash
# EnvyOS distro manifest + publish helpers. Package builds live in sibling repos.
set -euo pipefail

OTA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_JSON="${MANIFEST_JSON:-$OTA_ROOT/MANIFEST.json}"
MANIFEST_PY="$OTA_ROOT/scripts/manifest.py"
PACKAGES_ROOT="$OTA_ROOT/packages"
PACKAGES_META_ROOT="$OTA_ROOT/packages-meta"

MESHENVY_ROOT="$(cd "$OTA_ROOT/.." && pwd)"
MESHCORE_ROOT="${MESHCORE_ROOT:-$PACKAGES_ROOT/meshcore}"
_BOOTLOADER_SRC_OVERRIDE="${BOOTLOADER_SRC:-}"
MCMT_ROOT="${MCMT_ROOT:-$PACKAGES_ROOT/mcmt-gateway}"
MOTATOOL_ROOT="${MOTATOOL_ROOT:-$PACKAGES_ROOT/motatool}"
MESHCORE_OPEN_ROOT="${MESHCORE_OPEN_ROOT:-$PACKAGES_ROOT/meshcore-open}"
PEAKY_ROOT="${PEAKY_ROOT:-$MESHENVY_ROOT/peaky_finders}"
ENVYBOT_ROOT="${ENVYBOT_ROOT:-$MESHENVY_ROOT/envybot}"

BUILD_ROOT="$OTA_ROOT/build"
PEAKY_GITHUB_REPO="${PEAKY_GITHUB_REPO:-MeshEnvy/peaky-finders}"
export ENVYOS_ROOT="$OTA_ROOT"
export MANIFEST_JSON MANIFEST_PY
export MESHCORE_ROOT MCMT_ROOT MOTATOOL_ROOT MESHCORE_OPEN_ROOT PEAKY_ROOT ENVYBOT_ROOT PACKAGES_ROOT PACKAGES_META_ROOT

manifest_py() {
  python3 "$MANIFEST_PY" "$MANIFEST_JSON" --packages-meta "$PACKAGES_META_ROOT" "$@"
}

# shellcheck source=scripts/packages-meta-lib.sh
source "$OTA_ROOT/scripts/packages-meta-lib.sh"

if [[ -n "$_BOOTLOADER_SRC_OVERRIDE" ]]; then
  BOOTLOADER_SRC="$_BOOTLOADER_SRC_OVERRIDE"
else
  BOOTLOADER_SRC="$(package_checkout_dir adafruit-nrf52-bootloader)"
fi
export BOOTLOADER_SRC
unset _BOOTLOADER_SRC_OVERRIDE

RELEASED_FIRMWARE_FILE="${RELEASED_FIRMWARE_FILE:-$(package_releases_file meshcore)}"
RELEASED_BOOTLOADER_FILE="${RELEASED_BOOTLOADER_FILE:-$(package_releases_file adafruit-nrf52-bootloader)}"
export RELEASED_FIRMWARE_FILE RELEASED_BOOTLOADER_FILE

normalize_version() {
  local v="${1#v}"
  if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid version '$1' (want vMAJOR.MINOR.PATCH)" >&2
    return 1
  fi
  printf 'v%s' "$v"
}

read_manifest_key() {
  local key=$1 val
  case "$key" in
    firmware) key=meshcore ;;
    bootloader | bl) key=$NRF52_BOOTLOADER_ID ;;
  esac
  [[ -f "$MANIFEST_JSON" ]] || {
    echo "error: missing $MANIFEST_JSON" >&2
    return 1
  }
  val="$(manifest_py get "$key" version)" || {
    echo "error: missing key '$key' in $MANIFEST_JSON" >&2
    return 1
  }
  case "$key" in
    meshcore | motatool | adafruit-nrf52-bootloader)
      normalize_package_version "$val"
      ;;
    *)
      normalize_version "$val"
      ;;
  esac
}

# Optional manifest entries (peaky, mcmt-gateway, envybot) — absent until pinned for a distro bundle.
read_optional_manifest_key() {
  local key=$1 val
  [[ -f "$MANIFEST_JSON" ]] || return 1
  manifest_py has "$key" --field version 2>/dev/null || return 1
  val="$(manifest_py get "$key" version)" || return 1
  normalize_package_version "$val"
}

read_meshcore_version() { read_manifest_key meshcore; }
read_firmware_version() { read_meshcore_version; }
read_bootloader_version() { read_manifest_key adafruit-nrf52-bootloader; }
read_motatool_version() { read_manifest_key motatool; }
read_peaky_version() { read_optional_manifest_key peaky; }
read_mcmt_gateway_version() { read_optional_manifest_key mcmt-gateway; }
read_envybot_version() { read_optional_manifest_key envybot; }

read_bootloader_version_file() { read_bootloader_version; }

list_manifest() {
  manifest_py list
}

# Last shipped fleet tag (MANIFEST.json releases tail); v0.0.0 when none.
latest_released_distro_version() {
  manifest_py releases latest 2>/dev/null || printf 'v0.0.0'
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
    echo "error: peaky_finders/Cargo.toml version ($actual) != MANIFEST peaky ($expected)" >&2
    return 1
  }
}

read_envybot_pyproject_version() {
  local toml="$ENVYBOT_ROOT/pyproject.toml"
  [[ -f "$toml" ]] || return 1
  awk '/^version = /{gsub(/^version = "|"$/,""); print; exit}' "$toml"
}

read_mcmt_gateway_pyproject_version() {
  local toml="$MCMT_ROOT/pyproject.toml"
  [[ -f "$toml" ]] || return 1
  awk '/^version = /{gsub(/^version = "|"$/,""); print; exit}' "$toml"
}

verify_envybot_version_sync() {
  local expected="${1#v}"
  local actual
  actual="$(read_envybot_pyproject_version)" || {
    echo "error: envybot repo not found at $ENVYBOT_ROOT" >&2
    return 1
  }
  [[ "$actual" == "$expected" ]] || {
    echo "error: envybot/pyproject.toml version ($actual) != MANIFEST envybot ($expected)" >&2
    return 1
  }
}

verify_mcmt_gateway_version_sync() {
  local expected="${1#v}"
  local actual
  actual="$(read_mcmt_gateway_pyproject_version)" || {
    echo "error: mcmt-gateway repo not found at $MCMT_ROOT" >&2
    return 1
  }
  [[ "$actual" == "$expected" ]] || {
    echo "error: mcmt-gateway/pyproject.toml version ($actual) != MANIFEST mcmt-gateway ($expected)" >&2
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

# True when ver is listed in MANIFEST.json releases (shipped, immutable mota tree).
is_released_version() {
  local ver
  ver="$(normalize_version "$1")" || return 1
  manifest_py releases has "$ver" 2>/dev/null
}

assert_version_not_released() {
  local ver="$1"
  if is_released_firmware_version "$ver" || is_released_version "$ver"; then
    echo "error: $ver is released — $(firmware_bench_root "$ver" "$ver") is immutable" >&2
    echo "       (listed in packages-meta/meshcore/RELEASES or MANIFEST.json releases)" >&2
    exit 1
  fi
}

# Zero-padded key for portable version sort (macOS sort lacks -V).
version_sort_key() {
  local ver="$1" major minor patch ev upstream
  ver="${ver#v}"
  if [[ "$ver" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-ev([0-9]+)$ ]]; then
    upstream="${BASH_REMATCH[1]}"
    ev="${BASH_REMATCH[2]}"
    IFS=. read -r major minor patch <<<"$upstream"
    printf '%03d.%03d.%03d.%03d' "$major" "$minor" "${patch:-0}" "$ev"
    return 0
  fi
  read -r major minor patch <<<"$(parse_version "$1")"
  printf '%03d.%03d.%03d.%03d' "$major" "$minor" "$patch" 0
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
  # upstream-evN builds: delta bases are released distro semver firmware trees.
  if normalize_package_version "$1" >/dev/null 2>&1; then
    while IFS= read -r ver || [[ -n "$ver" ]]; do
      [[ -n "$ver" ]] || continue
      printf '%s\n' "$ver"
    done < <(read_registry_versions "$RELEASED_FIRMWARE_FILE")
    return 0
  fi
  target="$(normalize_version "$1")" || return 1
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    if version_lt "$ver" "$target"; then
      printf '%s\n' "$ver"
    fi
  done < <(list_known_mota_versions | while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    ver="$(normalize_version "$ver" 2>/dev/null)" || continue
    printf '%s\n' "$ver"
  done | awk '!seen[$0]++')
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

write_firmware_version_file() {
  return 0
}

write_motatool_cargo_version() {
  return 0
}

append_released_version() {
  local ver="$1"
  ver="$(normalize_version "$ver")"
  if is_released_version "$ver"; then
    echo "error: $ver is already listed in MANIFEST.json releases" >&2
    return 1
  fi
  lock_manifest_checkouts
  manifest_py releases record "$ver"
  append_package_release firmware "$ver"
}

read_package_manifest_sha() {
  local name=$1
  case "$name" in
    firmware) name=meshcore ;;
    bootloader | bl) name=$NRF52_BOOTLOADER_ID ;;
  esac
  manifest_py get "$name" sha 2>/dev/null || true
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
    echo "error: $label HEAD ($actual) != MANIFEST.json ($expected_sha)" >&2
    return 1
  }
}

verify_packages_lock() {
  local sha
  sha="$(read_package_manifest_sha meshcore)"
  verify_sibling_sha "$MESHCORE_ROOT" "$sha" meshcore || return 1
  sha="$(read_package_manifest_sha adafruit-nrf52-bootloader)"
  verify_sibling_sha "$BOOTLOADER_SRC" "$sha" adafruit-nrf52-bootloader || return 1
  sha="$(read_package_manifest_sha motatool)"
  verify_sibling_sha "$MOTATOOL_ROOT" "$sha" motatool || return 1
  if manifest_py has mcmt-gateway --field version 2>/dev/null; then
    sha="$(read_package_manifest_sha mcmt-gateway)"
    verify_sibling_sha "$MCMT_ROOT" "$sha" mcmt-gateway || return 1
  fi
  if manifest_py has envybot --field version 2>/dev/null; then
    sha="$(read_package_manifest_sha envybot)"
    verify_sibling_sha "$ENVYBOT_ROOT" "$sha" envybot || return 1
  fi
  if manifest_py has peaky --field version 2>/dev/null; then
    verify_peaky_release_sha || return 1
  fi
}

lock_manifest_checkouts() {
  local specs=()
  specs+=("meshcore=$(git -C "$MESHCORE_ROOT" rev-parse HEAD)")
  specs+=("adafruit-nrf52-bootloader=$(git -C "$BOOTLOADER_SRC" rev-parse HEAD)")
  specs+=("motatool=$(git -C "$MOTATOOL_ROOT" rev-parse HEAD)")
  if manifest_py has mcmt-gateway --field version 2>/dev/null; then
    local mcmt_sha
    mcmt_sha="$(git -C "$MCMT_ROOT" rev-parse HEAD 2>/dev/null || true)"
    [[ -n "$mcmt_sha" ]] && specs+=("mcmt-gateway=$mcmt_sha")
  fi
  if manifest_py has envybot --field version 2>/dev/null; then
    local envybot_sha
    envybot_sha="$(git -C "$ENVYBOT_ROOT" rev-parse HEAD 2>/dev/null || true)"
    [[ -n "$envybot_sha" ]] && specs+=("envybot=$envybot_sha")
  fi
  if manifest_py has peaky --field version 2>/dev/null; then
    local peaky_sha
    peaky_sha="$(peaky_pin_sha 2>/dev/null || true)"
    [[ -n "$peaky_sha" ]] && specs+=("peaky=$peaky_sha")
  fi
  manifest_py lock "${specs[@]}"
}

package_in_distro_bundle() {
  local id=$1 distro_ver=$2
  case "$id" in
    mcmt-gateway)
      read_optional_manifest_key mcmt-gateway >/dev/null 2>&1 && return 0
      is_version_tree_key "$distro_ver" || return 1
      local major minor patch
      read -r major minor patch <<<"$(parse_version "$distro_ver")"
      (( major > 0 || minor >= 2 ))
      ;;
    peaky)
      read_optional_manifest_key peaky >/dev/null 2>&1
      ;;
    envybot)
      read_optional_manifest_key envybot >/dev/null 2>&1
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

  if is_package_tree_released motatool "$ver"; then
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

# SHA of the pinned peaky tag (vX.Y.Z), not sibling HEAD. Artifacts come from GitHub Release.
peaky_pin_sha() {
  local ver=${1:-}
  [[ -d "$PEAKY_ROOT/.git" ]] || return 1
  ver="${ver:-$(read_peaky_version)}"
  git -C "$PEAKY_ROOT" rev-parse "v${ver#v}^{commit}"
}

verify_peaky_release_sha() {
  local expected_sha tag_sha ver
  expected_sha="$(read_package_manifest_sha peaky)"
  [[ -n "$expected_sha" ]] || return 0
  [[ -d "$PEAKY_ROOT/.git" ]] || return 0
  ver="$(read_peaky_version)"
  tag_sha="$(peaky_pin_sha "$ver")" || {
    echo "error: peaky v${ver#v} tag missing in $PEAKY_ROOT" >&2
    return 1
  }
  [[ "$tag_sha" == "$expected_sha" ]] || {
    echo "error: peaky v${ver#v} ($tag_sha) != MANIFEST.json ($expected_sha)" >&2
    return 1
  }
}

ensure_peaky_release_cache() {
  local ver=$1
  ver="$(normalize_version "$ver")"
  local dir distro host_triple
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dir="$(peaky_bench_root "$distro" "$ver")"

  if peaky_all_platforms_present "$ver"; then
    return 0
  fi

  if is_package_tree_released peaky "$ver"; then
    echo "error: peaky $ver is a released tree — $dir is immutable" >&2
    return 1
  fi

  if command -v gh >/dev/null 2>&1; then
    download_peaky_release_assets "$ver" 1 || true
  fi
  if peaky_all_platforms_present "$ver"; then
    return 0
  fi

  host_triple="$(peaky_host_rust_target 2>/dev/null || true)"
  if [[ -n "$host_triple" && -d "$PEAKY_ROOT" ]] && ! peaky_platform_has_binary "$ver" "$host_triple"; then
    if command -v cargo >/dev/null 2>&1; then
      build_peaky_local "$ver" || true
    fi
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

ensure_envybot_wheel() {
  local ver=$1 dir distro wheel src
  ver="$(normalize_package_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dir="$(envybot_bench_root "$distro" "$ver")"
  wheel="$dir/$(envybot_wheel_basename "$ver")"

  if [[ -f "$wheel" ]]; then
    return 0
  fi

  [[ -d "$ENVYBOT_ROOT" ]] || {
    echo "error: envybot repo not found at $ENVYBOT_ROOT" >&2
    return 1
  }

  if is_package_tree_released envybot "$ver"; then
    echo "error: envybot $ver is a released tree — $dir is immutable" >&2
    return 1
  fi

  command -v uv >/dev/null 2>&1 || {
    echo "error: uv not on PATH — needed to build the envybot wheel" >&2
    return 1
  }

  echo "envybot: uv build ($ENVYBOT_ROOT)"
  (
    cd "$ENVYBOT_ROOT"
    uv build
  )
  mkdir -p "$dir"
  src="$(echo "$ENVYBOT_ROOT"/dist/envybot-"${ver#v}"-py3-none-any.whl)"
  [[ -f "$src" ]] || {
    echo "error: uv build did not produce $src" >&2
    return 1
  }
  cp -f "$src" "$wheel"
  if [[ -f "$ENVYBOT_ROOT/dist/envybot-${ver#v}.tar.gz" ]]; then
    cp -f "$ENVYBOT_ROOT/dist/envybot-${ver#v}.tar.gz" "$dir/"
  fi
  printf '%s\n' "$ver" >"$dir/version.txt"
  echo "envybot: staged $wheel"
}

ensure_mcmt_gateway_wheel() {
  local ver=$1 dir distro wheel src
  ver="$(normalize_package_version "$ver")"
  distro="$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")"
  dir="$(mcmt_gateway_bench_root "$distro" "$ver")"
  wheel="$dir/$(mcmt_gateway_wheel_basename "$ver")"

  if [[ -f "$wheel" ]]; then
    return 0
  fi

  [[ -d "$MCMT_ROOT" ]] || {
    echo "error: mcmt-gateway checkout not found at $MCMT_ROOT — run ./envyos fetch mcmt-gateway" >&2
    return 1
  }

  if is_package_tree_released mcmt-gateway "$ver"; then
    echo "error: mcmt-gateway $ver is a released tree — $dir is immutable" >&2
    return 1
  fi

  command -v uv >/dev/null 2>&1 || {
    echo "error: uv not on PATH — needed to build the mcmt-gateway wheel" >&2
    return 1
  }

  echo "mcmt-gateway: uv build ($MCMT_ROOT)"
  (
    cd "$MCMT_ROOT"
    uv build
  )
  mkdir -p "$dir"
  src="$(echo "$MCMT_ROOT"/dist/mcmt_gateway-"${ver#v}"-py3-none-any.whl)"
  [[ -f "$src" ]] || {
    echo "error: uv build did not produce $src" >&2
    return 1
  }
  cp -f "$src" "$wheel"
  if [[ -f "$MCMT_ROOT/dist/mcmt_gateway-${ver#v}.tar.gz" ]]; then
    cp -f "$MCMT_ROOT/dist/mcmt_gateway-${ver#v}.tar.gz" "$dir/"
  fi
  printf '%s\n' "$ver" >"$dir/version.txt"
  echo "mcmt-gateway: staged $wheel"
}

write_released_marker() {
  local ver="$1"
  local dir
  dir="$(firmware_bench_root "$ver" "$ver")"
  local today
  today="$(date '+%Y-%m-%d')"
  cat >"$dir/.released" <<EOF
EnvyOS $ver — released $today. Do not delete or rebuild this directory.
Listed in MANIFEST.json releases and packages-meta/meshcore/RELEASES; the meshcore recipe refuses to overwrite released versions.
Includes delta_from_<base>.mota for every prior version with base hex (fleet jump updates).
EOF
}

# Distro release bundles these packages (extend list when adding packages).
list_release_package_ids() {
  local distro_ver="${1:-}"
  if [[ -z "$distro_ver" ]]; then
    distro_ver="$(latest_released_distro_version)"
  fi
  printf '%s\n' meshcore adafruit-nrf52-bootloader motatool
  if package_in_distro_bundle mcmt-gateway "$distro_ver"; then
    printf '%s\n' mcmt-gateway
  fi
  if package_in_distro_bundle peaky "$distro_ver"; then
    printf '%s\n' peaky
  fi
  if package_in_distro_bundle envybot "$distro_ver"; then
    printf '%s\n' envybot
  fi
}

package_build_root() {
  local id=$1 distro_ver=${2:-}
  distro_ver="${distro_ver:-$(read_bench_tree_key 2>/dev/null || echo dev)}"
  case "$id" in
    firmware | meshcore | bootloader | adafruit-nrf52-bootloader | motatool | peaky | envybot | mcmt-gateway) distro_bench_root "$distro_ver" ;;
    *)
      echo "error: unknown release package: $1" >&2
      return 1
      ;;
  esac
}

# Package version pinned in MANIFEST.
package_version_at_publish() {
  local id=$1 distro_ver=$2
  case "$id" in
    firmware | meshcore) read_firmware_version ;;
    bootloader | adafruit-nrf52-bootloader) read_bootloader_version ;;
    motatool) read_motatool_version ;;
    mcmt-gateway) read_mcmt_gateway_version ;;
    peaky) read_peaky_version ;;
    envybot) read_envybot_version ;;
    *)
      echo "error: unknown release package: $id" >&2
      return 1
      ;;
  esac
}

package_build_dir() {
  local id=$1 ver=$2 distro_ver=${3:-}
  distro_ver="${distro_ver:-$(read_bench_tree_key 2>/dev/null || printf '%s' "$ver")}"
  case "$id" in
    firmware | meshcore) firmware_bench_root "$distro_ver" "$ver" ;;
    bootloader | adafruit-nrf52-bootloader) bootloader_bench_root "$distro_ver" "$ver" ;;
    motatool) motatool_bench_root "$distro_ver" "$ver" ;;
    peaky) peaky_bench_root "$distro_ver" "$ver" ;;
    envybot) envybot_bench_root "$distro_ver" "$ver" ;;
    mcmt-gateway) mcmt_gateway_bench_root "$distro_ver" "$ver" ;;
    *)
      echo "error: unknown release package: $id" >&2
      return 1
      ;;
  esac
}

package_zip_basename() {
  local id=$1 ver=$2
  case "$id" in
    firmware | meshcore) printf 'meshcore-%s.zip' "$ver" ;;
    bootloader | adafruit-nrf52-bootloader) printf 'adafruit-nrf52-bootloader-%s.zip' "$ver" ;;
    motatool) printf 'motatool-%s.zip' "$ver" ;;
    mcmt-gateway) printf 'mcmt_gateway-%s-py3-none-any.whl' "${ver#v}" ;;
    peaky) printf 'peaky-%s.zip' "$ver" ;;
    envybot) printf 'envybot-%s-py3-none-any.whl' "${ver#v}" ;;
  esac
}

package_zip_path() {
  local id=$1 ver=$2
  printf '%s/%s' "$OTA_ROOT" "$(package_zip_basename "$id" "$ver")"
}

is_package_tree_released() {
  local id=$1 ver=$2
  [[ -f "$(package_build_dir "$id" "$ver")/.released" ]]
}

assert_package_tree_not_released() {
  local id=$1 ver=$2
  if is_package_tree_released "$id" "$ver"; then
    echo "error: $ver is a released $id tree — $(package_build_dir "$id" "$ver") is immutable" >&2
    exit 1
  fi
}

write_package_released_marker() {
  local id=$1 ver=$2 distro_ver=$3
  local dir today
  dir="$(package_build_dir "$id" "$ver")"
  today="$(date '+%Y-%m-%d')"
  cat >"$dir/.released" <<EOF
EnvyOS package $id $ver — published in distro $distro_ver on $today.
Do not delete or rebuild this directory.
EOF
}

write_release_manifest() {
  local distro_ver=$1 firmware_ver=$2 bootloader_ver=$3 motatool_ver=$4
  local dir today peaky_ver mcmt_ver envybot_ver
  dir="$(distro_tree_root "$distro_ver")"
  today="$(date '+%Y-%m-%d')"
  mkdir -p "$dir"
  cat >"$(release_manifest_path "$distro_ver")" <<EOF
# EnvyOS distro release manifest (immutable snapshot at publish)
distro=$distro_ver
meshcore=$firmware_ver
adafruit-nrf52-bootloader=$bootloader_ver
motatool=$motatool_ver
published=$today
EOF
  if package_in_distro_bundle mcmt-gateway "$distro_ver"; then
    mcmt_ver="$(read_mcmt_gateway_version)"
    printf 'mcmt-gateway=%s\n' "$mcmt_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
  if package_in_distro_bundle peaky "$distro_ver"; then
    peaky_ver="$(read_peaky_version)"
    printf 'peaky=%s\n' "$peaky_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
  if package_in_distro_bundle envybot "$distro_ver"; then
    envybot_ver="$(read_envybot_version)"
    printf 'envybot=%s\n' "$envybot_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
}

_format_release_manifest_val() {
  local key=$1 val=$2
  if [[ "$key" == "published" ]]; then
    printf '%s' "$val"
  elif [[ "$key" == "firmware" || "$key" == "meshcore" || "$key" == "motatool" ]] || is_nrf52_bootloader_id "$key"; then
    normalize_package_version "$val"
  else
    normalize_version "$val"
  fi
}

read_release_manifest_key() {
  local distro_ver=$1 key=$2
  local manifest_key=$2 val file line k from_gh try
  distro_ver="$(normalize_version "$distro_ver")"
  case "$key" in
    distro)
      printf '%s' "$distro_ver"
      return 0
      ;;
    firmware)
      manifest_key=meshcore
      ;;
    bootloader | bl | adafruit-nrf52-bootloader)
      for try in adafruit-nrf52-bootloader bootloader; do
        val="$(manifest_py releases get "$distro_ver" "$try" version 2>/dev/null || true)"
        if [[ -n "$val" ]]; then
          normalize_package_version "$val"
          return 0
        fi
      done
      manifest_key=""
      ;;
    *)
      manifest_key=$key
      ;;
  esac
  if [[ "$key" == "published" ]]; then
    manifest_py releases get "$distro_ver" published 2>/dev/null && return 0
  elif [[ -n "$manifest_key" ]]; then
    val="$(manifest_py releases get "$distro_ver" "$manifest_key" version 2>/dev/null || true)"
    if [[ -n "$val" ]]; then
      _format_release_manifest_val "$manifest_key" "$val"
      return 0
    fi
  fi
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
      release_key_matches "$key" "$k" || continue
      val="${line#*=}"
      val="${val#"${val%%[![:space:]]*}"}"
      val="${val%"${val##*[![:space:]]}"}"
      _format_release_manifest_val "$key" "$val"
      return 0
    done <"$file"
  fi
  from_gh="$(read_release_manifest_key_from_github "$distro_ver" "$key" 2>/dev/null || true)"
  [[ -n "$from_gh" ]] || return 1
  _format_release_manifest_val "$key" "$from_gh"
}

read_release_manifest_key_from_github() {
  local distro_ver=$1 key=$2
  local title repo alias extra=""
  command -v gh >/dev/null 2>&1 || return 1
  title="$(package_title "$key" 2>/dev/null || true)"
  repo="$(read_package_file_key "$key" fork_repo 2>/dev/null || true)"
  [[ -n "$repo" ]] || repo="$(read_package_file_key "$key" repo 2>/dev/null || true)"
  alias="$(package_meta_id "$key" 2>/dev/null || true)"
  if is_nrf52_bootloader_id "$key"; then
    extra=bootloader
  fi
  gh release view "$distro_ver" --json body -q .body 2>/dev/null | awk -v want="$key" -v title="$title" -v repo="$repo" -v alias="$alias" -v extra="$extra" '
    /^\|/ && $0 !~ /Component/ && $0 !~ /Package/ && $0 !~ /---/ {
      n = split($0, cells, "|")
      for (i = 1; i <= n; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", cells[i])
      }
      raw = cells[2]
      label = raw
      if (label ~ /^\[[^\]]+\]\([^)]+\)$/) {
        label = substr(label, 2, index(label, "]") - 2)
      }
      hit = (label == want)
      if (!hit && title != "" && label == title) hit = 1
      if (!hit && alias != "" && label == alias) hit = 1
      if (!hit && extra != "" && label == extra) hit = 1
      if (!hit && repo != "" && index(raw, repo)) hit = 1
      if (hit && cells[3] != "") {
        print cells[3]
        exit 0
      }
    }
  '
}

manifest_package_version() {
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
  if [[ -n "$ver" && -d "$(package_build_dir "$id" "$ver" "$distro_ver")" ]]; then
    printf '%s' "$ver"
    return 0
  fi
  if [[ "$id" == firmware ]]; then
    ver="$(read_firmware_version 2>/dev/null || true)"
    if [[ -n "$ver" && -d "$(package_build_dir "$id" "$ver" "$distro_ver")" ]]; then
      printf '%s' "$ver"
      return 0
    fi
  fi
  if [[ "$id" != firmware ]]; then
    while IFS= read -r legacy || [[ -n "$legacy" ]]; do
      [[ -n "$legacy" ]] || continue
      if version_lt "$legacy" "$distro_ver" && [[ -d "$(package_build_dir "$id" "$legacy" "$distro_ver")" ]]; then
        printf '%s' "$legacy"
        return 0
      fi
    done < <(list_known_mota_versions)
  fi
  package_version_at_publish "$id" "$distro_ver"
}

ensure_release_manifest_for_backfill() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver published mcmt_ver peaky_ver envybot_ver
  [[ -f "$(release_manifest_path "$distro_ver")" ]] && return 0
  [[ -f "$(firmware_bench_root "$distro_ver" "$distro_ver")/RELEASE_MANIFEST" ]] && return 0
  [[ -f "$(distro_bench_root "$distro_ver")/firmware/RELEASE_MANIFEST" ]] && return 0
  firmware_ver="$(manifest_package_version firmware "$distro_ver")"
  bootloader_ver="$(manifest_package_version bootloader "$distro_ver")"
  motatool_ver="$(manifest_package_version motatool "$distro_ver")"
  published="$(date '+%Y-%m-%d')"
  if [[ -f "$(distro_tree_root "$distro_ver")/.released" ]]; then
    published="$(sed -n 's/.*released \([0-9-]*\).*/\1/p' "$(distro_tree_root "$distro_ver")/.released" | head -1)"
    [[ -n "$published" ]] || published="$(date '+%Y-%m-%d')"
  fi
  mkdir -p "$(distro_tree_root "$distro_ver")"
  cat >"$(release_manifest_path "$distro_ver")" <<EOF
# EnvyOS distro release manifest (backfilled at asset upload)
distro=$distro_ver
meshcore=$firmware_ver
adafruit-nrf52-bootloader=$bootloader_ver
motatool=$motatool_ver
published=$published
EOF
  if package_in_distro_bundle mcmt-gateway "$distro_ver"; then
    mcmt_ver="$(manifest_package_version mcmt-gateway "$distro_ver")"
    printf 'mcmt-gateway=%s\n' "$mcmt_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
  if package_in_distro_bundle peaky "$distro_ver"; then
    peaky_ver="$(manifest_package_version peaky "$distro_ver")"
    printf 'peaky=%s\n' "$peaky_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
  if package_in_distro_bundle envybot "$distro_ver"; then
    envybot_ver="$(manifest_package_version envybot "$distro_ver")"
    printf 'envybot=%s\n' "$envybot_ver" >>"$(release_manifest_path "$distro_ver")"
  fi
}

verify_release_packages() {
  local distro_ver=$1
  local motatool_ver
  local id ver dir

  motatool_ver="$(read_motatool_version)" || return 1

  ensure_motatool_release_cache "$motatool_ver"

  while IFS= read -r id || [[ -n "$id" ]]; do
    ver="$(package_version_at_publish "$id" "$distro_ver")" || return 1
    if [[ "$id" == motatool ]]; then
      ensure_motatool_release_cache "$ver" || return 1
    fi
    if [[ "$id" == peaky ]]; then
      verify_peaky_version_sync "$ver" || return 1
      ensure_peaky_release_cache "$ver" || return 1
    fi
    if [[ "$id" == envybot ]]; then
      verify_envybot_version_sync "$ver" || return 1
      ensure_envybot_wheel "$ver" || return 1
    fi
    if [[ "$id" == mcmt-gateway ]]; then
      verify_mcmt_gateway_version_sync "$ver" || return 1
      ensure_mcmt_gateway_wheel "$ver" || return 1
    fi
    dir="$(package_build_dir "$id" "$ver" "$distro_ver")"
    [[ -d "$dir" ]] || {
      echo "error: missing $id artifacts at $dir — run ./envyos build first" >&2
      return 1
    }
    if [[ -f "$dir/version.txt" ]]; then
      local actual
      actual="$(head -1 "$dir/version.txt" | tr -d '[:space:]]')"
      [[ "$(normalize_package_version "$actual")" == "$ver" ]] || {
        echo "error: $dir/version.txt ($actual) != expected $ver" >&2
        return 1
      }
    fi
  done < <(list_release_package_ids "$distro_ver")

  verify_packages_lock || true
  verify_release_delta_matrix "$distro_ver" "$OTA_ROOT/scripts/targets.txt"
}

create_package_zip() {
  local id=$1 ver=$2
  local src zip base
  src="$(package_build_dir "$id" "$ver")"
  zip="$(package_zip_path "$id" "$ver")"
  base="$(basename "$src")"
  [[ -d "$src" ]] || {
    echo "error: missing $src" >&2
    return 1
  }
  rm -f "$zip"
  (
    cd "$(package_build_root "$id")"
    zip -rq "$zip" "$base" -x "*.DS_Store" -x "*/.DS_Store"
  )
  echo "$zip"
}

lock_release_packages() {
  local distro_ver=$1
  local firmware_ver bootloader_ver motatool_ver id ver

  firmware_ver="$(read_release_manifest_key "$distro_ver" firmware)"
  bootloader_ver="$(read_release_manifest_key "$distro_ver" bootloader)"
  motatool_ver="$(read_release_manifest_key "$distro_ver" motatool)"

  write_release_manifest "$distro_ver" "$firmware_ver" "$bootloader_ver" "$motatool_ver"
  write_released_marker "$firmware_ver"
  write_package_released_marker meshcore "$firmware_ver" "$distro_ver"
  write_package_released_marker adafruit-nrf52-bootloader "$bootloader_ver" "$distro_ver"
  write_package_released_marker motatool "$motatool_ver" "$distro_ver"
  if package_in_distro_bundle mcmt-gateway "$distro_ver"; then
    local mcmt_ver mcmt_sha
    mcmt_ver="$(read_mcmt_gateway_version)"
    mcmt_sha="$(git -C "$MCMT_ROOT" rev-parse HEAD)"
    write_package_released_marker mcmt-gateway "$mcmt_ver" "$distro_ver"
  fi
  if package_in_distro_bundle peaky "$distro_ver"; then
    local peaky_ver
    peaky_ver="$(read_peaky_version)"
    write_package_released_marker peaky "$peaky_ver" "$distro_ver"
  fi
  if package_in_distro_bundle envybot "$distro_ver"; then
    local envybot_ver
    envybot_ver="$(read_envybot_version)"
    write_package_released_marker envybot "$envybot_ver" "$distro_ver"
  fi
  mkdir -p "$(distro_tree_root "$distro_ver")"
  cp "$MANIFEST_JSON" "$(distro_tree_root "$distro_ver")/MANIFEST.json"
}

collect_distro_release_assets() {
  local distro_ver=$1
  local release_dir f
  distro_ver="$(normalize_version "$distro_ver")"
  release_dir="$(distro_release_root "$distro_ver")"
  if [[ ! -d "$release_dir" ]]; then
    populate_distro_release "$distro_ver" >&2
  fi
  while IFS= read -r f || [[ -n "$f" ]]; do
    [[ -n "$f" ]] || continue
    printf '%s\n' "$f"
  done < <(find "$release_dir" -maxdepth 1 -type f ! -name MANIFEST.txt | sort)
}

DISTRO_RELEASE_NOTES_FILENAME="RELEASE.md"

distro_release_notes_path() {
  printf '%s/%s' "$1" "$DISTRO_RELEASE_NOTES_FILENAME"
}

# Which tag the notes describe for a release tree key. Prints: "<ver> <preview>"
distro_release_notes_args() {
  local tree_key=$1
  local ver preview=1
  if ver="$(normalize_version "$tree_key" 2>/dev/null)"; then
    if is_published_distro_tag "$ver" 2>/dev/null; then
      preview=0
    fi
    printf '%s %s\n' "$ver" "$preview"
    return 0
  fi
  ver="$(propose_next_distro_version 2>/dev/null || true)"
  [[ -n "$ver" ]] || return 1
  printf '%s %s\n' "$ver" "1"
}

# Write generated GitHub notes to dest_dir/RELEASE.md. Prints the path.
write_distro_release_notes() {
  local distro_ver=$1 dest_dir=$2 preview=${3:-0}
  local path
  distro_ver="$(normalize_version "$distro_ver")"
  path="$(distro_release_notes_path "$dest_dir")"
  mkdir -p "$dest_dir"
  release_notes_for_distro "$distro_ver" "$preview" >"$path"
  printf '%s\n' "$path"
}

release_notes_for_distro() {
  local distro_ver=$1 preview=${2:-0}
  local firmware_ver bootloader_ver motatool_ver peaky_ver mcmt_ver envybot_ver published changelog_body

  distro_ver="$(normalize_version "$distro_ver")"

  if ((preview == 1)); then
    firmware_ver="$(read_firmware_version)"
    bootloader_ver="$(read_bootloader_version)"
    motatool_ver="$(read_motatool_version)"
    published="$(date '+%Y-%m-%d')"
  else
    firmware_ver="$(manifest_package_version firmware "$distro_ver")"
    bootloader_ver="$(manifest_package_version bootloader "$distro_ver")"
    motatool_ver="$(manifest_package_version motatool "$distro_ver")"
    published="$(read_release_manifest_key "$distro_ver" published 2>/dev/null || date '+%Y-%m-%d')"
  fi

  cat <<EOF
EnvyOS distro release **${distro_ver}** (${published}).

| Package | Version |
|---------|---------|
EOF
  printf '| %s | %s |\n' "$(package_notes_link firmware)" "$firmware_ver"
  printf '| %s | %s |\n' "$(package_notes_link adafruit-nrf52-bootloader)" "$bootloader_ver"
  printf '| %s | %s |\n' "$(package_notes_link motatool)" "$motatool_ver"
  if package_in_distro_bundle mcmt-gateway "$distro_ver"; then
    if ((preview == 1)); then
      mcmt_ver="$(read_mcmt_gateway_version)"
    else
      mcmt_ver="$(manifest_package_version mcmt-gateway "$distro_ver")"
    fi
    printf '| %s | %s |\n' "$(package_notes_link mcmt-gateway)" "$mcmt_ver"
  fi
  if package_in_distro_bundle peaky "$distro_ver"; then
    if ((preview == 1)); then
      peaky_ver="$(read_peaky_version)"
    else
      peaky_ver="$(manifest_package_version peaky "$distro_ver")"
    fi
    printf '| %s | %s |\n' "$(package_notes_link peaky)" "$peaky_ver"
  fi
  if package_in_distro_bundle envybot "$distro_ver"; then
    if ((preview == 1)); then
      envybot_ver="$(read_envybot_version)"
    else
      envybot_ver="$(manifest_package_version envybot "$distro_ver")"
    fi
    printf '| %s | %s |\n' "$(package_notes_link envybot)" "$envybot_ver"
  fi

  if changelog_body="$(changelog_body_for_distro_release "$distro_ver" 2>/dev/null)"; then
    cat <<EOF

### Changes

${changelog_body}
EOF
  fi

  cat <<EOF

### Assets

- \`RELEASE.md\` — these notes (same text as the GitHub Release description)
- \`envyos-<ver>-full.tgz\` — **complete offline bundle** (all firmware variants, bootloader, motatool platforms, optional peaky/mcmt/envybot; uncompressed bench tree + manifests)
- \`meshcore-<slug>-<ver>-full-<id>.mota.gz\` / \`meshcore-<slug>-<ver>-delta-from-<base>-<id>.mota.gz\` — fleet OTA (pick one per node)
- \`meshcore-<slug>-<ver>.uf2.gz\` — bench UF2 flash
- \`adafruit-nrf52-bootloader-<board>-<ver>.uf2.gz\` / \`adafruit-nrf52-bootloader-<board>-recovery-<ver>.zip\` — Adafruit nRF52 bootloader per board
- \`motatool-<ver>-<platform>.tar.gz\` — bench motatool (pick your OS/arch)
EOF
  if package_in_distro_bundle mcmt-gateway "$distro_ver"; then
    if ((preview == 1)); then
      mcmt_ver="$(read_mcmt_gateway_version)"
    else
      mcmt_ver="$(manifest_package_version mcmt-gateway "$distro_ver")"
    fi
    printf -- '- \`mcmt_gateway-%s-py3-none-any.whl\` — Meshtastic ↔ MeshCore bridge (`uv tool install`)\n' "${mcmt_ver#v}"
  fi
  if package_in_distro_bundle peaky "$distro_ver"; then
    if ((preview == 1)); then
      peaky_ver="$(read_peaky_version)"
    else
      peaky_ver="$(manifest_package_version peaky "$distro_ver")"
    fi
    printf -- '- \`peaky-%s-<platform>.tar.gz\` — Peaky Finders \`peaky serve\` (pick Linux or macOS archive)\n' "${peaky_ver#v}"
  fi
  if package_in_distro_bundle envybot "$distro_ver"; then
    if ((preview == 1)); then
      envybot_ver="$(read_envybot_version)"
    else
      envybot_ver="$(manifest_package_version envybot "$distro_ver")"
    fi
    printf -- '- \`envybot-%s-py3-none-any.whl\` — fleet CLI (\`uv tool install\`)\n' "${envybot_ver#v}"
  fi

  cat <<EOF

Restore released trees with \`./envyos restore\`.
EOF
}

create_release_zip() {
  create_package_zip firmware "$1"
}

release_zip_path() {
  package_zip_path firmware "$1"
}

publish_github_release() {
  local distro_ver=$1
  shift
  local assets=("$@")
  local repo notes_file asset found=0

  command -v gh >/dev/null 2>&1 || {
    echo "warning: gh not installed — skipping GitHub release" >&2
    return 0
  }

  repo="$(github_repo)" || {
    echo "warning: could not resolve GitHub repo — skipping release" >&2
    return 0
  }

  notes_file=""
  for asset in "${assets[@]}"; do
    if [[ "$(basename "$asset")" == "$DISTRO_RELEASE_NOTES_FILENAME" && -f "$asset" ]]; then
      notes_file="$asset"
      found=1
      break
    fi
  done
  if ((found == 0)); then
    notes_file="$(write_distro_release_notes "$distro_ver" "$(distro_release_root "$distro_ver")" 0)"
    assets+=("$notes_file")
  fi

  ((${#assets[@]} > 0)) || {
    echo "error: no release assets to upload" >&2
    return 1
  }

  for asset in "${assets[@]}"; do
    [[ -f "$asset" ]] || {
      echo "error: release asset not found: $asset" >&2
      return 1
    }
  done

  if gh release view "$distro_ver" -R "$repo" >/dev/null 2>&1; then
    echo "github:   release $distro_ver exists — uploading assets + notes"
    gh release upload "$distro_ver" "${assets[@]}" -R "$repo" --clobber
    gh release edit "$distro_ver" -R "$repo" --notes-file "$notes_file"
  else
    ensure_git_tag_on_remote "$distro_ver"
    echo "github:   creating release $distro_ver"
    gh release create "$distro_ver" "${assets[@]}" -R "$repo" \
      --title "EnvyOS ${distro_ver}" \
      --notes-file "$notes_file"
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
