#!/usr/bin/env bash
# Verify that the public curl-pipe bootstrap serves one exact repository commit.
# Post-deploy this catches a stale Pages artifact before anyone runs the one-liner.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${GWCU_PAGES_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
EXPECT="${GWCU_PAGES_EXPECT_COMMIT:-main}"
ATTEMPTS="${GWCU_PAGES_ATTEMPTS:-12}"
DELAY="${GWCU_PAGES_DELAY:-10}"
FILES=(install.sh uninstall.sh VERSION index.html)

fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

version="$(tr -d '[:space:]' <"$ROOT/VERSION")"
[ -n "$version" ] || fail "VERSION is empty"

for file in "${FILES[@]}"; do
    git -C "$ROOT" cat-file -e "$EXPECT:$file" 2>/dev/null || fail "$EXPECT does not contain $file"
done

# The page must point at the very base whose bytes we verify.
grep -Fq "curl -fsSL $BASE/install.sh | bash" "$ROOT/index.html" || fail "install command in index.html does not use $BASE"
grep -Fq "curl -fsSL $BASE/uninstall.sh | bash" "$ROOT/index.html" || fail "uninstall command in index.html does not use $BASE"

attempt=1
while :; do
    matched=1
    for file in "${FILES[@]}"; do
        git -C "$ROOT" show "$EXPECT:$file" >"$TMP/expected-$file" || fail "cannot read $EXPECT:$file"
        if ! curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --max-time 30 "$BASE/$file" -o "$TMP/published-$file"; then
            printf '# attempt %s: %s is not fetchable from %s\n' "$attempt" "$file" "$BASE" >&2
            matched=0
            break
        fi
        if ! cmp -s "$TMP/expected-$file" "$TMP/published-$file"; then
            printf '# attempt %s: published %s differs from %s\n' "$attempt" "$file" "$EXPECT" >&2
            printf '# published sha256: %s\n' "$(sha256sum "$TMP/published-$file" | cut -d' ' -f1)" >&2
            printf '# expected  sha256: %s\n' "$(sha256sum "$TMP/expected-$file" | cut -d' ' -f1)" >&2
            matched=0
            break
        fi
    done
    [ "$matched" -eq 1 ] && break
    [ "$attempt" -ge "$ATTEMPTS" ] && fail "Pages still serves stale bootstrap after $ATTEMPTS attempts"
    attempt=$((attempt + 1))
    sleep "$DELAY"
done

bash -n "$TMP/published-install.sh" || fail "published install.sh has a syntax error"
bash -n "$TMP/published-uninstall.sh" || fail "published uninstall.sh has a syntax error"
[ "$(tr -d '[:space:]' <"$TMP/published-VERSION")" = "$version" ] || fail "published VERSION differs from repository VERSION"

pass "Pages serves the exact $EXPECT bootstrap (v$version) and both curl-pipe scripts parse"
