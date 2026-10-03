#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

BRANCH='feat/mic-suppression-always-awake-lock'
HEAD="${AWTARCHY_TEST_HEAD:?Set AWTARCHY_TEST_HEAD to the exact feature-branch commit SHA}"
BASE='9084b15e773a408e82e626a5e967f979c32b8211'
REPO='https://github.com/dillacorn/awtarchy.git'
PKG='noise-suppression-for-voice'
CFG="$HOME/.config/pipewire/pipewire.conf.d/99-input-denoising.conf"
MANIFEST='/var/lib/awtarchy/managed-packages'
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
IDLE="$HOME/.config/hypr/scripts/idle_inhibitor_global.sh"
AWT="$HOME/.local/bin/awtarchy"
BACKUP="$STATE_HOME/awtarchy/runtime-test-$(date +%Y%m%d-%H%M%S)"
BRANCH_CLI="$BACKUP/awtarchy-branch-cli"

CFG_WAS=0
PKG_WAS=0
MANIFEST_WAS=0
PKG_VERSION=''
PKG_ARCHIVE=''
DEFAULT_SOURCE=''
IDLE_MODE='unknown'
IDLE_PERSIST=0

banner() { printf '\n===== %s =====\n' "$*"; }
fail() { printf 'TEST FAILURE: %s\n' "$*" >&2; return 1; }

yn() {
  local a=''
  while true; do
    printf '%s [y/n] ' "$1" >/dev/tty
    IFS= read -r a </dev/tty || return 1
    case "$a" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) printf '%s\n' 'Please answer y or n.' >/dev/tty ;;
    esac
  done
}

pause_here() {
  local _
  printf '%s\nPress Enter to continue.\n' "$1" >/dev/tty
  IFS= read -r _ </dev/tty
}

rnnoise_present() {
  pactl list short sources 2>/dev/null |
    awk '$2 == "rnnoise_source" {print $2}' |
    grep -Fxq rnnoise_source
}

physical_source_present() {
  pactl list short sources 2>/dev/null |
    awk '$2 != "rnnoise_source" && $2 !~ /[.]monitor$/ {print $2}' |
    grep -q .
}

audio_healthy() {
  systemctl --user is-active --quiet pipewire.service &&
  systemctl --user is-active --quiet pipewire-pulse.service &&
  systemctl --user is-active --quiet wireplumber.service &&
  wpctl status >/dev/null &&
  pactl info >/dev/null
}

restart_audio() {
  systemctl --user daemon-reload
  systemctl --user reset-failed
  systemctl --user restart pipewire.service wireplumber.service pipewire-pulse.service
  sleep 1
  audio_healthy
}

show_audio() {
  systemctl --user --no-pager --full status \
    pipewire.service pipewire-pulse.service wireplumber.service || true
  printf '\n--- wpctl ---\n'
  wpctl status || true
  printf '\n--- pactl sources ---\n'
  pactl list short sources || true
  printf '\n--- default source ---\n'
  pactl get-default-source || true
}

snap_wp() {
  local out="$1" p
  : >"$out"
  if [[ -d "$HOME/.config/wireplumber" ]]; then
    while IFS= read -r -d '' p; do sha256sum -- "$p" >>"$out"; done \
      < <(find "$HOME/.config/wireplumber" -type f -print0 | sort -z)
    while IFS= read -r p; do
      printf 'LINK %s -> %s\n' "$p" "$(readlink -- "$p")" >>"$out"
    done < <(find "$HOME/.config/wireplumber" -type l -print | sort)
  else
    printf '<absent>\n' >"$out"
  fi
}

remote_sha() {
  local ref="$1" n out=''
  for n in 1 2 3; do
    out="$(git ls-remote --refs "$REPO" "$ref" 2>/dev/null || true)"
    if [[ -n "$out" ]]; then
      awk 'NR == 1 {print $1; exit}' <<<"$out"
      return 0
    fi
    sleep 1
  done
  return 1
}

