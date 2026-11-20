#!/usr/bin/env python3
"""Sway checkout source: no false no-op, fast-forward only, preserve local edits."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "compositors/sway/source-refresh.sh"
BRANCH = "SwayWM_Migration_Trial_Investigation"


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True,
                          text=True, check=True, timeout=20).stdout.strip()


def check(root, mode):
    return subprocess.run(["bash", str(SCRIPT), mode, str(root)],
                          capture_output=True, text=True, timeout=20)


with tempfile.TemporaryDirectory(prefix="sway-trial-source-") as temp:
    root = Path(temp)
    remote = root / "origin.git"
    checkout = root / "local"
    publisher = root / "publisher"
    subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
    subprocess.run(["git", "clone", "-q", str(remote), str(checkout)], check=True)
    git(checkout, "config", "user.name", "Sway CI")
    git(checkout, "config", "user.email", "ci@example.invalid")
    git(checkout, "checkout", "-b", BRANCH)
    (checkout / "README").write_text("one\n")
    git(checkout, "add", "README")
    git(checkout, "commit", "-qm", "initial")
    git(checkout, "push", "-u", "origin", BRANCH)
    original = git(checkout, "rev-parse", "HEAD")
    assert check(checkout, "check").returncode == 0

    subprocess.run(["git", "clone", "-q", "-b", BRANCH,
                    str(remote), str(publisher)], check=True)
    git(publisher, "config", "user.name", "Sway CI")
    git(publisher, "config", "user.email", "ci@example.invalid")
    (publisher / "README").write_text("two\n")
    git(publisher, "commit", "-qam", "new upstream")
    git(publisher, "push", "origin", BRANCH)
    fresh = git(publisher, "rev-parse", "HEAD")

    review = check(checkout, "check")
    assert review.returncode == 3, review.stdout + review.stderr
    assert "checkout behind" in review.stdout
    assert git(checkout, "rev-parse", "HEAD") == original
    (checkout / "README").write_text("personal edit\n")
    refused = check(checkout, "apply")
    assert refused.returncode != 0
    assert (checkout / "README").read_text() == "personal edit\n"
    assert git(checkout, "rev-parse", "HEAD") == original
    git(checkout, "restore", "README")

    applied = check(checkout, "apply")
    assert applied.returncode == 0, applied.stdout + applied.stderr
    assert git(checkout, "rev-parse", "HEAD") == fresh
    assert (checkout / "README").read_text() == "two\n"
    assert check(checkout, "check").returncode == 0

    # Local unpublished commits must not be overwritten by a remote update.
    (checkout / "README").write_text("three local\n")
    git(checkout, "commit", "-qam", "local divergence")
    local = git(checkout, "rev-parse", "HEAD")
    (publisher / "README").write_text("three remote\n")
    git(publisher, "commit", "-qam", "remote divergence")
    git(publisher, "push", "origin", BRANCH)
    refused = check(checkout, "apply")
    assert refused.returncode != 0
    assert git(checkout, "rev-parse", "HEAD") == local
    assert (checkout / "README").read_text() == "three local\n"
print("PASS: current/stale source, readonly review, clean fast-forward, dirty/diverged preservation")
