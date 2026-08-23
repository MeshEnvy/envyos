#!/usr/bin/env bash
# Build and stage motatool for one or more platform targets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

MOTATOOL_DOCKER_IMAGE="${ENVYOS_MOTATOOL_DOCKER_IMAGE:-envyos-motatool-build}"
MOTATOOL_DOCKERFILE="$ROOT/docker/motatool-build/Dockerfile"

usage() {
  cat >&2 <<EOF
usage: $0 [--host-only] [--no-docker] [--target <platform>]…

  Build motatool release binaries staged under build/<distro>/bench/motatool/.

  (default)     All release platforms (linux via Docker; darwin native on macOS)
  --host-only   Current host platform only (native; fast bench path)
  --no-docker   Native cargo for linux targets too (needs host cross toolchain)
  --target      One platform (repeatable; overrides default)

  Release platforms:
    darwin-aarch64   darwin-x86_64   linux-aarch64   linux-x86_64

  Linux targets always use Docker by default (see docker/motatool-build/).
  Darwin targets require a macOS host.

examples:
  $0
  $0 --host-only
  $0 --target linux-x86_64
EOF
  exit 2
}

find_cargo() {
  local c
  if command -v rustup >/dev/null 2>&1; then
    c="$(rustup which cargo 2>/dev/null || true)"
    if [[ -n "$c" && -x "$c" ]] && "$c" --version >/dev/null 2>&1; then
      echo "$c"
      return
    fi
  fi
  c="$(ls -1d "$HOME"/.rustup/toolchains/stable-*/bin/cargo 2>/dev/null | head -1 || true)"
  if [[ -n "$c" && -x "$c" ]] && "$c" --version >/dev/null 2>&1; then
    echo "$c"
    return
  fi
  if command -v cargo >/dev/null 2>&1 && cargo --version 2>/dev/null | grep -q '^cargo '; then
    command -v cargo
    return
  fi
  echo "error: no working cargo (fix rustup: rustup which cargo)" >&2
  exit 1
}

ensure_cargo_target() {
  local triple=$1
  command -v rustup >/dev/null 2>&1 || return 0
  if rustup target list --installed | awk '{print $1}' | grep -qx "$triple"; then
    return 0
  fi
  echo "    rustup target add $triple" >&2
  rustup target add "$triple"
}

require_motatool_source() {
  [[ -d "$MOTATOOL_ROOT" ]] || {
    echo "error: motatool not found at $MOTATOOL_ROOT" >&2
    exit 1
  }
}

ensure_motatool_docker_image() {
  command -v docker >/dev/null 2>&1 || {
    echo "error: docker not found (install Docker to build linux motatool targets)" >&2
    exit 1
  }
  if docker image inspect "$MOTATOOL_DOCKER_IMAGE" >/dev/null 2>&1; then
    return 0
  fi
  echo "==> building $MOTATOOL_DOCKER_IMAGE"
  docker build -t "$MOTATOOL_DOCKER_IMAGE" -f "$MOTATOOL_DOCKERFILE" "$ROOT/docker/motatool-build"
}

stage_built_platform() {
  local platform=$1 mt_ver rel out
  platform="$(normalize_motatool_platform_slug "$platform")" || return 1
  mt_ver="$(read_motatool_version)"
  rel="$(motatool_cargo_release_path "$platform")"
  [[ -x "$rel" ]] || {
    echo "error: motatool build did not produce $rel" >&2
    exit 1
  }
  stage_motatool_binary "$rel" "$platform"
  out="$(motatool_staged_binary_path "$platform")"
  echo "    staged: $out"
}

build_motatool_platform_native() {
  local platform=$1 mt_ver cargo_bin cargo_dir triple host
  platform="$(normalize_motatool_platform_slug "$platform")" || return 1
  if [[ "$(motatool_platform_os "$platform")" == darwin && "$(uname -s)" != Darwin ]]; then
    echo "error: $platform requires a macOS host (Apple linker + SDK)" >&2
    exit 1
  fi
  mt_ver="$(read_motatool_version)"
  verify_motatool_version_sync "$mt_ver"
  require_motatool_source
  cargo_bin="$(find_cargo)"
  cargo_dir="$(dirname "$cargo_bin")"
  host="$(host_motatool_platform_slug)"
  echo "==> motatool $mt_ver ($platform, native)"
  if [[ "$platform" == "$host" ]]; then
    (cd "$MOTATOOL_ROOT" && PATH="$cargo_dir:$PATH" "$cargo_bin" build --release)
  else
    triple="$(motatool_platform_to_rust_triple "$platform")" || return 1
    ensure_cargo_target "$triple"
    (cd "$MOTATOOL_ROOT" && PATH="$cargo_dir:$PATH" "$cargo_bin" build --release --target "$triple")
  fi
  stage_built_platform "$platform"
}

