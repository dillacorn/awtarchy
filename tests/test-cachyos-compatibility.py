#!/usr/bin/env python3
"""Non-destructive CachyOS installer compatibility regressions."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = (ROOT / "local/share/awtarchy/awtarchy-runtime.sh").read_text()
DOCS = (ROOT / "docs/cachyos-compatibility.md").read_text()
RECONCILER = (ROOT / "local/share/awtarchy/awtarchy-package-reconcile.sh").read_text()
BACKEND = (ROOT / "config/hypr/scripts/hypr_quicksettings.sh").read_text()


def function(name: str, source: str = RUNTIME) -> str:
    start = re.search(rf"(?m)^{re.escape(name)}\(\)\s*\{{", source)
    if start is None:
        raise AssertionError(f"Missing function: {name}")
    next_fn = re.search(r"(?m)^[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{", source[start.end():])
    end = len(source) if next_fn is None else start.end() + next_fn.start()
    return source[start.start():end]


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

    def test_cachyos_legacy_config_and_backups_are_preserved(self):
        output = shell(function("remove_legacy_shell_files_stage") + r'''
is_cachyos_install() { return 0; }
log() { printf 'PRESERVED\n'; }
remove_legacy_shell_path_stage() { printf 'REMOVED\n'; }
remove_legacy_shell_files_stage
''')
        self.assertEqual(output.strip(), "PRESERVED")

    def test_untracked_cachyos_packages_are_preserved(self):
        output = shell(function("remove_legacy_shell_packages_stage") + r'''
HOME_DIR=/nonexistent/awtarchy-test-home
AWTARCHY_MANAGED_PACKAGES_FILE=/nonexistent/awtarchy-managed-packages
is_cachyos_install() { return 0; }
log() { :; }
warn() { printf 'PRESERVED\n'; }
pacman() {
  if [[ "$1" == -Qq ]]; then printf 'waybar\n'; return 0; fi
  printf 'REMOVED\n'
}
remove_legacy_shell_packages_stage
''')
        self.assertEqual(output.strip(), "PRESERVED")

    def test_existing_display_manager_is_preserved(self):
        output = shell(function("install_ly_stage") + r'''
INSTALL_LY=1
systemctl() {
  [[ "$1" == is-enabled && "$2" == --quiet && "$3" == sddm.service ]]
}
warn() { printf 'PRESERVED\n'; }
install_ly_stage
''')
        self.assertEqual(output.strip(), "PRESERVED")

    def test_cachyos_network_stays_user_owned(self):
        source = function("install_arch_repo_apps_stage")
        reconcile = function("hardware_reconcile")
        self.assertIn('if is_cachyos_install; then', source)
        self.assertIn('preserving existing networking, DNS and mDNS services', source)
        self.assertIn('if ! is_cachyos_install; then\n    configure_mdns_stack', reconcile)

    def test_external_scheduler_survives_session_restore(self):
        output = shell(function("machine_scheduler_restore", BACKEND) + r'''
SCHED_EXT_RESTORE_ENABLED=1
SCHED_EXT_LAST_SELECTED=scx_p2dq
SCHED_EXT_RUNNING=scx_lavd
SCHED_EXT_ENABLED=1
sched_ext_state_load() { :; }
valid_scheduler() { return 0; }
refresh_sched_ext() { :; }
sched_ext_switch_or_start() { printf 'OVERWRITTEN\n'; }
machine_scheduler_restore
printf 'PRESERVED\n'
''')
        self.assertEqual(output.strip(), "PRESERVED")

    def test_package_dependency_provider_counts_as_installed(self):
        output = shell(function("package_satisfied", RECONCILER) + r'''
package_installed() { return 1; }
pacman() { [[ "$1" == -T && "$2" == quickshell ]]; }
package_satisfied quickshell
printf 'SATISFIED\n'
if package_satisfied missing-package; then
  printf 'FALSE POSITIVE\n'
fi
''')
        self.assertEqual(output.strip(), "SATISFIED")

    def test_stable_documentation(self):
        self.assertIn("awtarchy update", DOCS)
        self.assertNotIn(
            "awtarchy git update --branch investigate/cachyos-compatibility", DOCS
        )


if __name__ == "__main__":
    unittest.main()
