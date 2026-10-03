# Awtarchy v3.8.8 Always Awake & RNNoise

Awtarchy v3.8.8 adds managed microphone noise suppression, persistent Always Awake behavior, and updater reliability improvements for GitHub connectivity.

## Install and update

- New installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)
- Existing Awtarchy users: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md) or run `awtarchy update`.

## Microphone noise suppression

- Adds optional RNNoise suppression using the official `noise-suppression-for-voice` package with a 48 kHz filter chain and mono as the default mode.
- Enabling or migrating RNNoise automatically selects `rnnoise_source` / **Noise Canceling source** as the default microphone.
- Awtarchy remembers the previous default microphone and restores it when suppression is disabled, while keeping capture routing device-agnostic and leaving unrelated PipeWire/WirePlumber configuration untouched.
- Explicit mono, stereo, disable, status, and restart controls are available through `awtarchy mic-suppression`, with warnings when the audio stack restart may require active applications to reconnect.

## Always Awake

- Always Awake can now be locked so it persists across logins and reboots.
- Unlocking persistence keeps the current Always Awake session active, while disabling Always Awake clears persistence.
- The locked state is visibly red/urgent, and the bar eye no longer keeps a persistent hover-style background when Always Awake is active.

## Updater reliability

- Interactive updater confirmations now accept only explicit `y` or `n`; invalid input re-prompts instead of being treated as a decision.
- Git-testing and updater branch resolution now prefer native Git remote lookup with GitHub REST fallback, reducing failures when `api.github.com` is temporarily slow or unreachable.
- REST fallback requests also use stronger timeout and retry handling for transient network failures.

## Validation

- PR #256 passed all triggered checks on exact feature head `07a33881d6394a233b63317fcd322a08467a6deb`, including the full **Validate Awtarchy**, updater, package, Quick Settings, bar, and idle-safety validation.
- The maintainer runtime-tested the RNNoise lifecycle with a real microphone, including install, mono/stereo switching, disable/re-enable, default-source migration, and final live microphone verification. Always Awake persistence was also confirmed across a real reboot before merge.
- Exact release target `43f6394adedc7b46bea43daa44ce675cbe1a2994` passed all 17 post-merge `main` push workflows, including **Validate Awtarchy**, **Validate Stable Release Notes**, **Validate Package Reconciler**, and the Quickshell lockscreen validation workflows.
