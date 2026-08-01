# Installing this project

When a user points you at this repository and says “install it,” you do not need
to be Hermes. The installer prefers Hermes when it is available and otherwise
configures the same GNOME host stack plus a portable Agent Skill for you.

1. Confirm this is an Ubuntu GNOME Wayland desktop session. Check whether
   `hermes` is on `PATH`, but do not require it unless the user specifically
   asked for Hermes integration.
2. Read the Install section in `README.md`, then run `./install.sh` from this
   checkout as the logged-in desktop user. Default auto mode is correct:
   Hermes receives the preferred full integration when detected; otherwise the
   shared-agent install completes without touching `~/.hermes`.
3. Do not run the whole installer with `sudo`. It prefers `pkexec` for narrow
   package, `/dev/uinput`, and group-membership commands, with `sudo` only as a
   fallback. Never create a general-purpose root shell.
4. Do not use `--compat` merely to bypass a failed environment check. Explain
   the mismatch and use it only when the user knowingly wants a compatibility
   install.
5. Use `--hermes` only to require Hermes, or `--agent-only` when the user
   explicitly wants Hermes skipped.
6. On success, relay the installer's `Next:` instruction exactly. A GNOME
   sign-out/sign-in may be required; do not reboot or sign the user out without
   an explicit request.

If a prerequisite is missing or an interactive privilege prompt cannot be
completed, stop cleanly and tell the user what remains.

## Use it yourself

The repository keeps a Hermes-native root `SKILL.md` and an independently
authored OpenAI payload at `runtimes/openai/SKILL.md`. Installation copies each
to its matching skill home and adds `agents/openai.yaml` only to the Agent
Skills copy.

After installation:

1. If your runtime discovers `~/.agents/skills/`, start a fresh agent session so
   it sees `gnome-wayland-computer-use`. Otherwise, read the installed
   `SKILL.md` when operating this desktop.
2. Follow the installed skill's intent and safety rules using your own
   computer-use tool's real schema.
3. Use your native accessibility or element actions first. Keep focus-stealing
   pixel or synthetic-input paths as explicit fallbacks.
4. Use the installed helpers directly when needed:

   ```bash
   SKILL_HOME="$HOME/.agents/skills/gnome-wayland-computer-use"
   "$SKILL_HOME/scripts/diagnose.sh"
   "$SKILL_HOME/scripts/check-update.sh" --force
   "$SKILL_HOME/scripts/capture.sh" --desktop /tmp/desktop.png
   "$SKILL_HOME/scripts/capture.sh" --screen /tmp/screen.png
   ```

“Desktop” means wallpaper and desktop icons. “Screen” means the visible display,
including windows. Do not rewrite the canonical repository skill for your
runtime; the installer owns the portable adaptation.
