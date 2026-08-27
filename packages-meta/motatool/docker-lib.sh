#!/usr/bin/env bash
# Shared Docker volume mounts for Rust cross-builds (EnvyOS package harness).
set -euo pipefail

# Host dirs for global crate caches (shared across projects and targets).
# Override with ENVYOS_DOCKER_CARGO_REGISTRY / ENVYOS_DOCKER_CARGO_GIT when needed.
docker_cargo_registry_dir() {
  if [[ -n "${ENVYOS_DOCKER_CARGO_REGISTRY:-}" ]]; then
    printf '%s' "$ENVYOS_DOCKER_CARGO_REGISTRY"
    return 0
  fi
  local home="${CARGO_HOME:-$HOME/.cargo}"
  printf '%s/registry' "$home"
}

docker_cargo_git_dir() {
  if [[ -n "${ENVYOS_DOCKER_CARGO_GIT:-}" ]]; then
    printf '%s' "$ENVYOS_DOCKER_CARGO_GIT"
    return 0
  fi
  local home="${CARGO_HOME:-$HOME/.cargo}"
  printf '%s/git' "$home"
}

# Container paths (rust:* official images use /usr/local/cargo).
docker_container_cargo_home() {
  printf '%s' "${ENVYOS_DOCKER_CONTAINER_CARGO_HOME:-/usr/local/cargo}"
}

# Run docker with host registry + git caches mounted (remaining args passed to docker run).
docker_run_with_rust_cache() {
  local registry git cargo_home
  registry="$(docker_cargo_registry_dir)"
  git="$(docker_cargo_git_dir)"
  cargo_home="$(docker_container_cargo_home)"
  mkdir -p "$registry" "$git"
  docker run \
    -v "$registry:$cargo_home/registry" \
    -v "$git:$cargo_home/git" \
    "$@"
}

# Print docker -v lines: registry + git (one flag pair per line). Ensures host dirs exist.
docker_rust_cache_mounts() {
  local registry git cargo_home
  registry="$(docker_cargo_registry_dir)"
  git="$(docker_cargo_git_dir)"
  cargo_home="$(docker_container_cargo_home)"
  mkdir -p "$registry" "$git"
  printf '%s\n' \
    "-v" "$registry:$cargo_home/registry" \
    "-v" "$git:$cargo_home/git"
}
