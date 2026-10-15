---
name: coderabbit-review
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. Handles CodeRabbit's PR-level review as an optional review adapter with Scope Brief triage and rate-limit degradation."
---

# CodeRabbit Review

> **Path note:** `[SKILLS_DIR]` below is the directory holding this skill's own folder —
> the parent of the directory containing this `SKILL.md`. Substitute its absolute path;
> every skill referenced below is installed as a sibling there.
>
> `[AGENT_DIR]` is your host's in-repo agent directory — `.claude` on Claude Code,
> `.agents` on Codex (`[SKILLS_DIR]/dev/references/host-adapters.md` § `[AGENT_DIR]`).
> Substitute it; never write a literal `.claude/` path on another host.

**⛔ Load `fx-review` first** (Skill tool: `skill="fx-review"`). It is the
canonical review procedure — carrying the Scope Brief, triaging in filter order,
sweeping a class, converging, reporting. This skill is the **CodeRabbit adapter**:
the GitHub App's check and threads, and the rate-limit exception. Where the two
appear to disagree, `fx-review` wins.

**CodeRabbit is PR-level only, and optional.** It applies when the repo's CodeRabbit
GitHub App auto-reviews pull requests, which exposes a `CodeRabbit` check. Most
repos do not have it installed; that is a normal, expected outcome and never a
reason to wait or retry.

> **There is no local CodeRabbit mode.** The `cr` CLI is no longer used anywhere in
> this SDLC catalog. **Codex is the only local pre-PR reviewer** — see
> `codex-review` and `dev` Step 4.5. Do not reintroduce a `cr` call,
> and do not treat a missing local CodeRabbit pass as a gap.

## Arguments

`args='<PR_NUMBER> — <Scope Brief verbatim>'`.

## How the brief reaches CodeRabbit — it does not

**The GitHub App cannot be addressed**, so the brief is applied **entirely at
triage** (`fx-review` Steps 1–2). Judge a run on triage coverage, not on how few
out-of-scope findings it produced — that signal does not exist for a reviewer that
never saw the brief (`fx-review` Step 8).

CodeRabbit's `🟠 Major` / `🟡 Minor` / `🧹 Nitpick` labels are an **input** to
triage, never a verdict.

## ⛔ CodeRabbit is optional when rate-limited

If the API, GitHub check, or wait script reports a CodeRabbit quota/rate limit:
report it once and continue without CodeRabbit. Do not sleep, poll, retry after a
cooldown, ask the user to wait, or block PR creation/merge on CodeRabbit throttling
alone. Do not consume convergence iterations waiting for a cooldown.

**Throttling waives only the review passes that never ran — never anything
already delivered.** Before recording the skip:

- fix every blocking finding CodeRabbit already returned, and
- settle *every* thread it already posted — immaterial and deferred ones included —
  by replying and resolving.

Skipping that leaves an open conversation behind a gate that requires zero
unresolved CodeRabbit threads, so the "degraded" PR is still blocked.

Only then mark the pass `skipped (rate-limited)`. This exception applies to
CodeRabbit alone; it does not relax Copilot, CI, tests, or other merge gates.

---

## Facts

- CodeRabbit's PR review is **completely independent of CI**. CI passing has
  nothing to do with CodeRabbit.
- CodeRabbit **re-reviews on every push** that changes the head SHA — unlike
  Copilot, it needs no nudge. After you push, the check goes pending again.
- **NEVER use raw `gh api repos/.../reviews` or `gh pr view --json reviews` to
  make merge decisions about CodeRabbit.** Use this skill's bundled script.

## Step 1: Wait for the check

CodeRabbit auto-runs — there is **no review-request step**.

**⛔ Run the waiter as a long wait** (`[SKILLS_DIR]/dev/references/host-adapters.md`
§ Long waits) under the discipline in
`[SKILLS_DIR]/dev/references/background-waits.md`, redirecting stdout and stderr to
a log file and reading that file on the wake. On Claude Code that is
`run_in_background: true` plus its completion notification:
```bash
mkdir -p [AGENT_DIR]/team/waits && \
bash [SKILLS_DIR]/coderabbit-review/scripts/wait-for-coderabbit-review.sh <PR_NUMBER> \
  > [AGENT_DIR]/team/waits/rabbit-<PR_NUMBER>.log 2>&1
```

