#!/usr/bin/env python3
"""Byte-level snapshot of trees/files: type, mode, size, sha256, symlink target,
mtime and ctime of every entry (ctime changes on ANY write, chmod, rename or
create/delete inside a directory, so touched-and-restored files still show).

usage: snapshot.py <out.json> <path>...
"""
import hashlib
import json
import os
import sys


def entry(p):
    st = os.lstat(p)
    e = {"mode": oct(st.st_mode), "size": st.st_size, "mtime_ns": st.st_mtime_ns, "ctime_ns": st.st_ctime_ns}
    if os.path.islink(p):
        e["link"] = os.readlink(p)
    elif os.path.isfile(p):
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        e["sha256"] = h.hexdigest()
    return e


out, roots = sys.argv[1], sys.argv[2:]
snap = {}
for root in roots:
    if not os.path.lexists(root):
        snap[root] = None
        continue
    snap[root] = entry(root)
    if os.path.isdir(root) and not os.path.islink(root):
        for d, dirs, files in os.walk(root):
            for n in sorted(dirs + files):
                p = os.path.join(d, n)
                snap[p] = entry(p)
with open(out, "w") as f:
    json.dump(snap, f, indent=1, sort_keys=True)
files = sum(1 for v in snap.values() if v and "sha256" in v)
digest = hashlib.sha256(json.dumps(snap, sort_keys=True).encode()).hexdigest()
print(f"{len(snap)} entries ({files} files), tree digest sha256:{digest}")
