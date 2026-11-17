#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

for script in install.sh uninstall.sh; do
    grep -Fq 'GWCU_RELEASE_URL' "$ROOT/$script" || fail "$script has no release URL override"
    grep -Fq 'releases/download/v$VERSION' "$ROOT/$script" || fail "$script does not use versioned release assets"
    ! grep -Fq 'BASE_URL/dist/' "$ROOT/$script" || fail "$script still fetches the unpublished Pages dist path"
done
grep -Fq 'GWCU_BASE_URL' "$ROOT/scripts/check-update.sh" || fail "version check lost its bootstrap base URL"
grep -Fq '## Release' "$ROOT/README.md" || fail "release procedure is undocumented"
grep -Fq 'GWCU_RELEASE_URL' "$ROOT/README.md" || fail "release URL override is undocumented"
pass "bootstrap and release sources are separated"

python3 - "$ROOT" <<'PY' || fail "release workflow contract drift"
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
text = (root / ".github/workflows/release.yml").read_text()
assert "tags: ['v*']" in text, "workflow is not tag-triggered"
assert "contents: write" in text, "workflow cannot publish assets"
assert "build-release.sh" in text, "workflow does not build the archive"
assert "gh release create" in text and "gh release upload" in text, "workflow does not publish assets"
assert "releases/download" in text, "workflow does not verify the published URL"
PY
pass "tag push publishes checksummed release assets"

python3 - "$ROOT" <<'PY' || fail "workflow references drift"
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
for name in (".github/workflows/ci.yml", ".github/workflows/release.yml", ".github/workflows/pages.yml"):
    text = (root / name).read_text()
    for rel in set(re.findall(r"(?:bash\s+)?\./(tests/[A-Za-z0-9_.-]+\.(?:sh|py))", text)):
        target = root / rel
        assert target.is_file(), f"{name}: missing {rel}"
    jobs = set(re.findall(r"^  ([a-z0-9-]+):\s*$", text, re.M))
    needs = set(re.findall(r"^\s+needs:\s*([a-z0-9-]+)\s*$", text, re.M))
    for group in re.findall(r"^\s+needs:\s*\[([^\]]+)\]", text, re.M):
        needs.update(n.strip() for n in group.split(",") if n.strip())
    assert needs <= jobs, f"{name}: unknown jobs {needs - jobs}"
    if "needs.worldline-visibility.outputs.public" in text:
        assert re.search(r"^\s+public:\s*\$\{\{", text, re.M), f"{name}: undeclared public output"
PY
pass "workflows reference existing tests and declared jobs"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
bash "$ROOT/scripts/build-release.sh" "$TMP" >/dev/null || fail "release build"
python3 - "$TMP" "$ROOT" <<'PY' || fail "release manifest identity drift"
import hashlib
import json
import pathlib
import sys

out, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
version = (root / "VERSION").read_text().strip()
commit = __import__("subprocess").check_output(
    ["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
d = json.loads((out / f"gwcu-{version}.json").read_text())
assert d["schema"] == "gwcu.release.v1"
assert d["version"] == version and d["commit"] == commit
assert len(d["sha256"]) == 64 and d["bytes"] > 0
archive = out / d["archive"]
assert hashlib.sha256(archive.read_bytes()).hexdigest() == d["sha256"]
assert archive.stat().st_size == d["bytes"]
PY
pass "release manifest is commit-addressed and checksummed"

if [ "${GWCU_RELEASE_SMOKE:-0}" = "1" ]; then
    version="$(tr -d '[:space:]' < "$ROOT/VERSION")"
    url="https://github.com/ryanraposo/gnome-wayland-computer-use/releases/download/v$version/gwcu-$version.json"
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 3 --max-time 60 "$url" -o "$TMP/published.json" || fail "published manifest is not fetchable at the installer URL"
    python3 - "$TMP/published.json" "$version" <<'PY' || fail "published manifest drift"
import json
import pathlib
import re
import sys

d = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert d["schema"] == "gwcu.release.v1"
assert d["version"] == sys.argv[2]
assert re.fullmatch(r"[0-9a-f]{64}", d["sha256"])
assert d["archive"] == f"gwcu-{sys.argv[2]}.tar.gz"
PY
    pass "published manifest is fetchable at the installer URL"
fi
