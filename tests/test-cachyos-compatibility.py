#!/usr/bin/env python3
"""Non-destructive CachyOS installer compatibility regressions."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = (ROOT / "local/share/awtarchy/awtarchy-runtime.sh").read_text()
DOCS = (ROOT / "docs/cachyos-compatibility.md").read_text()


def function(name: str) -> str:
    start = re.search(rf"(?m)^{re.escape(name)}\(\)\s*\{{", RUNTIME)
    if start is None:
        raise AssertionError(f"Missing function: {name}")
    next_fn = re.search(r"(?m)^[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{", RUNTIME[start.end():])
    end = len(RUNTIME) if next_fn is None else start.end() + next_fn.start()
    return RUNTIME[start.start():end]


def shell(script: str) -> str:
    proc = subprocess.run(
        ["bash", "-c", "set -euo pipefail\n" + script],
        cwd=ROOT, capture_output=True, text=True, check=False,
    )
    if proc.returncode:
        raise AssertionError(
            f"Bash returned {proc.returncode}:\n{proc.stdout}\n{proc.stderr}"
        )
    return proc.stdout


class CompatibilityTests(unittest.TestCase):
    def test_effective_multilib(self):
        source = function("multilib_enabled")
        installer = function("install_arch_repo_apps_stage")
        self.assertIn("pacman-conf --repo-list", installer)
        self.assertNotIn('grep -q "^\\[multilib\\]"', installer)
        output = shell(source + r'''
pacman-conf() { [[ "$1" == --repo-list ]] && printf 'core\nextra\nmultilib\n'; }
multilib_enabled
pacman-conf() { [[ "$1" == --repo-list ]] && printf 'core\nextra\n'; }
if multilib_enabled; then printf 'BAD\n'; else printf 'MISSING\n'; fi
''')
        self.assertEqual(output.strip(), "MISSING")

    def test_cachyos_mirror_failure_does_not_refresh_arch_mirrors(self):
        source = function("prepare_base_install")
        self.assertIn("if is_cachyos_install; then", source)
        self.assertLess(source.index("if is_cachyos_install; then"), source.index("retry_command reflector"))
        self.assertIn("Leaving Arch and CachyOS mirrorlists unchanged", source)
        output = shell(function("is_cachyos_install") + r'''
pacman-conf() { [[ "$1" == --repo-list ]] && printf 'cachyos-v3\ncore\nextra\n'; }
is_cachyos_install && printf 'CACHYOS\n'
pacman-conf() { [[ "$1" == --repo-list ]] && printf 'core\nextra\n'; }
if is_cachyos_install; then printf 'BAD\n'; else printf 'ARCH\n'; fi
''')
        self.assertEqual(output.strip().splitlines(), ["CACHYOS", "ARCH"])

    def test_working_nvidia_is_not_replaced(self):
        output = shell(function("install_nvidia_auto") + r'''
DRY_RUN=0
log() { :; }
extract_pci_ids_for_vendor() { printf '1234\n'; }
nvidia_model_lines() { printf 'NVIDIA RTX 5070\n'; }
nvidia-smi() { :; }
timeout() { [[ "$2" == nvidia-smi && "$3" == -L ]]; }
remove_all_nvidia_packages() { printf 'DESTRUCTIVE\n'; return 99; }
install_nvidia_auto "NVIDIA RTX 5070"
printf 'PRESERVED\n'
''')
        self.assertEqual(output.strip(), "PRESERVED")

    def test_failed_nvidia_probe_retains_install_path(self):
        output = shell(function("install_nvidia_auto") + r'''
DRY_RUN=0
log() { :; }
extract_pci_ids_for_vendor() { printf '1234\n'; }
nvidia_model_lines() { printf 'NVIDIA RTX 5070\n'; }
nvidia-smi() { :; }
timeout() { return 1; }
remove_all_nvidia_packages() { printf 'REPLACE\n'; }
fetch_nvidia_legacy_html() { return 1; }
is_modern_nvidia() { return 0; }
install_nvidia_open_stack() { printf 'INSTALL\n'; }
configure_nvidia() { :; }
install_nvidia_auto "NVIDIA RTX 5070"
''')
        self.assertEqual(output.strip().splitlines(), ["REPLACE", "INSTALL"])

    def test_flatpak_other_scope_is_not_duplicated(self):
        output = shell(function("install_flatpak_apps_stage") + r'''
INSTALL_FLATPAK=1
HOME_DIR=/nonexistent/awtarchy-test-home
COLOR_YELLOW=
COLOR_RESET=
FLATPAK_SELECTED_IDS=(org.example.App)
FLATPAK_SELECTED_NAMES=(Example)
have() { [[ "$1" == flatpak ]]; }
flatpak_effective_scope_install() { printf 'user\n'; }
log() { printf 'LOG: %s\n' "$*"; }
warn() { :; }
run_flatpak_scope() {
  local scope="$1" op="$2"
  if [[ "$op" == remotes ]]; then printf 'flathub\n'; return 0; fi
  if [[ "$op" == list && "$scope" == system ]]; then printf 'org.example.App\n'; return 0; fi
  if [[ "$op" == install ]]; then printf 'DUPLICATE\n'; return 99; fi
  return 0
}
install_flatpak_apps_stage
''')
        self.assertIn("exists in system scope", output)
        self.assertNotIn("DUPLICATE", output)

    def test_stable_documentation(self):
        self.assertIn("awtarchy update", DOCS)
        self.assertNotIn(
            "awtarchy git update --branch investigate/cachyos-compatibility", DOCS
        )


if __name__ == "__main__":
    unittest.main()
