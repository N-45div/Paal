#!/usr/bin/env bash
# Keep an unattended run's Claude Code seats paid for, without touching the room.
#
#   bash billing-guard.sh <room-id> <dispatch-utc> <api-cap-usd> <seat>...
#
# Phase 1 (move to subscription): once the first stage report lands, or once API spend since
# the dispatch passes <api-cap-usd>, restart the listed Claude seats one at a time so they pick
# up the subscription login (settings without apiKeyHelper).
# Phase 2 (fall back): if the room then shows a Claude usage-limit error, restore the API key
# settings saved in ~/.claude/settings.apikey.json and restart the seats again. Only Claude Code's
# own limit messages count: a Codex seat's provider rate limit (a short retry) must not trigger it.
# START_PHASE=2 skips phase 1 when the seats already start on the subscription.
# It only restarts runtimes and swaps a settings file; it never posts in the room.
set -uo pipefail
ROOM="$1"; SINCE="$2"; CAP="$3"; shift 3; SEATS=("$@")
KIT="$(cd "$(dirname "$0")" && pwd)"
log() { echo "$(date -u +%FT%TZ) $*"; }
restart_all() { for s in "${SEATS[@]}"; do band restart --as "$s" >/dev/null 2>&1 && log "restarted $s"; sleep 90; done; }

phase=${START_PHASE:-1}; since2=$(date -u +%FT%TZ)
while :; do
  if [ $phase = 1 ]; then
    spent=$(python3 "$KIT/spend.py" --since "$SINCE" | awk '/^claude-/{s+=$NF} END{print s+0}')
    stage=$(band room messages "$ROOM" --type text 2>/dev/null | grep -c 'STAGE 1 REPORT')
    if [ "$stage" -gt 0 ] || awk -v s="$spent" -v c="$CAP" 'BEGIN{exit !(s>=c)}'; then
      log "phase 1: stage1_report=$stage api_spend=\$$spent -> moving seats to subscription"
      restart_all; phase=2; since2=$(date -u +%FT%TZ)
    fi
  else
    if band room messages "$ROOM" --type error 2>/dev/null | awk -v t="$since2" '$1 > t' \
         | grep -viE 'gpt-|openai' | grep -qiE "hit your .*limit|usage limit|out of extra usage"; then
      log "phase 2: subscription limit seen -> restoring API key settings"
      cp "$HOME/.claude/settings.apikey.json" "$HOME/.claude/settings.json"
      restart_all; log "back on the API key; guard done"; exit 0
    fi
  fi
  sleep 120
done
