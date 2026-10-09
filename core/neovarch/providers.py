"""Model providers for the desktop's Model / Providers settings and model picker.

* Built-in presets (``config.PRESETS``) are "connected" when their API key is in
  ``~/.neovarch/.env``.
* Custom endpoints are any OpenAI-compatible base URL: ``https://`` gateways and
  routers, or ``http://`` servers on localhost / a LAN IP with any port (LiteLLM,
  Ollama, LM Studio, 9router...). They live in ``custom_providers`` in
  ``config.yaml``; the API key and any custom headers live in ``.env``.
  ``allow_insecure_tls`` (off by default) accepts a self-signed certificate.

Everything is written under the Neovarch home, never in another agent's home.
"""

from __future__ import annotations

import json
import re
import ssl
from typing import Any
from urllib.parse import urlparse

import aiohttp

from neovarch import config as cfgmod

PROBE_TIMEOUT_S = 12
PRESET_LABELS = {"openai": "OpenAI", "openrouter": "OpenRouter", "groq": "Groq", "deepseek": "DeepSeek",
                 "ollama": "Ollama (lokal)"}
PRESET_MODELS = {
    "openai": ["gpt-4o-mini", "gpt-4o", "gpt-4.1", "gpt-4.1-mini", "o4-mini"],
    "openrouter": ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "google/gemini-2.0-flash-001",
                   "meta-llama/llama-3.3-70b-instruct", "deepseek/deepseek-chat"],
    "groq": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"],
    "deepseek": ["deepseek-chat", "deepseek-reasoner"],
    "ollama": ["llama3.1"],
}


class EndpointError(ValueError):
    pass


# --------------------------------------------------------------- helpers -----

def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", str(text or "").lower()).strip("-")[:48]


def env_key_for(eid: str, kind: str) -> str:
    return "NEOVARCH_EP_" + re.sub(r"[^A-Z0-9]+", "_", eid.upper()).strip("_") + "_" + kind


def normalize_base_url(raw: str) -> str:
    url = str(raw or "").strip()
    if not url:
        raise EndpointError("URL endpoint wajib diisi, mis. https://router.example.com/v1 atau http://127.0.0.1:20128/v1")
    if not re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", url):
        host = url.split("/", 1)[0].split(":", 1)[0]
        local = host in ("localhost",) or re.match(r"^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)", host)
        url = ("http://" if local else "https://") + url
    p = urlparse(url)
    if p.scheme not in ("http", "https"):
        raise EndpointError(f"skema {p.scheme}:// tidak didukung; pakai http:// atau https://")
    if not p.hostname:
        raise EndpointError("URL endpoint tidak punya host")
    try:
        _ = p.port  # validates the port number
    except ValueError:
        raise EndpointError("port pada URL tidak valid") from None
    return url.rstrip("/")


