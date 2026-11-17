# Paal

**Stand up a team of coding agents in Band Desktop in minutes.**

Paal is an open-source skill pack and factory kit for [Band Desktop](https://docs.band.ai/band-desktop):
five agent seats that take a written specification, plan it, build it in parallel, prove it
with independent tests and merge only verified work, with no human in the loop after one
dispatch message.

```text
dispatch -> Lead writes a numbered requirements ledger from the spec
         -> Builder A + Builder B build disjoint packages, each in its own git worktree
         -> Prover writes black-box tests from the spec alone (never from the code)
         -> Gatekeeper rebuilds the exact commit, runs every check, plants bugs to test the
            tests, then ACCEPTs and merges, or REJECTs with evidence
```

Built for the BAND Dark Factory Buildathon (Nov 2026). Its review loop descends from
[Coord](https://github.com/N-45div/Coord), a four-seat factory that delivered all four
stages of an earlier Band track.

## Quick start

On Linux or WSL2 with Docker, Band Desktop, Claude Code and Codex installed and signed in:

```bash
git clone https://github.com/N-45div/Paal.git ~/buildathon/factory-kit
cd ~/buildathon
bash factory-kit/setup/create-seats.sh rehearsal            # 5 seats on cheap models
bash factory-kit/setup/prepare-result-repo.sh ~/buildathon/band-work/result
# create a room with the five seats, paste a dispatch from DISPATCH.md, and watch
```

Or install it as a Claude Code plugin and ask: *"set up a Band agent factory"*.

```text
/plugin marketplace add N-45div/Paal
/plugin install paal@paal
```

## What is in the box

| Path | What it is |
|---|---|
| [`mandates/`](mandates) | The five seats' standing instructions. Generic: they name no product, endpoint or field |
| [`setup/create-seats.sh`](setup/create-seats.sh) | Creates the seats with `band agent create` (rehearsal or production models) |
| [`setup/prepare-result-repo.sh`](setup/prepare-result-repo.sh) | Fresh result repository with one worktree, branch and git identity per seat |
| [`setup/bootstrap-user.sh`](setup/bootstrap-user.sh) | Installs Node, Codex, Claude Code and the event harness for one user |
| [`skills/band-factory/`](skills/band-factory) | The Claude Code skill that walks a machine from zero to a running factory |
| [`SETUP.md`](SETUP.md) | Full machine setup, including WSL2 on a second drive and Band Desktop settings |
| [`DISPATCH.md`](DISPATCH.md) | The single message that starts a run |
| [`FACTORY.md`](FACTORY.md) | Design, how it catches bad work, costs |
| [`SUBMIT.md`](SUBMIT.md) | Packaging a run for submission |

## Seats

| Seat | Runtime | Owns | Never |
|---|---|---|---|
| Lead | Claude Code | ledger, packages, rulings, stage freeze | writes product code |
| Builder A / B | Claude Code | implementation in its own worktree | accepts its own work |
| Prover | Codex | independent acceptance tests from the spec | reads code to decide expectations |
| Gatekeeper | Codex | clean-room review, checks, merges | fixes code |

Mixing two model families means the tests and the review are not written by the same model
that wrote the code.

## Safety defaults

- Keys live in `chmod 600` files outside every repository; mandates forbid printing
  environment variables, because Band room logs are often published.
- Band's *Human approval wait* is set to auto-deny, so an unattended run never stalls on a
  person.

## License

MIT
