# Copilot

`resolve-pr-feedback` loads this file whenever `copilot` is in its `sources:`, and
on an unscoped run when its Step 1 detection finds Copilot present.
It holds Copilot's mechanics only. The procedure — Scope Brief, triage, dispositions, review-rule entries — is
`fx-review` Steps 1–8, and none of it is restated here; Step 7's convergence
loop is the caller's, never `resolve-pr-feedback`'s (its § One round).

## Identify

A Copilot thread's author is `copilot-pull-request-reviewer` in GraphQL and
`copilot-pull-request-reviewer[bot]` in REST. Match both exactly —
`IN("copilot-pull-request-reviewer", "copilot-pull-request-reviewer[bot]")` — never with a prefix
or substring test, which also claims any login that merely begins with it
(`resolve-pr-feedback` § Supported Reviewers).

**⛔ Never match the bare string `Copilot`.** It appears only in
`requested_reviewers`, which is always empty, so matching on it categorises
**zero** Copilot threads on every PR — real threads stay open while the run
reports nothing to do and the merge gate stays unsatisfiable.

## Configured

Copilot review is mandatory (`copilot-review`), so it is always configured and is
never reported `not configured`. With no Copilot review of the head, report
`configured, no report on head <sha>`: next action "request and wait for Copilot
on `<sha>`" — `copilot-review` Steps 1–2, never this skill.

## Read the verdict of the current head's reviews

The verdict headline decides whether there is work: *Approval recommended* and
*Needs a closer look* both pass when no Copilot threads are open; *Changes
recommended* means work through its threads (`copilot-review` § Reading
Copilot's Verdict). Read every Copilot review **of the current head commit** —
scope by `commit_id`, or after a push you read the previous commit's verdict and
record a check as satisfied for code that review never covered:

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')

gh api --paginate --slurp "/repos/${REPO_NWO}/pulls/${PR_NUMBER}/reviews" \
  | jq -r --arg head "$HEAD_SHA" '[.[][] | select(.user.login | IN("copilot-pull-request-reviewer", "copilot-pull-request-reviewer[bot]")) | select(.commit_id == $head) | .body] | join("\n\n----- (next review of this commit) -----\n\n")'
```

Empty output means **no Copilot review covers the head** — unreviewed, not
clean. This reads every review of that commit, not `| last`: two reviews of one
commit are routine. Confirm the command succeeded before reading silence; an
empty result from a failed fetch looks exactly like a review with an empty body.
Where the caller has a `copilot-review` waiter log, it already prints these bodies.

A `Suppressed comments` block in the review body opens no thread and is ignored
by default (`copilot-review` **D4**). An absolutely-dire suppressed item that is
acted on has no thread to settle — record its outcome in the commit message or
PR body.

## Triage inputs

`[nitpick]` is Copilot's own label: an input to triage, never a verdict. A
project-rule, security, privacy or correctness defect carrying it still blocks —
never settle a thread on the prefix alone.

| Indicator | Usual disposition |
|---|---|
| `[nitpick]`, in scope, and fails the materiality bar | `immaterial` |
| Refers to code that no longer exists | False premise (outdated): reply naming the commit that removed it |
| Misreads a deliberate project convention | False premise (incorrect): reply, plus the `fx-review` Step 6 entry |
| Blocking per `dev`'s `references/scope-contract.md` § Blocking | `blocking` |
| Valid, but out of scope for this PR | `deferred` |

A coordinator's disposition wins over this table (`fx-review` Step 5); use it
only for threads the caller did not dispose of.

**Copilot reads `REVIEW.md` from the head branch**, so where `fx-review` Step 6
wrote its rule to `REVIEW.md`, the rule takes effect on this same PR's next
review.

Every push costs a full Copilot wait cycle: sweep the class before any push
(`fx-review` Step 4), and let only blocking findings produce one.

## State on head

Copilot's state for `resolve-pr-feedback` Step 5 turns on one fact — a Copilot
review **received for the current head** — read with:

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')

REVIEWED=$(gh api --paginate --slurp "/repos/${REPO_NWO}/pulls/${PR_NUMBER}/reviews" \
  | jq -r '[.[][] | select(.user.login | IN("copilot-pull-request-reviewer", "copilot-pull-request-reviewer[bot]")) | .commit_id] | last // empty')
[[ -n "$REVIEWED" && "$REVIEWED" == "$HEAD_SHA" ]] \
  && echo "covered: $HEAD_SHA" \
  || echo "NOT covered — head=$HEAD_SHA reviewed=${REVIEWED:-none}"
```

The `// empty` is load-bearing: without it a PR with no Copilot review prints the
literal `null`, which then gets compared against a SHA — an unreviewed head
presented as a concrete-looking value instead of an obvious absence.

"Received" is the only test — never "was requested": the request API is inert, so
whether a request happened is not a determinable fact (`copilot-review` **D1**).
Report Copilot as exactly one:

- **`clean on head <sha>`** — covered, and zero unresolved Copilot threads. A
  *Needs a closer look* verdict with zero open threads is clean, and a suppressed
  block never makes it otherwise.
- **Threads settled, re-review due** — this round pushed `<sha>`. Copilot does not
  re-review a push on its own: next action "request and wait for Copilot on
  `<sha>`" (`copilot-review` Step 5 → Steps 1–2; `dev` 6.3 per-reviewer step 4).
- **`configured, no report on head <sha>`** — not covered, whether Copilot never
  reviewed this head or reviewed only an older one: the same next action. Copilot
  is mandatory, so this is never clean.
- **Hand-back** — the caller's waiter ended `PENDING` again or `ERROR`
  (`copilot-review`'s `PENDING` row: "Copilot review has not arrived for head
  `<sha>`"), or the thread count stayed unreadable after one retry.
