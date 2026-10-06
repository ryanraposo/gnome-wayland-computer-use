#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRUTHS="$ROOT/scripts/truths.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

mkdir -p "$TMP/general/scratch" "$TMP/general/repos/project/work"
GWCU_WORKDIR="$TMP/general" python3 "$TRUTHS" init >"$TMP/general-init.json"
[ -f "$TMP/general/.gwcu" ] || fail "non-Git workspace .gwcu was not created"
[ ! -e "$TMP/general/.gitignore" ] || fail "non-Git workspace received a .gitignore"

GWCU_WORKDIR="$TMP/general/scratch" python3 "$TRUTHS" scope >"$TMP/general-scope.json"
python3 - "$TMP/general-scope.json" "$TMP/general" <<'PY' || fail "non-Git ancestor scope resolution failed"
import json,pathlib,sys
d=json.load(open(sys.argv[1])); expected=str(pathlib.Path(sys.argv[2]).resolve())
assert d['root']==expected, (d,expected)
assert d['git'] is False
assert d['source']=='nearest_truth'
PY
pass "non-Git descendants inherit the nearest workspace .gwcu"

git -C "$TMP/general/repos/project" init -q
GWCU_WORKDIR="$TMP/general/repos/project/work" python3 "$TRUTHS" scope >"$TMP/repo-scope.json"
python3 - "$TMP/repo-scope.json" "$TMP/general/repos/project" <<'PY' || fail "nested Git scope resolution failed"
import json,pathlib,sys
d=json.load(open(sys.argv[1])); expected=str(pathlib.Path(sys.argv[2]).resolve())
assert d['root']==expected, (d,expected)
assert d['git'] is True
assert d['source']=='git_root'
PY

GWCU_WORKDIR="$TMP/general/repos/project/work" python3 "$TRUTHS" init >"$TMP/repo-init.json"
[ -f "$TMP/general/repos/project/.gwcu" ] || fail "nested Git repo did not get its own .gwcu"
grep -qx '/\.gwcu' "$TMP/general/repos/project/.gitignore" || fail "nested Git repo .gwcu was not root-ignored"
[ -f "$TMP/general/.gwcu" ] || fail "parent workspace .gwcu was disturbed"
pass "Git repos remain isolated inside a broader .gwcu workspace"

mkdir -p "$TMP/explicit"
GWCU_SCOPE_ROOT="$TMP/explicit" GWCU_WORKDIR="$TMP/general/repos/project/work" python3 "$TRUTHS" scope >"$TMP/explicit-scope.json"
python3 - "$TMP/explicit-scope.json" "$TMP/explicit" <<'PY' || fail "explicit scope override failed"
import json,pathlib,sys
d=json.load(open(sys.argv[1])); expected=str(pathlib.Path(sys.argv[2]).resolve())
assert d['root']==expected
assert d['source']=='environment'
PY
pass "explicit scope override remains authoritative"
