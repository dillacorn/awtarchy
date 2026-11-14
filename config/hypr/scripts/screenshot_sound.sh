#!/usr/bin/env bash
# One preference store and one shutter sound for Hyprland and Sway.
set -euo pipefail

usage() {
    printf 'Usage: screenshot_sound.sh get | set enabled|direct|satty|print true|false | play direct|satty|print\n' >&2
    return 2
}

[[ $# -ge 1 ]] || { usage; exit 2; }
action="$1"
case "$action" in
    get) [[ $# -eq 1 ]] || { usage; exit 2; } ;;
    set)
        [[ $# -eq 3 ]] || { usage; exit 2; }
        case "$2" in enabled|direct|satty|print) ;; *) usage; exit 2 ;; esac
        case "$3" in true|false) ;; *) usage; exit 2 ;; esac
        ;;
    play)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        case "$2" in direct|satty|print) ;; *) usage; exit 2 ;; esac
        ;;
    *) usage; exit 2 ;;
esac

state_home="$HOME/.local/state"
if [[ -v XDG_STATE_HOME && -n "$XDG_STATE_HOME" ]]; then
    state_home="$XDG_STATE_HOME"
fi
state_dir="$state_home/awtarchy"
state_file="$state_dir/screenshot-sound.conf"
enabled=true
direct=true
satty=true
print=true

load_preferences() {
    [[ ! -L "$state_home" && ! -L "$state_dir" && ! -L "$state_file" ]] || {
        printf 'Unsafe screenshot sound state path\n' >&2
        return 1
    }
    [[ -e "$state_file" ]] || return 0
    [[ -f "$state_file" && -O "$state_file" ]] || {
        printf 'Unsafe screenshot sound state file\n' >&2
        return 1
    }
    local key value
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in enabled|direct|satty|print)
            case "$value" in
                true|false) printf -v "$key" '%s' "$value" ;;
                *) printf 'Invalid screenshot sound state value\n' >&2; return 1 ;;
            esac ;;
        *) printf 'Invalid screenshot sound state entry\n' >&2; return 1 ;;
        esac
    done < "$state_file"
}

if [[ "$action" == set ]]; then
    umask 077
    [[ ! -L "$state_home" && ! -L "$state_dir" ]] || {
        printf 'Unsafe screenshot sound directory\n' >&2; exit 1;
    }
    mkdir -p -- "$state_dir"
    [[ -d "$state_dir" && ! -L "$state_dir" && -O "$state_dir" ]] || exit 1
    lock="$state_dir/screenshot-sound.lock"
    [[ ! -L "$lock" && ( ! -e "$lock" || ( -f "$lock" && -O "$lock" ) ) ]] || exit 1
    exec 8>"$lock"
    flock 8
    load_preferences
    printf -v "$2" '%s' "$3"
    temp="$(mktemp "$state_dir/.screenshot-sound-XXXXXXXX")"
    trap 'if [[ -n "$temp" ]]; then rm -f -- "$temp"; fi' EXIT
    printf 'enabled=%s\ndirect=%s\nsatty=%s\nprint=%s\n' \
        "$enabled" "$direct" "$satty" "$print" > "$temp"
    mv -fT -- "$temp" "$state_file"
    temp=""
    exit 0
fi

if ! load_preferences; then
    # Invalid state must not silently turn muted sounds on.
    [[ "$action" == play ]] && exit 0
    exit 1
fi
if [[ "$action" == get ]]; then
    printf '{"enabled":%s,"direct":%s,"satty":%s,"print":%s}\n' \
        "$enabled" "$direct" "$satty" "$print"
    exit 0
fi

[[ "$enabled" == true ]] || exit 0
case "$2" in
    direct) [[ "$direct" == true ]] || exit 0 ;;
    satty) [[ "$satty" == true ]] || exit 0 ;;
    print) [[ "$print" == true ]] || exit 0 ;;
esac
command -v pw-play >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# Exact user-selected 180ms "Classic: tighter double-click" at 80% volume.
# Fully detached playback cannot delay captures or inherit compositor locks.
(
    python3 -c '
import math
import random
import struct
import sys

rate = 48000
rng = random.Random(2026)

def burst(t, start, duration, strength, decay=6):
    x = (t - start) / duration
    if not 0 <= x < 1:
        return 0.0
    return strength * math.exp(-decay * x)

def tone(t, start, duration, frequency, strength):
    x = (t - start) / duration
    if not 0 <= x < 1:
        return 0.0
    envelope = math.sin(math.pi * x) ** 2
    return strength * envelope * math.sin(
        2 * math.pi * frequency * (t - start)
    )

samples = []
for i in range(int(rate * 0.18)):
    t = i / rate
    noise = rng.uniform(-1, 1)
    value = noise * (
        burst(t, 0.005, 0.042, 1.0) +
        burst(t, 0.064, 0.058, 1.0)
    )
    value += tone(t, 0.006, 0.049, 170, 0.45)
    samples.append(value)

peak = max(abs(s) for s in samples) or 1.0
pcm = bytearray()
for value in samples:
    sample = max(-32768, min(32767, int(value / peak * 28000)))
    pcm.extend(struct.pack("<h", sample))
sys.stdout.buffer.write(pcm)
' | pw-play --raw --format=s16 --rate=48000 --channels=1 \
    --volume=0.80 --latency=20ms - >/dev/null 2>&1
) 8>&- 9>&- </dev/null >/dev/null 2>&1 &
