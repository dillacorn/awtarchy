#!/usr/bin/env python3
"""Offline Umbriel autostart regression: IPC races and missing Quickshell."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SESSION = ROOT / "compositors/umbriel/session.sh"


def executable(path: Path, body: str):
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    path.chmod(0o755)


def run_case(*, ready_after: int, manager: bool, manager_fails=False):
    with tempfile.TemporaryDirectory(prefix="umbriel-autostart-") as temp:
        root = Path(temp)
        home = root / "home"
        helper = home / ".config/umbriel/awtarchy"
        helper.mkdir(parents=True)
        binaries = root / "bin"
        binaries.mkdir()
        counter = root / "ipc-count"
        start_calls = root / "start-calls"
        executable(binaries / "umbriel", """set -euo pipefail
[[ "${1:-}" == outputs && "${2:-}" == --json ]] || false
count=0
if [[ -f "$AWTARCHY_TEST_IPC_COUNT" ]]; then
    read -r count < "$AWTARCHY_TEST_IPC_COUNT"
fi
count=$((count + 1))
printf '%s\\n' "$count" > "$AWTARCHY_TEST_IPC_COUNT"
(( count >= AWTARCHY_TEST_READY_AFTER )) || false
printf '[]\\n'
""")
        # Skip the deliberate 100ms pause in the mocked race test only.
        executable(binaries / "sleep", "true\n")
        if manager:
            executable(helper / "quickshell.sh", """set -euo pipefail
printf '%s\\n' "$*" >> "$AWTARCHY_TEST_MANAGER_CALLS"
[[ "$*" == start ]] || false
[[ "${AWTARCHY_TEST_MANAGER_FAIL:-0}" != 1 ]]
""")
        env = dict(os.environ)
        env.update({
            "PATH": str(binaries) + ":" + os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": str(home),
            "XDG_CURRENT_DESKTOP": "umbriel",
            "XDG_SESSION_TYPE": "wayland",
            "WAYLAND_DISPLAY": "wayland-test",
            "XDG_CONFIG_HOME": str(home / ".config"),
            "AWTARCHY_TEST_IPC_COUNT": str(counter),
            "AWTARCHY_TEST_MANAGER_CALLS": str(start_calls),
            "AWTARCHY_TEST_READY_AFTER": str(ready_after),
            "AWTARCHY_TEST_MANAGER_FAIL": "1" if manager_fails else "0",
        })
        run = subprocess.run(
            ["bash", str(SESSION)], env=env, capture_output=True,
            text=True, timeout=12,
        )
        attempts = int(counter.read_text().strip()) if counter.exists() else 0
        calls = start_calls.read_text().splitlines() if start_calls.exists() else []
        return run.returncode, attempts, calls, run.stderr


# The previous one-shot IPC check permanently left a fresh login without a
# shell when the first query raced compositor startup.
rc, checks, calls, stderr = run_case(ready_after=3, manager=True)
assert rc == 0, stderr
assert checks == 3, (checks, stderr)
assert calls == ["start"], calls

# Missing IPC must fail boundedly and must not launch Quickshell on another
# compositor's Wayland socket.
rc, checks, calls, stderr = run_case(ready_after=999, manager=True)
assert rc != 0
assert checks == 25, checks
assert calls == []
assert "after startup retries" in stderr, stderr

# A partial managed setup must not silently report success or play a login
# sound when its Quickshell manager is absent.
rc, checks, calls, stderr = run_case(ready_after=1, manager=False)
assert rc != 0
assert checks == 1 and calls == []
assert "manager missing or unsafe" in stderr, stderr

# Do not report success if the manager failed to bring up the QML shell.
rc, checks, calls, stderr = run_case(ready_after=1, manager=True, manager_fails=True)
assert rc != 0
assert checks == 1 and calls == ["start"]
assert "Umbriel Quickshell failed" in stderr, stderr

print("PASS: Umbriel IPC race, missing manager, and failed shell startup")
