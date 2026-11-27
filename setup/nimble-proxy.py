#!/usr/bin/env python3
"""Key-holding reverse proxy to Nimble's live API, with a unit budget and a call log.

    NIMBLE_PROXY_BUDGET=2500 python3 nimble-proxy.py --key-file /etc/nimble-gateway/nimble.env

Seats and the services they build point NIMBLE_BASE_URL at http://<host>:8797/nimble and use
any placeholder key. The proxy swaps in the real key, which it reads once from a file that only
its own system user can read, so no seat, room message or container environment ever holds it.

Every call is priced with the event's unit table (search lite/fast/deep 1/5/15, extract 1 per
URL or 3 rendered, research 25 per run; polls free) and charged before it is forwarded. When the
budget is spent the proxy answers 429 at no cost. Each call is appended to the JSONL log, which
holds no headers and no key, so it can be published with the entry.
"""
import argparse, asyncio, json, os, time
from aiohttp import ClientSession, ClientTimeout, web

UPSTREAM = "https://sdk.nimbleway.com"
DEPTH = {"lite": 1, "fast": 5, "standard": 5, "deep": 15}


def price(method: str, path: str, body: dict) -> tuple[str, int]:
    if method != "POST":
        return "poll", 0
    if path.endswith("/v2/search"):
        depth = str(body.get("search_depth") or body.get("depth") or "standard").lower()
        full = body.get("include_full_content") or body.get("full_content")
        return f"search:{depth}", 15 if full else DEPTH.get(depth, 5)
    if path.endswith("/v2/extract"):
        urls = body.get("urls") or [body.get("url")]
        n = len([u for u in urls if u]) or 1
        return "extract" + (":render" if body.get("render") else ""), n * (3 if body.get("render") else 1)
    if "/v2/agents" in path and path.rstrip("/").endswith("/runs"):
        return "research", 25
    return "other", 0


class Proxy:
    def __init__(self, key: str, budget: int, log_path: str):
        self.key, self.budget, self.log_path, self.spent, self.calls = key, budget, log_path, 0, 0
        self.lock = asyncio.Lock()
        self.session: ClientSession | None = None

    def log(self, **row):
        with open(self.log_path, "a") as f:
            f.write(json.dumps({"t": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **row}) + "\n")

    async def status(self, request):
        return web.json_response({"budget": self.budget, "spent": self.spent,
                                  "remaining": max(0, self.budget - self.spent), "calls": self.calls})

    async def forward(self, request: web.Request):
        path = "/" + request.match_info["tail"]
        raw = await request.read()
        try:
            body = json.loads(raw) if raw else {}
        except ValueError:
            body = {}
        kind, cost = price(request.method, path, body if isinstance(body, dict) else {})
        caller = request.headers.get("X-Caller", request.remote or "?")[:60]
        async with self.lock:
            if self.spent + cost > self.budget:
                self.log(caller=caller, kind=kind, path=path, cost=0, status=429, refused="budget")
                return web.json_response({"error": "live research budget exhausted",
                                          "spent": self.spent, "budget": self.budget}, status=429)
            self.spent += cost
            self.calls += 1
        headers = {"Authorization": f"Bearer {self.key}", "Content-Type": request.headers.get("Content-Type", "application/json")}
        t0 = time.time()
        try:
            async with self.session.request(request.method, UPSTREAM + path, params=request.query,
                                            data=raw or None, headers=headers) as r:
                data = await r.read()
                status = r.status
                ctype = r.headers.get("Content-Type", "application/json")
        except Exception as e:  # network failure: refund, answer like a provider fault
            async with self.lock:
                self.spent -= cost
            self.log(caller=caller, kind=kind, path=path, cost=0, status=502, error=type(e).__name__)
            return web.json_response({"error": f"upstream unreachable: {type(e).__name__}"}, status=502)
        if status >= 400:  # a refused or faulted call costs nothing, as in the event's rules
            async with self.lock:
                self.spent -= cost
            cost = 0
        self.log(caller=caller, kind=kind, path=path, cost=cost, status=status, ms=int((time.time() - t0) * 1000),
                 query=(body.get("query") or "")[:120] if isinstance(body, dict) else "",
                 url=(body.get("url") or "")[:200] if isinstance(body, dict) else "")
        return web.Response(body=data, status=status, content_type=ctype.split(";")[0])


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8797)
    ap.add_argument("--log", default="/var/log/nimble-gateway/calls.jsonl")
    a = ap.parse_args()
    key = ""
    for line in open(a.key_file):
        if line.strip().startswith("NIMBLE_API_KEY="):
            key = line.split("=", 1)[1].strip().strip("'\"")
    if not key:
        raise SystemExit("no NIMBLE_API_KEY in key file")
    p = Proxy(key, int(os.environ.get("NIMBLE_PROXY_BUDGET", "2500")), a.log)
    if os.path.exists(a.log):  # a restart keeps the run's spend: rebuild it from the call log
        for line in open(a.log):
            try:
                row = json.loads(line)
            except ValueError:
                continue
            p.spent += int(row.get("cost") or 0)
            p.calls += 1 if row.get("cost") is not None and not row.get("refused") else 0
    p.session = ClientSession(timeout=ClientTimeout(total=180))
    app = web.Application(client_max_size=8 * 1024 * 1024)
    app.router.add_get("/_budget", p.status)
    app.router.add_route("*", "/nimble/{tail:.*}", p.forward)
    runner = web.AppRunner(app, access_log=None)
    await runner.setup()
    await web.TCPSite(runner, a.host, a.port).start()
    print(f"nimble proxy on {a.host}:{a.port}, budget {p.budget} units, log {a.log}", flush=True)
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
