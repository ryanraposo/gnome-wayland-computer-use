"""Hermes integration for gnome-wayland-computer-use.

The installed skill owns ``/computer-use`` task dispatch. This plugin is enabled
by the installer and makes three policies mechanical instead of advisory:

* direct native ``computer_use`` input inherits GWCU's saved delivery mode;
* foreground input is admitted only after exact Cua/GNOME presentation proof;
* closed local apps are ACQUIREd through Cua ``launch_app`` and bound to the
  exact newly-created ``(pid, window_id)`` before later discovery/input.

The running gateway also writes a small identity attestation so GWCU doctor can
compare the Cua binary selected inside Hermes with the installed/doctor binary.
"""
from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

_INPUT_ACTIONS = frozenset({
    "click", "double_click", "right_click", "middle_click",
    "drag", "scroll", "type", "key",
})
_TRUE = frozenset({"on", "yes", "true", "1", "background"})
_SUBCOMMANDS = (
    "status",
    "trace",
    "present",
    "list-windows",
    "cursor-color",
    "background",
    "managed",
    "truths",
    "consent",
    "doctor",
    "help",
)


def _standing_delivery_mode() -> str:
    raw = os.getenv("GWCU_BACKGROUND_PRIORITY")
    if raw is None:
        state_home = Path(os.getenv("XDG_STATE_HOME", str(Path.home() / ".local/state")))
        path = state_home / "gnome-wayland-computer-use" / "background-priority"
        try:
            raw = path.read_text().strip()
        except OSError:
            raw = "off"
    return "background" if str(raw).strip().casefold() in _TRUE else "foreground"


def _presenter() -> Path:
    override = os.getenv("GWCU_PRESENTER")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".agents/skills/gnome-wayland-computer-use/scripts/present-window.py"


def _resolver() -> Path:
    override = os.getenv("GWCU_APP_RESOLVER")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".agents/skills/gnome-wayland-computer-use/scripts/app-identity.sh"


def _exact_target(call: dict) -> tuple[int, int] | None:
    pid = call.get("pid")
    window_id = call.get("window_id")
    if (
        isinstance(pid, int)
        and not isinstance(pid, bool)
        and pid > 0
        and isinstance(window_id, int)
        and not isinstance(window_id, bool)
        and 0 <= window_id <= (1 << 32) - 1
    ):
        return pid, window_id
    return None


