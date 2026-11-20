#!/usr/bin/env python3
"""NVIDIA Sway startup and safe stable-session migration contracts."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SESSION = ROOT / "trials/sway/session-launch.sh"
UPDATER = ROOT / "trials/sway/session-wrapper-update.sh"
session = SESSION.read_text(encoding="utf-8")
updater = UPDATER.read_text(encoding="utf-8")
for script in (SESSION, UPDATER):
    subprocess.run(["bash", "-n", str(script)], check=True)

old_line = 'exec /usr/bin/sway --config "$configuration"\n'
new_tail = (
    "# Sway's proprietary NVIDIA warning is an upstream support notice, not a\n"
    "# runtime compatibility check. Suppress it only when NVIDIA's driver is loaded.\n"
    "sway_args=()\n"
    "if [[ -r /proc/driver/nvidia/version ]]; then\n"
    "    sway_args+=(--unsupported-gpu)\n"
    "fi\n"
    'exec /usr/bin/sway "${sway_args[@]}" --config "$configuration"\n'
)
assert session.endswith(new_tail), "Unexpected NVIDIA launcher implementation"
original = session[: -len(new_tail)] + old_line
stock = subprocess.run(["git", "hash-object", "--stdin"], input=original,
                       text=True, capture_output=True, check=True).stdout.strip()
assert stock == "ffe175ba53f95f7480e478eeae63814609f8ca58", stock
assert stock in updater, "Stable updater does not recognize the old stock launcher"
assert "AWTARCHY_COMPOSITOR_RELEASE_SOURCE" in updater
assert '$(stat -c %u -- "$target"' in updater
assert "PRESERVE: Sway Ly launcher was customized" in updater

with tempfile.TemporaryDirectory(prefix="sway-nvidia-contract-") as temporary:
    root = Path(temporary)
    native = root / "native-sway"
    native.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@"\n')
    native.chmod(0o755)
    driver_marker = root / "nvidia/version"
    config = root / "config/sway/awtarchy-trial/config"
    config.parent.mkdir(parents=True)
    config.write_text("# fixture\n")
    fixture = root / "session"
    fixture.write_text(session.replace(
        "/proc/driver/nvidia/version", str(driver_marker)
    ).replace("/usr/bin/sway", str(native)))
    fixture.chmod(0o755)
    env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / "config"))

    def launch():
        result = subprocess.run([str(fixture)], env=env, capture_output=True,
                                text=True, timeout=10, check=True)
        return result.stdout.splitlines()

    assert launch() == ["--config", str(config)], "Non-NVIDIA launch changed"
    driver_marker.parent.mkdir()
    driver_marker.write_text("NVIDIA driver loaded\n")
    assert launch() == ["--unsupported-gpu", "--config", str(config)], (
        "NVIDIA launch did not supply exactly one unsupported-GPU flag")

    # The installed launcher is root-owned; test a disposable equivalent with
    # a fake sudo and relaxed ownership check, never the real system location.
    release = root / ("awtarchy-" + "a" * 40)
    (release / "trials/sway").mkdir(parents=True)
    (release / "config/hypr").mkdir(parents=True)
    (release / "trials/sway/setup.sh").write_text("# fixture\n")
    (release / "config/hypr/hyprland.lua").write_text("# fixture\n")
    (release / "trials/sway/session-launch.sh").write_text(session)
    target = root / "bin/awtarchy-sway-session"
    target.parent.mkdir()
    target.write_text(original)

    helper = root / "updater"
    test_updater = updater.replace(
        "target=/usr/local/bin/awtarchy-sway-session", f"target={target}"
    ).replace(
        "[[ -d /usr/local/bin && ! -L /usr/local/bin ]]",
        f"[[ -d {target.parent} && ! -L {target.parent} ]]"
    ).replace(
        '"$(stat -c %u -- "$target" 2>/dev/null)" != 0',
        '"$(id -u)" != "$(id -u)"'
    )
    assert test_updater != updater
    helper.write_text(test_updater)
    helper.chmod(0o755)
    fakebin = root / "fakebin"
    fakebin.mkdir()
    sudo = fakebin / "sudo"
    sudo.write_text('#!/usr/bin/env bash\n"$@"\n')
    sudo.chmod(0o755)
    release_env = dict(env, AWTARCHY_COMPOSITOR_RELEASE_SOURCE=str(release),
                       PATH=str(fakebin) + os.pathsep + env["PATH"])

    def update(mode, environment=release_env):
        return subprocess.run([str(helper), mode, str(release)],
                              env=environment, capture_output=True,
                              text=True, timeout=10)

    result = update("plan")
    assert result.returncode == 0 and "WOULD UPDATE" in result.stdout, result
    assert target.read_text() == original, "Preview changed the target"
    result = update("apply")
    assert result.returncode == 0 and "UPDATED:" in result.stdout, result
    assert target.read_text() == session, "Stock launcher not upgraded"
    assert any(p.read_text() == original for p in target.parent.glob(
        "awtarchy-sway-session.backup-*")), "Old stock file not backed up"
    result = update("plan")
    assert result.returncode == 0 and "current" in result.stdout, result
    target.write_text("# personal customized launcher\n")
    result = update("apply")
    assert result.returncode == 0 and "PRESERVE" in result.stdout, result
    assert target.read_text() == "# personal customized launcher\n"
    result = update("plan", dict(release_env, AWTARCHY_COMPOSITOR_RELEASE_SOURCE=""))
    assert result.returncode != 0 and "Not the registered Sway trial" in result.stderr
    result = update("plan", dict(release_env, AWTARCHY_COMPOSITOR_RELEASE_SOURCE=str(root)))
    assert result.returncode != 0 and "Invalid stable Sway release" in result.stderr

print("PASS: NVIDIA-only Sway flag, old stock migration, stable release gate and custom preservation")
