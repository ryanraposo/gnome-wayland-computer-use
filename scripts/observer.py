#!/usr/bin/env python3
"""Lazy persistent XDG ScreenCast/PipeWire broker. Independent of Cua."""
from __future__ import annotations
import argparse, json, os, pathlib, signal, socket, stat, threading, time, uuid

APP="gnome-wayland-computer-use"; SCHEMA="gwcu.observer.v1"
MAX_REQUEST=16384; DEFAULT_IDLE=120
Gio=GLib=Gst=GstVideo=GdkPixbuf=None

class E(Exception):
    def __init__(self, code, exit_code=40, retryable=True, terminal=False, detail=None):
        super().__init__(detail or code)
        self.code=code; self.exit_code=exit_code; self.retryable=retryable
        self.terminal=terminal; self.detail=detail or code

def env(ok, code, result=None, *, retryable=None, terminal=None, detail=None, next=None, timing_ms=None):
    d={"schema":SCHEMA,"ok":ok,"code":code}
    if result is not None: d["result"]=result
    if retryable is not None: d["retryable"]=bool(retryable)
    if terminal is not None: d["terminal"]=bool(terminal)
    if detail is not None: d["detail"]=str(detail)
    if timing_ms is not None: d["timing_ms"]=timing_ms
    d["next"]=next
    return d

def runtime_dir():
    return pathlib.Path(os.environ.get("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}"))/APP
def state_dir():
    return pathlib.Path(os.environ.get("XDG_STATE_HOME",str(pathlib.Path.home()/".local/state")))/APP
def sock_path(): return runtime_dir()/"observer.sock"
def private_dir(p):
    p.mkdir(parents=True,exist_ok=True,mode=0o700)
    try: p.chmod(0o700)
    except OSError: pass

def gi():
    global Gio,GLib,Gst,GstVideo,GdkPixbuf
    if Gio is not None: return
    try:
        import gi as _gi
        for n,v in (("Gio","2.0"),("Gst","1.0"),("GstVideo","1.0"),("GdkPixbuf","2.0")):
            _gi.require_version(n,v)
        from gi.repository import Gio as A,GLib as B,Gst as C,GstVideo as D,GdkPixbuf as F
    except Exception as ex:
        raise E("gi_unavailable",30,False,detail=str(ex))
    Gio,GLib,Gst,GstVideo,GdkPixbuf=A,B,C,D,F; Gst.init(None)

