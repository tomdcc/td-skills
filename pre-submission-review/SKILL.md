---
name: pre-submission-review
description: Review a patch or branch the way a senior maintainer would before it is posted to a public list — severity-tagged findings with file:line, a live reproduction for anything major, a long "verified clean" section, and an explicit verdict. Use before submitting a patch series (pgsql-hackers, a PR to an unfamiliar project, an RFC), when asked to review a branch "properly", or when a review needs to be trustworthy rather than quick.
argument-hint: "<branch, commit range, or PR to review>"
---

# Pre-submission review

Produces the kind of review that changes what gets submitted: findings a
maintainer would raise, each one demonstrated rather than asserted, and an
honest account of what was checked and found sound.

This is not a diff-reading pass. A review that lists style nits and misses the
branch that breaks the feature's promise is worse than no review, because it
buys false confidence.

## The method, in order

### 1. Establish what the change promises

Read the commit messages and the documentation the patch adds, and write down —
for yourself — what a user is entitled to expect once this lands. Every good
finding comes from comparing that promise against what the code does. Style
comes last, if at all.

Then find the sibling paths. If a branch carefully preserves an invariant, the
branch beside it that ignores the same invariant is where the bug is. Ask which
code paths reach the same state by a different route, and check each.

### 2. Build it and run it

A review of code you have not executed is a code reading, and should say so.
Build the branch, run its tests, and keep the build for the reproductions.

Beware of green results that prove nothing. Ask what a total no-op would have
looked like; if that is indistinguishable from what you got, find the check that
differs — the test actually registered, the binary actually rebuilt, the suite
actually ran the new file.

### 3. Probe, don't skim

Aim at:

- the interaction points the change creates with existing features (options,
  flags, and modes that can be combined with the new thing — try each);
- concurrency, if the change takes locks: what else locks the same objects, in
  what order, and can they cycle;
- the scope boundaries the feature claims (schema, database, session, tenant):
  what sits just outside, and what happens when it is reached;
- resources the command never touches today but now does — other sessions'
  objects, temporary state, catalogs;
- anything the patch says is impossible. Grep for what would falsify the claim,
  not for what confirms it.

### 4. Demonstrate every major finding

A major finding needs a reproduction run against the real build, pasted into the
review: the setup, the command, the output. Where the effect could have another
cause, add a **differential control** — the same scenario with the offending
condition removed, showing it behaves. A finding without evidence will be argued
with; a finding with a transcript will be fixed.

If a consequence is derived from reading call sites rather than observed, say so
in the finding. Do not promote reasoning to observation.

### 5. Check the claims the patch makes about the codebase

Comments and commit messages assert things: "X only happens at Y", "this avoids
the Z ordering", "nothing else does W". Verify each against source. Negative
claims are where reviews earn their keep, and where authors are most often
wrong. A false justification in a comment is a finding even when the code is
right, because the next person will rely on it.

### 6. Mechanics

Read the project's own contribution and environment notes before starting --
`CLAUDE.md`, `CONTRIBUTING`, `src/tools/*/README`, whatever it keeps. They name
the formatter, the test invocation, the submission ritual, and usually the
traps that make a green run meaningless. Nothing below substitutes for them.

Formatting tools the project mandates, generated files regenerated, tests
registered in the build, naming and numbering collisions with what upstream
added while the branch sat. Run the project's formatter against **unmodified
upstream** first: if upstream is already dirty, a blanket run sweeps unrelated
churn into the patch, and you want to say that rather than do it.

## Output shape

```
# Review: <subject> (<branch or range>)

Target: <base>..<tip> (<n> commits)
Head: <sha>

<the series, one line per commit>

## Findings

- [MAJOR] path/file.c:1234-1250 (`function`) — one-sentence statement of the defect.
  why: the argument, from the surrounding code's own conventions and invariants.
  fix: what to do, concretely.
  evidence: |
    <transcript of a live reproduction, with a differential control where useful>

- [MINOR] ...
- [NIT] ...

## Verified clean / non-findings

<The longest section. Each item: what was checked, how, and why it is sound.
This is what makes the findings believable — a reviewer who only lists problems
has not shown the reader where the boundary of their attention was.>

## Commands run

<Every build, suite and query, so each claim is reproducible.>

### Not done, and not claimed

<Everything that was not run: suites skipped, platforms not covered, results
taken from a subagent and not independently reproduced, consequences derived
from source rather than observed.>

## Submission / Usability / Feature test / Performance / Coding / Architecture

<Short sections, each a judgement rather than a list.>

## Verdict

<accept | changes-requested | reject>. Blockers: <n>.
```

Severity means: **MAJOR** blocks submission; **MINOR** should be fixed but would
not embarrass anyone; **NIT** is taste. If everything is MAJOR, nothing is.

## What makes it trustworthy

- **Roughly two-thirds of the document is "verified clean".** A review that is
  all findings tells the reader nothing about coverage.
- **Every external claim is fetched and read** before it is characterised — the
  cited thread, the referenced commit, the standard. Never describe a source
  from memory.
- **The "not done" list is explicit.** Reviews are used as evidence that
  something was checked; an unstated gap becomes a false claim the moment
  somebody relies on it.
- **Line references are real.** Re-derive them at the end if the branch moved;
  stale `file:line` is the fastest way to lose a reader's trust.

## When reviewing your own work

Say so at the top. Self-review is worth doing — it catches plenty — but the
blind spots that produced the code produce the review, and a reader deserves to
weigh it accordingly. Prefer probing the parts you were least sure of when
writing, and treat "I remember checking that" as unchecked.

## After the review

The findings are findings, not a work order. Do not start fixing unless asked;
report, and let the author decide what is in scope. If a finding is later fixed,
the review is stale — its hashes and line numbers will not survive a rebase, so
say which findings it still describes rather than implying it describes the
current tree.
