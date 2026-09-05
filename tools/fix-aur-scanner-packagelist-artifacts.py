#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
path = root / "crates/aur-scanner-cli/src/commands/install.rs"
text = path.read_text()

pattern = re.compile(
    r"fn package_paths_from_packagelist\(output: &\[u8\], base_dir: &Path\) -> Result<Vec<PathBuf>> \{.*?\n\}\n\npub async fn run",
    re.S,
)
replacement = r'''fn package_paths_from_packagelist(output: &[u8], base_dir: &Path) -> Result<Vec<PathBuf>> {
    let canonical_base = fs::canonicalize(base_dir).with_context(|| {
        format!(
            "canonicalizing scanned base directory {}",
            base_dir.display()
        )
    })?;
    let text =
        std::str::from_utf8(output).context("makepkg --packagelist returned non-UTF-8 output")?;
    let mut paths = Vec::new();
    let mut missing = Vec::new();
    for line in text.lines().map(str::trim).filter(|line| !line.is_empty()) {
        let path = PathBuf::from(line);
        if !path.is_absolute() {
            anyhow::bail!("makepkg --packagelist returned non-absolute path: {line}");
        }
        let parent = path.parent().context("package list path has no parent")?;
        let canonical_parent = fs::canonicalize(parent).with_context(|| {
            format!("canonicalizing package output parent {}", parent.display())
        })?;
        if !canonical_parent.starts_with(&canonical_base) {
            anyhow::bail!("makepkg package output escaped scanned base directory: {line}");
        }
        match fs::symlink_metadata(&path) {
            Ok(meta) if meta.file_type().is_file() => paths.push(path),
            Ok(_) => anyhow::bail!(
                "makepkg package output is not a regular file: {}",
                path.display()
            ),
            Err(error) if error.kind() == io::ErrorKind::NotFound => missing.push(path),
            Err(error) => {
                return Err(error).with_context(|| {
                    format!("stat package output {}", path.display())
                })
            }
        }
    }
    if paths.is_empty() {
        anyhow::bail!("makepkg completed but none of its listed package archives exist");
    }
    if !missing.is_empty() {
        eprintln!(
            "{} makepkg listed {} package archive(s) that were not produced; ignoring absent optional outputs: {}",
            "warning:".yellow(),
            missing.len(),
            missing
                .iter()
                .map(|path| path.display().to_string())
                .collect::<Vec<_>>()
                .join(", ")
        );
    }
    Ok(paths)
}

fn required_aur_package_names_for_base(
    graph: &depgraph::DependencyGraph,
    node_base: &BTreeMap<String, String>,
    base: &str,
) -> Vec<String> {
    graph
        .nodes
        .values()
        .filter(|node| {
            node.source == depgraph::PackageSource::Aur
                && node_base
                    .get(&node.name)
                    .is_some_and(|value| value == base)
        })
        .map(|node| node.name.clone())
        .collect()
}

fn archive_package_name(path: &Path) -> Result<String> {
    let pacman = absolute_binary(&["/usr/bin/pacman", "/bin/pacman"], "pacman")?;
    let output = Command::new(pacman)
        .arg("-Qp")
        .arg("--print-format")
        .arg("%n")
        .arg("--")
        .arg(path)
        .env_clear()
        .env("PATH", "/usr/bin:/bin:/usr/local/bin")
        .stdin(Stdio::null())
        .output()
        .with_context(|| format!("querying built package archive {}", path.display()))?;
    if !output.status.success() {
        anyhow::bail!("pacman could not query built package archive {}", path.display());
    }
    let name = std::str::from_utf8(&output.stdout)
        .context("pacman returned non-UTF-8 package metadata")?
        .trim();
    validate_package_name(name)
        .with_context(|| format!("built archive returned illegal package name {name:?}"))?;
    Ok(name.to_string())
}

fn missing_required_package_names(
    required: &[String],
    produced: &BTreeSet<String>,
) -> Vec<String> {
    required
        .iter()
        .filter(|name| !produced.contains(name.as_str()))
        .cloned()
        .collect()
}

fn ensure_required_package_archives(paths: &[PathBuf], required: &[String]) -> Result<()> {
    let mut produced = BTreeSet::new();
    for path in paths {
        produced.insert(archive_package_name(path)?);
    }
    let missing = missing_required_package_names(required, &produced);
    if !missing.is_empty() {
        anyhow::bail!(
            "successful makepkg build did not produce required AUR package archive(s): {}",
            missing.join(", ")
        );
    }
    Ok(())
}

pub async fn run'''
text, count = pattern.subn(replacement, text)
if count != 1:
    raise SystemExit(f"expected one packagelist function replacement, got {count}")

old = '''        let paths = package_paths_from_packagelist(&output.stdout, &dir)?;
        let asdeps = !package_base_is_explicit(&graph, &node_base, &base);
        broker.install_local(paths, asdeps)?;
'''
new = '''        let paths = package_paths_from_packagelist(&output.stdout, &dir)?;
        let required = required_aur_package_names_for_base(&graph, &node_base, &base);
        ensure_required_package_archives(&paths, &required)?;
        let asdeps = !package_base_is_explicit(&graph, &node_base, &base);
        broker.install_local(paths, asdeps)?;
'''
if text.count(old) != 1:
    raise SystemExit("expected one install_local call site")
text = text.replace(old, new)

marker = '''    #[test]
    fn local_package_staging_rejects_symlink() {
'''
tests = r'''    #[test]
    fn packagelist_ignores_absent_optional_output() {
        let base = tempfile::tempdir().unwrap();
        let output_dir = base.path().join("pkgdest");
        std::fs::create_dir(&output_dir).unwrap();
        let main = output_dir.join("example-1-1-any.pkg.tar.zst");
        let debug = output_dir.join("example-debug-1-1-any.pkg.tar.zst");
        std::fs::write(&main, b"pkg").unwrap();
        let output = format!("{}\n{}\n", main.display(), debug.display());
        let paths = package_paths_from_packagelist(output.as_bytes(), base.path()).unwrap();
        assert_eq!(paths, vec![main]);
    }

    #[test]
    fn packagelist_fails_when_no_listed_archive_exists() {
        let base = tempfile::tempdir().unwrap();
        let output_dir = base.path().join("pkgdest");
        std::fs::create_dir(&output_dir).unwrap();
        let missing = output_dir.join("example-1-1-any.pkg.tar.zst");
        let output = format!("{}\n", missing.display());
        assert!(package_paths_from_packagelist(output.as_bytes(), base.path()).is_err());
    }

    #[test]
    fn packagelist_rejects_existing_non_regular_output() {
        let base = tempfile::tempdir().unwrap();
        let output_dir = base.path().join("pkgdest");
        std::fs::create_dir(&output_dir).unwrap();
        let directory = output_dir.join("example-1-1-any.pkg.tar.zst");
        std::fs::create_dir(&directory).unwrap();
        let output = format!("{}\n", directory.display());
        assert!(package_paths_from_packagelist(output.as_bytes(), base.path()).is_err());
    }

    #[test]
    fn required_package_names_detect_missing_real_package() {
        let required = vec!["main".to_string(), "split".to_string()];
        let produced = BTreeSet::from(["main".to_string(), "main-debug".to_string()]);
        assert_eq!(
            missing_required_package_names(&required, &produced),
            vec!["split".to_string()]
        );
    }

'''
if text.count(marker) != 1:
    raise SystemExit("expected one unit-test insertion marker")
text = text.replace(marker, tests + marker)

path.write_text(text)
