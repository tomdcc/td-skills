---
name: new-issue-worktree
description: Create a new worktree for a GitHub issue. Use when the user specifies an issue number and wants a worktree created for it without starting a Claude session.
---

# New Issue Worktree

Create a worktree for a GitHub issue. The args are the issue number (e.g. `/new-issue-worktree 42`).

## Steps

1. **Update the base branch** — from the main checkout, pull the latest:
   ```
   git pull --ff-only
   ```
   If the pull fails (e.g. diverged), stop and report the problem rather than proceeding.

2. **Fetch issue details** using `gh issue view <number> --json number,title` to get the title.

3. **Derive a branch name**: pick 3–4 meaningful keywords from the title (skip common words like "switch", "from", "to", "the", "a", "and", file names like `cart_load.c`), join with hyphens, lowercase, then prefix with the issue number: `<number>-<keyword>-<keyword>...`. Aim for something a human would choose — short, readable, descriptive of the core change. Example: issue "cart_load.c: switch ELF section check from allowlist to denylist" → `71-elf-section-denylist`.

3. **Create the worktree** from the current repo root:
   ```
   wtp add -b <branch-name> --quiet
   ```
   Capture the output — it is the worktree path.

4. **Report back** with:
   - The issue title and number
   - The branch name
   - The worktree path
