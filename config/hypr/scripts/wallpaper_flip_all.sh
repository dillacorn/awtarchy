#!/usr/bin/env bash
# ~/.config/hypr/scripts/wallpaper_flip_all.sh
set -euo pipefail

WALL_DIR="${WALL_DIR:-$HOME/Pictures/wallpapers}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper_flip"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/wallpaper_flip_all.lock"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

ensure_swww() {
  if swww query >/dev/null 2>&1; then
    return 0
  fi

  swww init >/dev/null 2>&1 || true

  for _ in {1..40}; do
    swww query >/dev/null 2>&1 && return 0
    sleep 0.05
  done

  die "swww daemon not running (try: swww init)"
}

read_wallpapers() {
  [[ -d "$WALL_DIR" ]] || die "wallpaper directory not found: $WALL_DIR"

  local -a arr=()
  while IFS= read -r -d '' f; do
    arr+=("$f")
  done < <(
    find "$WALL_DIR" -maxdepth 1 -type f \( \
      -iname '*.png'  -o -iname '*.jpg'  -o -iname '*.jpeg' -o -iname '*.webp' -o \
      -iname '*.gif'  -o -iname '*.avif' -o -iname '*.bmp'  -o -iname '*.tif'  -o \
      -iname '*.tiff' -o -iname '*.svg' \
    \) -print0 | LC_ALL=C sort -z
  )

  ((${#arr[@]} > 0)) || die "no wallpapers found in: $WALL_DIR"
  printf '%s\0' "${arr[@]}"
}

next_index() {
  local state_file="$1"
  local count="$2"
  local last="-1"

  if [[ -f "$state_file" ]]; then
    read -r last <"$state_file" || last="-1"
  fi
  [[ "$last" =~ ^-?[0-9]+$ ]] || last="-1"

  local next=$(( (last + 1) % count ))

  local tmp
  tmp="$(mktemp "${state_file}.tmp.XXXXXX")"
  printf '%s\n' "$next" >"$tmp"
  mv -f "$tmp" "$state_file"

  printf '%s\n' "$next"
}

main() {
  need_cmd swww
  need_cmd find
  need_cmd sort
  need_cmd flock

  exec 9>"$LOCK_FILE"
  flock -n 9 || exit 0

  mkdir -p "$STATE_DIR"

  local -a walls=()
  while IFS= read -r -d '' f; do
    walls+=("$f")
  done < <(read_wallpapers)

  local idx_file="${STATE_DIR}/index.all"
  local idx
  idx="$(next_index "$idx_file" "${#walls[@]}")"

  ensure_swww

  # No --outputs means: apply to all outputs.
  swww img \
    --transition-type fade \
    --transition-duration 0.35 \
    --transition-fps 60 \
    "${walls[$idx]}"
}

main "$@"
