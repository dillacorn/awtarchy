# aur-scanner Single-Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce and validate an upstream-ready `aur-scanner` patch that authenticates once while keeping reusable sudo credentials out of PKGBUILD execution.

**Architecture:** Replace upstream `makepkg -si` per-package privilege escalation with an internal root pacman broker started once through sudo. The unprivileged parent installs repo dependencies through the broker, builds each scanned AUR package with plain makepkg, then asks the broker to install only the generated package archives.

**Tech Stack:** Rust 2021, Tokio, serde/serde_json, libc, pacman/makepkg, GitHub Actions, Bash/Python patch-generation harness.

**Spec:** `docs/superpowers/specs/2026-09-04-aur-scanner-single-auth-design.md`

## Global Constraints

- Prototype against exact upstream commit `07893f5c1a71252a8c2b584016eb6e24627a249e` (`aur-scanner` 2.0.0).
- Do not add NOPASSWD rules, password storage, `PACMAN_AUTH`, or sudo-ticket reuse across PKGBUILD execution.
- Do not merge Awtarchy PR #138 while the real one-password requirement remains unresolved.
- Awtarchy production must not ship the prototype as authoritative upstream code unless upstream accepts/releases it or GPL-compliant patched-source distribution is explicitly chosen later.
- Preserve upstream exact-directory scan/build ordering and sanitized build environment.

---

### Task 1: Build the upstream privilege-broker patch

**Files:**
- Create: `patches/aur-scanner/0001-single-auth-privileged-broker.patch`
- Create temporarily: `.github/workflows/apply-aur-scanner-broker-prototype.yml`
- Modify upstream in CI only: `crates/aur-scanner-cli/src/commands/install.rs`
- Modify upstream in CI only: `crates/aur-scanner-cli/src/main.rs`
- Modify upstream in CI only: `crates/aur-scanner-cli/Cargo.toml`

**Interfaces:**
- Consumes: upstream `DependencyGraph`, `DepKind`, `PackageSource`, existing `sanitized_build_env`, existing install topological order.
- Produces: hidden broker command, JSON broker request/response protocol, broker-backed repo/local package installs, build-only makepkg flow.

- [ ] **Step 1: Write failing upstream-focused tests in the transformation**

Add unit tests that require:

```rust
assert!(broker_mode_rejects_non_root());
assert!(workspace_local_path_validation_rejects_escape());
assert!(workspace_local_path_validation_rejects_symlink());
assert_eq!(package_base_install_reason(true), InstallReason::Explicit);
assert_eq!(package_base_install_reason(false), InstallReason::Dependency);
```

Add source-contract assertions in the Awtarchy harness that reject `cmd.arg("-si")`, `PACMAN_AUTH`, or a normal-build path containing `sudo`.

- [ ] **Step 2: Run the prototype workflow before production transformation and verify RED**

Expected: fail because upstream 2.0.0 still contains `makepkg -si` and has no broker implementation.

- [ ] **Step 3: Implement the minimal upstream transformation**

The generated patch must make these concrete changes:

```rust
// main.rs
#[command(hide = true)]
Broker {
    #[arg(long)]
    workspace: PathBuf,
}
```

```rust
// install.rs
#[derive(Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "lowercase")]
enum BrokerRequest {
    Repo { id: u64, packages: Vec<String> },
    Local { id: u64, paths: Vec<PathBuf>, asdeps: bool },
    Finish { id: u64 },
}

#[derive(Serialize, Deserialize)]
struct BrokerResponse {
    id: u64,
    ok: bool,
    error: Option<String>,
}
```

Start the broker with absolute `/usr/bin/sudo` or `/bin/sudo`, using the same exact current executable and piped stdin/stdout. After startup acknowledgement, run `sudo -k` in the parent.

Install repo graph leaves through broker before builds. Replace `makepkg -si` with sanitized plain `makepkg`, then sanitized `makepkg --packagelist`, and send only validated workspace package paths to broker pacman installation.

Add `libc.workspace = true` to the CLI crate and use `O_NOFOLLOW|O_CLOEXEC` when opening local package archives for root-owned staging.

- [ ] **Step 4: Run upstream validation**

Run in CI:

