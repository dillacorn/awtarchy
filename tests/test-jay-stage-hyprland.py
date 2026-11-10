#!/usr/bin/env python3
"""Keep Hyprland, its scripts and Quickshell user modifications on Jay dual installs."""
from pathlib import Path
import importlib.util
import tempfile

root=Path(__file__).resolve().parents[1]
path=root/"trials/jay/stage-hyprland.py"
spec=importlib.util.spec_from_file_location("stage_hyprland",path)
stage=importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)

with tempfile.TemporaryDirectory(prefix="awtarchy-hypr-stage.") as scratch:
    home=Path(scratch)
    cfg=home/".config/hypr"
    cfg.mkdir(parents=True)
    own=cfg/"hyprland.lua"
    own.write_text("-- user customized Hyprland\n")
    assert stage.stage(root,home,apply=False)>100
    assert not (cfg/"scripts").exists()
    assert own.read_text()=="-- user customized Hyprland\n"
    count=stage.stage(root,home,apply=True)
    assert count>100
    assert (cfg/"scripts").is_dir()
    assert (cfg/"shaders").is_dir()
    assert (cfg/"screenshare_guard.lua").is_file()
    assert (home/".config/quickshell/awtarchy/shell.qml").is_file()
    assert own.read_text()=="-- user customized Hyprland\n"
    assert stage.stage(root,home,apply=False)==0
    assert stage.stage(root,home,apply=True)==0
    assert own.read_text()=="-- user customized Hyprland\n"
    # Reject a symlink in a nested destination before starting any copy.
    external=home/"outside"
    external.mkdir()
    (cfg/"scripts").rename(cfg/"user-preserved-scripts")
    (cfg/"scripts").symlink_to(external,target_is_directory=True)
    try:
        stage.stage(root,home,apply=False)
    except ValueError:
        pass
    else:
        raise AssertionError("Symlinked config path was accepted")
    assert not list(external.iterdir())
print("PASS: Hyprland staging includes required scripts and preserves user-owned configs")
