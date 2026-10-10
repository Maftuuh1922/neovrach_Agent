"""List every /api route and gateway RPC the desktop renderer references and how
the core answers it: a real handler, a quiet compat stub, the catch-all
fallback, or nothing (RPC -32601).

    python core/scripts/parity_audit.py [--json out.json] [--md out.md]

Run from the repo root (it reads desktop/apps/desktop/src and core/neovarch).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "desktop" / "apps" / "desktop" / "src"
sys.path.insert(0, str(ROOT / "core"))

PATH_RE = re.compile(r"""['"`](/api/[A-Za-z0-9_\-./{}$:]*)""")
RPC_RE = re.compile(r"""(?:requestGateway|guideRequest|gatewayRequest|request|rpc|call)\s*(?:<[^>()]*>)?\(\s*['"]([a-z_]+(?:\.[a-z_]+)+)['"]""")


def source_files():
    for p in sorted(SRC.rglob("*")):
        if p.suffix in (".ts", ".tsx") and ".test." not in p.name and "__tests__" not in p.parts:
            yield p


def renderer_refs():
    paths: dict[str, set[str]] = {}
    rpcs: dict[str, set[str]] = {}
    for p in source_files():
        text = re.sub(r"\$\{[^}]*\}", "x1", p.read_text(encoding="utf-8", errors="replace"))
        rel = str(p.relative_to(SRC))
        for m in PATH_RE.finditer(text):
            raw = m.group(1)
            raw = re.sub(r"\$\{[^}]*\}", "x1", raw).split("?")[0].rstrip("/")
            if raw in ("/api", ""):
                continue
            paths.setdefault(raw, set()).add(rel)
        for m in RPC_RE.finditer(text):
            rpcs.setdefault(m.group(1), set()).add(rel)
    return paths, rpcs


def classify_paths(paths):
    """real / stub / fallback for each path, matching any HTTP method."""
    from neovarch.server import Gateway, build_app

    app = build_app(Gateway(isolated=False))
    resources = [r for r in app.router.resources() if getattr(r, "canonical", "") != "/api/{tail}"]

    def match(resource, path):
        try:
            return resource._match(path) is not None
        except Exception:  # noqa: BLE001
            return False

    out = {}
    for path in sorted(paths):
        hits = [r for r in resources if match(r, path)]
        if not hits:
            out[path] = ("fallback", "")
            continue
        mods = {getattr(route.handler, "__module__", "") for r in hits for route in r}
        methods = sorted({route.method for r in hits for route in r})
        status = "stub" if mods and all(m.endswith("compat") for m in mods) else "real"
        out[path] = (status, f"{hits[0].canonical} [{','.join(methods)}]")
    return out


def core_rpcs():
    text = (ROOT / "core" / "neovarch" / "server.py").read_text(encoding="utf-8")
    names = set(re.findall(r'method == "([a-z_.]+)"', text))
    for group in re.findall(r"method in \(([^)]*)\)", text):
        names |= set(re.findall(r'"([a-z_.]+)"', group))
    prefixes = set(re.findall(r'method\.startswith\("([a-z_.]+)"\)', text))
    return names, prefixes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    ap.add_argument("--md")
    a = ap.parse_args()
    paths, rpcs = renderer_refs()
    cls = classify_paths(paths)
    names, prefixes = core_rpcs()
    rows = [{"route": p, "status": cls[p][0], "core_route": cls[p][1], "used_by": sorted(paths[p])} for p in sorted(paths)]
    rpc_rows = [{"rpc": r, "status": "handled" if (r in names or any(r.startswith(x) for x in prefixes)) else "missing",
                 "used_by": sorted(rpcs[r])} for r in sorted(rpcs)]
    summary = {k: sum(1 for r in rows if r["status"] == k) for k in ("real", "stub", "fallback", "error")}
    summary["rpc_handled"] = sum(1 for r in rpc_rows if r["status"] == "handled")
    summary["rpc_missing"] = sum(1 for r in rpc_rows if r["status"] == "missing")
    if a.json:
        Path(a.json).write_text(json.dumps({"summary": summary, "routes": rows, "rpcs": rpc_rows}, indent=1))
    if a.md:
        lines = ["| route | core | used by |", "|---|---|---|"]
        for r in rows:
            used = ", ".join(u.split("/")[-1] for u in r["used_by"][:3]) + (" …" if len(r["used_by"]) > 3 else "")
            lines.append(f"| `{r['route']}` | {r['status']} | {used} |")
        lines += ["", "| rpc | core | used by |", "|---|---|---|"]
        for r in rpc_rows:
            used = ", ".join(u.split("/")[-1] for u in r["used_by"][:3]) + (" …" if len(r["used_by"]) > 3 else "")
            lines.append(f"| `{r['rpc']}` | {r['status']} | {used} |")
        Path(a.md).write_text("\n".join(lines) + "\n")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
