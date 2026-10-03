#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/config/hypr/scripts/mic_noise_suppression.sh"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"
LAUNCHER="$ROOT/local/bin/awtarchy"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_absent() { [[ ! -e "$1" && ! -L "$1" ]] || fail "unexpected path remains: $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
test_root="$TMP/root"
home="$test_root/home"
fakebin="$TMP/bin"
package_state="$TMP/packages"
managed_packages="$TMP/managed-packages"
plugin="$TMP/plugin/librnnoise_ladspa.so"
source_state="$TMP/source-state"
service_log="$TMP/systemctl.log"
mkdir -p "$home" "$fakebin" "$(dirname "$plugin")"
: >"$package_state"
: >"$managed_packages"
: >"$source_state"
: >"$service_log"

cat >"$fakebin/sudo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${1:-} == -- ]] && shift
"$@"
EOF

cat >"$fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${AWTARCHY_MIC_TEST_PACKAGE_STATE:?}"
plugin="${AWTARCHY_MIC_TEST_PLUGIN_PATH:?}"
action="${1:-}"
shift || true
case "$action" in
  -Qq)
    pkg="${1:-}"
    [[ -n "$pkg" ]] || exit 1
    grep -Fxq "$pkg" "$state" && printf '%s\n' "$pkg"
    ;;
  -S)
    for pkg in "$@"; do
      [[ $pkg == -* ]] && continue
      grep -Fxq "$pkg" "$state" || printf '%s\n' "$pkg" >>"$state"
    done
    LC_ALL=C sort -u -o "$state" "$state"
    mkdir -p -- "$(dirname "$plugin")"
    : >"$plugin"
    ;;
  *) exit 44 ;;
esac
EOF

cat >"$fakebin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_MIC_TEST_SERVICE_LOG:?}"
state="${AWTARCHY_MIC_TEST_SOURCE_STATE:?}"
case "$*" in
  "--user is-active --quiet "* ) exit 0 ;;
  "--user daemon-reload"|"--user reset-failed") exit 0 ;;
  "--user restart "* )
    cfg="${HOME}/.config/pipewire/pipewire.conf.d/99-input-denoising.conf"
    if [[ -f "$cfg" ]] && grep -Fq 'node.name = "rnnoise_source"' "$cfg"; then
      printf '%s\n' rnnoise_source >"$state"
    else
      : >"$state"
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF

cat >"$fakebin/pactl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${AWTARCHY_MIC_TEST_SOURCE_STATE:?}"
case "${1:-}" in
  get-default-source)
    if grep -Fxq rnnoise_source "$state"; then printf '%s\n' rnnoise_source; else printf '%s\n' alsa_input.test_mono; fi
    ;;
  list)
    [[ ${2:-} == short && ${3:-} == sources ]] || exit 2
    if grep -Fxq rnnoise_source "$state"; then printf '1\trnnoise_source\tPipeWire\n'; fi
    printf '2\talsa_input.test_mono\tPipeWire\n'
    ;;
  info) printf 'Server Name: PulseAudio (on PipeWire test)\n' ;;
  *) exit 2 ;;
esac
EOF

cat >"$fakebin/wpctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${1:-} == status ]] || exit 2
printf 'PipeWire test graph\n'
EOF
chmod 0755 "$fakebin/"*

export PATH="$fakebin:$PATH"
export AWTARCHY_MIC_TEST_ROOT="$test_root"
export AWTARCHY_MIC_TEST_PACMAN_BIN="$fakebin/pacman"
export AWTARCHY_MIC_TEST_PLUGIN_PATH="$plugin"
export AWTARCHY_MIC_TEST_PACKAGE_STATE="$package_state"
export AWTARCHY_MIC_TEST_SOURCE_STATE="$source_state"
export AWTARCHY_MIC_TEST_SERVICE_LOG="$service_log"
export AWTARCHY_MANAGED_PACKAGES_FILE="$managed_packages"

run_helper() {
  local target_home="$1"
  shift
  HOME="$target_home" AWTARCHY_MIC_HOME="$target_home" "$HELPER" "$@"
}

cfg="$home/.config/pipewire/pipewire.conf.d/99-input-denoising.conf"
mono_output="$(run_helper "$home" mono 2>&1)" || { printf '%s\n' "$mono_output" >&2; fail "fresh mono enable failed"; }
grep -Fxq noise-suppression-for-voice "$package_state" || fail "RNNoise package was not installed"
grep -Fxq noise-suppression-for-voice "$managed_packages" || fail "RNNoise package ownership was not recorded"
assert_file "$plugin"
assert_file "$cfg"
grep -Fq '# Managed by Awtarchy: microphone-noise-suppression' "$cfg" || fail "managed marker missing"
grep -Fq 'label = noise_suppressor_mono' "$cfg" || fail "fresh setup is not mono"
! grep -Fq 'target.object' "$cfg" || fail "fresh setup hard-coded a physical microphone instead of using WirePlumber routing"
grep -Fxq rnnoise_source "$source_state" || fail "restart did not expose rnnoise_source"
grep -Fq 'restart pipewire.service wireplumber.service pipewire-pulse.service' "$service_log" || fail "audio stack was not restarted"
grep -Fq 'Active games, VOIP apps' <<<"$mono_output" || fail "restart warning does not identify active microphone/audio applications"
grep -Fq 'Restart microphone-using applications' <<<"$mono_output" || fail "post-change application restart warning missing"

