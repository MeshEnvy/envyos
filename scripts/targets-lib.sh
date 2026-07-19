#!/usr/bin/env bash
# Shared helpers for scripts/targets.txt (sourced, not executed).

# Map a PlatformIO env name to an otafix BOARD= value (nRF52 hardware profile).
# Extend when EnvyOS adds another nRF52840 family to targets.txt.
otafix_board_for_env() {
  local env=$1
  case "$env" in
    RAK_4631_*)
      echo wiscore_rak4631_board
      ;;
    RAK_WisMesh_Tag_*)
      echo wismesh_tag
      ;;
    *)
      echo "error: no otafix board mapping for PlatformIO env: $env" >&2
      echo "       add a case to otafix_board_for_env() in scripts/targets-lib.sh" >&2
      return 1
      ;;
  esac
}

# Print unique otafix board names required by targets.txt (one per line, sorted).
otafix_boards_from_targets_file() {
  local file=$1
  [[ -f "$file" ]] || {
    echo "error: targets file not found: $file" >&2
    return 1
  }

  local line env board
  local -a boards=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue

    read -r _ env _ <<<"$line"
    [[ -n "$env" ]] || continue

    board="$(otafix_board_for_env "$env")" || return 1

    local seen=0 b
    for b in "${boards[@]:-}"; do
      [[ "$b" == "$board" ]] && seen=1 && break
    done
    ((seen == 0)) && boards+=("$board")
  done <"$file"

  ((${#boards[@]} > 0)) || {
    echo "error: no targets in $file" >&2
    return 1
  }

  printf '%s\n' "${boards[@]}" | sort -u
}
