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
  local file=${2:-$CHANGELOG_FILE}
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
  ' "$file" 2>/dev/null
}

changelog_unreleased_body() {
  changelog_section_body "Unreleased" "${1:-$CHANGELOG_FILE}"
}

changelog_text_nonempty() {
  [[ -n "$(printf '%s' "${1:-}" | tr -d '[:space:]')" ]]
}

package_overlay_changelog_file() {
  local pkg=$1
  local fork="$PACKAGES_ROOT/$pkg/CHANGELOG.md"
  local meta="$PACKAGES_META_ROOT/$pkg/CHANGELOG.md"
  if [[ -f "$fork" ]]; then
    printf '%s' "$fork"
  elif [[ -f "$meta" ]]; then
    printf '%s' "$meta"
  fi
}

# Distro Unreleased (or matching tag) plus per-package overlay notes.
changelog_body_for_distro_release() {
  local distro_ver=$1
  local section file ver pkg out=""
  local heading

  distro_ver="$(normalize_version "$distro_ver")"
  heading="$distro_ver"
  section="$(changelog_section_body "$heading")"
  if ! changelog_text_nonempty "$section"; then
    heading="v${distro_ver}"
    section="$(changelog_section_body "$heading")"
  fi
  if ! changelog_text_nonempty "$section"; then
    section="$(changelog_unreleased_body)"
  fi
  if changelog_text_nonempty "$section"; then
    out+="#### Distro"$'\n\n'"${section}"$'\n'
  fi

  for pkg in meshcore bootloader motatool; do
    file="$(package_overlay_changelog_file "$pkg")"
    [[ -n "$file" ]] || continue
    ver="$(read_release_manifest_key "$distro_ver" "$pkg" 2>/dev/null || true)"
    if [[ -z "$ver" ]]; then
      ver="$(read_package_version "$pkg" 2>/dev/null || true)"
    fi
    section=""
    if [[ -n "$ver" ]]; then
      section="$(changelog_section_body "$ver" "$file")"
    fi
    if ! changelog_text_nonempty "$section"; then
      section="$(changelog_unreleased_body "$file")"
    fi
    if changelog_text_nonempty "$section"; then
      out+=$'\n'"#### ${pkg}"
      [[ -n "$ver" ]] && out+=" (${ver})"
      out+=$'\n\n'"${section}"$'\n'
    fi
  done

  changelog_text_nonempty "$out" || return 1
  printf '%s' "$out"
}

changelog_has_pattern() {
  local pattern=$1 body
  body="$(changelog_unreleased_body)"
  [[ -n "$body" ]] || return 1
  grep -Eiq "$pattern" <<<"$body"
}

component_pin_upstream() {
  local v="${1#v}"
  v="${v%-ev*}"
  printf '%s' "$v"
}

# patch | minor | major — compare upstream semver pins (ignores -evN overlay).
component_pin_bump_level() {
  local last=$1 cur=$2
  local last_m last_mi last_p cur_m cur_mi cur_p
  last="$(component_pin_upstream "$last")"
  cur="$(component_pin_upstream "$cur")"
  [[ "$last" == "$cur" ]] && return 1
  IFS=. read -r last_m last_mi last_p <<<"$last"
  IFS=. read -r cur_m cur_mi cur_p <<<"$cur"
  last_p="${last_p:-0}"
  cur_p="${cur_p:-0}"
  if [[ "$cur_m" -gt "$last_m" ]]; then
    printf '%s\n' major
  elif [[ "$cur_m" -lt "$last_m" ]]; then
    printf '%s\n' major
  elif [[ "$cur_mi" -gt "$last_mi" ]]; then
    printf '%s\n' minor
  elif [[ "$cur_mi" -lt "$last_mi" ]]; then
    printf '%s\n' minor
  else
    printf '%s\n' patch
  fi
}

# True when bench pins use upstream-evN but the last published manifest still used distro-coupled semver.
packaging_scheme_migration_pending() {
  local last=$1 last_motatool cur_motatool
  [[ -n "$last" ]] || return 1
  cur_motatool="$(read_motatool_version 2>/dev/null || true)"
  [[ "$cur_motatool" == *-ev* ]] || return 1
  last_motatool="$(read_release_manifest_key "$last" motatool 2>/dev/null || true)"
  [[ -n "$last_motatool" && "$last_motatool" != *-ev* ]]
}

