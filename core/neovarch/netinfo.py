"""Addresses a phone can reach this PC on: LAN first, then Tailscale.

``GET /api/network/addresses`` returns them so a paired phone can learn (and
keep fresh) its fallback routes:

* ``lan``: private IPv4 addresses (192.168/16, 10/8, 172.16/12);
* ``tailscale``: the PC's tailnet IPv4 (100.64.0.0/10, CGNAT range) and its
  MagicDNS name (``pc.tailnet-xyz.ts.net``), read from ``tailscale status --json``
  when the Tailscale CLI is installed, otherwise from interface addresses in
  100.64/10.

The phone tries ``lan`` addresses first (fastest), then the MagicDNS name, then
the tailnet IP.
"""

from __future__ import annotations

import ipaddress
import json
import re
import shutil
import socket
import subprocess
from typing import Any

TAILNET = ipaddress.ip_network("100.64.0.0/10")


def classify(addr: str) -> str | None:
    try:
        ip = ipaddress.ip_address(addr)
    except ValueError:
        return None
    if ip.version != 4 or ip.is_loopback or ip.is_link_local:
        return None
    if ip in TAILNET:
        return "tailscale"
    if ip.is_private:
        return "lan"
    return None


def _interface_ipv4() -> list[str]:
    out: list[str] = []
    try:
        import psutil  # type: ignore

        for addrs in psutil.net_if_addrs().values():
            out += [a.address for a in addrs if a.family == socket.AF_INET]
        return out
    except Exception:
        pass
    for cmd in (["ip", "-4", "-o", "addr", "show"], ["ifconfig"], ["ipconfig"]):
        if not shutil.which(cmd[0]):
            continue
        try:
            text = subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        out += re.findall(r"(?:inet |IPv4[^:]*:\s*)(?:addr:)?(\d+\.\d+\.\d+\.\d+)", text)
        if out:
            break
    # Primary outbound address (no packet is sent for a UDP connect).
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            out.append(s.getsockname()[0])
    except OSError:
        pass
    return out


def tailscale_status(run=subprocess.run) -> dict[str, Any] | None:
    exe = shutil.which("tailscale")
    if not exe:
        return None
    try:
        proc = run([exe, "status", "--json"], capture_output=True, text=True, timeout=4)
        data = json.loads(proc.stdout or "{}")
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return None
    me = data.get("Self") or {}
    return {"dns_name": str(me.get("DNSName") or "").rstrip(".") or None,
            "ips": [ip for ip in me.get("TailscaleIPs") or [] if classify(ip) == "tailscale"],
            "online": bool(me.get("Online", True)),
            "backend_state": data.get("BackendState")}


def _rank(addr: str) -> int:
    return 0 if addr.startswith("192.168.") else 1 if addr.startswith("10.") else 2


def addresses(port: int, scheme: str = "http", ts: dict | None | bool = False,
              iface: list[str] | None = None) -> dict[str, Any]:
    if ts is False:
        ts = tailscale_status()
    ips = iface if iface is not None else _interface_ipv4()
    lan = sorted({a for a in ips if classify(a) == "lan"}, key=lambda a: (_rank(a), a))
    tnet = sorted({a for a in ips if classify(a) == "tailscale"} | set((ts or {}).get("ips") or []))
    magic = (ts or {}).get("dns_name")
    urls = [f"{scheme}://{a}:{port}" for a in lan]
    if magic:
        urls.append(f"{scheme}://{magic}:{port}")
    urls += [f"{scheme}://{a}:{port}" for a in tnet]
    return {"port": port, "lan": lan,
            "tailscale": {"ips": tnet, "magic_dns": magic, "installed": ts is not None,
                          "backend_state": (ts or {}).get("backend_state")},
            "urls": urls}
