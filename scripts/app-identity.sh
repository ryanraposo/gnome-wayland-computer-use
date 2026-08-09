#!/usr/bin/env bash
# app-identity.sh — cheaply distinguish installed web apps from browsers.
set -euo pipefail

REFRESH=false
QUERY=
for arg in "$@"; do
    case "$arg" in
        --refresh) REFRESH=true ;;
        --help|-h)
            echo "Usage: $0 [--refresh] [query]"
            echo "Lists browser/PWA/Electron desktop launchers as JSON."
            exit 0
            ;;
        -*) echo "error: unknown option: $arg" >&2; exit 2 ;;
        *)
            if [ -n "$QUERY" ]; then
                QUERY="$QUERY $arg"
            else
                QUERY="$arg"
            fi
            ;;
    esac
done

PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
[ -n "$PYTHON" ] || { echo 'python3 is required' >&2; exit 1; }

CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/gnome-wayland-computer-use"
CACHE_FILE="$CACHE_DIR/app-identities.json"
CACHE_SECONDS="${GNOME_WAYLAND_APP_IDENTITY_CACHE_SECONDS:-300}"
mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR" 2>/dev/null || true

exec "$PYTHON" - "$CACHE_FILE" "$CACHE_SECONDS" "$REFRESH" "$QUERY" <<'PY'
import configparser
import json
import os
import pathlib
import re
import shlex
import sys
import time

cache_file = pathlib.Path(sys.argv[1])
cache_seconds = max(0, int(sys.argv[2]))
refresh = sys.argv[3].lower() == 'true'
query = sys.argv[4].strip().casefold()


def cache_fresh(path):
    try:
        return time.time() - path.stat().st_mtime < cache_seconds
    except OSError:
        return False


def detect_engine(argv):
    tokens = [str(token).casefold() for token in argv]
    joined = '\n'.join(tokens)
    if any(x in joined for x in ('google-chrome', 'com.google.chrome')) or any(
        pathlib.Path(token).name in {'chrome', 'chrome-wrapper'} for token in tokens
    ):
        return 'chrome'
    if 'chromium' in joined or 'org.chromium.chromium' in joined:
        return 'chromium'
    if 'brave' in joined or 'com.brave.browser' in joined:
        return 'brave'
    if 'microsoft-edge' in joined or 'com.microsoft.edge' in joined:
        return 'edge'
    if 'firefox' in joined or 'org.mozilla.firefox' in joined:
        return 'firefox'
    if 'electron' in joined:
        return 'electron'
    return None


def parse_exec(value):
    # Desktop Exec field codes are irrelevant to launcher identity.
    cleaned = re.sub(r'(^|\s)%[fFuUdDnNickvm]', r'\1', value or '').strip()
    try:
        return shlex.split(cleaned)
    except ValueError:
        return cleaned.split()


def flag_value(argv, name):
    prefix = name + '='
    for index, token in enumerate(argv):
        if token.startswith(prefix):
            return token.split('=', 1)[1]
        if token == name and index + 1 < len(argv):
            return argv[index + 1]
    return None


def classify(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        with path.open('r', encoding='utf-8', errors='replace') as handle:
            parser.read_file(handle)
    except (OSError, configparser.Error):
        return None
    if not parser.has_section('Desktop Entry'):
        return None
    entry = parser['Desktop Entry']
    if entry.get('Type', 'Application') != 'Application':
        return None
    if entry.get('Hidden', '').casefold() == 'true':
        return None

    name = entry.get('Name', path.stem).strip()
    exec_value = entry.get('Exec', '').strip()
    argv = parse_exec(exec_value)
    if not argv:
        return None

    engine = detect_engine(argv)
    app_flag = flag_value(argv, '--app-id')
    app_url = flag_value(argv, '--app')
    standalone = bool(app_flag or app_url or any(x in {'--ssb', '--kiosk-app'} for x in argv))
    startup_wm_class = entry.get('StartupWMClass', '').strip() or None

    if standalone:
        kind = 'installed-web-app'
    elif engine in {'chrome', 'chromium', 'brave', 'edge', 'firefox'}:
        kind = 'browser'
    elif engine == 'electron':
        kind = 'electron-app'
    else:
        return None

    desktop_id = path.name
    app_id = app_flag or startup_wm_class or path.stem
    return {
        'display_name': name,
        'desktop_id': desktop_id,
        'app_id': app_id,
        'startup_wm_class': startup_wm_class,
        'engine': engine,
        'kind': kind,
        'standalone_web_app': standalone,
        'site': app_url,
        'exec': exec_value,
        'source': str(path),
    }


def application_dirs():
    seen = set()
    candidates = []
    data_home = os.environ.get('XDG_DATA_HOME') or str(pathlib.Path.home() / '.local/share')
    candidates.append(pathlib.Path(data_home) / 'applications')
    for root in (os.environ.get('XDG_DATA_DIRS') or '/usr/local/share:/usr/share').split(':'):
        if root:
            candidates.append(pathlib.Path(root) / 'applications')
    for path in candidates:
        key = str(path)
        if key not in seen:
            seen.add(key)
            yield path


def scan():
    # First desktop ID wins, matching XDG user-over-system precedence.
    rows = []
    seen_ids = set()
    for directory in application_dirs():
        if not directory.is_dir():
            continue
        try:
            files = sorted(directory.glob('*.desktop'))
        except OSError:
            continue
        for path in files:
            if path.name in seen_ids:
                continue
            seen_ids.add(path.name)
            row = classify(path)
            if row:
                rows.append(row)
    rows.sort(key=lambda r: (r['display_name'].casefold(), r['desktop_id']))
    return rows


rows = None
if not refresh and cache_fresh(cache_file):
    try:
        rows = json.loads(cache_file.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        rows = None
if rows is None:
    rows = scan()
    tmp = cache_file.with_suffix('.tmp')
    try:
        tmp.write_text(json.dumps(rows, separators=(',', ':')), encoding='utf-8')
        os.chmod(tmp, 0o600)
        os.replace(tmp, cache_file)
    except OSError:
        try:
            tmp.unlink()
        except OSError:
            pass

if query:
    def matches(row):
        haystack = '\n'.join(str(row.get(k) or '') for k in (
            'display_name', 'desktop_id', 'app_id', 'startup_wm_class', 'engine', 'kind', 'site', 'exec'
        )).casefold()
        return query in haystack
    rows = [row for row in rows if matches(row)]

print(json.dumps(rows, indent=2, sort_keys=True))
PY
