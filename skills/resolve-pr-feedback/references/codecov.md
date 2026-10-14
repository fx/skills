# Codecov

`resolve-pr-feedback` loads this file only when its Step 1 detection finds
Codecov on the PR's head and Codecov is in its `sources:` scope. It holds
Codecov's mechanics only. The procedure — Scope Brief, triage, dispositions,
review-rule entries, convergence — is `fx-review` Steps 1–8, and none of it is
restated here.

## Identify

Codecov reports through three channels, and review threads are the rare one:

- commit statuses whose context starts `codecov/` — `codecov/patch` covers the
  lines this PR changed and is the actionable one; `codecov/project` is the
  overall impact;
- an issue comment by `codecov[bot]` or `codecov-commenter`;
- line annotations — PR review comments by those logins.

A review thread whose author starts `codecov` is settled through
`resolve-pr-feedback` Step 4 like any other source's.

## Collect — three sources, head-scoped

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')

# 1. Codecov statuses on the head
gh api --paginate --slurp "/repos/${REPO_NWO}/commits/${HEAD_SHA}/statuses" \
  | jq '[.[][] | select(.context | startswith("codecov/")) | {context, state, description, target_url}]'

# 2. The latest Codecov PR comment
gh api --paginate --slurp "/repos/${REPO_NWO}/issues/${PR_NUMBER}/comments" \
  | jq -r '[.[][] | select(.user.login == "codecov[bot]" or .user.login == "codecov-commenter")] | last | .body // empty'

# 3. Line annotations
gh api --paginate --slurp "/repos/${REPO_NWO}/pulls/${PR_NUMBER}/comments" \
  | jq '[.[][] | select(.user.login == "codecov[bot]" or .user.login == "codecov-commenter") | {path, line: (.line // .original_line), body}]'
```

Codecov edits one comment in place. Confirm it names the head commit before using
it — a report on an older commit is not evidence about this head (`dev`'s
`references/head-discipline.md` § Evidence is SHA-scoped).

## Assess

**CI status alone is not sufficient — read the Codecov comment.**
`codecov/patch` can pass at a lower threshold than the project requires, so trust
the comment's patch percentage and missing lines over the status.

**Threshold lookup — first hit wins:**

1. `codecov.yml`, `.codecov.yml` or `.github/codecov.yml` →
   `coverage.status.patch.*.target`;
2. `AGENTS.md`;
3. the repo-root `CLAUDE.md`, for a repo that still keeps its conventions there;
4. `CONTRIBUTING.md`;
5. only then the default: 100% patch coverage.

Defaulting while a documented threshold sits unread either blocks the PR or
produces tests nobody asked for.

| Condition | Result |
|---|---|
| Comment shows 0 missing lines and the patch % meets the threshold | Clean |
| Comment shows any missing lines, even with a passing status | Coverage gap |
| No comment, but a `codecov/*` status is `failure` or `error` | Coverage gap |
| Comment clean, but a `codecov/*` status is `failure` or `error` — usually `codecov/project` | Not a patch gap and not flaky: report it as Codecov's, with the status description, for the user's decision. The failing check still gates the merge |
| No Codecov data at all | § Not configured |

## Locate the uncovered lines

Most precise first:

1. line annotations — each names a file and line;
2. the comment's per-file table, plus `git diff` of those files to find the new
   or changed lines;
3. the status's `target_url` (WebFetch) for the full report.

## Hand-off to Step 3

```
Codecov coverage gaps — head <sha>, patch <x>% (threshold <y>% from <source>)
- <path>: lines <ranges> (new or changed in this PR)
Deliberately uncovered: <path:lines> — <why>
```

- **Only lines this PR changed.** Patch coverage is the target, not the project
  total.
- The fix uses the project's own test, lint and type-check commands (its
  `AGENTS.md`), never a hardcoded runner.
- **Untestable code** — error handlers, platform-specific branches: document which
  lines and why, and report them for the user's decision. Never add a meaningless
  test to hit a number.
- **One fix iteration.** If coverage still fails after one push, report the
  remaining gaps instead of looping.

## Not configured

No status, comment or annotation on the head: check for `codecov.yml` /
`.codecov.yml` and for `codecov/codecov-action` in `.github/workflows/`, report
"Codecov does not appear to be configured for this repository", and treat the
source as absent — not as a failure.

## Converged

Codecov's condition for `resolve-pr-feedback` Step 5: the Codecov comment for the
current head shows zero missing lines (or every remaining gap is user-accepted as
untestable), and the head's `codecov/*` statuses pass — read after the CI wait
for that head reached a terminal verdict, since Codecov reports only once CI
uploads coverage. That wait is `dev` Step 7.1's under a coordinator and
`resolve-pr-feedback` Step 5's on a standalone run.
