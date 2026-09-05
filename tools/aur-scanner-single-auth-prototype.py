#!/usr/bin/env python3
"""Apply the single-auth privileged-broker prototype to ks-aur-scanner 2.0.0.

This is a patch-generation/testing tool, not Awtarchy production runtime code.
It expects exact upstream commit 07893f5c1a71252a8c2b584016eb6e24627a249e.
"""

from __future__ import annotations

import pathlib
import sys

UPSTREAM = "07893f5c1a71252a8c2b584016eb6e24627a249e"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def patch_cargo(root: pathlib.Path) -> None:
    path = root / "crates/aur-scanner-cli/Cargo.toml"
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        'dirs = "5.0"\n',
        'dirs = "5.0"\nlibc.workspace = true\ntempfile = "3.14"\n',
        "cli libc dependency",
    )
    path.write_text(text, encoding="utf-8")


def patch_main(root: pathlib.Path) -> None:
    path = root / "crates/aur-scanner-cli/src/main.rs"
    text = path.read_text(encoding="utf-8")

    install_tail = '''        #[arg(long)]
        keep_build: bool,
    },

    /// Scan all installed AUR packages on the system
'''
    install_tail_new = '''        #[arg(long)]
        keep_build: bool,
    },

    /// Internal root-only pacman broker used by `aur-scan install`.
    #[command(name = "__broker", hide = true)]
    Broker {
        /// Exact aur-scan workspace approved by the unprivileged parent.
        #[arg(long)]
        workspace: PathBuf,
    },

    /// Scan all installed AUR packages on the system
'''
    text = replace_once(text, install_tail, install_tail_new, "hidden broker command")

    dispatch = '''        Commands::System { rescan, cache_dir } => {
'''
    dispatch_new = '''        Commands::Broker { workspace } => commands::install::run_broker(workspace),
        Commands::System { rescan, cache_dir } => {
'''
    text = replace_once(text, dispatch, dispatch_new, "broker dispatch")
    path.write_text(text, encoding="utf-8")