def parse_headers(raw: Any) -> dict[str, str]:
    """Headers as a dict, or text with one ``Name: value`` per line."""
    if not raw:
        return {}
    if isinstance(raw, dict):
        items = raw.items()
    else:
        items = []
        for line in str(raw).splitlines():
            if not line.strip():
                continue
            if ":" not in line:
                raise EndpointError(f"header tidak valid (pakai format Nama: nilai): {line.strip()[:60]}")
            k, v = line.split(":", 1)
            items.append((k, v))
    out: dict[str, str] = {}
    for k, v in items:
        k = str(k).strip()
        if not k:
            continue
        if not re.match(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$", k):
            raise EndpointError(f"nama header tidak valid: {k[:60]}")
        out[k] = str(v).strip()
    return out


def _ssl(insecure: bool):
    ctx = ssl.create_default_context()   # built per call so SSL_CERT_FILE / system CAs apply
    if not insecure:
        return ctx
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def _error_text(url: str, exc: BaseException) -> str:
    text = str(exc)
    if isinstance(exc, aiohttp.ClientConnectorCertificateError) or "CERTIFICATE_VERIFY_FAILED" in text:
        return (f"Sertifikat TLS {url} tidak tepercaya (self-signed?). Centang \u201cIzinkan sertifikat "
                "self-signed\u201d hanya jika Anda memercayai server ini.")
    if isinstance(exc, aiohttp.ClientConnectorError):
        return f"Tidak bisa terhubung ke {url}: {getattr(exc, 'os_error', None) or text}. Pastikan server berjalan dan port benar."
    if isinstance(exc, TimeoutError) or "Timeout" in type(exc).__name__:
        return f"Waktu habis menghubungi {url} ({PROBE_TIMEOUT_S} dtk)."
    return f"Gagal menghubungi {url}: {text or type(exc).__name__}"


async def probe(base_url: str, api_key: str = "", headers: dict[str, str] | None = None,
                insecure: bool = False) -> dict[str, Any]:
    """GET {base}/models (and {base}/v1/models for a bare root)."""
    try:
        base = normalize_base_url(base_url)
    except EndpointError as exc:
        return {"ok": False, "reachable": False, "message": str(exc), "models": [], "model_details": []}
    h = {"Accept": "application/json", **(headers or {})}
    if api_key:
        h["Authorization"] = f"Bearer {api_key}"
    candidates = [base]
    if not re.search(r"/v\d+[a-z]*$", base):
        candidates.append(base + "/v1")
    reachable = False
    last = ""
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=PROBE_TIMEOUT_S)) as s:
        for cand in candidates:
            url = cand + "/models"
            try:
                async with s.get(url, headers=h, ssl=_ssl(insecure)) as r:
                    reachable = True
                    body = await r.text(errors="replace")
                    if r.status in (401, 403):
                        return {"ok": False, "reachable": True, "models": [], "model_details": [],
                                "message": f"Server menolak kredensial (HTTP {r.status}). Periksa API key atau header.",
                                "resolved_base_url": cand}
                    if r.status >= 400:
                        last = f"HTTP {r.status} dari {url}"
                        continue
                    try:
                        data = json.loads(body)
                    except ValueError:
                        last = f"{url} tidak membalas JSON"
                        continue
                    rows = data.get("data") if isinstance(data, dict) else data
                    if isinstance(data, dict) and rows is None:
                        rows = data.get("models")
                    models: list[str] = []
                    for row in rows or []:
                        mid = row.get("id") or row.get("name") or row.get("model") if isinstance(row, dict) else row
                        if mid and str(mid) not in models:
                            models.append(str(mid))
                    return {"ok": True, "reachable": True, "models": models,
                            "model_details": [{"id": m} for m in models], "resolved_base_url": cand,
                            "transport_checked": "chat_completions",
                            "message": f"Terhubung. {len(models)} model ditemukan." if models else
                                       "Terhubung, tetapi daftar model kosong. Ketik ID model secara manual."}
            except Exception as exc:  # noqa: BLE001 - reported to the user
                if reachable:
                    last = _error_text(url, exc)
                    continue
                return {"ok": False, "reachable": False, "models": [], "model_details": [],
                        "message": _error_text(cand, exc)}
    return {"ok": False, "reachable": reachable, "models": [], "model_details": [], "resolved_base_url": base,
            "message": (f"Endpoint terjangkau, tetapi tidak menyediakan daftar model ({last}). "
                        "Ketik ID model secara manual.") if reachable else (last or "Endpoint tidak terjangkau.")}


# --------------------------------------------------------- custom endpoints ----

def _custom_list(cfg: dict) -> list[dict]:
    items = cfg.get("custom_providers")
    if not isinstance(items, list):
        items = []
        cfg["custom_providers"] = items
    return items


def _eid(spec: dict) -> str:
    return str(spec.get("id") or slugify(spec.get("name") or "") or "endpoint")


def current_provider(cfg: dict) -> str:
    return str(cfgmod.get_path(cfg, "model.provider", "") or "")


def _is_current(cfg: dict, spec: dict) -> bool:
    prov = current_provider(cfg)
    eid = _eid(spec)
    return prov in (f"custom:{eid}", f"custom:{spec.get('name')}")


