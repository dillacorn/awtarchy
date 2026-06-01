#!/usr/bin/env bash
set -u

MODE="do-not-disturb"
SIGNAL="14"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
MAKO_DIR="$CONFIG_HOME/mako"
MAKO_CONFIG="$MAKO_DIR/config"

notify_waybar() {
  pkill -RTMIN+"$SIGNAL" waybar 2>/dev/null || true
}

mako_running() {
  pgrep -x mako >/dev/null 2>&1
}

has_mode() {
  makoctl mode 2>/dev/null | tr ' ' '\n' | grep -Fxq "$MODE"
}

ensure_mako_dnd_rule() {
  mkdir -p "$MAKO_DIR"
  touch "$MAKO_CONFIG"

  if awk '
    /^\[mode=do-not-disturb\]$/ { in_section=1; found_section=1; next }
    /^\[/ { in_section=0 }
    in_section && /^invisible=1$/ { found_rule=1 }
    END { exit !(found_section && found_rule) }
  ' "$MAKO_CONFIG"; then
    return 0
  fi

  tmp="$(mktemp "${MAKO_CONFIG}.tmp.XXXXXX")" || return 1

  awk '
    BEGIN {
      in_section=0
      seen_section=0
      inserted=0
    }

    /^\[mode=do-not-disturb\]$/ {
      in_section=1
      seen_section=1
      print
      next
    }

    /^\[/ {
      if (in_section && !inserted) {
        print "invisible=1"
        inserted=1
      }
      in_section=0
      print
      next
    }

    {
      print
    }

    END {
      if (seen_section && in_section && !inserted) {
        print "invisible=1"
      }

      if (!seen_section) {
        print ""
        print "[mode=do-not-disturb]"
        print "invisible=1"
      }
    }
  ' "$MAKO_CONFIG" > "$tmp" && mv "$tmp" "$MAKO_CONFIG"

  makoctl reload >/dev/null 2>&1 || true
}

print_json() {
  if ! command -v makoctl >/dev/null 2>&1; then
    printf '{"text":"","class":"error","tooltip":"makoctl not found"}\n'
    exit 0
  fi

  if ! mako_running; then
    printf '{"text":"","class":"error","tooltip":"mako is not running"}\n'
    exit 0
  fi

  if has_mode; then
    printf '{"text":"","class":"muted","tooltip":"Notifications disabled\\nLeft: enable notifications"}\n'
  else
    printf '{"text":"","class":"normal","tooltip":"Notifications enabled\\nLeft: disable notifications"}\n'
  fi
}

case "${1:-status}" in
  toggle)
    ensure_mako_dnd_rule

    if has_mode; then
      makoctl mode -r "$MODE" >/dev/null 2>&1 || true
    else
      makoctl dismiss -a >/dev/null 2>&1 || true
      makoctl mode -a "$MODE" >/dev/null 2>&1 || true
    fi

    notify_waybar
    ;;

  on|enable)
    makoctl mode -r "$MODE" >/dev/null 2>&1 || true
    notify_waybar
    ;;

  off|disable)
    ensure_mako_dnd_rule
    makoctl dismiss -a >/dev/null 2>&1 || true
    makoctl mode -a "$MODE" >/dev/null 2>&1 || true
    notify_waybar
    ;;

  status)
    ensure_mako_dnd_rule
    ;;

  *)
    ;;
esac

print_json