restore_idle() {
  [[ -x "$IDLE" && ! -L "$IDLE" ]] || return 0
  case "$IDLE_MODE" in
    off|keep-awake|always-awake)
      "$IDLE" set-mode "$IDLE_MODE" || true
      if [[ "$IDLE_MODE" == always-awake && "$IDLE_PERSIST" == 1 ]]; then
        "$IDLE" lock-always-awake || true
      elif [[ "$IDLE_MODE" == always-awake ]]; then
        "$IDLE" unlock-always-awake || true
      fi
      ;;
  esac
}

recover() {
  banner 'RECOVERY TO PRE-TEST STATE'
  if (( CFG_WAS == 1 )); then
    mkdir -p -- "${CFG%/*}"
    cp -a -- "$BACKUP/original-rnnoise.conf" "$CFG" || true
  else
    rm -f -- "$CFG" || true
  fi

  if (( PKG_WAS == 1 )); then
    if ! pacman -Qq "$PKG" >/dev/null 2>&1; then
      if [[ -n "$PKG_ARCHIVE" && -f "$PKG_ARCHIVE" ]]; then
        sudo pacman -U --noconfirm "$PKG_ARCHIVE" || true
      else
        sudo pacman -S --needed --noconfirm "$PKG" || true
      fi
    fi
  elif pacman -Qq "$PKG" >/dev/null 2>&1; then
    sudo pacman -R --noconfirm "$PKG" || true
  fi

  if (( MANIFEST_WAS == 1 )); then
    sudo install -m 0644 "$BACKUP/managed-packages" "$MANIFEST" || true
  else
    sudo rm -f -- "$MANIFEST" || true
  fi

  restart_audio || true
  if [[ -n "$DEFAULT_SOURCE" ]] &&
     pactl list short sources | awk '{print $2}' | grep -Fxq "$DEFAULT_SOURCE"; then
    pactl set-default-source "$DEFAULT_SOURCE" || true
  fi
  restore_idle
  show_audio
  printf 'Recovery backup: %s\n' "$BACKUP"
}

