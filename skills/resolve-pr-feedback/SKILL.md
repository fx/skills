---
name: resolve-pr-feedback
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. Coordinates explicitly requested automated PR-feedback resolution for the reviewers it has adapters for — Copilot, CodeRabbit and Codecov; any other configured reviewer is settled by hand by the caller."
---

# Resolve PR Feedback

> **Path note:** `[SKILLS_DIR]` below is the directory holding this skill's own folder —
> the parent of the directory containing this `SKILL.md`. Substitute its absolute path;
> every skill referenced below is installed as a sibling there.

**⛔ Load `fx-review` first** (Skill tool: `skill="fx-review"`). It is the
canonical review procedure. This skill is the **coordinator adapter**: it finds
every unresolved finding on a PR **from the reviewers in § Supported Reviewers**,
triages it, and dispatches the right resolver with the brief and a disposition per
thread. Where the two appear to disagree, `fx-review` wins.

**"Every" is a claim the queries below have to earn, and one page does not earn
it.** `reviewThreads(first: 100)` returns *at most* the first 100 threads, not the
thread list — a PR that has accumulated more (a long review cycle, several
reviewers, a large diff) silently drops the remainder, and every count and verdict
downstream is then computed over a subset while still reading as complete. **Every
thread enumeration in this skill MUST be paginated to exhaustion** — follow
`pageInfo.endCursor` with `after:` until `hasNextPage` is `false`, and triage the
union of the pages (`[SKILLS_DIR]/github/references/graphql-patterns.md`
§ Pagination Pattern). A truncated read is not a smaller finding list; it is an
unknown one.

**That table is the whole of this skill's coverage.** An automated reviewer with
no row in it is never categorised, never dispatched, and never counted in any
verdict below. Its threads still gate the merge, and the caller settles them by
hand (`[SKILLS_DIR]/dev/references/scope-contract.md` § Injecting the brief into
reviews).

You are the coordinator here, so three of its steps are specifically yours:

- **Step 1** — establish the Scope Brief before dispatching anything. From the
  caller, or reconstructed from the conversation and PR description.
- **Steps 2–3** — you hold the brief and the ledger, so **your** triage is the
  authoritative one; a resolver classifying from comment text alone does not have
  what you have. Verify each premise before assigning anything.
- **Step 6** — when resolvers run in parallel, the `REVIEW.md` writes must be
  serialized through you.

## Supported Reviewers

| Reviewer | Author Pattern | Resolver Skill |
|----------|---------------|----------------|
| GitHub Copilot | `copilot-pull-request-reviewer` (GraphQL thread authors) / `copilot-pull-request-reviewer[bot]` (REST) — **never** the bare `Copilot`, which matches nothing | `copilot-feedback-resolver` |
| CodeRabbit | `coderabbitai[bot]` | `rabbit-feedback-resolver` |
| Codecov | `codecov[bot]` / `codecov-commenter` | `resolve-codecov-feedback` — for coverage gaps (§ 3b), its only channel. A review thread from Codecov is settled by hand instead (§ 3): that resolver has no thread-settlement path. |

These three are the roster — there is no fallback row. A reviewer absent from the
table has no author pattern here and no resolver to dispatch to, so this skill
cannot settle it; do not treat the list as illustrative and do not infer a generic
path for a fourth bot.

## WHEN TO USE THIS SKILL

- User says "resolve PR feedback" / "check PR comments" / "address review comments"
- User wants to handle the automated review feedback from the § Supported Reviewers roster on a PR
- After PR creation, to ensure the reviewers in § Supported Reviewers are addressed — any other configured reviewer's threads also gate the merge, but the caller settles those by hand
- As part of the SDLC workflow before finalizing a PR

## Parallel resolvers MUST NOT write `REVIEW.md` concurrently

`fx-review` Step 6 states the rule; this is the coordinator's half of it.
Re-reading before writing is **not** locking — two sub-agents can read the same
revision and the second write silently discards the first's rule.

When dispatching resolvers in parallel (Step 4):

