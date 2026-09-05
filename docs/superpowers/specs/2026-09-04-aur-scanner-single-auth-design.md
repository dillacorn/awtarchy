# aur-scanner Single-Authentication Install Design

## Goal

Make `aur-scan install` require one operator sudo authentication for the complete install transaction while preserving the security property that untrusted PKGBUILD code never inherits a reusable sudo credential.

## Proven current failure

`aur-scanner` 2.0.0 resolves and scans the complete AUR dependency graph, then invokes `makepkg -si` separately for each AUR package base. `makepkg -s` performs privileged dependency installation and `makepkg -i` performs privileged package installation. Arch makepkg deliberately invalidates sudo credentials before those pacman operations. A dependency chain therefore causes repeated password prompts inside one `aur-scan install` invocation.

The real Awtarchy test reproduced this with `hyprmoncfg-bin`: `xdg-terminal-exec` requested sudo for its package install, `hyprmoncfg-bin` requested sudo again, and the next selected AUR package requested sudo again for missing dependencies.

Awtarchy cannot safely solve this with a sudo keepalive, `PACMAN_AUTH=('sudo')`, password caching, or NOPASSWD rules because PKGBUILD code executes as the same user while those credentials would be reusable.

## Architecture

The privilege boundary belongs inside `aur-scanner`, because it owns the dependency graph, exact scanned build directories, build order, and generated package artifacts.

`aur-scan install` will start one privileged broker process after the scan gate and install consent have passed:

1. The normal unprivileged `aur-scan` process authenticates once using `/usr/bin/sudo` and starts a hidden broker mode of the same exact `aur-scan` executable with stdin/stdout pipes.
2. After the broker has started as root, the parent invalidates the user's normal sudo timestamp with `sudo -k`.
3. The parent installs official repository dependencies through the broker before any PKGBUILD build function runs.
4. Every AUR package is built unprivileged with plain `makepkg`, not `makepkg -s` or `makepkg -i`.
5. After a successful build exits, the parent identifies the expected package artifacts and asks the already-root broker to install them with pacman.
6. The broker exits at the end of the transaction or immediately on parent failure/interruption.

The root broker is not a general shell and never accepts arbitrary commands. It exposes only two protocol operations:

- install named official repository packages as dependencies;
- install local package archives produced under the approved `aur-scan` workspace.

## Security invariants

The implementation must preserve all existing `aur-scanner` scan and race-free build guarantees and add these invariants:

- Exactly one interactive sudo authentication is needed to start the broker.
- No valid user sudo timestamp remains while PKGBUILD build functions execute.
- PKGBUILD processes do not inherit the broker's stdin/stdout descriptors or an authorization secret.
- The broker executes only the absolute `/usr/bin/pacman` or `/bin/pacman` binary.
- Official repo dependency names are validated as legal package identifiers before broker execution.
- Local package paths must resolve inside the exact approved workspace and must be regular files, not symlinks.
- The broker copies local packages into a root-owned temporary staging directory before invoking pacman so a user process cannot swap the path after broker validation.
- AUR dependency package bases are installed before dependents according to the existing resolved topological order.
- A package base containing a user-requested root is installed explicitly; dependency-only package bases are installed with `--asdeps`.
- The hidden broker mode rejects direct invocation unless it is already running as root and receives a valid protocol setup from the parent.
- The normal build environment remains sanitized exactly as upstream currently requires. No `PACMAN_AUTH`, `SUDO_ASKPASS`, `LD_*`, `GIT_*`, `PKGDEST`, or other redirect vector is introduced.

## Broker protocol

The prototype uses a line-oriented JSON protocol over anonymous pipes. Each request carries a monotonically increasing numeric request id and one of these operations:

- `repo`: `{ "id": N, "op": "repo", "packages": ["pkg1", "pkg2"] }`
- `local`: `{ "id": N, "op": "local", "paths": ["/workspace/base/pkg.tar.zst"], "asdeps": true|false }`
- `finish`: `{ "id": N, "op": "finish" }`

The broker returns one JSON response per request: `{ "id": N, "ok": true }` or `{ "id": N, "ok": false, "error": "..." }`.

The protocol is deliberately private and version-local. It is not a public plugin API.

## Dependency installation

The existing dependency graph already tracks `depends`, `makedepends`, and `checkdepends`, and classifies nodes as AUR or official-repository/virtual. Before builds begin, the parent collects all concrete repo nodes and asks the broker to run:

`pacman -S --needed --asdeps --noconfirm <repo packages>`

Virtual dependencies that pacman cannot install by the graph name are allowed to fail closed rather than being guessed. If upstream resolution needs a provider-aware enhancement, that is a separate follow-up and must not weaken this transaction model.

## AUR build and installation

For each unique AUR package base in existing topological order:

1. Run sanitized `makepkg --noconfirm` from the exact directory that was scanned.
2. On success, run sanitized `makepkg --packagelist` from that same directory to obtain expected output archive paths.
3. Require at least one package archive and require every reported path to remain inside that package base directory/workspace.
4. Send those archive paths to the broker.
5. Install dependency-only package bases with `pacman -U --needed --asdeps --noconfirm` and root package bases with `pacman -U --needed --noconfirm`.

`makepkg --packagelist` is executed only after the user has passed the scan gate and approved building, so PKGBUILD evaluation at that stage is inside the existing execution boundary.

## Failure handling

- Broker startup failure aborts before any package build.
- Repo dependency installation failure aborts before any AUR build.
- A build failure aborts immediately and asks the broker to exit.
- Local package validation or pacman failure aborts immediately.
- Parent interruption closes the broker pipe; the broker treats EOF as termination and exits.
- Successful completion sends `finish`, waits for broker exit, then performs existing workspace cleanup.
- No failure path leaves a sudo keepalive process, sudoers modification, stored password, or persistent privileged service.

## Awtarchy integration

Awtarchy must not ship a custom privileged broker. During prototype validation it may carry the upstream patch and CI harness only.

After upstream behavior is proven, Awtarchy's package reconciler should:

- authenticate only when the user approves `Apply this package plan?` for trusted Arch/removal work;
- stop any Awtarchy sudo keepalive before invoking AUR code;
- invoke the broker-capable `aur-scan install` normally;
- rely on `aur-scanner` to own its one authentication and internal privilege separation;
- retain the notification-terminal detachment and low-root-space recovery independently.

Awtarchy main must not depend on this feature until either upstream merges/releases it or Awtarchy explicitly decides to carry a GPL-compliant patched `aur-scanner` build with corresponding source. The latter is not the preferred production path.

## Prototype and upstream delivery

Because the connected GitHub account has pull but not push permission to `KiefStudioMA/ks-aur-scanner`, the prototype is staged as a patch in Awtarchy. CI clones exact upstream commit `07893f5c1a71252a8c2b584016eb6e24627a249e`, applies the patch, and runs upstream formatting/tests.

Once the patch is green, create an upstream issue containing the reproduced failure, security rationale, design, and a link to the exact patch. Do not claim an upstream merge or release until upstream actually accepts it.
