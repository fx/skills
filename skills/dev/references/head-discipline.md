# Head Discipline

Canonical rules for **when to push**, **what a review or CI result is evidence of**, and **what order to wait in**.

**These rules are defined here and referenced elsewhere, never restated** (`AGENTS.md` § Writing style; `scope-contract.md` § Blocking states the same principle for its own rules — a copied rule drifts, and the stale copy is reliably the narrower one). A skill applying one of them at its point of use writes the imperative it needs and names the section: *"launch the CI waiter last (§ Waiter scheduling order)"*, not a paraphrase of why. If a skill needs different behaviour, change it here, for everyone.

One failure motivates all of it: **every push invalidates the head-scoped evidence gathered before it.** A workflow that pushes between collecting evidence and using it pays for the same wait twice. Observed on a 19-hour `team` run: roughly 70% of wall clock spent waiting on CI, most of it on runs a later push had already superseded.

## The candidate head

The **candidate head** is the commit you intend to merge. Everything that can still change the tree happens *before* it exists; everything expensive and head-scoped happens *after*.

Per PR, in this order:

1. Implement.
2. Run every **local** check and reviewer available — tests, `/simplify`, `/code-review`, `codex-review`.
3. Batch every local finding, classify, and fix in **one** pass (§ Batch findings — one fix pass per push).
4. Run the verification that does not need a PR to exist — browser and programmatic test-plan items.
5. Finalize everything else that would otherwise force a later commit: task-tracking docs, change-doc and index status flips, generated files, recorded test-plan results.
6. Push. **Record that SHA as the candidate head.**
7. Open or update the PR, set its metadata, then start the hosted reviewers.
8. Batch every hosted blocking finding into **one** fix push. That push creates a new candidate head — return to step 7 for the delta only.
9. Once hosted review has converged, wait for CI on the current candidate head.
10. Verify the merge gates against that same SHA, then merge.

**Nothing between step 9 and the merge may push.** A gate that needs a commit is a defect in an earlier step — fix it there. If one slips through anyway, the resulting SHA is a new candidate head: re-run steps 9–10 on it rather than merging on evidence collected for its parent.

CI normally starts by itself the moment you push, and that is fine — it may well be green by the time you reach step 9. The rule is not "stop CI from running", it is **do not spend a coordinator turn, or a concurrency slot, watching a run you are about to invalidate**.

## Evidence is SHA-scoped

**Every review result and every CI result is evidence about exactly one commit.** Record the SHA next to every result in the ledger; a result with no SHA is not evidence.

When the head changes:

- Outstanding CI waits for the previous SHA are **superseded**. Do not keep waiting on them, do not read their eventual verdict as merge evidence, and do not treat their failure as this head's failure. Where the waiter is a child process or teammate, stop it and reclaim the slot.
- Review results for the previous SHA remain valid **for the code that did not change**; re-review the delta only. That is the existing bounded-delta rule, unchanged.
- Re-launch the waiters whose evidence the delta invalidated, and only those. A head change is never by itself a reason to restart every reviewer — but it is always a reason to re-cover the code that changed, so a reviewer that does not re-review a push on its own (Copilot) must be relaunched explicitly or the new commits ship unreviewed by it.

**A verdict whose SHA you cannot confirm is not a pass.** The CI waiter prints `PR_HEAD_SHA=` beside its verdict for exactly this comparison, and `PR_HEAD_SHA=unknown` when it could not read it; the Copilot waiter prints `REVIEWED_COMMIT_ID=` and `PR_HEAD_SHA=`, which must be equal.

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

This caching applies to `NOT_CONFIGURED` only. `PENDING`, `TERMINAL_PASS`, `TERMINAL_FAIL`, and `ERROR` are per-PR, per-SHA facts and are never carried across PRs.
