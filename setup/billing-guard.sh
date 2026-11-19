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
# ON_LIMIT=wait stays on the subscription instead: on a limit it sleeps until the reset time the
# message names, then restarts the seats so they pick their pending work back up. A reset more
# than MAX_WAIT_H hours away (default 6, e.g. a weekly limit) still falls back to the API key.
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
    hit=$(band room messages "$ROOM" --type error 2>/dev/null | awk -v t="$since2" '$1 > t' \
         | grep -viE 'gpt-|openai' | grep -iE "hit your .*limit|usage limit|out of extra usage" | head -1)
    if [ -n "$hit" ] && [ "${ON_LIMIT:-apikey}" = wait ]; then
      at=$(echo "$hit" | sed -nE 's/.*resets ([0-9:]+ ?[ap]m) \(UTC\).*/\1/p'); now=$(date +%s)
      if [ -n "$at" ]; then t=$(date -u -d "$at" +%s); [ "$t" -le "$now" ] && t=$((t + 86400))
      else t=$((now + 1800)); fi
      if [ $((t - now)) -le $(( ${MAX_WAIT_H:-6} * 3600 )) ]; then
        log "limit seen (resets ${at:-unknown} UTC) -> waiting until $(date -u -d @$t +%FT%TZ)"
        sleep $((t - now + 120)); restart_all; since2=$(date -u +%FT%TZ); continue
      fi
    fi
    if [ -n "$hit" ]; then
      log "phase 2: subscription limit seen -> restoring API key settings"
      cp "$HOME/.claude/settings.apikey.json" "$HOME/.claude/settings.json"
      restart_all; log "back on the API key; guard done"; exit 0
    fi
  fi
  sleep 120
done
