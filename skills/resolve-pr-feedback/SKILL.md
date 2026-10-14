---
name: resolve-pr-feedback
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. Settles automated PR feedback — Copilot, CodeRabbit and Codecov findings and failing CI checks — loading per-source instructions only for the sources present on the PR; any other configured reviewer is settled by hand by the caller."
---

# Resolve PR Feedback

> **Path note:** `[SKILLS_DIR]` below is the directory holding this skill's own folder —
> the parent of the directory containing this `SKILL.md`. Substitute its absolute path;
> every skill referenced below is installed as a sibling there.

**⛔ Load `fx-review` first** (Skill tool: `skill="fx-review"`). It is the
canonical review procedure. This skill is the **PR-feedback adapter**: it detects
which feedback sources are present on the PR's head, loads
`references/<source>.md` for each one present, triages every finding, settles
every thread, and — when no caller owns the loop — converges. `fx-review` owns
the procedure; each reference holds only its source's mechanics (`fx-review`
§ What a platform skill adds). Where they disagree, `fx-review` wins.

**"Every" is a claim the queries below have to earn, and one page does not earn
it.** `reviewThreads(first: 100)` returns *at most* the first 100 threads, not the
thread list — a PR that has accumulated more (a long review cycle, several
reviewers, a large diff) silently drops the remainder, and every count and verdict
downstream is then computed over a subset while still reading as complete. **Every
thread enumeration in this skill MUST be paginated to exhaustion** — run it under
`gh api graphql --paginate --slurp` and triage the union of the pages
(`[SKILLS_DIR]/github/references/graphql-patterns.md` § Pagination Pattern, which
carries the mechanism and the checks that make it fail closed). A truncated read is
not a smaller finding list; it is an unknown one.

**§ Supported Reviewers is the whole of this skill's reviewer coverage.** An
automated reviewer with no row in it is never categorised, never settled, and
never counted in any verdict below. Its threads still gate the merge, and the
caller settles them by hand (`[SKILLS_DIR]/dev/references/scope-contract.md`
§ Injecting the brief into reviews).

## Invocation Boundary

Use this skill only when the user names it, or an active explicitly invoked
workflow calls it by name: `copilot-review` Step 3 (`sources: copilot`),
`coderabbit-review` Step 2 (`sources: coderabbit`), `dev` Step 6.3 (each
reviewer's own source) and Step 7.2 (`sources: ci,codecov`, the lifecycle's only
Codecov pass). A mention of PR comments,
review threads, coverage or failing checks does not load it.

## Arguments

```
Skill tool: skill="resolve-pr-feedback",
            args="<PR_NUMBER> — <Scope Brief verbatim> — sources: <copilot|coderabbit|codecov|ci, comma-separated; omitted = all> — dispositions: <id> blocking (already fixed in <sha>) | immaterial | deferred (<exclusion>) — false premise: <id> (<what does not hold>)"
```

- **The Scope Brief is mandatory.** Run standalone without one, reconstruct it
  from the conversation and the PR description, and say that you did
  (`fx-review` Step 1).
- **`sources:` given → settle those sources on the current head and return; the
  convergence loop is the caller's** (`copilot-review` Steps 4–5,
  `coderabbit-review` Step 3, `dev` Steps 6.3 and 7). A scoped call from
  `copilot-review` used to fall into this skill's own loop, which nudged Copilot
  and re-invoked the adapter that had called it. **Omitted** → Steps 1–5,
  convergence included.
- **Dispositions are authoritative** (`[SKILLS_DIR]/dev/references/scope-contract.md`
  § Resolver dispositions). The caller set them with the Scope Brief and the
  ledger in hand; a classification from comment text alone does not override
  them.
- **False-premise threads are listed separately, not as a disposition.** A thread
  the caller verified and rejected goes in `— false premise: <id> (<what does not
  hold>)`. That keeps the outdated/incorrect handling reachable — reply, resolve,
  and the `fx-review` Step 6 entry where a convention was misread — which an
  authoritative disposition would close off.
- **No bare invocation.** A call with only a PR number is incomplete, not a
  shorthand: the skill then re-derives triage it cannot see and treats findings
  the caller classified immaterial or deferred as work.

