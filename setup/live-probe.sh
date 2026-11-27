#!/usr/bin/env bash
# Build one stage folder of the result repository at a revision and research real companies on
# the live web through the key-holding Nimble proxy. Called by web-tools-mcp.py (live_probe).
#
#   bash live-probe.sh <result-repo> <revision> <stage-N> <domain> [domain ...]
#
# The container gets a placeholder key and NIMBLE_BASE_URL pointing at the proxy, so nothing
# secret is in its environment. Writes $LIVE_OUT/probe-<job>.json (summary) and one JSON file per
# domain; never writes into the result repository.
set -euo pipefail
REPO="${1:?repo}"; REV="${2:?revision}"; STAGE="${3:?stage-N}"; shift 3
JOB="${PROBE_JOB:-$(date +%s)}"; OUT="${LIVE_OUT:-$HOME/factory7/band-work/live}"
PROXY_PORT="${NIMBLE_PROXY_PORT:-8797}"
NAME="probe-$JOB"; W=$(mktemp -d); mkdir -p "$OUT"
case "$STAGE" in stage-[1-9]) ;; *) echo "stage must look like stage-N" >&2; exit 2 ;; esac
git -C "$REPO" archive "$REV" "$STAGE" | tar -x -C "$W"
cleanup() { docker logs "$NAME" > "$OUT/probe-$JOB.service.log" 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$W"; }
trap cleanup EXIT
exec 9>/tmp/factory-heavy.lock; flock 9
docker build -q -t "$NAME" "$W/$STAGE" >/dev/null
docker run -d --name "$NAME" -p 127.0.0.1::8000 --add-host host.docker.internal:host-gateway \
  -e PORT=8000 -e NIMBLE_API_KEY=via-proxy -e NIMBLE_BASE_URL="http://host.docker.internal:$PROXY_PORT/nimble" \
  -e TAVILY_API_KEY=unavailable -e TAVILY_BASE_URL=https://api.tavily.com \
  -e KERNEL_API_KEY=unavailable -e KERNEL_BASE_URL=https://api.onkernel.com \
  -e BROWSERBASE_API_KEY=unavailable -e BROWSERBASE_BASE_URL=https://api.browserbase.com \
  "$NAME" >/dev/null
flock -u 9
PORT=$(docker port "$NAME" 8000/tcp | head -1 | sed 's/.*://')
python3 - "$PORT" "$OUT" "$JOB" "$REV" "$STAGE" "$@" <<'P'
import json, sys, time, uuid, urllib.request, urllib.error
port, out, job, rev, stage, *domains = sys.argv[1:]
base = f"http://127.0.0.1:{port}"
def req(method, path, body=None, headers=None):
    r = urllib.request.Request(base + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                               headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(r, timeout=60) as f:
            return f.status, json.loads(f.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, None
for _ in range(120):
    try:
        if req("GET", "/health")[0] == 200: break
    except Exception: pass
    time.sleep(1)
_, s = req("POST", "/auth/signup", {"email": f"probe-{job}@example.com", "password": "probe-pass-1", "display_name": "Probe"})
auth = {"Authorization": "Bearer " + s["token"]}
summary = {"revision": rev, "stage": stage, "domains": {}}
for d in domains:
    t0 = time.time()
    req("POST", "/dossiers", {"domain": d}, {**auth, "Idempotency-Key": str(uuid.uuid4())})
    doc = None
    for _ in range(240):
        st, doc = req("GET", f"/dossiers/{d}", headers=auth)
        if doc and doc.get("state") != "building": break
        time.sleep(3)
    json.dump(doc, open(f"{out}/probe-{job}-{d}.json", "w"), indent=1)
    fields = {}
    for name, v in ((doc or {}).get("fields") or {}).items():
        c = (v.get("citations") or [{}])[0]
        fields[name] = {"value": v.get("value"), "status": v.get("status"),
                        "source": c.get("url"), "excerpt": (c.get("excerpt") or "")[:200]}
    summary["domains"][d] = {"state": (doc or {}).get("state"), "spent_units": (doc or {}).get("spent_units"),
                             "seconds": int(time.time() - t0), "fields": fields}
json.dump(summary, open(f"{out}/probe-{job}.json", "w"), indent=1)
print(json.dumps({d: {k: v["state"] for k, v in [(d, summary["domains"][d])]} for d in domains}))
P
