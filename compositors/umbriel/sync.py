#!/usr/bin/env python3
"""Isolated, always-preserve Umbriel/Quickshell staging and baseline updates."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tomllib



def port_brightness(repo: Path) -> dict[str, bytes]:
    """Adapt proven Awtarchy DDC implementation for Umbriel IPC without touching Hyprland."""
    scripts = repo / "config/hypr/scripts"
    bar = (scripts / "ddc_brightness.sh").read_text(encoding="utf-8")
    control = (scripts / "hypr-ddc-brightness.sh").read_text(encoding="utf-8")
    if (scripts / "ddc_brightness.sh").is_symlink() or (
            scripts / "hypr-ddc-brightness.sh").is_symlink():
        raise ValueError("Refusing symlinked brightness source")

    def once(body: str, old: str, new: str) -> str:
        if body.count(old) != 1:
            raise ValueError("Shared DDC source drift; refusing unverified port: " + old[:65])
        return body.replace(old, new, 1)

    first = bar.index("focused_monitor() {")
    last = bar.index("resolve_monitor() {", first)
    bar = bar[:first] + """focused_monitor() {
  umbriel outputs --json 2>/dev/null |
    jq -r '.[] | select(.enabled == true and .focused == true) | .name' | head -n1
}

monitor_under_cursor() {
  # Umbriel does not expose a cursor-position query. The bar supplies the
  # exact output through AWTARCHY_OUTPUT_NAME; otherwise use focused output.
  return 1
}

