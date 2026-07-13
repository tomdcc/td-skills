---
name: resume-session
description: Resume a previous Claude session found by GitHub issue number or description, relaunching it (tmux+remote-control by default, cmux otherwise) with --resume so its prior context is intact. Use when the user wants to reopen/continue an existing session for a worktree or issue rather than start a fresh one.
---

# Resume Session

Find a previous Claude session — by GitHub issue number or a free-text description — and relaunch it in a tmux (or cmux) session, **resuming its transcript** so the prior context is intact. This is the resume counterpart of the `new-claude-session` skill: it shares the launcher logic, but adds session discovery and uses `--resume <id>` instead of injecting a warmup/initial prompt.

Args: an issue number or a description, plus an optional launcher flag (e.g. `/resume-session 251`, `/resume-session "host-lua fp seam" --tmux`, `/resume-session 208 --cmux`).

## Steps

1. **Resolve the config dir at runtime.** Sessions live under `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/`. This depends on which account/config is currently active, so compute it now rather than assuming — and the session you launch in step 7 MUST use the **same** config dir (both discovery here and the `-e CLAUDE_CONFIG_DIR` on launch). Set:
   ```
   CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; PROJ="$CFG/projects"
   ```

2. **Find candidate project dirs.** Each subdirectory of `$PROJ` is one working directory, encoded with path separators (and dots) flattened to `-`. Match against the arg:
   - **Issue number** (e.g. `251`): `ls -dt "$PROJ"/*251* 2>/dev/null` — worktrees are conventionally named `<issue>-<keywords>`, so the dir name contains the number.
   - **Description**: match dir names first (`ls -dt "$PROJ"/*<slug>*`); if nothing obvious, grep transcript contents for the phrase: `grep -rli "<phrase>" "$PROJ"/*/*.jsonl` (case-insensitive; may be slow over a large history — that's fine).

   The encoding is **not reversible** (a `-` may have been a `/`, `.`, or literal `-`), so do NOT decode a dir name back into a path — read the real cwd from inside the transcript in step 3.

3. **Enumerate transcripts and gather metadata.** Within each matched dir, every `*.jsonl` is one session. For each candidate collect: modified time, line count, the first real user message (skip the leading `{"type":"mode"}` line), and the `cwd` recorded inside. Note the *most recent* transcript may be a throwaway (e.g. a session that only ran warmup then was quit), so do NOT pick by mtime alone — weigh substance (line count / first user message) too. Example per-file probe:
   ```
   for f in <dir>/*.jsonl; do
     echo "=== $f ($(wc -l <"$f") lines, $(stat -f%Sm "$f")) ==="
     grep -m1 '"cwd"' "$f" | python3 -c 'import sys,json;print("cwd:",json.load(sys.stdin).get("cwd"))'
     grep -m1 '"type":"user"' "$f" | python3 -c 'import sys,json;m=json.load(sys.stdin).get("message",{});c=m.get("content");print("first:",(c if isinstance(c,str) else str(c))[:200])'
   done
   ```

4. **Pick the session to resume.**
   - Exactly one strong candidate → use it.
   - Multiple plausible candidates → **ask the user** (AskUserQuestion), listing each with its first-user-message summary, mtime, and line count so they can choose. Never silently guess between substantive sessions.
   - No candidate → stop and report that no matching session was found under `$CFG/projects`.

   Capture the chosen **session id** (the `.jsonl` basename, without extension) and the **working directory** (the `cwd` read from the transcript).

5. **Determine the launcher** (same rule as new-claude-session):
   - `--tmux` → **tmux** (remote control). `--cmux` → **cmux** (no remote control).
   - Otherwise read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/policy-limits.json` and check `restrictions.allow_remote_control.allowed`: `true` → tmux, `false` → cmux, absent → tmux.

6. **Derive the session name** from the working directory's basename (e.g. `.../251-hybrid-native-gdb-reload` → `251-hybrid-native-gdb-reload`). If a live tmux/cmux session of that name already exists, suffix `-2`, `-3`, … so the relaunch doesn't collide.

7. **Launch, resuming the transcript.** Unlike new-claude-session, pass **NO** warmup/initial prompt — `--resume` restores the prior context and the user picks up where they left off. Use the same runtime `CLAUDE_CONFIG_DIR` resolved in step 1.

   **tmux** (with remote control):
   ```
   tmux new-session -d -s "<session-name>" -c "<cwd>" ${CLAUDE_CONFIG_DIR:+-e CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"} -e NODE_OPTIONS= 'command claude --remote-control <session-name> --resume <session-id>'
   ```
   (`-e NODE_OPTIONS=` clears any `NODE_OPTIONS` inherited from the launching shell. cmux exports a `--require=…/restore-node-options.cjs` shim whose temp file gets garbage-collected, which then crashes every `node`/`npm`/`emcc` the spawned session runs. Starting the session with an empty `NODE_OPTIONS` avoids that.)

   **cmux** (without remote control):
   ```
   cmux new-workspace \
     --cwd "<cwd>" \
     --command "${CLAUDE_CONFIG_DIR:+CLAUDE_CONFIG_DIR=\"$CLAUDE_CONFIG_DIR\" }command claude --resume <session-id>"
   ```

8. **Report back** with:
   - Which session was resumed (id + a one-line summary of its first user message) and why it was chosen
   - The working directory
   - tmux: the session name and how to attach: `tmux attach -t <session-name>`
   - cmux: the workspace name
