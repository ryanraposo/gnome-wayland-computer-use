#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }; pass(){ printf 'ok - %s\n' "$1"; }

# Published installs are assembled from one exact commit into one
# checksum-addressed archive. Validate the builder independently of Pages.
mkdir -p "$TMP/release"
bash "$ROOT/scripts/build-release.sh" "$TMP/release" >"$TMP/release-build.txt"
release_version=$(tr -d '[:space:]' <"$ROOT/VERSION")
release_meta="$TMP/release/gwcu-$release_version.json"
release_archive="$TMP/release/gwcu-$release_version.tar.gz"
[ -s "$release_meta" ] && [ -s "$release_archive" ] || fail "release builder did not emit metadata + archive"
python3 - "$release_meta" "$release_archive" "$release_version" <<'PY' || fail "release archive identity contract invalid"
import hashlib,json,pathlib,sys,tarfile
meta_path,archive_path,version=sys.argv[1:]
meta=json.load(open(meta_path))
assert meta["schema"]=="gwcu.release.v1"
assert meta["version"]==version
assert meta["archive"]==pathlib.Path(archive_path).name
blob=pathlib.Path(archive_path).read_bytes()
assert meta["bytes"]==len(blob)
assert meta["sha256"]==hashlib.sha256(blob).hexdigest()
with tarfile.open(archive_path,"r:gz") as tf:
    names={m.name.removeprefix("./") for m in tf.getmembers()}
    assert "SKILL.md" in names and "VERSION" in names and ".gwcu-release.json" in names
    internal=json.load(tf.extractfile(next(m for m in tf.getmembers() if m.name.removeprefix("./")==".gwcu-release.json")))
assert internal["schema"]=="gwcu.release.v1"
assert internal["version"]==version
assert internal["commit"]==meta["commit"]
PY
pass "release builder emits one commit-addressed SHA-256 archive"

# Official curl-pipe form must not trust ./scripts/teardown.sh from the caller cwd.
# It consumes the same verified archive built above.
mkdir -p "$TMP/attacker/scripts" "$TMP/home" "$TMP/bin"
cat >"$TMP/attacker/scripts/teardown.sh" <<'SH'
#!/usr/bin/env bash
touch "$ATTACK_MARK"
SH
chmod +x "$TMP/attacker/scripts/teardown.sh"
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) shift; out="$1" ;;
    http*) url="$1" ;;
  esac
  shift || true
done
case "$url" in
  *.json) cp "$RELEASE_META" "$out" ;;
  *.tar.gz) cp "$RELEASE_ARCHIVE" "$out" ;;
  *) exit 22 ;;
esac
SH
chmod +x "$TMP/bin/curl"
(
  cd "$TMP/attacker"
  ATTACK_MARK="$TMP/attacked" RELEASE_META="$release_meta" RELEASE_ARCHIVE="$release_archive" \
    HOME="$TMP/home" XDG_STATE_HOME="$TMP/uninstall-state" PATH="$TMP/bin:/usr/bin:/bin" \
    bash -s -- <"$ROOT/uninstall.sh" >"$TMP/uninstall-verified.out"
)
[ ! -e "$TMP/attacked" ] || fail "curl-pipe uninstaller executed caller-local teardown"
grep -Fq '[OK] Verified GWCU teardown source' "$TMP/uninstall-verified.out" || fail "curl-pipe uninstaller did not prove release identity"
pass "curl-pipe uninstall ignores caller cwd and uses verified release teardown"

# Integrity failure is terminal even when a same-generation managed fallback exists.
rm -rf "$TMP/home" "$TMP/bin"; mkdir -p "$TMP/home/.agents/skills/gnome-wayland-computer-use/scripts" "$TMP/bin"
printf '%s\n' "$release_version" >"$TMP/home/.agents/skills/gnome-wayland-computer-use/VERSION"
: >"$TMP/home/.agents/skills/gnome-wayland-computer-use/.gnome-wayland-computer-use-managed"
cat >"$TMP/home/.agents/skills/gnome-wayland-computer-use/scripts/teardown.sh" <<'SH'
#!/usr/bin/env bash
touch "$FALLBACK_MARK"
SH
chmod +x "$TMP/home/.agents/skills/gnome-wayland-computer-use/scripts/teardown.sh"
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in -o) shift; out="$1";; http*) url="$1";; esac
  shift || true