""" + bar[last:]
    bar = once(bar,
        '  if [[ "${XDG_CURRENT_DESKTOP:-}" == "sway" && -n "${SWAYSOCK:-}" ]]; then',
        '  if [[ "${XDG_CURRENT_DESKTOP,,}" == "umbriel" ]]; then\n'
        '    quickshell_manager="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel/awtarchy/quickshell.sh"\n'
        '    profile="awtarchy-umbriel"\n'
        '  elif [[ "${XDG_CURRENT_DESKTOP:-}" == "sway" && -n "${SWAYSOCK:-}" ]]; then')

    control = once(control,
        '  if [[ "${XDG_CURRENT_DESKTOP:-}" == "sway" && -n "${SWAYSOCK:-}" ]]; then\n'
        '    inventory="$(swaymsg -r -t get_outputs 2>/dev/null)" || return 1',
        '  if [[ "${XDG_CURRENT_DESKTOP,,}" == "umbriel" ]]; then\n'
        '    inventory="$(umbriel outputs --json 2>/dev/null)" || return 1\n'
        '  elif [[ "${XDG_CURRENT_DESKTOP:-}" == "sway" && -n "${SWAYSOCK:-}" ]]; then\n'
        '    inventory="$(swaymsg -r -t get_outputs 2>/dev/null)" || return 1')
    control = once(control,
        'if [[ "${XDG_CURRENT_DESKTOP:-}" == "sway" && -n "${SWAYSOCK:-}" ]]; then\n'
        '  need_cmd swaymsg\nelse\n  need_cmd hyprctl\nfi',
        'if [[ "${XDG_CURRENT_DESKTOP,,}" == "umbriel" ]]; then\n'
        '  need_cmd umbriel\n'
        'elif [[ "${XDG_CURRENT_DESKTOP:-}" == "sway" && -n "${SWAYSOCK:-}" ]]; then\n'
        '  need_cmd swaymsg\nelse\n  need_cmd hyprctl\nfi')
    control = control.replace('.active != false)', '.active != false and .enabled != false)')
    return {"ddc_brightness.sh": bar.encode(), "hypr-ddc-brightness.sh": control.encode()}


def port_quicksettings(repo: Path) -> dict[str, bytes]:
    """Keep the working Sway Quick Settings contract, swap only compositor identity."""
    source = repo / "compositors/sway"
    results = {}
    for name in ("quicksettings.py", "quicksettings.sh", "ddc.sh"):
        path = source / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("Missing or unsafe shared Quick Settings adapter " + str(path))
        body = path.read_text(encoding="utf-8")
        body = body.replace("Sway", "Umbriel").replace("sway/awtarchy-trial", "umbriel/awtarchy")
        body = body.replace("awtarchy-sway-submap", "awtarchy-umbriel-submap")
        if name == "ddc.sh":
            body = body.replace('"${SWAYSOCK:-}"', '"${WAYLAND_DISPLAY:-}"')
            body = body.replace('== "sway"', '== "Umbriel"')
            body = body.replace('${XDG_CURRENT_DESKTOP:-}', '${XDG_CURRENT_DESKTOP,,}')
            body = body.replace('== "Umbriel"', '== "umbriel"')
        if name == "quicksettings.sh":
            body = body.replace('== sway', '== Umbriel')
            body = body.replace('${XDG_CURRENT_DESKTOP:-}', '${XDG_CURRENT_DESKTOP,,}')
            body = body.replace('== Umbriel', '== umbriel')
        if name == "quicksettings.py":
            body = body.replace('!= "sway"', '!= "Umbriel"')
            body = body.replace('os.environ.get("XDG_CURRENT_DESKTOP") != "Umbriel"',
                                'os.environ.get("XDG_CURRENT_DESKTOP", "").casefold() != "umbriel"')
            body = body.replace('"mode-control.sh"', '"mode-control.py"')
            body = body.replace('["bash", str(MODE_CONTROL)', '["python3", str(MODE_CONTROL)')
            if 'command(["awtwall"])' in body:
                raise ValueError("Unported synchronous wallpaper picker action")
        if "swaymsg" in body or "SWAYSOCK" in body:
            raise ValueError("Unported Sway Quick Settings adapter: " + name)
        results[name] = body.encode()
    return results


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def desired_files(repo: Path, home: Path, stage: Path) -> dict[Path, bytes]:
    src = repo / "compositors/umbriel"
    config = home / ".config"
    target = config / "umbriel/awtarchy"
    sources = {
        config / "umbriel/config.toml": src / "native-config.toml",
        target / "config.toml": src / "config.toml",
    }
    # Keep the generated migration in Umbriel's private include. It is
    # regenerated from the selected source, never executed as Lua/Sway shell.
    spec = importlib.util.spec_from_file_location("awtarchy_umbriel_migrate", src / "migrate.py")
    migrator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migrator)
    override = os.environ.get("AWTARCHY_MIGRATE_FROM", "auto")
    migrated, info = migrator.migrate(home, override)
    print("MIGRATION: " + info["source"] + " (" + info["selection"] +
          "), displays=" + str(info["outputs"]) +
          ", shortcuts=" + str(info["keybinds"]))
    if info["outputs"] == 0:
        print("MIGRATION: no verified explicit display rules; defaults retained")
    result = {target / "migrated.toml": migrated}
    if info["workspace_home"]:
        # Retain the chosen global workspace home across compositor restarts,
        # focus changes, and future incremental Awtarchy updates.
        result[target / "workspace-home"] = (info["workspace_home"] + "\n").encode()
        print("MIGRATION: global workspaces 1-10 initially on " +
              info["workspace_home"] + " (native named workspaces)")
    guard_spec = importlib.util.spec_from_file_location(
        "awtarchy_umbriel_capture_guard", src / "screenshare-guard.py")
    guard_module = importlib.util.module_from_spec(guard_spec)
    guard_spec.loader.exec_module(guard_module)
    result[target / "capture-rules.toml"] = guard_module.render_defaults()
    floating_spec = importlib.util.spec_from_file_location(
        "awtarchy_umbriel_floating", src / "floating-windows.py")
    floating_module = importlib.util.module_from_spec(floating_spec)
    floating_spec.loader.exec_module(floating_module)
    result[target / "floating-rules.toml"] = floating_module.OFF
    theme_spec = importlib.util.spec_from_file_location(
        "awtarchy_umbriel_colors", src / "theme-colors.py")
    theme_module = importlib.util.module_from_spec(theme_spec)
    theme_spec.loader.exec_module(theme_module)
    theme = theme_module.palette(home)
    result[target / "theme.toml"] = theme_module.render_toml(theme)
    initial_quickshell_palette = theme_module.quickshell_palette(theme)
    # On the first Umbriel install, reflect the user's last selected
    # Awtarchy theme in its own picker state; never replace a later Umbriel
    # theme selection, which is protected by the separate managed baseline.
    shared_theme = home / ".local/state/awtarchy/active-theme"
    if (shared_theme.is_file() and not shared_theme.is_symlink()
            and shared_theme.stat().st_uid == os.geteuid()):
        name = shared_theme.read_text(encoding="utf-8").strip()
        if theme_module.valid_theme_name(name):
            try:
                theme_module.theme_source(home, name)
            except ValueError:
                pass
            else:
                result[home / ".local/state/awtarchy/active-theme-umbriel"] = (
                    name + "\n").encode()
    for name in ("session.sh", "awtwall.sh", "ipc.sh", "monitor-info.py", "workspace-state.py",
                 "workspace-events.py", "capture.sh", "toggle-utility.py",
                 "mode-control.py", "animations.sh",
                 "default-apps.sh", "workspace-nav.py",
                 "screenshare-guard.sh", "screenshare-guard.py",
                 "floating-windows.sh", "floating-windows.py", "position.sh", "runtime-rules.sh", "theme-apply.sh", "theme-colors.py"):
        sources[target / name] = src / name
    # Quickshell's save/copy/reset operations target the isolated compositor
    # helper, not the Hyprland executable. The old staging omitted this file,
    # so every flyout Save appeared successful while its command failed.
    shared_state = repo / "config/hypr/scripts/quickshell_application_state.sh"
    if not shared_state.is_file() or shared_state.is_symlink():
        raise ValueError("Unsafe shared Quickshell state helper")
    state_body = shared_state.read_text(encoding="utf-8")
    old_state = '/hypr/scripts/quickshell.sh'
    if state_body.count(old_state) != 1:
        raise ValueError("Shared Quickshell state manager source changed")
    state_body = state_body.replace(
        old_state, '/umbriel/awtarchy/quickshell.sh', 1)
    result[target / "application-state.sh"] = state_body.encode()

    # Screenshot preferences are shared; stage the known-good helper without
    # writing into any source compositor's installed configuration.
    sources[target / "screenshot_sound.sh"] = repo / "config/hypr/scripts/screenshot_sound.sh"
    # Sched-ext uses the same restricted Awtarchy core and authorization
    # across compositors, staged privately rather than calling Hyprland.
    sources[target / "scheduler.sh"] = repo / "compositors/sway/scheduler.sh"
    for name in ("hypr_quicksettings_core.sh", "hypr_quicksettings.sh"):
        sources[target / name] = repo / "config/hypr/scripts" / name
    # Carry Sway's tested, isolated login sound without touching installed
    # Hyprland, compositor configuration, or the shared sound preferences.
    audio = repo / "config/hypr/sounds/awtarchy-login.mp3"
    login_source = repo / "compositors/sway/login-sound.sh"
    if (not audio.is_file() or audio.is_symlink() or audio.stat().st_size < 100
            or not login_source.is_file() or login_source.is_symlink()):
        raise ValueError("Unsafe Awtarchy login audio source")
    result[target / "awtarchy-login.mp3"] = audio.read_bytes()
    login = login_source.read_text(encoding="utf-8")
    old_session = ('[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" &&\n'
                   '   -n "${WAYLAND_DISPLAY:-}" ]] || exit 0')
    new_session = ('[[ "${XDG_CURRENT_DESKTOP,,}" == umbriel &&\n'
                   '   -n "${WAYLAND_DISPLAY:-}" ]] || exit 0')
    if login.count(old_session) != 1:
        raise ValueError("Sway login sound session guard changed")
    login = login.replace(old_session, new_session, 1)
    login = login.replace("sway/awtarchy-trial", "umbriel/awtarchy")
    login = login.replace("awtarchy-sway-login-sound.lock",
                          "awtarchy-umbriel-login-sound.lock")
    result[target / "login-sound.sh"] = login.encode("utf-8")
    for dst, origin in sources.items():
        if origin.is_symlink() or not origin.is_file():
            raise ValueError("Unsafe Umbriel source " + str(origin))
        result[dst] = origin.read_bytes()
    tomllib.loads(result[target / "config.toml"].decode())
    tomllib.loads(result[config / "umbriel/config.toml"].decode())
    # Validate the full include stack before staging any live user config.
    # An invalid native config must not be installed or activated.
    if shutil.which("umbriel") is not None:
        testroot = stage / "validate/umbriel"
        testroot.mkdir(parents=True, exist_ok=True)
        for name, data in (
            ("config.toml", result[config / "umbriel/config.toml"]),
            ("awtarchy/config.toml", result[target / "config.toml"]),
            ("awtarchy/migrated.toml", result[target / "migrated.toml"]),
            ("awtarchy/theme.toml", result[target / "theme.toml"]),
            ("awtarchy/capture-rules.toml",
             result[target / "capture-rules.toml"]),
            ("awtarchy/floating-rules.toml",
             result[target / "floating-rules.toml"]),
        ):
            dest = testroot / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
        env = dict(os.environ)
        env["XDG_CONFIG_HOME"] = str(testroot.parent)
        check = subprocess.run(["umbriel", "config", "validate"], env=env,
                               capture_output=True, text=True, timeout=12)
        if check.returncode:
            raise ValueError("Umbriel rejected migrated config: " +
                             (check.stderr or check.stdout).strip()[:2500])

    rendered = stage / "awtarchy-umbriel"
    manager = stage / "quickshell.sh"
    subprocess.run([sys.executable, str(src / "render-quickshell.py"),
                    "--repo", str(repo), "--dest", str(rendered)],
                   check=True, timeout=70)
    subprocess.run([sys.executable, str(src / "render-manager.py"),
                    "--repo", str(repo), "--dest", str(manager)],
                   check=True, timeout=40)
    for asset in sorted(rendered.iterdir()):
        if not asset.is_file() or asset.is_symlink():
            raise ValueError("Unexpected rendered Umbriel shell asset")
        result[config / "quickshell/awtarchy-umbriel" / asset.name] = (
            initial_quickshell_palette if asset.name == "theme.json"
            else asset.read_bytes())
    result[target / "quickshell.sh"] = manager.read_bytes()
    for name, content in port_brightness(repo).items():
        result[target / name] = content
    for name, content in port_quicksettings(repo).items():
        result[target / name] = content
    return result


def safe_directories(home: Path):
    for relative in (".config", ".config/umbriel",
                     ".config/umbriel/awtarchy",
                     ".config/quickshell", ".config/quickshell/awtarchy-umbriel",
                     ".local", ".local/state", ".local/state/awtarchy"):
        item = home / relative
        if item.is_symlink() or (item.exists() and not item.is_dir()):
            raise ValueError("Unsafe Umbriel destination directory " + str(item))
        if item.exists() and item.stat().st_uid != os.geteuid():
            raise ValueError("Unowned Umbriel destination directory " + str(item))


def atomic_write(path: Path, data: bytes, backup: bool):
    staged_name = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".umbriel-stage-", dir=path.parent,
                                         delete=False) as staged:
            staged_name = staged.name
            staged.write(data)
            staged.flush()
            os.fsync(staged.fileno())
        os.chmod(staged_name, 0o755 if path.suffix == ".sh" else 0o644)
        if backup:
            import datetime
            tag = datetime.datetime.now(datetime.timezone.utc).strftime(
                "%Y%m%d-%H%M%S-%f")
            previous = path.with_name(path.name + ".backup-" + tag)
            with previous.open("xb") as handle:
                os.fchmod(handle.fileno(), 0o600)
                handle.write(path.read_bytes())
                handle.flush()
                os.fsync(handle.fileno())
        os.replace(staged_name, path)
        staged_name = None
    finally:
        if staged_name is not None and os.path.exists(staged_name):
            os.unlink(staged_name)


def reconcile(repo: Path, home: Path, mode: str):
    if mode not in ("preview", "apply"):
        raise ValueError("Invalid Umbriel staging mode")
    if os.geteuid() == 0:
        raise ValueError("Do not stage Umbriel files as root")
    if home.is_symlink() or not home.is_dir():
        raise ValueError("Unsafe home directory")
    safe_directories(home)
    state = home / ".local/state/awtarchy/umbriel-trial-baseline.json"
    if state.is_symlink() or (state.exists() and (not state.is_file()
            or state.stat().st_uid != os.geteuid())):
        raise ValueError("Unsafe Umbriel managed baseline")
    baseline = {}
    if state.is_file():
        contents = json.loads(state.read_text(encoding="utf-8"))
        if (not isinstance(contents, dict) or contents.get("version") != 1
                or not isinstance(contents.get("hashes"), dict)):
            raise ValueError("Invalid Umbriel baseline manifest")
        baseline = contents["hashes"]
        if any(not isinstance(k, str) or not isinstance(v, str)
               or not re.fullmatch(r"[0-9a-f]{64}", v) for k, v in baseline.items()):
            raise ValueError("Invalid Umbriel baseline entries")
    with tempfile.TemporaryDirectory(prefix="umbriel-render-") as temp:
        desired = desired_files(repo, home, Path(temp))
    native = home / ".config/umbriel/config.toml"
    native_source = desired[native]
    # Never quietly install a shell that the native session will not load.
    if native.is_symlink() or (native.is_file()
            and native.read_bytes() != native_source
            and baseline.get(str(native.relative_to(home)))
                != digest(native.read_bytes())):
        raise ValueError(
            "Personal Umbriel config exists. Preserved; refusing to override "
            "it or misrepresent that Awtarchy will launch. Add an include manually "
            "or test on a fresh Umbriel config.")
    for target in desired:
        if target.is_symlink() or (target.exists() and (
                not target.is_file() or target.stat().st_uid != os.geteuid())):
            raise ValueError("Unsafe or unowned Umbriel file " + str(target))
    updated = dict(baseline)
    new_files = changes = preserved = 0
    # Install migration data before publishing an include that references it.
    # On an already running Umbriel session this avoids an incomplete reload.
    native = home / ".config/umbriel/config.toml"
    ordered = sorted(desired, key=lambda path: (
        path == native, str(path)))
    for target in ordered:
        content = desired[target]
        key = str(target.relative_to(home))
        expected = digest(content)
        existing = target.read_bytes() if target.exists() else None
        if existing == content:
            if mode == "apply":
                updated[key] = expected
            continue
        if existing is None:
            new_files += 1
            print(("INSTALL " if mode == "apply" else "WOULD INSTALL ") + key)
            if mode == "apply":
                target.parent.mkdir(parents=True, exist_ok=True)
                atomic_write(target, content, False)
                updated[key] = expected
            continue
        if baseline.get(key) != digest(existing):
            preserved += 1
            print("PRESERVE personalized file " + key)
            continue
        changes += 1
        print(("UPDATE " if mode == "apply" else "WOULD UPDATE ")
              + key + " (original backup)")
        if mode == "apply":
            # A settings editor may modify the file after our initial scan.
            # Never turn a stale baseline into authority over a newer edit.
            if target.is_symlink() or not target.is_file() or target.read_bytes() != existing:
                raise ValueError("Umbriel file changed during update; preserving " + key)
            atomic_write(target, content, True)
            updated[key] = expected
    if mode == "apply":
        state.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(state, (json.dumps({"version": 1, "hashes": updated},
                     indent=2, sort_keys=True) + "\n").encode(), bool(state.exists()))
    print("Umbriel files: new=%s updated=%s preserved=%s"
          % (new_files, changes, preserved))
    print("Other compositor configurations and installed packages are untouched.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preview", "apply"))
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    try:
        reconcile(args.repo.resolve(), Path.home().resolve(), args.mode)
    except (ValueError, OSError, UnicodeError, json.JSONDecodeError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print("Umbriel staging: " + str(error), file=sys.stderr)
        sys.exit(1)
