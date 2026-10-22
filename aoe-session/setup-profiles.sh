#!/usr/bin/env bash
# Create/refresh the per-account Agent of Empires profiles used by the
# session-launch skills. Each profile pins one Claude account's
# CLAUDE_CONFIG_DIR via its `environment` list, which aoe injects onto every
# session launched under that profile.
#
# Idempotent — re-run any time; existing profiles are kept and their config
# rewritten (config is declarative). Companion to install-daemon.sh.
#
# Usage:  ./setup-profiles.sh            # create/refresh profiles
#         ./setup-profiles.sh --verify   # also launch a probe per profile and
#                                         # confirm CLAUDE_CONFIG_DIR is injected;
#                                         # exits 1 if any profile fails
#
# It also points each account's settings.json statusLine at statusline.sh (in
# this dir), labelled with the profile name; see STATUSLINE_COLOURS below.
#
# NOTE: this only wires the aoe profile -> config-dir mapping. It does NOT
# authenticate the accounts (log in / copy credentials into those config dirs
# per machine separately), and it does NOT encode remote-control on/off — the
# skills decide that dynamically from each account's policy-limits.json.
set -euo pipefail

# --- Default account table: "profile_name=CLAUDE_CONFIG_DIR" -----------------
# Absolute paths (no ~); $HOME expands at runtime. These are the CREATOR
# machine's accounts; a host whose accounts differ should NOT edit them here
# (that would push machine-specific values through the shared repo). Instead
# drop a machine-local override file — see below.
PROFILES=(
  "personal=$HOME/.claude-personal"
  "work=default"
)
DEFAULT_PROFILE="personal"

# Status line label colour per profile, as ANSI SGR codes ("profile=code", space
# separated). A profile not listed gets 36 (cyan). Set INSTALL_STATUSLINE=0 in
# the machine-local file to leave every account's statusLine alone.
STATUSLINE_COLOURS="personal=95 work=96"
INSTALL_STATUSLINE=1

# Turn off Claude's commit/PR attribution (Co-Authored-By trailer, "Generated
# with Claude Code" PR footer, session URL) in every account's settings.json.
# Set INSTALL_NO_ATTRIBUTION=0 in the machine-local file to leave it alone.
INSTALL_NO_ATTRIBUTION=1

# Machine-local override (kept OUT of the shared repo): if this file exists it
# is sourced here and may redefine PROFILES / DEFAULT_PROFILE for this host.
# Use the value "default" for an account that uses Claude's default config
# (~/.claude.json in HOME) — that omits CLAUDE_CONFIG_DIR (see the writer below).
# e.g. a single-account workstation whose login is the default account:
#   PROFILES=( "personal=default" ); DEFAULT_PROFILE="personal"
LOCAL_CONF="${AOE_SKILL_PROFILES_CONF:-$HOME/.agent-of-empires/skill-profiles.conf}"
if [ -f "$LOCAL_CONF" ]; then
  # shellcheck disable=SC1090
  . "$LOCAL_CONF"
  echo "using machine-local profile table: $LOCAL_CONF"
fi
# -----------------------------------------------------------------------------

command -v aoe >/dev/null || { echo "ERROR: aoe not found. Install with: brew install aoe" >&2; exit 1; }
PROFILES_DIR="$HOME/.agent-of-empires/profiles"
STATUSLINE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/statusline.sh"

# Point an account's settings.json statusLine at statusline.sh, labelled with
# the profile name. Only the statusLine key changes. The file is rewritten in
# place rather than replaced, so its mode (the personal account's is 0600) and
# a symlinked settings.json both survive.
install_statusline() {
  local name="$1" dir="$2" colour=36 pair settings cmd tmp
  for pair in $STATUSLINE_COLOURS; do
    [ "${pair%%=*}" = "$name" ] && colour="${pair#*=}"
  done
  if [ ! -d "$dir" ]; then
    echo "  statusLine: skipped, $dir does not exist yet"
    return
  fi
  command -v jq >/dev/null || { echo "  statusLine: skipped, jq not found" >&2; return; }
  settings="$dir/settings.json"
  [ -s "$settings" ] || echo '{}' > "$settings"
  cmd="'$STATUSLINE_SCRIPT' $name $colour"
  if [ "$(jq -r '.statusLine.command // empty' "$settings")" = "$cmd" ]; then
    echo "  statusLine: up to date"
    return
  fi
  tmp="$(mktemp)"
  jq --arg cmd "$cmd" '.statusLine = {type: "command", command: $cmd}' "$settings" > "$tmp"
  cat "$tmp" > "$settings"
  rm -f "$tmp"
  echo "  statusLine: installed in $settings"
}

