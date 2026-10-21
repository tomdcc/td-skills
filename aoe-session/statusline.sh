#!/usr/bin/env bash
# Claude Code status line: account label, cwd, git branch, model, context used.
#
#   <label> ~/code/repo (branch) <model> ctx:42%
#
# Usage (as a settings.json statusLine command):  statusline.sh <label> [<sgr-colour>]
#   <label>       account name shown first, e.g. the aoe profile name
#   <sgr-colour>  ANSI SGR colour code for the label (default 36, cyan)
#
# Installed into each account's settings.json by setup-profiles.sh. Needs jq.
# Reads the status line JSON on stdin.

label="${1:-claude}"
colour="${2:-36}"

input=$(cat)
{
  IFS= read -r cwd
  IFS= read -r model
  IFS= read -r used
} < <(printf '%s' "$input" | jq -r '(.workspace.current_dir // .cwd), .model.display_name, (.context_window.used_percentage // "")')

case "$cwd" in
  "$HOME" | "$HOME"/*) short_cwd="~${cwd#"$HOME"}" ;;
  *) short_cwd="$cwd" ;;
esac

branch=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" -c core.hooksPath=/dev/null symbolic-ref --short HEAD 2>/dev/null ||
    git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
fi

line=$(printf '\033[%sm%s\033[0m \033[94m%s\033[0m' "$colour" "$label" "$short_cwd")
[ -n "$branch" ] && line="$line $(printf '\033[32m(%s)\033[0m' "$branch")"
line="$line $(printf '\033[37m%s\033[0m' "$model")"
[ -n "$used" ] && line="$line $(printf '\033[37mctx:%.0f%%\033[0m' "$used")"
printf '%s' "$line"