### Read the `STATUS=` line

The script's last stdout line is `STATUS=<state>`; the exit code mirrors it. Branch
on STATUS, not on prose.

| STATUS | Exit | What to do |
|---|---|---|
| `TERMINAL_PASS` | 0 | Check settled clean, zero unresolved threads → the gate is met. Go to Step 1b only if you still need to read findings. |
| `TERMINAL_FAIL` | 1 | Settled with a failing conclusion, or unresolved threads remain → **Step 1b**; where Step 1b finds no unresolved CodeRabbit thread, **Step 1c**. Do not re-run for a better answer. |
| `PENDING` | 2 | Still running at budget expiry. **Not a verdict, not a failure.** Re-running once is safe and correct if you still need it; `PENDING` again on that re-run is a hand-back: "CodeRabbit check still pending on head `<sha>`." Never record it as "no findings". |
| `NOT_CONFIGURED` | 3 | The App is not installed for this repo. **Terminal — report once and proceed without the PR-level gate. Never retry, never wait.** A CodeRabbit thread already on the PR — from before the App was removed — is still settled: Step 1b, then Step 2 (`resolve-pr-feedback`, `sources: coderabbit`, which reports it `not configured` with the threads settled). A coordinator running several PRs also caches it per `[SKILLS_DIR]/dev/references/head-discipline.md` § Reviewer availability is cached for the run, rather than re-establishing it on each PR. |
| `ERROR` | 4 | Bad args or `gh` failure; the wait never started → report — a hand-back to the user, never Step 1b. If it identifies a rate/quota limit, take the exception above. |

`UNRESOLVED_THREADS=unknown` means the read **failed**, not that there are none;
the script fails closed on it. Verify the threads yourself with Step 1b's query
before any merge gate; if that read fails too, after one retry, hand back "CodeRabbit
threads unreadable on head `<sha>`" — never a zero, never another wait.

## Step 1b: Fetch the threads and triage them

**The waiter emits a count, not the threads**, and Step 2 hands `resolve-pr-feedback`
a disposition per thread — a count cannot be triaged. Fetch the bodies, then run
`fx-review` Steps 2–3 over them.

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
          comments(first: 10) { nodes { author { login } body } }
        }
      }
    }
  }
}'
```

**`--paginate --slurp` is what reads that to exhaustion — run it under the
fail-closed checks before triaging off it**
(`[SKILLS_DIR]/github/references/graphql-patterns.md` § Pagination Pattern, which
carries the executable version). `gh` walks the cursor and returns an array of
pages; flatten `nodes` across them into one array. There is no `--jq` on that call
because `gh` rejects it under `--slurp`, and a filter reducing the response to an
array of matches would discard the `pageInfo` `--paginate` pages from.
**Accumulate, then filter** — once, over the whole set:

```bash
jq '[.[] | select(.isResolved == false
       and (.comments.nodes[0].author.login | IN("coderabbitai", "coderabbitai[bot]")))]' \
  <<< "$ALL_THREADS"
