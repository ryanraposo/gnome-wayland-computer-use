#!/usr/bin/env python3
"""Execute an already-decided Cua/WORLDLINE transaction behind one model/tool boundary.

Cua Driver remains the sole actuator. WORLDLINE supplies revisioned waits,
postconditions, conflict detection, and predetermined local branches.
"""
from __future__ import annotations
import argparse, json, os
from pathlib import Path
import selectors, shutil, socket, subprocess, sys, time
from typing import Any

SCHEMA="gwcu.action-span.v1"; REQUEST_SCHEMA="gwcu.action-span.request.v1"; TRANSACTION_SCHEMA="gwcu.transaction.v1"
PROTOCOL="2024-11-05"; MAX_ACTIONS=64; MAX_TRANSITIONS=256; MAX=1<<20

def compact(value:Any)->str:return json.dumps(value,separators=(",",":"),ensure_ascii=True)
def resolve_driver(explicit:str|None)->str|None:
    if explicit:return explicit
    env=os.environ.get("CUA_DRIVER_BIN")
    if env:return env
    found=shutil.which("cua-driver")
    if found:return found
    candidate=Path.home()/".local/bin/cua-driver"
    return str(candidate) if candidate.is_file() and os.access(candidate,os.X_OK) else None
def worldline_socket(explicit:str|None)->Path:
    if explicit:return Path(explicit)
    root=Path(os.getenv("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}"))/"gnome-wayland-computer-use"
    return root/"worldline.sock"
def worldline_call(path:Path,payload:dict[str,Any],timeout:float)->dict[str,Any]:
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.settimeout(timeout)
    try:
        s.connect(str(path));s.sendall((compact(payload)+"\n").encode());buf=bytearray()
        while b"\n" not in buf and len(buf)<=MAX:
            b=s.recv(65536)
            if not b:break
            buf.extend(b)
    finally:s.close()
    if len(buf)>MAX:raise RuntimeError("WORLDLINE response too large")
    if not buf:raise RuntimeError("WORLDLINE closed without a response")
    return json.loads(bytes(buf).split(b"\n",1)[0])

def send(proc:subprocess.Popen[str],payload:dict[str,Any])->None:
    assert proc.stdin is not None;proc.stdin.write(compact(payload)+"\n");proc.stdin.flush()
def recv_for(proc:subprocess.Popen[str],request_id:int,timeout:float)->dict[str,Any]:
    assert proc.stdout is not None;selector=selectors.DefaultSelector();selector.register(proc.stdout,selectors.EVENT_READ);deadline=time.monotonic()+timeout
    try:
        while True:
            remaining=deadline-time.monotonic()
            if remaining<=0 or not selector.select(remaining):raise TimeoutError(f"timed out waiting for MCP response id={request_id}")
            line=proc.stdout.readline()
            if not line:raise RuntimeError("cua-driver MCP exited before responding")
            msg=json.loads(line)
            if msg.get("id")==request_id:return msg
    finally:selector.close()

def normalize_result(result:Any)->Any:
    if not isinstance(result,dict):return result
    structured=result.get("structuredContent",result.get("structured_content"))
    return structured if structured is not None else result.get("content",result)
def explicit_boundary(response:dict[str,Any])->tuple[bool,str|None]:
    if "error" in response:return True,"mcp_error"
    result=response.get("result")
    if not isinstance(result,dict):return True,"invalid_result"
    if result.get("isError") is True:return True,"cua_error"
    structured=result.get("structuredContent",result.get("structured_content"))
    if isinstance(structured,dict):
        if structured.get("ok") is False or structured.get("success") is False:return True,"cua_failure"
        if structured.get("refused") is True:return True,"cua_refusal"
    return False,None

def normalize_action(raw:dict[str,Any],index:int)->dict[str,Any]:
    name=raw.get("name");arguments=raw.get("arguments",{})
    if not isinstance(name,str) or not name.strip():raise ValueError(f"action {index} requires a name")
    if not isinstance(arguments,dict):raise ValueError(f"action {index} arguments must be an object")
    return {"name":name,"arguments":arguments}

def parse_request(raw:str)->dict[str,Any]:
    value=json.loads(raw)
    if isinstance(value,list):value={"schema":REQUEST_SCHEMA,"actions":value}
    if not isinstance(value,dict):raise ValueError("request must be an object or action array")
    schema=value.get("schema")
    if schema not in (None,REQUEST_SCHEMA,TRANSACTION_SCHEMA):raise ValueError("unsupported request schema")
    if "steps" in value:
        steps=value["steps"]
        if not isinstance(steps,list) or not steps:raise ValueError("steps must be a non-empty array")
        if len(steps)>MAX_ACTIONS:raise ValueError(f"transaction exceeds {MAX_ACTIONS} steps")
        out=[]
        for i,step in enumerate(steps):
            if not isinstance(step,dict):raise ValueError(f"step {i} must be an object")
            action=step.get("action",step if "name" in step else None)
            if not isinstance(action,dict):raise ValueError(f"step {i} requires action")
            item={"action":normalize_action(action,i)}
            if "await" in step:
                if not isinstance(step["await"],dict):raise ValueError(f"step {i} await must be an object")
                item["await"]=step["await"]
            if "next" in step:
                if not isinstance(step["next"],(int,dict)):raise ValueError(f"step {i} next must be an index or branch map")
                item["next"]=step["next"]
            out.append(item)
        return {"schema":TRANSACTION_SCHEMA,"steps":out,"start":int(value.get("start",0))}
    actions=value.get("actions")
    if not isinstance(actions,list) or not actions:raise ValueError("actions must be a non-empty JSON array")
    if len(actions)>MAX_ACTIONS:raise ValueError(f"action span exceeds {MAX_ACTIONS} actions")
    return {"schema":REQUEST_SCHEMA,"steps":[{"action":normalize_action(a,i)} for i,a in enumerate(actions)]}

