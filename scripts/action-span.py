#!/usr/bin/env python3
"""Execute a Cua/WORLDLINE transaction behind one model/tool boundary."""
from __future__ import annotations
import argparse,json,os,socket,subprocess,sys
from pathlib import Path
from typing import Any
from mcp_client import recv_for, resolve_driver, send
SCHEMA="gwcu.action-span.v1";REQUEST_SCHEMA="gwcu.action-span.request.v1";TRANSACTION_SCHEMA="gwcu.transaction.v1";PROTOCOL="2024-11-05";MAX_ACTIONS=64;MAX_TRANSITIONS=256;MAX=1<<20;LOW=.40;HIGH=.60

def compact(v:Any)->str:return json.dumps(v,separators=(",",":"),ensure_ascii=True)
def standing_preference():
    raw=os.getenv("GWCU_BACKGROUND_PRIORITY")
    if raw is not None:return ("background" if raw.casefold() in {"on","yes","true","1","background"} else "foreground","environment")
    p=Path(os.getenv("XDG_STATE_HOME",str(Path.home()/".local/state")))/"gnome-wayland-computer-use/background-priority"
    try:raw=p.read_text().strip().casefold()
    except OSError:raw="off"
    return ("background" if raw in {"on","yes","true","1","background"} else "foreground","saved" if p.is_file() else "default")
def resolve_control(c):
    pref,source=standing_preference();score=c.get("foreground_confidence");explicit=c.get("explicit_mode")
    if explicit in {"background","foreground"}:mode=explicit;reason="explicit_intent"
    elif score is None or LOW<=score<=HIGH:mode=pref;reason="standing_preference"
    elif score<LOW:mode="background";reason="intent"
    else:mode="foreground";reason="intent"
    conflict=mode!=pref
    return {"schema":"gwcu.control-priority.v1","mode":mode,"reason":reason,"standing_preference":pref,"preference_source":source,"foreground_confidence":score,"deadband":[LOW,HIGH],"contradicts_preference":conflict,"notice":"Doing that now — switching to foreground. OK?" if conflict and mode=="foreground" else None,"extra_model_calls":0}
def worldline_socket(x):return Path(x) if x else Path(os.getenv("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}"))/"gnome-wayland-computer-use/worldline.sock"
def worldline_call(path,payload,timeout):
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.settimeout(timeout)
    try:
        s.connect(str(path));s.sendall((compact(payload)+"\n").encode());b=bytearray()
        while b"\n" not in b and len(b)<=MAX:
            x=s.recv(65536)
            if not x:break
            b.extend(x)
    finally:s.close()
    if not b:raise RuntimeError("WORLDLINE closed without response")
    return json.loads(bytes(b).split(b"\n",1)[0])
def structured(response):
    r=response.get("result") if isinstance(response,dict) else None
    if not isinstance(r,dict):return None
    s=r.get("structuredContent",r.get("structured_content"));return s if isinstance(s,dict) else None
def normalize_result(response):
    r=response.get("result") if isinstance(response,dict) else None
    if not isinstance(r,dict):return r
    s=structured(response);return s if s is not None else r.get("content",r)
def boundary(response):
    if "error" in response:return True,"mcp_error"
    r=response.get("result")
    if not isinstance(r,dict):return True,"invalid_result"
    if r.get("isError") is True:return True,"cua_error"
    s=structured(response)
    if s and (s.get("ok") is False or s.get("success") is False):return True,"cua_failure"
    if s and s.get("refused") is True:return True,"cua_refusal"
    return False,None
def background_unavailable(response):
    blob=compact(structured(response) or {}).casefold();return any(x in blob for x in ("background_unavailable","background unavailable","foreground_required","foreground required"))
def normalize_action(raw,i):
    n=raw.get("name");a=raw.get("arguments",{})
    if not isinstance(n,str) or not n.strip():raise ValueError(f"action {i} requires a name")
    if not isinstance(a,dict):raise ValueError(f"action {i} arguments must be an object")
    return {"name":n,"arguments":a}
def normalize_control(v):
    if v is None:return {}
    if not isinstance(v,dict):raise ValueError("control must be an object")
    c=v.get("foreground_confidence");e=v.get("explicit_mode")
    if c is not None and (not isinstance(c,(int,float)) or isinstance(c,bool) or not 0<=float(c)<=1):raise ValueError("foreground_confidence must be 0..1")
    if e not in (None,"background","foreground"):raise ValueError("explicit_mode must be background|foreground")
    return {"foreground_confidence":None if c is None else float(c),"explicit_mode":e}
