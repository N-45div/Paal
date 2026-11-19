# The Ledger Factory

> DRAFT. Sections marked TBD are filled from rehearsal and judged-run measurements.

A five-seat software factory for Band Desktop. It turns a written specification into a
numbered **requirements ledger**, builds against it in parallel, proves each requirement
with tests written independently of the code, and lets only verified work reach the
integration branch. Nothing in the mandates names a problem domain: point the factory at a
different specification and it runs the same way.

## Seats

| Seat | Harness | Model | Owns |
|---|---|---|---|
| Lead | Claude Code | claude-sonnet-5-5 (high) | Ledger, work packages, rulings, stage freeze, reports |
| Builder A | Claude Code | claude-haiku-5-5 (medium) | Implements assigned packages |
| Builder B | Claude Code | claude-haiku-5-5 (medium) | Implements assigned packages |
| Prover | Codex | gpt-6.1-terra (medium) | Black-box acceptance tests derived from the specification |
| Gatekeeper | Codex | gpt-6.1-terra (medium) | Clean-room review, all check runs, merges, final checks |

Mandates: [`mandates/`](mandates/). Each one says how a seat works, never what it builds.

## One stage, end to end

```text
dispatch -> @lead reads the stage spec, writes the ledger (every "must" = one id, quoted verbatim)
         -> @builder-a + @builder-b build disjoint packages      } in parallel
         -> @prover writes tests per ledger id from the spec only }
         -> builder hands off commit -> @gatekeeper: clean clone, build, run, test, read diff
              REJECT (failing ids + evidence) -> builder fixes -> hands off again
              ACCEPT -> merge into main
         -> all packages in -> @gatekeeper final check (isolated) -> @lead freezes the folder,
            copies it forward, and only then opens the next specification
```

## How it catches bad work

1. **The ledger.** Every normative sentence, table row and appendix rule becomes an id with
   the specification quoted. A stage is accepted only when every id has code, a test and a
   pass. This is aimed at requirements a happy-path check never exercises.
2. **Independent tests.** The Prover derives expected behaviour from the specification,
   never from the implementation, and never copies the event's shipped checks. Tests and code
   are written by different seats on different model families.
3. **Clean-room review.** The Gatekeeper builds every handed-off commit from a fresh
   checkout, following the run instructions literally, so uncommitted files, broken run
   instructions and nested repositories fail before they reach main.
4. **Diff review.** The Gatekeeper rejects logic that branches on a check's inputs, weakened
   tests, changes to frozen folders, and credentials.
5. **Isolated final check.** Each stage ends with the event check in isolated mode, which
   catches dependencies on outbound network access.
6. **Loop guard.** An id rejected three times is re-planned by the Lead (split, reassigned or
   re-derived) instead of retried.

## Design choices and what they cost

| Choice | Why | Cost |
|---|---|---|
| Five seats, two builders | Parallel packages and clearly distributed work | More tokens; merge coordination |
| Separate worktree and git identity per seat | Builders never trample each other's working tree; history shows who wrote what | One-time setup script |
| Only the Gatekeeper merges and runs the harness | One gate, no parallel heavy checks overloading the machine | Gatekeeper can become a queue |
| Prover on a different model family than the builders | Reduces shared blind spots between code and tests | A second provider account |
| Full specification pasted into each seat's first handoff | Seats see only messages that mention them; pointers lose context | Large first messages per stage |
| Cumulative ledger copied forward | Later stages re-verify earlier requirements | Ledger grows each stage |
| Shared memory (Cognee) for rulings and rejection lessons | Context survives compaction and stage boundaries | Optional dependency; seats continue without it |
| Claude seats fall back to Meta's Muse models (muse-spark-1.3) during a subscription limit, through `setup/muse-proxy.py` | Builders keep building through a limit window instead of idling until the reset | A third provider; Muse is untried on long agentic work, so seats return to Claude at the reset, each restarted only when quiet |

## Failure handling

- Missing seat: the Lead adds that exact seat and retries the handoff; unresponsive work is
  reassigned and recorded.
- Harness or infrastructure failure: retried once, then reported as a blocker with the log.
- Unresolvable ambiguity: the Lead rules from the specification text and records the ruling.
- Hard blocker: recorded as the stage outcome with evidence; the band never asks the human.

## Standing it up

See [`SETUP.md`](SETUP.md) (machine, Band Desktop settings, seats, shared memory) and
[`DISPATCH.md`](DISPATCH.md) (the single message that starts a run).
`setup/prepare-result-repo.sh` creates the result repository with one worktree per seat.

## Measured cost and time

TBD per stage: wall-clock from dispatch to freeze, model spend per seat (Band Desktop
Analytics -> Usage & Cost), number of handoffs, rejections and what each changed.

## What we tried that failed

- **Claude Code seats could not start on Band Desktop 0.4.18 for Linux.** Every turn ended
  with "could not load Band's disposition MCP relay". Band passes the relay as
  `~/.local/share/jam/daemon/jam`, but the Linux package installs only `jamd` there; Claude
  Code reported the missing program as `posix_spawn 'stdio'`, which pointed at the wrong
  cause. Found by capturing the `--settings` file Band hands Claude Code. Fix: link
  `/usr/bin/jam` to that path; `setup/create-seats.sh` now does it automatically.
- Band refuses `--claude-disallowed-tool AskUserQuestion`: it is one of Band's own control
  tools. A short *Question timeout* in Settings -> Runtime covers the same risk.
- **A stage report stalled the whole band (practice run, stage 1).** The Lead sent its stage
  report to the person, wrote "continuing with stage 2 now" and ended its turn. Seats only see
  messages that mention them, and the person never answers, so no seat ever took another
  turn. Fix: the Lead mandate now says a report is never the last message of a turn; the same
  turn opens the next specification and sends every seat its first handoff.
- **Review deadlocked on interpretation (same run).** The Gatekeeper rejected a research
  engine that passed every shipped check, on a literal reading of one requirement the Lead had
  already ruled on. Neither seat moved, and the Lead froze the stage with passing work unmerged
  (110/122 instead of 122/122). Fix: rulings now bind every seat. The Gatekeeper states its
  dissent once with evidence, then reviews against the ruling, and the Lead must settle a
  reading dispute in its next turn.
- **Opus Lead + Sonnet builders were too expensive for a four-stage run.** Stage 1 alone
  cost about $73 (list price, Claude seats) in four hours, and a Claude Pro window ran out
  within about 15 minutes of the dispatch. The submitted factory runs a Sonnet Lead and Haiku
  builders, keeping the review seats on a different model family.
- **A billing guard misread a Codex rate limit as a Claude usage limit** and moved the Claude
  seats from the subscription to the API key needlessly. `setup/billing-guard.sh` now matches
  only Claude Code's own limit messages.
