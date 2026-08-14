#!/usr/bin/env python3
"""WORLDLINE: revisioned desktop state + local postconditions for GWCU.

WORLDLINE never injects input. Cua Driver remains the sole control authority.
"""
from __future__ import annotations
import argparse, hashlib, json, os, signal, socket, stat, subprocess, threading, time
from pathlib import Path
from typing import Any

APP="gnome-wayland-computer-use"; SCHEMA="gwcu.worldline.v1"; REV="gwcu.worldline.revision.v1"
MAX=1<<20; IDLE=300

def js(x:Any)->str:return json.dumps(x,separators=(",",":"),ensure_ascii=True)
def root()->Path:return Path(os.getenv("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}"))/APP
def sock()->Path:return root()/"worldline.sock"
def observer()->Path:return root()/"observer.sock"
def statefile()->Path:return root()/"worldline/state.json"
def mkdir(p:Path):p.mkdir(parents=True,exist_ok=True,mode=0o700);p.chmod(0o700)
def save_json(p:Path,x:Any):
    mkdir(p.parent); t=p.with_name(f".{p.name}.{os.getpid()}.tmp");t.write_text(js(x)+"\n");os.chmod(t,0o600);os.replace(t,p)
def run(argv:list[str],timeout=.6)->str|None:
    try:r=subprocess.run(argv,text=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=timeout)
    except (OSError,subprocess.TimeoutExpired):return None
    return r.stdout.strip() if r.returncode==0 else None

def call(path:Path,payload:dict[str,Any],timeout=3.0)->dict[str,Any]:
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.settimeout(timeout)
    try:
        s.connect(str(path));s.sendall((js(payload)+"\n").encode());buf=bytearray()
        while b"\n" not in buf and len(buf)<=MAX:
            b=s.recv(65536)
            if not b:break
            buf.extend(b)
    finally:s.close()
    if len(buf)>MAX:raise RuntimeError("response_too_large")
    return json.loads(bytes(buf).split(b"\n",1)[0])

def observer_capture(timeout_ms=1500)->dict[str,Any]:
    try:return call(observer(),{"v":1,"op":"capture","fresh":"next","timeout_ms":timeout_ms},max(2,timeout_ms/1000+1))
    except Exception as e:return {"ok":False,"code":"observer_unavailable","detail":str(e)}

def value(entry:Any)->Any:return entry.get("value") if isinstance(entry,dict) and "value" in entry else entry
def pred(p:dict[str,Any],facts:dict[str,Any],changed:set[str],invalid:set[str])->bool:
    path=p.get("path");op=p.get("op","eq")
    if not isinstance(path,str) or not path:return False
    exists=path in facts and path not in invalid;v=value(facts.get(path));want=p.get("value")
    if op=="exists":return exists
    if op=="missing":return not exists
    if op=="changed":return path in changed
    if op=="invalid":return path in invalid
    if not exists:return False
    if op=="eq":return v==want
    if op=="ne":return v!=want
    if op=="in":return isinstance(want,list) and v in want
    if op=="contains":
        try:return want in v
        except TypeError:return False
    return False

def pid_of(p:dict[str,Any])->str:return str(p.get("id") or js(p))
def digest(path:Path)->str|None:
    try:
        h=hashlib.sha256()
        with path.open("rb") as f:
            for b in iter(lambda:f.read(1<<20),b""):h.update(b)
        return h.hexdigest()
    except OSError:return None

def oracles(pids:list[int]|None=None,paths:list[str]|None=None)->dict[str,tuple[Any,str]]:
    out={}
    for k,e in (("session.type","XDG_SESSION_TYPE"),("session.desktop","XDG_CURRENT_DESKTOP"),("session.wayland_display","WAYLAND_DISPLAY")):
        if os.getenv(e):out[k]=(os.environ[e],"environment")
    sid=os.getenv("XDG_SESSION_ID")
    if sid:
        q=run(["loginctl","show-session",sid,"-p","Active","-p","LockedHint","--value"])
        if q:
            a=q.splitlines();out["session.active"]=(a[0].lower()=="yes","loginctl")
            if len(a)>1:out["session.locked"]=(a[1].lower()=="yes","loginctl")
    q=run(["gsettings","get","org.gnome.desktop.interface","color-scheme"])
    if q:out["settings.color_scheme"]=(q.strip("'"),"gsettings")
    q=run(["nmcli","-t","-f","STATE,CONNECTIVITY","general"])
    if q:
        a=q.split(":",1);out["network.state"]=(a[0],"nmcli")
        if len(a)>1:out["network.connectivity"]=(a[1],"nmcli")
    for pid in pids or []:
        try:
            p=Path(f"/proc/{int(pid)}");out[f"process.{pid}.exists"]=(p.exists(),"procfs")
            if p.exists():out[f"process.{pid}.exe"]=(os.readlink(p/"exe"),"procfs");out[f"process.{pid}.cwd"]=(os.readlink(p/"cwd"),"procfs")
        except (OSError,ValueError):pass
    for raw in paths or []:
        try:
            p=Path(raw).expanduser();k=hashlib.sha256(str(p).encode()).hexdigest()[:16];ex=p.exists()
            out[f"fs.{k}.path"]=(str(p),"stat");out[f"fs.{k}.exists"]=(ex,"stat")
            if ex:
                s=p.stat();out[f"fs.{k}.size"]=(s.st_size,"stat");out[f"fs.{k}.mtime_ns"]=(s.st_mtime_ns,"stat")
        except OSError:pass
    return out

