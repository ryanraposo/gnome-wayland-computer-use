import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

Gio._promisify(Shell.Screenshot.prototype, 'screenshot_stage_to_content');
Gio._promisify(Shell.Screenshot, 'composite_to_stream');

const SERVICE = 'io.github.ryanraposo.GnomeWaylandDesktopCapture';
const OBJECT_PATH = '/io/github/ryanraposo/GnomeWaylandDesktopCapture';

const IFACE = `
<node>
  <interface name="${SERVICE}">
    <method name="CaptureDesktop">
      <arg name="filename" type="s" direction="in"/>
      <arg name="ok" type="b" direction="out"/>
      <arg name="message" type="s" direction="out"/>
      <arg name="proof_json" type="s" direction="out"/>
    </method>
  </interface>
</node>
`;

const DesktopCaptureDBus = GObject.registerClass(
class DesktopCaptureDBus extends GObject.Object {
    constructor() {
        super();
        this._dbusObject = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbusObject.export(Gio.DBus.session, OBJECT_PATH);
        this._nameId = Gio.DBus.session.own_name(
            SERVICE,
            Gio.BusNameOwnerFlags.NONE,
            null,
            () => log(`GNOME Wayland Desktop Capture lost ${SERVICE}`));
    }

    destroy() {
        if (this._nameId) {
            Gio.DBus.session.unown_name(this._nameId);
            this._nameId = 0;
        }
        this._dbusObject?.unexport();
        this._dbusObject?.run_dispose();
        this._dbusObject = null;
    }

    async CaptureDesktopAsync([filename], invocation) {
        const path = String(filename ?? '').trim();
        if (!this._isAllowedPath(path)) {
            this._return(invocation, false,
                'Output must be an absolute PNG path under /tmp or XDG_RUNTIME_DIR',
                {});
            return;
        }

        const actors = global.get_window_actors()
            .filter(actor => actor?.visible)
            .filter(actor => {
                const window = actor.meta_window ?? actor.get_meta_window?.();
                return window?.get_window_type?.() !== Meta.WindowType.DESKTOP;
            });
        const before = this._snapshotState(actors);
        const opacities = actors.map(actor => actor.opacity);
        let stream = null;

        try {
            // DING removes its desktop actor from get_window_actors(). Making
            // the remaining app-window actors transparent therefore exposes
            // the real wallpaper/icons layer without minimizing, activating,
            // moving, or changing workspace for any window.
            actors.forEach(actor => actor.set_opacity(0));

            const screenshot = new Shell.Screenshot();
            const [content, scale] = await screenshot.screenshot_stage_to_content();
            actors.forEach((actor, index) => actor.set_opacity(opacities[index]));

            const after = this._snapshotState(actors);
            const stable = JSON.stringify(before) === JSON.stringify(after);
            if (!stable)
                throw new Error('window focus, workspace, or state changed during capture');

            const file = Gio.File.new_for_path(path);
            stream = file.replace(
                null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null);
            await Shell.Screenshot.composite_to_stream(
                content.get_texture(),
                0, 0, -1, -1,
                scale,
                null, 0, 0, 1,
                stream
            );
            stream.close(null);
            stream = null;

            const [width, height] = global.stage.get_size();
            this._return(invocation, true, path, {
                source: 'gnome-shell-desktop-layer',
                hidden_app_actors: actors.length,
                focus_unchanged: before.focused === after.focused,
                workspace_unchanged: before.workspace === after.workspace,
                window_state_unchanged: stable,
                width: Math.round(width),
                height: Math.round(height),
            });
        } catch (error) {
            actors.forEach((actor, index) => actor.set_opacity(opacities[index]));
            try {
                stream?.close(null);
            } catch (_) {
                // Preserve the original capture error.
            }
            this._return(invocation, false, String(error), {});
        }
    }

    _snapshotState(actors) {
        const workspace = global.workspace_manager.get_active_workspace_index();
        const focused = global.display.focus_window?.get_stable_sequence?.() ?? null;
        const windows = actors.map(actor => {
            const window = actor.meta_window ?? actor.get_meta_window?.();
            return {
                id: window?.get_stable_sequence?.() ?? null,
                minimized: Boolean(window?.minimized),
                workspace: window?.get_workspace?.()?.index?.() ?? null,
                opacity: actor.opacity,
            };
        });
        return {workspace, focused, windows};
    }

    _return(invocation, ok, message, proof) {
        invocation.return_value(new GLib.Variant('(bss)', [
            ok,
            message,
            JSON.stringify(proof),
        ]));
    }

    _isAllowedPath(path) {
        if (!GLib.path_is_absolute(path) || !path.endsWith('.png'))
            return false;
        const canonical = GLib.canonicalize_filename(path, null);
        const directory = GLib.path_get_dirname(canonical);
        const runtime = GLib.canonicalize_filename(
            GLib.get_user_runtime_dir(), null);
        return directory === '/tmp' || directory === runtime;
    }
});

export default class DesktopCaptureExtension extends Extension {
    enable() {
        this._server = new DesktopCaptureDBus();
    }

    disable() {
        this._server?.destroy();
        this._server = null;
    }
}