def start_index(value,size):
    if value is None:return 0
    if not isinstance(value,int) or isinstance(value,bool) or not 0<=value<size:
        raise ValueError(f"start must be an integer in 0..{size-1}")
    return value
def valid_target(t,size):
    if isinstance(t,int) and not isinstance(t,bool):return 0<=t<size
    if isinstance(t,dict):
        return all(isinstance(v,int) and not isinstance(v,bool) and 0<=v<size for v in t.values())
    return False
def parse_request(raw):
    v=json.loads(raw)
    if isinstance(v,list):v={"schema":REQUEST_SCHEMA,"actions":v}
    if not isinstance(v,dict) or v.get("schema") not in (None,REQUEST_SCHEMA,TRANSACTION_SCHEMA):raise ValueError("unsupported request schema")
    control=normalize_control(v.get("control"));steps=v.get("steps")
    if steps is not None:
        if not isinstance(steps,list) or not steps or len(steps)>MAX_ACTIONS:raise ValueError("invalid steps")
        out=[]
        for i,s in enumerate(steps):
            if not isinstance(s,dict):raise ValueError(f"step {i} must be an object")
            a=s.get("action",s if "name" in s else None)
            if not isinstance(a,dict):raise ValueError(f"step {i} requires action")
            item={"action":normalize_action(a,i)}
            if "await" in s:
                if not isinstance(s["await"],dict):raise ValueError(f"step {i} await must be an object")
                item["await"]=s["await"]
            if "next" in s:
                if not valid_target(s["next"],len(steps)):raise ValueError(f"step {i} next targets must be indices in 0..{len(steps)-1}")
                item["next"]=s["next"]
            out.append(item)
        return {"schema":TRANSACTION_SCHEMA,"steps":out,"start":start_index(v.get("start"),len(out)),"control":control}
    actions=v.get("actions")
    if not isinstance(actions,list) or not actions or len(actions)>MAX_ACTIONS:raise ValueError("actions must be a non-empty bounded array")
    out=[{"action":normalize_action(a,i)} for i,a in enumerate(actions)]
    return {"schema":REQUEST_SCHEMA,"steps":out,"start":start_index(v.get("start"),len(out)),"control":control}
def envelope(ok,code,**kw):
    p={"schema":SCHEMA,"ok":ok,"code":code,"requested":kw.get("requested",0),"completed":kw.get("completed",0),"results":kw.get("results",[]),"boundary":kw.get("boundary")}
    for k in ("detail","revision","control"):
        if kw.get(k) is not None:p[k]=kw[k]
    return p
def next_index(step,current,wait_result,total):
    n=step.get("next")
    if isinstance(n,int):target=n
    elif isinstance(n,dict):
        b=(wait_result or {}).get("matched_branch")
        if b in n:target=int(n[b])
        elif "default" in n:target=int(n["default"])
        elif b is not None:raise RuntimeError(f"no next target for branch {b}")
        else:return current+1
    else:return current+1
    if not 0<=target<total:raise ValueError(f"next target {target} out of range 0..{total-1}")
    return target
def tool_modes(response):
    out={};r=response.get("result") if isinstance(response,dict) else None
    for t in (r.get("tools",[]) if isinstance(r,dict) else []):
        if not isinstance(t,dict) or not isinstance(t.get("name"),str):continue
        schema=t.get("inputSchema",t.get("input_schema",{}));props=schema.get("properties",{}) if isinstance(schema,dict) else {}
        if isinstance(props,dict) and "delivery_mode" in props:out[t["name"]]=True
    return out