```

A thread stranded past the first page is never triaged and never given a
disposition, so it neither reaches `resolve-pr-feedback` nor shows up in Step 3's count —
the gate reads as met while the finding sits unread.

Assign one of `blocking`, `immaterial`, or `deferred` to each thread **that
carries a finding**. Yours is authoritative — you hold the Scope Brief;
`resolve-pr-feedback` does not. A thread whose premise fails gets **no**
disposition; list it with the reason so its outdated/incorrect handling takes it
(`fx-review` Step 3).

## Step 1c: A failing check with no open thread

`TERMINAL_FAIL` with zero unresolved CodeRabbit threads has nothing for Step 1b to
triage, and Step 3's condition 1 can never hold on it by waiting: without this step
the loop repeats the same failure. CodeRabbit puts some of its feedback in places
that open no thread — the review body's "Actionable comments posted" and
"Outside diff range" sections — says why a check failed in its own output, and
posts its rate-limit notice as a PR comment. Read all three, for the current head
only:

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')
set -o pipefail   # a failed gh read must fail the pipeline, never print an empty "none found"

# The check's own explanation — a check run's output, or a commit status's description
gh api --paginate --slurp "/repos/${REPO_NWO}/commits/${HEAD_SHA}/check-runs" \
  | jq '[.[].check_runs[] | select(.name == "CodeRabbit") | {conclusion, title: .output.title, summary: .output.summary}]' \
  || echo "READ FAILED: check runs — not evidence"
gh api "/repos/${REPO_NWO}/commits/${HEAD_SHA}/status" \
  --jq '[.statuses[] | select(.context == "CodeRabbit") | {state, description}]' \
  || echo "READ FAILED: commit status — not evidence"

# CodeRabbit's review bodies for this head
gh api --paginate --slurp "/repos/${REPO_NWO}/pulls/${PR_NUMBER}/reviews" \
  | jq -r --arg head "$HEAD_SHA" '[.[][] | select(.user.login | IN("coderabbitai", "coderabbitai[bot]")) | select(.commit_id == $head) | .body] | join("\n\n----- (next review of this commit) -----\n\n")' \
  || echo "READ FAILED: reviews — not evidence"

# CodeRabbit's PR comments, edited in place: keep those updated at or after the head commit
if HEAD_DATE=$(gh api "/repos/${REPO_NWO}/commits/${HEAD_SHA}" --jq '.commit.committer.date'); then
  gh api --paginate --slurp "/repos/${REPO_NWO}/issues/${PR_NUMBER}/comments" \
    | jq --arg since "$HEAD_DATE" '[.[][] | select(.user.login | IN("coderabbitai", "coderabbitai[bot]")) | select(.updated_at >= $since) | {updated_at, body}]' \
    || echo "READ FAILED: issue comments — not evidence"
else
  echo "READ FAILED: head commit date — not evidence"
fi
```

A `READ FAILED` line is not "nothing actionable": retry once, then hand back the
failed read — never the no-actionable-feedback hand-back.

Then exactly one of:

- **A rate or quota limit** in the check output, the status description or a
  CodeRabbit comment → § CodeRabbit is optional when rate-limited.
- **Actionable items in a review body** → each is a finding. Triage it like a
  thread (`fx-review` Steps 2–3), blocking ones into the batched fix like any other.
  There is no thread to reply to or resolve, so record each item's disposition in
  the report — and, for a fixed one, the commit. After a push CodeRabbit re-reviews:
  back to Step 1. **If none of them is blocking, nothing is pushed and the check
  stays failed: hand back** "CodeRabbit check failed on `<sha>`; its review-body
  findings were triaged non-blocking: <items and dispositions>".
- **Nothing actionable** → hand back: "CodeRabbit check failed on `<sha>` with no
  actionable feedback: <check summary or status description>".

A hand-back ends Step 3's loop. It is not settlement: the caller's merge gate stays
unmet until the user decides.

## Step 2: Settle the threads through `resolve-pr-feedback`

```
Skill tool: skill="resolve-pr-feedback",
            args="<PR_NUMBER> — <Scope Brief verbatim> — sources: coderabbit — dispositions: <thread id> blocking (already fixed in <sha>), <thread id> immaterial, <thread id> deferred (<exclusion>) — false premise: <thread id> (<what does not hold>)"
```

**`sources: coderabbit` keeps it to CodeRabbit's threads, and it runs one round
and returns — no wait, no re-request** (its § One round). Step 3 below is the
loop, and the wait its report names after a push is this skill's Step 1.

**Both suffixes are mandatory.** Invoked with only a PR number it re-derives
triage it cannot see and treats threads you classified immaterial or deferred as
work. The false-premise suffix routes a thread Step 1b rejected to its
outdated/incorrect handling instead of a re-triage that loses the `fx-review`
Step 6 entry.