run_helper "$home" stereo >/dev/null 2>&1 || fail "stereo switch failed"
grep -Fq 'label = noise_suppressor_stereo' "$cfg" || fail "stereo mode was not written"
! grep -Fq 'target.object' "$cfg" || fail "stereo switch unexpectedly pinned a physical microphone"

run_helper "$home" disable >/dev/null 2>&1 || fail "disable failed"
assert_absent "$cfg"
grep -Fxq noise-suppression-for-voice "$package_state" || fail "disable incorrectly uninstalled the package"
[[ ! -s "$source_state" ]] || fail "rnnoise_source survived disable/restart"

run_helper "$home" mono >/dev/null 2>&1 || fail "re-enable after disable failed"
grep -Fq 'label = noise_suppressor_mono' "$cfg" || fail "re-enabled config is not mono"

# Adopt a known-good pre-existing upstream-style config without destroying unrelated WirePlumber state.
home2="$test_root/home-existing"
cfg2="$home2/.config/pipewire/pipewire.conf.d/99-input-denoising.conf"
wp2="$home2/.config/wireplumber/wireplumber.conf.d/10-user-bluetooth.conf"
mkdir -p "$(dirname "$cfg2")" "$(dirname "$wp2")"
cat >"$cfg2" <<'EOF'
context.modules = [
{   name   = libpipewire-module-filter-chain
    args = {
        filter.graph = {
            nodes = [
                {
                    type = ladspa
                    plugin = /usr/lib/ladspa/librnnoise_ladspa.so
                    label = noise_suppressor_mono
                }
            ]
        }
        capture.props = {
            node.name = "capture.rnnoise_source"
            node.passive = true
            audio.rate = 48000
        }
        playback.props = {
            node.name = "rnnoise_source"
            media.class = Audio/Source
            audio.rate = 48000
        }
    }
}
]
EOF
printf 'user bluetooth config\n' >"$wp2"
printf '%s\n' rnnoise_source >"$source_state"
run_helper "$home2" is-configured || fail "known-good pre-existing RNNoise config was not recognized"
run_helper "$home2" stereo >/dev/null 2>&1 || fail "adopting existing config for stereo failed"
backup2="$home2/.local/state/awtarchy/mic-suppression/pre-awtarchy-99-input-denoising.conf"
assert_file "$backup2"
grep -Fq 'name   = libpipewire-module-filter-chain' "$backup2" || fail "original config backup was not preserved byte-for-byte enough to retain its syntax"
grep -Fq '# Managed by Awtarchy: microphone-noise-suppression' "$cfg2" || fail "adopted config was not marked managed"
grep -Fq 'label = noise_suppressor_stereo' "$cfg2" || fail "adopted config did not switch to stereo"
! grep -Fq 'target.object' "$cfg2" || fail "adopted auto-routing config gained a device-specific target"
grep -Fxq 'user bluetooth config' "$wp2" || fail "unrelated WirePlumber config was modified"
run_helper "$home2" disable >/dev/null 2>&1 || fail "disable after adoption failed"
assert_absent "$cfg2"
assert_file "$backup2"
grep -Fxq 'user bluetooth config' "$wp2" || fail "disable modified unrelated WirePlumber config"

# Refuse an unrelated config occupying the managed filename.
home3="$test_root/home-conflict"
cfg3="$home3/.config/pipewire/pipewire.conf.d/99-input-denoising.conf"
mkdir -p "$(dirname "$cfg3")"
printf 'unrelated = true\n' >"$cfg3"
if run_helper "$home3" mono >"$TMP/conflict.out" 2>&1; then fail "unrelated PipeWire config was overwritten"; fi
grep -Fxq 'unrelated = true' "$cfg3" || fail "conflicting config changed despite refusal"

# Installer/update/CLI integration contract.
grep -Fq 'RNNoise microphone suppression (mono, optional)' "$RUNTIME" || fail "installer questionnaire does not offer RNNoise"
grep -Fq 'configure_installer_mic_suppression_stage' "$RUNTIME" || fail "installer does not apply selected RNNoise setup"
grep -Fq 'maybe_offer_mic_suppression_update' "$RUNTIME" || fail "updater has no optional RNNoise setup path"
grep -Fq 'is-configured >/dev/null 2>&1' "$RUNTIME" || fail "updater does not skip the setup prompt for an existing healthy RNNoise graph"
grep -Fq 'active games, VOIP apps, browsers, OBS/recording software' "$RUNTIME" || fail "updater warning does not explain application restarts"
grep -Fq 'mic-suppression)' "$LAUNCHER" || fail "awtarchy command does not expose mic-suppression"
grep -Fq 'Enable / switch to Mono (recommended)' "$LAUNCHER" || fail "maintenance UI does not expose mono mode"
grep -Fq 'Enable / switch to Stereo' "$LAUNCHER" || fail "maintenance UI does not expose stereo mode"
grep -Fq 'Disable suppression' "$LAUNCHER" || fail "maintenance UI does not expose disable"

printf '%s\n' 'PASS: RNNoise install/adopt/mono/stereo/disable/re-enable lifecycle is guarded and testable.'
