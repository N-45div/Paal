#!/usr/bin/env python3
"""Move running Codex seats to another OpenAI model without recreating them.

    python3 model-proxy.py [port]        # default 8791, forwards to https://api.openai.com

Band fixes each seat's model when the seat is created and has no command to change it, and a
new seat would get a new room identity the other seats do not know. This proxy sits between
the seats and OpenAI: Codex reaches it through a model provider in ~/.codex/config.toml, and
the proxy rewrites the request's `model` to the id in the target file (default
~/.paal-model-target), re-read on every request. An empty or missing file passes requests
through unchanged, so the switch can be armed ahead of time and flipped at a stage boundary.
The seat's own Authorization header is forwarded as is; the proxy holds no key. Responses,
including streamed ones, pass through unchanged. Standard library only.
"""
import http.server
import json
import os
import sys
import urllib.error
import urllib.request

UPSTREAM = os.environ.get("MODEL_PROXY_UPSTREAM", "https://api.openai.com")
TARGET_FILE = os.path.expanduser(os.environ.get("MODEL_PROXY_TARGET", "~/.paal-model-target"))


def target():
    try:
        return open(TARGET_FILE, encoding="utf-8").read().strip()
    except OSError:
        return ""


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.log_date_time_string(), fmt % args))

    def _forward(self, body):
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() not in ("host", "content-length", "accept-encoding", "connection")}
        if body is not None:
            headers["content-length"] = str(len(body))
        req = urllib.request.Request(UPSTREAM + self.path, data=body, headers=headers,
                                     method=self.command)
        try:
            resp = urllib.request.urlopen(req, timeout=900)
        except urllib.error.HTTPError as err:
            resp = err
        self.send_response(resp.status)
        for k, v in resp.headers.items():
            if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                self.send_header(k, v)
        self.send_header("transfer-encoding", "chunked")
        self.end_headers()
        while True:
            chunk = resp.read1(65536) if hasattr(resp, "read1") else resp.read(65536)
            if not chunk:
                break
            self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.flush()
        self.wfile.write(b"0\r\n\r\n")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length") or 0))
        to = target()
        if to and not self.headers.get("content-encoding"):
            try:
                data = json.loads(body)
                if isinstance(data, dict) and "model" in data:
                    sys.stderr.write(f"{self.path} model {data['model']} -> {to}\n")
                    data["model"] = to
                    body = json.dumps(data).encode()
            except ValueError:
                pass
        elif self.headers.get("content-encoding"):
            sys.stderr.write(f"{self.path} compressed body ({self.headers['content-encoding']}), passed through\n")
        self._forward(body)

    def do_GET(self):
        self._forward(None)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8791
    print(f"model proxy on 127.0.0.1:{port} -> {UPSTREAM}, target from {TARGET_FILE}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Proxy).serve_forever()