# Blank the commit and PR attribution in an account's settings.json, and set the
# older includeCoAuthoredBy flag too for builds that predate `attribution`.
# Other keys under `attribution` are kept. Rewritten in place, like the
# statusLine above.
NO_ATTRIBUTION_JQ='.attribution = ((.attribution // {}) + {commit: "", pr: "", sessionUrl: false}) | .includeCoAuthoredBy = false'
install_no_attribution() {
  local dir="$1" settings tmp
  if [ ! -d "$dir" ]; then
    echo "  attribution: skipped, $dir does not exist yet"
    return
  fi
  command -v jq >/dev/null || { echo "  attribution: skipped, jq not found" >&2; return; }
  settings="$dir/settings.json"
  [ -s "$settings" ] || echo '{}' > "$settings"
  if jq -e "($NO_ATTRIBUTION_JQ) == ." "$settings" >/dev/null; then
    echo "  attribution: already off"
    return
  fi
  tmp="$(mktemp)"
  jq "$NO_ATTRIBUTION_JQ" "$settings" > "$tmp"
  cat "$tmp" > "$settings"
  rm -f "$tmp"
  echo "  attribution: turned off in $settings"
}

for entry in "${PROFILES[@]}"; do
  name="${entry%%=*}"
  cfgdir="${entry#*=}"

  if [ -d "$PROFILES_DIR/$name" ]; then
    echo "profile exists:  $name"
  else
    aoe profile create "$name" >/dev/null
    echo "profile created: $name"
  fi

  mkdir -p "$PROFILES_DIR/$name"
  if [ "$cfgdir" = "default" ] || [ -z "$cfgdir" ]; then
    # DEFAULT-config account: CLAUDE_CONFIG_DIR must be genuinely UNSET, so it is
    # OMITTED from the environment list below (NOT set to ""). This claude build
    # does NOT treat an empty string as unset: CLAUDE_CONFIG_DIR="" sends it to a
    # bogus config dir and it fails to find conversations ("No conversation found"
    # on --resume). Unset → claude uses the default ~/.claude.json config + ~/.claude
    # data dir with creds from the login Keychain. Do NOT set it to ~/.claude
    # either: that relocates the config file to ~/.claude/.claude.json (a
    # different, empty file) and forces onboarding.
    # Because aoe sessions inherit the tmux SERVER's global env, a stale
    # CLAUDE_CONFIG_DIR leaked there (e.g. by a cmux/Claude session on the shared
    # socket) would bleed through and run this profile under the WRONG account.
    # Omitting relies on that global being clean — the block after the loop clears
    # it, and --verify flags a leak that reappears later.
    cat > "$PROFILES_DIR/$name/config.toml" <<EOF
# Managed by setup-profiles.sh — DEFAULT-config account (~/.claude.json in HOME).
# CLAUDE_CONFIG_DIR is intentionally OMITTED (must be genuinely unset — this
# claude build does NOT treat "" as unset). setup-profiles.sh keeps the tmux
# server-global CLAUDE_CONFIG_DIR clear so nothing leaks in.
environment = [
  "AGENT_OF_EMPIRES_PROFILE=$name",   # self-reference so nested aoe spawns inherit the account
  "NODE_OPTIONS=",                    # blanks any inherited cmux --require shim
]
EOF
    echo "  CLAUDE_CONFIG_DIR=(default; omitted/unset)"
  else
    cat > "$PROFILES_DIR/$name/config.toml" <<EOF
# Managed by setup-profiles.sh — Claude account => CLAUDE_CONFIG_DIR mapping.
environment = [
  "CLAUDE_CONFIG_DIR=$cfgdir",
  "AGENT_OF_EMPIRES_PROFILE=$name",   # self-reference so nested aoe spawns inherit the account
  "NODE_OPTIONS=",                     # blanks any inherited cmux --require shim
]
EOF
    echo "  CLAUDE_CONFIG_DIR=$cfgdir"
    [ -d "$cfgdir" ] || echo "  WARNING: $cfgdir does not exist — that account is not set up on this machine yet." >&2
  fi

  if [ "$INSTALL_STATUSLINE" = 1 ]; then
    case "$cfgdir" in default|"") install_statusline "$name" "$HOME/.claude" ;; *) install_statusline "$name" "$cfgdir" ;; esac
  fi
  if [ "$INSTALL_NO_ATTRIBUTION" = 1 ]; then
    case "$cfgdir" in default|"") install_no_attribution "$HOME/.claude" ;; *) install_no_attribution "$cfgdir" ;; esac
  fi
done