1. Instruct each sub-agent to **collect** its proposed `REVIEW.md` rules and
   return them in its final report **instead of editing the file**. Everything
   else — code fixes, thread replies, thread resolution — proceeds in parallel;
   those touch disjoint resources.
2. After **all** parallel resolvers return, apply the collected rules in a single
   serialized edit, then commit and push.
3. Verify by diffing, not by counting the whole file — an established `REVIEW.md`
   already contains unrelated rules, so a total-count check always fails:

   ```bash
   git diff -- REVIEW.md
   ```

   Every proposed rule must appear as an added line, and pre-existing rules must
   be untouched.

When resolvers run **sequentially** (one reviewer only, or Mode B), each edits
`REVIEW.md` directly as its own skill describes — no aggregation needed.

## Prerequisites

**CRITICAL: Load the `github` skill FIRST** before running any GitHub API operations.

## Core Workflow

### 1. Determine PR Number

If not provided, get from current branch:

```bash
gh pr view --json number -q '.number'
```

### 2. Query All Unresolved Review Threads

**IMPORTANT — this applies to the GraphQL query bodies only:** substitute inline
values, NOT `$variable` syntax. `-f query='...'` is single-quoted so the shell never
expands anything inside it, and `$` is GraphQL's own variable sigil, so a `$name`
there is a GraphQL variable you have not declared rather than a value.

**Plain `gh api` / `gh pr view` snippets are the opposite:** they use real shell
variables (`PR_NUMBER`, `REPO_NWO`, `HEAD_SHA`), assigned at the top of each snippet
so it is copy-pasteable as-is. Never mix the two styles inside one snippet — a bare
`PR_NUMBER` sitting next to a real `${HEAD_SHA}` reads as though it were defined, and
silently builds a request against a repo path containing the literal text.

```bash
# Replace OWNER, REPO, PR_NUMBER with actual values (GraphQL body — no shell expansion here)
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100, after: null) {
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

**This returns one page, not the thread list.** Re-run it with
`after: "<endCursor>"` for as long as `pageInfo.hasNextPage` is `true`, and
categorise the accumulated nodes from **all** pages — the executable loop is
`[SKILLS_DIR]/github/references/graphql-patterns.md` § Pagination Pattern.
Stopping at the first page on a PR with more than 100 threads drops the rest
without any error — the response is well-formed and simply shorter — so the skill
would report a triaged, settled PR while unread findings sit on page 2.

**Fetch `path`, `line`, and `body`, not just the author.** Step 4 requires a
disposition per thread, and a disposition cannot be derived from an ID and a
login: the filters need to see what the thread actually says and where. A query
that returns only `id`/`isResolved`/`author` forces the dispatch step to hand out
dispositions it has not reasoned about, or to omit them — which is the bare
invocation Step 4 forbids.

### 3. Identify Unresolved Feedback by Source

Parse the response and categorize unresolved threads by author:

- **Copilot threads**: author login is `copilot-pull-request-reviewer` (GraphQL). Match with `startswith("copilot-pull-request-reviewer")` so the REST `copilot-pull-request-reviewer[bot]` form matches too.
  - **⛔ It is NOT the bare string `Copilot`.** That value appears only in `requested_reviewers`, which is always empty and which this skill never reads. Matching on `Copilot` categorizes **zero** Copilot threads on every PR — so the resolver is never invoked, real threads are silently left unresolved, and this skill reports "nothing to do" while the merge gate is unsatisfiable.
- **CodeRabbit threads**: author login contains `coderabbitai`
- **Codecov threads**: author login starts with `codecov` — `codecov[bot]` or `codecov-commenter`. Match with `startswith("codecov")`, the same filter Step 5's convergence query uses. **Settle these by hand, yourself** — triage against the brief, reply with the disposition, resolve via `resolveReviewThread` (`github`). Codecov has a § Supported Reviewers row, so a thread of its is *not* one of the uncategorised ones you hand back to the caller (§ Error Handling).
  - **⛔ Do NOT dispatch a Codecov review *thread* to `resolve-codecov-feedback`.** That resolver reads coverage statuses and PR comments and adds coverage; it has no thread-settlement path at all, so a thread handed to it comes back unresolved while Step 5's gate keeps selecting it — the same stall, one step later. Step 4's Codecov dispatch is for coverage gaps (§ 3b) only.
  - **This bullet is the belt, not the primary Codecov path.** § 3b is Codecov's real channel — PR comments and commit statuses, not review threads — and it is why Codecov has a § Supported Reviewers row and a resolver at all; so this bullet usually matches nothing. Keep it anyway: Step 5's gate counts every unresolved `startswith("codecov")` thread, so a Codecov thread left uncategorised here holds the convergence loop open forever. Hand settlement resolves the thread, so the gate clears.

Threads matching none of the three patterns above fall into two kinds, and
neither is yours to resolve: human threads, which `github` forbids you from
touching, and threads from an automated reviewer with no § Supported Reviewers
row. **Report the second kind rather than dropping it** — list the reviewer and
its open threads in your summary as uncategorised, so the caller knows there is
a merge gate left for it to settle by hand. Silently omitting them is what makes
a clean report here read as a clean PR.

**Threads are the review.** Copilot also puts some observations in a `<details><summary>Suppressed comments</summary>` block in the **review body**, where they create no thread at all — those are **ignored by default** (`copilot-review` **D4**): Copilot itself declined to raise them as threads, they are overwhelmingly wording and comment-phrasing nits, and acting on one costs a full re-review cycle. Do not open the block routinely; act only on something absolutely dire that has already caught your eye.

What you do still need from the review body is its **verdict headline**: *Approval recommended* and *Needs a closer look* both pass when no threads are open, while *Changes recommended* means work through its threads. Read the bodies of the Copilot reviews **of the current head commit** — scoping by `commit_id` is required, or after a push you read the PREVIOUS commit's body and record this check as satisfied for code that review never covered:

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')

gh api "/repos/${REPO_NWO}/pulls/${PR_NUMBER}/reviews" \
  --jq "[.[] | select(.user.login | startswith(\"copilot-pull-request-reviewer\")) | select(.commit_id == \"${HEAD_SHA}\") | .body] | join(\"\n\n----- (next review of this commit) -----\n\n\")"
```

