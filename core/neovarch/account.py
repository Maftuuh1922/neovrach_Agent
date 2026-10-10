"""The desktop's Akun page: sign in with GitHub only.

A GitHub token (fine-grained or classic personal access token) is checked
against ``GET https://api.github.com/user`` and kept in ``~/.neovarch/.env`` as
``GITHUB_TOKEN``. The agent's shell commands get it as ``GITHUB_TOKEN`` and
``GH_TOKEN`` so ``git``/``gh`` work for the signed-in account. Nothing else is
an account in Neovarch; model providers use API keys or custom endpoints.
"""

from __future__ import annotations

from typing import Any

import aiohttp

from neovarch import config as cfgmod

TOKEN_ENV = "GITHUB_TOKEN"
LOGIN_ENV = "NEOVARCH_GITHUB_LOGIN"
API = "https://api.github.com/user"
TIMEOUT_S = 12


def token() -> str:
    return cfgmod.secret(TOKEN_ENV).strip()


def shell_env() -> dict[str, str]:
    """Variables the agent's shell gets for the signed-in GitHub account."""
    tok = token()
    return {"GITHUB_TOKEN": tok, "GH_TOKEN": tok} if tok else {}


async def lookup(tok: str, api: str = "") -> dict[str, Any]:
    """Who ``tok`` belongs to, or an Indonesian error the page can show."""
    headers = {"Accept": "application/vnd.github+json", "Authorization": f"Bearer {tok}",
               "User-Agent": "Neovarch-Agent", "X-GitHub-Api-Version": "2022-11-28"}
    try:
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=TIMEOUT_S)) as s:
            async with s.get(api or API, headers=headers) as r:
                if r.status in (401, 403):
                    return {"ok": False, "error": "Token GitHub ditolak (HTTP %d). Buat token baru lalu coba lagi." % r.status}
                if r.status >= 400:
                    return {"ok": False, "error": f"GitHub menjawab HTTP {r.status}."}
                data = await r.json(content_type=None)
                scopes = [x.strip() for x in (r.headers.get("X-OAuth-Scopes") or "").split(",") if x.strip()]
    except Exception as exc:  # noqa: BLE001 - shown to the user
        return {"ok": False, "error": f"GitHub tidak terjangkau: {exc.__class__.__name__}."}
    if not isinstance(data, dict) or not data.get("login"):
        return {"ok": False, "error": "Jawaban GitHub tidak berisi akun."}
    return {"ok": True, "login": str(data["login"]), "name": data.get("name") or "",
            "avatar_url": data.get("avatar_url") or "", "html_url": data.get("html_url") or "",
            "scopes": scopes}


async def status(api: str = "") -> dict[str, Any]:
    tok = token()
    if not tok:
        return {"provider": "github", "connected": False}
    info = await lookup(tok, api)
    if not info.get("ok"):
        # Keep the saved login visible so the user knows which account broke.
        return {"provider": "github", "connected": True, "valid": False,
                "login": cfgmod.secret(LOGIN_ENV), "error": info.get("error")}
    return {"provider": "github", "connected": True, "valid": True, **{k: v for k, v in info.items() if k != "ok"}}


async def connect(tok: str, api: str = "") -> dict[str, Any]:
    tok = (tok or "").strip()
    if not tok:
        return {"ok": False, "error": "Tempel token GitHub terlebih dahulu."}
    info = await lookup(tok, api)
    if not info.get("ok"):
        return info
    cfgmod.write_env_value(TOKEN_ENV, tok)
    cfgmod.write_env_value(LOGIN_ENV, info["login"])
    return {**info, "provider": "github", "connected": True, "valid": True}


def disconnect() -> dict[str, Any]:
    cfgmod.write_env_value(TOKEN_ENV, "")
    cfgmod.write_env_value(LOGIN_ENV, "")
    return {"ok": True, "provider": "github", "connected": False}