class Cast:
    def __init__(self):
        self.bus=self.portal=self.session=self.pipeline=None; self.pwfd=None
        self.cond=threading.Condition(); self.sample=None; self.frame_ns=0
        self.version=0; self.generation=0

    @property
    def active(self): return self.pipeline is not None

    def proxy(self):
        gi()
        if self.portal is not None: return
        self.bus=Gio.bus_get_sync(Gio.BusType.SESSION,None)
        self.portal=Gio.DBusProxy.new_sync(
            self.bus,Gio.DBusProxyFlags.NONE,None,"org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop","org.freedesktop.portal.ScreenCast",None)
        v=self.portal.get_cached_property("version"); self.version=int(v.unpack()) if v else 0

    def close_obj(self,path,iface):
        if not path or not self.bus: return
        try:
            self.bus.call_sync("org.freedesktop.portal.Desktop",path,iface,"Close",
                None,None,Gio.DBusCallFlags.NONE,1000,None)
        except Exception: pass

    def request(self,method,signature,values,timeout=20):
        self.proxy()
        sender=self.bus.get_unique_name().lstrip(":").replace(".","_")
        token="gwcu_"+uuid.uuid4().hex
        expected=f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
        loop=GLib.MainLoop(); response={}
        def got(_c,_s,_p,_i,_n,params): response["v"]=params.unpack(); loop.quit()
        sub=self.bus.signal_subscribe("org.freedesktop.portal.Desktop",
            "org.freedesktop.portal.Request","Response",expected,None,
            Gio.DBusSignalFlags.NONE,got)
        actual=expected
        try:
            values[-1]["handle_token"]=GLib.Variant("s",token)
            reply=self.portal.call_sync(method,GLib.Variant(signature,tuple(values)),
                Gio.DBusCallFlags.NONE,3000,None)
            unpacked=reply.unpack() if reply else ()
            if unpacked and isinstance(unpacked[0],str): actual=unpacked[0]
            if actual!=expected:
                self.bus.signal_unsubscribe(sub)
                sub=self.bus.signal_subscribe("org.freedesktop.portal.Desktop",
                    "org.freedesktop.portal.Request","Response",actual,None,
                    Gio.DBusSignalFlags.NONE,got)
            timer=GLib.timeout_add(int(timeout*1000),lambda:(loop.quit(),False)[1])
            loop.run()
            try: GLib.source_remove(timer)
            except Exception: pass
        finally: self.bus.signal_unsubscribe(sub)
        if "v" not in response: self.close_obj(actual,"org.freedesktop.portal.Request"); raise E("portal_timeout")
        code,results=response["v"]
        if code:
            raise E("portal_cancelled" if code==1 else "portal_interaction_ended",
                    20,False,True,f"{method} response {code}")
        return results

    def token(self,new=None):
        p=state_dir()/"screencast-restore-token"
        if new:
            private_dir(p.parent); tmp=p.with_name(f".{p.name}.{os.getpid()}.tmp")
            tmp.write_text(new,encoding="utf-8"); tmp.chmod(0o600); tmp.replace(p); return None
        try: return p.read_text(encoding="utf-8").strip() or None
        except OSError: return None

    def on_sample(self,sink):
        s=sink.emit("pull-sample")
        if s is None: return Gst.FlowReturn.ERROR
        with self.cond:
            self.sample=s; self.frame_ns=time.monotonic_ns(); self.cond.notify_all()
        return Gst.FlowReturn.OK

    def start_pipeline(self,fd,node,props):
        pipe=Gst.Pipeline.new("gwcu"); src=Gst.ElementFactory.make("pipewiresrc","src")
        conv=Gst.ElementFactory.make("videoconvert","conv"); filt=Gst.ElementFactory.make("capsfilter","rgb")
        sink=Gst.ElementFactory.make("appsink","sink")
        if not all((pipe,src,conv,filt,sink)): raise E("gstreamer_elements_missing",30,False)
        src.set_property("fd",fd)
        serial=props.get("pipewire-serial")
        if self.version>=6 and serial is not None and src.find_property("target-object"):
            src.set_property("target-object",str(serial))
        else: src.set_property("path",str(node))
        filt.set_property("caps",Gst.Caps.from_string("video/x-raw,format=RGB"))
        for k,v in (("emit-signals",True),("max-buffers",1),("drop",True),("sync",False)): sink.set_property(k,v)
        sink.connect("new-sample",self.on_sample)
        for x in (src,conv,filt,sink): pipe.add(x)
        if not (src.link(conv) and conv.link(filt) and filt.link(sink)): raise E("gstreamer_link_failed")
        pipe.set_state(Gst.State.PLAYING)
        if pipe.get_state(3*Gst.SECOND)[0]==Gst.StateChangeReturn.FAILURE:
            pipe.set_state(Gst.State.NULL); raise E("pipewire_stream_failed")
        self.pipeline=pipe

    def ensure(self):
        if self.active: return
        self.proxy()
        try:
            c=self.request("CreateSession","(a{sv})",[{"session_handle_token":GLib.Variant("s","gwcu_"+uuid.uuid4().hex)}],5)
            self.session=c["session_handle"]
            opts={"types":GLib.Variant("u",1),"multiple":GLib.Variant("b",False)}
            modes=self.portal.get_cached_property("AvailableCursorModes")
            if modes is not None and int(modes.unpack())&2: opts["cursor_mode"]=GLib.Variant("u",2)
            if self.version>=4:
                opts["persist_mode"]=GLib.Variant("u",2)
                old=self.token()
                if old: opts["restore_token"]=GLib.Variant("s",old)
            self.request("SelectSources","(oa{sv})",[self.session,opts],5)
            started=self.request("Start","(osa{sv})",[self.session,"",{}],20)
            streams=started.get("streams",[])
            if not streams: raise E("portal_no_streams")
            node,props=streams[0]; self.token(started.get("restore_token"))
            reply,fds=self.portal.call_with_unix_fd_list_sync("OpenPipeWireRemote",
                GLib.Variant("(oa{sv})",(self.session,{})),Gio.DBusCallFlags.NONE,3000,None,None)
            self.pwfd=fds.get(reply.unpack()[0]); self.start_pipeline(self.pwfd,node,props or {})
            self.generation+=1
        except Exception: self.stop(); raise

    def encode(self,sample,path):
        buf=sample.get_buffer(); caps=sample.get_caps(); vi=GstVideo.VideoInfo()
        if not vi.from_caps(caps): raise E("frame_caps_invalid")
        ok,m=buf.map(Gst.MapFlags.READ)
        if not ok: raise E("frame_map_failed")
        try: data=bytes(m.data)
        finally: buf.unmap(m)
        b=GLib.Bytes.new(data)
        pix=GdkPixbuf.Pixbuf.new_from_bytes(b,GdkPixbuf.Colorspace.RGB,False,8,int(vi.width),int(vi.height),int(vi.stride[0]))
        private_dir(path.parent); tmp=path.with_name(f".{path.name}.{os.getpid()}.tmp")
        pix.savev(str(tmp),"png",[],[]); os.chmod(tmp,0o600); os.replace(tmp,path)
        return int(vi.width),int(vi.height)

    def capture(self,fresh="next",timeout_ms=1500):
        t0=time.monotonic_ns(); self.ensure(); after=time.monotonic_ns()
        deadline=time.monotonic()+max(.05,timeout_ms/1000)
        with self.cond:
            while self.sample is None or (fresh=="next" and self.frame_ns<=after):
                left=deadline-time.monotonic()
                if left<=0: raise E("frame_timeout")
                self.cond.wait(left)
            sample=self.sample; frame=self.frame_ns
        d=runtime_dir()/"frames"; p=d/f"frame-{time.monotonic_ns()}.png"; e0=time.monotonic_ns()
        w,h=self.encode(sample,p); end=time.monotonic_ns()
        try:
            fs=sorted(d.glob("frame-*.png"),key=lambda x:x.stat().st_mtime)
            for old in fs[:-8]: old.unlink(missing_ok=True)
        except OSError: pass
        return env(True,"ok",{"scope":"visible-screen","method":"screencast-broker","path":str(p),
            "width":w,"height":h,"freshness_ms":max(0,int((end-frame)/1e6)),"stream_generation":self.generation},
            timing_ms={"total":int((end-t0)/1e6),"wait_and_session":int((e0-t0)/1e6),"encode":int((end-e0)/1e6)})

    def stop(self):
        if self.pipeline is not None:
            try: self.pipeline.set_state(Gst.State.NULL)
            except Exception: pass
        self.pipeline=None; self.sample=None; self.frame_ns=0
        if self.pwfd is not None:
            try: os.close(self.pwfd)
            except OSError: pass
        self.pwfd=None
        if self.session: self.close_obj(self.session,"org.freedesktop.portal.Session")
        self.session=None

    def status(self):
        return env(True,"ok",{"state":"streaming" if self.active else "idle",
            "session_active":self.active,"portal_version":self.version if self.portal else None,
            "stream_generation":self.generation})