class AtspiSensor:
    EVENTS=("focus:","object:state-changed","object:children-changed","object:property-change","object:text-changed","object:selection-changed","object:value-changed","window:create","window:destroy","window:activate","window:deactivate","window:move","window:resize","window:minimize","window:maximize","window:restore")
    def __init__(self,w:"World"):self.w=w;self.available=False;self.detail="not started"
    def start(self):
        def worker():
            try:
                import gi;gi.require_version("Atspi","2.0");gi.require_version("GLib","2.0")
                from gi.repository import Atspi,GLib
                Atspi.init()
                def on(e:Any,*_:Any):
                    src=getattr(e,"source",None);facts={"ui.last.event":str(getattr(e,"type","") or "atspi")}
                    if src:
                        for key,fn in (("name","get_name"),("role","get_role_name"),("pid","get_process_id")):
                            try:
                                v=getattr(src,fn)()
                                if v:facts[f"ui.last.{key}"]=int(v) if key=="pid" else v
                            except Exception:pass
                        chain=[];cur=src
                        for _ in range(5):
                            try:cur=cur.get_parent()
                            except Exception:break
                            if cur is None:break
                            item={}
                            for key,fn in (("name","get_name"),("role","get_role_name")):
                                try:
                                    v=getattr(cur,fn)()
                                    if v:item[key]=v
                                except Exception:pass
                            if item:chain.append(item)
                        if chain:facts["ui.last.ancestors"]=chain
                    et=facts["ui.last.event"]
                    if et.startswith("focus:"):
                        for k in ("name","role","pid"):
                            if f"ui.last.{k}" in facts:facts[f"ui.focus.{k}"]=facts[f"ui.last.{k}"]
                    inv=["ui.semantic"]+(["ui.window_roots"] if et.startswith("window:") else [])
                    self.w.event({"source":"atspi","type":et,"facts":facts,"invalidates":inv})
                listener=Atspi.EventListener.new(on,None);n=0
                for et in self.EVENTS:
                    try:listener.register(et);n+=1
                    except Exception:pass
                if not n:raise RuntimeError("no AT-SPI event classes registered")
                self.available=True;self.detail=f"{n} event classes";GLib.MainLoop().run()
            except Exception as e:self.available=False;self.detail=str(e)
        threading.Thread(target=worker,name="gwcu-atspi",daemon=True).start()