Empty output means **no Copilot review covers the current head** — that is an unreviewed head, not a clean one. Note this reads *every* review of that commit, not `| last`: two reviews of one commit are routine, so `last` may show a different review than the one being judged.

`copilot-review`'s waiter does this for you and prints the bodies; prefer it
over this snippet. Its `SUPPRESSED_COMMENTS=1|0|unknown` line is informational and
gates nothing (its **D4**) — do not re-run it to turn `unknown` into a number. If
you run the snippet above by hand, confirm the command succeeded before drawing a
conclusion from silence: empty output from a failed fetch looks exactly like empty
output from a review with an empty body.

If an absolutely-dire suppressed item is acted on, it cannot be resolved (no thread exists), so record the outcome in the commit message or PR body instead.

### 3b. Check for Codecov Coverage Feedback

Codecov's channel is PR comments and commit statuses, NOT review threads — this
is Codecov's normal path, and the only one Step 4's Codecov dispatch serves. The
uncommon case where Codecov does open a review thread is § 3's Codecov bullet,
and that thread is settled by hand there rather than dispatched from here. Query
separately:

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')

# Check for Codecov commit statuses
gh api "/repos/${REPO_NWO}/commits/${HEAD_SHA}/statuses" \
  --jq '[.[] | select(.context | startswith("codecov/"))] | {count: length, statuses: [.[] | {context, state, description}]}'

# Check for Codecov PR comments
gh api "/repos/${REPO_NWO}/issues/${PR_NUMBER}/comments" \
  --jq '[.[] | select(.user.login == "codecov[bot]" or .user.login == "codecov-commenter")] | length'
