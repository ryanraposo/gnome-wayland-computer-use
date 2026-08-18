"""Hermes compatibility shim for gnome-wayland-computer-use.

Hermes exposes installed skills as native slash commands. GWCU deliberately does
not register a plugin-level ``/computer-use`` command here: plugin commands take
precedence over skill commands and would consume free-form task text before the
computer-use skill can turn it into an agent request.

Keeping this tiny plugin in the install payload makes upgrades safe: the
installer can replace and retire older GWCU plugin copies that did register the
command, while the installed ``computer-use`` skill owns the canonical surface.
"""
from __future__ import annotations


def register(ctx):
    """Intentionally register no slash command; the installed skill owns it."""
    return None
