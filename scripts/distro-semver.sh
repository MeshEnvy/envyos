#!/usr/bin/env bash
# Distro semver suggestions from CHANGELOG + bundle membership (sourced by version.sh).
set -euo pipefail

CHANGELOG_FILE="${CHANGELOG_FILE:-$OTA_ROOT/CHANGELOG.md}"

latest_released_distro_from_registry() {
  local ver last=""
  while IFS= read -r ver || [[ -n "$ver" ]]; do
    [[ -n "$ver" ]] || continue
    last="$ver"
  done < <(list_released_distros)
  [[ -n "$last" ]] && printf '%s' "$last"
}

bundle_ids_sorted() {
  local probe=${1:-v0.0.0}
  list_release_component_ids "$probe" | sort
}

manifest_bundle_ids() {
  local distro_ver=$1 id
  distro_ver="$(normalize_version "$distro_ver")"
  while IFS= read -r id || [[ -n "$id" ]]; do
    [[ -n "$id" ]] || continue
    printf '%s\n' "$id"
  done < <(list_release_component_ids "$distro_ver")
}

changelog_section_body() {
  local heading=$1
  awk -v want="$heading" '
    BEGIN { capture = 0 }
    /^## \[/ {
      if (capture) exit
      line = $0
      sub(/^## \[/, "", line)
      sub(/\].*$/, "", line)
      if (line == want) capture = 1
      next
    }
    capture { print }
  ' "$CHANGELOG_FILE" 2>/dev/null
}

changelog_unreleased_body() {
  changelog_section_body "Unreleased"
}

changelog_has_pattern() {
  local pattern=$1 body
  body="$(changelog_unreleased_body)"
  [[ -n "$body" ]] || return 1
  grep -Eiq "$pattern" <<<"$body"
}

bundle_set_diff_level() {
  local last=$1
  local last_ids cur_ids id
  last_ids="$(manifest_bundle_ids "$last" | sort)"
  cur_ids="$(bundle_ids_sorted "$(read_distro_version 2>/dev/null || echo v0.0.0)")"

  while IFS= read -r id || [[ -n "$id" ]]; do
    [[ -n "$id" ]] || continue
    grep -qxF "$id" <<<"$cur_ids" || {
      printf '%s\n' major
      return 0
    }
  done <<<"$last_ids"

  while IFS= read -r id || [[ -n "$id" ]]; do
    [[ -n "$id" ]] || continue
    grep -qxF "$id" <<<"$last_ids" || {
      printf '%s\n' minor
      return 0
    }
  done <<<"$cur_ids"

  local key last_val cur_val
  for key in bootloader motatool mcmt-gateway peaky; do
    last_val="$(read_release_manifest_key "$last" "$key" 2>/dev/null || true)"
    cur_val=""
    case "$key" in
      bootloader) cur_val="$(read_bootloader_version 2>/dev/null || true)" ;;
      motatool) cur_val="$(read_motatool_version 2>/dev/null || true)" ;;
      mcmt-gateway) cur_val="$(read_optional_envyos_version_key mcmt-gateway 2>/dev/null || true)" ;;
      peaky) cur_val="$(read_optional_envyos_version_key peaky 2>/dev/null || true)" ;;
    esac
    [[ -n "$last_val" && -n "$cur_val" && "$last_val" != "$cur_val" ]] || continue
    grep -qxF "$key" <<<"$cur_ids" || continue
    printf '%s\n' minor
    return 0
  done

  return 1
}

suggest_distro_bump_level() {
  local last level

  if changelog_has_pattern '(^|[[:space:]])breaking|removed bundled|drop (peaky|mcmt|motatool|bootloader)'; then
    printf '%s\n' major
    return 0
  fi

  last="$(latest_released_distro_from_registry 2>/dev/null || true)"
  if [[ -n "$last" ]]; then
    if level="$(bundle_set_diff_level "$last")"; then
      printf '%s\n' "$level"
      return 0
    fi
  fi

  if changelog_has_pattern 'added (peaky|mcmt|mcmt-gateway|motatool|bootloader)|new board|new target|new platform'; then
    printf '%s\n' minor
    return 0
  fi

  if changelog_has_pattern '^### Added'; then
    printf '%s\n' minor
    return 0
  fi

  printf '%s\n' patch
}

propose_next_distro_version() {
  local level last major minor patch
  level="$(suggest_distro_bump_level)"
  last="$(latest_released_distro_from_registry 2>/dev/null || echo v0.0.0)"
  read -r major minor patch <<<"$(parse_version "$last")"
  case "$level" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *)
      echo "error: unknown bump level '$level'" >&2
      return 1
      ;;
  esac
  printf 'v%s.%s.%s' "$major" "$minor" "$patch"
}

print_distro_publish_recommendation() {
  local last level proposed
  last="$(latest_released_distro_from_registry 2>/dev/null || true)"
  level="$(suggest_distro_bump_level)"
  proposed="$(propose_next_distro_version)"
  echo "Last published:    ${last:-(none)}"
  echo "Changelog suggests: $level"
  echo "Proposed tag:      $proposed"
}

write_envyos_version_key() {
  local key=$1 val=$2
  val="${val#v}"
  python3 - "$ENVYOS_VERSIONS_FILE" "$key" "$val" <<'PY'
import sys

path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().splitlines()
out = []
found = False
for line in lines:
    raw = line
    body = line.split("#", 1)[0].strip()
    if not body:
        out.append(raw)
        continue
    k, _, _ = body.partition("=")
    if k.strip() == key:
        out.append(f"{key}={val}")
        found = True
    else:
        out.append(raw)
if not found:
    out.append(f"{key}={val}")
open(path, "w").write("\n".join(out) + "\n")
PY
}

set_distro_versions_for_publish() {
  local publish_ver=$1
  publish_ver="$(normalize_version "$publish_ver")"
  write_envyos_version_key distro "${publish_ver#v}"
  write_envyos_version_key firmware "${publish_ver#v}"
}
