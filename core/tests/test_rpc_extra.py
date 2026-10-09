"""Chat RPCs beyond the core loop: attachments, cwd, history, context, steer, close."""

import base64

from test_server import WS, _client


async def test_chat_rpcs(mock_provider, monkeypatch, tmp_path):
    gw, c = await _client(monkeypatch, NEOVARCH_SESSION_TOKEN="tok")
    try:
        ws = WS(await c.ws_connect("/api/ws?token=tok"))
        await ws.pump()
        sid = (await ws.call("session.create", {"source": "desktop"}))["result"]["session_id"]

        # cwd
        res = (await ws.call("session.cwd.set", {"session_id": sid, "cwd": str(tmp_path)}))["result"]
        assert res["cwd"] == str(tmp_path) and "branch" in res
        bad = await ws.call("session.cwd.set", {"session_id": sid, "cwd": str(tmp_path / "nope")})
        assert bad["error"]["code"] == -32602

        # attachments: bytes, data url, host path, missing file
        img = (await ws.call("image.attach_bytes", {"session_id": sid, "filename": "a.png",
                                                     "content_base64": base64.b64encode(b"PNG").decode()}))["result"]
        assert img["attached"] and img["text"].startswith("@file:") and img["bytes"] == 3
        doc = tmp_path / "catatan.txt"
        doc.write_text("isi", encoding="utf-8")
        f = (await ws.call("file.attach", {"session_id": sid, "path": str(doc), "name": "catatan.txt"}))["result"]
        assert f["attached"] and f["ref_text"] == f"@file:{doc}"
        du = (await ws.call("file.attach", {"session_id": sid, "name": "x.txt",
                                            "data_url": "data:text/plain;base64," + base64.b64encode(b"hi").decode()}))["result"]
        assert du["attached"] and du["uploaded"]
        missing = (await ws.call("image.attach", {"session_id": sid, "path": str(tmp_path / "x.png")}))["result"]
        assert missing["attached"] is False and "tidak ditemukan" in missing["message"]
        assert (await ws.call("image.detach", {"session_id": sid, "path": img["path"]}))["result"]["ok"]

        # a turn, then history / context breakdown / steer while idle
        await ws.call("prompt.submit", {"session_id": sid, "text": "halo"})
        await ws.until("message.complete")
        hist = (await ws.call("session.history", {"session_id": sid}))["result"]
        assert [m["role"] for m in hist["messages"]] == ["user", "assistant"]
        ctx = (await ws.call("session.context_breakdown", {"session_id": sid}))["result"]
        assert ctx["total"] > 0 and {i["key"] for i in ctx["items"]} == {"system", "user", "assistant", "tool"}
        ws.events.clear()
        steer = (await ws.call("session.steer", {"session_id": sid, "text": "lagi"}))["result"]
        assert steer["ok"]
        await ws.until("message.complete")

        one = (await ws.call("llm.oneshot", {"prompt": "halo"}))["result"]
        assert "halo" in one["text"]
        assert (await ws.call("process.stop", {}))["result"]["ok"]
        assert (await ws.call("session.close", {"session_id": sid}))["result"]["ok"]
        assert sid not in gw.live
        assert (await ws.call("voice.speak", {}))["error"]["code"] == -32601
    finally:
        await c.close()
