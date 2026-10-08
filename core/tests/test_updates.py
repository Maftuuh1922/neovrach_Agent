"""Update check: version maths and /api/update against a fake GitHub releases API."""
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from neovarch import updates
from neovarch.server import Gateway, build_app


def test_version_compare():
    assert updates.is_newer("1.4.0", "1.3.0") and updates.is_newer("v1.10.0", "1.9.9")
    assert updates.is_newer("2", "1.9") and not updates.is_newer("1.3.0", "1.3")
    assert not updates.is_newer("1.3.0", "1.4.0") and not updates.is_newer("garbage", "1.0")


async def test_update_endpoint(home, monkeypatch, aiohttp_unused_port=None):
    hits = []

    async def latest(request):
        hits.append(request.headers.get("User-Agent"))
        return web.json_response({"tag_name": "v9.9.0", "name": "Neovarch 9.9", "html_url": "https://example.test/r/v9.9.0",
                                  "body": "Catatan rilis", "assets": [
                                      {"name": "Neovarch-9.9.0-linux-x64.tar.gz", "browser_download_url": "https://dl/linux"},
                                      {"name": "neovarch-remote-arm64-v8a.apk", "browser_download_url": "https://dl/apk"}]})
    fake = web.Application()
    fake.router.add_get("/latest", latest)
    gh = TestServer(fake)
    await gh.start_server()
    monkeypatch.setenv("NEOVARCH_RELEASES_URL", str(gh.make_url("/latest")))
    monkeypatch.setenv("HERMES_DASHBOARD_SESSION_TOKEN", "tok")
    updates._cache.update(at=0.0, data=None)
    c = TestClient(TestServer(build_app(Gateway(isolated=False))))
    await c.start_server()
    try:
        d = await (await c.get("/api/update?token=tok&platform=android")).json()
        assert d["available"] and d["latest"] == "9.9.0" and d["download_url"] == "https://dl/apk"
        assert d["url"] == "https://example.test/r/v9.9.0" and d["notes"] == "Catatan rilis"
        d2 = await (await c.get("/api/update?token=tok&platform=linux")).json()
        assert d2["download_url"] == "https://dl/linux" and len(hits) == 1  # cached
        await gh.close()
        d3 = await (await c.get("/api/update?token=tok&force=1")).json()
        assert d3["available"] is False and "error" in d3  # offline: quiet, no 5xx
    finally:
        await c.close()
        updates._cache.update(at=0.0, data=None)
