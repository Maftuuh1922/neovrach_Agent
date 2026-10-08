"""Neovarch Agent core.

An original agent runtime for the Neovarch desktop and phone apps: an
OpenAI-compatible chat loop with tool calling, sessions/memory/skills under
``~/.neovarch``, and ``neovarch serve`` — an HTTP + WebSocket gateway whose wire
format is compatible with what the Neovarch desktop (derived from Hermes
Desktop) and the Neovarch phone remote speak. The design is inspired by Hermes
Agent (Nous Research); no Hermes Agent code is included.
"""

__version__ = "1.3.0"
PRODUCT = "Neovarch Agent"
