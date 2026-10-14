# CI

`resolve-pr-feedback` loads this file whenever `ci` is in its `sources:`, and on
an unscoped run when its Step 1 detection finds failing CI on the PR's head
(`resolve-pr-feedback` Step 1, which references load). It holds CI's mechanics
only. The procedure — Scope Brief, triage, dispositions — is
`fx-review` Steps 1–8, and none of it is restated here; Step 7's convergence
loop is the caller's, never `resolve-pr-feedback`'s (its § One round).

CI is not a reviewer: it posts no threads, so nothing here settles one.

## Configured

Loaded on request with no failing check on the head, read the head's checks
(§ Select the failing checks, without the failure filter) and report exactly one:

- **Every check completed, none failed** → `clean on head <sha>`. Nothing to
  diagnose.
- **Checks still running** → `configured, no report on head <sha> (checks
  pending)`. The CI wait is the caller's (`dev` Step 7.1); this skill runs none.
- **No check at all** → § Conflict check first; with no conflict, `not
  configured` — and "no CI ran on head `<sha>`" is never a pass (§ State on head).

## Input

The caller's CI waiter log (`dev` Step 7.1) where it has one; otherwise the
head's checks read directly (§ Select the failing checks) — this skill runs no
wait of its own. Act only on `STATUS=TERMINAL_FAIL` whose
`PR_HEAD_SHA=` equals the caller's candidate head (`dev`'s
`references/head-discipline.md` § Evidence is SHA-scoped) — a verdict for an
older head is superseded, not this head's failure. A `NOT_CONFIGURED` verdict
goes to § Conflict check first.

## Conflict check first

**GitHub Actions does not run CI on a PR that conflicts with its base branch.**
When checks are absent, stuck in `Expected`, never fired after a push, or the
waiter reported `NOT_CONFIGURED`, rule this out before looking at workflow files,
runners or branch protection:

```bash
gh pr view "$PR_NUMBER" --json mergeable,mergeStateStatus -q '{mergeable, mergeStateStatus}'
```

`mergeable: CONFLICTING` or `mergeStateStatus: DIRTY` means CI is blocked by the
conflict, not by the code. Return it to the caller as a blocking finding ("branch
conflicts with its base"); resolving it is the caller's — `dev` § Error Handling
→ Git conflict stops and reports to the user. Never rebase or force-push from
here.

## Select the failing checks — head-scoped

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')

# Check runs on the head commit
gh api --paginate --slurp "/repos/${REPO_NWO}/commits/${HEAD_SHA}/check-runs" \
  | jq '[.[].check_runs[] | select(.conclusion as $c | ["failure","cancelled","timed_out","action_required"] | index($c)) | {name, id, conclusion, html_url}]'

# Legacy commit statuses on the head (combined status, not a list endpoint)
gh api "/repos/${REPO_NWO}/commits/${HEAD_SHA}/status" \
  --jq '[.statuses[] | select(.state == "failure" or .state == "error") | {context, description, target_url}]'
```

Exclude `codecov/*` contexts and the `CodeRabbit` check — their references own
them. **Excluded is not dropped, and never flaky or infrastructure:** list each
failing excluded check under "Owned by another source" in the hand-off, so the
caller routes it to that source instead of reading a failed run with no CI finding
as a transient one.

If you read checks through `gh pr checks` instead, select
`bucket == "fail" or bucket == "cancel"`. It has no field for a run's final
result — its `--json` fields are bucket, completedAt, description, event, link,
name, startedAt, state and workflow — and it always reports the PR's *current*
head, so confirm the head did not move across the read.

## Fetch the logs — most structured first

1. **Annotations:**
   `gh api --paginate "/repos/${REPO_NWO}/check-runs/${CHECK_RUN_ID}/annotations"`
2. **Actions runs for the head commit**, then the failed steps' log:

   ```bash
   gh run list --commit "$HEAD_SHA" --json databaseId,name,conclusion --jq '.[] | select(.conclusion == "failure")'
   gh run view "$RUN_ID" --log-failed
   ```

   List by commit, never by `--branch`: a branch listing mixes in runs from older
   commits.
3. **Output too large:** list the failed jobs and fetch one job's log:

   ```bash
   gh run view "$RUN_ID" --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {name, id: .databaseId}'
   gh api "/repos/${REPO_NWO}/actions/jobs/${JOB_ID}/logs"
   ```
4. **No logs at all:** infer from the check's name and conclusion, and say so.

## Categorise

| Category | Indicator | Result |
|---|---|---|
| Test failure | Runner output, assertion errors | Blocking. Fix the test or the code; never skip it (`dev` § Test Policy) |
| Build error | Compile errors, missing dependencies, module not found | Blocking |
| Lint / format | Linter or formatter output | Blocking. Never suppress with an ignore comment unless it is justified, and the justification is in the commit |
| Security scan | Vulnerability alerts, dependency audit | Blocking. Update the dependency or fix the code |
| **Flaky** | Passed earlier on the same code; intermittent; no change caused it | Never re-run blindly. Record the evidence — the failing run, a passing run of the same SHA or test, the assertion — and report it; a re-run is the user's call |
| **Infrastructure** | Runner errors, network, image pulls, timeouts the code did not cause | Report it. Never try to fix it with a code change |

Fix the root cause, not the symptom. A check is never retried without a fix
pushed first.

## Hand-off to Step 3

```
CI failures — head <sha>
- <check> (<workflow>): <category> — <root cause, file:line> — evidence: <annotation or log excerpt>
Reported, not fixed: <check>: infrastructure | flaky — <evidence>
Owned by another source: <check> → coderabbit | codecov | none
Base-branch conflict: yes | no
```

## State on head

Report CI as exactly one, for `resolve-pr-feedback` Step 5:

- **`clean on head <sha>`** — every check completed, none failed.
- **Failures returned** — the § Hand-off set went to the caller's batched fix, or
  the standalone implementer pushed `<sha>`. Either way the next CI verdict is a
  wait on the new head: next action "wait on CI for `<sha>`" (`dev` 7.1).
- **`configured, no report on head <sha> (checks pending)`** — next action "wait
  on CI for `<sha>`" (`dev` 7.1).
- **Hand-back** — report the reason; nothing here or in a further wait changes it:
  - every failure flaky or infrastructure (§ Categorise), or owned by another
    source (§ Select the failing checks), with the evidence;
  - after § Conflict check, a base-branch conflict (returned as the blocking
    finding it is), or "no CI ran on head `<sha>`", which is not a pass;
  - the caller's wait ended `PENDING` again or `ERROR` — unfinished or failed,
    never a verdict.
