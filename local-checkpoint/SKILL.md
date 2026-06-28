---
name: local-checkpoint
description: Save a work-in-progress checkpoint — commit any uncommitted state locally, write a cold-session handover document, and hand back a ready-to-paste prompt to resume the work in a fresh session. Use when pausing work that should be resumable later (e.g. "checkpoint this", "save my progress", "create a handover before I stop").
argument-hint: "[optional extra note for the handover, and/or a commit-scope override like 'only staged changes']"
---

# Local Checkpoint

Capture the current state of work so a **cold session** — one with no memory of
this conversation — can pick it up cleanly. Produces three things:

1. a **local commit** of any uncommitted state,
2. a **handover document** with enough context to resume, and
3. a **pickup prompt** the user can paste into the new session.

This is a **local** checkpoint: never push, never open or update a PR. The goal
is to make the work safely resumable, not to ship it.

The optional argument is a free-text note to fold into the handover (e.g. "the
WASM leg is the risky part" or "don't trust the last test run").

## Steps

### 1. Commit any uncommitted state locally

1. Look at the working tree and branch:
   ```
   git status --short
   git branch --show-current
   ```
2. **Never checkpoint onto the default branch.** If the current branch is the
   repo's default (`main`/`master`/`trunk`), create a checkpoint branch first and
   tell the user:
   ```
   git switch -c checkpoint/<short-task-slug>
   ```
   Derive `<short-task-slug>` from the task or issue (e.g. `158-mem-budget`).
3. If there is nothing uncommitted, say so and continue to step 2 (you still
   write a handover, against the current `HEAD`).
4. Otherwise commit. **The default is to commit everything**:
   ```
   git add -A
   git commit -m "<message>"
   ```
   - **An explicit user instruction about *what* or *how* to commit overrides
     this default — honour it exactly.** For example:
     - *"commit only staged changes"* → skip `git add -A`; commit just the index
       (`git commit -m ...`). Leave unstaged/untracked changes in place and
       **note in the handover that they were intentionally left uncommitted**.
     - *"only commit `src/`"* / a named set → stage only those paths.
     - *"amend the last commit"* → `git commit --amend` (only if they ask;
       amending rewrites history, so never do it by default — see Guardrails).
     - *"don't commit, just write the handover"* → skip the commit entirely and
       checkpoint against the current `HEAD` + working tree, recording in the
       handover that the tree is dirty and uncommitted.
     When in doubt about an override's scope, ask rather than guess — the wrong
     commit scope is annoying to unpick.
   - Message: a clear WIP marker plus a one-line state, e.g.
     `wip: checkpoint — <what works / where you stopped>`.
   - Follow the repo's commit conventions if it has any — grep
     `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md` for a required message format
     or trailer, and honour any session/trailer line this environment mandates.
   - **Do not gate on green.** A checkpoint captures whatever exists, including
     half-finished or failing work. Don't run formatters or tests as a
     precondition — record their state in the handover instead.
5. Note the commit hash for the handover: `git rev-parse --short HEAD`.

### 2. Write the handover document

First decide **where** it goes, then write it. It must end up git-ignored or
unstaged — the handover is scaffolding, not part of the committed work, so it is
written *after* the step-1 commit and never included in it.

**Location — prefer a git-ignored top-level doc, fall back to `.claude/`:**

1. `git check-ignore` is the reliable test (it honours exact names, wildcards,
   the repo `.gitignore`, `.git/info/exclude`, and the global
   `core.excludesFile` all at once). Probe a candidate list, in order, and take
   the **first that is ignored**:
   ```
   for n in <slug>-plan.md <slug>Plan.md PLAN.md PLANNING.md TASKS.md \
            HANDOVER.md NOTES.md; do
     git check-ignore -q "$n" && echo "use: $n" && break
   done
   ```
   - Many setups globally ignore names like `PLAN.md` / `PLANNING.md` /
     `TASKS.md` (or a `*Plan.md`-style wildcard). If a **wildcard** pattern
     matches, you can mint a unique, descriptive name from it (substitute the
     `*` with the task slug). If only **exact** names are ignored, use the most
     handover-appropriate one that is **not already an unrelated existing file**
     (don't clobber someone else's `PLAN.md` — fall through to the next
     candidate or to `.claude/`).
   - This is what "use that format" means: match the repo/global ignore
     convention so the handover sits visibly at the repo root yet stays
     untracked.
2. **If no top-level candidate is ignored**, write it under `.claude/` (create
   the directory if needed) with a unique name:
   ```
   .claude/HANDOVER-<slug>.md
   ```
   Leave it **unstaged**. (`.claude/` is commonly git-ignored already, e.g. via
   a global `.claude/*` rule — that's fine; if it isn't, simply don't `git add`
   it.)
3. After writing, **verify it won't be committed**: it should show as ignored or
   as an untracked file in `git status`, never staged.

**Content — fill from THIS session's real state, no placeholders.** Write enough
that a cold session needs nothing else:

- **Task & goal** — what's being built and why; link the issue / PR / ADRs /
  design docs by number and URL.
- **Repo & location** — repo, branch, worktree path, and the checkpoint commit
  hash from step 1.
- **Status** — what is done and verified vs. in progress; the current
  build / test / lint state, stated honestly (note anything red or mid-edit).
- **Next steps** — a specific, ordered list of what to do next.
- **Key files** — the files touched or central to the work, each with a one-line
  note on its role.
- **How to build & validate** — the exact commands for this repo (from its
  conventions docs), so the cold session can re-verify before continuing.
- **Decisions & gotchas** — choices already settled (so they aren't relitigated),
  dead-ends to avoid, and anything non-obvious.
- The skill argument note, if one was given.

### 3. Give the user a pickup prompt

Output a ready-to-paste prompt for a fresh session, and state the handover path
and commit hash plainly. For example:

> Resume work in the worktree at `<worktree-path>` on branch `<branch>`
> (checkpoint commit `<hash>`). Read the handover at `<handover-path>` for full
> context, then continue with: `<one-line next step>`.

Keep the next-step line concrete so the cold session starts in the right place.

## Guardrails

- **Local only.** Never `git push`, and never open or update a PR. If the user
  wants to publish, that's a separate, explicit action.
- **Never commit onto the default branch** — branch first (step 1.2).
- **Don't gate on green.** The checkpoint must succeed even with failing tests or
  mid-edit code; capture the state and record its health, don't refuse.
- **Keep the handover out of the commit** — a git-ignored name, or unstaged under
  `.claude/`. Verify with `git status` before finishing.
- **Honour an explicit commit-scope override** (step 1.4) — e.g. "only staged
  changes", a named path set, or "don't commit". The full-tree `git add -A` is
  only the *default* for when the user hasn't said otherwise.
- **Add, don't rewrite — unless told to.** By default a checkpoint adds at most
  one commit (plus the optional new branch) and never amends, rebases, or
  discards existing history or work. Only rewrite (e.g. `--amend`) when the user
  explicitly asks for it.
- If the handover would overwrite an unrelated existing doc (e.g. a pre-existing
  `PLAN.md`), choose a different name rather than clobber it.
