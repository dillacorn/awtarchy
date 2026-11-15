#!/usr/bin/env bash
# Stable compositor source comes from the user's exact published config release.
set -euo pipefail
umask 077
[[ $EUID -ne 0 ]] || { printf 'Run as your normal user.\n' >&2; false; }
[[ $# -eq 3 ]] || { printf 'Invalid compositor manager invocation.\n' >&2; false; }
operation="$1"
mode="$2"
remove_deps="$3"
case "$operation" in
    status|install-sway|install-hyprland|remove-sway|remove-hyprland|update-sway) ;;
    *) printf 'Unknown compositor operation.\n' >&2; false ;;
esac
[[ $mode == plan || $mode == apply ]] || { printf 'Invalid mode.\n' >&2; false; }
[[ $remove_deps == yes || $remove_deps == no ]] || { printf 'Invalid dependencies choice.\n' >&2; false; }
here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
core="$here/awtarchy-compositor-core.sh"
[[ -f $core && ! -L $core && -O $core ]] || {
    printf 'Stable compositor helper missing; run awtarchy self-update.\n' >&2
    false
}
bash -n "$core"
if [[ $operation == status ]]; then
    bash "$core" status plan no
    return_code=$?
    (exit "$return_code")
fi
version_file="$HOME/.local/state/awtarchy/config-version"
[[ -f $version_file && ! -L $version_file && -O $version_file ]] || {
    printf 'Missing stable config version. Run awtarchy update.\n' >&2
    false
}
tag="$(sed -n 's/^tag=//p' "$version_file" | head -n1)"
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf 'Install a stable Awtarchy release first via awtarchy update.\n' >&2
    false
}
for cmd in curl python3 tar mktemp; do
    command -v "$cmd" >/dev/null 2>&1 || { printf 'Missing %s\n' "$cmd" >&2; false; }
done
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
api='https://api.github.com/repos/dillacorn/awtarchy'
curl_args=(-fLsS --connect-timeout 8 --max-time 45 --retry 2 --retry-all-errors
           -H 'Accept: application/vnd.github+json'
           -H 'User-Agent: awtarchy-compositor')
if [[ -n ${GITHUB_TOKEN:-} ]]; then
    curl_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi
curl "${curl_args[@]}" "$api/releases/tags/$tag" -o "$tmp/release.json"
python3 - "$tmp/release.json" "$tag" <<'PY'
import json, sys
from pathlib import Path
j = json.loads(Path(sys.argv[1]).read_text())
if j.get("tag_name") != sys.argv[2] or j.get("draft") is not False or not j.get("published_at"):
    raise SystemExit("Expected exact published stable release")
PY
curl "${curl_args[@]}" "$api/git/ref/tags/$tag" -o "$tmp/ref.json"
revision="$(python3 - "$tmp/ref.json" <<'PY'
import json, re, sys
from pathlib import Path
o = json.loads(Path(sys.argv[1]).read_text()).get("object") or {}
kind, sha = o.get("type"), o.get("sha", "")
if kind not in ("commit", "tag") or not re.fullmatch(r"[0-9a-f]{40}", sha):
    raise SystemExit("Unexpected tag reference")
print(kind, sha)
PY
)"
read -r kind sha <<< "$revision"
for ((depth=0; depth<8 && kind == tag; depth++)); do
    curl "${curl_args[@]}" "$api/git/tags/$sha" -o "$tmp/ref.json"
    revision="$(python3 - "$tmp/ref.json" <<'PY'
import json, re, sys
from pathlib import Path
o = json.loads(Path(sys.argv[1]).read_text()).get("object") or {}
kind, sha = o.get("type"), o.get("sha", "")
if kind not in ("commit", "tag") or not re.fullmatch(r"[0-9a-f]{40}", sha):
    raise SystemExit("Unexpected annotated tag object")
print(kind, sha)
PY
)"
    read -r kind sha <<< "$revision"
done
[[ $kind == commit ]] || { printf 'Cannot resolve immutable release commit.\n' >&2; false; }
printf 'Using Awtarchy %s at %.12s.\n' "$tag" "$sha"
curl -fLsS --connect-timeout 8 --max-time 300 --retry 2 \
    --speed-limit 1024 --speed-time 30 \
    "https://github.com/dillacorn/awtarchy/archive/$sha.tar.gz" -o "$tmp/source.tar.gz"
python3 - "$tmp/source.tar.gz" "awtarchy-$sha" <<'PY'
from pathlib import PurePosixPath
import sys, tarfile
archive, root = sys.argv[1:]
total, seen = 0, set()
with tarfile.open(archive, "r:gz") as reader:
    for member in reader:
        p = PurePosixPath(member.name)
        if (not p.parts or p.parts[0] != root or p.is_absolute()
                or len(p.parts) > 30 or any(x in ("", ".", "..") for x in p.parts)
                or member.name in seen or not (member.isfile() or member.isdir())):
            raise SystemExit("Unsafe release archive")
        seen.add(member.name)
        total += member.size
        if total > 300 * 1024 * 1024 or len(seen) > 30000:
            raise SystemExit("Release archive size limit")
PY
tar -xzf "$tmp/source.tar.gz" -C "$tmp"
source="$tmp/awtarchy-$sha"
[[ -f "$source/trials/sway/setup.sh" && -f "$source/config/hypr/hyprland.lua" ]] || {
    printf 'Release %s does not contain stable Sway support. Run awtarchy update first.\n' "$tag" >&2
    false
}
AWTARCHY_COMPOSITOR_RELEASE_SOURCE="$source" bash "$core" "$operation" "$mode" "$remove_deps"
