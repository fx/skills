# CI

`resolve-pr-feedback` loads this file only when its Step 1 detection finds
failing CI on the PR's head and `ci` is in its `sources:` scope. It holds CI's
mechanics only. The procedure — Scope Brief, triage, dispositions, convergence —
is `fx-review` Steps 1–8, and none of it is restated here.

CI is not a reviewer: it posts no threads, so nothing here settles one.

## Input

`dev` Step 7.1's waiter log under a coordinator; standalone, the CI wait
`resolve-pr-feedback` Step 5 runs. Act only on `STATUS=TERMINAL_FAIL` whose
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
them.

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
Base-branch conflict: yes | no
```

## Converged

CI's condition: the next CI wait on the new head reports `TERMINAL_PASS` for the
SHA it names. Under a coordinator that wait is the caller's (`dev` Step 7.1) and
`resolve-pr-feedback` never runs one; on a standalone unscoped run,
`resolve-pr-feedback` Step 5 runs `dev`'s CI waiter itself, because no one else
will and the condition otherwise has no action that can satisfy it.