def listener():
    try: n=int(os.environ.get("LISTEN_FDS","0")); pid=int(os.environ.get("LISTEN_PID","0"))
    except ValueError: n=pid=0
    if n>=1 and pid==os.getpid():
        s=socket.fromfd(3,socket.AF_UNIX,socket.SOCK_STREAM); s.setblocking(True); return s
    private_dir(runtime_dir()); p=sock_path()
    try: p.unlink()
    except OSError: pass
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.bind(str(p)); os.chmod(p,0o600); s.listen(8); return s

def handle(cast,q):
    if q.get("v") not in (None,1): raise E("unsupported_protocol",2,False)
    op=q.get("op")
    if op=="status": return cast.status()
    if op=="close": cast.stop(); return env(True,"closed",{"state":"idle"})
    if op=="capture":
        fresh=q.get("fresh","next")
        if fresh not in ("next","latest"): raise E("invalid_freshness",2,False)
        return cast.capture(fresh,min(max(int(q.get("timeout_ms",1500)),50),10000))
    raise E("invalid_operation",2,False)

def serve():
    s=listener(); s.settimeout(1); cast=Cast()
    idle=min(max(int(os.environ.get("GWCU_OBSERVER_IDLE_SECONDS",DEFAULT_IDLE)),10),1800)
    last=time.monotonic(); stop=False
    def halt(*_):
        nonlocal stop; stop=True
    signal.signal(signal.SIGTERM,halt); signal.signal(signal.SIGINT,halt)
    try:
        while not stop and time.monotonic()-last < (idle if cast.active else 5):
            try: c,_=s.accept()
            except socket.timeout: continue
            with c:
                last=time.monotonic()
                try:
                    raw=b""
                    while b"\n" not in raw and len(raw)<=MAX_REQUEST:
                        x=c.recv(4096)
                        if not x: break
                        raw+=x
                    if len(raw)>MAX_REQUEST: raise E("request_too_large",2,False)
                    r=handle(cast,json.loads(raw.split(b"\n",1)[0].decode()))
                except E as ex:
                    r=env(False,ex.code,retryable=ex.retryable,terminal=ex.terminal,detail=ex.detail); r["_exit"]=ex.exit_code
                except Exception as ex:
                    r=env(False,"internal_error",retryable=False,terminal=False,detail=str(ex)); r["_exit"]=50
                c.sendall((json.dumps(r,separators=(",",":"))+"\n").encode())
    finally: cast.stop(); s.close()
    return 0

