#!/usr/bin/env bash
# Static integration checks for Awtarchy's full Foot terminal transition.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"
HYPR="$ROOT/config/hypr/hyprland.lua"
HELPER="$ROOT/config/hypr/scripts/default_terminal.sh"
LAUNCHER="$ROOT/config/quickshell/awtarchy/Launcher.qml"
CONFIG="$ROOT/config/foot/foot.ini"

require() {
    grep -Fq -- "$2" "$1" || {
        printf 'FAIL: missing %s in %s\n' "$2" "$1" >&2
        return 1
    }
}

[[ -f "$CONFIG" ]] || { printf 'FAIL: Foot profile is missing\n' >&2; exit 1; }
require "$RUNTIME" 'Terminal Apps:foot '
require "$RUNTIME" 'config_dirs=(hypr quickshell foot '
require "$RUNTIME" '.config/foot/*'
require "$RUNTIME" '"alacritty", "foot",'
require "$HYPR" 'local terminal = "foot"'
grep -Fxq -- "local yazi = \"foot -f 'JetBrainsMono Nerd Font Mono:size=12' yazi\"" "$HYPR" || {
    printf '%s\n' 'FAIL: the Foot Yazi command is malformed' >&2
    exit 1
}
if command -v lua >/dev/null 2>&1; then
    HYPR_TO_CHECK="$HYPR" lua -e 'assert(loadfile(os.getenv("HYPR_TO_CHECK")))'
    printf 'PASS: Hyprland Lua syntax validated\n'
fi
require "$HELPER" 'exec foot --app-id="$window_class"'
require "$LAUNCHER" 'command: ["foot", ...entry.command]'
require "$CONFIG" 'font=NotoSansM Nerd Font Mono:size=12'
require "$CONFIG" 'pad=22x22'
require "$CONFIG" '[colors-dark]'
require "$CONFIG" 'alpha=0.85'
if grep -Fxq '[colors]' "$CONFIG"; then
    printf 'FAIL: obsolete Foot [colors] section\n' >&2
    exit 1
fi
# Alacritty Graphics may remain installed as an optional user-managed terminal.
# The Foot migration must never uninstall it or remove its existing config.
if grep -Fq 'remove_retired_alacritty_packages' "$RUNTIME"; then
    printf 'FAIL: Awtarchy must not uninstall Alacritty during the Foot migration\n' >&2
    exit 1
fi
require "$RUNTIME" 'if rel.startswith(".config/alacritty/") and ni is None:'
require "$RUNTIME" 'if ! pacman -Qq foot >/dev/null 2>&1; then'
require "$RUNTIME" 'pacman_install_one foot'
require "$CONFIG" 'alpha=0.85'
require "$ROOT/config/hypr/scripts/quickshell_theme_apply.sh" 'FOOT_CONF="$CONFIG_HOME/foot/foot.ini"'
require "$ROOT/config/hypr/scripts/quickshell_theme_catalog.sh" '"foot": path.name,'
require "$ROOT/config/hypr/scripts/quickshell_theme_apply.sh" 'foot_theme_live.py'
require "$ROOT/config/hypr/scripts/foot_theme_live.py" 'def broadcast(colors:'
if grep -Eq '^[[:space:]]*alacritty-graphics([[:space:]]|$)' "$RUNTIME"; then
    printf 'FAIL: Alacritty Graphics remains in the package catalog\n' >&2
    exit 1
fi
require "$RUNTIME" 'local -a required=(quickshell foot upower'
require "$ROOT/config/hypr/scripts/awtarchy-polkit-agent/launcher.sh" 'FOOT="/usr/bin/foot"'

for quicksettings in "$ROOT/config/hypr/scripts/hypr_quicksettings.sh" "$ROOT/config/hypr/scripts/hypr_quicksettings_core.sh"; do
    require "$quicksettings" 'exec foot --app-id="$TERM_CLASS"'
    if grep -Eiq 'alacritty|exec kitty|exec xterm' "$quicksettings"; then
        printf 'FAIL: retired terminal launch path still exists: %s\n' "$quicksettings" >&2
        exit 1
    fi
done
require "$ROOT/config/hypr/scripts/hypr_quicksettings_core.sh" "printf -v launch_cmd 'foot --app-id wallpicker %q --resume'"


