#!/usr/bin/env bash
# Rename historical .mota files to apply-identity names.
# Bytes unchanged. Default is dry-run.
#
#   ./scripts/rename-motas.sh              # dry-run local build/
#   ./scripts/rename-motas.sh --apply
#   ./scripts/rename-motas.sh --apply --github
#
# Needs motatool with `name` (this tree). Override: MOTATOOL=/path/to/motatool

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
unset MANIFEST_JSON MANIFEST_PY OTA_ROOT MESHCORE_ROOT BOOTLOADER_SRC MOTATOOL_ROOT 2>/dev/null || true
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

APPLY=0
GITHUB=0
SCAN_ROOT="$ROOT/build"

usage() {
  cat >&2 <<EOF
usage: $0 [--apply] [--github] [--dir DIR]

  --apply    Rename (default is dry-run)
  --github   Rewrite *.mota / *.mota.gz on published GitHub releases
  --dir DIR  Local tree to walk (default: $SCAN_ROOT)
EOF
  exit 2
}

while (($#)); do
  case "$1" in
    --apply) APPLY=1 ;;
    --github) GITHUB=1 ;;
    --dir)
      [[ -n "${2:-}" ]] || usage
      SCAN_ROOT="$2"
      shift
      ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
  shift
done

resolve_motatool_name() {
  if [[ -n "${MOTATOOL:-}" && -x "${MOTATOOL}" ]]; then
    printf '%s' "$MOTATOOL"
    return 0
  fi
  local try
  if try="$(resolve_motatool_bin "$(read_optional_manifest_key motatool 2>/dev/null || true)" 2>/dev/null)"; then
    if "$try" name --help >/dev/null 2>&1; then
      printf '%s' "$try"
      return 0
    fi
  fi
  if [[ -x "$MOTATOOL_ROOT/target/release/motatool" ]]; then
    printf '%s' "$MOTATOOL_ROOT/target/release/motatool"
    return 0
  fi
  if [[ -x "$MOTATOOL_ROOT/target/debug/motatool" ]]; then
    printf '%s' "$MOTATOOL_ROOT/target/debug/motatool"
    return 0
  fi
  echo "error: motatool with \`name\` not found — cargo build -p motatool or MOTATOOL=" >&2
  return 1
}

