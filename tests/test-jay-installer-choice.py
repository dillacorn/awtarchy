#!/usr/bin/env python3
"""Prevent installer regressions when adding optional Jay to Awtarchy.

Runs in an unprivileged CI container. Does not source the live installer or
invoke package managers.
"""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
runtime = root / "local/share/awtarchy/awtarchy-runtime.sh"
text = runtime.read_text(encoding="utf-8")
subprocess.run(["bash", "-n", str(runtime)], check=True)

def fn(name):
    match = re.search(r"(?ms)^" + re.escape(name) + r"\(\) \{\n.*?^\}\n", text)
    assert match is not None, name
    return match.group(0)

helpers = "".join(fn(n) for n in (
    "compositor_has_hyprland", "compositor_has_jay", "is_hyprland_only_package"
))
script = helpers + r'''
set -euo pipefail
COMPOSITOR_SELECTION=hyprland
compositor_has_hyprland && ! compositor_has_jay
COMPOSITOR_SELECTION=jay
compositor_has_jay && ! compositor_has_hyprland
COMPOSITOR_SELECTION=both
compositor_has_jay && compositor_has_hyprland
is_hyprland_only_package hyprland
is_hyprland_only_package hypridle
is_hyprland_only_package xdg-desktop-portal-hyprland
! is_hyprland_only_package quickshell
! is_hyprland_only_package foot
! is_hyprland_only_package xdg-desktop-portal-gtk
'''
subprocess.run(["bash", "-c", script], check=True)

assert 'COMPOSITOR_SELECTION="hyprland"' in text
assert 'single_select_menu "Wayland compositor"' in text
for choice in (
    'COMPOSITOR_SELECTION="jay"; step=2',
    'COMPOSITOR_SELECTION="both"; step=2',
    'COMPOSITOR_SELECTION="hyprland"; step=2',
):
    assert choice in text, choice
assert "install_jay_repo_dependencies_stage" in text
assert "packages_to_install+=(jay)" in text
assert "install_aur_with_scanner" in text
assert "install_jay_session_stage" in text
assert "run_as_target env" in fn("install_jay_session_stage")
assert 'bash "${source}/setup.sh" --check' in fn("install_jay_session_stage")
assert 'bash "${source}/setup.sh" --install' in fn("install_jay_session_stage")
assert 'if compositor_has_hyprland && [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then' in text
assert 'if [[ "$dir" == hypr ]] && ! compositor_has_hyprland; then' in fn("copy_awtarchy_configs_stage")
assert "install_jay_session_stage" in fn("run_install")
print("PASS: compositor menu, package selection, Jay staging and Hyprland preservation")
