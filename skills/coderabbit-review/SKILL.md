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
§ Long waits), redirecting stdout and stderr to a log file and reading that file on
the wake. On Claude Code that is `run_in_background: true` plus its completion
notification:
```bash
mkdir -p [AGENT_DIR]/team/waits && \
bash [SKILLS_DIR]/coderabbit-review/scripts/wait-for-coderabbit-review.sh <PR_NUMBER> \
  > [AGENT_DIR]/team/waits/rabbit-<PR_NUMBER>.log 2>&1
```

**Do NOT run it in a call that cannot outlive it.** On Claude Code the Bash tool
caps a foreground `timeout` at 600 000 ms, below the script's 900 s budget — such
a call is killed mid-poll, printing no STATUS and no exit code, which is exactly
what used to force blind re-runs; backgrounded processes are not subject to that
cap. Never launch it *without* the redirect: the cycle is driven by what the
script prints.

### Read the `STATUS=` line

The script's last stdout line is `STATUS=<state>`; the exit code mirrors it. Branch
on STATUS, not on prose.

| STATUS | Exit | What to do |
|---|---|---|
| `TERMINAL_PASS` | 0 | Check settled clean, zero unresolved threads → the gate is met. Go to Step 1b only if you still need to read findings. |
| `TERMINAL_FAIL` | 1 | Settled with a failing conclusion, or unresolved threads remain → **Step 1b**. Do not re-run for a better answer. |
| `PENDING` | 2 | Still running at budget expiry. **Not a verdict, not a failure.** Re-running is safe and correct if you still need it. Never record it as "no findings". |
| `NOT_CONFIGURED` | 3 | The App is not installed for this repo. **Terminal — report once and proceed without the PR-level gate. Never retry, never wait.** A coordinator running several PRs also caches it per `[SKILLS_DIR]/dev/references/head-discipline.md` § Reviewer availability is cached for the run, rather than re-establishing it on each PR. |
| `ERROR` | 4 | Bad args or `gh` failure; the wait never started → report. If it identifies a rate/quota limit, take the exception above. |

`UNRESOLVED_THREADS=unknown` means the read **failed**, not that there are none;
the script fails closed on it. Verify the threads yourself before any merge gate.

## Step 1b: Fetch the threads and triage them

**The waiter emits a count, not the threads**, and Step 2 hands the resolver a
disposition per thread — a count cannot be triaged. Fetch the bodies, then run
`fx-review` Steps 2–3 over them.

```bash
# Replace OWNER, REPO, PR_NUMBER with actual values (GraphQL body — no shell expansion here)
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100) {
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
}' --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false and (.comments.nodes[0].author.login | tostring | contains("coderabbitai")))]'
```

Assign one of `blocking`, `immaterial`, or `deferred` to each thread **that
carries a finding**. Yours is authoritative — you hold the Scope Brief; the
resolver does not. A thread whose premise fails gets **no** disposition; list it
with the reason so the resolver's outdated/incorrect handler takes it
(`fx-review` Step 3).

## Step 2: Hand it to the resolver

```
Skill tool: skill="rabbit-feedback-resolver",
            args="<PR_NUMBER> — <Scope Brief verbatim> — dispositions: <thread id> blocking, <thread id> immaterial, <thread id> deferred (<exclusion>) — false premise (resolver's own handler): <thread id> (<what does not hold>)"
```

**Both suffixes are mandatory.** Invoking the resolver with only a PR number makes
it re-derive triage it cannot see, and it will edit for threads you classified
immaterial or deferred. The false-premise suffix is what routes a thread Step 1b
rejected to the outdated/incorrect path instead of a re-triage that loses the
`REVIEW.md` entry.

## Step 3: Loop until settled

CodeRabbit re-reviews after every push, so once Step 2 pushes fixes the check goes
pending again — go back to Step 1. Per `fx-review` Step 7, repeat Steps
1 → 1b → 2 until **all three** hold:

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
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: <PR_NUMBER>) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(first: 1) { nodes { author { login } } }
        }
      }
    }
  }
}' --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false and (.comments.nodes[0].author.login | tostring | contains("coderabbitai")))] | length'
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