def _present_exact(call: dict) -> dict:
    target = _exact_target(call)
    if target is None:
        return {
            "ok": False,
            "code": "exact_target_required_for_foreground",
            "detail": "foreground native input requires exact integer pid + window_id",
        }
    pid, window_id = target
    presenter = _presenter()
    try:
        proc = subprocess.run(
            [
                sys.executable,
                str(presenter),
                "present",
                "--pid",
                str(pid),
                "--window-id",
                str(window_id),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "code": "presentation_transport_failed", "detail": str(exc)}
    try:
        result = json.loads(proc.stdout.strip()) if proc.stdout.strip() else {}
    except json.JSONDecodeError:
        result = {"ok": False, "code": "presentation_invalid_output", "detail": proc.stdout[:1024]}
    if proc.returncode != 0 and result.get("ok") is not False:
        result = {"ok": False, "code": "presentation_failed", "detail": proc.stderr[:1024]}
    return result


def _resolve_local_app(query: str) -> dict:
    if not isinstance(query, str) or not query.strip():
        return {"ok": False, "code": "app_required", "detail": "launch_app requires app=<local application>"}
    resolver = _resolver()
    try:
        proc = subprocess.run(
            [str(resolver), "--resolve", "--machine", query.strip()],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "code": "app_resolution_failed", "detail": str(exc)}
    try:
        result = json.loads(proc.stdout.strip()) if proc.stdout.strip() else {}
    except json.JSONDecodeError:
        return {"ok": False, "code": "app_resolution_invalid", "detail": proc.stdout[:1024]}
    if proc.returncode != 0 or not result.get("ok"):
        return {
            "ok": False,
            "code": result.get("code", "app_resolution_failed"),
            "detail": result.get("detail") or result.get("candidates") or query,
        }
    identity = result.get("result") or {}
    if not identity.get("display_name") or not identity.get("desktop_id"):
        return {"ok": False, "code": "app_identity_incomplete", "detail": identity}
    return {"ok": True, "identity": identity}


def _window_rows(value) -> list[dict]:
    if isinstance(value, list):
        return [row for row in value if isinstance(row, dict)]
    if isinstance(value, dict):
        rows = value.get("windows")
        if isinstance(rows, list):
            return [row for row in rows if isinstance(row, dict)]
    return []


def _window_key(row: dict) -> tuple[int, int] | None:
    pid, window_id = row.get("pid"), row.get("window_id")
    if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0 and isinstance(window_id, int) and not isinstance(window_id, bool):
        return pid, window_id
    return None


def _acquire_app(call: dict, kwargs: dict) -> str:
    """Resolve -> Cua launch_app -> bind one exact newly-created native window."""
    resolved = _resolve_local_app(call.get("app", ""))
    if not resolved.get("ok"):
        return json.dumps({"schema": "gwcu.acquire.v1", **resolved}, separators=(",", ":"))

    try:
        from tools.computer_use import tool as computer_use_tool
        backend = computer_use_tool._get_backend(str(kwargs.get("session_id") or ""))
    except Exception as exc:
        return json.dumps({
            "schema": "gwcu.acquire.v1", "ok": False, "code": "cua_backend_unavailable", "detail": str(exc)
        }, separators=(",", ":"))

    request_approval = getattr(computer_use_tool, "_request_approval", None)
    if callable(request_approval):
        refusal = request_approval("launch_app", call)
        if refusal is not None:
            return refusal

    identity = resolved["identity"]
    before_rows = _window_rows(backend.list_windows())
    before = {key for row in before_rows if (key := _window_key(row)) is not None}
    try:
        launched = backend.launch_app(name=identity["display_name"])
    except Exception as exc:
        return json.dumps({
            "schema": "gwcu.acquire.v1", "ok": False, "code": "launch_app_failed",
            "app": identity, "detail": str(exc),
        }, separators=(",", ":"))

    launched_pid = launched.get("pid") if isinstance(launched, dict) else None
    deadline = time.monotonic() + 5.0
    last_new: list[dict] = []
    while time.monotonic() < deadline:
        rows = _window_rows(backend.list_windows())
        new_rows = [row for row in rows if (key := _window_key(row)) is not None and key not in before]
        if isinstance(launched_pid, int) and launched_pid > 0:
            pid_rows = [row for row in new_rows if row.get("pid") == launched_pid]
            if pid_rows:
                new_rows = pid_rows
        last_new = new_rows
        if len(new_rows) == 1:
            row = new_rows[0]
            target = {"pid": row["pid"], "window_id": row["window_id"]}
            return json.dumps({
                "schema": "gwcu.acquire.v1", "ok": True, "code": "acquired",
                "phase": "ACQUIRE", "app": identity, "target": target,
                "launch": launched, "next": {"action": "present", **target},
            }, separators=(",", ":"), ensure_ascii=False)
        if len(new_rows) > 1:
            return json.dumps({
                "schema": "gwcu.acquire.v1", "ok": False, "code": "new_window_ambiguous",
                "app": identity, "launch": launched,
                "candidates": [{"pid": r.get("pid"), "window_id": r.get("window_id"), "title": r.get("title")} for r in new_rows],
                "next": None,
            }, separators=(",", ":"), ensure_ascii=False)
        time.sleep(0.05)

    return json.dumps({
        "schema": "gwcu.acquire.v1", "ok": False, "code": "new_window_not_observed",
        "app": identity, "launch": launched,
        "candidates": [{"pid": r.get("pid"), "window_id": r.get("window_id"), "title": r.get("title")} for r in last_new],
        "next": {"action": "discover_existing"},
    }, separators=(",", ":"), ensure_ascii=False)


def _gateway_identity_path() -> Path:
    state_home = Path(os.getenv("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    state = state_home / "gnome-wayland-computer-use"
    state.mkdir(parents=True, exist_ok=True)
    try:
        state.chmod(0o700)
    except OSError:
        pass
    home = os.getenv("HERMES_HOME", str(Path.home() / ".hermes"))
    token = hashlib.sha256(os.path.realpath(home).encode()).hexdigest()[:12]
    return state / f"hermes-gateway-identity-{token}.json"


def _write_gateway_identity() -> None:
    """Attest the Cua identity selected by the *running* Hermes process."""
    try:
        from tools.computer_use.cua_backend_driver import cua_driver_runtime_contract_status, resolve_cua_driver_cmd
        selected = resolve_cua_driver_cmd()
        contract = cua_driver_runtime_contract_status(selected) if selected else {"version": None}
        selected_real = os.path.realpath(selected) if selected else None
        payload = {
            "schema": "gwcu.hermes-gateway-identity.v1",
            "pid": os.getpid(),
            "hermes_home": os.getenv("HERMES_HOME", str(Path.home() / ".hermes")),
            "environment": {key: os.getenv(key) for key in (
                "DISPLAY", "WAYLAND_DISPLAY", "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "XDG_RUNTIME_DIR",
                "HERMES_CUA_DRIVER_CMD",
            )},
            "hermes_selected": {"binary": selected_real, "version": contract.get("version")},
            "gateway_backend": {"binary": selected_real, "version": contract.get("version"), "kind": "cua-driver"},
        }
        path = _gateway_identity_path()
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
        tmp.chmod(0o600)
        os.replace(tmp, path)
    except Exception:
        # Diagnostics treat a missing live attestation as unproved. Plugin load
        # must not break Hermes merely because the diagnostic write failed.
        pass


def _wrap_builtin(handler):
    def gwcu_computer_use(args: dict, **kwargs):
        call = dict(args or {})
        action = call.get("action")
        if action == "launch_app":
            return _acquire_app(call, kwargs)
        if action in _INPUT_ACTIONS:
            if "delivery_mode" not in call:
                call["delivery_mode"] = _standing_delivery_mode()
            if call.get("delivery_mode") == "foreground":
                presentation = _present_exact(call)
                if not presentation.get("ok"):
                    raise RuntimeError(
                        "GWCU refused foreground input before actuation: "
                        + json.dumps(presentation, separators=(",", ":"))
                    )
        return handler(call, **kwargs)

    return gwcu_computer_use


def _override_allowed(ctx) -> bool:
    """Honor modern capability consent; recognize the pre-capability API."""
    has_capability = getattr(ctx, "has_capability", None)
    if callable(has_capability):
        return bool(has_capability("tools.override"))
    return callable(getattr(ctx, "register_tool", None))


def _install_completion_contract(ctx) -> None:
    """Expose GWCU operator verbs after ``/computer-use `` in Hermes CLI.

    Hermes normally treats text after a skill slash as either another stacked
    skill or free-form task text and therefore returns before its static
    subcommand completer. GWCU is intentionally dual-use (task + operator
    subcommands), so mark this one skill as non-stackable *for completion only*
    and publish its reserved verbs in the ordinary SUBCOMMANDS table. Runtime
    skill dispatch is untouched.
    """
    try:
        from hermes_cli import commands as commands_mod

        commands_mod.SUBCOMMANDS["/computer-use"] = list(_SUBCOMMANDS)
        cls = commands_mod.SlashCommandCompleter
        marker = "_gwcu_original_is_skill_command"
        if not hasattr(cls, marker):
            original = cls._is_skill_command
            setattr(cls, marker, original)

            def _gwcu_is_skill_command(self, token: str) -> bool:
                normalized = self._normalize_skill_token(token)
                if normalized == "/computer-use":
                    return False
                return original(self, token)

            cls._is_skill_command = _gwcu_is_skill_command

            on_unload = getattr(ctx, "on_unload", None)
            if callable(on_unload):
                def restore() -> None:
                    try:
                        cls._is_skill_command = getattr(cls, marker)
                        delattr(cls, marker)
                        commands_mod.SUBCOMMANDS.pop("/computer-use", None)
                    except Exception:
                        pass
                on_unload(restore)
    except Exception:
        # Completion enrichment is ergonomic only; runtime control policy must
        # still load even on an older Hermes build without this completer.
        pass


def _extend_schema(schema: dict) -> None:
    params = schema.setdefault("parameters", {})
    props = params.setdefault("properties", {})
    action = props.setdefault("action", {})
    enum = action.setdefault("enum", [])
    if "launch_app" not in enum:
        enum.append("launch_app")
    props.setdefault("app", {"type": "string"})
    action["description"] = (
        str(action.get("description", ""))
        + " `launch_app` is GWCU ACQUIRE: resolve a local .desktop app, invoke Cua launch_app, "
          "and return only after one exact new (pid, window_id) is bound."
    )


def register(ctx):
    """Enforce control policy and install /computer-use completion metadata."""
    _install_completion_contract(ctx)
    _write_gateway_identity()

    if not _override_allowed(ctx):
        return None

    try:
        from tools.computer_use.schema import COMPUTER_USE_SCHEMA
        from tools.computer_use.tool import handle_computer_use
    except Exception:
        return None

    schema = copy.deepcopy(COMPUTER_USE_SCHEMA)
    _extend_schema(schema)
    schema["description"] = (
        "GWCU control authority for Ubuntu GNOME Wayland via cua-driver. "
        "For a closed local app, ACQUIRE first with action=launch_app and app=<name>; "
        "GWCU resolves the installed app, calls Cua launch_app, and binds the exact new pid/window_id. "
        "Never substitute a terminal launch or desktop-search workaround. "
        "Default foreground native input MUST include exact pid and window_id; "
        "GWCU first proves persistent visible presentation through Cua's "
        "GNOME helper, then admits the input. Use list_windows to DISCOVER an already-running target "
        "only after ACQUIRE has established that no new target was created. For typed browser work, bind the exact "
        "native browser pid/window_id and keep visible presentation as a separate postcondition. "
        + str(schema.get("description", ""))
    )
    ctx.register_tool(
        name="computer_use",
        toolset="computer_use",
        schema=schema,
        handler=_wrap_builtin(handle_computer_use),
        override=True,
    )
    return None