```

Codecov feedback exists if:
- Any `codecov/*` commit status has state `failure` or `error`
- OR Codecov PR comment indicates patch coverage below threshold

### 4. Invoke Appropriate Resolver Skills

**Triage BEFORE dispatching, and pass the result.** A resolver invoked with a bare
skill name has neither the Scope Brief nor your per-finding dispositions, so it
re-derives both — and a correct-but-immaterial thread comes back as an edit,
which is the push that reopens the loop. Every invocation below MUST carry, as
its argument:
1. The **Scope Brief**, verbatim (`[SKILLS_DIR]/dev/references/scope-contract.md` § The Scope Brief).
2. A **disposition for every thread that carries a finding** — `blocking`,
   `immaterial`, or `deferred`, as defined in
   `[SKILLS_DIR]/dev/references/scope-contract.md` § Resolver dispositions.
   Yours is authoritative: it is set with the Scope Brief and the ledger in hand,
   which the resolver does not have. **Verify the premise before disposing of
   it** — a thread describing code that no longer exists, or misreading a
   deliberate convention, is a false positive rather than a finding. List it as
   undisposed with the reason, and let the resolver's outdated/incorrect handler
   take it; forcing a disposition onto one overrides that handler and loses the
   `REVIEW.md` entry that stops the finding recurring.

**If Copilot threads exist:**
```
Skill tool: skill="copilot-feedback-resolver",
            args="<Scope Brief verbatim> — dispositions: <thread id> blocking, <thread id> immaterial, <thread id> deferred (<exclusion>) — false premise (resolver's own handler): <thread id> (<what does not hold>)"
```

**If CodeRabbit threads exist:**
```
Skill tool: skill="rabbit-feedback-resolver",
            args="<Scope Brief verbatim> — dispositions: <thread id> blocking, <thread id> immaterial, <thread id> deferred (<exclusion>) — false premise (resolver's own handler): <thread id> (<what does not hold>)"
```

**If Codecov coverage gaps are detected (§ 3b):**
```
Skill tool: skill="resolve-codecov-feedback",
            args="<Scope Brief verbatim> — uncovered lines in scope: <paths>; deliberately uncovered: <paths and why>"
```

**No bare invocation.** A `Skill tool:` line with no `args` is an incomplete call
here, not a shorthand — the resolver then re-derives triage it cannot see and
edits for findings you classified immaterial or deferred.

**List false positives separately, not as a disposition.** Append
`— false premise (resolver's own handler): <thread id> (<what does not hold>)`
for any thread you verified and rejected. That leaves the resolver's
outdated/incorrect path — reply, resolve, and update `REVIEW.md` where a
convention was misread — reachable, which an authoritative disposition would
close off.

**If multiple exist:** run the Copilot and CodeRabbit resolvers **in parallel** by spawning each as a sub-agent in the same message (see `dev` Step 6.3 for the exact pattern) — but only where at most one of them carries `blocking` dispositions. Codecov is sequential after them since coverage fixes typically require code from the other resolvers to be in place first.

**Where two or more channels carry blocking findings, fix them once, together, before dispatching any resolver** (`[SKILLS_DIR]/dev/references/head-discipline.md` § Batch findings). Two resolvers editing the same branch in parallel also race on the working tree, which is the local reason the rule is not optional here. Hand the whole blocking set to one fix agent, push once, then invoke each resolver with its blocking threads annotated `already fixed in <sha>` (`[SKILLS_DIR]/dev/references/scope-contract.md` § Resolver dispositions), leaving each to do only what it alone can do.

### 5. Verify Categorised Reviewers Resolved AND Loop Until Convergence

After invoking resolver skills, re-query to confirm every thread from a § Supported Reviewers reviewer is resolved AND that none of them has posted new feedback in response to the fixes that were pushed.

**Cycle, don't single-shot.** CodeRabbit re-runs after every push and may post new threads on the new commits. Copilot does **not** — it must be asked again. Either way, a single-pass resolver leaves a stale "settled" state behind. Loop:

1. **If the current head SHA has no Copilot review yet — because a fix was pushed, or because none has covered this head at all — nudge Copilot for it** via `copilot-review` (its Step 1). **Copilot does NOT re-review pushed commits on its own.** Where the last cycle only replied and resolved, the head has not moved and a review of it already exists: skip straight to step 3. Nudging and waiting there buys a full cycle to re-read code nobody changed, which is the same churn as editing for an immaterial finding. Skipping this makes the rest of the loop meaningless: you will poll, see nothing, and "converge" on code no reviewer has read. Issue the nudge and discard its response — it is fire-and-forget, never evidence, and having issued it is never a substitute for step 6's received-review check.
2. Wait for all reviewer checks to reach terminal state (use the dedicated waiters: `copilot-review` for Copilot, `coderabbit-review` for CodeRabbit). **Do not hand-roll a `gh api` / GraphQL polling loop in their place** — a hand-rolled loop only observes, never requests, and will happily accept a review of a superseded commit.
3. Re-run **Step 2's full query** — `id`, `path`, `line` and comment bodies — and re-triage every unresolved thread, including the ones the last cycle's push created. The breakdown query below counts threads by reviewer; it cannot feed step 4, which refuses a resolver invocation without a disposition per thread, and a disposition cannot be assigned to a name and a number. Every iteration repeats the fetch and the triage, not just the first.
4. If the breakdown array is non-empty, re-invoke the relevant resolver(s) with the dispositions from step 3.
5. **If fixes were pushed**, restart at step 1 — the push created unreviewed commits. If this cycle produced no push, do not restart: go to step 6 and judge convergence on the review already delivered for this head.
6. Stop when the loop has **converged** per `fx-review` Step 7 — no blocking
   finding left unresolved, ledger-wide — **and** two PR-level conditions hold
   that the ledger test alone does not cover:
   - the state holds on a head SHA that was **actually reviewed** (verify: the
     newest Copilot review's `commit_id` equals `headRefOid`);
   - **every thread on that head from a reviewer this skill categorised is resolved** — say which reviewers that covered, since a bot with no adapter is outside this query and is the caller's to settle.

   A suppressed-comments block is **not** a third condition and never extends this
   loop (`copilot-review` **D4**), and neither does a *Needs a closer look*
   verdict with no open threads.

   Immaterial findings resolved by reply satisfy all of this: they produce no
   push, so they are not "new feedback" owing another cycle. The bound and the
   escalation triggers are `fx-review` Step 7 and are not restated here.

**⛔ Zero new threads is not convergence unless a Copilot review has been RECEIVED for the current head SHA.** "Received for the current head" is the *only* condition — do **not** phrase it as "was requested", and do not try to verify that a request happened: `requested_reviewers` is empirically always empty, so whether a review was requested is not a determinable fact (see `copilot-review` **D1**/**D3**). Issue the nudge because it sometimes helps, then judge convergence solely on the delivered review. Absence of feedback is not evidence of quality.