```bash
cargo fmt --all --check
cargo test -p aur-scanner-cli
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Expected: all pass.

- [ ] **Step 5: Commit the generated patch and remove the temporary applicator**

Commit only the patch plus permanent validation harness/docs. No temporary write-capable workflow remains.

---

### Task 2: Add permanent reproducible upstream-patch CI

**Files:**
- Create: `.github/workflows/validate-aur-scanner-privileged-broker.yml`
- Create: `tests/test-aur-scanner-privileged-broker-patch.sh`

**Interfaces:**
- Consumes: exact upstream commit and patch from Task 1.
- Produces: deterministic proof the patch applies and upstream Rust validation passes.

- [ ] **Step 1: Write the permanent shell contract test**

The test must require the patch to contain all of:

```text
BrokerRequest
BrokerResponse
--packagelist
O_NOFOLLOW
sudo -k
pacman
```

and reject all of:

```text
PACMAN_AUTH
SUDO_ASKPASS
NOPASSWD
cmd.arg("-si")
```

- [ ] **Step 2: Verify the test fails if the patch is absent or contains `makepkg -si`**

Run:

```bash
bash tests/test-aur-scanner-privileged-broker-patch.sh
```

Expected pre-patch: non-zero.

- [ ] **Step 3: Add the permanent workflow**

Workflow steps:

```bash
git clone https://github.com/KiefStudioMA/ks-aur-scanner.git upstream
git -C upstream checkout 07893f5c1a71252a8c2b584016eb6e24627a249e
git -C upstream apply "$GITHUB_WORKSPACE/patches/aur-scanner/0001-single-auth-privileged-broker.patch"
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

- [ ] **Step 4: Verify GREEN on the exact Awtarchy branch head**

Expected: shell contract and upstream Rust validation both pass.

- [ ] **Step 5: Commit permanent validation**

Commit the workflow and shell test.

---

### Task 3: Publish the upstream request with reproducible evidence

**Files:**
- No upstream code write is possible from the connected GitHub account.
- Update: upstream GitHub issue in `KiefStudioMA/ks-aur-scanner`.

**Interfaces:**
- Consumes: exact green Awtarchy patch commit and real Awtarchy terminal reproduction.
- Produces: upstream issue containing problem statement, security reasoning, design, patch link, and validation evidence.

- [ ] **Step 1: Confirm no duplicate upstream issue/PR exists**

Search for repeated sudo/password/makepkg install privilege separation.

- [ ] **Step 2: Create the upstream issue**

Issue must state:

```text
Current `aur-scan install` invokes `makepkg -si` once per AUR package base.
This causes repeated sudo prompts because makepkg deliberately invalidates sudo
before pacman operations. Preserving a sudo ticket across PKGBUILD execution is
not an acceptable workaround.
```

Include exact real reproduction and link to the green prototype patch.

- [ ] **Step 3: Do not claim merge/release**

Record upstream issue URL only. Production Awtarchy integration remains gated on an accepted upstream capability or an explicit decision to distribute the patched GPL source.

---

### Task 4: Reconcile Awtarchy PR #138 after upstream prototype proof

**Files:**
- Modify: `local/bin/awtarchy`
- Modify: `local/share/awtarchy/awtarchy-package-reconcile.sh`
- Modify: `tests/test-awtarchy-update-session.sh`
- Modify: PR #138 metadata/branch

**Interfaces:**
- Consumes: proven broker architecture from Tasks 1-3.
- Produces: Awtarchy behavior that keeps notification detachment and low-disk recovery but does not fake one-password AUR behavior with sudo keepalives.

- [ ] **Step 1: Write regression expectations**

Require Awtarchy authentication only after `Apply this package plan?`, prohibit reusable sudo authorization across `aur-scan install`, and retain low-disk recovery/notification detachment.

- [ ] **Step 2: Remove failed AUR sudo workaround**

Remove Awtarchy per-package `sudo -k` choreography and any claim that Awtarchy itself can collapse upstream makepkg prompts.

- [ ] **Step 3: Keep independent fixes**

Preserve:

```text
notification terminal detachment
paccache -rk2 low-root-space recovery
post-reconciliation disk recheck
```

- [ ] **Step 4: Run Awtarchy validation**

Run relevant focused workflows and full `Validate Awtarchy`.

- [ ] **Step 5: Leave PR unmerged pending real-machine validation**

Do not merge until the user tests the exact final branch head.
