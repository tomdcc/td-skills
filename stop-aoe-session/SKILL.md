---
name: stop-aoe-session
description: Stop a running aoe + tmux + Claude Code session — terminate the Claude process and its attached (stdio) MCP servers — while LEAVING the session in the aoe list so it can be restarted later. Use when the user wants to shut down / halt / free up a session's processes without deleting or trashing it (e.g. "stop the 68432 session", "kill claude for that session but keep it").
---

# Stop AoE Session

Halt a running session's compute — the Claude Code process and the stdio MCP servers it spawned — **without** removing the session from AoE. The session stays in `aoe list` with `Status: Stopped` and can be brought back with `aoe session start`.

## What `aoe session stop` does (verified on this machine, aoe 1.12.x)

`aoe session stop <id-or-title>` **destroys the session's tmux session**, which kills the pane's process group:

- The **Claude Code process** is terminated (verified: the recorded claude PID is gone after stop, and `tmux has-session` fails).
- **Stdio MCP servers are direct children of the Claude process** (verified: e.g. `gt-headroom-mcp`, `npx mcp-mermaid → node`, and a `mcp-proxy` for an HTTP server like `develocity-grdev` all appear as children of the interactive `claude` pane process). Killing the pane tears down that process group, so those MCP servers go with it — when Claude dies their stdin closes and well-behaved servers exit.
- The AoE session row **remains** in `aoe list`, flipped to `Status: Stopped` (verified). It is NOT trashed or purged, and it stays in **the same group** (and same id) — stopping is process-only, so its placement in the list is unchanged and it keeps clustering with its siblings (verified: a session in group `X` is still in group `X` after stop).

Contrast with the destructive alternatives — do not use these if the goal is "stop but keep":
- `aoe remove <id>` → moves the session to **trash** (recoverable via `aoe session restore`).
- `aoe rm --purge <id>` → **permanent** deletion.

**Caveat — Bash-tool background jobs are NOT killed.** Claude Code runs `Bash` commands (including `run_in_background`) under a separate `cc-daemon` PTY-host daemon, not under the interactive pane process, and that daemon is shared across sessions. Long-running background jobs a session started therefore survive `aoe session stop`. Only the Claude process and its **MCP** children are guaranteed to be reaped. If the user needs those background jobs gone too, identify and kill them separately.

**Caveat — purely remote MCP.** An HTTP/SSE MCP server reached directly (no local proxy) has no local process to kill; only its client side inside Claude goes away. A `mcp-proxy` wrapper, being a child process, does get killed.

## Steps

1. **Resolve the session and profile.** Args: a session title or id, plus an optional `--profile`. Resolve the profile the same way the other AoE skills do: explicit `--profile` → else `$AGENT_OF_EMPIRES_PROFILE` → else match `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` against each profile's `config.toml` (see the `aoe-session` skill). On a single-account host it is that one profile. If the title is ambiguous or you are unsure which profile holds it, locate it: `aoe list -p <profile>` (check each profile). Operate by **id** when a title might be duplicated.

2. **Capture the process tree BEFORE stopping** (so stragglers can be verified and cleaned). Find the tmux session and its pane pid, then record all descendant PIDs — flag the MCP ones:
   ```sh
   sess=$(tmux ls 2>/dev/null | grep -i "<title-or-idprefix>" | cut -d: -f1)
   pane_pid=$(tmux list-panes -t "$sess" -F '#{pane_pid}' | head -1)
   # record $pane_pid and its descendants; MCP children match: mcp, mcp-proxy, gt-headroom, mermaid, develocity, server-*
   ```
   Keep the descendant PID list for step 4. (If the session is already stopped/dead there is no pane — skip to step 3, nothing to verify.)

3. **Stop the session:**
   ```sh
   aoe session stop "<id-or-title>" -p "<profile>"
   ```

4. **Verify the teardown** (this skill confirms rather than assumes):
   - Session still listed, now stopped: `aoe list -p <profile> | grep "<title>"` and `aoe session show "<id-or-title>" -p <profile>` shows `Status: Stopped` (occasionally `Error`, but still listed — both mean "kept").
   - tmux gone: `tmux has-session -t "$sess"` fails.
   - Claude process gone: the recorded `pane_pid` no longer exists (`ps -p <pane_pid>`).
   - **No leaked MCP children:** none of the recorded MCP descendant PIDs survive (`ps -p <pid>`). If any linger (a detached server that ignored stdin EOF — rare), terminate them: `kill <pid>`, then `kill -9 <pid>` if still alive. Report anything you had to force-kill.

5. **Report back:**
   - The session name/id and that it is **stopped but still in the AoE list** (restartable).
   - That the Claude process was terminated and its MCP servers were torn down (plus any stragglers you had to clean up).
   - How to resume: `aoe session start "<title>" -p "<profile>"` (it resumes the same conversation, subject to the resume-target caveats in the `aoe-session` skill).

## One-liner

For a quick, non-forensic stop when verification isn't needed:
```sh
aoe session stop "<id-or-title>" -p "<profile>"
```
Everything above (capture → verify → clean stragglers) is the robust version; use it when the user cares that MCP/child processes are actually gone.