done
case "$url" in
  *.json) cp "$RELEASE_META" "$out" ;;
  *.tar.gz) printf 'tampered-release' >"$out" ;;
  *) exit 22 ;;
esac
SH
chmod +x "$TMP/bin/curl"
rc=0
FALLBACK_MARK="$TMP/fallback-called" RELEASE_META="$release_meta" HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" \
  bash -s -- <"$ROOT/uninstall.sh" >"$TMP/uninstall-tampered.out" 2>"$TMP/uninstall-tampered.err" || rc=$?
[ "$rc" -ne 0 ] || fail "tampered release uninstall succeeded"
[ ! -e "$TMP/fallback-called" ] || fail "integrity failure downgraded to installed fallback"
grep -Fq 'refusing uninstall because current release integrity could not be proved' "$TMP/uninstall-tampered.err" || fail "integrity failure boundary is unclear"
pass "uninstall integrity failure is terminal and cannot downgrade"

# Teardown must preserve every unmarked skill directory, including profiles.
mkdir -p "$TMP/home/.agents/skills/gnome-wayland-computer-use" \
         "$TMP/home/.hermes/skills/computer-use" \
         "$TMP/home/.hermes/skills/gnome-wayland-computer-use" \
         "$TMP/home/.hermes/profiles/work/skills/computer-use" \
         "$TMP/bin2"
for d in \
  "$TMP/home/.agents/skills/gnome-wayland-computer-use" \
  "$TMP/home/.hermes/skills/computer-use" \
  "$TMP/home/.hermes/skills/gnome-wayland-computer-use" \
  "$TMP/home/.hermes/profiles/work/skills/computer-use"
do echo user-owned >"$d/KEEP"; done
cat >"$TMP/bin2/systemctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$TMP/bin2/gsettings" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/bin2/"*
HOME="$TMP/home" HERMES_HOME="$TMP/home/.hermes" XDG_STATE_HOME="$TMP/state" PATH="$TMP/bin2:/usr/bin:/bin" \
  bash "$ROOT/scripts/teardown.sh" --force >/dev/null
for d in \
  "$TMP/home/.agents/skills/gnome-wayland-computer-use" \
  "$TMP/home/.hermes/skills/computer-use" \
  "$TMP/home/.hermes/skills/gnome-wayland-computer-use" \
  "$TMP/home/.hermes/profiles/work/skills/computer-use"
do [ -f "$d/KEEP" ] || fail "teardown deleted unmanaged $d"; done
pass "teardown preserves unmanaged default/profile skill directories"

# Managed profile integration is removed everywhere and archived prior skills are
# restored independently in each Hermes home.
rm -rf "$TMP/home" "$TMP/state"; mkdir -p "$TMP/bin2"
for target in "$TMP/home/.hermes" "$TMP/home/.hermes/profiles/work"; do
  mkdir -p "$target/skills/computer-use" "$target/plugins/gnome-wayland-computer-use" \
           "$target/backups/gnome-wayland-computer-use" "$TMP/archive"
  : >"$target/skills/computer-use/.gnome-wayland-computer-use-managed"
  : >"$target/plugins/gnome-wayland-computer-use/.gnome-wayland-computer-use-managed"
  printf 'name: gnome-wayland-computer-use\n' >"$target/plugins/gnome-wayland-computer-use/plugin.yaml"
  backup="$TMP/archive/$(printf '%s' "$target" | tr '/' '_')-computer-use"
  mkdir -p "$backup"; echo restored >"$backup/KEEP"
  printf '%s\t%s\n' "$target/skills/computer-use" "$backup" >"$target/backups/gnome-wayland-computer-use/manifest.tsv"
