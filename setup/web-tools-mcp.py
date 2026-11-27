#!/usr/bin/env python3
"""MCP server that gives factory seats the live web through the key-holding Nimble proxy.

    WEB_TOOLS_REPO=~/factory7/band-work/result python3 web-tools-mcp.py      # http://localhost:8798/mcp

Register for every seat:  claude mcp add -s user --transport http web http://localhost:8798/mcp

Tools:
  web_search(query, depth, max_results)  live search; returns title, url and snippet
  web_extract(url, render, max_chars)    the text of one page, optionally as a browser shows it
  live_probe(revision, stage, domains)   builds a stage folder at a revision and runs it against
                                          the live web; returns a job id
  probe_result(job_id)                   the probe's summary once it has finished
  live_budget()                          live units spent and left for this run

This process holds no key. Every call goes through nimble-proxy.py, which adds the key, charges
the run's unit budget and logs the call. Probe containers get a placeholder key and the proxy's
URL, so `docker inspect` shows nothing secret either.
"""
import json, os, subprocess, time, uuid, urllib.request, urllib.error
from mcp.server.fastmcp import FastMCP

PROXY = os.environ.get("NIMBLE_PROXY", "http://127.0.0.1:8797")
REPO = os.path.expanduser(os.environ.get("WEB_TOOLS_REPO", "~/factory7/band-work/result"))
OUT = os.path.expanduser(os.environ.get("WEB_TOOLS_OUT", "~/factory7/band-work/live"))
PROBE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "live-probe.sh")
mcp = FastMCP("web", host="127.0.0.1", port=int(os.environ.get("WEB_TOOLS_PORT", "8798")))
JOBS: dict[str, dict] = {}


def _post(path: str, body: dict, caller: str) -> tuple[int, object]:
    req = urllib.request.Request(PROXY + "/nimble" + path, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "X-Caller": caller})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"null")
        except ValueError:
            return e.code, {"error": f"HTTP {e.code}"}


def _longest_text(obj, best=""):
    if isinstance(obj, str):
        return obj if len(obj) > len(best) else best
    if isinstance(obj, dict):
        for v in obj.values():
            best = _longest_text(v, best)
    if isinstance(obj, list):
        for v in obj:
            best = _longest_text(v, best)
    return best


@mcp.tool()
def web_search(query: str, depth: str = "lite", max_results: int = 5, caller: str = "seat") -> dict:
    """Search the live web. depth is lite (1 unit: title, url, snippet), fast (5) or deep (15).
    Use it to answer questions about external libraries, APIs and real-world facts, and cite the urls."""
    status, data = _post("/v2/search", {"query": query, "max_results": max(1, min(int(max_results), 10)),
                                        "search_depth": depth}, caller)
    if status != 200:
        return {"status": status, "error": data}
    rows = (data.get("results") or data.get("data") or []) if isinstance(data, dict) else data or []
    out = []
    for r in rows[:10] if isinstance(rows, list) else []:
        if isinstance(r, dict):
            out.append({"title": r.get("title"), "url": r.get("url") or r.get("link"),
                        "snippet": (r.get("snippet") or r.get("description") or r.get("content") or "")[:500]})
    return {"status": status, "results": out}


@mcp.tool()
def web_extract(url: str, render: bool = False, max_chars: int = 8000, caller: str = "seat") -> dict:
    """Fetch one live page's text (1 unit; 3 with render=True, which returns the text a browser
    shows once the page has loaded). Returns at most max_chars characters."""
    body = {"url": url, "formats": ["markdown"]}
    if render:
        body["render"] = True
    status, data = _post("/v2/extract", body, caller)
    if status != 200:
        return {"status": status, "error": data}
    text = ((data.get("data") or {}).get("markdown") if isinstance(data, dict) else None) or _longest_text(data)
    return {"status": status, "url": url, "chars": len(text), "text": text[: max(200, int(max_chars))]}


@mcp.tool()
def live_probe(revision: str, stage: str, domains: list[str], caller: str = "seat") -> dict:
    """Build `stage` (for example "stage-2") of the result repository at `revision` (a commit or
    branch) and research up to three real company domains against the live web. Costs roughly
    40-60 live units per domain. Returns a job id; call probe_result(job_id) for the outcome."""
    domains = [d.strip().lower() for d in domains if d.strip()][:3]
    if not domains:
        return {"error": "give one to three domains"}
    job = uuid.uuid4().hex[:8]
    log = os.path.join(OUT, f"probe-{job}.log")
    os.makedirs(OUT, exist_ok=True)
    env = {**os.environ, "PROBE_JOB": job, "PROBE_CALLER": caller, "NIMBLE_PROXY": PROXY, "LIVE_OUT": OUT}
    p = subprocess.Popen(["bash", PROBE, REPO, revision, stage, *domains], stdout=open(log, "w"),
                         stderr=subprocess.STDOUT, env=env)
    JOBS[job] = {"proc": p, "log": log, "started": time.time(), "revision": revision, "stage": stage,
                 "domains": domains}
    return {"job_id": job, "domains": domains, "note": "about 1-3 minutes per domain; poll probe_result"}


@mcp.tool()
def probe_result(job_id: str) -> dict:
    """The outcome of a live probe: per domain, each field's value, status and first source url."""
    j = JOBS.get(job_id)
    if not j:
        return {"error": "unknown job"}
    if j["proc"].poll() is None:
        return {"state": "running", "elapsed_s": int(time.time() - j["started"])}
    summary = os.path.join(OUT, f"probe-{job_id}.json")
    if os.path.exists(summary):
        return {"state": "done", **json.load(open(summary))}
    return {"state": "failed", "log_tail": open(j["log"]).read()[-1500:]}


@mcp.tool()
def live_budget() -> dict:
    """Live research units spent and left for this run."""
    with urllib.request.urlopen(PROXY + "/_budget", timeout=10) as r:
        return json.loads(r.read())


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
