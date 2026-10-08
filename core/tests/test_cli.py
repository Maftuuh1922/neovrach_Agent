import os
import subprocess
import sys
from pathlib import Path

CORE = Path(__file__).resolve().parent.parent


def run(*args, env):
    return subprocess.run([sys.executable, "-m", "neovarch", *args], env=env, capture_output=True, text=True, timeout=30)


def _env(tmp_path):
    env = {k: v for k, v in os.environ.items() if not k.startswith(("HERMES_", "NEOVARCH_"))}
    env.update(HOME=str(tmp_path), NEOVARCH_HOME=str(tmp_path / ".neovarch"), PYTHONPATH=str(CORE))
    return env


def test_version_reports_install_directory(tmp_path):
    r = run("--version", env=_env(tmp_path))
    assert r.returncode == 0, r.stderr
    assert "Neovarch" in r.stdout
    assert f"Install directory: {CORE}" in r.stdout


def test_profile_lives_under_neovarch_home(tmp_path):
    env = _env(tmp_path)
    r = run("--profile", "work", "config", "path", env=env)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(tmp_path / ".neovarch" / "profiles" / "work" / "config.yaml")
    r = run("-p", "default", "config", "path", env=env)
    assert r.stdout.strip() == str(tmp_path / ".neovarch" / "config.yaml")
    assert run("--profile", "../x", "config", "path", env=env).returncode == 2
    assert not (tmp_path / ".hermes").exists()
