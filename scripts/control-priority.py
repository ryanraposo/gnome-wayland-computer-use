#!/usr/bin/env python3
"""Resolve foreground/background control priority without another model call."""
from __future__ import annotations
import argparse, json, os
from pathlib import Path
from typing import Any

SCHEMA="gwcu.control-priority.v1"; LOW=.40; HIGH=.60

def compact(v:Any)->str:return json.dumps(v,separators=(",",":"),ensure_ascii=True)
def preference()->tuple[str,str]:
    raw=os.getenv("GWCU_BACKGROUND_PRIORITY")
    if raw is not None:return ("background" if raw.casefold() in {"on","yes","true","1","background"} else "foreground","environment")
    p=Path(os.getenv("XDG_STATE_HOME",str(Path.home()/".local/state")))/"gnome-wayland-computer-use/background-priority"
    try:raw=p.read_text().strip().casefold()
    except OSError:raw="off"
    return ("background" if raw in {"on","yes","true","1","background"} else "foreground","saved" if p.is_file() else "default")

def resolve(confidence:float|None=None,explicit:str|None=None)->dict[str,Any]:
    pref,source=preference(); mode=explicit if explicit in {"background","foreground"} else None
    if mode:reason="explicit_intent"
    elif confidence is None or LOW<=confidence<=HIGH:mode=pref;reason="standing_preference"
    elif confidence<LOW:mode="background";reason="intent"
    else:mode="foreground";reason="intent"
    conflict=mode!=pref
    notice="Doing that now — switching to foreground. OK?" if conflict and mode=="foreground" else None
    return {"schema":SCHEMA,"ok":True,"mode":mode,"reason":reason,"standing_preference":pref,"preference_source":source,"foreground_confidence":confidence,"deadband":[LOW,HIGH],"contradicts_preference":conflict,"notice":notice,"extra_model_calls":0}

def main()->int:
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--foreground-confidence",type=float);p.add_argument("--explicit",choices=["background","foreground"]);a=p.parse_args()
    if a.foreground_confidence is not None and not 0<=a.foreground_confidence<=1:p.error("confidence must be 0..1")
    print(compact(resolve(a.foreground_confidence,a.explicit)));return 0
if __name__=="__main__":raise SystemExit(main())
