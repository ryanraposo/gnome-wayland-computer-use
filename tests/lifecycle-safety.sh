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

# Teardown must preserve every unmarked skill directory, regardless of location.
mkdir -p "$TMP/home/.agents/skills/gnome-wayland-computer-use" \
         "$TMP/home/.hermes/skills/computer-use" \
         "$TMP/home/.hermes/skills/gnome-wayland-computer-use" \
         "$TMP/bin2"
for d in "$TMP/home/.agents/skills/gnome-wayland-computer-use" "$TMP/home/.hermes/skills/computer-use" "$TMP/home/.hermes/skills/gnome-wayland-computer-use"; do echo user-owned >"$d/KEEP"; done
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
for d in "$TMP/home/.agents/skills/gnome-wayland-computer-use" "$TMP/home/.hermes/skills/computer-use" "$TMP/home/.hermes/skills/gnome-wayland-computer-use"; do [ -f "$d/KEEP" ] || fail "teardown deleted unmanaged $d"; done
pass "teardown preserves all unmanaged skill directories"

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
grep -q 'LEGACY_YDO=' "$ROOT/install.sh" || fail "upgrade does not retire legacy ydotool service"
grep -q 'LEGACY_RULE_VALUE=' "$ROOT/install.sh" || fail "upgrade does not retire exact legacy uinput rule"
grep -q 'write_cua_ownership' "$ROOT/install.sh" || fail "Cua ownership is not persisted immediately"
grep -q 'agents/openai.yaml' "$ROOT/install.sh" || fail "OpenAI metadata is not deployed"
grep -q 'worldline_degraded' "$ROOT/scripts/diagnose.sh" || fail "diagnosis can ignore dead WORLDLINE"
pass "upgrade and installed-runtime contracts cover reviewed lifecycle seams"