prepare() {
  local c remote_head remote_main candidate q

  banner 'BEFORE STATE / SAFETY BACKUP'

  for c in pacman sudo systemctl wpctl pactl curl git sha256sum find diff awk grep sed; do
    command -v "$c" >/dev/null || { fail "Missing command: $c"; return 1; }
  done

  [[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || { fail 'Invalid exact test commit'; return 1; }
  [[ -x "$AWT" && ! -L "$AWT" ]] || { fail "Missing $AWT"; return 1; }

  remote_head="$(remote_sha "refs/heads/$BRANCH")" ||
    { fail 'Could not resolve feature branch after 3 attempts'; return 1; }
  remote_main="$(remote_sha refs/heads/main)" ||
    { fail 'Could not resolve main after 3 attempts'; return 1; }

  [[ "$remote_head" == "$HEAD" ]] ||
    { fail "Branch moved: $remote_head"; return 1; }
  [[ "$remote_main" == "$BASE" ]] ||
    { fail "main moved: $remote_main"; return 1; }

  printf 'Verified branch: %s@%s\n' "$BRANCH" "$HEAD"
  printf 'Verified main: %s\n' "$BASE"

  mkdir -p -- "$BACKUP"
  chmod 0700 "$BACKUP"

  curl --retry 5 --retry-all-errors --retry-delay 1 --max-time 120 -fsSL \
    -o "$BRANCH_CLI" \
    "https://raw.githubusercontent.com/dillacorn/awtarchy/$HEAD/local/bin/awtarchy"
  chmod 0700 "$BRANCH_CLI"
  bash -n "$BRANCH_CLI"
  grep -Fq -- '    --retry 3' "$BRANCH_CLI" ||
    { fail 'Staged branch launcher does not contain the updater retry fix'; return 1; }
  grep -Fq -- '    --retry-all-errors' "$BRANCH_CLI" ||
    { fail 'Staged branch launcher does not retry timeout/network errors'; return 1; }
  grep -Fq -- '      CURL_ARGS+=(--silent --max-time 20)' "$BRANCH_CLI" ||
    { fail 'Staged branch launcher does not contain the longer API timeout'; return 1; }

  [[ ! -L "$CFG" ]] || { fail "$CFG is a symlink"; return 1; }
  if [[ -e "$CFG" ]]; then
    [[ -f "$CFG" ]] || { fail "$CFG is not a regular file"; return 1; }
    grep -Fq '/usr/lib/ladspa/librnnoise_ladspa.so' "$CFG" ||
      { fail 'Unexpected RNNoise config'; return 1; }
    grep -Eq 'node[.]name[[:space:]]*=[[:space:]]*"rnnoise_source"[[:space:]]*$' "$CFG" ||
      { fail 'rnnoise_source missing from config'; return 1; }
    CFG_WAS=1
    cp -a -- "$CFG" "$BACKUP/original-rnnoise.conf"
  fi

  if pacman -Qq "$PKG" >/dev/null 2>&1; then
    PKG_WAS=1
    PKG_VERSION="$(pacman -Q "$PKG" | awk '{print $2}')"
    mkdir -p -- "$BACKUP/pkg"
    while IFS= read -r -d '' candidate; do
      q="$(pacman -Qp "$candidate" 2>/dev/null || true)"
      [[ "$q" == "$PKG $PKG_VERSION" ]] || continue
      cp -a -- "$candidate" "$BACKUP/pkg/"
      PKG_ARCHIVE="$BACKUP/pkg/${candidate##*/}"
      break
    done < <(find /var/cache/pacman/pkg -maxdepth 1 -type f \
      -name "${PKG}-*.pkg.tar.*" ! -name '*.sig' -print0 2>/dev/null)

    if [[ -z "$PKG_ARCHIVE" ]]; then
      sudo pacman -Sw --noconfirm --cachedir "$BACKUP/pkg" "$PKG"
      sudo chown -R "$(id -u):$(id -g)" "$BACKUP/pkg"
      while IFS= read -r -d '' candidate; do
        q="$(pacman -Qp "$candidate" 2>/dev/null || true)"
        [[ "$q" == "$PKG $PKG_VERSION" ]] || continue
        PKG_ARCHIVE="$candidate"
        break
      done < <(find "$BACKUP/pkg" -maxdepth 1 -type f \
        -name "${PKG}-*.pkg.tar.*" ! -name '*.sig' -print0)
    fi
    [[ -n "$PKG_ARCHIVE" && -f "$PKG_ARCHIVE" ]] ||
      { fail "No exact recovery package for $PKG_VERSION"; return 1; }
  fi

  if sudo test -f "$MANIFEST"; then
    MANIFEST_WAS=1
    sudo cp -a -- "$MANIFEST" "$BACKUP/managed-packages"
    sudo chown "$(id -u):$(id -g)" "$BACKUP/managed-packages"
  fi

  DEFAULT_SOURCE="$(pactl get-default-source 2>/dev/null || true)"
  if [[ -x "$IDLE" && ! -L "$IDLE" ]]; then
    IDLE_MODE="$("$IDLE" mode 2>/dev/null || printf unknown)"
    "$IDLE" is-persistent >/dev/null 2>&1 && IDLE_PERSIST=1
  fi

  snap_wp "$BACKUP/wireplumber.before"
  show_audio
  audio_healthy || { fail 'Audio unhealthy before test'; return 1; }
  physical_source_present || { fail 'No physical source'; return 1; }
  (( CFG_WAS == 0 )) || rnnoise_present ||
    { fail 'Configured rnnoise_source is not live'; return 1; }
}

run_test() {
  banner '1. REMOVE RNNOISE ONLY'
  yn 'Continue with destructive RNNoise lifecycle testing?' ||
    { fail 'Canceled before destructive changes'; return 1; }

  rm -f -- "$CFG"
  pacman -Qq "$PKG" >/dev/null 2>&1 && sudo pacman -R --noconfirm "$PKG"
  sudo test -f "$MANIFEST" &&
    sudo sed -i '\|^noise-suppression-for-voice$|d' -- "$MANIFEST"
  restart_audio

  [[ ! -e "$CFG" ]]
  ! pacman -Qq "$PKG" >/dev/null 2>&1
  ! rnnoise_present
  physical_source_present

  banner '2. EXACT GIT UPDATE / STRICT Y-N'
  printf '%s\n' \
    'At the RNNoise prompt type: yes' \
    'It MUST say: Please answer y or n.' \
    'Then type only: y'
  if ! AWTARCHY_SKIP_UPDATE_CHECK=1 "$BRANCH_CLI" git update --branch "$BRANCH" --commit "$HEAD"; then
    fail 'Exact Git-testing update failed; stopping before any follow-up assertions'
    return 1
  fi

  yn 'Did invalid input re-prompt, y enable RNNoise, and the audio-app restart warning appear?' ||
    { fail 'Updater strict y/n or warning failed'; return 1; }

  pacman -Q "$PKG"
  sudo grep -nFx "$PKG" "$MANIFEST"
  grep -Fq '# Managed by Awtarchy: microphone-noise-suppression' "$CFG"
  grep -Fq 'label = noise_suppressor_mono' "$CFG"
  (( $(grep -Fc 'audio.rate = 48000' "$CFG") >= 2 ))
  ! grep -Fq 'target.object' "$CFG"
  rnnoise_present
  physical_source_present
  audio_healthy
  [[ "$(pactl get-default-source)" == rnnoise_source ]] ||
    { fail 'Fresh RNNoise enable did not select rnnoise_source as the default microphone'; return 1; }

  banner '3. REAL MONO MIC'
  "$BRANCH_CLI" mic-suppression status
  show_audio
  pause_here 'Restart a mic app, select Noise Canceling source / rnnoise_source, and test the real Focusrite mono microphone.'
  yn 'Did the real mono microphone test pass?' ||
    { fail 'Mono microphone test failed'; return 1; }

  banner '4. STEREO CONFIG'
  "$BRANCH_CLI" mic-suppression stereo
  grep -Fq 'label = noise_suppressor_stereo' "$CFG"
  rnnoise_present
  audio_healthy

  banner '5. BACK TO MONO'
  "$BRANCH_CLI" mic-suppression mono
  grep -Fq 'label = noise_suppressor_mono' "$CFG"
  rnnoise_present
  audio_healthy

  banner '6. DISABLE / PACKAGE STAYS / WIREPLUMBER UNTOUCHED'
  snap_wp "$BACKUP/wireplumber.pre-disable"
  "$BRANCH_CLI" mic-suppression disable
  snap_wp "$BACKUP/wireplumber.post-disable"
  diff -u "$BACKUP/wireplumber.pre-disable" "$BACKUP/wireplumber.post-disable"
  [[ ! -e "$CFG" ]]
  pacman -Q "$PKG"
  ! rnnoise_present
  physical_source_present
  audio_healthy
  if [[ -n "$DEFAULT_SOURCE" ]] &&
     pactl list short sources | awk '{print $2}' | grep -Fxq "$DEFAULT_SOURCE"; then
    [[ "$(pactl get-default-source)" == "$DEFAULT_SOURCE" ]] ||
      { fail 'Disabling RNNoise did not restore the pre-test default microphone'; return 1; }
  fi

  banner '7. RE-ENABLE MONO'
  "$BRANCH_CLI" mic-suppression mono
  grep -Fq 'label = noise_suppressor_mono' "$CFG"
  rnnoise_present
  audio_healthy
  [[ "$(pactl get-default-source)" == rnnoise_source ]] ||
    { fail 'Re-enabling RNNoise did not select rnnoise_source as default'; return 1; }

  banner '8. HEALTHY SETUP UPDATE SKIP'
  if [[ -n "$DEFAULT_SOURCE" && "$DEFAULT_SOURCE" != rnnoise_source ]] &&
     pactl list short sources | awk '{print $2}' | grep -Fxq "$DEFAULT_SOURCE"; then
    pactl set-default-source "$DEFAULT_SOURCE"
    [[ "$(pactl get-default-source)" == "$DEFAULT_SOURCE" ]] ||
      { fail 'Could not stage the previous physical default for migration testing'; return 1; }
  fi
  if ! AWTARCHY_SKIP_UPDATE_CHECK=1 "$BRANCH_CLI" git update --branch "$BRANCH" --commit "$HEAD"; then
    fail 'Healthy-setup verification update failed; stopping and recovering'
    return 1
  fi
  yn 'Did the updater report RNNoise already configured and skip its setup question?' ||
    { fail 'Healthy setup skip failed'; return 1; }
  [[ "$(pactl get-default-source)" == rnnoise_source ]] ||
    { fail 'Healthy RNNoise updater migration did not repair the default microphone'; return 1; }

  banner '9. ALWAYS AWAKE UI'
  pause_here 'Turn Always Awake OFF. Confirm there is no lock icon.'
  [[ "$("$IDLE" mode)" == off ]]
  yn 'Was the lock icon absent?' || return 1

  pause_here 'Enable Always Awake without locking it. Confirm unlocked icon / normal color.'
  [[ "$("$IDLE" mode)" == always-awake ]]
  ! "$IDLE" is-persistent
  yn 'Was it unlocked with normal color?' || return 1

  pause_here 'Click the lock icon. Confirm locked red/urgent state.'
  "$IDLE" is-persistent
  yn 'Did it become locked and red/urgent?' || return 1

  banner '9A. PERSISTENCE BACKEND'
  local sim="$BACKUP/always-awake-sim"
  mkdir -p "$sim/config/hypr/scripts" "$sim/tests"
  cp -a "$IDLE" "$sim/config/hypr/scripts/idle_inhibitor_global.sh"
  curl --retry 3 --retry-all-errors -fsSL \
    -o "$sim/tests/test-always-awake-persistence.sh" \
    "https://raw.githubusercontent.com/dillacorn/awtarchy/$HEAD/tests/test-always-awake-persistence.sh"
  chmod 0700 "$sim/tests/test-always-awake-persistence.sh"
  bash "$sim/tests/test-always-awake-persistence.sh"

  pause_here 'Unlock the red lock but leave Always Awake enabled.'
  ! "$IDLE" is-persistent
  [[ "$("$IDLE" mode)" == always-awake ]]
  yn 'Did it return to unlocked/normal while staying active?' || return 1

  pause_here 'Turn Always Awake OFF. Confirm lock icon disappears.'
  [[ "$("$IDLE" mode)" == off ]]
  yn 'Did the lock icon disappear?' || return 1

  banner '10. FINAL MONO'
  "$BRANCH_CLI" mic-suppression mono
  grep -Fq 'label = noise_suppressor_mono' "$CFG"
  rnnoise_present
  physical_source_present
  audio_healthy
  pacman -Q "$PKG"
  sudo grep -nFx "$PKG" "$MANIFEST"

  snap_wp "$BACKUP/wireplumber.final"
  diff -u "$BACKUP/wireplumber.before" "$BACKUP/wireplumber.final"
  [[ "$(pactl get-default-source)" == rnnoise_source ]] ||
    { fail 'Final RNNoise state is not the default microphone'; return 1; }

  show_audio
  pause_here 'Restart the mic app one final time and test Noise Canceling source with the real mono microphone.'
  yn 'Did the final mono microphone test pass?' ||
    { fail 'Final mono test failed'; return 1; }

  restore_idle
  banner 'COMPLETE'
  printf 'Tested: %s@%s\nFinal RNNoise mode: mono\nFinal default microphone: rnnoise_source\nEvidence/recovery: %s\n' \
    "$BRANCH" "$HEAD" "$BACKUP"
}

main() {
  prepare || return 1
  if run_test; then
    return 0
  fi
  recover
  return 1
}

main
