#!/usr/bin/env python3
"""Preview/apply Sway code updates without replacing personalized TOML or QML."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

# The broken 2026-11-13 trial updater forced manual staging of this exact
# initial component. Recognize only those original bytes when upgrading a
# still-untracked manual install; all other untracked QML stays protected.
LEGACY_MANUAL_INSTALL_HASHES = {
    ".config/quickshell/awtarchy-sway/SwayFlyoutWindow.qml": frozenset({
        "f2ade98dad43a0ca39564f1ccd45992c296ea0a8d08fb2bf82c69698965ff461",
    }),
}

# Exact Git blob IDs of prior stock trial compositor managers; do NOT upgrade
# any user-modified manager. This once-only adoption lets the menu refresh its
# own future source-check and activation behavior without a separate installer.
LEGACY_MANAGER_GIT_BLOBS = frozenset({
    "77e494c9f8fe758b3cc26b26bb680d167f33cbc1",
    "f17db9840449b73c235b458314908f6b821ffb43",
    "14d085b3045ccb6654d9bd02684e880c83f6e850",
})


def git_blob_sha1(body: bytes):
    return hashlib.sha1(
        b"blob " + str(len(body)).encode("ascii") + b"\x00" + body
    ).hexdigest()

def sha(data):
    return hashlib.sha256(data).hexdigest()

def expected_files(repo, home, temporary):
    trial = repo / "trials/sway"
    script = (trial / "setup.sh").read_text(encoding="utf-8")
    m = re.search(r"^sources=\(([^)]*)\)$", script, flags=re.MULTILINE)
    if not m:
        raise ValueError("Sway setup source manifest is unavailable")
    sources = shlex.split(m.group(1))
    if "config" not in sources or "sway-portals.conf" not in sources:
        raise ValueError("Sway managed source inventory changed")
    result = {}
    for name in sources:
        if "/" in name or not re.fullmatch(r"[a-zA-Z0-9._-]+", name):
            raise ValueError("Unsafe Sway source name")
        target = (
            home / ".config/sway/awtarchy-trial/config" if name == "config" else
            home / ".config/xdg-desktop-portal/sway-portals.conf" if name == "sway-portals.conf" else
            home / ".config/xdg-desktop-portal-wlr/sway" if name == "screencast-chooser.conf" else
            home / ".config/sway/awtarchy-trial" / name
        )
        source = trial / name
        if source.is_symlink() or not source.is_file():
            raise ValueError("Unsafe Sway source file: " + str(source))
        result[target] = source.read_bytes()
    # Sway uses private copies of shared helpers (DDC and screenshot audio).
    # Active ~/.config/hypr/scripts may be personalized or from an older
    # release, so Sway updates must not depend on replacing those files.
    for name in ("ddc_brightness.sh", "hypr-ddc-brightness.sh", "screenshot_sound.sh"):
        source = repo / "config/hypr/scripts" / name
        if source.is_symlink() or not source.is_file():
            raise ValueError("Unsafe shared helper source: " + str(source))
        result[home / ".config/sway/awtarchy-trial" / name] = source.read_bytes()
    # Preserve the exact Awtarchy login MP3 in the isolated Sway profile.
    login_audio = repo / "config/hypr/sounds/awtarchy-login.mp3"
    if not login_audio.is_file() or login_audio.is_symlink():
        raise ValueError("Missing or unsafe Awtarchy login audio")
    result[home / ".config/sway/awtarchy-trial/awtarchy-login.mp3"] = login_audio.read_bytes()
    shell = temporary / "awtarchy-sway"
    subprocess.run(
        ["python3", str(trial / "render-quickshell.py"),
         "--source", str(repo / "config/quickshell/awtarchy"),
         "--dest", str(shell), "--bridge-dir", str(trial)],
        check=True, timeout=45
    )
    for source in shell.iterdir():
        if not source.is_file() or source.is_symlink():
            raise ValueError("Unexpected generated Sway Quickshell asset")
        result[home / ".config/quickshell/awtarchy-sway" / source.name] = source.read_bytes()
    generated = temporary / "quickshell.sh"
    subprocess.run(
        ["python3", str(trial / "render-manager.py"),
         "--source", str(repo / "config/hypr/scripts/quickshell.sh"),
         "--dest", str(generated)],
        check=True, timeout=30
    )
    result[home / ".config/sway/awtarchy-trial/quickshell.sh"] = generated.read_bytes()
    # The installed menu runs this user-owned helper directly. Keep it in the
    # managed Sway update set, but only migrate known unmodified stock versions.
    source_manager = repo / "local/share/awtarchy/awtarchy-compositor-manager.sh"
    if source_manager.is_symlink() or not source_manager.is_file():
        raise ValueError("Missing or unsafe trial compositor manager source")
    result[home / ".local/share/awtarchy/awtarchy-compositor-manager.sh"] = (
        source_manager.read_bytes()
    )
    return result

def prepare_config_update(old: bytes, new: bytes) -> bytes:
    """Keep the original Sway output profile byte-for-byte across updates.

    Called only when the installed config hash still matches Awtarchy's
    recorded baseline. A user-edited config is preserved without guessing.
    """
    start = "# AWTARCHY-SWAY-OUTPUTS-BEGIN"
    end = "# AWTARCHY-SWAY-OUTPUTS-END"
    previous = old.decode("utf-8")
    proposed = new.decode("utf-8")
    for text in (previous, proposed):
        if text.count(start) != 1 or text.count(end) != 1:
            raise ValueError("Sway monitor delimiters changed; refusing config update")
    imported = previous.split(start, 1)[1].split(end, 1)[0]
    return (proposed.split(start, 1)[0] + start + imported + end
            + proposed.split(end, 1)[1]).encode("utf-8")


def validate_sway_config(target: Path, content: bytes):
    # Parse the *real* imported monitor profile with installed Sway before
    # replacing the live config. This never starts a session.
    with tempfile.NamedTemporaryFile(
            prefix=".sway-config-check-", dir=target.parent,
            delete=False) as stage:
        temp_path = Path(stage.name)
        stage.write(content)
    try:
        result = subprocess.run(
            ["sway", "-C", "-c", str(temp_path)], timeout=20,
            capture_output=True, text=True)
        if result.returncode:
            raise ValueError("Sway rejected candidate config: " + result.stderr.strip())
    finally:
        temp_path.unlink(missing_ok=True)


def refresh_sway_portal_if_safe():
    """Reload the Sway-only portal backend only when idle and already running.

    xdpw reads its chooser configuration at startup. Never terminate an
    active xdpw PipeWire source; that would interrupt screen sharing.
    Unknown PipeWire state fails closed and defers the refresh.
    """
    service = "xdg-desktop-portal-wlr.service"
    active = subprocess.run(
        ["systemctl", "--user", "is-active", "--quiet", service],
        capture_output=True, timeout=7)
    if active.returncode != 0:
        print("Portal chooser installed; inactive backend will use it on next start.")
        return
    try:
        probe = subprocess.run(
            ["pw-dump"], capture_output=True, text=True, timeout=8)
        if probe.returncode:
            raise ValueError("PipeWire state query failed")
        nodes = json.loads(probe.stdout)
        if not isinstance(nodes, list):
            raise ValueError("Unexpected PipeWire state")
        streaming = any(
            isinstance(node, dict)
            and node.get("type") == "PipeWire:Interface:Node"
            and isinstance(node.get("info"), dict)
            and isinstance(node["info"].get("props"), dict)
            and str(node["info"]["props"].get("node.name", "")).startswith("xdpw-stream-")
            for node in nodes
        )
    except (OSError, ValueError, subprocess.TimeoutExpired):
        print("Portal chooser installed; could not prove streams are idle, "
              "so the active portal was preserved.", file=sys.stderr)
        return
    if streaming:
        print("Portal chooser installed; active screen sharing detected. "
              "Preserving the current stream and deferring portal restart.")
        return
    result = subprocess.run(
        ["systemctl", "--user", "restart", service],
        capture_output=True, text=True, timeout=20)
    if result.returncode:
        raise ValueError("Portal picker installed but backend restart failed: "
                         + result.stderr.strip())
    print("LIVE: Sway screen-sharing portal refreshed for the Quickshell picker.")


def activate_in_running_sway(home: Path, expected: dict, changed_keys: set):
    """Activate managed updates without interrupting the compositor session.

    Never send reload to a different Sway instance or restart a modified
    Quickshell manager. A failed live refresh must not discard applied files.
    """
    if not changed_keys:
        print("Sway managed files already current; no live reload needed.")
        return
    if (os.environ.get("XDG_CURRENT_DESKTOP", "").lower() != "sway"
            or not os.environ.get("SWAYSOCK")
            or not os.environ.get("WAYLAND_DISPLAY")):
        print("Sway is not the current session; updates activate on next Sway login.")
        return

    version = subprocess.run(
        ["swaymsg", "-r", "-t", "get_version"], capture_output=True,
        text=True, timeout=8)
    if version.returncode:
        raise ValueError("Files updated, but Sway identity check failed: "
                         + version.stderr.strip())
    try:
        running_config = json.loads(version.stdout)["loaded_config_file_name"]
    except (ValueError, KeyError, TypeError):
        raise ValueError("Files updated; Sway did not report its loaded config")
    target_config = str(home / ".config/sway/awtarchy-trial/config")
    if running_config != target_config:
        print("Active Sway is not the Awtarchy trial; skipping unrelated session reload.")
        return

    config_key = ".config/sway/awtarchy-trial/config"
    if config_key in changed_keys:
        reply = subprocess.run(
            ["swaymsg", "-r", "-t", "command", "reload"],
            capture_output=True, text=True, timeout=15)
        try:
            result = json.loads(reply.stdout)
        except (ValueError, TypeError):
            result = None
        if (reply.returncode or not isinstance(result, list) or not result
                or any(not isinstance(item, dict) or item.get("success") is not True
                       for item in result)):
            raise ValueError("Files updated, but Sway config reload failed: "
                             + (reply.stderr.strip() or reply.stdout.strip()))
        print("LIVE: Sway configuration reloaded; applications and workspaces retained.")

    # Activate the newly installed daemon without a logout. The manager
    # checks the exact Sway socket and rejects unrelated compositor sessions.
    idle_keys = {
        '.config/sway/awtarchy-trial/idle-manager.py',
        '.config/sway/awtarchy-trial/idle-action.sh',
        '.config/sway/awtarchy-trial/swayidle.conf',
    }
    if changed_keys & idle_keys:
        idle = home / '.config/sway/awtarchy-trial/idle-manager.py'
        if (idle.is_symlink() or not idle.is_file()
                or expected.get(idle) != idle.read_bytes()):
            print('Sway idle manager is customized/missing; automatic startup skipped.',
                  file=sys.stderr)
        else:
            result = subprocess.run(['python3', str(idle), 'start'], timeout=16)
            if result.returncode:
                raise ValueError('Sway idle files installed but swayidle could not start; '
                                 'check ~/.cache/awtarchy/swayidle.log')
            print('LIVE: Sway idle daemon checked and activated without logout.')

    # No portal restart for unrelated updates, and no restart during any
    # active xdpw screencast. Only the verified Sway trial may touch it.
    if ".config/xdg-desktop-portal-wlr/sway" in changed_keys:
        refresh_sway_portal_if_safe()

    # The compositor's own environment is immutable until next login, but
    # D-Bus-activated apps and the Quickshell launcher can refresh in place.
    qt_changed = ".config/sway/awtarchy-trial/session.sh" in changed_keys
    if qt_changed:
        themed_env = dict(os.environ, QT_QPA_PLATFORMTHEME="qt5ct:qt6ct")
        for command in (
            ["dbus-update-activation-environment", "--systemd",
             "QT_QPA_PLATFORMTHEME"],
            ["systemctl", "--user", "import-environment", "QT_QPA_PLATFORMTHEME"],
        ):
            try:
                r = subprocess.run(command, env=themed_env,
                                   capture_output=True, text=True, timeout=8)
                if r.returncode:
                    print("Sway Qt environment import failed: "
                          + (r.stderr.strip() or " ".join(command)), file=sys.stderr)
            except (OSError, subprocess.TimeoutExpired) as exc:
                print("Sway Qt environment import unavailable: " + str(exc),
                      file=sys.stderr)

    needs_shell_restart = qt_changed or any(
        key.startswith(".config/quickshell/awtarchy-sway/")
        or key == ".config/sway/awtarchy-trial/quickshell.sh"
        for key in changed_keys
    )
    if not needs_shell_restart:
        return
    manager = home / ".config/sway/awtarchy-trial/quickshell.sh"
    if (manager.is_symlink() or not manager.is_file()
            or expected.get(manager) != manager.read_bytes()):
        print("Sway shell update installed; custom/missing Quickshell manager not "
              "executed automatically. Restart the Sway shell manually after review.",
              file=sys.stderr)
        return
    env = dict(os.environ, QUICKSHELL_CONFIG_NAME="awtarchy-sway")
    if qt_changed:
        env["QT_QPA_PLATFORMTHEME"] = "qt5ct:qt6ct"
    restart = subprocess.run(["bash", str(manager), "restart"],
                             env=env, timeout=30)
    if restart.returncode:
        raise ValueError("Files updated and Sway reloaded, but the Sway Quickshell "
                         "restart failed; inspect the Quickshell-Sway log")
    print("LIVE: Only the Awtarchy Sway Quickshell profile restarted.")


def atomic_replace(target, body):
    if target.is_symlink() or target.parent.is_symlink():
        raise ValueError("Refusing symlinked Sway destination")
    if not target.parent.is_dir():
        raise ValueError("Sway destination parent missing: " + str(target.parent))
    if target.exists() and not target.is_file():
        raise ValueError("Sway destination is not a file")
    previous = target.read_bytes() if target.exists() else None
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    if previous is not None:
        backup = target.with_name(target.name + ".backup-" + stamp)
        with backup.open("xb") as handle:
            handle.write(previous)
            handle.flush()
            os.fsync(handle.fileno())
        backup.chmod(0o600)
    fd, name = tempfile.mkstemp(prefix=".sway-managed-", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(body)
            handle.flush()
            os.fsync(handle.fileno())
        mode = target.stat().st_mode & 0o777 if target.exists() else 0o755 if target.suffix == ".sh" else 0o644
        os.chmod(name, mode)
        os.replace(name, target)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("record", "review", "apply"))
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    if os.geteuid() == 0:
        raise ValueError("Run the Sway updater as the normal user")
    home = Path.home().resolve()
    repo = args.repo.resolve()
    if not (repo / "trials/sway/setup.sh").is_file():
        raise ValueError("Sway source checkout not found")
    state = home / ".local/state/awtarchy"
    manifest = state / "sway-managed-baseline.json"
    if manifest.is_symlink() or state.is_symlink():
        raise ValueError("Unsafe Sway baseline path")
    with tempfile.TemporaryDirectory(prefix="sway-sync-") as stage:
        desired = expected_files(repo, home, Path(stage))
    actual = {}
    for path, body in desired.items():
        if path.is_symlink() or path.parent.is_symlink():
            raise ValueError("Refusing linked installed Sway path: " + str(path))
        if path.is_file():
            actual[str(path.relative_to(home))] = sha(path.read_bytes())
    if args.mode == "record":
        for path, body in desired.items():
            key = str(path.relative_to(home))
            if key == ".config/sway/awtarchy-trial/config":
                # Includes the one-time imported monitor profile, not base defaults.
                if key not in actual:
                    raise ValueError("No installed Sway configuration")
            elif actual.get(key) != sha(body):
                raise ValueError("Installed Sway stage does not match source: " + key)
        state.mkdir(parents=True, exist_ok=True)
        if manifest.exists():
            raise ValueError("Existing Sway baseline cannot be silently adopted")
        atomic_replace(manifest, json.dumps(actual, indent=2, sort_keys=True).encode() + b"\n")
        print("PASS: recorded exact initial Sway source baseline")
        return
    if not manifest.is_file():
        raise ValueError("Missing Sway baseline; refusing to assume personalized files are unmodified")
    original = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(original, dict):
        raise ValueError("Invalid Sway baseline")
    updated = dict(original)
    changed_keys = set()
    counts = dict(unchanged=0, update=0, preserve=0, missing=0)
    for path, body in sorted(desired.items(), key=lambda item: str(item[0])):
        key = str(path.relative_to(home))
        current = actual.get(key)
        target = sha(body)
        if current == target:
            # A new managed asset may have been installed by setup.sh after
            # the original baseline was recorded. Adopt only byte-for-byte
            # source matches, never arbitrary existing user files.
            if key not in original:
                print(("ADOPT: " if args.mode == "apply" else "WOULD ADOPT: ")
                      + key + " (exact source match; no file write)")
                if args.mode == "apply":
                    updated[key] = target
            counts["unchanged"] += 1
            continue
        if key == ".config/sway/awtarchy-trial/config":
            # Awtarchy's original installer records the installed config
            # *after* one-time monitor import. Honor that exact hash as proof
            # the user has not edited it. Preserve every personal change.
            if original.get(key) != current:
                counts["preserve"] += 1
                print("PRESERVE user-modified Sway config: " + key)
                continue
            candidate = prepare_config_update(path.read_bytes(), body)
            if sha(candidate) == current:
                counts["unchanged"] += 1
                continue
            validate_sway_config(path, candidate)
            counts["update"] += 1
            print(("UPDATE: " if args.mode == "apply" else "WOULD UPDATE: ")
                  + key + " (preserve imported monitor layout)")
            if args.mode == "apply":
                if sha(path.read_bytes()) != current:
                    raise ValueError("Sway config changed during update; refusing")
                atomic_replace(path, candidate)
                updated[key] = sha(candidate)
                changed_keys.add(key)
            continue
        if current is None:
            # New QML emitted by our strict Sway renderer is managed source,
            # not an unknown user file. This was previously skipped, leaving
            # the shell unable to start when SwayFlyoutWindow.qml was added.
            # Existing files that differ from source remain protected below.
            generated_qml = (
                path.parent == home / ".config/quickshell/awtarchy-sway"
                and path.suffix == ".qml"
                and re.fullmatch(r"[A-Za-z0-9_-]+[.]qml", path.name) is not None
            )
            new_helper = key in (
                ".config/sway/awtarchy-trial/awtarchy-login.mp3",
                ".config/sway/awtarchy-trial/login-sound.sh",
                ".config/sway/awtarchy-trial/screenshot_sound.sh",
                ".config/sway/awtarchy-trial/ddc_brightness.sh",
                ".config/sway/awtarchy-trial/hypr-ddc-brightness.sh",
                ".config/sway/awtarchy-trial/ddc.sh",
                ".config/sway/awtarchy-trial/theme-colors.sh",
                ".config/sway/awtarchy-trial/toggle-utility.py",
                ".config/sway/awtarchy-trial/lock-manager.sh",
                ".config/sway/awtarchy-trial/mime-parity.py",
                ".config/sway/awtarchy-trial/focus-cycle.py",
                ".config/sway/awtarchy-trial/mode-control.sh",
                ".config/sway/awtarchy-trial/portal-chooser.py",
                ".config/sway/awtarchy-trial/idle-manager.py",
                ".config/sway/awtarchy-trial/idle-action.sh",
                ".config/sway/awtarchy-trial/swayidle.conf",
                ".config/xdg-desktop-portal-wlr/sway",
                ".local/share/awtarchy/awtarchy-compositor-manager.sh",
            )
            if not (generated_qml or new_helper):
                counts["missing"] += 1
                print("MISSING (manual re-stage required): " + key)
                continue
            counts["update"] += 1
            label = "new rendered Sway QML" if generated_qml else "new Sway-only helper"
            print(("INSTALL: " if args.mode == "apply" else "WOULD INSTALL: ")
                  + key + " (" + label + ")")
            if args.mode == "apply":
                if key == ".config/xdg-desktop-portal-wlr/sway":
                    # Only create the Sway-specific portal configuration
                    # directory; preserve all existing files and symlinks.
                    directory = path.parent
                    if directory.is_symlink() or (
                        directory.exists() and not directory.is_dir()
                    ):
                        raise ValueError("Unsafe Sway portal configuration directory")
                    directory.mkdir(mode=0o700, exist_ok=True)
                atomic_replace(path, body)
                updated[key] = target
                changed_keys.add(key)
            continue
        if (key not in original
                and current in LEGACY_MANUAL_INSTALL_HASHES.get(key, ())):
            # The user had to install the original flyout QML by hand to
            # recover a broken Quickshell session. Its exact stock hash is
            # proven, so this specific older copy can be updated and backed
            # up without adopting arbitrary untracked user content.
            counts["update"] += 1
            print(("UPDATE: " if args.mode == "apply" else "WOULD UPDATE: ")
                  + key + " (recognized old manual Sway hotfix; backup)")
            if args.mode == "apply":
                if sha(path.read_bytes()) != current:
                    raise ValueError("Sway manual hotfix changed during update; refusing")
                atomic_replace(path, body)
                updated[key] = target
                changed_keys.add(key)
            continue
        # Previous trial installs staged the manager outside this manifest.
        # Adopt only exact known stock Git blobs; never take over custom scripts.
        if (key == ".local/share/awtarchy/awtarchy-compositor-manager.sh"
                and key not in original
                and git_blob_sha1(path.read_bytes()) in LEGACY_MANAGER_GIT_BLOBS):
            counts["update"] += 1
            print(("UPDATE: " if args.mode == "apply" else "WOULD UPDATE: ")
                  + key + " (recognized original trial manager; backup)")
            if args.mode == "apply":
                if git_blob_sha1(path.read_bytes()) not in LEGACY_MANAGER_GIT_BLOBS:
                    raise ValueError("Trial manager changed during update; refusing")
                atomic_replace(path, body)
                updated[key] = target
                changed_keys.add(key)
            continue
        if original.get(key) != current:
            counts["preserve"] += 1
            print("PRESERVE modified file: " + key)
            continue
        counts["update"] += 1
        print(("UPDATE: " if args.mode == "apply" else "WOULD UPDATE: ") + key)
        if args.mode == "apply":
            atomic_replace(path, body)
            updated[key] = target
            changed_keys.add(key)
    if args.mode == "apply":
        atomic_replace(manifest, json.dumps(updated, indent=2, sort_keys=True).encode() + b"\n")
    print("Summary: " + ", ".join(f"{key}={value}" for key, value in counts.items()))
    print("Personal config and user-modified files were never overwritten.")
    if args.mode == "apply":
        activate_in_running_sway(home, desired, changed_keys)
        # Portal refresh is handled by activate_in_running_sway, only when
        # the backend has no xdpw PipeWire stream; never require a logout.

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired, KeyError, json.JSONDecodeError) as exc:
        print("Sway sync: " + str(exc), file=sys.stderr)
        sys.exit(1)
