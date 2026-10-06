#!/usr/bin/env bash
# Real GNOME Wayland acceptance: prove installed readiness, then exercise Cua end-to-end.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${GWCU_ACCEPTANCE_DIR:-$ROOT/.gwcu-acceptance}"
PYTHON="${GWCU_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3)"
mkdir -p "$OUT"

if [ "${GWCU_LIVE_ACCEPTANCE:-}" != "1" ]; then
  cat <<'EOF'
GWCU live desktop acceptance controls the visible GNOME desktop.
Run explicitly from the real Ubuntu GNOME Wayland session:

  GWCU_LIVE_ACCEPTANCE=1 bash tests/desktop-acceptance.sh

Artifacts are written to .gwcu-acceptance/ by default.
EOF
  exit 2
fi

[ "${XDG_SESSION_TYPE:-}" = wayland ] || { printf 'not ok - live acceptance requires Wayland\n' >&2; exit 30; }
printf '%s' "${XDG_CURRENT_DESKTOP:-}" | grep -qi gnome || { printf 'not ok - live acceptance requires GNOME\n' >&2; exit 30; }

printf '[1/2] proving installed desktop/runtime state\n'
set +e
"$ROOT/scripts/diagnose.sh" --machine >"$OUT/diagnose.json"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  printf 'not ok - diagnose did not reach READY // PROVED; evidence: %s\n' "$OUT/diagnose.json" >&2
  exit "$rc"
fi
"$PYTHON" - "$OUT/diagnose.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d.get("ok") is True and d.get("code")=="ready"
assert (d.get("presentation") or {}).get("status")=="ready"
assert (d.get("worldline") or {}).get("status")=="ready"
assert (d.get("cua") or {}).get("status")=="ready"
PY

printf '[2/2] exercising cold app acquisition, exact presentation, cursor, actuation, verification\n'
GWCU_LIVE_CALCULATOR=1 GWCU_ACCEPTANCE_OUTPUT="$OUT/calculator-cold.json" "$PYTHON" "$ROOT/tests/calculator-cold.py"

"$PYTHON" - "$OUT/diagnose.json" "$OUT/calculator-cold.json" "$OUT/summary.json" <<'PY'
import json,pathlib,sys,time
diagnose=json.load(open(sys.argv[1])); calc=json.load(open(sys.argv[2])); out=pathlib.Path(sys.argv[3])
payload={
  "schema":"gwcu.acceptance-suite.v1",
  "ok":bool(diagnose.get("ok") and calc.get("ok")),
  "scenarios":{"diagnose":{"ok":bool(diagnose.get("ok")),"code":diagnose.get("code")},"calculator-cold":calc},
  "completed_at_unix":int(time.time()),
}
out.write_text(json.dumps(payload,separators=(",",":"))+"\n")
print(json.dumps(payload,indent=2))
PY
printf 'ok - GWCU live desktop acceptance passed; summary: %s\n' "$OUT/summary.json"
