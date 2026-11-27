#!/usr/bin/env bash
# Start (or restart) the factory's live-web layer as the current user, without root:
#
#   bash web-layer.sh <result-repo> [budget-units]     e.g. bash web-layer.sh ~/factory7/band-work/result 2500
#
# - nimble-proxy.py on 0.0.0.0:8797 reads NIMBLE_API_KEY from ~/.nimble.env and is the only
#   process that holds it. Seats, tools and probe containers get a placeholder key and the
#   proxy's URL. It charges a unit budget and logs every call to <run>/live/calls.jsonl.
# - web-tools-mcp.py on 127.0.0.1:8798 gives seats web_search, web_extract, live_probe,
#   probe_result and live_budget. Register once:
#       claude mcp add -s user --transport http web http://localhost:8798/mcp
# For stronger isolation (the key readable only by a separate system user), run
# nimble-gateway.sh as root instead.
set -euo pipefail
REPO="$(cd "${1:?result repo}" && pwd)"; BUDGET="${2:-2500}"; KIT="$(cd "$(dirname "$0")" && pwd)"
RUN="$(dirname "$REPO")"; OUT="$RUN/live"; V="${PAAL_TOOLS_VENV:-$HOME/buildathon/factory-tools/.venv}"
mkdir -p "$OUT"
[ -f "$HOME/.nimble.env" ] || { echo "missing ~/.nimble.env" >&2; exit 1; }
[ -x "$V/bin/python" ] || { python3 -m venv "$V"; "$V/bin/pip" install -q aiohttp "mcp[cli]<2"; }
pkill -f "$KIT/nimble-proxy.py" 2>/dev/null || true
pkill -f "$KIT/web-tools-mcp.py" 2>/dev/null || true
sleep 1
NIMBLE_PROXY_BUDGET="$BUDGET" nohup "$V/bin/python" "$KIT/nimble-proxy.py" --key-file "$HOME/.nimble.env" \
  --log "$OUT/calls.jsonl" > "$OUT/proxy.out" 2>&1 &
WEB_TOOLS_REPO="$REPO" WEB_TOOLS_OUT="$OUT" nohup "$V/bin/python" "$KIT/web-tools-mcp.py" > "$OUT/web-tools.out" 2>&1 &
for _ in $(seq 1 20); do curl -sf http://127.0.0.1:8797/_budget >/dev/null && break; sleep 1; done
curl -s http://127.0.0.1:8797/_budget; echo
