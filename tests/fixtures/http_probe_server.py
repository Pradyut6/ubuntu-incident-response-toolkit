#!/usr/bin/env python3
"""Disposable localhost HTTP fixture. Responds with status from a private file."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import time

port_file = Path(sys.argv[1])
status_file = Path(sys.argv[2])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            status = status_file.read_text(encoding="ascii").strip()
        except OSError:
            status = "500"
        if status == "slow":
            time.sleep(9)
            return
        code = int(status)
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        try:
            self.wfile.write(b"SECRET_RESPONSE_BODY_SHOULD_NEVER_BE_STORED\n")
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, fmt, *args):
        return


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(str(server.server_address[1]), encoding="ascii")
server.serve_forever(poll_interval=0.1)
