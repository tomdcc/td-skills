---
name: aoe-session
description: Reference for launching/resuming Claude sessions via Agent of Empires (aoe) — per-account profiles, the single serve daemon, and the add/start/send flow. The new-claude-session, start-issue, and resume-session skills default to this; read it for the AoE launch details and one-time setup.
---

# AoE Session (reference)

Agent of Empires (`aoe`) is the default launcher for `new-claude-session`, `start-issue`, and `resume-session`. AoE is tmux-backed (sessions are real `aoe_<title>_<idprefix>` tmux sessions), so the discovery/verification logic of those skills is unchanged — only the launch step differs, and sessions additionally appear on AoE's web/mobile dashboard. This file is the canonical description of the AoE launch flow and its one-time setup; the three skills carry a concise inline copy and point here.

Verified on this machine, **aoe 1.12.1**, host (non-sandbox) sessions. Setup also verified on **aoe 1.20.0**, which adds a one-time hooks approval (see "Agent hooks approval" below).

## One-time setup: one aoe profile per Claude account

A profile's `config.toml` `environment` list is injected onto the host agent's launch command, so it carries the account's `CLAUDE_CONFIG_DIR` (this replaces the tmux skills' `-e CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"`). Values are **literal absolute paths** (no `~`, `$HOME`, `$VAR`).

**The live source of truth is `aoe profile list` — the profile layout is per-machine, not fixed.** The table below is the **creator machine's** layout (illustrative). A host whose accounts differ captures its own layout in a machine-local file, `~/.agent-of-empires/skill-profiles.conf` (sourced by `setup-profiles.sh`, kept out of this repo); e.g. a single-account workstation whose login is Claude's **default** account sets `PROFILES=( "personal=default" )` there (see the gotcha next).

> **⚠️ The default account needs `CLAUDE_CONFIG_DIR` genuinely UNSET (omitted) — never a path, and never an empty string.** Claude's default keeps the *config file* at `~/.claude.json` (in `$HOME`) but the *data dir* at `~/.claude` — a split that **no single `CLAUDE_CONFIG_DIR` value reproduces**. Setting `CLAUDE_CONFIG_DIR=~/.claude` relocates the config file to `~/.claude/.claude.json` (a *different*, empty file with no `oauthAccount`) → the session comes up **at the login/onboarding screen** even though credentials exist in the Keychain. And `CLAUDE_CONFIG_DIR=""` is **not** treated as unset by this claude build — it points claude at a bogus config dir, so it fails to find conversations (`No conversation found` on `--resume`). *(An earlier version of this note claimed empty == unset and set `CLAUDE_CONFIG_DIR=`; that was wrong and broke default-account resume.)*
>
> The catch: aoe sessions inherit the **tmux server's global environment**, and if that server was started by a shell that exported `CLAUDE_CONFIG_DIR` (a cmux/Claude session on the shared default socket does exactly this — verified `tmux show-environment -g` carries `CLAUDE_CONFIG_DIR=…/.claude-personal`), a profile that omits the var lets that **stale value bleed through** and the session silently runs under the *wrong* account. The fix is **not** an empty value (that breaks resume, above) but to **omit** `CLAUDE_CONFIG_DIR` from the default-account profile **and keep the server-global clear**: `setup-profiles.sh` clears it (`tmux set-environment -g -u CLAUDE_CONFIG_DIR`) and its `--verify` probe flags a leak that reappears. Only set `CLAUDE_CONFIG_DIR` to a real path for *non-default* accounts under an alternate dir (e.g. `~/.claude-personal`). No credential file export needed.

| Profile | CLAUDE_CONFIG_DIR | Remote control |
|---|---|---|
| `personal` | `/Users/tom/.claude-personal` | allowed → pass `--remote-control` |
| `work` | *(unset — default account)* | disabled (`policy-limits.json`) → omit `--remote-control` |

```toml
# ~/.agent-of-empires/profiles/personal/config.toml
environment = [
  "CLAUDE_CONFIG_DIR=/Users/tom/.claude-personal",
  "AGENT_OF_EMPIRES_PROFILE=personal",   # self-reference so nested aoe spawns inherit the account
  "NODE_OPTIONS=",                        # blanks any cmux --require shim inherited by the daemon
]
```

Add a profile with `aoe profile create <name>` then write its `config.toml` — or run `setup-profiles.sh` (in this skill dir), which does exactly this for the account table at its top and is idempotent. AoE requires ≥1 profile to always exist (you cannot delete the last one; `rename` instead).

## The serve daemon (single, global)

There is **one** daemon for all profiles (single `~/.agent-of-empires/serve.pid`, port 8080); starting a second is refused. Ensure it before launching:

