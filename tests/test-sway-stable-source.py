#!/usr/bin/env python3
"""Offline test of exact stable compositor release-source selection."""
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "local/share/awtarchy/awtarchy-compositor-stable.sh"
CORE = ROOT / "local/share/awtarchy/awtarchy-compositor-manager.sh"
assert "AWTARCHY_COMPOSITOR_RELEASE_SOURCE" in CORE.read_text()

with tempfile.TemporaryDirectory(prefix="awtarchy-release-source-") as work:
    root = Path(work)
    home = root / "home"
    state = home / ".local/state/awtarchy"
    state.mkdir(parents=True)
    version = state / "config-version"
    version.write_text("tag=v4.2.0\n")
    folder = root / "manager"
    folder.mkdir()
    wrapper = folder / SOURCE.name
    source = SOURCE.read_text()
    # GitHub's Arch container runs as root. Only this disposable test copy
    # simulates the unprivileged caller; the production guard is unchanged.
    assert source.count("[[ $EUID -ne 0 ]]") == 1
    wrapper.write_text(source.replace("[[ $EUID -ne 0 ]]", "[[ 1000 -ne 0 ]]"))
    core = folder / "awtarchy-compositor-core.sh"
    core.write_text(
        '#!/usr/bin/env bash\nset -euo pipefail\n'
        'printf "core:%s %s %s\\n" "$1" "$2" "$3"\n'
        'if [[ "$1" != status ]]; then\n'
        '  [[ -f "$AWTARCHY_COMPOSITOR_RELEASE_SOURCE/compositors/sway/setup.sh" ]]\n'
        '  [[ -f "$AWTARCHY_COMPOSITOR_RELEASE_SOURCE/config/hypr/hyprland.lua" ]]\n'
        'fi\n')
    sha = "a" * 40
    tag_sha = "b" * 40
    top = "awtarchy-" + sha
    archive = root / "archive.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        for name in (top + "/compositors/sway/setup.sh",
                     top + "/config/hypr/hyprland.lua"):
            payload = b"# fixture\n"
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(payload))
    released = root / "release.json"
    released.write_text(json.dumps({
        "tag_name": "v4.2.0", "draft": False,
        "published_at": "2026-11-15T01:00:00Z",
    }))
    reference = root / "ref.json"
    nested = root / "annotated.json"
    nested.write_text(json.dumps({"object": {"type": "commit", "sha": sha}}))
    fakebin = root / "bin"
    fakebin.mkdir()
    fake_curl = fakebin / "curl"
    fake_curl.write_text(
        '#!/usr/bin/env bash\nset -euo pipefail\n'
        'out=""\nurl=""\n'
        'while (($#)); do\n'
        '  case "$1" in\n'
        '    -o) out="$2"; shift 2 ;;\n'
        '    -H|--connect-timeout|--max-time|--retry|--speed-limit|--speed-time)'
        ' shift 2 ;;\n'
        '    -*) shift ;;\n'
        '    *) url="$1"; shift ;;\n'
        '  esac\n'
        'done\n'
        'case "$url" in\n'
        '  */releases/tags/v4.2.0) cp "$AWTARCHY_TEST_RELEASE" "$out" ;;\n'
        '  */git/ref/tags/v4.2.0) cp "$AWTARCHY_TEST_REF" "$out" ;;\n'
        '  */git/tags/*) cp "$AWTARCHY_TEST_ANNOTATED" "$out" ;;\n'
        '  */archive/*.tar.gz) cp "$AWTARCHY_TEST_ARCHIVE" "$out" ;;\n'
        '  *) echo "Unexpected URL: $url" >&2; exit 17 ;;\n'
        'esac\n')
    fake_curl.chmod(0o755)
    env = dict(os.environ)
    env.update({
        "HOME": str(home),
        "PATH": str(fakebin) + os.pathsep + os.environ.get("PATH", ""),
        "AWTARCHY_TEST_RELEASE": str(released),
        "AWTARCHY_TEST_REF": str(reference),
        "AWTARCHY_TEST_ANNOTATED": str(nested),
        "AWTARCHY_TEST_ARCHIVE": str(archive),
    })
    def run(*args):
        return subprocess.run(["bash", str(wrapper), *args],
                              env=env, capture_output=True, text=True, timeout=20)

    status = run("status", "plan", "no")
    assert status.returncode == 0, status.stderr
    assert "core:status plan no" in status.stdout
    for kind, target in (("commit", sha), ("tag", tag_sha)):
        reference.write_text(json.dumps({"object": {"type": kind, "sha": target}}))
        planned = run("update-sway", "plan", "no")
        assert planned.returncode == 0, (kind, planned.stdout, planned.stderr)
        assert "Using Awtarchy v4.2.0 at " + sha[:12] in planned.stdout
        assert "core:update-sway plan no" in planned.stdout
    released.write_text(json.dumps({
        "tag_name": "v4.2.1", "draft": False,
        "published_at": "2026-11-15T01:00:00Z",
    }))
    rejected = run("update-sway", "plan", "no")
    assert rejected.returncode != 0
    assert "core:update-sway" not in rejected.stdout
    version.write_text("tag=SwayWM_Migration_Trial_Investigation\n")
    rejected = run("update-sway", "plan", "no")
    assert rejected.returncode != 0
    assert "core:update-sway" not in rejected.stdout

print("PASS: exact stable release source, annotated tags, mismatch rejection")
