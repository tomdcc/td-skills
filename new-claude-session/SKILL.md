---
name: new-claude-session
description: Start a new personal Claude session. Defaults to Agent of Empires (aoe) when installed, else falls back to tmux+remote-control / cmux by account policy. Native --remote-control is passed only for accounts that allow it. Use when the user wants to open a new Claude session with a given name, optionally in a specified directory.
---

# New Claude Session

Start a new personal Claude session. Args: a session name, an optional directory path, and an optional launcher flag (e.g. `/new-claude-session my-session`, `/new-claude-session my-session /path/to/dir`, `/new-claude-session my-session --cmux`).

## Steps

1. **Parse args**: the first word is the session name; if a path argument is present, it is the working directory; if no directory is given, use the current working directory. `--aoe`, `--no-aoe`, `--tmux`, and `--cmux` are flags, not positional args.

2. **Determine the launcher** (precedence: explicit flag → AoE default → tmux/cmux fallback):
   - First compute `allow_remote` = `restrictions.allow_remote_control.allowed` from `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/policy-limits.json` (**true when the file is absent**). This gates Claude's native `--remote-control` in every branch below.
   - Explicit override wins: `--aoe` forces AoE; `--tmux` forces tmux; `--cmux` forces cmux; `--no-aoe` skips AoE and applies the fallback rule.
   - **Default = AoE** when the `aoe` binary is installed (`command -v aoe`). Under AoE, pass `--remote-control` **only if `allow_remote`** — omit it for the remote-control-disabled account.
   - **Fallback** (no `aoe`, or `--no-aoe`): the original behaviour — `allow_remote` true → **tmux** (with `--remote-control`); false → **cmux** (no `--remote-control`).

3. **Launch the session**, delivering the **warmup prompt** (below) so the session's first action is to build the working directory's test prerequisites (if that repo provides a warmup hook).

   **AoE** (default when installed — see the `aoe-session` skill for full detail and one-time profile setup): resolve the profile for the current account (match `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` to a profile's `CLAUDE_CONFIG_DIR`, or `$AGENT_OF_EMPIRES_PROFILE`, or `--profile`), ensure the single daemon is up, then:
   ```
   if aoe url >/dev/null 2>&1; then :; else aoe serve --daemon; fi
   aoe add "<directory>" -t "<name>" -p "<profile>" -g "<group>" --cmd claude ${allow_remote:+--extra-args "--remote-control <name>"}
   aoe session start "<name>" -p "<profile>"
   # if a first-run trust prompt is showing (aoe session capture "<name>"), dismiss it before sending:
   aoe send "<name>" "<WARMUP-PROMPT>" -p "<profile>"
   ```
   Include `--extra-args "--remote-control <name>"` **only when `allow_remote`**. `-g "<group>"` files the session under its **base repo** (a `<base>-worktrees/…` path → `<base>`, else the directory basename — see the `aoe-session` skill). Deliver the prompt via `aoe send` (not `--extra-args`, which is whitespace-split). Report the dashboard URL from `aoe url`.

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
   - The session name (and, for AoE, the profile/account used and whether `--remote-control` was passed)
   - AoE: the dashboard URL (`aoe url`) and how to attach: `tmux attach -t aoe_<name>_<idprefix>` or `aoe`
   - tmux: how to attach: `tmux attach -t <name>`
   - cmux: the workspace name
