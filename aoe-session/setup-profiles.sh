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
#                                         # confirm CLAUDE_CONFIG_DIR is injected
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
    # DEFAULT-config account: force CLAUDE_CONFIG_DIR to EMPTY (not merely unset).
    # aoe sessions inherit the tmux SERVER's global environment; if that server was
    # started from a shell that exported CLAUDE_CONFIG_DIR (e.g. a cmux/Claude
    # session on the shared default socket), merely OMITTING the var lets that stale
    # value bleed through — the session then runs under the WRONG account. An
    # explicit empty value overrides the leak, and claude treats empty as unset, so
    # it uses the default ~/.claude.json config + ~/.claude data dir with creds from
    # the login Keychain. Do NOT set it to ~/.claude: that relocates the config file
    # to ~/.claude/.claude.json (a different, empty file) and forces onboarding.
    cat > "$PROFILES_DIR/$name/config.toml" <<EOF
# Managed by setup-profiles.sh — DEFAULT-config account (~/.claude.json in HOME).
# CLAUDE_CONFIG_DIR is forced EMPTY to override any value leaked from the tmux
# server's global env; claude treats empty as unset (see setup-profiles.sh).
environment = [
  "CLAUDE_CONFIG_DIR=",
  "AGENT_OF_EMPIRES_PROFILE=$name",   # self-reference so nested aoe spawns inherit the account
  "NODE_OPTIONS=",                    # blanks any inherited cmux --require shim
]
EOF
    echo "  CLAUDE_CONFIG_DIR=(default; forced empty)"
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
done

aoe profile default "$DEFAULT_PROFILE" >/dev/null
echo "default profile: $DEFAULT_PROFILE"
echo
aoe profile list 2>&1 | sed 's/^/  /'

# --- optional verification ---------------------------------------------------
if [ "${1:-}" = "--verify" ]; then
  echo
  echo "Verifying env injection (needs the serve daemon)..."
  aoe url >/dev/null 2>&1 || { echo "  no daemon — starting one for the check"; aoe serve --daemon >/dev/null 2>&1; sleep 2; }

  tmp="$(mktemp -d)"
  probe="$tmp/probe.sh"
  printf '#!/bin/sh\necho "$CLAUDE_CONFIG_DIR" > "%s/last.out"\n' "$tmp" > "$probe"
  chmod +x "$probe"

  set +e
  for entry in "${PROFILES[@]}"; do
    name="${entry%%=*}"; cfgdir="${entry#*=}"; t="verify-$name"
    # default-config account: CLAUDE_CONFIG_DIR is intentionally unset, so the
    # probe should see it empty.
    case "$cfgdir" in default|"") expect="" ;; *) expect="$cfgdir" ;; esac
    rm -f "$tmp/last.out"
    aoe add --scratch -t "$t" -p "$name" --cmd-override "$probe" </dev/null >/dev/null 2>&1
    aoe session start "$t" -p "$name" </dev/null >/dev/null 2>&1
    sleep 2
    got="$(cat "$tmp/last.out" 2>/dev/null || echo '<none>')"
    if [ "$got" = "$expect" ]; then echo "  ✓ $name -> ${got:-(default; CLAUDE_CONFIG_DIR unset)}"; else echo "  ✗ $name -> got '$got', expected '${expect:-(unset)}'"; fi
    aoe rm "$t" -p "$name" --purge </dev/null >/dev/null 2>&1
  done
  set -e
  rm -rf "$tmp"
fi
