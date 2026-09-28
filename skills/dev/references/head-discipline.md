# Head Discipline

Canonical rules for **when to push**, **what a review or CI result is evidence of**, and **what order to wait in**.

**These rules are defined here and referenced elsewhere, never restated** (`AGENTS.md` § Writing style; `scope-contract.md` § Blocking states the same principle for its own rules — a copied rule drifts, and the stale copy is reliably the narrower one). A skill applying one of them at its point of use writes the imperative it needs and names the section: *"launch the CI waiter last (§ Waiter scheduling order)"*, not a paraphrase of why. If a skill needs different behaviour, change it here, for everyone.

One failure motivates all of it: **every push invalidates the head-scoped evidence gathered before it.** A workflow that pushes between collecting evidence and using it pays for the same wait twice. Observed on a 19-hour `team` run: roughly 70% of wall clock spent waiting on CI, most of it on runs a later push had already superseded.

## The candidate head

The **candidate head** is the commit you intend to merge. Everything that can still change the tree happens *before* it exists; everything expensive and head-scoped happens *after*.

Per PR, in this order:

1. Implement.
2. Run every **local** check and reviewer available — tests and `codex-review`, the only local reviewer.
3. Batch every local finding, classify, and fix in **one** pass (§ Batch findings — one fix pass per push).
4. Run the verification that does not need a PR to exist — browser and programmatic test-plan items.
5. Confirm everything else that would otherwise force a later commit **is already committed** — task-tracking docs, change-doc and index status flips, generated files, recorded test-plan results. These ride with the implementation in step 1, not in a finalizing commit of their own; this step is the check that none is outstanding, and finding one here means step 1 missed it.
6. Push. **Record that SHA as the candidate head.**
7. Open or update the PR, set its metadata, then start the hosted reviewers.
8. Batch every hosted blocking finding into **one** fix push. That push creates a new candidate head — return to step 7 for the delta only.
9. Once hosted review has converged, wait for CI on the current candidate head.
10. Verify the merge gates against that same SHA, then merge.

**Every push after step 6 re-enters at step 7, whatever produced it.** A hosted-review fix, a CI-remediation fix, a late verification fix, a missing tracking commit — each creates a new candidate head, and the steps after 7 are the ones whose evidence it just invalidated. Re-entering means re-covering a material delta with the reviewers that do not re-review a push on their own — a non-material one carries their earlier review (§ Carried review coverage) — then reaching CI and the gates on the new SHA. Skipping back in — jumping from a CI fix straight to another CI wait, say — ships a commit no reviewer has read, and finalization then discovers a reviewed SHA that is not the head.

**Nothing between step 9 and the merge may push.** A gate that needs a commit is a defect in an earlier step — fix it there. If one slips through anyway, it is a push like any other: re-enter at step 7 rather than merging on evidence collected for its parent.

CI normally starts by itself the moment you push, and that is fine — it may well be green by the time you reach step 9. The rule is not "stop CI from running", it is **do not spend a coordinator turn, or a concurrency slot, watching a run you are about to invalidate**.

## Evidence is SHA-scoped

**Every review result and every CI result is evidence about exactly one commit.** Record the SHA next to every result in the ledger; a result with no SHA is not evidence.

When the head changes:

- Outstanding CI waits for the previous SHA are **superseded**. Do not keep waiting on them, do not read their eventual verdict as merge evidence, and do not treat their failure as this head's failure. Where the waiter is a child process or teammate, stop it and reclaim the slot.
- Review results for the previous SHA remain valid **for the code that did not change**; re-review the delta only. That is the existing bounded-delta rule, unchanged.
- Re-launch the waiters whose evidence the delta invalidated, and only those. A head change is never by itself a reason to restart every reviewer — but a **material** delta is always a reason to re-cover the code that changed, so a reviewer that does not re-review a push on its own (Copilot) must be relaunched explicitly for one, or the new commits ship unreviewed by it. A non-material delta invalidates nothing (§ Carried review coverage).

**A verdict whose SHA you cannot confirm is not a pass.** The CI waiter prints `PR_HEAD_SHA=` beside its verdict for exactly this comparison, and `PR_HEAD_SHA=unknown` when it could not read it; the Copilot waiter prints `REVIEWED_COMMIT_ID=` and `PR_HEAD_SHA=`, which must be equal — unless the review is carried (§ Carried review coverage).

This section scopes CI evidence strictly: a CI result never carries to another SHA. Review evidence carries under the one rule below.

## Carried review coverage

**A settled hosted review of an earlier SHA of the same PR covers the current head when the delta between them is not material** — by `dev` Step 6.1's material-change test, the only definition: a head that moved without changing what the reviewed code does. Do not relaunch that reviewer's waiter, and do not wait for it. Record `<reviewer>: carried from <reviewed-sha> to <head-sha> — <what the delta was>` in the ledger; that entry is the reviewer's coverage for the merge gates.

"Settled" means every thread that review opened is settled and its verdict does not ask for changes beyond those threads. Typical non-material deltas:

- a rebase or base merge that leaves the PR's own diff unchanged, or changes it only in tracking/change docs;
- a one-line correction — including one that applies the reviewer's *own* finding from the review being carried;
- a commit touching only task-tracking docs, change-doc status, or PR-irrelevant generated files.

Compare the PR's diff at each SHA, not the two commits — after a rebase, `git diff <reviewed> <head>` also contains every commit the base gained:

```bash
BASE_REF=$(gh pr view <PR_NUMBER> --json baseRefName --jq '.baseRefName')   # not always main
git fetch -q origin "$BASE_REF" <reviewed-sha> <head-sha>   # a pre-force-push SHA may not be local
BASE="origin/$BASE_REF"
git range-diff "$(git merge-base "$BASE" <reviewed-sha>)..<reviewed-sha>" \
               "$(git merge-base "$BASE" <head-sha>)..<head-sha>"
```

Anything that changes behaviour, touches a file the reviewed diff did not, or fixes a finding with more than a local correction is material: relaunch. When unsure, it is material.

**Why this exists.** A review that recommended approval, followed by a rebase and a one-character help-text fix for that review's own nit, was treated as zero coverage. The run then waited seven hours for a re-review of code Copilot had already passed — see § A review that does not arrive for the other half of that failure. A delta nobody would re-review by hand is not worth a reviewer cycle either.

This does not relax the merge gates' size rule: a PR that no reviewer has ever covered is unreviewed however small it is. Carrying requires a settled review **of this PR**, and it covers only the delta the test calls non-material.

## A review that does not arrive

**A hosted review that has not arrived after 30 minutes of waiting on the same head is abandoned.** That is at most two 900 s waiter runs: relaunch a `PENDING` waiter once, and on a second `PENDING` stop. Record `<reviewer>: abandoned on <sha> — no review after 30 min` in the ledger, report it once, and proceed. The abandonment satisfies that reviewer's slot in the merge gates; everything it already delivered on this PR is still settled — the thread gate is unaffected.

Where a carried review exists (§ Carried review coverage), there is nothing to wait for in the first place. Abandonment is for the case where waiting was genuinely owed.

**Never provoke a review.** Do not push a commit to retrigger a reviewer, close and reopen the PR, remove and re-add the reviewer, or try further request APIs beyond the waiter's own nudge. Each is outward-facing noise on the PR; a push also invalidates every head-scoped result gathered so far; and in the run that motivated this rule, every one of them was tried and none produced a review.

**Do not keep retrying on a timer.** A silence backstop or scheduled wakeup must not relaunch an abandoned waiter. The motivating run relaunched hourly for six hours while three PRs sat unmerged.

**Once a reviewer has been abandoned twice in a run with no review from it anywhere in between, treat it as unavailable for the rest of the run** — skip its waiter on later PRs and report once, as § Reviewer availability is cached for the run does for `NOT_CONFIGURED`. An outage or exhausted quota is repository-wide, and paying 30 minutes per PR to rediscover it is the same waste in smaller pieces. Resume waiting if it posts a review anywhere in the run.

## Batch findings — one fix pass per push

**Collect → classify → deduplicate → fix once → push once.**

Never run `finding → fix → push`, then `next finding → fix → push`. Each push restarts CI and every push-triggered reviewer, so serializing N findings buys N convergence cycles for work that fits in one.

Before spawning a fix agent, drain everything already on the table: local reviewer output, every hosted reviewer that has reported, browser and test-plan verification results, and CI failures already known for this head. Classify all of it in the ledger, deduplicate by fingerprint, sweep each finding's class (`scope-contract.md` § Fix the class, not the instance), then hand the whole blocking set to **one** fix agent.

**Do not hold the batch open for a channel that has not reported.** Batching means "take everything currently available", not "wait for everyone". A reviewer that reports after the fix push is simply the next batch, against the new head.

## Waiter scheduling order

Where a wait costs a concurrency slot (waiter children on Codex) or a coordinator wake, order the launches by what actually unblocks work:

0. **Never start a hosted reviewer on a head you already know must change.** A blocking finding you are holding — from a local pass, an integration check, a failed verification — is a diff that will not survive, and every reviewer launched against it spends a full cycle reviewing it anyway. Fix and push first; that costs only the push it already needed. This orders *against* the rest of the list rather than within it: waiting is cheap to start and expensive to waste.
1. **Hosted reviewer waiters first.** Their findings change the tree, so their results decide whether the current head survives at all.
2. **Keep at least one slot for coding or fix work** while they run. A coordinator whose every slot holds a waiter cannot advance anything.
3. **Launch the CI waiter last** — only once the current head carries no unresolved blocking review finding, or when there is genuinely nothing else to advance. Watching CI on a head a pending review is about to invalidate is a wait you pay for twice.

This is an ordering rule, not a prohibition. CI runs from the moment of the push either way, and where waits are free background jobs an early CI waiter costs a wasted wake rather than a lost slot — order them anyway, because the wake is not free either.

## Reviewer availability is cached for the run

A reviewer's configuration is a property of the **repository**, not of the PR. The first `STATUS=NOT_CONFIGURED` for a reviewer settles it for every remaining PR in the run: record it in the ledger and skip that reviewer's waiter from then on, without launching the script again.

Re-establishing the same absence once per PR costs a process launch, the discovery grace period, and a coordinator wake, every time, for a fact that cannot have changed in between. Re-check only if the configuration visibly changes — the App is installed mid-run, or the reviewer posts on a PR regardless.

This caching applies to `NOT_CONFIGURED`, and to a reviewer abandoned twice (§ A review that does not arrive). `PENDING`, `TERMINAL_PASS`, `TERMINAL_FAIL`, and `ERROR` are per-PR, per-SHA facts and are never carried across PRs.