## Supported Reviewers

| Reviewer | Author pattern | Reference |
|---|---|---|
| GitHub Copilot | `copilot-pull-request-reviewer` (GraphQL thread authors) / `copilot-pull-request-reviewer[bot]` (REST) — **never** the bare `Copilot`, which matches nothing | `references/copilot.md` |
| CodeRabbit | `coderabbitai[bot]` | `references/coderabbit.md` |
| Codecov | `codecov[bot]` / `codecov-commenter` | `references/codecov.md` |

These three are the roster — there is no fallback row. A reviewer absent from the
table has no author pattern here and no reference to load, so this skill cannot
settle it; do not treat the list as illustrative and do not infer a generic path
for a fourth bot.

### CI source

CI is not a reviewer and posts no threads. `references/ci.md` covers failing
checks on the head. It does not widen the roster: a bot that posts threads is
either in the table above or uncategorised.

## Step 1: Detect, then load

Read `HEAD_SHA` once, at the start; every read below is keyed to it, so a push
mid-run cannot mix two heads' evidence.

**(a) Threads.** Fetch every review thread, paginated:

```bash
# Replace OWNER, REPO, PR_NUMBER with actual values (GraphQL body — no shell expansion here)
# $endCursor is declared and left unbound on purpose: --paginate supplies it.
gh api graphql --paginate --slurp -f query='
query($endCursor: String) {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100, after: $endCursor) {
        totalCount
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          path
          line
          comments(first: 10) {
            nodes {
              author { login }
              body
            }
          }
        }
      }
    }
  }
}'
```

**`$` inside a GraphQL body turns on one thing: does the query signature declare
it.** An undeclared `$name` is an undefined GraphQL variable — the single-quoted
body is never shell-expanded, so the server rejects it; substitute such values
inline (that is what `OWNER` / `REPO` / `PR_NUMBER` are for). A declared one is
correct: `--paginate` binds `$endCursor` itself, so it deliberately has no `-f`
flag. Plain `gh api` / `gh pr view` snippets are the opposite — `$` is the
shell's again, so they assign real shell variables (`PR_NUMBER`, `REPO_NWO`,
`HEAD_SHA`) at the top. Never mix the two styles in one snippet.

**`--paginate --slurp` is what makes that the thread list rather than one page.**
Flatten `nodes` across the slurped pages and categorise the accumulated set under
the fail-closed checks in `[SKILLS_DIR]/github/references/graphql-patterns.md`
§ Pagination Pattern. Reading only the first page drops the rest without any
error — the response is well-formed and simply shorter. **Fetch `path`, `line` and
`body`, not just the author:** a disposition cannot be derived from an ID and a
login.

Categorise each unresolved thread by its first comment's author:
`startswith("copilot-pull-request-reviewer")` → copilot,
`contains("coderabbitai")` → coderabbit, `startswith("codecov")` → codecov.
Anything else is one of two kinds, and neither is yours to settle: a human thread,
which `github` § PR Comments Prohibition forbids you to touch, or a thread from an
automated reviewer with no § Supported Reviewers row. **Report the second kind
rather than dropping it** — list the reviewer and its open threads as
uncategorised, so the caller knows a merge gate is left for it to settle by hand.
Silently omitting them is what makes a clean report here read as a clean PR.

**(b) Reviews, checks, statuses and comments on the head:**

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')

