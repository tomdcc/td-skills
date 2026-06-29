---
name: start-issue
description: Start a new worktree and Claude session for a GitHub issue. Defaults to tmux+remote-control if the account supports it, cmux otherwise. Use when the user specifies an issue number to work on and wants a Claude session spun up in a new worktree.
---

# Start Issue

Set up a worktree and Claude session for a GitHub issue. The args are the issue number, an optional launcher flag, and an optional `--eager` flag (e.g. `/start-issue 42`, `/start-issue 42 --tmux --eager`, `/start-issue 42 --cmux`).

## Steps

1. **Update the base branch** — from the main checkout, pull the latest:
   ```
   git pull --ff-only
   ```
   If the pull fails (e.g. diverged), stop and report the problem rather than proceeding.

2. **Fetch issue details** using `gh issue view <number> --json number,title` to get the title.

3. **Check the current session for context the new session needs — BEFORE creating anything.** This step runs *before* worktree creation (step 6), on **every** start — regardless of whether `--eager` was passed. The launching ("overseer") session often holds information, from other work done in this conversation, that could change how the new session approaches issue #<number> and which the new session would otherwise discover only much later (or never). Actively consider whether any such context exists, for example:
   - a design refinement or decision settled in this session that the issue text does not yet reflect;
   - a dependency that just merged, did **not** merge, or changed shape (so the issue's stated approach is now stale);
   - a related issue/PR, ADR amendment, or gotcha surfaced while working a sibling issue;
   - a correction to the issue's "fix sketch" / proposed approach.

   If you identify no such context, continue silently to the next step.

   If you **do** identify relevant context, **stop here — before any worktree creation — and ask the user** (via the AskUserQuestion tool) how to handle it. State the specific context concisely in the question, and offer exactly these four choices:
   - **Update the issue** — edit the issue body or add a comment capturing the context, so the new session (which reads the issue in full at startup) picks it up from the durable source. Prefer this when the context is durable and should outlive this session.
   - **Include it in the initial instructions** — carry the context into the new session's `<INITIAL-PROMPT>` (see step 9) as an extra paragraph. Use for session-specific steering that does not belong in the issue itself.
   - **Proceed without the additional context** — the context is not worth acting on; start the session unchanged.
   - **Cancel the operation** — do not start the session at all.

   Apply the chosen action before proceeding: for *Update the issue*, make the edit/comment with `gh` now; for *Include it in the initial instructions*, hold the context text to append in step 9; for *Cancel*, stop entirely and report that nothing was created. Only continue past this step once the choice is applied.

4. **Derive a branch name**: pick 3–4 meaningful keywords from the title (skip common words like "switch", "from", "to", "the", "a", "and", file names like `cart_load.c`), join with hyphens, lowercase, then prefix with the issue number: `<number>-<keyword>-<keyword>...`. Aim for something a human would choose — short, readable, descriptive of the core change. Example: issue "cart_load.c: switch ELF section check from allowlist to denylist" → `71-elf-section-denylist`.

5. **Derive the repo name** from `git remote get-url origin` — extract just the repo name (the last path component, without `.git`).

6. **Create the worktree** from the current repo root:
   ```
   wtp add -b <branch-name> --quiet
   ```
   Capture the output — it is the worktree path.

7. **Determine the launcher**:
   - If `--tmux` was passed: use **tmux** (with remote control).
   - If `--cmux` was passed: use **cmux** (without remote control).
   - Otherwise: read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/policy-limits.json` and check `restrictions.allow_remote_control.allowed`. If `true`, use **tmux**; if `false`, use **cmux**. If the file is absent, use **tmux**.

8. **Derive the session name**: use `<repo>-<branch-name>` if the total length is ≤40 characters, otherwise fall back to `<repo>-<number>`.

9. **Launch a Claude session** according to the launcher. Pass the **initial prompt** (below) as the final argument. **Substitute the real issue number for `<number>`** in the prompt.

   **tmux** (with remote control):
   ```
   tmux new-session -d -s "<session-name>" -c "<worktree-path>" ${CLAUDE_CONFIG_DIR:+-e CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"} -e NODE_OPTIONS= 'command claude --remote-control <session-name> "<INITIAL-PROMPT>"'
   ```
   (`-e NODE_OPTIONS=` clears any `NODE_OPTIONS` inherited from the launching shell. cmux exports a `--require=…/restore-node-options.cjs` shim whose temp file gets garbage-collected, which then crashes every `node`/`npm`/`emcc` the spawned session runs — including the warmup. Starting the session with an empty `NODE_OPTIONS` avoids that.)

   **cmux** (without remote control):
   ```
   cmux new-workspace \
     --cwd "<worktree-path>" \
     --command "${CLAUDE_CONFIG_DIR:+CLAUDE_CONFIG_DIR=\"$CLAUDE_CONFIG_DIR\" }command claude '<INITIAL-PROMPT>'"
   ```

   **`<INITIAL-PROMPT>`** (keep it generic — do not hardcode a repo's build command. It runs the repo-provided `.claude/session-warmup` hook if present, so repos without the hook are unaffected):

   **Base prompt** (always used):
   > Starting work on GitHub issue #<number>. Do these together: (1) Session warmup — if a file .claude/session-warmup exists in the current directory, start it in the background with a 10-minute (600000 ms) Bash timeout and surface its output; it builds this repo's test prerequisites so the test legs are not skipped. If the file does not exist, skip it silently. (2) While the warmup builds, read issue #<number> in full — run gh issue view <number> --comments for its body and discussion — and work to understand it, following any GitHub issues, PRs, ADRs, or design docs it references until you have a clear picture of the goal and the acceptance criteria. Once the warmup has finished and you understand the issue, summarise your understanding and the proposed approach, then stop and wait for instructions.

   **Session-context paragraph** (append ONLY if the user chose "Include it in the initial instructions" in step 3): add a clearly-labelled paragraph carrying that context, e.g.:
   > Context from the session that launched you (factor this into your understanding and approach before implementing): <the held context text>.

   **Eager suffix** (append when `--eager` was passed):
   > Once you have summarised your understanding: if there is a clear way forward, start implementing it (test-first, per the repo's conventions); if genuine ambiguity about scope or approach remains that the issue and its linked context do not resolve, do NOT guess — stop and ask me to start a grill-me session to settle it before you implement.

10. **Report back** with:
    - The issue title and number
    - The branch name
    - The worktree path
    - How the step-3 context was handled (issue updated / folded into the initial prompt / proceeded without / — if nothing relevant was found, omit)
    - tmux: the session name and how to attach: `tmux attach -t <session-name>`
    - cmux: the session name
