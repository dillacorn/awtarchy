#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p -- "$tmp/bin"
cat > "$tmp/bin/qs" <<'QS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWTARCHY_TEST_QS_LOG"
printf '%s\n' true
QS
cat > "$tmp/bin/mmsg" <<'MMSG'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWTARCHY_TEST_MMSG_LOG"
MMSG
chmod +x -- "$tmp/bin/qs" "$tmp/bin/mmsg"
export AWTARCHY_TEST_QS_LOG="$tmp/qs.log"
export AWTARCHY_TEST_MMSG_LOG="$tmp/mmsg.log"
export PATH="$tmp/bin:$PATH"
export MANGO_INSTANCE_SIGNATURE="/run/user/1000/mango-mock.sock"
export QUICKSHELL_CONFIG_NAME=awtarchy-mango

for path in \
    config/hypr/scripts/quickshell_launcher.sh \
    config/hypr/scripts/quickshell_quick_settings_toggle.sh \
    config/hypr/scripts/quickshell_clipboard_toggle.sh \
    config/hypr/scripts/quickshell_notifications_toggle.sh \
    config/hypr/scripts/quickshell_notification_dismiss.sh \
    config/hypr/scripts/quickshell_lockscreen_editor.sh \
    config/hypr/scripts/quickshell_bar_toggle.sh \
    config/hypr/scripts/quickshell_bar_flip.sh; do
    bash -n "$path"
    bash "$path"
done

bash -n config/hypr/scripts/quickshell_power_menu.sh
bash config/hypr/scripts/quickshell_power_menu.sh
bash -n config/hypr/scripts/quickshell_application_state.sh

if grep -vF -- '-c awtarchy-mango' "$tmp/qs.log"; then
    printf 'ERROR: used Hyprland Quickshell instance in Mango session\n' >&2
    false
fi
grep -Fxq 'dispatch setkeymode,default' "$tmp/mmsg.log"
printf 'PASS: shared Awtarchy shell controls route to Mango instance\n'
