---
name: report-to-overseer
description: Report this session's status back to the overseer session that spawned it, delivered directly into that session via `aoe send` (Agent of Empires). Presents the drafted report and the resolved target session for the user to confirm before anything is sent — never auto-submits. Use when a child session needs to hand a status update, result, or completion report up to its overseer.
argument-hint: "[overseer session id/title override] [+ optional notes on what to emphasize]"
---

# Report to Overseer

Deliver a concise status report from *this* (child) session to the **overseer**
session that is coordinating it, injecting it directly into the overseer via
`aoe send` (Agent of Empires' session-to-session message primitive) instead of
handing the user a block to copy-paste.

**Two hard rules:**
- **Never auto-submit.** Draft the report, resolve the target session, then
  present *both* to the user and get explicit confirmation of *both* before
  calling `aoe send`. The user may edit either.
- **Never send to a guessed or ambiguous target.** If you cannot resolve exactly
  one overseer, stop and ask — do not pick one.

The optional argument is an **overseer identifier override** (an aoe session id
or title) and/or free-text notes on what the report should emphasize.

## Steps

1. **Preflight — is direct delivery even possible?** Check the environment:
   ```
   command -v aoe            # aoe installed?
   echo "$TMUX"              # in a tmux session?
   echo "$AOE_INSTANCE_ID"   # this session's own aoe id (exclude it from matches)
   echo "$AOE_PROFILE"       # profile to scope `aoe list` / `aoe send` to
   ```
   - If `aoe` is **not** installed, or there is no aoe/tmux context
     (`AOE_INSTANCE_ID` empty), **skip the send path entirely**: draft the report
     (step 3) and present it as a copy-paste block, telling the user direct
     delivery isn't available here. Do not fabricate a target.

2. **Resolve the overseer**, in this precedence — stop at the first that yields a
   single valid session, and **validate it exists** in `aoe list` (scope to
   `$AOE_PROFILE` via `-p` / `AGENT_OF_EMPIRES_PROFILE`):
   1. **Explicit override** — the skill argument, if it names a session id/title.
   2. **Env hand-off** — `$OVERSEER_AOE_ID` (set by the spawn flow, when present).
   3. **Title convention** — `aoe list`, take sessions whose title contains
      "overseer" (case-insensitive), **excluding this session's own
      `$AOE_INSTANCE_ID`**. Exactly one match → use it. More than one, or none →
      do **not** guess.
   4. **Ask** — if still unresolved (zero or multiple candidates), show the user
      the relevant `aoe list` rows and ask which session is the overseer (or to
      confirm there isn't one, in which case fall back to the copy-paste block).
   - Capture the target's **title, id, and path** for the confirmation step.

3. **Draft the report.** Write a concise, self-contained status update a cold
   overseer read can act on — not a transcript. Cover, as applicable:
   - What this session was tasked with and its current state (done / blocked /
     in-progress).
   - Concrete outcomes with links: PRs (number + merge state), issues
     filed/closed, commits, branches.
   - Validation status (tests/lint/CI — pass/fail with specifics).
   - Anything the overseer must decide or do next, and any blockers.
   Fold in the argument's emphasis notes if given. Keep it tight; prefer bullets.
   Write it to a scratch file so it can be passed verbatim (avoids shell-quoting
   pitfalls with multi-line text).

4. **Present both for confirmation — do not send yet.** Show the user:
   - **Target:** the resolved overseer — `title` · `id` · `path` — and, briefly,
     *how* it was resolved (override / env / title-match / user-picked).
   - **Report:** the full drafted text.
   Ask them to confirm **both** the target and the content, and invite edits to
   either. Treat anything short of an explicit go as "not yet" — revise and
   re-present rather than sending. (A cancelled/again-declined confirmation means
   stop, not send.)

5. **Send** — only after explicit confirmation of both:
   ```
   aoe send [-p "$AOE_PROFILE"] "<overseer-id-or-title>" "$(cat <report-file>)"
   ```
   - `aoe send` delivers the message as an incoming turn into the overseer
     session (auto-reviving it if it was stopped; pass `--no-revive` only if the
     user wants a hard fail on a dead session instead).
   - On success, confirm to the user what was sent and to which session.
   - On any failure (send errors, target vanished), **fall back**: print the
     report as a copy-paste block so the update isn't lost, and report the error.

## Guardrails

- The confirmation in step 4 is the whole point — it is the gate that makes this
  safe. Sending injects a turn into another live agent session; do it only with
  the user's explicit OK on both target and content.
- Resolve targets by identity (id/title from `aoe list`), never by raw tmux
  pane guessing. If identity is unclear, ask.
- Exclude this session (`$AOE_INSTANCE_ID`) from any automatic match so a report
  can't be sent to itself.
- If direct delivery isn't possible, the copy-paste block is always the fallback
  — the user should never be left with no way to relay the report.
