import os
from pathlib import Path

import pytest

from neovarch import config as cfgmod
from neovarch.paths import ForeignPathError, check_path, is_foreign_path, neovarch_home


def test_home_from_env(home):
    assert neovarch_home() == home
    for sub in ("sessions", "memory", "skills", "logs"):
        assert (home / sub).is_dir()


def test_default_home_is_dot_neovarch(monkeypatch):
    monkeypatch.delenv("NEOVARCH_HOME", raising=False)
    monkeypatch.setenv("HERMES_HOME", "/somewhere/.hermes")  # ignored on purpose
    assert neovarch_home() == Path.home() / ".neovarch"


def test_hermes_paths_are_foreign():
    h = os.path.expanduser("~/.hermes")
    assert is_foreign_path(h)
    assert is_foreign_path(h + "/config.yaml")
    assert is_foreign_path("~/.hermes/skills/x/SKILL.md")
    assert is_foreign_path(os.path.expanduser("~/.local/bin/hermes"))
    assert not is_foreign_path(os.path.expanduser("~/.hermes-notes.txt"))
    assert not is_foreign_path(os.path.expanduser("~/.neovarch/config.yaml"))
    with pytest.raises(ForeignPathError):
        check_path(h)


def test_config_roundtrip_and_env(home):
    cfg = cfgmod.load_config()
    assert cfg["approvals"]["mode"] == "ask"
    cfgmod.set_path(cfg, "model.default", "m1")
    cfgmod.save_config(cfg)
    assert cfgmod.load_config()["model"]["default"] == "m1"
    cfgmod.write_env_value("OPENAI_API_KEY", "sk-test")
    cfgmod.write_env_value("OPENAI_API_KEY", "sk-test2")
    assert cfgmod.read_env_file() == {"OPENAI_API_KEY": "sk-test2"}
    assert "sk-test" not in cfgmod.config_path().read_text()


def test_resolve_endpoint_presets_and_custom(home):
    cfg = cfgmod.load_config()
    cfg["model"] = {"provider": "groq", "default": ""}
    ep = cfgmod.resolve_endpoint(cfg)
    assert ep["base_url"].startswith("https://api.groq.com") and ep["model"] == "llama-3.3-70b-versatile"
    cfg["model"] = {"provider": "custom:Mock", "default": "x"}
    cfg["custom_providers"] = [{"name": "Mock", "base_url": "http://127.0.0.1:1/v1/", "api_key": "k"}]
    ep = cfgmod.resolve_endpoint(cfg)
    assert ep == {"base_url": "http://127.0.0.1:1/v1", "api_key": "k", "model": "x", "provider": "custom:Mock",
                  "headers": {}, "verify_ssl": True}


def test_soul_is_neovarch(home):
    assert "Neovarch Agent" in cfgmod.soul_text()
    assert "Hermes" not in cfgmod.soul_text()
