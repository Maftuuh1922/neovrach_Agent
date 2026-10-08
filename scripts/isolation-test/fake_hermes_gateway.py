#!/usr/bin/env python3
"""Stand-in for a running Hermes Agent gateway/dashboard on its default port.

Started from the fake ~/.hermes before Neovarch is installed. It answers HTTP on
127.0.0.1:<port>; it never writes to disk, so ~/.hermes stays byte-identical
unless something else touches it.
"""
import http.server
import json
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9119


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        body = json.dumps({"product": "hermes-agent (fake)", "pid": os.getpid(),
                           "hermes_home": os.environ.get("HERMES_HOME")}).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