SLUGS=()
load_slugs() {
  local line slug
  SLUGS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue
    read -r slug _ <<<"$line"
    SLUGS+=("$slug")
  done <"$ROOT/scripts/targets.txt"
  local extra
  for extra in rak4631-repeater rak4631-client-ble sensecap-p1pro-repeater-slim; do
    SLUGS+=("$extra")
  done
  # longest first so rak4631-repeater-slim wins over a shorter prefix
  local i j tmp
  for ((i = 0; i < ${#SLUGS[@]}; i++)); do
    for ((j = i + 1; j < ${#SLUGS[@]}; j++)); do
      if ((${#SLUGS[j]} > ${#SLUGS[i]})); then
        tmp="${SLUGS[i]}"
        SLUGS[i]="${SLUGS[j]}"
        SLUGS[j]="$tmp"
      fi
    done
  done
}

is_ver_label() {
  [[ "${1#v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-ev[0-9]+)?$ ]]
}

infer_slug_from_path() {
  local path="$1" d b slug
  d="$(dirname "$path")"
  while [[ -n "$d" && "$d" != "/" && "$d" != "." ]]; do
    b="$(basename "$d")"
    for slug in "${SLUGS[@]}"; do
      if [[ "$b" == "$slug" ]]; then
        printf '%s' "$slug"
        return 0
      fi
    done
    d="$(dirname "$d")"
  done
  return 1
}

infer_ver_from_path() {
  local path="$1"
  if [[ "$path" =~ /meshcore-([0-9]+\.[0-9]+\.[0-9]+-ev[0-9]+)/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$path" =~ /meshcore-v?([0-9]+\.[0-9]+\.[0-9]+)/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$path" =~ /firmware-v?([0-9]+\.[0-9]+\.[0-9]+)/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$path" =~ /v([0-9]+\.[0-9]+\.[0-9]+)/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# Sets PARSE_SLUG PARSE_VER. $1 = basename, $2 = full path (optional), $3 = ver fallback.
parse_mota_basename() {
  local base="$1" path="${2:-}" fallback="${3:-}" prefix rest slug
  PARSE_SLUG=""
  PARSE_VER=""
  for slug in "${SLUGS[@]}"; do
    for prefix in fw- meshcore-; do
      rest="${base#"${prefix}${slug}-"}"
      if [[ "$rest" == "$base" ]]; then
        continue
      fi
      if [[ "$rest" == *-full-* ]]; then
        PARSE_VER="${rest%%-full-*}"
      elif [[ "$rest" == *-delta-from-* ]]; then
        PARSE_VER="${rest%%-delta-from-*}"
      elif [[ "$rest" == *-delta-* ]]; then
        PARSE_VER="${rest%%-delta-*}"
      elif [[ "$rest" == full-* ]]; then
        PARSE_VER="${rest#full-}"
        PARSE_VER="${PARSE_VER%.mota}"
      elif [[ "$rest" == delta-from-* || "$rest" == delta_from_* ]]; then
        PARSE_VER=""
      else
        continue
      fi
      PARSE_SLUG="$slug"
      break 2
    done
  done
  if [[ -z "$PARSE_SLUG" && -n "$path" ]]; then
    PARSE_SLUG="$(infer_slug_from_path "$path" || true)"
  fi
  if { [[ -z "$PARSE_VER" ]] || ! is_ver_label "$PARSE_VER"; } && [[ -n "$path" ]]; then
    PARSE_VER="$(infer_ver_from_path "$path" || true)"
  fi
  if { [[ -z "$PARSE_VER" ]] || ! is_ver_label "$PARSE_VER"; } && [[ -n "$fallback" ]]; then
    PARSE_VER="${fallback#v}"
  fi
  [[ -n "$PARSE_SLUG" && -n "$PARSE_VER" ]] && is_ver_label "$PARSE_VER"
}

look_fw_in_dir() {
  local dir="$1" slug="$2" ver="$3"
  local p mota tmp
  [[ -d "$dir" ]] || return 1
  local vlabel
  vlabel="$(firmware_artifact_ver_label "$ver")"
  for p in \
    "$dir/$(firmware_artifact_name "$slug" "$ver" hex)" \
    "$dir/$(firmware_artifact_name "$slug" "$ver" bin)" \
    "$dir/fw-${slug}-${vlabel}.hex" \
    "$dir/fw-${slug}-${vlabel}.bin" \
    "$dir/fw-${slug}-v${vlabel}.hex" \
    "$dir/fw-${slug}-v${vlabel}.bin" \
    "$dir/meshcore-${slug}-v${vlabel}.hex" \
    "$dir/meshcore-${slug}-v${vlabel}.bin" \
    "$dir/firmware.hex" \
    "$dir/firmware.bin"; do
    if [[ -f "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  shopt -s nullglob
  for mota in \
    "$dir"/fw-"${slug}"-"${ver}"-full-*.mota \
    "$dir"/fw-"${slug}"-*-full-*.mota \
    "$dir"/fw-"${slug}"-full-*.mota \
    "$dir"/meshcore-"${slug}"-"${ver}"-full-*.mota \
    "$dir"/meshcore-"${slug}"-*-full-*.mota \
    "$dir"/*_full_*.mota \
    "$dir"/*-full-*.mota; do
    [[ -f "$mota" ]] || continue
    tmp="$(mktemp -t envyos-mota-fw.XXXXXX.bin)"
    if extract_full_mota_payload "$mota" "$tmp"; then
      printf '%s' "$tmp"
      shopt -u nullglob
      return 0
    fi
    rm -f "$tmp"
  done
  shopt -u nullglob
  return 1
}

resolve_target_fw() {
  local dir="$1" slug="$2" ver="$3"
  local cand vlabel slot
  if cand="$(look_fw_in_dir "$dir" "$slug" "$ver")"; then
    printf '%s' "$cand"
    return 0
  fi
  vlabel="$(firmware_artifact_ver_label "$ver")"
  for slot in \
    "$(firmware_slug_dir "$ver" "$ver" "$slug")" \
    "$(firmware_slug_dir "v${vlabel}" "$ver" "$slug")"; do
    if cand="$(look_fw_in_dir "$slot" "$slug" "$ver")"; then
      printf '%s' "$cand"
      return 0
    fi
  done
  # Historical + current-slot trees (release/ has no sibling hex).
  local hist
  shopt -s nullglob
  for hist in \
    "$BUILD_ROOT"/main/bench/meshcore-"${vlabel}"/"${slug}" \
    "$BUILD_ROOT"/v"${vlabel}"/bench/meshcore-"${vlabel}"/"${slug}" \
    "$BUILD_ROOT"/v"${vlabel}"/bench/meshcore-v"${vlabel}"/"${slug}" \
    "$BUILD_ROOT"/v"${vlabel}"/bench/firmware-v"${vlabel}"/"${slug}" \
    "$BUILD_ROOT"/"${vlabel}"/bench/meshcore-"${vlabel}"/"${slug}" \
    "$BUILD_ROOT"/*/bench/meshcore-"${vlabel}"/"${slug}" \
    "$BUILD_ROOT"/*/bench/meshcore-v"${vlabel}"/"${slug}" \
    "$BUILD_ROOT"/v"${vlabel}"/release/"${slug}"; do
    if cand="$(look_fw_in_dir "$hist" "$slug" "$ver")"; then
      shopt -u nullglob
      printf '%s' "$cand"
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

is_delta_mota() {
  local file="$1" b
  b="$(basename "$file")"
  b="${b%.gz}"
  [[ "$b" == *delta* ]]
}

rename_one_mota() {
  local mt="$1" src="$2" ver_fallback="${3:-}"
  local base dir stem new tmp_src tmp_fw unpacked gz=0
  tmp_fw=""
  unpacked=""

  base="$(basename "$src")"
  dir="$(dirname "$src")"
  if [[ "$base" == *.mota.gz ]]; then
    gz=1
    base="${base%.gz}"
    unpacked="$(mktemp -t envyos-mota.XXXXXX.mota)"
    gunzip -c "$src" >"$unpacked"
    tmp_src="$unpacked"
  else
    tmp_src="$src"
  fi

  if ! parse_mota_basename "$base" "$src" "$ver_fallback"; then
    echo "SKIP  (unparsed) $src" >&2
    [[ -n "$unpacked" ]] && rm -f "$unpacked"
    return 0
  fi

  stem="$(mota_name_stem "$PARSE_SLUG" "$PARSE_VER")"
  local name_args=("$mt" name "$tmp_src" --name-stem "$stem")
  # Use original basename (gz unpacks to a random temp name).
  if is_delta_mota "$base"; then
    if ! tmp_fw="$(resolve_target_fw "$dir" "$PARSE_SLUG" "$PARSE_VER")"; then
      echo "FAIL  (no target hex/full for $PARSE_SLUG $PARSE_VER) $src" >&2
      [[ -n "$unpacked" ]] && rm -f "$unpacked"
      return 1
    fi
    name_args+=(--fw "$tmp_fw")
  fi

  if ! new="$("${name_args[@]}")" || [[ -z "$new" ]]; then
    echo "FAIL  (name) $src" >&2
    [[ -n "$unpacked" ]] && rm -f "$unpacked"
    if [[ -n "$tmp_fw" && "$tmp_fw" != "$dir/"* ]]; then
      rm -f "$tmp_fw"
    fi
    return 1
  fi

  local dest_base="$new"
  if ((gz)); then
    dest_base="${new}.gz"
  fi
  local dest="$dir/$dest_base"

  if [[ "$(basename "$src")" == "$dest_base" ]]; then
    echo "OK    $src"
    [[ -n "$unpacked" ]] && rm -f "$unpacked"
    if [[ -n "$tmp_fw" && ! -f "$dir/$(basename "$tmp_fw")" ]]; then
      rm -f "$tmp_fw"
    fi
    return 0
  fi

  if ((APPLY == 0)); then
    echo "WOULD $src"
    echo "    → $dest"
  else
    if ((gz)); then
      gzip -cn9 "$unpacked" >"$dest"
      rm -f "$src"
    else
      mv -n "$src" "$dest"
    fi
    echo "MOVED $src"
    echo "    → $dest"
  fi

  [[ -n "$unpacked" ]] && rm -f "$unpacked"
  if [[ -n "$tmp_fw" && "$tmp_fw" != "$dir/"* ]]; then
    rm -f "$tmp_fw"
  fi
}

github_rewrite() {
  local mt="$1"
  local tag asset tmp dest newgz old
  local -a tags=()
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    tags+=("$tag")
  done < <(gh release list --repo MeshEnvy/envyos --limit 50 --json tagName -q '.[].tagName')

  for tag in "${tags[@]}"; do
    echo "==> GitHub $tag"
    while IFS= read -r asset; do
      [[ -n "$asset" ]] || continue
      [[ "$asset" == *.mota || "$asset" == *.mota.gz ]] || continue
      tmp="$(mktemp -d -t envyos-gh-mota.XXXXXX)"
      gh release download "$tag" --repo MeshEnvy/envyos -p "$asset" -D "$tmp"
      old="$tmp/$asset"
      if ! rename_one_mota "$mt" "$old" "$tag"; then
        rm -rf "$tmp"
        return 1
      fi
      dest="$(ls -1 "$tmp"/*.mota "$tmp"/*.mota.gz 2>/dev/null | head -n 1 || true)"
      if [[ -z "$dest" || "$(basename "$dest")" == "$asset" ]]; then
        rm -rf "$tmp"
        continue
      fi
      newgz="$(basename "$dest")"
      if ((APPLY == 0)); then
        echo "    WOULD upload $newgz and delete $asset"
        rm -rf "$tmp"
        continue
      fi
      if [[ "$newgz" != *.gz ]]; then
        gzip -cn9 "$dest" >"$tmp/${newgz}.gz"
        dest="$tmp/${newgz}.gz"
        newgz="${newgz}.gz"
      fi
      gh release upload "$tag" "$dest" --repo MeshEnvy/envyos --clobber
      gh release delete-asset "$tag" "$asset" --repo MeshEnvy/envyos --yes
      echo "    uploaded $newgz; deleted $asset"
      rm -rf "$tmp"
    done < <(gh release view "$tag" --repo MeshEnvy/envyos --json assets -q '.assets[].name')

    github_retar_tgz "$tag"
  done
}

# Re-upload local retarred tgz when the release already has one.
github_retar_tgz() {
  local tag="$1"
  local tgz="envyos-${tag#v}-full.tgz"
  local local_tgz="$BUILD_ROOT/${tag}/release/${tgz}"
  local names
  names="$(gh release view "$tag" --repo MeshEnvy/envyos --json assets -q '.assets[].name' || true)"
  if ! grep -qx "$tgz" <<<"$names"; then
    return 0
  fi
  if [[ ! -f "$local_tgz" ]]; then
    echo "    SKIP tgz (no $local_tgz)" >&2
    return 0
  fi
  if ((APPLY == 0)); then
    echo "    WOULD upload $local_tgz"
    return 0
  fi
  gh release upload "$tag" "$local_tgz" --repo MeshEnvy/envyos --clobber
  echo "    uploaded $tgz"
}

MT="$(resolve_motatool_name)"
if ! "$MT" name --help >/dev/null 2>&1; then
  echo "error: $MT has no \`name\` subcommand — rebuild motatool from this tree" >&2
  exit 1
fi
echo "motatool: $MT"
load_slugs

retar_local_tgz() {
  local mt="$1" tgz="$2"
  local tmp root inner ver failed_inner=0
  tmp="$(mktemp -d -t envyos-local-tgz.XXXXXX)"
  mkdir -p "$tmp/unpack"
  tar -xzf "$tgz" -C "$tmp/unpack"
  ver="$(basename "$tgz")"
  ver="${ver#envyos-}"
  ver="${ver%-full.tgz}"
  while IFS= read -r -d '' f; do
    if ! rename_one_mota "$mt" "$f" "$ver"; then
      failed_inner=1
    fi
  done < <(find "$tmp/unpack" \( -name '*.mota' -o -name '*.mota.gz' \) -type f -print0 | sort -z)
  if ((failed_inner)); then
    rm -rf "$tmp"
    return 1
  fi
  root="$(find "$tmp/unpack" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  inner="$(basename "$root")"
  if ((APPLY == 0)); then
    echo "WOULD retar $tgz"
    rm -rf "$tmp"
    return 0
  fi
  tar -czf "$tgz" --exclude='.DS_Store' -C "$tmp/unpack" "$inner"
  echo "RETAR $tgz"
  rm -rf "$tmp"
}

failed=0
if [[ -d "$SCAN_ROOT" ]]; then
  echo "==> local $SCAN_ROOT"
  while IFS= read -r -d '' f; do
    if ! rename_one_mota "$MT" "$f"; then
      failed=1
    fi
  done < <(find "$SCAN_ROOT" \( -name '*.mota' -o -name '*.mota.gz' \) -type f -print0 | sort -z)
  while IFS= read -r -d '' tgz; do
    if ! retar_local_tgz "$MT" "$tgz"; then
      failed=1
    fi
  done < <(find "$SCAN_ROOT" -name 'envyos-*-full.tgz' -type f -print0 | sort -z)
fi

if ((GITHUB)); then
  github_rewrite "$MT" || failed=1
fi

if ((failed)); then
  echo "rename-motas: some files failed" >&2
  exit 1
fi
if ((APPLY == 0)); then
  echo "dry-run only. Re-run with --apply to rename."
fi
