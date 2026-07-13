---
name: aoe-session
description: Reference for launching/resuming Claude sessions via Agent of Empires (aoe) — per-account profiles, the single serve daemon, and the add/start/send flow. The new-claude-session, start-issue, and resume-session skills default to this; read it for the AoE launch details and one-time setup.
---

# AoE Session (reference)

Agent of Empires (`aoe`) is the default launcher for `new-claude-session`, `start-issue`, and `resume-session`. AoE is tmux-backed (sessions are real `aoe_<title>_<idprefix>` tmux sessions), so the discovery/verification logic of those skills is unchanged — only the launch step differs, and sessions additionally appear on AoE's web/mobile dashboard. This file is the canonical description of the AoE launch flow and its one-time setup; the three skills carry a concise inline copy and point here.

Verified on this machine, **aoe 1.12.1**, host (non-sandbox) sessions.

## One-time setup: one aoe profile per Claude account

A profile's `config.toml` `environment` list is injected onto the host agent's launch command, so it carries the account's `CLAUDE_CONFIG_DIR` (this replaces the tmux skills' `-e CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"`). Values are **literal absolute paths** (no `~`, `$HOME`, `$VAR`). Already created on this machine:

| Profile | CLAUDE_CONFIG_DIR | Remote control |
|---|---|---|
| `personal` | `/Users/tom/.claude-personal` | allowed → pass `--remote-control` |
| `work` | `/Users/tom/.claude` | disabled (`policy-limits.json`) → omit `--remote-control` |

```toml
# ~/.agent-of-empires/profiles/personal/config.toml
environment = [
  "CLAUDE_CONFIG_DIR=/Users/tom/.claude-personal",
  "AGENT_OF_EMPIRES_PROFILE=personal",   # self-reference so nested aoe spawns inherit the account
  "NODE_OPTIONS=",                        # blanks any cmux --require shim inherited by the daemon
]
```

Add a profile with `aoe profile create <name>` then write its `config.toml`. AoE requires ≥1 profile to always exist (you cannot delete the last one; `rename` instead).

## The serve daemon (single, global)

There is **one** daemon for all profiles (single `~/.agent-of-empires/serve.pid`, port 8080); starting a second is refused. Ensure it before launching:

```sh
if aoe url >/dev/null 2>&1; then :; else aoe serve --daemon; fi   # add --remote to expose via Tailscale/Cloudflare
aoe url            # prints the dashboard URL; exits non-zero when down
```
Leave it running across sessions; do not stop it on exit. `aoe serve --stop` stops it, `aoe killall` tears down everything.

## Resolve the profile (= account)

Precedence: explicit `--profile <name>` → else `$AGENT_OF_EMPIRES_PROFILE` if set (auto when the *launching* session was itself AoE-started, via the self-reference above) → else match `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` against each profile's `config.toml` `CLAUDE_CONFIG_DIR`. No match → tell the user to create a profile (setup above).

`allow_remote` = `restrictions.allow_remote_control.allowed` from `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/policy-limits.json` (true when the file is absent). Pass Claude's native `--remote-control` **only when `allow_remote`**.

## Launch — new session

```sh
aoe add "<dir>" -t "<title>" -p "<profile>" --cmd claude \
  ${allow_remote:+--extra-args "--remote-control <title>"}      # ONLY when allow_remote
aoe session start "<title>" -p "<profile>"                       # detached, exit 0 (do NOT use -l: it attaches a TTY and errors headless)
# deliver the warmup/initial prompt as a real message (NOT via --extra-args, which is whitespace-split into argv):
aoe send "<title>" "<WARMUP-OR-INITIAL-PROMPT>" -p "<profile>"
```

- `<dir>` as a positional path is used **only as cwd** — an existing `wtp` worktree is not hijacked (verified: worktree/branch untouched, no new branch). Pass `-w/--worktree <branch>` only if you *want* AoE to create the worktree.
- **Trust-prompt gotcha:** a first-run/untrusted folder makes claude show "Is this a project you trust?" *before* its input, and that dialog **swallows the first `aoe send`** (verified). Real worktrees are usually already trusted. Defensive: after `session start`, `aoe session capture <title>` (or `tmux capture-pane -t aoe_<title>_<idprefix> -p`); if the trust prompt is showing, dismiss it (`tmux send-keys -t <tmux-sess> Enter`) before `aoe send`. `aoe add -y/--yolo` skips permission prompts but is broader than needed.
- `aoe add` prints a machine-readable `ID:`; the tmux session is `aoe_<title>_<idprefix>` — verify with `tmux has-session`.

## Launch — resume

Preferred, AoE-native (builds a `claude --resume <id>` session for the transcript's cwd and puts it on the dashboard):
```sh
aoe session import "<cwd>" -p "<profile>"     # scans for Claude conversations at/under <cwd>
aoe session start "<title-or-id>" -p "<profile>"
```
Or pin a known session id onto a session you create:
```sh
aoe add "<cwd>" -t "<title>" -p "<profile>" --cmd claude ${allow_remote:+--extra-args "--remote-control <title>"}
aoe session set-session-id "<title>" "<session-id>" -p "<profile>"   # pin the resume target
aoe session start "<title>" -p "<profile>"
```
(Passing `--extra-args "--resume <id>"` also works, but AoE appends its own `--session-id`, so `import`/`set-session-id` are cleaner.)

## Nesting from within a session

Spawning a child is just a Bash call to `aoe add`/`session start` from inside a running session — same as `tmux new-session` today. AoE also has first-class `-P/--parent <session>` to create a true sub-session grouped under the caller (not yet exercised here; worth trying vs. the flat-sibling model).

## Reporting

Report: profile (account) + dashboard URL (`aoe url`); the title + `ID:` + backing tmux session; how to reach it — dashboard URL, `tmux attach -t aoe_<title>_<idprefix>`, or `aoe` (TUI).

## Proven end-to-end

Real `claude --remote-control` under AoE: personal profile → `CLAUDE_CONFIG_DIR=/Users/tom/.claude-personal` + live `claude.ai/code` bridge; work profile → `CLAUDE_CONFIG_DIR=/Users/tom/.claude` + no `--remote-control`, no bridge. `aoe send` delivers a prompt reliably once past the trust prompt.
