#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }; pass(){ printf 'ok - %s\n' "$1"; }

# Official curl-pipe form must not trust ./scripts/teardown.sh from the caller cwd.
mkdir -p "$TMP/attacker/scripts" "$TMP/home" "$TMP/bin"
cat >"$TMP/attacker/scripts/teardown.sh" <<'SH'
#!/usr/bin/env bash
touch "$ATTACK_MARK"
SH
chmod +x "$TMP/attacker/scripts/teardown.sh"
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && { shift; out="$1"; }; shift || true; done
cat >"$out" <<'SAFE'
#!/usr/bin/env bash
touch "$SAFE_MARK"
SAFE
SH
chmod +x "$TMP/bin/curl"
(
  cd "$TMP/attacker"
  ATTACK_MARK="$TMP/attacked" SAFE_MARK="$TMP/safe" HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" \
    bash -s -- <"$ROOT/uninstall.sh"
)
[ ! -e "$TMP/attacked" ] || fail "curl-pipe uninstaller executed caller-local teardown"
[ -e "$TMP/safe" ] || fail "curl-pipe uninstaller did not use fetched teardown"
pass "curl-pipe uninstall ignores planted caller-local scripts"

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
