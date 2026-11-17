# Submission checklist

Deadline: **Nov 21, 2026, 6:30 AM IST** (Nov 20, 5:00 PM PST). Channel: the HackerSquad
project form, unless the event lead announces another. A saved draft is not a submission.

## After the judged run

1. **Room log.** Band Desktop room -> `⋮` -> **Open in Band** -> console room `⋮` ->
   **Download -> Download full session** (never the filtered one). Save it unchanged as
   `room.json` at the result repository root. Search it for keys before committing; if one
   appears, rotate it and replace only that value with `[REDACTED]`.
2. **Mandates.** Copy `mandates/*.md` into the result repository with the `Harness:`,
   `Model:` and `Effort:` lines exactly as the seats ran.
3. **Docs.** Add `README.md` (team, track, how to read the repository), `FACTORY.md` with the
   measured numbers (Band Desktop **Analytics -> Usage & Cost**; delivery time = first to
   last seat message), `SETUP.md`, `DISPATCH.md` and `setup/`.
4. **Live artifact.** Pick the highest `stage-N/` where `harness run --all` shows every folder
   up to it claiming its stage. Run the participant guide's live commands with your Nimble
   key, research exactly `runway.com`, confirm `state` is `ready`, save the response
   verbatim as `dossier-runway.com.json`, commit it.
5. **Offline check.** `python -m harness check <result-repo> --track dossier` must be clean.
6. **Push** to a public GitHub repository without amending, rebasing or squashing the seats'
   commits.

## Validate a fresh clone

```bash
git clone <public-repo-url> /tmp/fresh-clone
cd ~/buildathon/sf-buildathon-2026 && . .venv/bin/activate
python -m harness check /tmp/fresh-clone --track dossier
python -m harness run --track dossier --repo /tmp/fresh-clone --all --mode isolated
```

Then follow each stage's `RUN.md` by hand in a clean environment and use the UI from stage 2;
confirm the reciprocal `@handle` exchange is in `room.json`; confirm no stage folder is its own
repository; search the repository and its history for keys, emails and personal paths.

## Presentation and video

Cover the factory design, what it cost, a bad result it caught (a real rejection from the
room, never staged), and the stage reached. The video must show the factory working: the
room, a handoff between seats, and the result. A slideshow alone does not count.

## HackerSquad form

Project name, description, repository link, technologies, team roster, the
judging-partner consent (review it yourself), a demo recorded in the form, then **Submit for
judging** and keep the receipt.
