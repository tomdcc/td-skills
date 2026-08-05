---
name: start-aoe-session
description: Start or restart an existing aoe session row — bring its Claude Code process (and MCP servers) back up, resuming the prior conversation in place. Use to wake a Stopped session, restart a wedged/Error or running one (stop→start), e.g. "start the 68432 session", "restart that session", "bring 69788 back up". The companion to stop-aoe-session. NOT for creating a brand-new session (use new-claude-session / start-issue) or importing a session aoe doesn't track (use resume-session).
---

# Start / Restart AoE Session

Bring an existing AoE session row back to life: relaunch its Claude Code process in the session's worktree, resuming the same conversation, so it reappears with its history intact. The row already exists in `aoe list` (e.g. after `stop-aoe-session`, or a crash/reboot that left it `Stopped`/`Error`). This is the companion to `stop-aoe-session`.

It is **start** and **restart** in one: a `Stopped`/`Error` session is started; a live one is restarted (stop → start).

> **Why the pre-flight checks matter.** `aoe session start` runs `claude --resume <agent_session_id>` from the session's `project_path`. Two real failure modes brick that silently, and both were hit on this machine:
> - **The worktree/cwd was deleted.** With the cwd gone, the shell falls back to `$HOME`, `claude --resume` looks in the wrong project bucket, prints `No conversation found with session ID: <uuid>`, and the pane dies. (The trust prompt then reads `Accessing workspace: /Users/tom` — the tell.)
> - **The pinned resume target is stale / never hit disk** (a ghost id from AoE's "fresher live observation" clobbering, or an empty thread). Same `No conversation found` → dead pane → `Status: Error`, and a restart just repeats it.
>
> So this skill **verifies the cwd and the resume target exist before starting**, and diagnoses rather than repeats the loop if they don't.

## Steps

1. **Resolve the session and profile.** Args: a session title or id, optional `--profile`, and an optional `--restart` to force stop→start even if already running. Resolve the profile as the other AoE skills do (explicit `--profile` → `$AGENT_OF_EMPIRES_PROFILE` → match `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` to a profile's `config.toml`; see `aoe-session`). **Operate by id when a title might be duplicated** — duplicate titles make `aoe session start "<title>"` misroute to the wrong row (observed). Read the row: `aoe session show "<id-or-title>" -p <profile>` → note `Path` (the cwd), `Status`, and (from `profiles/<profile>/sessions.json`) its `agent_session_id`.

2. **If it is already running** (`Status: Idle`, tmux session alive): without `--restart`, report it's already up and stop — do not relaunch (that would resume-fork or collide). With `--restart`, stop it first (`aoe session stop "<id>" -p <profile>`; see `stop-aoe-session`), then continue.

3. **Pre-flight: verify the cwd exists.**
   ```sh
   dir=$(aoe session show "<id>" -p "<profile>" | awk -F': *' '/Path/{print $2}')
   [ -d "$dir" ] && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
   ```
   If the directory is **missing**, do NOT start yet — the resume will fail. If it was a `wtp` worktree, recreate it at the **exact same path** (`wtp add <branch>` when the branch is on origin; large repos take >2 min, so run it in the background) so the path the transcript is keyed to reappears. If you cannot restore the path, stop and report; starting would only dead-pane.

4. **Pre-flight: verify the resume target has a transcript on disk.** Transcripts live under the **target profile's `CLAUDE_CONFIG_DIR`**, not always `~/.claude` — the default/`work` account uses `~/.claude`, but the `personal` account uses `~/.claude-personal` (its `config.toml` sets `CLAUDE_CONFIG_DIR=/Users/tom/.claude-personal`). Hardcoding `~/.claude` makes this check falsely report "absent" for every personal session and trigger a bogus re-pin. Resolve the config dir from the profile, then look up `<config-dir>/projects/<bucket>/<agent_session_id>.jsonl`, where the bucket is the cwd with every non-alphanumeric char replaced by `-`:
   ```sh
   # config dir for the TARGET profile (empty entry / no match => default account => ~/.claude)
   cfgdir=$(sed -n 's/^[[:space:]]*"CLAUDE_CONFIG_DIR=\([^"]*\)".*/\1/p' ~/.agent-of-empires/profiles/"<profile>"/config.toml)
   cfgdir=${cfgdir:-$HOME/.claude}
   bucket=$(printf '%s' "$dir" | sed 's#[^A-Za-z0-9]#-#g')
   ls -l "$cfgdir"/projects/"$bucket"/"<agent_session_id>".jsonl
   ```
   (When the skill runs under the same account it manages — the normal case — `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` equals `$cfgdir`; deriving from the profile's `config.toml` also covers cross-account `--profile` use.)
   - **Present** → good, proceed.
   - **Absent** (stale/ghost pin) → find the real conversation for this cwd and re-pin it. Pick the largest/most-recent transcript in that **same `$cfgdir/projects/$bucket`** that belongs to this session (grep it for a distinctive term, or take the most recently modified), then:
     ```sh
     aoe session set-session-id "<id>" "<real-uuid>" -p "<profile>"
     ```
     If the bucket itself is empty/missing, there is no conversation to resume — starting will come up fresh; tell the user rather than pretending history was recovered.

5. **Start it:**
   ```sh
   aoe session start "<id-or-title>" -p "<profile>"
   ```

6. **Handle the first-run trust prompt.** A first-run/untrusted folder shows *"Is this a project you trust?"* before the prompt, and it **swallows the first `aoe send`**. Pure resume needs no send, so it is usually harmless — but if you intend to send an initial message, capture first (`aoe session capture "<id>" -p <profile>`) and only send once past the prompt. Do **not** auto-accept a trust prompt whose scope is broader than the worktree (e.g. `/Users/tom`) — that is the signal the cwd was wrong (step 3); surface it instead.

7. **Verify it came up** (don't assume):
   - tmux alive: `tmux has-session -t aoe_<title>_<idprefix>`.
   - Pane is not dead and does **not** show `No conversation found` — capture the pane (`aoe session capture "<id>" -p <profile>` or `tmux capture-pane -p`). If it shows `No conversation found` / `Pane is dead`, the pre-flight missed something — re-check steps 3–4 (cwd present? pinned id on disk?) rather than restarting blindly.
   - `Status` returns to `Idle`, and the pane shows the resumed history.

8. **Report back:** the session name/id, that it resumed **in place** (same group, same worktree, history intact — or, if the bucket was empty, that it came up fresh), and how to attach (`tmux attach -t aoe_<title>_<idprefix>` or `aoe -p <profile>`). Note any repair you had to do (recreated worktree, re-pinned resume target).

## One-liner

When the session is known-healthy (cwd present, pin valid) and you just want it up:
```sh
aoe session start "<id-or-title>" -p "<profile>"
```
The pre-flight/verify steps above are the robust version — use them for anything in `Error`, anything not started in a while, or any session whose worktree might have been removed.

## See also
- `stop-aoe-session` — the inverse (halt Claude + MCP, keep the row).
- `aoe-session` — profile resolution, groups, the trust-prompt gotcha, and the resume-target clobbering background.