Verify before declaring the loop converged:

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')
REVIEWED=$(gh api "/repos/${REPO_NWO}/pulls/${PR_NUMBER}/reviews" \
  --jq '[.[] | select(.user.login | startswith("copilot-pull-request-reviewer")) | .commit_id] | last // empty')
[[ -n "$REVIEWED" && "$REVIEWED" == "$HEAD_SHA" ]] \
  && echo "covered: $HEAD_SHA" \
  || echo "NOT covered — head=$HEAD_SHA reviewed=${REVIEWED:-none}"
```

The `// empty` is load-bearing: without it, a PR with no Copilot reviews prints the literal string `null`, which then gets compared against a SHA under a "these MUST match" instruction — an unreviewed head presented as a concrete-looking value instead of an obvious absence.

Re-query remaining unresolved threads **from the § Supported Reviewers roster
only** — the filter below selects those three by login, not every automated
reviewer. The query returns a per-reviewer breakdown array, not a single number.
This skill resolves the automated feedback it has adapters for, and `github`
forbids touching human review threads at all, so an unfiltered query makes one
open human comment permanently unsatisfiable and loops this skill against work it
must not do:

**Say what this verdict covers when you report it.** The roster is whatever the
query below selects by author login — the § Supported Reviewers table's three,
Copilot, CodeRabbit and Codecov — so a clean result here means *those* reviewers
are settled. It is not evidence about a further automated reviewer a repo has
configured, whose threads this skill never categorised and never resolved. Those
still gate the merge, and the caller settles them by hand
(`[SKILLS_DIR]/dev/references/scope-contract.md`
§ Injecting the brief into reviews). Reporting a bare "0 unresolved" hands the
caller a merge gate it has not actually verified.