def endpoint_view(cfg: dict, spec: dict) -> dict[str, Any]:
    eid = _eid(spec)
    key = cfgmod.secret(str(spec.get("key_env") or ""))
    headers = cfgmod.endpoint_headers(spec)
    models = [str(m) for m in spec.get("models") or [] if m]
    if spec.get("model") and spec["model"] not in models:
        models.insert(0, str(spec["model"]))
    return {
        "id": eid, "name": str(spec.get("name") or eid), "base_url": str(spec.get("base_url") or ""),
        "model": str(spec.get("model") or ""), "models": models,
        "context_length": spec.get("context_length"), "api_mode": spec.get("api_mode") or "",
        "discover_models": bool(spec.get("discover_models", True)),
        "has_api_key": bool(key), "api_key_preview": ("\u2022\u2022\u2022\u2022" + key[-4:]) if len(key) >= 8 else ("\u2022\u2022\u2022\u2022" if key else None),
        "header_names": sorted(headers), "allow_insecure_tls": bool(spec.get("allow_insecure_tls")),
        "is_current": _is_current(cfg, spec), "source": "config",
    }


def endpoints_response(cfg: dict, saved_id: str | None = None) -> dict[str, Any]:
    ep = cfgmod.resolve_endpoint(cfg)
    out = {"current": {"base_url": ep["base_url"], "model": ep["model"], "provider": ep["provider"]},
           "endpoints": [endpoint_view(cfg, s) for s in _custom_list(cfg) if isinstance(s, dict)], "ok": True}
    if saved_id:
        out["id"] = saved_id
    return out


def activate(cfg: dict, provider: str, model: str = "", base_url: str | None = None) -> None:
    cfgmod.set_path(cfg, "model.provider", provider)
    if model:
        cfgmod.set_path(cfg, "model.default", model)
    # A named provider supplies its own URL; a stale model.base_url would win over it.
    cfgmod.set_path(cfg, "model.base_url", base_url or "")


def save_endpoint(cfg: dict, body: dict) -> str:
    items = _custom_list(cfg)
    name = str(body.get("name") or "").strip()
    base = normalize_base_url(str(body.get("base_url") or ""))
    eid = slugify(body.get("id") or name or urlparse(base).hostname or "endpoint")
    if not eid:
        raise EndpointError("nama endpoint wajib diisi")
    existing = next((s for s in items if isinstance(s, dict) and _eid(s) == eid), None)
    spec = existing if existing is not None else {}
    spec.update({"id": eid, "name": name or spec.get("name") or eid, "base_url": base,
                 "model": str(body.get("model") or spec.get("model") or "").strip(),
                 "discover_models": bool(body.get("discover_models", spec.get("discover_models", True))),
                 "allow_insecure_tls": bool(body.get("allow_insecure_tls", spec.get("allow_insecure_tls", False)))})
    if body.get("api_mode") is not None:
        spec["api_mode"] = str(body.get("api_mode") or "")
    ctx = body.get("context_length")
    if isinstance(ctx, int) and ctx > 0:
        spec["context_length"] = ctx
    models = body.get("models")
    if isinstance(models, list):
        spec["models"] = [str(m) for m in models if m][:500]
    spec["key_env"] = env_key_for(eid, "API_KEY")
    if body.get("api_key"):
        cfgmod.write_env_value(spec["key_env"], str(body["api_key"]).strip())
    if "headers" in body and body.get("headers") is not None:
        headers = parse_headers(body.get("headers"))
        spec["headers_env"] = env_key_for(eid, "HEADERS")
        cfgmod.write_env_value(spec["headers_env"], json.dumps(headers, separators=(",", ":")))
    if existing is None:
        items.append(spec)
    if body.get("make_default") or not current_provider(cfg) or not cfgmod.resolve_endpoint(cfg)["base_url"]:
        if spec.get("model"):
            activate(cfg, f"custom:{eid}", spec["model"])
    return eid


def delete_endpoint(cfg: dict, eid: str) -> bool:
    items = _custom_list(cfg)
    keep = [s for s in items if not (isinstance(s, dict) and _eid(s) == eid)]
    if len(keep) == len(items):
        return False
    cfg["custom_providers"] = keep
    if current_provider(cfg) == f"custom:{eid}":
        cfgmod.set_path(cfg, "model.provider", "")
    for kind in ("API_KEY", "HEADERS"):
        cfgmod.write_env_value(env_key_for(eid, kind), "")
    return True