gh api --paginate --slurp "/repos/${REPO_NWO}/pulls/${PR_NUMBER}/reviews"           # copilot, coderabbit reviews
gh api --paginate --slurp "/repos/${REPO_NWO}/commits/${HEAD_SHA}/check-runs"       # CodeRabbit check, ci
gh api "/repos/${REPO_NWO}/commits/${HEAD_SHA}/status"                              # codecov/*, CodeRabbit, ci (combined status)
gh api --paginate --slurp "/repos/${REPO_NWO}/issues/${PR_NUMBER}/comments"         # codecov, coderabbit comments
gh pr view "$PR_NUMBER" --json mergeable,mergeStateStatus                           # ci: base-branch conflict
```

| Source | Present when |
|---|---|
| copilot | It has any review or any thread on the PR |
| coderabbit | A check run or status named `CodeRabbit` exists on `HEAD_SHA` in any state, `coderabbitai[bot]` posted a review or comment on the PR, or it has a thread |
| codecov | A status context on `HEAD_SHA` starts `codecov/`, `codecov[bot]` or `codecov-commenter` commented, or it has a thread |
| ci | A check run on `HEAD_SHA` concluded `failure`, `cancelled`, `timed_out` or `action_required`, or a status is `failure` / `error` — **excluding `codecov/*` and the `CodeRabbit` check**, which their own references own; or the head has no checks at all and `mergeable` is `CONFLICTING` |

**Presence is any signal the source emits, never threads alone.** A source that
reports through a check, a status or a comment is present before it posts a
thread, and often without ever posting one: a pending or failed `CodeRabbit`
check, or a rate-limit comment, with no threads is CodeRabbit present and
unsettled. Detecting it by threads alone reports it absent, skips its reference
and its `## Converged` condition, and lets the run report settled over a review
that never finished.

**A failing check excluded from `ci` is its owner's, and is reported against that
owner even when the owner is not in `sources:`** — a failing `CodeRabbit` check
under `sources: ci,codecov` is reported as CodeRabbit's, not dropped. Excluding it
from CI without naming it leaves a failed run with no failure anyone owns, which
the caller then reads as flaky or infrastructure.

**Load `references/<source>.md` for each source that is present and in `sources:`
scope — and only those.** An unscoped run also loads `references/copilot.md` when
Copilot is absent, for its convergence condition: Copilot review is mandatory
(`copilot-review`), and a head it has not reviewed is unreviewed, not settled.

Report every source as `present`, `absent` or `not requested`. **Absent is not a
clean result**: it means nothing from that source on this head, never that it is
settled.

## Step 2: Triage

**Triage before acting.** Every finding-bearing item in scope needs the Scope
Brief and a disposition — `blocking`, `immaterial` or `deferred`
(`[SKILLS_DIR]/dev/references/scope-contract.md` § Resolver dispositions). The
caller's is authoritative; assign your own, per `fx-review` Steps 2–3, only to
what the caller left undisposed. **Verify the premise before disposing of
anything**: a finding describing code that no longer exists, or misreading a
deliberate convention, is a false positive, not a finding — it takes the
false-premise path (Step 4), never a disposition.

**A thread with no disposition and no stated reason is untriaged, not rejected:
run the filters over it, premise check included.** Reading a bare omission as a
rejection closes a real blocker with a reply and no fix.

CI failures and coverage gaps are findings too. Each becomes a ledger entry,
classified and judged blocking by the same rules
(`[SKILLS_DIR]/dev/references/scope-contract.md` § Blocking). The per-source
indicators — Copilot's `[nitpick]`, CodeRabbit's severity labels, the CI
categories, the Codecov threshold — live in the loaded references.

## Step 3: Fix once

**Coordinator-owned** — a lifecycle coordinator (`dev`, `team`) is running this
PR, directly or through the adapter that called you. **Make no edit, no commit
and no push.**

- Blocking thread dispositions arrive `already fixed in <sha>`: verify the fix is
  on the branch and cite it (`[SKILLS_DIR]/dev/references/scope-contract.md`
  § Resolver dispositions).
- For ci and codecov, **return** the diagnosed blocking set in the loaded
  reference's hand-off format; the caller folds it into its one batched fix
  (`dev` Step 6.2) and one push.
- A `blocking` disposition that arrives un-fixed goes back to the caller unfixed,
  with that note.
- A review-rule entry `fx-review` Step 6 requires goes back as exact rule text for
  that batched fix, unless the caller says it already landed.

**Standalone** — no lifecycle coordinator: the user invoked this skill, or
`copilot-review` / `coderabbit-review`, directly. Spawn **one** implementer — a
sub-agent that loads `dev` in its Implementer role — with the Scope Brief and the
whole blocking set across every source, review-rule entries included. It pushes
once, at the end (`[SKILLS_DIR]/dev/references/head-discipline.md` § Batch
findings). Then run Step 4 with those threads annotated `already fixed in <sha>`.

**When unsure which applies, coordinator-owned wins.** Returning costs a round
trip; a second fix path races the coordinator's on the same branch and buys a
review and CI cycle per push.

## Step 4: Settle the threads

For every unresolved thread in scope, reply with its disposition and resolve it
with `github`'s reply and resolve mutations (`github` § Resolve Copilot Review
Threads; `[SKILLS_DIR]/github/references/graphql-patterns.md` § Review Thread
Management), following `fx-review` Step 5. Codecov threads take the same path.

- **False premise** — reply with the evidence and resolve, plus the `fx-review`
  Step 6 entry where a deliberate convention was misread.
- **Deferred** — return the follow-up to the caller, never a tracker commit on
  this PR (`fx-review` Step 5).
- **Review-rule entries** (`fx-review` Step 6) are landed by the caller's batched
  fix when coordinator-owned, or by the standalone implementer.

Re-query and confirm `isResolved` for every thread you settled. Code changed but a
thread left open is unfinished work.

## Step 5: Converge (unscoped invocation only)

With `sources:` given, return after Step 4; the caller loops.

Unscoped, loop:

1. **If a fix was pushed, the new head has to be re-covered** — the push created
   unreviewed commits, and every reference's evidence is keyed to the old SHA.
   Copilot does not re-review on its own (`references/copilot.md` § Converged).
   A cycle that only replied and resolved did not move the head, and a review of
   it already exists: skip the wait and go to step 3.
2. Wait on the new head with the dedicated waiters — `copilot-review` for
   Copilot, `coderabbit-review` for CodeRabbit, and, **when `ci` or `codecov` is
   loaded**, `dev`'s CI waiter:

   ```bash
   bash [SKILLS_DIR]/dev/scripts/wait-for-ci-checks.sh <PR_NUMBER> > <log> 2>&1
   ```

   Run it as a long wait (`[SKILLS_DIR]/dev/references/background-waits.md`;
   `[SKILLS_DIR]/dev/references/host-adapters.md` § Long waits for the shape) and
   read it the way `dev` Step 7.1 does: act only where `PR_HEAD_SHA=` equals the
   new head, and only on `TERMINAL_PASS` / `TERMINAL_FAIL`. Codecov reports after
   the CI run that uploads coverage, so its evidence is read after that terminal
   verdict, never before. **Never hand-roll a polling loop in their place:** it
   only observes, never requests, and accepts a result for a superseded commit.
3. Re-run Step 1 in full on the new head — threads, reviews, checks, statuses and
   comments — and re-triage every unresolved thread, including the ones the last
   push created. The breakdown query below counts threads by reviewer; it cannot
   feed Step 2, which needs a disposition per thread.
4. **A reference loaded on an earlier cycle stays loaded until its `## Converged`
   condition holds.** Detection reads a moment: a CI fix's new head has no failed
   check until CI finishes, and a source that has not reported yet reads absent.
   Dropping the reference there drops the only condition that would have caught
   the fix not working.
5. Stop when `fx-review` Step 7's ledger test holds **and** every loaded
   reference's `## Converged` condition holds on a head that was actually
   reviewed — each on the evidence step 2's waiter produced for that head.
   Otherwise go back through § Step 2 to § Step 4.

**⛔ Zero new threads is not convergence unless a Copilot review has been RECEIVED
for the current head SHA** (`references/copilot.md` § Converged).

**Say what this verdict covers when you report it.** The roster is whatever the
query below selects by author login — the § Supported Reviewers table's three —
so a clean result means *those* reviewers are settled. It is not evidence about a
further automated reviewer a repo has configured, whose threads this skill never
categorised. Those still gate the merge, and the caller settles them by hand
(`[SKILLS_DIR]/dev/references/scope-contract.md` § Injecting the brief into
reviews). Reporting a bare "0 unresolved" hands the caller a merge gate it has not
actually verified.

```bash
# Replace OWNER, REPO, PR_NUMBER with actual values (GraphQL body — no shell expansion here)
# $endCursor is declared and left unbound on purpose: --paginate supplies it.
gh api graphql --paginate --slurp -f query='
query($endCursor: String) {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100, after: $endCursor) {
        totalCount
        pageInfo { hasNextPage endCursor }
        nodes {
          isResolved
          comments(first: 1) {
            nodes {
              author { login }
            }
          }
        }
      }
    }
  }
}'
```

**Run it under the fail-closed checks before reading the gate off it**
(`[SKILLS_DIR]/github/references/graphql-patterns.md` § Pagination Pattern, which
carries the executable version). `gh` walks the cursor; flatten `nodes` across the
slurped pages into one array. Nothing reduces that call, deliberately: `gh` rejects
`--jq` under `--slurp`, and the `jq` below would consume the `pageInfo` the cursor
lives in — and this query is the merge gate, the one place a false zero converts
straight into "settled". **Accumulate, then filter, then count**, over the whole
set:

```bash
jq '[.[] | select(.isResolved == false) | .comments.nodes[0].author.login]
    | group_by(.) | map({reviewer: .[0], unresolved: length})
    | map(select(.reviewer
          | startswith("copilot-pull-request-reviewer")
            or contains("coderabbitai")
            or startswith("codecov")))' <<< "$ALL_THREADS"
```

Run that once, never per page: a per-page `group_by` splits one reviewer's threads
across pages and reports each slice as that reviewer's total, and an empty array
from a single page is exactly what a truncated read looks like.

The filter is the § Supported Reviewers table — human threads, which `github`
forbids you to touch, are excluded so one open human comment cannot make the gate
permanently unsatisfiable. An empty array over the **fully paginated** set means
the reviewers this skill categorised have no open feedback — not that the PR has
none. If threads remain, report which reviewers still have open feedback.

## Output Format

```
## PR #123 Feedback Summary — head <sha>

### Detection
- copilot: present (2 unresolved threads) | absent | not requested
- coderabbit: present (check <state>, 3 unresolved threads) | absent | not requested
- codecov: present (patch 65%, threshold 80% from codecov.yml) | absent | not requested
- ci: present (2 failed checks) | absent | not requested
- Failing checks owned by another source: <check> → <source> (<present | not requested>) | none
- Uncategorised automated reviewers: <name>: <n> unresolved — no reference here (or "none seen")

### Loaded references
- references/copilot.md, references/ci.md

### Resolution
- Threads settled: <n> (<count per disposition>)
- Returned to the caller for its batched fix: <blocking set | none>
- Reported, not fixed: <flaky / infrastructure / untestable | none>
- Proposed review rules: <rule text | none>

### Final Status
- Settled sources: <list> (no other reviewer categorised)
- Left for the caller: <uncategorised reviewer>: <n> threads still gating the merge (settle by hand)
```

Keep the last two lines even when there is nothing to report — write "none seen"
and "nothing left for the caller". Dropping the line makes its absence
indistinguishable from a run that never looked, which is the state the caller
would read as full coverage.

## Success Criteria

1. Every in-scope source detected and reported `present`, `absent` or `not
   requested`; only present sources' references loaded (plus Copilot's for an
   unscoped run's convergence).
2. Every in-scope thread from a categorised reviewer triaged, replied to and
   resolved — Copilot matched on `copilot-pull-request-reviewer`, never the bare
   `Copilot`. Suppressed comments open no thread and are not part of this
   (`copilot-review` **D4**).
3. Coordinator-owned: nothing edited, committed or pushed here; the blocking set
   returned. Standalone: one implementer, one push.
4. Unscoped: converged per Step 5, on a head that was actually reviewed.
5. The report names which reviewers the verdict covers.

## Error Handling

- If no PR found: ask the user for the PR number.
- If a fix or settle step fails: report which source's feedback remains open.
- If API errors: retry with proper auth context.
- If a thread comes from an automated reviewer with no § Supported Reviewers row:
  this is not an error to work around and not a reason to improvise a reference.
  Report the reviewer and its open threads as uncategorised and hand them back to
  the caller, which settles them by hand
  (`[SKILLS_DIR]/dev/references/scope-contract.md` § Injecting the brief into
  reviews). Never report the PR as settled on their behalf.
