#!/usr/bin/env bash
# app-identity.sh — deterministic installed-app identity resolver.
set -euo pipefail
REFRESH=false; RESOLVE=false; MACHINE=false; QUERY=
for arg in "$@"; do
 case "$arg" in
  --refresh) REFRESH=true;; --resolve) RESOLVE=true;; --machine) MACHINE=true;;
  --help|-h) echo "Usage: $0 [--refresh] [--resolve] [--machine] [query]"; exit 0;;
  -*) echo "error: unknown option: $arg" >&2; exit 2;;
  *) if [ -n "$QUERY" ]; then QUERY="$QUERY $arg"; else QUERY="$arg"; fi;;
 esac
done
$RESOLVE && [ -z "$QUERY" ] && { echo "error: --resolve requires a query" >&2; exit 2; }
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"; [ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"; [ -n "$PYTHON" ] || exit 30
CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/gnome-wayland-computer-use"; CACHE_FILE="$CACHE_DIR/app-identities.json"; CACHE_SECONDS="${GNOME_WAYLAND_APP_IDENTITY_CACHE_SECONDS:-300}"
mkdir -p "$CACHE_DIR"; chmod 700 "$CACHE_DIR" 2>/dev/null || true
exec "$PYTHON" - "$CACHE_FILE" "$CACHE_SECONDS" "$REFRESH" "$RESOLVE" "$MACHINE" "$QUERY" <<'PY'
import configparser,json,os,pathlib,re,shlex,sys,time
cache=pathlib.Path(sys.argv[1]); ttl=max(0,int(sys.argv[2])); refresh=sys.argv[3]=='true'; resolve=sys.argv[4]=='true'; machine=sys.argv[5]=='true'; raw=sys.argv[6].strip(); q=raw.casefold()
def parse_exec(v):
 try:return shlex.split(re.sub(r'(^|\s)%[fFuUdDnNickvm]',r'\1',v or '').strip())
 except ValueError:return (v or '').split()
def flag(a,n):
 for i,t in enumerate(a):
  if t.startswith(n+'='):return t.split('=',1)[1]
  if t==n and i+1<len(a):return a[i+1]
def engine(a):
 j='\n'.join(str(x).casefold() for x in a)
 for needle,name in [('google-chrome','chrome'),('chromium','chromium'),('brave','brave'),('microsoft-edge','edge'),('firefox','firefox'),('electron','electron')]:
  if needle in j:return name
def classify(p):
 c=configparser.ConfigParser(interpolation=None,strict=False); c.optionxform=str
 try:
  with p.open(encoding='utf-8',errors='replace') as h:c.read_file(h)
 except Exception:return None
 if not c.has_section('Desktop Entry'):return None
 e=c['Desktop Entry']
 if e.get('Type','Application')!='Application' or e.get('Hidden','').casefold()=='true':return None
 a=parse_exec(e.get('Exec','')); eng=engine(a)
 if not a or not eng:return None
 app=flag(a,'--app-id'); site=flag(a,'--app'); standalone=bool(app or site or any(x in {'--ssb','--kiosk-app'} for x in a)); wm=e.get('StartupWMClass','').strip() or None
 kind='installed-web-app' if standalone else ('electron-app' if eng=='electron' else 'browser')
 return {'display_name':e.get('Name',p.stem).strip(),'desktop_id':p.name,'app_id':app or wm or p.stem,'startup_wm_class':wm,'engine':eng,'kind':kind,'standalone_web_app':standalone,'site':site,'exec':e.get('Exec',''),'source':str(p)}
def dirs():
 seen=set(); roots=[pathlib.Path(os.environ.get('XDG_DATA_HOME') or pathlib.Path.home()/'.local/share')/'applications']
 roots += [pathlib.Path(x)/'applications' for x in (os.environ.get('XDG_DATA_DIRS') or '/usr/local/share:/usr/share').split(':') if x]
 for p in roots:
  if str(p) not in seen:seen.add(str(p));yield p
def scan():
 out=[]; seen=set()
 for d in dirs():
  if not d.is_dir():continue
  for p in sorted(d.glob('*.desktop')):
   if p.name in seen:continue
   seen.add(p.name); r=classify(p)
   if r:out.append(r)
 return sorted(out,key=lambda r:(r['display_name'].casefold(),r['desktop_id']))
rows=None
try:
 if not refresh and time.time()-cache.stat().st_mtime<ttl:rows=json.loads(cache.read_text())
except Exception:pass
if rows is None:
 rows=scan()
 try:
  t=cache.with_suffix('.tmp'); t.write_text(json.dumps(rows,separators=(',',':')));os.chmod(t,0o600);os.replace(t,cache)
 except OSError:pass
def hay(r):return '\n'.join(str(r.get(k) or '') for k in ('display_name','desktop_id','app_id','startup_wm_class','engine','kind','site','exec')).casefold()
if not resolve:
 if q:rows=[r for r in rows if q in hay(r)]
 print(json.dumps(rows,separators=(',',':') if machine else None,indent=None if machine else 2,sort_keys=not machine));raise SystemExit(0)
def score(r):
 d=(r.get('display_name') or '').casefold();di=(r.get('desktop_id') or '').casefold();stem=di[:-8] if di.endswith('.desktop') else di;a=(r.get('app_id') or '').casefold();w=(r.get('startup_wm_class') or '').casefold();s=(r.get('site') or '').casefold()
 for hit,pts,why in ((d==q,100,'exact_display_name'),(di==q or stem==q,98,'exact_desktop_id'),(a==q,96,'exact_app_id'),(w==q,94,'exact_startup_wm_class'),(s==q,92,'exact_site')):
  if hit:return pts,[why]
 if d.startswith(q):return 80,['display_name_prefix']
 if any(v.startswith(q) for v in (a,w,stem) if v):return 75,['identity_prefix']
 if q in hay(r):return 50,['substring_match']
 return 0,[]
rank=[]
for r in rows:
 pts,ev=score(r)
 if pts:rank.append((pts,r['display_name'].casefold(),r,ev))
rank.sort(key=lambda x:(-x[0],x[1],x[2]['desktop_id']))
def emit(p,rc):print(json.dumps(p,separators=(',',':') if machine else None,indent=None if machine else 2));raise SystemExit(rc)
if not rank:emit({'schema':'gwcu.identity.v1','ok':False,'code':'missing','query':raw,'retryable':False,'terminal':False,'candidates':[],'next':{'action':'use_live_window_identity'}},10)
top=rank[0][0];leaders=[x for x in rank if x[0]==top]
if len(leaders)==1 and top>=75:
 _,_,r,ev=leaders[0];emit({'schema':'gwcu.identity.v1','ok':True,'code':'resolved','query':raw,'result':r,'evidence':ev,'score':top,'next':{'action':'use_identity'}},0)
c=[]
for pts,_,r,ev in rank[:8]:c.append({'display_name':r['display_name'],'desktop_id':r['desktop_id'],'app_id':r.get('app_id'),'kind':r.get('kind'),'score':pts,'evidence':ev})
emit({'schema':'gwcu.identity.v1','ok':False,'code':'ambiguous','query':raw,'retryable':False,'terminal':False,'candidates':c,'next':{'action':'disambiguate'}},10)
PY