# Theme switching must update all 18 ANSI/foreground/background entries,
# preserve the existing terminal opacity, and leave optional Alacritty alone.
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/config/foot/themes" "$tmp/config/hypr/themes" "$tmp/config/alacritty" "$tmp/fakebin"
cp -- "$CONFIG" "$tmp/config/foot/foot.ini"
cp -- "$ROOT"/config/foot/themes/*.ini "$tmp/config/foot/themes/"
cp -- "$ROOT"/config/hypr/themes/* "$tmp/config/hypr/themes/"
printf '%s\n' '[window]' 'opacity = 0.85' >"$tmp/config/alacritty/alacritty.toml"
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/fakebin/hyprctl"
printf '#!/usr/bin/env bash\nexit 1\n' >"$tmp/fakebin/systemctl"
chmod 0755 "$tmp/fakebin/hyprctl" "$tmp/fakebin/systemctl"

for theme in carbon_night catppuccin-frappé crimson_red electric_blue gruvbox iron_forge obsidian_night pink pipboy; do
    palette="$tmp/config/foot/themes/${theme}.ini"
    [[ -f "$palette" ]] || { printf 'FAIL: missing Foot palette: %s\n' "$theme" >&2; exit 1; }
    [[ "$(grep -Ec '^(background|foreground|regular[0-7]|bright[0-7])=[0-9a-f]{6}$' "$palette")" -eq 18 ]] || {
        printf 'FAIL: incomplete Foot palette: %s\n' "$theme" >&2
        exit 1
    }
    XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" \
        PATH="$tmp/fakebin:$PATH" \
        bash "$ROOT/config/hypr/scripts/quickshell_theme_apply.sh" "$theme"
    while IFS= read -r entry; do
        [[ "$entry" == \#* || -z "$entry" ]] && continue
        grep -Fxq -- "$entry" "$tmp/config/foot/foot.ini" || {
            printf 'FAIL: switched Foot palette did not match %s: %s\n' "$theme" "$entry" >&2
            exit 1
        }
    done <"$palette"
    grep -Fxq 'alpha=0.85' "$tmp/config/foot/foot.ini" || {
        printf 'FAIL: Foot opacity changed while switching themes\n' >&2
        exit 1
    }
done
grep -Fxq 'opacity = 0.85' "$tmp/config/alacritty/alacritty.toml" || {
    printf 'FAIL: Foot theme switching touched optional Alacritty settings\n' >&2
    exit 1
}

# A personalized, preserved v3.8.9 hyprland.lua must adopt Foot even after
# the v4.0.0 update, without replacing its other local customizations.
require "$RUNTIME" 'migrate_legacy_foot_hyprland "$repo_dir" "$target_home"'
require "$RUNTIME" 'rollback_quickshell_update'
migrator="$ROOT/local/share/awtarchy/migrate-foot-hyprland.py"
[[ -f "$migrator" ]] || { printf 'FAIL: Foot Hyprland migrator missing\\n' >&2; exit 1; }
python3 - "$migrator" "$HYPR" "$tmp" <<'PY_MIGRATE_FOOT'
import importlib.util
from pathlib import Path
import subprocess
import sys

script, target, temp = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("foot_hyprland", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

assert len(module.LEGACY_COMMANDS) == 9, "missing historical Alacritty launch paths"
current = target.read_text(encoding="utf-8")
assert all("foot" in module.managed_line(current.splitlines(), key)
           for key, _ in module.LEGACY_COMMANDS)

live = temp / "preserved-hyprland.lua"
out = temp / "migrated-hyprland.lua"
custom = '-- personalized layout should be retained intact\n'
original = custom + current.replace(
    'local web_browser = "firefox"', 'local web_browser = "custom-browser"'
)
legacy = original
for key, old_line in module.LEGACY_COMMANDS:
    new_line = module.managed_line(current.splitlines(), key)
    assert legacy.count(new_line + "\n") == 1, key
    legacy = legacy.replace(new_line + "\n", old_line + "\n", 1)

live.write_text(legacy, encoding="utf-8")
result = subprocess.run(
    [sys.executable, str(script), str(live), str(target), str(out)],
    capture_output=True, text=True
)
assert result.returncode == 0, result.stderr
assert out.read_text(encoding="utf-8") == original, "migration damaged personal Hyprland settings"

# Already-migrated and user-authored configurations must be unaffected.
out.unlink()
live.write_text(original, encoding="utf-8")
result = subprocess.run(
    [sys.executable, str(script), str(live), str(target), str(out)],
    capture_output=True, text=True
)
assert result.returncode == 0 and not out.exists(), "repeat migration was not idempotent"

# Unknown custom Alacritty launch commands must remain user-owned.
customized = legacy.replace(
    'local terminal = "alacritty"',
    'local terminal = "alacritty --my-custom-launcher"'
)
live.write_text(customized, encoding="utf-8")
result = subprocess.run(
    [sys.executable, str(script), str(live), str(target), str(out)],
    capture_output=True, text=True
)
assert result.returncode == 0, result.stderr
migrated = out.read_text(encoding="utf-8")
assert 'local terminal = "alacritty --my-custom-launcher"' in migrated
assert custom in migrated and 'custom-browser' in migrated
out.unlink()

# A bad release command must not be substituted into the live configuration.
bad_target = temp / "bad-hyprland.lua"
bad_target.write_text(current.replace('local terminal = "foot"',
                                      'local terminal = "other-terminal"'), encoding="utf-8")
live.write_text(legacy, encoding="utf-8")
result = subprocess.run(
    [sys.executable, str(script), str(live), str(bad_target), str(out)],
    capture_output=True, text=True
)
assert result.returncode != 0 and not out.exists(), "invalid target was accepted"

print("PASS: all nine legacy Hyprland terminal commands, custom preservation and idempotence")
PY_MIGRATE_FOOT


# v4.0.0 archives omitted migrate-foot-hyprland.py while the refreshed
# updater still called it. Exercise the actual shell migration function against
# a staged archive without the helper, not just the standalone Python script.
python3 - "$RUNTIME" "$migrator" "$HYPR" "$tmp" <<'PY_FOOT_MISSING_HELPER'
from pathlib import Path
import importlib.util
import re
import subprocess
import sys

runtime_path, helper_path, target_path, root = map(Path, sys.argv[1:])
runtime = runtime_path.read_text(encoding="utf-8")
match = re.search(
    r"(?ms)^migrate_legacy_foot_hyprland\(\) \{\n.*?^\}",
    runtime,
)
assert match, "updater Foot migration function missing"
assert '[[ -f "$target" && -f "$migrator" ]]' not in match.group(), \
    "updater still requires the helper from the release archive"
assert "PY_FOOT_HYPRLAND_FALLBACK" in match.group(), \
    "updater lacks its own migration implementation"

spec = importlib.util.spec_from_file_location("foot_migration", helper_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

current = target_path.read_text(encoding="utf-8")
custom = "-- personal Hyprland customization must survive\n"
expected = custom + current
legacy = expected
for key, original in module.LEGACY_COMMANDS:
    new = module.managed_line(current.splitlines(), key)
    assert legacy.count(new + "\n") == 1, key
    legacy = legacy.replace(new + "\n", original + "\n", 1)

stage = root / "release-without-helper"
live_home = root / "live-without-helper"
temp = root / "migration-fallback"
(stage / ".config/hypr").mkdir(parents=True, exist_ok=True)
(live_home / ".config/hypr").mkdir(parents=True, exist_ok=True)
temp.mkdir(exist_ok=True)
(stage / ".config/hypr/hyprland.lua").write_text(current, encoding="utf-8")
live_file = live_home / ".config/hypr/hyprland.lua"

# The source archive intentionally contains no standalone helper.
assert not (stage / "local/share/awtarchy/migrate-foot-hyprland.py").exists()

harness = "\n".join([
    "set -euo pipefail",
    match.group(),
    'HOME_DIR="$1"; TMPD="$2"',
    'ROLLBACK_PATHS=(); CHANGED=()',
    'log() { :; }',
    'warn() { printf "WARN: %s\\n" "$*" >&2; }',
    'snapshot_for_rollback() { :; }',
    'make_persistent_backup() { :; }',
    'validate_candidate() { [[ -s "$1" ]]; }',
    'atomic_copy() { cp -- "$1" "$2"; }',
    'migrate_legacy_foot_hyprland "$3" "$4"',
]) + "\n"

def run_case(source: str, expected_text: str, valid_target=True):
    live_file.write_text(source, encoding="utf-8")
    output = stage / ".config/hypr/hyprland.lua"
    if valid_target:
        output.write_text(current, encoding="utf-8")
    else:
        output.unlink()
    result = subprocess.run(
        ["bash", "-c", harness, "foot-test", str(live_home), str(temp), str(stage), str(stage)],
        capture_output=True, text=True,
    )
    assert (result.returncode == 0) == valid_target, result.stderr
    assert live_file.read_text(encoding="utf-8") == expected_text, \
        f"unexpected migration result: {result.stdout} {result.stderr}"
    return result

result = run_case(legacy, expected)
assert "Updated preserved Awtarchy terminal commands" not in result.stderr, \
    "unexpected migration diagnostic"
run_case(expected, expected)  # idempotent on repeat
run_case(legacy.replace(
    'local terminal = "alacritty"',
    'local terminal = "alacritty --custom-options"'
), expected.replace(
    'local terminal = "foot"',
    'local terminal = "alacritty --custom-options"'
))  # custom terminal command is user-owned
run_case(legacy, legacy, valid_target=False)  # fail without modifying live file
print("PASS: updater migrates the v4.0.0 release without an external helper")
PY_FOOT_MISSING_HELPER

if command -v foot >/dev/null 2>&1; then
    foot --check-config --config="$CONFIG"
    printf 'PASS: Foot configuration validated with installed Foot\n'
else
    printf 'SKIP: Foot binary unavailable; native config validation needs the Arch test machine\n'
fi

printf 'PASS: Foot terminal migration and optional Alacritty preservation contracts\n'