def run(driver,request,timeout,wlsock):
    steps=request["steps"];requested=len(steps);control=resolve_control(request.get("control",{}));overrides=[]
    try:p=subprocess.Popen([driver,"mcp"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,encoding="utf-8",errors="replace",bufsize=1)
    except OSError as e:return envelope(False,"driver_unavailable",requested=requested,detail=str(e),control=control),50
    results=[];completed=0;last_revision=None
    try:
        send(p,{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":PROTOCOL,"capabilities":{},"clientInfo":{"name":"gwcu-action-span","version":"2.3.0"}}});init=recv_for(p,1,timeout)
        if "error" in init:return envelope(False,"mcp_initialize_failed",requested=requested,detail=compact(init),control=control),50
        send(p,{"jsonrpc":"2.0","method":"notifications/initialized"});send(p,{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}})
        try:modes=tool_modes(recv_for(p,2,min(timeout,5)))
        except Exception:modes={}
        index=request["start"];transition=0;request_id=3
        while 0<=index<requested:
            transition+=1
            if transition>MAX_TRANSITIONS:return envelope(False,"boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"reason":"transition_limit"},control=control),30
            step=steps[index];action=step["action"];baseline=last_revision
            if "await" in step:
                try:
                    s=worldline_call(wlsock,{"op":"status"},3);baseline=s.get("revision",baseline) if s.get("ok") else baseline
                except Exception as e:return envelope(False,"worldline_boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"reason":"worldline_unavailable_before_action"},detail=str(e),revision=last_revision,control=control),50
            args=dict(action["arguments"]);supports=bool(modes.get(action["name"]));applied=None
            if supports and "delivery_mode" not in args:args["delivery_mode"]=control["mode"];applied=control["mode"]
            elif "delivery_mode" in args:applied=args["delivery_mode"]
            send(p,{"jsonrpc":"2.0","id":request_id,"method":"tools/call","params":{"name":action["name"],"arguments":args}});response=recv_for(p,request_id,timeout);request_id+=1
            fallback=False
            if applied=="background" and supports and background_unavailable(response):
                fallback=True;overrides.append({"index":index,"from":"background","to":"foreground","reason":"cua_background_unavailable"});args["delivery_mode"]="foreground"
                send(p,{"jsonrpc":"2.0","id":request_id,"method":"tools/call","params":{"name":action["name"],"arguments":args}});response=recv_for(p,request_id,timeout);request_id+=1
            result=normalize_result(response);bad,reason=boundary(response);record={"index":index,"name":action["name"],"result":result,"control":{"requested":control["mode"],"delivery_mode_supported":supports,"applied":args.get("delivery_mode") if supports else "driver_default","fallback":fallback}};results.append(record)
            if bad:
                control["runtime_overrides"]=overrides;return envelope(False,"boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"name":action["name"],"reason":reason},revision=last_revision,control=control),30
            completed+=1;wait_result=None
            if "await" in step:
                spec=dict(step["await"]);spec["op"]="wait"
                if baseline is not None:spec.setdefault("after_revision",baseline)
                try:wait_result=worldline_call(wlsock,spec,max(1,min(float(spec.get("timeout_ms",5000))/1000+2,122)))
                except Exception as e:return envelope(False,"worldline_boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"reason":"worldline_unavailable"},detail=str(e),revision=last_revision,control=control),50
                record["worldline"]=wait_result;last_revision=wait_result.get("revision",last_revision)
                if not wait_result.get("ok"):return envelope(False,"boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"reason":f"worldline_{wait_result.get('code','failure')}"},revision=last_revision,control=control),30
            index=next_index(step,index,wait_result,requested)
        control["runtime_overrides"]=overrides;control["runtime_notice"]="Had to switch to foreground for this." if overrides else None
        return envelope(True,"completed",requested=requested,completed=completed,results=results,revision=last_revision,control=control),0
    except Exception as e:return envelope(False,"transport_boundary",requested=requested,completed=completed,results=results,detail=str(e),revision=last_revision,control=control),50
    finally:
        if p.poll() is None:
            p.terminate()
            try:p.wait(timeout=1)
            except subprocess.TimeoutExpired:p.kill();p.wait(timeout=1)
def main():
    p=argparse.ArgumentParser();p.add_argument("--driver");p.add_argument("--worldline-socket");p.add_argument("--timeout",type=float,default=15);g=p.add_mutually_exclusive_group(required=True);g.add_argument("--actions-json");g.add_argument("--stdin",action="store_true");a=p.parse_args();raw=sys.stdin.read() if a.stdin else a.actions_json
    try:req=parse_request(raw)
    except Exception as e:print(compact(envelope(False,"invalid_request",detail=str(e))));return 2
    d=resolve_driver(a.driver)
    if not d:print(compact(envelope(False,"driver_missing",requested=len(req["steps"]))));return 50
    out,rc=run(d,req,max(1,min(a.timeout,120)),worldline_socket(a.worldline_socket));print(compact(out));return rc
if __name__=="__main__":raise SystemExit(main())
