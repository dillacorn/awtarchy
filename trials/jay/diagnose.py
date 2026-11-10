#!/usr/bin/env python3
"""Read-only Jay first-login audit. No config writes or compositor mutations."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib

def call(args, timeout=7):
    run = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if run.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}: {run.stderr.strip() or 'failed'}")
    return run.stdout.strip()

def randr_data(output):
    documents = [json.loads(row) for row in output.splitlines() if row.strip()]
    if len(documents) != 1 or not isinstance(documents[0], dict):
        raise ValueError("Unexpected JSONL from jay --json randr")
    data = documents[0]
    rows, renderers = {}, []
    for device in data.get("drm_devices", []):
        if not isinstance(device, dict):
            raise ValueError("Malformed Jay DRM entry")
        renderers.append(device.get("gfx_api", "unknown"))
        for connector in device.get("connectors", []):
            record_connector(connector, rows)
    for connector in data.get("unbound_connectors", []):
        record_connector(connector, rows)
    return rows, renderers

def record_connector(connector, rows):
    if not isinstance(connector, dict) or not isinstance(connector.get("name"), str):
        raise ValueError("Malformed Jay connector")
    name = connector["name"]
    if name in rows:
        raise ValueError(f"Duplicate Jay connector: {name}")
    output = connector.get("output") or {}
    mode = output.get("mode") or {}
    rows[name] = {
        "enabled": bool(connector.get("enabled")) and bool(output),
        "width": int(mode.get("width", output.get("width", 0))),
        "height": int(mode.get("height", output.get("height", 0))),
        "refresh": float(mode.get("refresh_rate_millihz", 0)) / 1000.0,
        "x": int(output.get("x", 0)),
        "y": int(output.get("y", 0)),
        "scale": float(output.get("scale", 1)),
        "vrr": str(output.get("vrr_mode", "unknown")),
        "tearing": str(output.get("tearing_mode", "unknown")),
        "vrr_capable": bool(output.get("vrr_capable", False)),
    }

def compare_outputs(config, actual):
    failures, notes = [], []
    saved = config.get("outputs", [])
    if not saved:
        notes.append("No saved Jay monitor profile. Import the active Hyprland layout before relying on display persistence.")
        return failures, notes
    for entry in saved:
        name = entry.get("match", {}).get("connector")
        if not isinstance(name, str):
            failures.append("Invalid saved Jay connector match")
            continue
        observed = actual.get(name)
        if not observed or not observed["enabled"]:
            failures.append(f"{name}: expected enabled output is missing")
            continue
        mode = entry["mode"]
        expected = (
            int(mode["width"]), int(mode["height"]),
            float(mode["refresh-rate"]), int(entry["x"]), int(entry["y"]),
            float(entry["scale"])
        )
        got = (
            observed["width"], observed["height"], observed["refresh"],
            observed["x"], observed["y"], observed["scale"]
        )
        mismatch = (
            expected[0] != got[0] or expected[1] != got[1]
            or abs(expected[2] - got[2]) > 0.15
            or expected[3] != got[3] or expected[4] != got[4]
            or abs(expected[5] - got[5]) > 0.02
        )
        summary = f"{name}: {got[0]}x{got[1]}@{got[2]:.3f} Hz, ({got[3]},{got[4]}), scale {got[5]:g}"
        if mismatch:
            failures.append(f"{summary}; expected {expected[0]}x{expected[1]}@{expected[2]:.3f} Hz, ({expected[3]},{expected[4]}), scale {expected[5]:g}")
        else:
            notes.append(f"Mode, refresh, position and scale match: {summary}")
    return failures, notes

def main():
    if os.environ.get("XDG_CURRENT_DESKTOP") != "jay" or not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Run from a Jay Wayland session only")
    home = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    config = home / "jay/config.toml"
    if config.is_symlink() or not config.is_file():
        raise RuntimeError(f"Missing/symlinked Jay config: {config}")
    data = tomllib.loads(config.read_text(encoding="utf-8"))
    errors, warnings, passed = [], [], []
    print("Jay first-login audit (read-only)")
    print("==============================")
    try:
        pid = call(["jay", "pid"])
        passed.append(f"Jay compositor responds (PID {pid})")
        outputs, renderers = randr_data(call(["jay", "--json", "randr"]))
        if not any(v["enabled"] for v in outputs.values()):
            errors.append("No active DRM output reported")
        else:
            failures, details = compare_outputs(data, outputs)
            errors.extend(failures)
            passed.extend(details)
            for name, row in outputs.items():
                if not row["enabled"]:
                    continue
                print(f"Output {name}: {row['width']}x{row['height']}@{row['refresh']:.3f}Hz; "
                      f"VRR={row['vrr']} (capable={row['vrr_capable']}), tearing={row['tearing']}")
                if row["tearing"] != data.get("tearing", {}).get("mode"):
                    errors.append(f"{name}: Jay tearing differs from configured fullscreen policy")
                if row["vrr_capable"] and row["vrr"] != data.get("vrr", {}).get("mode"):
                    errors.append(f"{name}: VRR mode differs from configured fullscreen policy")
            if renderers and any(x.lower() != "vulkan" for x in renderers):
                warnings.append("Not all Jay DRM devices report Vulkan; investigate active render GPU")
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired, KeyError) as exc:
        errors.append(f"Jay output/runtime query failed: {exc}")
    try:
        if call(["qs", "-c", "awtarchy-jay", "ipc", "call", "control", "ping"]) == "ok":
            passed.append("Jay Quickshell responds to control ping")
        else:
            errors.append("Quickshell control ping returned unexpected data")
    except (OSError, RuntimeError, subprocess.TimeoutExpired):
        errors.append("Jay Quickshell control IPC is unavailable")
    portal_file = home / "xdg-desktop-portal/jay-portals.conf"
    if portal_file.is_file() and not portal_file.is_symlink():
        lines = portal_file.read_text(encoding="utf-8")
        if "org.freedesktop.impl.portal.ScreenCast=jay" in lines:
            passed.append("Jay user screencast portal preference present (live sharing NOT validated)")
        else:
            warnings.append("Jay screencast portal preference is incorrect")
    else:
        warnings.append("Jay user portal preference missing")
    warnings.extend([
        "Screen Share Guard: no equivalent runtime implementation yet",
        "Digital vibrance: no verified Jay replacement",
        "Manual: verify display survives second login; test a Proton game, input modes, floating focus and real screen sharing"
    ])
    for label, values in (("PASS", passed), ("FAIL", errors), ("WARN", warnings)):
        for value in values:
            print(f"{label}: {value}")
    print(f"Summary: {len(passed)} pass, {len(errors)} fail, {len(warnings)} warnings")
    return 1 if errors else 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Jay diagnostic: {error}", file=sys.stderr)
        sys.exit(1)
