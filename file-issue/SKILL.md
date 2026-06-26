---
name: file-issue
description: File a GitHub issue from a description arising in the current session. Searches for duplicates first, reports overlaps before filing, and ensures the issue has enough context for cold-session pickup. Use when the user wants to capture a bug, gap, or improvement discovered during a session.
argument-hint: "<description of the issue>"
---

# File Issue

File a GitHub issue from a description in the current session. The arg is a description of the issue (a sentence or paragraph). If no arg is given, ask the user to describe it.

## Steps

1. **Understand the issue**: from the description and current conversation context, extract:
   - The core problem or request — what is wrong or missing
   - The affected component(s) and any relevant file paths or module names
   - Key technical terms and concepts
   - Any constraints, discoveries, or non-obvious context that only exists in this session (not yet in the codebase or docs)

2. **Search for duplicates**: run 2–3 targeted searches with different keyword angles (component name, symptom, affected feature) across both open and recently closed issues and open PRs:
   ```
   gh issue list --search "<keywords>" --state all --limit 20 --json number,title,state,url
   gh pr list --search "<keywords>" --state open --limit 10 --json number,title,url
   ```
   Cast a wide net — err on the side of more results rather than fewer.

3. **Assess overlaps**:
   - If any result looks like a significant duplicate or materially the same scope, **stop and report** them — titles, numbers, URLs — and ask the user whether to proceed, link to an existing issue instead, or abandon.
   - If results are minor or tangential, note them briefly and continue.

4. **Gather supporting links**: before drafting, look for materials to link:
   - ADRs in `docs/adr/` (or wherever the repo keeps them) relevant to the affected area
   - Design or spec docs referenced in the conversation or discoverable from related issues
   - Relevant recent PRs or commits that provide background context

5. **Draft the issue** using this structure:

   **Title**: ≤70 characters, names the problem not the solution.

   **Body**:
   ```
   ## Problem

   <What is wrong or missing. Concrete and observable. Avoid implementation details.>

   ## Context

   <Why it matters, where it was discovered, any constraints or non-obvious background
   a cold session would need. Include session-specific discoveries not yet in the codebase.>

   ## Related

   <Linked issues, PRs, ADRs, design docs, or code locations. Full GitHub URLs for issues/PRs.>

   ## Acceptance Criteria

   <Bulleted list of what "done" looks like — concrete enough that a cold agent knows when to stop.>
   ```

6. **Confirm before filing**: show the title and body and ask the user to approve before creating anything. This is an external action — do not skip this step.

7. **File the issue**:
   ```
   gh issue create --title "<title>" --body "<body>"
   ```
   Apply labels only if obvious ones exist (`gh label list`) and clearly fit — do not guess.

8. **Report back** with the issue URL.