# The default-config account relies on CLAUDE_CONFIG_DIR being genuinely unset,
# but aoe sessions inherit the tmux SERVER's global env — clear any stale value
# leaked there (e.g. by a cmux/Claude session) so it cannot bleed into a
# default-account session. Harmless when no server is running or the var is
# already unset; non-default profiles inject their own path per launch, so this
# cannot misroute them.
if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
  if tmux show-environment -g CLAUDE_CONFIG_DIR >/dev/null 2>&1; then
    tmux set-environment -g -u CLAUDE_CONFIG_DIR
    echo "cleared stale tmux global CLAUDE_CONFIG_DIR (default-account safety)"
  fi
fi

# tmux's stock 2000-line scrollback is only a few minutes of agent output. This
# script doesn't own ~/.tmux.conf (it lives in github.com/tomdcc/dotfiles), so
# it only prints a hint when the limit hasn't been raised.
tmux_conf=""
for f in "$HOME/.tmux.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"; do
  [ -e "$f" ] && { tmux_conf="$f"; break; }
done
history_limit=""
[ -n "$tmux_conf" ] && history_limit="$(grep -E '^[[:space:]]*set(-option)?[[:space:]].*history-limit[[:space:]]+[0-9]+' "$tmux_conf" | awk '{print $NF}' | tail -1 || true)"
if [ "${history_limit:-0}" -lt 10000 ]; then
  echo "HINT: tmux scrollback is ${history_limit:-the default 2000} lines; agent output soon scrolls off." >&2
  echo "      Set 'set-option -g history-limit 50000' in ~/.tmux.conf, or run install.sh from" >&2
  echo "      github.com/tomdcc/dotfiles." >&2
fi

aoe profile default "$DEFAULT_PROFILE" >/dev/null
echo "default profile: $DEFAULT_PROFILE"
echo
aoe profile list 2>&1 | sed 's/^/  /'

# --- optional verification ---------------------------------------------------
if [ "${1:-}" = "--verify" ]; then
  echo
  echo "Verifying env injection (needs the serve daemon)..."
  aoe url >/dev/null 2>&1 || { echo "  no daemon — starting one for the check"; aoe serve --daemon >/dev/null 2>&1; sleep 2; }

  # aoe >= 1.20 refuses to launch any host session until agent hooks are
  # approved once per installation. Approval lets aoe write hooks into every
  # agent's own config (e.g. each account's claude settings.json), so it is the
  # user's call — report it rather than approving here. Older aoe has no
  # `hooks` command and never prints "not approved".
  if aoe hooks status 2>/dev/null | grep -q 'not approved'; then
    echo "  ✗ aoe agent hooks are not approved, so no session can launch." >&2
    echo "    Review \`aoe hooks status\`, then run \`aoe hooks approve\` and re-run --verify." >&2
    exit 1
  fi

  tmp="$(mktemp -d)"
  probe="$tmp/probe.sh"
  printf '#!/bin/sh\necho "$CLAUDE_CONFIG_DIR" > "%s/last.out"\n' "$tmp" > "$probe"
  chmod +x "$probe"

  set +e
  failed=0
  for entry in "${PROFILES[@]}"; do
    name="${entry%%=*}"; cfgdir="${entry#*=}"; t="verify-$name"
    # default-config account: CLAUDE_CONFIG_DIR is intentionally unset, so the
    # probe should see it empty.
    case "$cfgdir" in default|"") expect="" ;; *) expect="$cfgdir" ;; esac
    rm -f "$tmp/last.out"
    aoe add --scratch -t "$t" -p "$name" --cmd-override "$probe" </dev/null >/dev/null 2>&1
    # Keep start's output: when the launch itself is refused (e.g. hooks not
    # approved) the probe never runs, and this is the only place the reason shows.
    start_err="$(aoe session start "$t" -p "$name" </dev/null 2>&1)"
    sleep 2
    got="$(cat "$tmp/last.out" 2>/dev/null || echo '<none>')"
    if [ "$got" = "$expect" ]; then
      echo "  ✓ $name -> ${got:-(default; CLAUDE_CONFIG_DIR unset)}"
    else
      echo "  ✗ $name -> got '$got', expected '${expect:-(unset)}'"
      [ "$got" = "<none>" ] && [ -n "$start_err" ] && printf '%s\n' "$start_err" | sed 's/^/      /'
      failed=$((failed + 1))
    fi
    aoe rm "$t" -p "$name" --purge </dev/null >/dev/null 2>&1
  done
  set -e
  rm -rf "$tmp"
  if [ "$failed" -gt 0 ]; then
    echo "Verification FAILED for $failed profile(s)." >&2
    exit 1
  fi
fi