class World:
    def __init__(self):
        self.lock=threading.RLock();self.revision=0;self.facts={};self.events=[];self.armed={};self.last=None;self.prev_visual=None;self.sensor=None;self.load()
    def load(self):
        try:d=json.loads(statefile().read_text())
        except Exception:return
        self.revision=int(d.get("revision",0));self.facts=d.get("facts",{});self.events=d.get("events",[]);self.armed=d.get("armed",{});self.last=d.get("last_revision");self.prev_visual=d.get("prev_visual")
    def save(self):save_json(statefile(),{"revision":self.revision,"facts":self.facts,"events":self.events,"armed":self.armed,"last_revision":self.last,"prev_visual":self.prev_visual})
    def event(self,e:dict[str,Any]):
        with self.lock:
            self.events.append({"source":str(e.get("source") or "external"),"type":str(e.get("type") or "event"),"facts":e.get("facts") if isinstance(e.get("facts"),dict) else {},"invalidates":e.get("invalidates") if isinstance(e.get("invalidates"),list) else [],"monotonic_ns":time.monotonic_ns()});self.events=self.events[-2048:];self.save();return {"schema":SCHEMA,"ok":True,"code":"queued","queued":len(self.events)}
    def setfact(self,path:str,v:Any,source:str,rev:int,changed:set[str]):
        old=self.facts.get(path);entry={"value":v,"source":source,"revision":rev,"confidence":1.0}
        if value(old)!=v:changed.add(path)
        self.facts[path]=entry
    def invalidate(self,path:str,invalid:set[str]):
        for k in list(self.facts):
            if k==path or k.startswith(path+"."):invalid.add(k);self.facts.pop(k,None)
        invalid.add(path)
    def capture(self,q:dict[str,Any]):
        with self.lock:
            n=self.revision+1;changed:set[str]=set();invalid:set[str]=set();before=set(self.facts);events=self.events;self.events=[];sources={}
            requested=q.get("invalidates") if isinstance(q.get("invalidates"),list) else []
            for p in requested:
                if isinstance(p,str):self.invalidate(p,invalid)
            for e in events:
                sources[e["source"]]=sources.get(e["source"],0)+1
                for p in e.get("invalidates",[]):
                    if isinstance(p,str):self.invalidate(p,invalid)
                for p,v in e.get("facts",{}).items():
                    if isinstance(p,str):self.setfact(p,v,e["source"],n,changed)
            for p,(v,s) in oracles(q.get("pids") if isinstance(q.get("pids"),list) else [],q.get("paths") if isinstance(q.get("paths"),list) else []).items():self.setfact(p,v,s,n,changed)
            visual={"requested":bool(q.get("visual")),"ok":False}
            if q.get("visual"):
                r=observer_capture(int(q.get("visual_timeout_ms",1500)));visual.update({"ok":bool(r.get("ok")),"code":r.get("code")})
                rr=r.get("result") if isinstance(r.get("result"),dict) else r;path=rr.get("path") if isinstance(rr,dict) else None
                if r.get("ok") and isinstance(path,str):
                    d=digest(Path(path));visual.update({"hash":d,"width":rr.get("width"),"height":rr.get("height"),"changed":bool(d and d!=self.prev_visual)})
                    if d:self.setfact("visual.frame_hash",d,"pipewire",n,changed);self.setfact("visual.width",rr.get("width"),"pipewire",n,changed);self.setfact("visual.height",rr.get("height"),"pipewire",n,changed);self.prev_visual=d
                else:visual["uncertain"]=True
            self.revision=n;expect=q.get("expect") if isinstance(q.get("expect"),list) else []
            sat=[pid_of(p) for p in expect if isinstance(p,dict) and pred(p,self.facts,changed,invalid)];unsat=[pid_of(p) for p in expect if isinstance(p,dict) and not pred(p,self.facts,changed,invalid)]
            woken=[]
            for ident,tx in self.armed.items():
                ps=[p for p in tx.get("predicates",[]) if isinstance(p,dict)];states=[pred(p,self.facts,changed,invalid) for p in ps];ready=bool(states) and (all(states) if tx.get("mode","all")=="all" else any(states))
                if ready and tx.get("status")!="ready":tx["status"]="ready";tx["ready_revision"]=n;woken.append(ident)
            conflicts=[{"type":"postcondition_unsatisfied","predicate":p} for p in unsat] if q.get("conflict_on_unsatisfied") else []
            self.last={"schema":REV,"ok":not conflicts,"revision":n,"previous_revision":n-1,"trigger":str(q.get("trigger") or "manual"),"boundary":{"monotonic_ns":time.monotonic_ns(),"wall_time_ns":time.time_ns()},"events":{"count":len(events),"sources":sources},"changed":sorted(changed),"invalidated":sorted(invalid),"preserved":sorted(before-changed-invalid),"predicates_satisfied":sat,"predicates_unsatisfied":unsat,"woken":woken,"conflicts":conflicts,"uncertain":bool(visual.get("uncertain")),"visual":visual};self.save();return self.last
    def arm(self,q:dict[str,Any]):
        ident=str(q.get("id") or "");ps=q.get("predicates");mode=q.get("mode","all")
        if not ident or not isinstance(ps,list) or mode not in ("all","any"):raise ValueError("arm requires id, predicates and mode all|any")
        with self.lock:self.armed[ident]={"predicates":ps,"mode":mode,"status":"waiting","armed_revision":self.revision};self.save();return {"schema":SCHEMA,"ok":True,"code":"armed","id":ident,"revision":self.revision}
    def status(self):
        with self.lock:return {"schema":SCHEMA,"ok":True,"code":"ok","revision":self.revision,"facts":len(self.facts),"queued_events":len(self.events),"transactions_waiting":sum(x.get("status")=="waiting" for x in self.armed.values()),"last_revision":self.last,"socket":str(sock()),"observer_socket":str(observer()),"atspi":{"available":bool(self.sensor and self.sensor.available),"detail":self.sensor.detail if self.sensor else "not started"}}
    def handle(self,q):
        op=q.get("op")
        if op=="status":return self.status()
        if op=="event":return self.event(q.get("event") if isinstance(q.get("event"),dict) else q)
        if op=="capture":return self.capture(q)
        if op=="arm":return self.arm(q)
        if op=="close":return {"schema":SCHEMA,"ok":True,"code":"closing"}
        raise ValueError("op must be status|event|capture|arm|close")