def client(op,fresh="next",timeout_ms=1500):
    q={"v":1,"op":op}
    if op=="capture": q|={"fresh":fresh,"timeout_ms":timeout_ms}
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(max(.1,min(10,timeout_ms/1000+.5)))
    try:
        s.connect(str(sock_path())); s.sendall((json.dumps(q,separators=(",",":"))+"\n").encode())
        raw=b""
        while b"\n" not in raw and len(raw)<262144:
            x=s.recv(4096)
            if not x: break
            raw+=x
        if not raw: raise E("broker_no_response")
        r=json.loads(raw.split(b"\n",1)[0]); rc=int(r.pop("_exit",0 if r.get("ok") else 40))
        print(json.dumps(r,separators=(",",":"))); return rc
    except (FileNotFoundError,ConnectionRefusedError):
        print(json.dumps(env(False,"broker_unavailable",retryable=True,terminal=False,next={"action":"start_observer_socket"}),separators=(",",":"))); return 30
    except E as ex:
        print(json.dumps(env(False,ex.code,retryable=ex.retryable,terminal=ex.terminal,detail=ex.detail),separators=(",",":"))); return ex.exit_code
    except Exception as ex:
        print(json.dumps(env(False,"broker_protocol_error",retryable=True,terminal=False,detail=str(ex)),separators=(",",":"))); return 40
    finally: s.close()

def selftest():
    p=runtime_dir(); private_dir(p); assert stat.S_IMODE(p.stat().st_mode)&0o077==0
    print(json.dumps({"schema":"gwcu.observer.selftest.v1","ok":True,"code":"ok",
        "checks":["private_runtime_dir","stable_envelope","lazy_gi_import"]},separators=(",",":"))); return 0

def main():
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest="cmd",required=True); sub.add_parser("serve"); sub.add_parser("self-test")
    c=sub.add_parser("client"); c.add_argument("op",choices=["capture","status","close"])
    c.add_argument("--fresh",choices=["next","latest"],default="next"); c.add_argument("--timeout-ms",type=int,default=1500)
    a=p.parse_args()
    if a.cmd=="serve": return serve()
    if a.cmd=="self-test": return selftest()
    return client(a.op,a.fresh,a.timeout_ms)
if __name__=="__main__": raise SystemExit(main())
