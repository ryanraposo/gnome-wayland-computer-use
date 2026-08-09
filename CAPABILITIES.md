# The Full Computer-Use Spread

**Native, closed-loop computer use for Ubuntu 26, GNOME 50, and Wayland.**

This is not a screenshot-and-hope macro layer. `gnome-wayland-computer-use` gives an agent a complete operating model for seeing, understanding, controlling, verifying, and recovering on the real Linux desktop.

## See the right thing

- Discover running applications and windows only when target identity is ambiguous.
- Cache resolved app/window identity until navigation, disappearance, or a failed scoped action invalidates it.
- Distinguish installed standalone web apps from the browser engine underneath them using desktop IDs, WM class, launch flags, and accessible identity.
- Capture a specific application instead of exposing the whole desktop.
- Read an **AX-only accessibility tree** as the default when text, roles, and state are sufficient.
- Capture a clean **vision image** only for visual reasoning.
- Capture in **SOM mode** with numbered visual targets plus accessibility only when both pixels and semantic grounding are required.
- Capture the **desktop layer**—wallpaper and desktop icons—without covering application windows.
- Capture the **visible screen**, including windows, through the GNOME screenshot stack.
- Route desktop and screen intent separately instead of pretending they mean the same thing.
- Work display-by-display with coordinates relative to the latest relevant image.

## Understand native interfaces

- Inspect accessible widgets, editable fields, buttons, menus, lists, sliders, dialogs, and window structure through AT-SPI.
- Scope dense Electron, Chromium, browser, and IDE accessibility trees to the intended application.
- Prefer stable semantic elements over brittle coordinates.
- Treat element references as short-lived tokens and re-observe at real invalidation boundaries: navigation, dialogs, changing lists, or a stale-element verdict.
- Distinguish nested scrolling regions instead of blindly scrolling the outer window.
- Resolve browser-backed app identity once instead of repeatedly searching or recapturing to rediscover the same PWA.

## Act across the whole desktop vocabulary

- Click, double-click, right-click, and middle-click.
- Type complete text in one semantic action instead of character-by-character loops.
- Send keyboard shortcuts as one hotkey action.
- Set accessible values directly for selects, popup controls, and sliders.
- Scroll vertically or horizontally, anchored to an element or coordinate, and verify at a meaningful boundary instead of after every notch.
- Drag and drop between accessible elements.
- Drag across canvases and inaccessible drop zones using fresh image coordinates.
- Fill forms, replace field values, submit, and verify the resulting state.
- Operate menus and native selectors.
- Handle modal dialogs and file choosers.
- Work across multiple windows and displays.
- Wait only for genuine asynchronous interface changes that provide no completion signal.

## Co-work without stealing the desktop

- Deliver supported AT-SPI actions in the background.
- Target application windows without raising them.
- Preserve the user’s foreground workflow whenever the application permits it.
- Escalate from semantic background action to pixel targeting only when needed.
- Escalate to foreground input only after the driver reports that background delivery is unavailable or ineffective.
- Use `/dev/uinput` through Ubuntu’s `ydotool` as an explicit final recovery layer.

The escalation ladder is intentional:

1. Accessible element, background delivery.
2. Pixel target from the latest image when semantics are unavailable.
3. Foreground delivery for the same action.
4. Raw synthetic input only after native paths and diagnostics are exhausted.

## Prove that actions worked without slowing everything down

Every task follows a decision-boundary loop:

> **Route → cheapest useful evidence → semantic action span → verify only what changed → continue.**

- Accept structured driver read-back when it directly proves the requested postcondition.
- Avoid duplicate post-action captures merely to prove that a verified action was verified.
- Avoid observations between deterministic, semantically coupled inputs when the next input does not depend on newly rendered state.
- Re-observe after navigation, new dialogs, materially changed lists, stale references, focus escalation, or visual ambiguity.
- Read structured driver verdicts such as confirmed, unverifiable, suspected no-op, or background unavailable.
- Verify text values, selection changes, moved objects, closed dialogs, opened pages, and other meaningful outcomes.
- Re-plan instead of repeating the same failed action blindly.
- Use atomic screenshot writes so failed capture attempts never replace a valid image.

## Capture GNOME properly

### Desktop layer

The GNOME Shell extension captures wallpaper and desktop icons while excluding application-window actors from the offscreen render. It verifies that focus, workspace, and window state remain unchanged.

A compatibility route can temporarily show the desktop, capture it, restore the previous state, and compare compositor state before reporting success. The compatibility path polls for the screenshot and compositor restoration instead of imposing fixed multi-second sleeps.

### Visible screen

The screen router uses the strongest available GNOME path in order:

1. Supported `gnome-screenshot --file` behavior.
2. The non-interactive `org.freedesktop.portal.Screenshot` request.
3. GNOME’s direct screenshot shortcut through `ydotool`.

Portal cancellation ends the chain cleanly instead of opening another chooser. ScreenCast/PipeWire remains an opt-in diagnostic fallback because it may present a sharing prompt. `capture.sh --timing` reports elapsed milliseconds without changing normal output.

## Cross the privilege boundary safely

- Present a narrow graphical PolicyKit prompt for an explicitly authorized package or host change.
- Run the smallest exact command through `pkexec`.
- Keep the installer itself unprivileged.
- Verify the result afterward without privilege.
- Avoid typing passwords, using `sudo -S`, or opening a general-purpose root shell.

## Diagnose and recover the stack

- Check GNOME and Wayland session compatibility.
- Verify toolkit accessibility and the AT-SPI bus.
- Inspect the persistent `cua-driver` service.
- Diagnose compositor capture, screenshot routing, focus preservation, coordinates, `/dev/uinput`, and synthetic input.
- Resolve installed browser/PWA/Electron launchers with `scripts/app-identity.sh` without taking a screenshot.
- Emit human-readable or JSON diagnostics.
- Preserve and restore existing Hermes computer-use and screenshot skills.
- Remove managed services, routing, extensions, udev rules, and skills through a deliberate teardown path.
- Keep first-use version checks cache-only so computer-use startup never waits on the network; explicit update checks may refresh the cache.

## Agent-native integration

The project ships independently authored integrations for their actual runtimes:

- A canonical Hermes `computer-use` skill with latency-aware AX/vision/SOM routing, semantic input spans, structured verification, and escalation.
- An OpenAI-native Agent Skill that follows the runtime’s live tool schema instead of inventing Hermes-shaped arguments.
- Shared GNOME host helpers for capture, installed-app identity, diagnostics, recovery, and teardown.
- One installer that selects the right integration while preserving existing agent configuration.

## The point

Linux agents should be able to do more than poke pixels at a screenshot.

They should understand the application, act through native semantics, stay out of the user’s way, cross system boundaries responsibly, spend round-trips only where a decision actually changes, verify every meaningful result, and recover intelligently when the ideal path is unavailable.

That is the computer-use surface this repository delivers.