build_motatool_linux_docker() {
  local -a platforms=("$@")
  local mt_ver triple cmd platform rel
  ((${#platforms[@]} > 0)) || return 0

  mt_ver="$(read_motatool_version)"
  verify_motatool_version_sync "$mt_ver"
  require_motatool_source
  ensure_motatool_docker_image

  cmd=""
  for platform in "${platforms[@]}"; do
    platform="$(normalize_motatool_platform_slug "$platform")" || return 1
    [[ "$(motatool_platform_os "$platform")" == linux ]] || {
      echo "error: internal: docker build called for non-linux platform $platform" >&2
      exit 1
    }
    triple="$(motatool_platform_to_rust_triple "$platform")" || return 1
    if [[ -n "$cmd" ]]; then
      cmd+=" && "
    fi
    cmd+="cargo build --release --target $triple"
  done

  echo "==> motatool $mt_ver (linux: ${platforms[*]}, docker)"
  docker run --rm \
    -v "$MOTATOOL_ROOT:/src" \
    -w /src \
    "$MOTATOOL_DOCKER_IMAGE" \
    sh -c "$cmd"

  for platform in "${platforms[@]}"; do
    stage_built_platform "$platform"
  done
}

HOST_ONLY=0
NO_DOCKER=0
PLATFORMS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-only)
      HOST_ONLY=1
      shift
      ;;
    --no-docker)
      NO_DOCKER=1
      shift
      ;;
    --target)
      [[ $# -ge 2 ]] || usage
      PLATFORMS+=("$2")
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

if ((${#PLATFORMS[@]} > 0)); then
  :
elif ((HOST_ONLY == 1)); then
  PLATFORMS=("$(host_motatool_platform_slug)")
else
  while IFS= read -r platform || [[ -n "$platform" ]]; do
    [[ -n "$platform" ]] || continue
    PLATFORMS+=("$platform")
  done < <(list_motatool_release_platforms)
fi

LINUX_PLATFORMS=()
DARWIN_PLATFORMS=()
for platform in "${PLATFORMS[@]}"; do
  platform="$(normalize_motatool_platform_slug "$platform")" || exit 1
  case "$(motatool_platform_os "$platform")" in
    linux) LINUX_PLATFORMS+=("$platform") ;;
    darwin) DARWIN_PLATFORMS+=("$platform") ;;
  esac
done

if ((${#DARWIN_PLATFORMS[@]} > 0)) && [[ "$(uname -s)" != Darwin ]]; then
  if ((${#LINUX_PLATFORMS[@]} == 0)); then
    echo "error: darwin motatool targets require a macOS host" >&2
    exit 1
  fi
  echo "note: skipping darwin targets on non-macOS host (${DARWIN_PLATFORMS[*]})" >&2
  DARWIN_PLATFORMS=()
fi

distro_ver="$(read_distro_version)"
mt_bench="$(motatool_bench_root "$distro_ver")"
echo "==> motatool bench: clean $mt_bench"
rm -rf "$mt_bench"
mkdir -p "$mt_bench"

if ((${#LINUX_PLATFORMS[@]} > 0)); then
  if ((NO_DOCKER == 1 || HOST_ONLY == 1)); then
    for platform in "${LINUX_PLATFORMS[@]}"; do
      build_motatool_platform_native "$platform"
    done
  else
    build_motatool_linux_docker "${LINUX_PLATFORMS[@]}"
  fi
fi

if ((${#DARWIN_PLATFORMS[@]} > 0)); then
  for platform in "${DARWIN_PLATFORMS[@]}"; do
    build_motatool_platform_native "$platform"
  done
fi

maybe_populate_distro_release
