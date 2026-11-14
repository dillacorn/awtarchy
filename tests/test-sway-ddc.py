#!/usr/bin/env python3
"""Exercise the Sway DDC controller with fake outputs and no live hardware."""
import importlib.util
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "config/hypr/scripts/hypr-ddc-brightness.sh"
BAR = ROOT / "config/hypr/scripts/ddc_brightness.sh"
QUICKSETTINGS = ROOT / "trials/sway/quicksettings.py"

with tempfile.TemporaryDirectory(prefix="sway-ddc-") as directory:
    tmp = Path(directory)
    bin_dir = tmp / "bin"
    config = tmp / "config"
    cache = tmp / "cache"
    runtime = tmp / "runtime"
    for directory_path in (bin_dir, config / "hypr", cache, runtime):
        directory_path.mkdir(parents=True, exist_ok=True)

    (config / "hypr/ddcutil-bus-map.conf").write_text("DP-1=2\n")
    # Stage the repository sources like the installer (0755) before executing.
    staged_scripts = config / "sway/awtarchy-trial"
    staged_scripts.mkdir(parents=True)
    adapter_source = ROOT / "trials/sway/ddc.sh"
    for source in (CONTROLLER, BAR, adapter_source):
        target = staged_scripts / source.name
        shutil.copyfile(source, target)
        target.chmod(0o755)
    CONTROLLER = staged_scripts / CONTROLLER.name
    BAR = staged_scripts / BAR.name
    ADAPTER = staged_scripts / adapter_source.name
    swaymsg = bin_dir / "swaymsg"
    swaymsg.write_text(
        "#!/usr/bin/env bash\n"
        "printf '%s\\n' '[{\"name\":\"DP-1\",\"active\":true,"
        "\"focused\":true,\"make\":\"LG\",\"model\":\"27GN\","
        "\"serial\":\"TEST\"},{\"name\":\"DP-3\","
        "\"active\":true,\"focused\":false}]'\n"
    )
    ddcutil = bin_dir / "ddcutil"
    ddcutil.write_text(
        "#!/usr/bin/env bash\n"
        "case \" $* \" in\n"
        "  *' getvcp 0x10'*) printf '%s\\n' "
        "'VCP code 0x10 (Brightness): current value = 47, max value = 100' ;;\n"
        "  *) printf 'Unexpected DDC operation\\n' >&2; return 1 ;;\n"
        "esac\n"
    )
    hyprctl = bin_dir / "hyprctl"
    hyprctl.write_text(
        "#!/usr/bin/env bash\n"
        "printf '%s\\n' 'Incorrect Hyprland call in Sway' >&2\n"
        "return 91\n"
    )
    for script in (swaymsg, ddcutil, hyprctl):
        script.chmod(0o755)

    environment = os.environ.copy()
    environment.update({
        "PATH": str(bin_dir) + os.pathsep + environment.get("PATH", ""),
        "XDG_CURRENT_DESKTOP": "sway",
        "SWAYSOCK": str(tmp / "sway.sock"),
        "XDG_CONFIG_HOME": str(config),
        "XDG_CACHE_HOME": str(cache),
        "XDG_RUNTIME_DIR": str(runtime),
        "AWTARCHY_OUTPUT_NAME": "DP-1",
        "HYPR_BRIGHTNESS_SCRIPT": str(CONTROLLER),
        "HYPR_DDC_NOTIFY": "0",
    })

    def run(*args):
        return subprocess.run(
            [str(args[0]), *args[1:]], text=True,
            capture_output=True, env=environment, timeout=15,
        )

    direct = run(CONTROLLER, "--monitor", "DP-1", "status")
    assert direct.returncode == 0, direct.stderr
    assert "conn=DP-1\n" in direct.stdout, direct.stdout
    assert "cur=47\n" in direct.stdout, direct.stdout
    assert "max=100\n" in direct.stdout, direct.stdout

    focused = run(CONTROLLER, "status")
    assert focused.returncode == 0, focused.stderr
    assert "conn=DP-1\n" in focused.stdout, focused.stdout

    missing = run(CONTROLLER, "--monitor", "DP-99", "status")
    assert missing.returncode != 0, missing.stdout
    assert "monitor not found" in missing.stderr

    bar = run(ADAPTER, "status")
    assert bar.returncode == 0, bar.stderr
    data = json.loads(bar.stdout)
    assert data["percentage"] == 47, data

    spec = importlib.util.spec_from_file_location("sway_quicksettings", QUICKSETTINGS)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.DDC_STATUS = ADAPTER
    module.DDC_CONTROL = CONTROLLER
    monitors = [{"name": "DP-1"}, {"name": "DP-3"}]
    with patch.dict(os.environ, environment):
        status = module.brightness_status("DP-1", monitors)
        assert status["current"] == 47, status
        assert status["max"] == 100, status
        assert module.brightness_status("UNKNOWN", monitors)["current"] is None

print("PASS: Sway DDC status, focused monitor, bar output and Quick Settings value")