def envelope(ok:bool,code:str,*,requested:int=0,completed:int=0,results:list[dict[str,Any]]|None=None,boundary:dict[str,Any]|None=None,detail:str|None=None,revision:int|None=None)->dict[str,Any]:
    payload={"schema":SCHEMA,"ok":ok,"code":code,"requested":requested,"completed":completed,"results":results or [],"boundary":boundary}
    if detail:payload["detail"]=detail
    if revision is not None:payload["revision"]=revision
    return payload

def next_index(step:dict[str,Any],current:int,wait_result:dict[str,Any]|None,total:int)->int:
    nxt=step.get("next")
    if isinstance(nxt,int):return nxt
    if isinstance(nxt,dict):
        branch=(wait_result or {}).get("matched_branch")
        if branch is not None and branch in nxt:return int(nxt[branch])
        if "default" in nxt:return int(nxt["default"])
        if branch is not None:raise RuntimeError(f"no next target for branch {branch}")
    return current+1

def run(driver:str,request:dict[str,Any],timeout:float,wlsock:Path)->tuple[dict[str,Any],int]:
    steps=request["steps"];requested=len(steps)
    try:
        proc=subprocess.Popen([driver,"mcp"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,encoding="utf-8",errors="replace",bufsize=1)
    except OSError as exc:return envelope(False,"driver_unavailable",requested=requested,detail=str(exc)),50
    results=[];completed=0;last_revision=None
    try:
        send(proc,{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":PROTOCOL,"capabilities":{},"clientInfo":{"name":"gwcu-action-span","version":"2.3.0"}}})
        init=recv_for(proc,1,timeout)
        if "error" in init or not isinstance(init.get("result"),dict):return envelope(False,"mcp_initialize_failed",requested=requested,detail=compact(init)),50
        send(proc,{"jsonrpc":"2.0","method":"notifications/initialized"})
        index=int(request.get("start",0));transition=0;request_id=2
        while 0<=index<requested:
            transition+=1
            if transition>MAX_TRANSITIONS:return envelope(False,"boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"reason":"transition_limit"}),30
            step=steps[index];action=step["action"];baseline_revision=last_revision
            if "await" in step:
                try:
                    status=worldline_call(wlsock,{"op":"status"},3.0)
                    if status.get("ok"):baseline_revision=status.get("revision",baseline_revision)
                except (OSError,TimeoutError,RuntimeError,json.JSONDecodeError) as exc:
                    return envelope(False,"worldline_boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"name":action["name"],"reason":"worldline_unavailable_before_action"},detail=str(exc),revision=last_revision),50
            send(proc,{"jsonrpc":"2.0","id":request_id,"method":"tools/call","params":{"name":action["name"],"arguments":action["arguments"]}})
            response=recv_for(proc,request_id,timeout);request_id+=1
            result=normalize_result(response.get("result"));is_boundary,reason=explicit_boundary(response)
            record={"index":index,"name":action["name"],"result":result};results.append(record)
            if is_boundary:return envelope(False,"boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"name":action["name"],"reason":reason},revision=last_revision),30
            completed+=1;wait_result=None
            if "await" in step:
                await_spec=dict(step["await"]);await_spec["op"]="wait"
                if baseline_revision is not None:await_spec.setdefault("after_revision",baseline_revision)
                wait_timeout=max(1.0,min(float(await_spec.get("timeout_ms",5000))/1000+2,122.0))
                try:wait_result=worldline_call(wlsock,await_spec,wait_timeout)
                except (OSError,TimeoutError,RuntimeError,json.JSONDecodeError) as exc:
                    return envelope(False,"worldline_boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"name":action["name"],"reason":"worldline_unavailable"},detail=str(exc),revision=last_revision),50
                record["worldline"]=wait_result;last_revision=wait_result.get("revision",last_revision)
                if not wait_result.get("ok"):
                    return envelope(False,"boundary",requested=requested,completed=completed,results=results,boundary={"index":index,"name":action["name"],"reason":f"worldline_{wait_result.get('code','failure')}","worldline":wait_result},revision=last_revision),30
            index=next_index(step,index,wait_result,requested)
        return envelope(True,"completed",requested=requested,completed=completed,results=results,revision=last_revision),0
    except (TimeoutError,RuntimeError,ValueError,json.JSONDecodeError) as exc:
        return envelope(False,"transport_boundary",requested=requested,completed=completed,results=results,detail=str(exc),revision=last_revision),50
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:proc.wait(timeout=1)
            except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=1)

def main()->int:
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--driver");p.add_argument("--worldline-socket");p.add_argument("--timeout",type=float,default=15.0)
    group=p.add_mutually_exclusive_group(required=True);group.add_argument("--actions-json");group.add_argument("--stdin",action="store_true");args=p.parse_args()
    raw=sys.stdin.read() if args.stdin else args.actions_json
    assert raw is not None
    try:req=parse_request(raw)
    except (ValueError,json.JSONDecodeError) as exc:print(compact(envelope(False,"invalid_request",detail=str(exc))));return 2
    driver=resolve_driver(args.driver)
    if not driver:print(compact(envelope(False,"driver_missing",requested=len(req["steps"]))));return 50
    payload,rc=run(driver,req,max(1.0,min(args.timeout,120.0)),worldline_socket(args.worldline_socket));print(compact(payload));return rc
if __name__=="__main__":raise SystemExit(main())
