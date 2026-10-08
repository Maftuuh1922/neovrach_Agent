import sys
from pathlib import Path

import pytest
from aiohttp.test_utils import TestServer

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import mock_llm  # noqa: E402


@pytest.fixture
def home(tmp_path, monkeypatch):
    h = tmp_path / "nvhome"
    monkeypatch.setenv("NEOVARCH_HOME", str(h))
    for k in ("OPENAI_API_KEY", "NEOVARCH_API_KEY", "HERMES_DASHBOARD_SESSION_TOKEN",
              "HERMES_DASHBOARD_BASIC_AUTH_SECRET", "NEOVARCH_SESSION_TOKEN", "NEOVARCH_REMOTE_SECRET"):
        monkeypatch.delenv(k, raising=False)
    from neovarch.paths import ensure_home
    ensure_home()
    return h


@pytest.fixture
async def mock_provider(home):
    server = TestServer(mock_llm.build_app(delay=0))
    await server.start_server()
    from neovarch import config as cfgmod
    cfg = cfgmod.load_config()
    cfg["model"] = {"provider": "custom", "default": "mock-model",
                    "base_url": str(server.make_url("/v1")), "context_length": 1000}
    cfgmod.save_config(cfg)
    yield server
    await server.close()