**Where a coordinator is running several channels, the blocking fixes are batched
and pushed before this call** (`[SKILLS_DIR]/dev/references/head-discipline.md`
§ Batch findings), so `blocking` dispositions arrive annotated
`already fixed in <sha>` (`[SKILLS_DIR]/dev/references/scope-contract.md`
§ Resolver dispositions). Under a coordinator `resolve-pr-feedback` edits nothing
(its Step 3): an un-fixed `blocking` disposition comes back to you unfixed — one
more round trip, not a fix.

## Step 3: Loop until settled

CodeRabbit re-reviews after every push, so once a fix is pushed the check goes
pending again — go back to Step 1. Per `fx-review` Step 7, repeat Steps
1 → 1b (→ 1c) → 2 until **all three** hold, or a step hands back — Step 1's
`PENDING`-again or unreadable-threads case, or Step 1c:

1. The most-recent `CodeRabbit` check is terminal with conclusion `success` (or
   `skipped` / `neutral` if the repo configures it that way).
2. Zero unresolved CodeRabbit threads.
3. **No blocking finding is left unresolved, across every pass** — the ledger test
   (`[SKILLS_DIR]/dev/references/scope-contract.md` § Convergence). Conditions 1
   and 2 describe the latest check; this one describes the ledger. A blocker an
   earlier pass raised and this one did not still blocks, and resolving its thread
   does not discharge it: a thread is closed by a reply, a blocker only by a fix.

`STATUS=TERMINAL_PASS` asserts conditions 1 and 2 together. The third is yours to
track, and it is the one a passing check cannot stand in for.

```bash
# $endCursor is declared and left unbound on purpose: --paginate supplies it.
gh api graphql --paginate --slurp -f query='
query($endCursor: String) {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: <PR_NUMBER>) {
      reviewThreads(first: 100, after: $endCursor) {
        totalCount
        pageInfo { hasNextPage endCursor }
        nodes {
          isResolved
          comments(first: 1) { nodes { author { login } } }
        }
      }
    }
  }
}'
```

**Run it under the fail-closed checks before reading condition 2 off it**, the same
mechanism Step 1b uses
(`[SKILLS_DIR]/github/references/graphql-patterns.md` § Pagination Pattern). `gh`
walks the cursor; flatten `nodes` across the slurped pages. Keep the call free of a
reducing `--jq` — `gh` rejects it under `--slurp`, and it would otherwise strip the
`pageInfo` `--paginate` pages from. **Accumulate, then filter, then count** — a
per-page `length` under-reports exactly as a per-page `group_by` would:

```bash
jq '[.[] | select(.isResolved == false
       and (.comments.nodes[0].author.login | IN("coderabbitai", "coderabbitai[bot]")))]
    | length' <<< "$ALL_THREADS"
```

## Concurrency with other reviewers

This skill runs **in parallel** with `copilot-review`. That parallelism needs no
mode selection: launch each reviewer's waiter in the shape your host's row
prescribes (`[SKILLS_DIR]/dev/references/host-adapters.md` § Long waits), then
handle whichever wake arrives first.

The SDLC step gating merge on automated review should wait for every configured
reviewer to settle — terminal, zero unresolved threads, **and no blocking finding
left unresolved**, for each — and loop the whole group: any reviewer that re-runs
after a push re-triggers its waiter → resolver → possibly more commits → the other
reviewers' waiters.

## Success criteria

All three of Step 3's conditions — the check terminal with a passing conclusion,
zero unresolved CodeRabbit threads, **and no blocking finding left unresolved across
every pass**. The third is not implied by the first two: a thread is closed by a
reply, a blocker only by a fix, so a passing check over a resolved-but-unfixed
blocker is not settlement.

Or CodeRabbit rate-limited, **every thread it had already delivered is settled**,
and the gate recorded `skipped (rate-limited)`. Throttling alone never blocks merge.

Or `STATUS=NOT_CONFIGURED` — the App is not installed for this repo. Report once and
proceed; there is no PR-level CodeRabbit gate to satisfy.

A hand-back (Step 1, Step 1c) is **not** success: it ends the loop with its reason
reported, and the gate stays unmet for the user to decide.
