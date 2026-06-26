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

3. **Derive a branch name**: pick 3–4 meaningful keywords from the title (skip common words like "switch", "from", "to", "the", "a", "and", file names like `cart_load.c`), join with hyphens, lowercase, then prefix with the issue number: `<number>-<keyword>-<keyword>...`. Aim for something a human would choose — short, readable, descriptive of the core change. Example: issue "cart_load.c: switch ELF section check from allowlist to denylist" → `71-elf-section-denylist`.

4. **Derive the repo name** from `git remote get-url origin` — extract just the repo name (the last path component, without `.git`).

5. **Create the worktree** from the current repo root:
   ```
   wtp add -b <branch-name> --quiet
   ```
   Capture the output — it is the worktree path.

6. **Determine the launcher**:
   - If `--tmux` was passed: use **tmux** (with remote control).
   - If `--cmux` was passed: use **cmux** (without remote control).
   - Otherwise: read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/policy-limits.json` and check `restrictions.allow_remote_control.allowed`. If `true`, use **tmux**; if `false`, use **cmux**. If the file is absent, use **tmux**.

7. **Derive the session name**: use `<repo>-<branch-name>` if the total length is ≤40 characters, otherwise fall back to `<repo>-<number>`.

8. **Launch a Claude session** according to the launcher. Pass the **initial prompt** (below) as the final argument. **Substitute the real issue number for `<number>`** in the prompt.

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

   **Eager suffix** (append when `--eager` was passed):
   > Once you have summarised your understanding: if there is a clear way forward, start implementing it (test-first, per the repo's conventions); if genuine ambiguity about scope or approach remains that the issue and its linked context do not resolve, do NOT guess — stop and ask me to start a grill-me session to settle it before you implement.

9. **Report back** with:
   - The issue title and number
   - The branch name
   - The worktree path
   - tmux: the session name and how to attach: `tmux attach -t <session-name>`
   - cmux: the session name
