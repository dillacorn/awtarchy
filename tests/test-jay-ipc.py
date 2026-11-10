#!/usr/bin/env python3
"""Jay IPC must check a real control reply, not only qs' exit status."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
IPC = ROOT / "trials/jay/ipc.sh"

QS = r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 6 && "$1" == -c && "$2" == awtarchy-jay &&
   "$3" == ipc && "$4" == call ]] || { printf 'bad qs invocation\n' >&2; exit 3; }
printf '%s/%s\n' "$5" "$6" >>"$EVENTS"
if [[ "$5:$6" == control:ping ]]; then
    case "$SCENARIO" in
        unavailable) printf 'Target not found.\n'; exit 0 ;;
        recover) [[ -e "$READY" ]] || { printf 'Target not found.\n'; exit 0; } ;;
        ping-error) printf 'unreachable\n' >&2; exit 1 ;;
    esac
    printf 'ok\n'
    exit 0
fi
if [[ "$SCENARIO" == target-error ]]; then
    printf 'Function not found.\n'
    exit 0
fi
if [[ "$SCENARIO" == target-exit-error ]]; then
    printf 'Broken transport\n' >&2
    exit 1
fi
printf 'Dispatched.\n'
"""

MANAGER = r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == start ]] || exit 3
printf 'manager-start\n' >>"$EVENTS"
touch -- "$READY"
"""


def check(scenario, expected_code, expected_events, error_text=None):
    with tempfile.TemporaryDirectory(prefix="jay-ipc-test-") as temp:
        parent = Path(temp)
        binpath = parent / "bin"
        binpath.mkdir()
        qs = binpath / "qs"
        qs.write_text(QS)
        qs.chmod(0o755)
        manager = parent / "config/jay/awtarchy-trial/quickshell.sh"
        manager.parent.mkdir(parents=True)
        manager.write_text(MANAGER)
        events = parent / "events"
        ready = parent / "ready"
        env = dict(os.environ)
        env.update(
            PATH=str(binpath) + os.pathsep + env.get("PATH", ""),
            XDG_CONFIG_HOME=str(parent / "config"),
            XDG_CURRENT_DESKTOP="jay",
            WAYLAND_DISPLAY="wayland-test",
            EVENTS=str(events),
            READY=str(ready),
            SCENARIO=scenario,
        )
        run = subprocess.run(["bash", str(IPC), "launcher", "toggle"],
                             env=env, capture_output=True, text=True, timeout=5)
        assert run.returncode == expected_code, (scenario, run.stdout, run.stderr)
        assert events.read_text().splitlines() == expected_events, scenario
        if error_text:
            assert error_text in run.stderr, (scenario, run.stderr)
        else:
            assert "Jay Quickshell IPC:" not in run.stderr, (scenario, run.stderr)


check("ready", 0, ["control/ping", "launcher/toggle"])
check("recover", 0, ["control/ping", "manager-start", "control/ping", "launcher/toggle"])
check("unavailable", 1, ["control/ping", "manager-start", "control/ping"],
      "control handler unavailable")
check("ping-error", 1, ["control/ping", "manager-start", "control/ping"],
      "control handler unavailable")
check("target-error", 1, ["control/ping", "launcher/toggle"],
      "Function not found.")
check("target-exit-error", 1, ["control/ping", "launcher/toggle"],
      "Broken transport")
print("PASS: Jay IPC detects false-success status, starts once, and reports failures")
