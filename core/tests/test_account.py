"""Akun page: GitHub-only sign-in with a token checked against the GitHub API."""

from aiohttp import web
from aiohttp.test_utils import TestServer

from neovarch import account
from neovarch import config as cfgmod

from test_server import _client


async def _fake_github():
    async def user(request):
        if request.headers.get("Authorization") != "Bearer good-token":
            return web.json_response({"message": "Bad credentials"}, status=401)
        return web.json_response({"login": "octo", "name": "Octo Cat", "avatar_url": "https://a/x.png",
                                  "html_url": "https://github.com/octo"}, headers={"X-OAuth-Scopes": "repo, read:org"})
    app = web.Application()
    app.router.add_get("/user", user)
    server = TestServer(app)
    await server.start_server()
    return server


async def test_github_account_connect_status_disconnect(home, monkeypatch):
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    gh = await _fake_github()
    monkeypatch.setattr(account, "API", str(gh.make_url("/user")))
    gw, c = await _client(monkeypatch, NEOVARCH_SESSION_TOKEN="tok")
    h = {"Authorization": "Bearer tok"}
    try:
        st = await (await c.get("/api/account/github", headers=h)).json()
        assert st == {"provider": "github", "connected": False}
        bad = await c.post("/api/account/github", json={"token": "nope"}, headers=h)
        assert bad.status == 200 and "ditolak" in (await bad.json())["error"]
        assert not account.token()
        ok = await (await c.post("/api/account/github", json={"token": " good-token "}, headers=h)).json()
        assert ok["login"] == "octo" and ok["connected"] and ok["scopes"] == ["repo", "read:org"]
        assert cfgmod.secret("GITHUB_TOKEN") == "good-token"
        assert account.shell_env() == {"GITHUB_TOKEN": "good-token", "GH_TOKEN": "good-token"}
        st = await (await c.get("/api/account/github", headers=h)).json()
        assert st["valid"] and st["login"] == "octo" and st["name"] == "Octo Cat"
        out = await (await c.delete("/api/account/github", headers=h)).json()
        assert out["connected"] is False and not account.token() and account.shell_env() == {}
    finally:
        await c.close()
        await gh.close()