bundle_set_diff_level() {
  local last=$1
  local last_ids cur_ids id
  local key last_val cur_val level max=""
  last_ids="$(manifest_bundle_ids "$last" | sort)"
  cur_ids="$(bundle_ids_sorted "$(propose_next_distro_version 2>/dev/null || latest_released_distro_version)")"

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

  for key in bootloader motatool mcmt-gateway peaky envybot; do
    last_val="$(read_release_manifest_key "$last" "$key" 2>/dev/null || true)"
    cur_val=""
    case "$key" in
      bootloader) cur_val="$(read_bootloader_version 2>/dev/null || true)" ;;
      motatool) cur_val="$(read_motatool_version 2>/dev/null || true)" ;;
      mcmt-gateway) cur_val="$(read_optional_manifest_key mcmt-gateway 2>/dev/null || true)" ;;
      peaky) cur_val="$(read_optional_manifest_key peaky 2>/dev/null || true)" ;;
      envybot) cur_val="$(read_optional_manifest_key envybot 2>/dev/null || true)" ;;
    esac
    [[ -n "$last_val" && -n "$cur_val" ]] || continue
    [[ "$last_val" == "$cur_val" ]] && continue
    level="$(component_pin_bump_level "$last_val" "$cur_val")" || continue
    case "$level" in
      major) printf '%s\n' major; return 0 ;;
      minor) max=minor ;;
      patch)
        [[ "$max" != minor ]] && max=patch
        ;;
    esac
  done

  [[ -n "$max" ]] && printf '%s\n' "$max" && return 0
  return 1
}

suggest_distro_bump_level() {
  local last level

  if changelog_has_pattern '(^|[[:space:]])breaking|removed bundled|drop (peaky|mcmt|motatool|bootloader|envybot)'; then
    printf '%s\n' major
    return 0
  fi

  last="$(latest_released_distro_from_registry 2>/dev/null || true)"
  if [[ -n "$last" ]] && packaging_scheme_migration_pending "$last"; then
    printf '%s\n' patch
    return 0
  fi
  if [[ -n "$last" ]]; then
    if level="$(bundle_set_diff_level "$last")"; then
      printf '%s\n' "$level"
      return 0
    fi
  fi

  if changelog_has_pattern 'added (peaky|mcmt|mcmt-gateway|motatool|bootloader|envybot)|new board|new target|new platform'; then
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

print_distro_bump_summary() {
  print_distro_publish_recommendation
}

# Full console dump for `./envyos publish --dry-run`: plan, pins, GitHub notes, staged files.
print_distro_publish_plan() {
  local distro_ver=$1
  local slot=$2
  local git_tag=${3:-1}
  local github_release=${4:-1}
  local preview=1
  local dir f count=0 last_dir=""

  distro_ver="$(normalize_version "$distro_ver")"
  if is_published_distro_tag "$distro_ver" 2>/dev/null; then
    preview=0
  fi

  echo "Publish plan (dry-run — no promote, lock, tag, or upload)"
  echo ""
  echo "Tag:            $distro_ver"
  echo "Build slot:     $slot"
  echo "Git tag:        $( ((git_tag)) && echo yes || echo no )"
  echo "GitHub release: $( ((github_release)) && echo yes || echo no )"
  echo ""
  print_distro_publish_recommendation
  echo ""
  echo "releases.next"
  list_manifest | sed 's/^/  /'
  echo ""
  echo "GitHub release notes"
  echo "--------------------"
  release_notes_for_distro "$distro_ver" "$preview"
  echo "--------------------"
  echo ""
  echo "Staged upload files (read-only)"
  for dir in "$(distro_release_root "$slot")" "$(distro_release_root "$distro_ver")"; do
    [[ -d "$dir" ]] || continue
    [[ "$dir" == "$last_dir" ]] && continue
    last_dir="$dir"
    echo "  $dir"
    while IFS= read -r f || [[ -n "$f" ]]; do
      [[ -n "$f" ]] || continue
      printf '    %s\n' "$(basename "$f")"
      count=$((count + 1))
    done < <(find "$dir" -maxdepth 1 -type f ! -name MANIFEST.txt | sort)
  done
  if ((count == 0)); then
    echo "  (none — run ./envyos build to populate build/${slot}/release/)"
  fi
}
