#!/usr/bin/env bash
# Resolve the independently managed WORLDLINE service before GWCU is declared ready.
set -euo pipefail
COMMAND="${1:-ensure}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${GWCU_SYSTEM_PYTHON:-/usr/bin/python3}"
CLIENT="$ROOT/scripts/worldline.py"
CONTRACT="$ROOT/scripts/worldline-contract.py"
REPO="ryanraposo/WORLDLINE"
REF="${GWCU_WORLDLINE_INSTALL_REF:-main}"
TMP=""
cleanup(){ [ -z "$TMP" ] || rm -rf "$TMP"; }
trap cleanup EXIT

die(){ printf 'GWCU WORLDLINE: %s\n' "$*" >&2; exit 1; }
features(){
  local output="$1"
  "$PYTHON" "$CLIENT" request --json '{"op":"features"}' >"$output" 2>/dev/null
}
contract_ok(){
  local output="$1"
  "$PYTHON" "$CONTRACT" "$output" >/dev/null 2>&1
}
ready(){
  local output
  output="$(mktemp)"
  if features "$output"; then
    if contract_ok "$output"; then rm -f "$output"; return 0; fi
    rm -f "$output"
    die "WORLDLINE answered, but its protocol does not satisfy GWCU's receipt contract. Upgrade WORLDLINE with its own installer; GWCU will not replace it."
  fi
  rm -f "$output"
  return 1
}
wait_ready(){
  local i
  for i in {1..20}; do ready && return 0; sleep 0.5; done
  return 1
}

case "$COMMAND" in
  ensure)
    ready && { printf 'WORLDLINE ready (protocol 1; receipt verified).\n'; exit 0; }
    if command -v systemctl >/dev/null 2>&1 && systemctl --user cat worldline.service >/dev/null 2>&1; then
      printf 'WORLDLINE is installed but not responding; asking its service manager to start it.\n'
      systemctl --user start worldline.service || die "Could not start worldline.service. Inspect: journalctl --user -u worldline.service"
      wait_ready && exit 0
      die "worldline.service started but the protocol-1 receipt check failed. Inspect: journalctl --user -u worldline.service"
    fi
    if [ "${GWCU_WORLDLINE_INSTALL:-0}" != 1 ]; then
      if [ ! -t 0 ]; then
        die "WORLDLINE is missing. Re-run with GWCU_WORLDLINE_INSTALL=1 after authorizing acquisition, or install WORLDLINE separately."
      fi
      printf 'WORLDLINE is not installed. Acquire it from %s? [y/N] ' "$REPO"
      IFS= read -r answer || answer=""
      case "$answer" in y|Y|yes|YES) ;; *) die "Installation cancelled; GWCU was not declared ready." ;; esac
    fi
    command -v git >/dev/null 2>&1 || die "git is required to acquire WORLDLINE."
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/gwcu-worldline.XXXXXX")"
    if command -v gh >/dev/null 2>&1; then
      gh repo clone "$REPO" "$TMP/source" -- --depth 1 --branch "$REF" || die "Could not acquire WORLDLINE. Confirm GitHub access to the private repository $REPO."
    else
      git clone --depth 1 --branch "$REF" "https://github.com/$REPO.git" "$TMP/source" || die "Could not acquire WORLDLINE. The repository is private; authenticate GitHub access or install WORLDLINE separately."
    fi
    [ -x "$TMP/source/scripts/worldline-install.sh" ] || die "The selected WORLDLINE ref does not contain its independent installer."
    if [ "${GWCU_WORLDLINE_GRANT_FRAMES:-0}" = 1 ]; then
      WORLDLINE_INSTALL_REF="$REF" WORLDLINE_INSTALL_SOURCE="$TMP/source" bash "$TMP/source/scripts/worldline-install.sh" install --grant-window-frames
    else
      WORLDLINE_INSTALL_REF="$REF" WORLDLINE_INSTALL_SOURCE="$TMP/source" bash "$TMP/source/scripts/worldline-install.sh" install
    fi
    wait_ready || die "WORLDLINE installation completed without a verified receipt-capable service."
    ;;
  *)
    die "Unknown command: $COMMAND"
    ;;
esac