```sh
if aoe url >/dev/null 2>&1; then :; else aoe serve --daemon; fi   # add --remote to expose via Tailscale/Cloudflare
aoe url            # prints the dashboard URL; exits non-zero when down
```
Leave it running across sessions; do not stop it on exit. `aoe serve --stop` stops it, `aoe killall` tears down everything.

### Autostart at login (per machine)

`install-daemon.sh` (in this skill dir) installs a launchd LaunchAgent (`~/Library/LaunchAgents/com.tomdunstan.aoe-serve.plist`) that starts the daemon at login and restarts it on crash. It resolves machine-specific paths at runtime (Homebrew prefix, the real `claude` bin dir avoiding cmux shims, `$HOME`), so it is portable across macOS machines and re-runnable:

```sh
./install-daemon.sh                 # install + load (port 8080; AOE_SERVE_PORT overrides)
./install-daemon.sh --uninstall     # bootout + remove the plist
```

Control the agent: `launchctl kickstart -k gui/$(id -u)/com.tomdunstan.aoe-serve` (restart), `launchctl bootout gui/$(id -u)/com.tomdunstan.aoe-serve` (disable this session). It runs `aoe serve` in the **foreground** under launchd (not `--daemon`) so KeepAlive can supervise it; `KeepAlive.SuccessfulExit=false` restarts on crash but leaves a deliberate `aoe serve --stop` down. Logs: `~/Library/Logs/aoe-serve.{out,err}.log`.

The plist wraps the start in `/bin/sh -c 'tmux set-environment -g -u CLAUDE_CONFIG_DIR …; exec aoe serve …'` so **every daemon (re)start clears any leaked `CLAUDE_CONFIG_DIR` from the shared default tmux socket's global env** — sessions inherit that global, and a var-omitting default-account profile would otherwise silently run under whatever config dir a cmux/Claude session left there (the leak gotcha above). `exec` keeps the daemon PID under KeepAlive. This is daemon-start hygiene, not a continuous guard: if something re-pollutes the global *after* start, re-clear it (`tmux set-environment -g -u CLAUDE_CONFIG_DIR`) or kickstart the agent. `setup-profiles.sh --verify` still flags a live leak.

### Standing session at login (per machine)

`install-startup-session.sh` (in this skill dir) installs a per-machine LaunchAgent (`com.tomdunstan.aoe-session-<name>`) that, at each login, waits for the serve daemon then creates + starts one named session — aoe/tmux sessions don't survive a reboot, so it recreates it (idempotent: skipped if already present). The emitted runner + plist are machine-local (self-contained); only this installer is versioned.

```sh
./install-startup-session.sh <session-name> [directory] [profile]   # dir defaults to ~/scratch/<profile>-claude-scratch; profile to personal
./install-startup-session.sh <session-name> "" work                 # "" = default dir, for a non-default profile
./install-startup-session.sh --uninstall <session-name>
```

The **profile defaults to `personal`**, so each machine's standing session runs under that machine's `personal` account — the default-config account on a single-account host, or `~/.claude-personal` on a two-account host — no per-machine edit needed. The runner reads that profile's `CLAUDE_CONFIG_DIR` (or the default) to decide `--remote-control` from `policy-limits.json`, exactly like the launch flow. The **directory defaults to `~/scratch/<profile>-claude-scratch`** (e.g. `~/scratch/personal-claude-scratch`): one subdir per profile, so standing scratch sessions under different accounts never share a working dir (otherwise their scratch files, `CLAUDE.md` and `.claude/` project settings would be shared across accounts). Pass an explicit directory only for a non-scratch standing session. Pick a machine-identifying `<session-name>` (e.g. `imac-scratch`, `<host>-scratch`). The session comes up idle (no prompt); its cwd's first-run "trust this folder?" is a one-time confirm that then persists.