done
HOME="$TMP/home" HERMES_HOME="$TMP/home/.hermes" XDG_STATE_HOME="$TMP/state" PATH="$TMP/bin2:/usr/bin:/bin" \
  bash "$ROOT/scripts/teardown.sh" --force >/dev/null
for target in "$TMP/home/.hermes" "$TMP/home/.hermes/profiles/work"; do
  [ -f "$target/skills/computer-use/KEEP" ] || fail "profile backup restoration failed for $target"
  [ ! -e "$target/plugins/gnome-wayland-computer-use" ] || fail "managed plugin survived teardown in $target"
  [ ! -e "$target/backups/gnome-wayland-computer-use/manifest.tsv" ] || fail "completed profile restoration left manifest in $target"
done
pass "teardown removes managed integration and restores archives across profiles"

# A completed backup restoration must remove the manifest cleanly and exit zero.
rm -rf "$TMP/home" "$TMP/state"; mkdir -p "$TMP/home/.hermes/backups/gnome-wayland-computer-use" "$TMP/home/archive" "$TMP/bin2"
backup="$TMP/home/archive/original-skill"; mkdir -p "$backup"; echo restored >"$backup/KEEP"
original="$TMP/home/.hermes/skills/computer-use"
printf '%s\t%s\n' "$original" "$backup" >"$TMP/home/.hermes/backups/gnome-wayland-computer-use/manifest.tsv"
HOME="$TMP/home" HERMES_HOME="$TMP/home/.hermes" XDG_STATE_HOME="$TMP/state" PATH="$TMP/bin2:/usr/bin:/bin" \
  bash "$ROOT/scripts/teardown.sh" --force >/dev/null
[ -f "$original/KEEP" ] || fail "backup restoration did not restore archived skill"
[ ! -e "$TMP/home/.hermes/backups/gnome-wayland-computer-use/manifest.tsv" ] || fail "completed restoration left manifest behind"
pass "backup restoration completes without MANIFEST typo failure"

# RemoteDesktop authorization is only successful when Cua has persisted its restore token.
cat >"$TMP/fake-cua" <<'PY'
#!/usr/bin/env python3
import json,sys
for line in sys.stdin:
 q=json.loads(line)
 if q.get('method')=='initialize': print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'protocolVersion':'2024-11-05'}}),flush=True)
 elif q.get('method')=='tools/call':
  name=q['params']['name']; payload={'width':100,'height':100} if name=='get_screen_size' else {'ok':True}
  print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'isError':False,'structuredContent':payload,'content':[]}}),flush=True)
PY
chmod +x "$TMP/fake-cua"
rc=0
GWCU_REMOTE_DESKTOP_AVAILABLE=1 GWCU_LIBEI_TOKEN="$TMP/missing-token" \
  python3 "$ROOT/scripts/portal-control.py" --authorize --driver "$TMP/fake-cua" --timeout 5 >"$TMP/portal.json" || rc=$?
[ "$rc" -ne 0 ] || fail "authorization succeeded without persistent token"
python3 - "$TMP/portal.json" <<'PY' || fail "missing-token authorization envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert not d['ok']; assert d['code']=='persistent_authorization_missing'; assert not d['portal']['restore_token']['present']
PY
pass "RemoteDesktop authorization requires durable restore token"

