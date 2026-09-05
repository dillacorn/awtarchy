#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path(sys.argv[1]) / "crates/aur-scanner-cli/src/commands/install.rs"
text = path.read_text()
old = '''    let output = Command::new(pacman)
        .arg("-Qp")
        .arg("--print-format")
        .arg("%n")
        .arg("--")
        .arg(path)
'''
new = '''    let output = Command::new(pacman)
        .arg("-Qqp")
        .arg(path)
'''
if text.count(old) != 1:
    raise SystemExit("expected exactly one pacman archive-query block")
path.write_text(text.replace(old, new))
