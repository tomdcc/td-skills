---
name: merge-when-green
description: Monitor a pull request's CI and, once all checks pass, merge it using the project's preferred merge technique. Use when the user wants to watch a PR's CI and have it merged automatically as soon as it goes green (e.g. "merge this when CI passes", "watch CI and merge").
argument-hint: "[PR number or URL — defaults to the current branch's PR]"
---

# Merge When Green

Watch a PR's CI checks and, **only if every check passes**, merge it with the
project's preferred merge technique. If CI fails, stop and report — never merge a
red PR.

The arg is an optional PR number or URL. If omitted, resolve the PR for the
current branch.

## Steps

1. **Resolve the PR.** If an arg was given, use it. Otherwise find the PR for the
   current branch:
   ```
   gh pr view --json number,headRefName,baseRefName,state,url,isDraft,mergeable,mergeStateStatus
   ```
   - If there is no PR for the branch, stop and tell the user.
   - If the PR is already `MERGED` or `CLOSED`, report that and stop.
   - If it is a **draft**, stop and ask whether to mark it ready first — don't
     merge a draft.
   - Sanity-check the base branch is the repo's real integration branch (usually
     `main`/`master`), not something unexpected. If the head branch *is* the
     default branch, stop — there is nothing to merge.

2. **Confirm there is a determinate set of CI jobs to wait on.** Before
   watching, list what the PR reports:
   ```
   gh pr checks <pr>
   ```
   - If this reports a clear set of checks, note them and proceed.
   - **If you cannot determine the correct set of CI jobs — STOP and report to
     the user; do not guess.** This includes: no checks reported at all (CI may
     not have triggered yet, or none is configured); checks still in a
     `queued`/no-status limbo with none ever appearing after a reasonable wait;
     or genuine doubt about which checks are the *required* gate vs. optional/
     advisory ones (e.g. a mix where some are non-blocking and it's unclear
     whether the PR can merge without them). Show what you found and ask the
     user which jobs constitute "green" before going further. Merging without
     knowing the real gate is exactly the guess to avoid.

3. **Monitor CI until it completes.** Block on the checks rather than
   one-shot polling:
   ```
   gh pr checks <pr> --watch --interval 30
   ```
   - This exits non-zero if any required check fails and zero when all pass.
   - If CI is expected to run longer than the command timeout, instead poll
     `gh pr checks <pr>` every 30–60s until no check is `pending`/`in_progress`,
     re-running as needed. Don't give up early; CI can take several minutes.
   - Surface progress to the user (which checks are still running) rather than
     going silent.

4. **Evaluate the result.**
   - **Any check failed, errored, timed out, or was cancelled:** STOP. Do not
     merge. Report the failing check names and their URLs
     (`gh pr checks <pr>`), and let the user decide. Resist the urge to "retry"
     or push fixes unless the user asks.
   - **All checks passed:** continue.

5. **Re-confirm mergeability** (CI green ≠ mergeable — there may be conflicts or
   an out-of-date branch, or required reviews):
   ```
   gh pr view <pr> --json mergeable,mergeStateStatus,reviewDecision
   ```
   - `mergeable: CONFLICTING` → stop, report the conflict; the user must resolve.
   - `mergeStateStatus: BEHIND` → the branch needs updating; tell the user (offer
     to `gh pr update-branch <pr>`, then loop back to monitoring — the update
     re-triggers CI). Don't update silently.
   - `reviewDecision: REVIEW_REQUIRED` / `CHANGES_REQUESTED` → stop, report that
     a review gate is unmet; don't try to bypass it.
   - `BLOCKED` for any other reason → stop and report.

6. **Determine the project's preferred merge technique**, in this order:
   1. **Repo conventions doc.** Grep the repo's `CLAUDE.md` / `AGENTS.md` /
      `CONTRIBUTING.md` for merge guidance (e.g. "squash-and-merge",
      "fast-forward", "merge commit"). An explicit instruction there wins.
   2. **What the repo allows.**
      ```
      gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
      ```
      If exactly one method is enabled, use it.
   - **If you still cannot determine the preferred technique — STOP and report to
     the user; do not guess.** That is: the conventions docs say nothing about
     merge style *and* the repo allows more than one method (so there is no
     unambiguous choice). Show what the docs said (nothing) and which methods are
     allowed, and ask the user which to use. Do **not** silently default to
     squash or any other method — picking a merge style the project didn't ask
     for is a guess that's awkward to undo once history is written.
   - Map the chosen method to the `gh pr merge` flag: `--squash`, `--merge`, or
     `--rebase`.
   - **Note on local fast-forward:** some projects (check the conventions doc)
     want certain PRs landed as multiple long-lived commits via a local
     `git merge --ff-only` to `main` + push, rather than through `gh`. Only do
     that if the doc explicitly calls for it; it requires pushing the default
     branch, so confirm with the user first.

7. **Merge.**
   ```
   gh pr merge <pr> --<method>
   ```
   - Do **not** pass `--delete-branch` by default — branch/worktree cleanup is
     often project-specific (e.g. a worktree tool). Leave it to the user or a
     dedicated cleanup step unless the conventions doc says otherwise.
   - If the PR body has a closing keyword (`Closes #N`), the linked issue
     auto-closes on merge; if the link is only a bare `(#N)` or in the title,
     note that the issue may need closing manually.

8. **Report back**: the merge method used, the merged PR URL, whether any linked
   issue auto-closed, and a reminder of any leftover cleanup (worktree/branch
   removal) — but don't perform destructive cleanup unless asked.

## Guardrails

- **Never merge on red, and never force a merge past an unmet gate** (failing
  check, conflict, required review). The whole value of this skill is that it
  only merges a genuinely green, mergeable PR.
- **Never push directly to the default branch** as a substitute for the PR merge
  unless the conventions doc explicitly prescribes a local fast-forward flow and
  the user has approved it.
- If anything is ambiguous (which PR, an unexpected base branch), ask rather
  than guess — a merge is hard to unwind.
- **Two specific things must never be guessed — report to the user instead:**
  (1) the **set of CI jobs** that constitutes "green" (step 2), and (2) the
  **preferred merge technique** (step 6). If either can't be determined from the
  PR's checks, the repo's conventions docs, or its allowed-methods config, stop
  and ask. Guessing the gate could merge a PR whose real checks haven't run;
  guessing the technique writes the wrong history.