# Source integrity must be established before durable install state or package
# mutation, and verified sources must never fall back to per-file HTTP reads.
grep -Fq 'prepare_source' "$ROOT/install.sh" || fail "installer has no release source gate"
grep -Fq 'Remote GWCU source must use HTTPS' "$ROOT/install.sh" || fail "remote source is not HTTPS-only"
grep -Fq 'release archive SHA-256 mismatch' "$ROOT/install.sh" || fail "release digest is not enforced"
grep -Fq 'tf.extractall(dest,filter="data")' "$ROOT/install.sh" || fail "archive extraction lacks safe-data filter"
grep -Fq 'verified source missing: $r' "$ROOT/install.sh" || fail "installed files can escape the verified source"
grep -Fq 'SOURCE_KIND="checkout-dirty"' "$ROOT/install.sh" || fail "dirty local installs can masquerade as exact commits"
grep -Fq 'SOURCE_KIND="local-files"' "$ROOT/install.sh" || fail "non-Git local installs lack honest source identity"
grep -Fq 'flock -n 9' "$ROOT/install.sh" || fail "concurrent installs are not fenced"
grep -Fq 'fetch_verified_release' "$ROOT/uninstall.sh" || fail "public uninstall does not verify the release bundle"
grep -Fq 'refusing uninstall because current release integrity could not be proved' "$ROOT/uninstall.sh" || fail "uninstall can downgrade after integrity failure"
! grep -Fq 'else curl -fsSL --retry 3 --retry-delay 1 -o "$d" "$BASE_URL/$r"' "$ROOT/install.sh" || fail "per-file remote fallback can mix releases"
python3 - "$ROOT/install.sh" <<'PY' || fail "release verification is not ordered before mutation"
import pathlib,sys
text=pathlib.Path(sys.argv[1]).read_text()
gate=text.index("\nprepare_source\n")
state=text.index('mkdir -p "$STATE"',gate)
packages=text.index('as_root apt-get update')
assert gate < state < packages
assert text.index('flock -n 9',gate) < packages
PY
pass "installer verifies one source and locks before durable/system mutation"

# Installer contracts that must survive an in-place upgrade.
grep -q 'PKGS=(.*git' "$ROOT/install.sh" || fail "Git is not an explicit dependency"
grep -Fq 'get_file scripts/migrate-main.sh "$MIGRATOR"' "$ROOT/install.sh" || fail "installer does not bootstrap published-main migration"
grep -Fq 'scripts/migrate-main.sh' "$ROOT/install.sh" || fail "installed bundle omits published-main migrator"
grep -Fq 'Description=ydotool uinput daemon' "$ROOT/scripts/migrate-main.sh" || fail "migration does not identify old ydotool service"
grep -Fq 'LEGACY_RULE_VALUE=' "$ROOT/scripts/migrate-main.sh" || fail "migration does not identify exact old uinput rule"
grep -Fq 'desktop-capture@gnome-wayland-computer-use' "$ROOT/scripts/migrate-main.sh" || fail "migration does not retire old GNOME capture extension"
grep -Fq 'gnome-wayland-computer-use:start' "$ROOT/scripts/migrate-main.sh" || fail "migration does not retire old Hermes SOUL routing"
grep -q 'write_cua_ownership' "$ROOT/install.sh" || fail "Cua ownership is not persisted immediately"
grep -q 'agents/openai.yaml' "$ROOT/install.sh" || fail "OpenAI metadata is not deployed"
grep -q 'worldline_degraded' "$ROOT/scripts/diagnose.sh" || fail "diagnosis can ignore dead WORLDLINE"
grep -Fq -- '--hermes-profile NAME' "$ROOT/install.sh" || fail "installer lacks explicit Hermes profile targeting"
grep -Fq -- '--hermes-all-profiles' "$ROOT/install.sh" || fail "installer lacks all-profile opt-in"
grep -Fq 'HERMES_TARGET_HOMES' "$ROOT/install.sh" || fail "installer does not resolve Hermes homes explicitly"
grep -Fq 'HERMES_PROFILE_ROOT/profiles' "$ROOT/scripts/teardown.sh" || fail "teardown does not scan Hermes profiles"
grep -Fq 'built-in `computer_use` tool' "$ROOT/scripts/teardown.sh" || fail "teardown does not state computer_use ownership boundary"
pass "upgrade and installed-runtime contracts cover published-main and Hermes-profile lifecycle seams"