def listen()->socket.socket:
    try:n=int(os.getenv("LISTEN_FDS","0"));pid=int(os.getenv("LISTEN_PID","0"))
    except ValueError:n=pid=0
    if n>=1 and pid==os.getpid():return socket.fromfd(3,socket.AF_UNIX,socket.SOCK_STREAM)
    mkdir(root());p=sock();p.unlink(missing_ok=True);s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.bind(str(p));os.chmod(p,stat.S_IRUSR|stat.S_IWUSR);s.listen(16);return s

def serve()->int:
    w=World();w.sensor=AtspiSensor(w);w.sensor.start();s=listen();s.settimeout(1);stop=False;last=time.monotonic();idle=max(30,min(int(os.getenv("GWCU_WORLDLINE_IDLE_SECONDS",IDLE)),3600))
    def halt(*_):
        nonlocal stop;stop=True
    signal.signal(signal.SIGTERM,halt);signal.signal(signal.SIGINT,halt)
    while not stop and time.monotonic()-last<idle:
        try:c,_=s.accept()
        except socket.timeout:continue
        with c:
            try:
                raw=bytearray()
                while b"\n" not in raw and len(raw)<=MAX:
                    b=c.recv(65536)
                    if not b:break
                    raw.extend(b)
                if len(raw)>MAX:raise ValueError("request_too_large")
                q=json.loads(bytes(raw).split(b"\n",1)[0]);r=w.handle(q)
                if q.get("op")=="close":stop=True
            except Exception as e:r={"schema":SCHEMA,"ok":False,"code":"invalid_request","detail":str(e)}
            try:c.sendall((js(r)+"\n").encode())
            except OSError:pass
            last=time.monotonic()
    s.close();return 0

def selftest()->int:
    import tempfile,shutil
    old=os.getenv("XDG_RUNTIME_DIR");tmp=tempfile.mkdtemp(prefix="gwcu-worldline-");os.environ["XDG_RUNTIME_DIR"]=tmp
    try:
        w=World();w.event({"source":"atspi","facts":{"ui.focus.name":"Save"},"invalidates":["ui.dialog"]});r=w.capture({"trigger":"test","expect":[{"id":"focus-save","path":"ui.focus.name","op":"eq","value":"Save"}]});assert r["revision"]==1 and "ui.dialog" in r["invalidated"] and "focus-save" in r["predicates_satisfied"]
        w.arm({"id":"tx","predicates":[{"path":"task.done","op":"eq","value":True}]});w.event({"source":"task","facts":{"task.done":True}});assert "tx" in w.capture({"trigger":"done"})["woken"]
        print(js({"schema":SCHEMA,"ok":True,"code":"self_test_ok"}));return 0
    finally:
        if old is None:os.environ.pop("XDG_RUNTIME_DIR",None)
        else:os.environ["XDG_RUNTIME_DIR"]=old
        shutil.rmtree(tmp,ignore_errors=True)

def main()->int:
    p=argparse.ArgumentParser(description=__doc__);sp=p.add_subparsers(dest="cmd",required=True);sp.add_parser("serve");sp.add_parser("self-test");q=sp.add_parser("request");q.add_argument("--json",required=True);a=p.parse_args()
    if a.cmd=="serve":return serve()
    if a.cmd=="self-test":return selftest()
    try:r=call(sock(),json.loads(a.json),5)
    except Exception as e:print(js({"schema":SCHEMA,"ok":False,"code":"worldline_unavailable","detail":str(e)}));return 50
    print(js(r));return 0 if r.get("ok") else 30
if __name__=="__main__":raise SystemExit(main())
