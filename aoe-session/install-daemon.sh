#!/usr/bin/env bash
# Install (or refresh) the launchd LaunchAgent that keeps the Agent of Empires
# `aoe serve` daemon running at login and restarts it on crash.
#
# Portable across macOS machines: all machine-specific paths (Homebrew prefix,
# the real `claude` binary dir, $HOME) are resolved at runtime, so the same
# script works on Apple Silicon or Intel and for any user. Idempotent — re-run
# it any time to regenerate and reload.
#
# Usage:  ./install-daemon.sh            # install + load, port 8080
#         AOE_SERVE_PORT=9000 ./install-daemon.sh
#         ./install-daemon.sh --uninstall
#
# Per-account PROFILES are a separate, account-specific step — see the
# aoe-session skill (SKILL.md) "One-time setup" section. This script only
# manages the autostart daemon.
set -euo pipefail

LABEL="com.tomdunstan.aoe-serve"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Removed $LABEL and $PLIST"
  exit 0
fi

# --- preconditions -----------------------------------------------------------
command -v aoe  >/dev/null || { echo "ERROR: aoe not found. Install with: brew install aoe"  >&2; exit 1; }
command -v tmux >/dev/null || { echo "ERROR: tmux not found. Install with: brew install tmux" >&2; exit 1; }
AOE_BIN="$(command -v aoe)"

# Real claude bin dir — NEVER a cmux/temp shim (those are ephemeral per-session).
if [ -x "$HOME/.local/bin/claude" ]; then
  CLAUDE_DIR="$HOME/.local/bin"
else
  c="$(command -v claude 2>/dev/null || true)"
  case "$c" in
    ""|*cmux-cli-shims*|*/T/*) CLAUDE_DIR="$HOME/.local/bin" ;;  # fall back to the canonical install dir
    *) CLAUDE_DIR="$(cd "$(dirname "$c")" && pwd)" ;;
  esac
fi
[ -x "$CLAUDE_DIR/claude" ] || echo "WARNING: no claude at $CLAUDE_DIR/claude — sessions may not find it." >&2

BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
PATH_ENV="$CLAUDE_DIR:$BREW_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin"
PORT="${AOE_SERVE_PORT:-8080}"

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

# --- generate the plist ------------------------------------------------------
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <!-- Foreground \`aoe serve\` (NOT --daemon) so launchd owns the process and
         KeepAlive can supervise it. Foreground mode registers with
         \`aoe url\` / \`aoe serve --status\` / \`aoe add\` exactly like --daemon. -->
    <key>ProgramArguments</key>
    <array>
        <string>$AOE_BIN</string>
        <string>serve</string>
        <string>--port</string>
        <string>$PORT</string>
        <string>--host</string>
        <string>127.0.0.1</string>
    </array>

    <!-- Clean, explicit env. Every aoe session inherits the daemon's
         environment, so this PATH must resolve claude/aoe/tmux and must NOT
         carry any cmux shim PATH or NODE_OPTIONS pollution. -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$PATH_ENV</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <!-- Restart on crash / abnormal exit, but let a deliberate
         \`aoe serve --stop\` (clean exit 0) stay down instead of fighting it. -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>ProcessType</key>
    <string>Background</string>

    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/aoe-serve.out.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/aoe-serve.err.log</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST" >/dev/null

# --- (re)load ----------------------------------------------------------------
# bootout is asynchronous; bootstrapping before the label fully releases fails
# with "Input/output error 5". Poll until the service is gone, then bootstrap.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
for _ in $(seq 1 25); do
  launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break
  sleep 0.2
done
launchctl bootstrap "$DOMAIN" "$PLIST"
sleep 3

echo "Installed $LABEL"
echo "  aoe:    $AOE_BIN"
echo "  PATH:   $PATH_ENV"
echo "  plist:  $PLIST"
aoe serve --status 2>&1 | sed 's/^/  /' || {
  echo "  daemon did not report running — check $HOME/Library/Logs/aoe-serve.err.log" >&2
  exit 1
}
