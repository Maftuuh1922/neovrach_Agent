"""Update check against GitHub Releases (the only update channel Neovarch has).

``GET /api/update`` answers whether a newer release than this core exists. The
desktop shows a banner and the phone remote shows one too, both linking to the
release page. Nothing is downloaded or installed automatically.
"""

from __future__ import annotations

import os
import re
import time

import aiohttp

from neovarch import __version__

REPO = "Maftuuh1922/neovrach_Agent"
RELEASES_URL = f"https://api.github.com/repos/{REPO}/releases/latest"
RELEASES_PAGE = f"https://github.com/{REPO}/releases/latest"
CACHE_S = 6 * 3600
FAIL_CACHE_S = 15 * 60

_cache: dict = {"at": 0.0, "data": None}


def parse_version(v: str) -> tuple[int, ...]:
    m = re.match(r"^\s*v?(\d+(?:\.\d+)*)", str(v or ""))
    return tuple(int(x) for x in m.group(1).split(".")) if m else ()


def is_newer(latest: str, current: str) -> bool:
    a, b = parse_version(latest), parse_version(current)
    if not a or not b:
        return False
    n = max(len(a), len(b))
    return a + (0,) * (n - len(a)) > b + (0,) * (n - len(b))


def _asset_for(assets: list[dict], platform: str) -> str | None:
    pats = {"linux": (r"linux.*\.(tar\.gz|AppImage|deb)$",), "windows": (r"win.*\.(zip|exe)$",),
            "android": (r"\.apk$",)}.get(platform, ())
    for pat in pats:
        for a in assets:
            if re.search(pat, str(a.get("name") or ""), re.I):
                return a.get("browser_download_url")
    return None


def summarize(release: dict, current: str = __version__, platform: str = "") -> dict:
    tag = str(release.get("tag_name") or "")
    latest = tag.lstrip("v") or None
    url = release.get("html_url") or RELEASES_PAGE
    return {"current": current, "latest": latest, "tag": tag or None,
            "available": bool(latest) and is_newer(latest, current), "url": url,
            "download_url": _asset_for(release.get("assets") or [], platform) or url,
            "name": release.get("name") or tag or None, "published_at": release.get("published_at"),
            "notes": (release.get("body") or "")[:4000]}


async def check(*, force: bool = False, platform: str = "", current: str = __version__) -> dict:
    now = time.time()
    data = _cache["data"]
    ttl = CACHE_S if data and not data.get("error") else FAIL_CACHE_S
    if not force and data is not None and now - _cache["at"] < ttl:
        release = data
    else:
        url = os.environ.get("NEOVARCH_RELEASES_URL") or RELEASES_URL
        try:
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=10)) as s:
                async with s.get(url, headers={"Accept": "application/vnd.github+json",
                                               "User-Agent": f"neovarch-agent/{current}"}) as r:
                    if r.status == 404:
                        release = {}
                    elif r.status >= 400:
                        release = {"error": f"GitHub menjawab HTTP {r.status}"}
                    else:
                        release = await r.json(content_type=None)
        except Exception as exc:  # offline is normal; never fail the request
            release = {"error": f"Tidak bisa mengecek pembaruan: {type(exc).__name__}"}
        _cache.update(at=now, data=release)
    out = summarize(release if not release.get("error") else {}, current, platform)
    out["checked_at"] = _cache["at"]
    if release.get("error"):
        out["error"] = release["error"]
    return out