**Bringing up a fresh machine:** (1) `brew install aoe tmux satococoa/tap/wtp` (`wtp` creates the worktrees for `start-issue`/`new-issue-worktree`; it comes from its author's tap, not homebrew-core); (1a) clone `github.com/tomdcc/dotfiles` and run its `install.sh` for the tmux config (50000-line scrollback, bare Page Up into copy-mode, mouse on) — `setup-profiles.sh` prints a hint if the scrollback is still under 10000; (2) `./install-daemon.sh`; (2a) on aoe ≥ 1.20, `aoe hooks approve` after the user confirms (see "Agent hooks approval" below); (3) `./setup-profiles.sh --verify` to create the per-account profiles (drop a machine-local `~/.agent-of-empires/skill-profiles.conf` if the accounts differ from the default table — use `<name>=default` for the default-config account) — the daemon alone is inert without them. It also sets each account's `settings.json` `statusLine` to `statusline.sh` (this dir), which shows the profile name in the profile's colour (`STATUSLINE_COLOURS`), then the cwd, git branch, model and `ctx:N%`; `INSTALL_STATUSLINE=0` in the machine-local file opts out. It also turns off commit/PR attribution (`attribution.commit`/`pr` blanked, `sessionUrl: false`, `includeCoAuthoredBy: false`) in each account's `settings.json`; `INSTALL_NO_ATTRIBUTION=0` opts out. Re-run it after authenticating an account whose config dir did not exist yet; (4) authenticate each account (`claude` login; the default account's token lives in the login Keychain and is read directly); (4a) `../link-skills.sh` (repo root) to symlink every td-skills skill into each account's `skills/` dir (`~/.claude` and every `~/.claude-*` holding a `.claude.json`, so run it after the accounts exist; re-run after adding or removing a skill or an account; it also sets this clone's `core.hooksPath` to `.githooks`, whose `commit-msg` rejects any message mentioning claude, since git never installs hooks on clone); (5) `./install-startup-session.sh <host>-scratch` to add a standing scratch session under the `personal` profile, in `~/scratch/personal-claude-scratch`.

### Agent hooks approval (aoe ≥ 1.20, per installation)

aoe 1.20+ refuses to launch any host session until agent hooks are approved: `aoe session start` fails with `agent hook paths have not been approved; run \`aoe hooks approve\` before launching this host session`. Approval lets aoe write status hooks (running/waiting/idle) and session-id hooks (needed for native resume) into **each agent's own config**: for Claude, every profile's `settings.json` (e.g. `~/.claude-personal/settings.json`, `~/.claude/settings.json`). It is one approval for every agent and profile, and also covers Codex/Cursor/Gemini/Kiro/etc. configs (Kiro: may set its default agent). The hooks are no-ops outside aoe sessions (guarded by `$AOE_INSTANCE_ID`). Review with `aoe hooks status`, then `aoe hooks approve`. Because it edits the user's agent configs, **confirm with the user before approving** — scripts here never approve on their own; `setup-profiles.sh --verify` checks for it and stops with a pointer.

## Resolve the profile (= account)

Precedence: explicit `--profile <name>` → else `$AGENT_OF_EMPIRES_PROFILE` if set (auto when the *launching* session was itself AoE-started, via the self-reference above) → else match the launching session's config against each profile's `config.toml`: a profile with a **non-empty** `CLAUDE_CONFIG_DIR` matches when it equals `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`; a profile with **no** `CLAUDE_CONFIG_DIR` entry is the **default-config account** and matches when the launching session also has no `CLAUDE_CONFIG_DIR` set (`${CLAUDE_CONFIG_DIR:-}` empty). No match → tell the user to create a profile (setup above). On a single-account default-config host this resolves to that one profile.

`allow_remote` = `restrictions.allow_remote_control.allowed` from `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/policy-limits.json` (true when the file is absent). Pass Claude's native `--remote-control` **only when `allow_remote`**.

## Group (= base repo)

Put every session in a group named after its **base repository**, so a repo's main checkout and all its worktree sessions cluster together (aoe otherwise defaults the group to the *parent folder* — which buckets by `…-worktrees`/`gradle` instead of the repo). Derive `<group>` from the session's directory **via git** — a linked worktree's `--git-common-dir` points at the *main* checkout, whatever path the worktree lives under — falling back to the directory basename for a non-repo dir. Pass it as `-g "<group>"` on `aoe add`:

```sh
cd_common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -n "$cd_common" ]; then group=$(basename "$(dirname "$cd_common")"); else group=$(basename "$dir"); fi
```

Examples: `…/gradle/dv-release-worktrees/68205-…` and `…/gradle/dv-release` both → `dv-release`; `…/gradle/worktrees/versatility/rnett/…` (a dv-design-docs worktree that landed *outside* `dv-design-docs-worktrees/`) → `dv-design-docs`; `…/code/blyt` → `blyt`; a non-repo dir like `…/scratch` → `scratch`.

> **Don't** string-match the path for `-worktrees/`. Worktrees don't always live under `<base>-worktrees/`: a missing per-repo `.wtp.yml` symlink sends `wtp` to its default `…/gradle/worktrees/<branch>`, which encodes no repo name — a path match would then mis-group the session. The git lookup is authoritative regardless of layout.

Re-group an existing session with `aoe group move <title-or-id> <group> -p <profile>` (the group is auto-created).

## Naming (= distinct purpose)

The group is the base repo; the **title** must still distinguish this session from others in that group.

- **Worktree session** → name it after the branch/issue (e.g. `68205-object-storage-grafana-use-tag`); already distinct.
- **No own worktree** (a main checkout or plain dir) → do **not** fall back to the bare repo/dir name — that's now the *group*, so it neither distinguishes nor describes the session. If there's any clue to its purpose — an initial task, an issue number, the prompt about to be sent, a resumed transcript's first message — coin a short meaningful title from it (e.g. a `dv-release` main-checkout session doing a status check on #67440 → `67440-status-check`). If there's **no** clue at all, **ask the user** for a title rather than guessing.

Keep titles short (they become the tmux session `aoe_<title>_<idprefix>`, with long titles cut short — see "Launch — new session" — and, when remote control is on, the `--remote-control` name). Rename later with `aoe session rename <id-or-title> -t "<new-title>" -p <profile>` (also takes `-g` to re-group).

## Launch — new session

```sh
id=$(aoe add "<dir>" -t "<title>" -p "<profile>" -g "<group>" --cmd claude \
  ${allow_remote:+--extra-args "--remote-control <title>"} | awk '$1 == "ID:" { print $2 }')   # ONLY when allow_remote; -g = base repo (see "Group")
aoe session start "$id" -p "<profile>"                          # detached, exit 0 (do NOT use -l: it attaches a TTY and errors headless)
tmux_sess=$(tmux ls -F '#S' | grep -- "_${id:0:8}\$")           # never build it from the title (see below)
# deliver the warmup/initial prompt as a real message (NOT via --extra-args, which is whitespace-split into argv):
aoe send "$id" "<WARMUP-OR-INITIAL-PROMPT>" -p "<profile>"
```

- `<dir>` as a positional path is used **only as cwd** — an existing `wtp` worktree is not hijacked (verified: worktree/branch untouched, no new branch). Pass `-w/--worktree <branch>` only if you *want* AoE to create the worktree.
- **Trust-prompt gotcha:** a first-run/untrusted folder makes claude show "Is this a project you trust?" *before* its input, and that dialog **swallows the first `aoe send`** (verified). Real worktrees are usually already trusted. Defensive: after `session start`, `aoe session capture "$id" -p <profile>`; if the trust prompt is showing, dismiss it before `aoe send`. **The highlighted default is "No, exit", so a bare Enter quits claude**: select "Yes, I trust this folder" first (`tmux send-keys -t "$tmux_sess" Down`, capture to confirm the `❯` is on it, then `Enter`). If the prompt also lists pre-approved permissions or commands the folder runs (from its `.claude/settings.json` or `.mcp.json`), ask the user before accepting. `aoe add -y/--yolo` skips permission prompts but is broader than needed.
- `aoe add` prints a machine-readable `ID:` — capture it and address the session by ID (`aoe session start/send/capture "$id"`), since a title can also match a trashed or duplicate session. The tmux session is `aoe_<title>_<idprefix>`, but aoe **shortens long titles** (`dv-75927-drv-sync-dashboard` → `aoe_dv-75927-drv-sync-da_1c32de9e`; observed: cut to 20 characters), so never build the name from the title: resolve it from the ID, `tmux_sess=$(tmux ls -F '#S' | grep -- "_${id:0:8}\$")`, and verify with `tmux has-session -t "$tmux_sess"`. Check it is non-empty: `tmux send-keys -t ""` silently targets the most recent session.

## Launch — resume

Preferred, AoE-native (builds a `claude --resume <id>` session for the transcript's cwd and puts it on the dashboard):
```sh
aoe session import "<cwd>" -p "<profile>"     # scans for Claude conversations at/under <cwd>
aoe session start "<title-or-id>" -p "<profile>"
```
Or pin a known session id onto a session you create:
```sh
aoe add "<cwd>" -t "<title>" -p "<profile>" -g "<group>" --cmd claude ${allow_remote:+--extra-args "--remote-control <title>"}
aoe session set-session-id "<title>" "<session-id>" -p "<profile>"   # pin the resume target
aoe session start "<title>" -p "<profile>"
```
(Passing `--extra-args "--resume <id>"` also works, but AoE appends its own `--session-id`, so `import`/`set-session-id` are cleaner.)

## Nesting from within a session

Spawning a child is just a Bash call to `aoe add`/`session start` from inside a running session — same as `tmux new-session` today. AoE also has first-class `-P/--parent <session>` to create a true sub-session grouped under the caller (not yet exercised here; worth trying vs. the flat-sibling model).

## Reporting

Report: profile (account) + dashboard URL (`aoe url`); the title + `ID:` + backing tmux session; how to reach it — dashboard URL, `tmux attach -t "$tmux_sess"` (resolved from the ID, not built from the title), or `aoe -p <profile>` (TUI).

## Proven end-to-end

Real `claude --remote-control` under AoE: personal profile → `CLAUDE_CONFIG_DIR=/Users/tom/.claude-personal` + live `claude.ai/code` bridge; work profile → `CLAUDE_CONFIG_DIR=/Users/tom/.claude` + no `--remote-control`, no bridge. `aoe send` delivers a prompt reliably once past the trust prompt.