def find_endpoint(cfg: dict, eid: str) -> dict | None:
    return next((s for s in _custom_list(cfg) if isinstance(s, dict) and _eid(s) == eid), None)


# ------------------------------------------------------------ model options ---

def clean_models(models: Any) -> list[str]:
    """Non-empty, stripped, de-duplicated model ids (order kept)."""
    out: list[str] = []
    for m in models if isinstance(models, list) else []:
        mid = str(m or "").strip()
        if mid and mid not in out:
            out.append(mid)
    return out


def apply_discovered(spec: dict, served: list[str]) -> dict[str, Any]:
    """Replace a custom endpoint's model list with what its server really serves.

    Returns what was pruned and whether the endpoint's own model is unknown
    to the server (a dead pick such as a typo)."""
    served = clean_models(served)[:500]
    before = clean_models(spec.get("models"))
    spec["models"] = served
    spec["models_discovered"] = True
    model = str(spec.get("model") or "").strip()
    return {"removed": [m for m in before if m not in served],
            "model": model, "model_unknown": bool(model and served and model not in served)}


async def refresh_models(cfg: dict) -> dict[str, Any]:
    """Probe every custom endpoint that discovers models and prune dead ids."""
    report: dict[str, Any] = {}
    for spec in _custom_list(cfg):
        if not isinstance(spec, dict) or not spec.get("discover_models", True) or not spec.get("base_url"):
            continue
        res = await probe(str(spec["base_url"]), cfgmod.secret(str(spec.get("key_env") or "")),
                          cfgmod.endpoint_headers(spec), bool(spec.get("allow_insecure_tls")))
        if res.get("ok") and res.get("models"):
            report[_eid(spec)] = apply_discovered(spec, res["models"])
    return report


def model_options(cfg: dict, include_unconfigured: bool = False, endpoint: dict | None = None) -> dict[str, Any]:
    """The picker catalog. ``endpoint`` is a session's effective endpoint
    (its own pick), so the current row/model follow that session."""
    ep = endpoint or cfgmod.resolve_endpoint(cfg)
    current = ep["provider"]
    providers: list[dict[str, Any]] = []
    for slug, preset in cfgmod.PRESETS.items():
        key_env = preset.get("key_env") or ""
        authed = bool(cfgmod.secret(key_env)) if key_env else slug == "ollama"
        is_cur = current == slug
        if not (authed or is_cur or include_unconfigured):
            continue
        models = clean_models(PRESET_MODELS.get(slug, [preset["model"]]))
        if is_cur and ep["model"] and ep["model"] not in models:
            models.insert(0, ep["model"])
        providers.append({"slug": slug, "name": PRESET_LABELS.get(slug, slug), "models": models,
                          "total_models": len(models), "is_current": is_cur, "is_user_defined": False,
                          "api_url": preset["base_url"], "authenticated": authed, "key_env": key_env or None,
                          "source": "preset", "auth_type": "api_key" if key_env else "none"})
    for spec in _custom_list(cfg):
        if not isinstance(spec, dict):
            continue
        view = endpoint_view(cfg, spec)
        slug = f"custom:{view['id']}"
        is_cur = current in (slug, f"custom:{view['name']}")
        models = clean_models(view["models"])
        if spec.get("models_discovered") and spec.get("models"):
            # A discovered list is authoritative: drop ids the server no
            # longer serves, keeping only the live pick so it stays visible.
            served = clean_models(spec.get("models"))
            models = [m for m in models if m in served]
        unknown = bool(is_cur and ep["model"] and spec.get("models_discovered") and spec.get("models")
                       and ep["model"] not in clean_models(spec.get("models")))
        if is_cur and ep["model"] and ep["model"] not in models:
            models.insert(0, ep["model"])
        view["is_current"] = is_cur
        providers.append({"slug": slug, "name": view["name"], "models": models, "total_models": len(models),
                          "is_current": view["is_current"], "is_user_defined": True, "api_url": view["base_url"],
                          "authenticated": True, "key_env": spec.get("key_env"), "source": "custom",
                          "aliases": [view["name"]], "auth_type": "api_key" if view["has_api_key"] else "none",
                          **({"unknown_models": [ep["model"]]} if unknown else {})})
    if current and not any(p["is_current"] for p in providers) and ep["base_url"]:
        name = current.split(":", 1)[-1] or "custom"
        providers.insert(0, {"slug": current, "name": name, "models": [ep["model"]] if ep["model"] else [],
                             "total_models": 1 if ep["model"] else 0, "is_current": True, "is_user_defined": True,
                             "api_url": ep["base_url"], "authenticated": True, "source": "config"})
    providers.sort(key=lambda p: (not p["is_current"], not p["is_user_defined"], p["name"].lower()))
    return {"model": ep["model"], "provider": current, "providers": providers,
            "model_unknown": any(p.get("unknown_models") for p in providers if p["is_current"])}