def patch_install(root: pathlib.Path) -> None:
    path = root / "crates/aur-scanner-cli/src/commands/install.rs"
    text = path.read_text(encoding="utf-8")

    imports = '''use anyhow::{Context, Result};
use colored::Colorize;
use std::collections::BTreeMap;
use std::io::{self, IsTerminal, Write};
use std::path::PathBuf;
'''
    imports_new = '''use anyhow::{Context, Result};
use colored::Colorize;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, BufReader, BufWriter, IsTerminal, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
'''
    text = replace_once(text, imports, imports_new, "install imports")

    marker = '''pub async fn run(args: InstallArgs) -> Result<()> {
'''
    helpers = r'''#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "lowercase")]
enum BrokerRequest {
    Repo {
        id: u64,
        packages: Vec<String>,
    },
    Local {
        id: u64,
        paths: Vec<PathBuf>,
        asdeps: bool,
    },
    Finish {
        id: u64,
    },
}

impl BrokerRequest {
    fn id(&self) -> u64 {
        match self {
            Self::Repo { id, .. } | Self::Local { id, .. } | Self::Finish { id } => *id,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct BrokerResponse {
    id: u64,
    ok: bool,
    error: Option<String>,
}

struct BrokerClient {
    child: Child,
    stdin: Option<BufWriter<ChildStdin>>,
    stdout: BufReader<ChildStdout>,
    next_id: u64,
    finished: bool,
}

fn absolute_binary(candidates: &[&'static str], label: &str) -> Result<&'static str> {
    candidates
        .iter()
        .find(|path| Path::new(path).is_file())
        .copied()
        .with_context(|| format!("required {label} binary is unavailable"))
}

fn require_trusted_current_exe() -> Result<PathBuf> {
    let exe = std::env::current_exe().context("resolving current aur-scan executable")?;
    let meta = fs::metadata(&exe).with_context(|| format!("stat {}", exe.display()))?;
    let mode = meta.permissions().mode();
    if meta.uid() != 0 || mode & 0o022 != 0 {
        anyhow::bail!(
            "single-auth install requires a root-owned aur-scan executable that is not group/world writable: {}",
            exe.display()
        );
    }
    Ok(exe)
}

fn set_cloexec(fd: i32) -> Result<()> {
    // SAFETY: fcntl operates on a valid owned descriptor and does not retain it.
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFD) };
    if flags < 0 {
        return Err(io::Error::last_os_error()).context("reading descriptor flags");
    }
    // SAFETY: same descriptor contract as above.
    if unsafe { libc::fcntl(fd, libc::F_SETFD, flags | libc::FD_CLOEXEC) } < 0 {
        return Err(io::Error::last_os_error()).context("setting FD_CLOEXEC");
    }
    Ok(())
}

fn disable_same_uid_process_inspection() -> Result<()> {
    // PKGBUILD code runs as the same uid as the aur-scan parent. Mark the parent
    // non-dumpable so descendants cannot inspect its broker descriptors/memory
    // through ptrace-style /proc access while untrusted build functions run.
    // SAFETY: PR_SET_DUMPABLE accepts the integer value 0 and has no pointer args.
    if unsafe { libc::prctl(libc::PR_SET_DUMPABLE, 0, 0, 0, 0) } != 0 {
        return Err(io::Error::last_os_error()).context("disabling same-uid process inspection");
    }
    Ok(())
}

impl BrokerClient {
    fn start(workspace: &Path) -> Result<Self> {
        let sudo = absolute_binary(&["/usr/bin/sudo", "/bin/sudo"], "sudo")?;
        let exe = require_trusted_current_exe()?;

        let auth = Command::new(sudo)
            .arg("-v")
            .status()
            .context("starting sudo authentication for aur-scan install")?;
        if !auth.success() {
            anyhow::bail!("sudo authentication failed; no AUR package was built");
        }

        let mut child = Command::new(sudo)
            .args(["-n", "--"])
            .arg(&exe)
            .arg("__broker")
            .arg("--workspace")
            .arg(workspace)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .context("starting privileged pacman broker")?;

        let child_stdin = child
            .stdin
            .take()
            .context("privileged broker stdin was not created")?;
        let child_stdout = child
            .stdout
            .take()
            .context("privileged broker stdout was not created")?;
        set_cloexec(child_stdin.as_raw_fd())?;
        set_cloexec(child_stdout.as_raw_fd())?;

        let mut client = Self {
            child,
            stdin: Some(BufWriter::new(child_stdin)),
            stdout: BufReader::new(child_stdout),
            next_id: 1,
            finished: false,
        };
        client.read_response(0)?;

        let invalidate = Command::new(sudo)
            .arg("-k")
            .status()
            .context("invalidating normal sudo timestamp before PKGBUILD execution")?;
        if !invalidate.success() {
            anyhow::bail!("failed to invalidate normal sudo timestamp before PKGBUILD execution");
        }
        disable_same_uid_process_inspection()?;
        Ok(client)
    }

    fn read_response(&mut self, expected_id: u64) -> Result<()> {
        let mut line = String::new();
        let read = self
            .stdout
            .read_line(&mut line)
            .context("reading privileged broker response")?;
        if read == 0 {
            anyhow::bail!("privileged broker exited without a response");
        }
        let response: BrokerResponse =
            serde_json::from_str(&line).context("decoding privileged broker response")?;
        if response.id != expected_id {
            anyhow::bail!(
                "privileged broker response id mismatch: expected {expected_id}, got {}",
                response.id
            );
        }
        if !response.ok {
            anyhow::bail!(
                "privileged broker rejected request {expected_id}: {}",
                response.error.as_deref().unwrap_or("unknown broker error")
            );
        }
        Ok(())
    }

    fn request(&mut self, request: BrokerRequest) -> Result<()> {
        let id = request.id();
        let writer = self
            .stdin
            .as_mut()
            .context("privileged broker is already closed")?;
        serde_json::to_writer(&mut *writer, &request).context("encoding privileged broker request")?;
        writer.write_all(b"\n").context("writing privileged broker request")?;
        writer.flush().context("flushing privileged broker request")?;
        self.read_response(id)
    }

    fn install_repo(&mut self, packages: Vec<String>) -> Result<()> {
        if packages.is_empty() {
            return Ok(());
        }
        let id = self.next_id;
        self.next_id += 1;
        self.request(BrokerRequest::Repo { id, packages })
    }

    fn install_local(&mut self, paths: Vec<PathBuf>, asdeps: bool) -> Result<()> {
        if paths.is_empty() {
            anyhow::bail!("makepkg reported no package archives to install");
        }
        let id = self.next_id;
        self.next_id += 1;
        self.request(BrokerRequest::Local { id, paths, asdeps })
    }

    fn finish(mut self) -> Result<()> {
        let id = self.next_id;
        self.request(BrokerRequest::Finish { id })?;
        self.stdin.take();
        let status = self.child.wait().context("waiting for privileged broker")?;
        if !status.success() {
            anyhow::bail!("privileged broker exited with {status}");
        }
        self.finished = true;
        Ok(())
    }
}

impl Drop for BrokerClient {
    fn drop(&mut self) {
        if self.finished {
            return;
        }
        self.stdin.take();
        let _ = self.child.wait();
    }
}

fn broker_response<W: Write>(writer: &mut W, id: u64, result: Result<()>) -> Result<bool> {
    let (ok, error) = match result {
        Ok(()) => (true, None),
        Err(err) => (false, Some(format!("{err:#}"))),
    };
    let response = BrokerResponse { id, ok, error };
    serde_json::to_writer(&mut *writer, &response).context("encoding broker response")?;
    writer.write_all(b"\n").context("writing broker response")?;
    writer.flush().context("flushing broker response")?;
    Ok(ok)
}

fn pacman_stdio(command: &mut Command) -> Result<()> {
    command.stdin(Stdio::null());
    let terminal = OpenOptions::new()
        .read(true)
        .write(true)
        .open("/dev/tty")
        .or_else(|_| OpenOptions::new().write(true).open("/dev/stderr"))
        .context("opening terminal output for pacman")?;
    command.stdout(Stdio::from(terminal.try_clone()?));
    command.stderr(Stdio::from(terminal));
    Ok(())
}

fn broker_install_repo(packages: &[String]) -> Result<()> {
    if packages.is_empty() {
        return Ok(());
    }
    for package in packages {
        validate_package_name(package)
            .with_context(|| format!("refusing illegal repository dependency {package:?}"))?;
    }
    let pacman = absolute_binary(&["/usr/bin/pacman", "/bin/pacman"], "pacman")?;
    let mut command = Command::new(pacman);
    command.args(["-S", "--needed", "--asdeps", "--noconfirm", "--"]);
    command.args(packages);
    pacman_stdio(&mut command)?;
    let status = command.status().context("installing official repository dependencies")?;
    if !status.success() {
        anyhow::bail!("pacman failed while installing official repository dependencies");
    }
    Ok(())
}

fn stage_local_package(
    workspace: &Path,
    staging: &Path,
    request_id: u64,
    index: usize,
    path: &Path,
) -> Result<PathBuf> {
    if !path.is_absolute() {
        anyhow::bail!("local package path is not absolute: {}", path.display());
    }
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .context("local package path has no valid filename")?;
    if !file_name.contains(".pkg.tar.") {
        anyhow::bail!("refusing non-package local archive: {}", path.display());
    }

    let mut source = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(path)
        .with_context(|| format!("opening local package {}", path.display()))?;
    let metadata = source.metadata().context("reading local package metadata")?;
    if !metadata.is_file() {
        anyhow::bail!("local package is not a regular file: {}", path.display());
    }

    let fd_path = PathBuf::from(format!("/proc/self/fd/{}", source.as_raw_fd()));
    let actual = fs::canonicalize(&fd_path)
        .with_context(|| format!("resolving opened package {}", path.display()))?;
    if !actual.starts_with(workspace) {
        anyhow::bail!(
            "local package escaped approved workspace: {}",
            actual.display()
        );
    }

    let staged = staging.join(format!("{request_id}-{index}-{file_name}"));
    let mut destination = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&staged)
        .with_context(|| format!("creating root-owned staged package {}", staged.display()))?;
    io::copy(&mut source, &mut destination).context("copying package into root-owned staging")?;
    destination.sync_all().context("syncing staged package")?;
    Ok(staged)
}

fn broker_install_local(
    workspace: &Path,
    staging: &Path,
    request_id: u64,
    paths: &[PathBuf],
    asdeps: bool,
) -> Result<()> {
    if paths.is_empty() {
        anyhow::bail!("local install request contains no package paths");
    }
    let mut staged = Vec::with_capacity(paths.len());
    for (index, path) in paths.iter().enumerate() {
        staged.push(stage_local_package(workspace, staging, request_id, index, path)?);
    }

    let pacman = absolute_binary(&["/usr/bin/pacman", "/bin/pacman"], "pacman")?;
    let mut command = Command::new(pacman);
    command.args(["-U", "--needed", "--noconfirm"]);
    if asdeps {
        command.arg("--asdeps");
    }
    command.arg("--");
    command.args(&staged);
    pacman_stdio(&mut command)?;
    let status = command.status().context("installing built AUR packages")?;
    for path in &staged {
        let _ = fs::remove_file(path);
    }
    if !status.success() {
        anyhow::bail!("pacman failed while installing built AUR package archives");
    }
    Ok(())
}

pub fn run_broker(workspace: PathBuf) -> Result<()> {
    // SAFETY: geteuid has no arguments or memory-safety preconditions.
    if unsafe { libc::geteuid() } != 0 {
        anyhow::bail!("internal pacman broker must run as root");
    }
    let workspace = fs::canonicalize(&workspace)
        .with_context(|| format!("canonicalizing broker workspace {}", workspace.display()))?;
    if !workspace.is_dir() {
        anyhow::bail!("broker workspace is not a directory: {}", workspace.display());
    }

    let staging = tempfile::Builder::new()
        .prefix("aur-scan-broker-")
        .tempdir_in("/var/tmp")
        .context("creating secure root broker staging directory in /var/tmp")?;

    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut reader = BufReader::new(stdin.lock());
    let mut writer = BufWriter::new(stdout.lock());
    broker_response(&mut writer, 0, Ok(()))?;

    let result = (|| -> Result<()> {
        let mut line = String::new();
        loop {
            line.clear();
            if reader.read_line(&mut line).context("reading broker request")? == 0 {
                break;
            }
            let request: BrokerRequest =
                serde_json::from_str(&line).context("decoding broker request")?;
            let id = request.id();
            let finish = matches!(request, BrokerRequest::Finish { .. });
            let operation = match request {
                BrokerRequest::Repo { packages, .. } => broker_install_repo(&packages),
                BrokerRequest::Local {
                    paths, asdeps, ..
                } => broker_install_local(&workspace, staging.path(), id, &paths, asdeps),
                BrokerRequest::Finish { .. } => Ok(()),
            };
            let ok = broker_response(&mut writer, id, operation)?;
            if !ok || finish {
                break;
            }
        }
        Ok(())
    })();
    result
}

fn package_base_is_explicit(
    graph: &depgraph::DependencyGraph,
    node_base: &BTreeMap<String, String>,
    base: &str,
) -> bool {
    graph.nodes.values().any(|node| {
        node_base.get(&node.name).is_some_and(|value| value == base)
            && node.kinds.contains(&depgraph::DepKind::Root)
    })
}

fn package_paths_from_packagelist(output: &[u8], base_dir: &Path) -> Result<Vec<PathBuf>> {
    let canonical_base = fs::canonicalize(base_dir)
        .with_context(|| format!("canonicalizing scanned base directory {}", base_dir.display()))?;
    let text = std::str::from_utf8(output).context("makepkg --packagelist returned non-UTF-8 output")?;
    let mut paths = Vec::new();
    for line in text.lines().map(str::trim).filter(|line| !line.is_empty()) {
        let path = PathBuf::from(line);
        if !path.is_absolute() {
            anyhow::bail!("makepkg --packagelist returned non-absolute path: {line}");
        }
        let parent = path.parent().context("package list path has no parent")?;
        let canonical_parent = fs::canonicalize(parent)
            .with_context(|| format!("canonicalizing package output parent {}", parent.display()))?;
        if !canonical_parent.starts_with(&canonical_base) {
            anyhow::bail!("makepkg package output escaped scanned base directory: {line}");
        }
        paths.push(path);
    }
    if paths.is_empty() {
        anyhow::bail!("makepkg --packagelist returned no package archives");
    }
    Ok(paths)
}

pub async fn run(args: InstallArgs) -> Result<()> {
'''
    text = replace_once(text, marker, helpers, "broker helper insertion")

    old_loop_start = '''    let order = depgraph::topo_order(&graph);
    let mut built: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
'''
    loop_start = text.find(old_loop_start)
    if loop_start < 0:
        raise SystemExit("build loop start marker missing")
    cleanup_marker = '''    // 6. Tidy up after a successful install: remove the per-package build dirs we
'''
    loop_end = text.find(cleanup_marker, loop_start)
    if loop_end < 0:
        raise SystemExit("build loop end marker missing")

    new_loop = r'''    let mut broker = BrokerClient::start(&workspace)?;

    let repo_packages: Vec<String> = graph
        .nodes
        .values()
        .filter(|node| node.source == depgraph::PackageSource::Repo)
        .map(|node| node.name.clone())
        .collect();
    broker.install_repo(repo_packages)?;

    let order = depgraph::topo_order(&graph);
    let mut built: BTreeSet<String> = BTreeSet::new();
    for name in &order {
        let base = match node_base.get(name) {
            Some(b) => b.clone(),
            None => continue,
        };
        if !built.insert(base.clone()) {
            continue; // base already built (split package / shared)
        }
        let dir = match base_dirs.get(&base) {
            Some(d) if d.join("PKGBUILD").is_file() => d.clone(),
            _ => {
                eprintln!("{} {} not fetched; skipping", "warning:".yellow(), base);
                continue;
            }
        };
        println!();
        println!("{} {}", "Building:".cyan().bold(), base.white().bold());
        // Resolve makepkg to an absolute path rather than letting it be looked
        // up relative to the attacker-controlled package directory.
        let makepkg_bin = absolute_binary(&["/usr/bin/makepkg", "/bin/makepkg"], "makepkg")?;
        let pkgdest = dir.join(".aur-scan-pkgdest");
        fs::create_dir_all(&pkgdest)
            .with_context(|| format!("creating trusted package output dir {}", pkgdest.display()))?;

        let mut cmd = tokio::process::Command::new(makepkg_bin);
        cmd.current_dir(&dir);
        cmd.env_clear();
        for (k, v) in sanitized_build_env(std::env::vars()) {
            cmd.env(k, v);
        }
        // Trusted override selected by aur-scan, not inherited from the ambient
        // environment. Keeping artifacts under the scanned base lets the broker
        // enforce a strict workspace boundary.
        cmd.env("PKGDEST", &pkgdest);
        if args.noconfirm {
            cmd.arg("--noconfirm");
        }
        let status = cmd.status().await.context("failed to launch makepkg")?;
        if !status.success() {
            anyhow::bail!(
                "makepkg failed for '{}' (exit {:?}); stopping. Built so far: {}",
                base,
                status.code(),
                built
                    .iter()
                    .filter(|b| *b != &base)
                    .cloned()
                    .collect::<Vec<_>>()
                    .join(", ")
            );
        }

        let mut list_cmd = tokio::process::Command::new(makepkg_bin);
        list_cmd.arg("--packagelist").current_dir(&dir);
        list_cmd.env_clear();
        for (k, v) in sanitized_build_env(std::env::vars()) {
            list_cmd.env(k, v);
        }
        list_cmd.env("PKGDEST", &pkgdest);
        let output = list_cmd
            .output()
            .await
            .context("failed to run makepkg --packagelist")?;
        if !output.status.success() {
            anyhow::bail!("makepkg --packagelist failed for '{base}'");
        }
        let paths = package_paths_from_packagelist(&output.stdout, &dir)?;
        let asdeps = !package_base_is_explicit(&graph, &node_base, &base);
        broker.install_local(paths, asdeps)?;
    }

    broker.finish()?;

'''
    text = text[:loop_start] + new_loop + text[loop_end:]

    tests_end = '''    #[test]
    fn build_env_keeps_safe_passthroughs() {
'''
    if tests_end not in text:
        raise SystemExit("test insertion marker missing")
    extra_tests = r'''    #[test]
    fn packagelist_rejects_output_outside_scanned_base() {
        let base = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        let artifact = outside.path().join("escape.pkg.tar.zst");
        std::fs::write(&artifact, b"pkg").unwrap();
        let output = format!("{}\n", artifact.display());
        assert!(package_paths_from_packagelist(output.as_bytes(), base.path()).is_err());
    }

    #[test]
    fn local_package_staging_rejects_symlink() {
        use std::os::unix::fs::symlink;

        let workspace = tempfile::tempdir().unwrap();
        let staging = tempfile::tempdir().unwrap();
        let real = workspace.path().join("real.pkg.tar.zst");
        let link = workspace.path().join("link.pkg.tar.zst");
        std::fs::write(&real, b"pkg").unwrap();
        symlink(&real, &link).unwrap();
        assert!(stage_local_package(
            workspace.path(),
            staging.path(),
            1,
            0,
            &link,
        )
        .is_err());
    }

    #[test]
    fn package_base_root_is_explicit() {
        use aur_scanner_core::depgraph::{DepKind, DependencyGraph, PackageNode, PackageSource};
        let mut nodes = BTreeMap::new();
        nodes.insert(
            "root".to_string(),
            PackageNode {
                name: "root".to_string(),
                version: None,
                source: PackageSource::Aur,
                package_base: Some("root-base".to_string()),
                maintainer: None,
                orphaned: false,
                depends: vec![],
                kinds: vec![DepKind::Root],
                depth: 0,
            },
        );
        let graph = DependencyGraph {
            roots: vec!["root".to_string()],
            nodes,
            truncated: vec![],
        };
        let node_base = BTreeMap::from([("root".to_string(), "root-base".to_string())]);
        assert!(package_base_is_explicit(&graph, &node_base, "root-base"));
    }

    #[test]
    fn dependency_only_base_is_asdeps() {
        use aur_scanner_core::depgraph::{DepKind, DependencyGraph, PackageNode, PackageSource};
        let mut nodes = BTreeMap::new();
        nodes.insert(
            "dep".to_string(),
            PackageNode {
                name: "dep".to_string(),
                version: None,
                source: PackageSource::Aur,
                package_base: Some("dep-base".to_string()),
                maintainer: None,
                orphaned: false,
                depends: vec![],
                kinds: vec![DepKind::Runtime],
                depth: 1,
            },
        );
        let graph = DependencyGraph {
            roots: vec!["root".to_string()],
            nodes,
            truncated: vec![],
        };
        let node_base = BTreeMap::from([("dep".to_string(), "dep-base".to_string())]);
        assert!(!package_base_is_explicit(&graph, &node_base, "dep-base"));
    }

'''
    text = replace_once(text, tests_end, extra_tests + tests_end, "broker unit tests")

    path.write_text(text, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <ks-aur-scanner-root>", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    if not (root / "Cargo.toml").is_file():
        raise SystemExit(f"not a ks-aur-scanner checkout: {root}")
    patch_cargo(root)
    patch_main(root)
    patch_install(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
