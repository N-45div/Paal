#!/usr/bin/env bash
# Install and start the factory's live-web layer. Run as root inside WSL/Linux:
#
#   sudo bash nimble-gateway.sh <operator-user> [budget-units]        e.g. sudo bash nimble-gateway.sh ndivij 2500
#
# 1. Moves the operator's Nimble key (~/.nimble.env) into /etc/nimble-gateway/nimble.env, readable
#    only by a dedicated system user `nimblegw`. Seats run as the operator, so they cannot read the
#    key, the proxy's process environment or its memory. A root-only backup is kept.
# 2. Installs nimble-proxy.py, web-tools-mcp.py and live-probe.sh into /opt/paal-tools (root-owned,
#    so no seat can edit code that is running) with their own virtualenv.
# 3. Starts the proxy as `nimblegw` on 0.0.0.0:8797 (containers reach it via host-gateway) and the
#    MCP tools server as the operator on 127.0.0.1:8798. Call log: /var/log/nimble-gateway/calls.jsonl.
set -euo pipefail
OP="${1:?operator user}"; BUDGET="${2:-2500}"; KIT="$(cd "$(dirname "$0")" && pwd)"
OPHOME=$(getent passwd "$OP" | cut -d: -f6)
id nimblegw >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin nimblegw
install -d -m 750 -o root -g nimblegw /etc/nimble-gateway
if [ -f "$OPHOME/.nimble.env" ]; then
  install -m 640 -o root -g nimblegw "$OPHOME/.nimble.env" /etc/nimble-gateway/nimble.env
  install -m 600 -o root -g root "$OPHOME/.nimble.env" /root/nimble.env.bak
  shred -u "$OPHOME/.nimble.env" 2>/dev/null || rm -f "$OPHOME/.nimble.env"
fi
[ -f /etc/nimble-gateway/nimble.env ] || { echo "no key: put NIMBLE_API_KEY=... in $OPHOME/.nimble.env first" >&2; exit 1; }
install -d -m 755 /opt/paal-tools
install -m 644 "$KIT/nimble-proxy.py" "$KIT/web-tools-mcp.py" /opt/paal-tools/
install -m 755 "$KIT/live-probe.sh" /opt/paal-tools/
[ -x /opt/paal-tools/.venv/bin/python ] || python3 -m venv /opt/paal-tools/.venv
/opt/paal-tools/.venv/bin/pip install -q aiohttp "mcp[cli]<2"
install -d -m 755 -o nimblegw -g nimblegw /var/log/nimble-gateway
touch /var/log/nimble-gateway/calls.jsonl; chown nimblegw:nimblegw /var/log/nimble-gateway/calls.jsonl
chmod 644 /var/log/nimble-gateway/calls.jsonl
pkill -f /opt/paal-tools/nimble-proxy.py 2>/dev/null || true
pkill -f /opt/paal-tools/web-tools-mcp.py 2>/dev/null || true
sleep 1
runuser -u nimblegw -- env NIMBLE_PROXY_BUDGET="$BUDGET" nohup /opt/paal-tools/.venv/bin/python \
  /opt/paal-tools/nimble-proxy.py --key-file /etc/nimble-gateway/nimble.env \
  > /var/log/nimble-gateway/proxy.out 2>&1 &
runuser -u "$OP" -- env HOME="$OPHOME" WEB_TOOLS_REPO="${WEB_TOOLS_REPO:-$OPHOME/factory7/band-work/result}" \
  WEB_TOOLS_OUT="${WEB_TOOLS_OUT:-$OPHOME/factory7/band-work/live}" \
  nohup /opt/paal-tools/.venv/bin/python /opt/paal-tools/web-tools-mcp.py > "$OPHOME/web-tools-mcp.out" 2>&1 &
for _ in $(seq 1 20); do curl -sf http://127.0.0.1:8797/_budget >/dev/null && break; sleep 1; done
curl -s http://127.0.0.1:8797/_budget; echo
echo "register for seats: claude mcp add -s user --transport http web http://localhost:8798/mcp"