def set_model(cfg: dict, body: dict) -> dict[str, Any]:
    if str(body.get("scope") or "main") != "main":
        task = str(body.get("task") or "")
        if task:
            cfgmod.set_path(cfg, f"auxiliary.{task}", {"provider": body.get("provider") or "", "model": body.get("model") or ""})
        return {"ok": True, "scope": "auxiliary", "provider": body.get("provider"), "model": body.get("model"),
                "tasks": [task] if task else []}
    provider = str(body.get("provider") or "").strip()
    model = str(body.get("model") or "").strip()
    if not provider and not model:
        raise EndpointError("provider atau model wajib diisi")
    entries = cfgmod.provider_entries(cfg)
    if provider and not provider.startswith("custom:") and provider not in cfgmod.PRESETS and provider in entries:
        provider = f"custom:{_eid(entries[provider])}"
    if not provider:
        provider = current_provider(cfg)
    base_url = None
    if provider in ("custom", "local") and body.get("base_url"):
        base_url = normalize_base_url(str(body["base_url"]))
        provider = "custom"
        if body.get("api_key"):
            cfgmod.write_env_value("OPENAI_API_KEY", str(body["api_key"]))
    elif provider == "custom":
        base_url = str(cfgmod.get_path(cfg, "model.base_url", "") or "") or None
    activate(cfg, provider, model, base_url)
    if provider.startswith("custom:"):
        spec = find_endpoint(cfg, provider.split(":", 1)[1])
        if spec is not None and model:
            # The endpoint's model only; never append to its model list, so a
            # typo (``depsek``) does not stay in the picker after it is replaced.
            spec["model"] = model
    ep = cfgmod.resolve_endpoint(cfg)
    return {"ok": True, "scope": "main", "provider": provider, "model": model or ep["model"],
            "base_url": ep["base_url"], "stale_aux": []}


# --------------------------------------------------------------- env vars -----

def env_vars() -> dict[str, dict[str, Any]]:
    env = cfgmod.read_env_file()
    out: dict[str, dict[str, Any]] = {}
    known = {p["key_env"]: slug for slug, p in cfgmod.PRESETS.items() if p.get("key_env")}
    for key in sorted(set(known) | {k for k in env if not k.startswith("NEOVARCH_EP_")}):
        value = env.get(key, "")
        slug = known.get(key)
        out[key] = {"advanced": False, "category": "provider" if slug else "other",
                    "description": f"API key {PRESET_LABELS.get(slug, slug)}" if slug else key,
                    "is_password": True, "is_set": bool(value),
                    "redacted_value": ("\u2022\u2022\u2022\u2022" + value[-4:]) if len(value) >= 8 else ("\u2022\u2022\u2022\u2022" if value else None),
                    "tools": [], "url": None, "provider": slug or "", "provider_label": PRESET_LABELS.get(slug, "") if slug else ""}
    return out


def preset_for_env(key: str) -> str | None:
    return next((slug for slug, p in cfgmod.PRESETS.items() if p.get("key_env") == key), None)
