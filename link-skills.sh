#!/usr/bin/env bash
# Symlink every skill in this repo into each Claude account's skills dir, so a
# `git pull` (or a local edit) is live in the next session with no reinstall.
#
# Claude Code only discovers skills one level deep (<config-dir>/skills/<name>/
# SKILL.md), so each skill dir is linked individually rather than the whole repo.
# Each account reads its own config dir, so every account is linked.
#
# Idempotent — re-run after adding or removing a skill. Links to skills that no
# longer exist in the repo are pruned. A real file or dir (or a link pointing
# outside this repo) with a skill's name is never replaced; it is reported.
#
# Usage:  ./link-skills.sh [config-dir...]              # link (default: all accounts)
#         ./link-skills.sh --uninstall [config-dir...]  # remove this repo's links
#
# Default accounts: ~/.claude (Claude's default config) plus every ~/.claude-*
# dir holding a .claude.json (an alternate CLAUDE_CONFIG_DIR, e.g. ~/.claude-personal).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

uninstall=0
if [ "${1:-}" = "--uninstall" ]; then
  uninstall=1
  shift
fi

if [ $# -gt 0 ]; then
  CONFIG_DIRS=("$@")
else
  CONFIG_DIRS=("$HOME/.claude")
  for d in "$HOME"/.claude-*/; do
    [ -f "$d.claude.json" ] && CONFIG_DIRS+=("${d%/}")
  done
fi

# Is $1 a symlink whose target is inside this repo?
links_into_repo() {
  [ -L "$1" ] && case "$(readlink "$1")" in "$REPO"/*) true ;; *) false ;; esac
}

for cfg in "${CONFIG_DIRS[@]}"; do
  if [ ! -d "$cfg" ]; then
    echo "$cfg: skipped, does not exist" >&2
    continue
  fi
  skills="$cfg/skills"
  echo "$skills"
  mkdir -p "$skills"

  # Prune (or, with --uninstall, remove all) links into this repo.
  for link in "$skills"/*; do
    links_into_repo "$link" || continue
    if [ "$uninstall" = 1 ] || [ ! -f "$(readlink "$link")/SKILL.md" ]; then
      rm "$link"
      echo "  removed  $(basename "$link")"
    fi
  done
  [ "$uninstall" = 1 ] && continue

  for skill_md in "$REPO"/*/SKILL.md; do
    src="$(dirname "$skill_md")"
    name="$(basename "$src")"
    dest="$skills/$name"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
      echo "  ok       $name"
    elif [ -e "$dest" ] || [ -L "$dest" ]; then
      echo "  CONFLICT $name: $dest already exists and is not a link to $src — left alone" >&2
    else
      ln -s "$src" "$dest"
      echo "  linked   $name"
    fi
  done
done
