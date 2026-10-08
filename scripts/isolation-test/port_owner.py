#!/usr/bin/env python3
"""Print the pid(s) listening on a TCP port (Linux /proc, no ss/lsof needed)."""
import os
import sys

port = int(sys.argv[1])
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                parts = line.split()
                if parts[3] == "0A" and int(parts[1].rsplit(":", 1)[1], 16) == port:
                    inodes.add(parts[9])
    except OSError:
        pass
pids = set()
for pid in filter(str.isdigit, os.listdir("/proc")):
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            link = os.readlink(f"/proc/{pid}/fd/{fd}")
            if link.startswith("socket:[") and link[8:-1] in inodes:
                pids.add(int(pid))
    except OSError:
        continue
print(" ".join(str(p) for p in sorted(pids)))