```bash
# Replace OWNER, REPO, PR_NUMBER with actual values (GraphQL body — no shell expansion here)
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100, after: null) {
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

**That returns one page — page it to exhaustion before reading the gate off it**
(`[SKILLS_DIR]/github/references/graphql-patterns.md` § Pagination Pattern, which
carries the executable loop). Keep requesting `after: "<endCursor>"` while
`pageInfo.hasNextPage` is `true` and concatenate the `nodes` arrays. Nothing
reduces that call, deliberately: the `jq` below would consume the response the
cursor lives in, and this query is the merge gate — the one place a false zero
converts straight into "settled". **Accumulate, then filter, then count**, over
the whole set:

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

That reports a per-reviewer breakdown, so "unresolved threads remain" comes with the
reviewer name attached. An empty array over the **fully paginated** set means **the
reviewers this skill categorised by login** have no open feedback — not that the PR
has none. Human threads it excluded are deliberately not your concern; an
uncategorised bot's threads are the caller's, per the caveat above.

If unresolved threads remain, report which reviewers still have open feedback.

## Output Format

```
## PR #123 Feedback Summary

### Detection
- Copilot: 2 unresolved threads found
- CodeRabbit: 3 unresolved threads found
- Codecov: patch coverage 65% (below threshold)
- Uncategorised automated reviewers: <name>: <n> unresolved — no adapter here (or "none seen")

### Resolution
- Invoked copilot-feedback-resolver
- Invoked rabbit-feedback-resolver
- Invoked resolve-codecov-feedback

### Final Status
- All Copilot, CodeRabbit and Codecov threads resolved (no other reviewer categorised)
- Coverage improved to 85%
- Left for the caller: <uncategorised reviewer>: <n> threads still gating the merge (settle by hand)
```

Keep the last two lines even when there is nothing to report — write "none seen"
and "nothing left for the caller". Dropping the line makes its absence
indistinguishable from a run that never looked, which is the state the caller
would read as full coverage.

## Success Criteria

1. All unresolved threads **from the reviewers this skill categorises** identified — matched on the `copilot-pull-request-reviewer` login, **not** the bare `Copilot`. Name that roster — the § Supported Reviewers table's three — when reporting the verdict; a reviewer with no adapter is outside it and is settled by the caller. Suppressed comments are **not** part of this: they open no thread and are ignored by default (`copilot-review` **D4**)
2. Appropriate resolver skill(s) invoked (Copilot + CodeRabbit in parallel where applicable)
3. The wait-and-resolve loop has CONVERGED — a Copilot review has been **RECEIVED for the current head SHA**, left **no blocking finding unresolved** (including any carried from an earlier pass), and every thread on that head from a reviewer this skill categorised is resolved. Immaterial findings resolved by reply do not block this. Do not add "and was requested", which is not a determinable fact (**D1**). A quiet poll on an unreviewed head is not convergence
4. CodeRabbit's check is in a terminal passing state (or absent if not configured)
5. Final verification confirms every categorised reviewer's threads resolved, and says which reviewers that covered
6. Summary output provided

## Error Handling

- If no PR found: Ask user for PR number
- If resolver skill fails: Report which reviewer's feedback remains unresolved
- If API errors: Retry with proper auth context
- If a thread comes from an automated reviewer with no § Supported Reviewers row: this is not an error to work around and not a reason to improvise a resolver. Report the reviewer and its open threads as uncategorised and hand them back to the caller, which settles them by hand (`[SKILLS_DIR]/dev/references/scope-contract.md` § Injecting the brief into reviews). Never report the PR as settled on their behalf
