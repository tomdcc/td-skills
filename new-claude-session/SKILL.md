---
name: new-claude-session
description: Start a new personal Claude session in tmux or cmux. Defaults to tmux+remote-control if the account supports it, cmux otherwise. Use when the user wants to open a new Claude session with a given name, optionally in a specified directory.
---

# New Claude Session

Start a new personal Claude session with remote control enabled. Args: a session name, an optional directory path, and an optional launcher flag (e.g. `/new-claude-session my-session`, `/new-claude-session my-session /path/to/dir`, `/new-claude-session my-session --cmux`).

## Steps

1. **Parse args**: the first word is the session name; if a path argument is present, it is the working directory; if no directory is given, use the current working directory. `--tmux` and `--cmux` are flags, not positional args.

2. **Determine the launcher**:
   - If `--tmux` was passed: use **tmux** (with remote control).
   - If `--cmux` was passed: use **cmux** (without remote control).
   - Otherwise: read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/policy-limits.json` and check `restrictions.allow_remote_control.allowed`. If `true`, use **tmux**; if `false` or the file is absent, use **cmux**.

3. **Launch the session**, passing the **warmup prompt** (below) as the final argument so the session's first action is to build the working directory's test prerequisites (if that repo provides a warmup hook).

   **tmux** (with remote control):
   ```
   tmux new-session -d -s "<name>" -c "<directory>" ${CLAUDE_CONFIG_DIR:+-e CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"} -e NODE_OPTIONS= 'command claude --remote-control <name> "<WARMUP-PROMPT>"'
   ```
   (`-e NODE_OPTIONS=` clears any `NODE_OPTIONS` inherited from the launching shell. cmux exports a `--require=…/restore-node-options.cjs` shim whose temp file gets garbage-collected, which then crashes every `node`/`npm`/`emcc` the spawned session runs — including the warmup. Starting the session with an empty `NODE_OPTIONS` avoids that.)

   **cmux** (without remote control):
   ```
   cmux new-workspace \
     --cwd "<directory>" \
     --command "${CLAUDE_CONFIG_DIR:+CLAUDE_CONFIG_DIR=\"$CLAUDE_CONFIG_DIR\" }command claude '<WARMUP-PROMPT>'"
   ```

   **`<WARMUP-PROMPT>`** (verbatim — generic; runs the repo-provided `.claude/session-warmup` hook if present, so directories without the hook are unaffected):

   > Session warmup: if a file .claude/session-warmup exists in the current directory, run it now in the foreground with a 10-minute (600000 ms) Bash timeout and show its output — it builds this repo test prerequisites so the test legs are not skipped. If the file does not exist, skip silently. Then stop and wait for my instructions; do not start any other work on your own.

4. **Report back** with:
   - The session name
   - tmux: how to attach: `tmux attach -t <name>`
   - cmux: the workspace name
