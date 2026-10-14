# Codecov

`resolve-pr-feedback` loads this file whenever `codecov` is in its `sources:` —
`dev` Step 7.2 always names it — and on an unscoped run when its Step 1 detection
finds Codecov present. It holds Codecov's mechanics only. The procedure — Scope Brief, triage, dispositions, review-rule entries — is
`fx-review` Steps 1–8, and none of it is restated here; Step 7's convergence
loop is the caller's, never `resolve-pr-feedback`'s (its § One round).

## Identify

Codecov reports through three channels, and review threads are the rare one:

- commit statuses whose context starts `codecov/` — `codecov/patch` covers the
  lines this PR changed and is the actionable one; `codecov/project` is the
  overall impact;
- an issue comment by `codecov[bot]` or `codecov-commenter`;
- line annotations — PR review comments by those logins.

A review thread whose author is exactly `codecov`, `codecov[bot]` or
`codecov-commenter` (`resolve-pr-feedback` § Supported Reviewers) is settled through
`resolve-pr-feedback` Step 4 like any other source's.

## Collect — three sources, head-scoped

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')          # or set it explicitly: PR_NUMBER=123
REPO_NWO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')
set -o pipefail   # a failed gh read must fail the pipeline, never print an empty "none found"

# 1. Codecov statuses on the head
gh api --paginate --slurp "/repos/${REPO_NWO}/commits/${HEAD_SHA}/statuses" \
  | jq '[.[][] | select(.context | startswith("codecov/")) | {context, state, description, target_url}]' \
  || echo "READ FAILED: statuses — not evidence"

# 2. The latest Codecov PR comment — only if it names the head (short SHA)
gh api --paginate --slurp "/repos/${REPO_NWO}/issues/${PR_NUMBER}/comments" \
  | jq -r --arg h "${HEAD_SHA:0:7}" '[.[][] | select(.user.login | IN("codecov[bot]", "codecov-commenter"))] | last
        | if . == null then empty
          elif (.body | contains($h)) then .body
          else "STALE: the latest Codecov comment does not name head \($h) — not evidence" end' \
  || echo "READ FAILED: comments — not evidence"

# 3. Line annotations on the head commit only
gh api --paginate --slurp "/repos/${REPO_NWO}/pulls/${PR_NUMBER}/comments" \
  | jq --arg head "$HEAD_SHA" '[.[][] | select(.user.login | IN("codecov[bot]", "codecov-commenter")) | select(.commit_id == $head)
        | {path, line: (.line // .original_line), commit_id, body}]' \
  || echo "READ FAILED: annotations — not evidence"
```

Empty output from a read that succeeded is "nothing from Codecov there"; a
`READ FAILED` line is not — retry once, then hand it back. Treating it as empty
sends a configured Codecov to § Configured, or a covered head to a gap.

Codecov edits one comment in place, so read 2 prints its body only when it names
the head's short SHA, and a `STALE:` line otherwise; read 3 keeps only annotations
whose `commit_id` is the head. A report on an older commit is not evidence about
this head (`dev`'s `references/head-discipline.md` § Evidence is SHA-scoped), and
an old annotation would steer the fix to lines this head may no longer have.

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
| No Codecov data on the head | § Configured |

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
- **One fix iteration**, counted by the caller (`dev` Step 7.2). If coverage
  still fails after that push, report the remaining gaps — § State on head's
  hand-back — rather than a second fix.

## Configured

Run this whenever the head has no Codecov evidence — no `codecov/*` status on it,
no Codecov comment naming it. Codecov is **configured** when any one holds:

```bash
ROOT=$(git rev-parse --show-toplevel)
evidence=()
read_failed=0
# 1. A Codecov config file — any one of the three, each tested on its own
for f in codecov.yml .codecov.yml .github/codecov.yml; do
  [ -f "$ROOT/$f" ] && evidence+=("config:$f")
done
# 2. An uploader in a workflow: the action, or the CLI/uploader script
if [ -d "$ROOT/.github/workflows" ]; then
  while IFS= read -r wf; do evidence+=("uploader:${wf#"$ROOT"/}"); done < <(
    grep -rlE 'codecov/codecov-action|codecov(cli)?[[:space:]]+(upload|do-upload)|codecov\.io/(bash|uploader)' \
      "$ROOT/.github/workflows/" 2>/dev/null)
fi
# 3. A codecov/* status on any earlier commit of this PR — a failed read is not a zero
if shas=$(gh pr view "$PR_NUMBER" --json commits --jq '.commits[].oid'); then
  for sha in $shas; do
    if n=$(gh api "/repos/${REPO_NWO}/commits/${sha}/status" \
             --jq '[.statuses[] | select(.context | startswith("codecov/"))] | length'); then
      [ "$n" -gt 0 ] && { evidence+=("status:${sha:0:7}"); break; }
    else
      read_failed=1
    fi
  done
else
  read_failed=1
fi
# One verdict line — read this, never an exit status
if [ ${#evidence[@]} -gt 0 ]; then echo "CODECOV_CONFIGURED=yes ${evidence[*]}"
elif [ "$read_failed" = 1 ]; then echo "CODECOV_CONFIGURED=unknown (a GitHub read failed)"
else echo "CODECOV_CONFIGURED=no"; fi
```

Branch on the `CODECOV_CONFIGURED=` line, never on an exit status: the probes
are several independent tests, and one missing file or one failed read says
nothing about the others.

- **`no`** → `not configured`: report "Codecov does not appear to be configured
  for this repository". Absent, and not a failure.
- **`unknown`** → a read failed and nothing else proved configuration: report the
  failed read as a hand-back (§ State on head). Never classify it as `not
  configured` — that would turn a failed read into a gate that is not there.
- **`yes`** → `configured, no report on head <sha>`, with the evidence. Codecov reports only
  after CI uploads coverage, so this is never a pass and never absent. The one
  re-wait that gives a late `codecov/*` status its chance is the caller's
  (`dev` Step 7.2): it re-runs the CI wait once and invokes this skill again.
  Reported a second time, it is § State on head's hand-back.

## State on head

Report Codecov as exactly one, for `resolve-pr-feedback` Step 5. All of them are
read only after the head's CI wait was terminal, since Codecov reports once CI
uploads coverage; every open Codecov thread is settled either way.

- **`clean on head <sha>`** — the Codecov comment for the head shows zero missing
  lines (or every remaining gap is user-accepted as untestable), and the head's
  `codecov/*` statuses pass.
- **Coverage gaps returned** — the § Hand-off set went to the caller's batched
  fix, or the standalone implementer pushed `<sha>`: next action "wait on CI for
  `<sha>`, then invoke with `codecov`" (`dev` 7.1 → 7.2).
- **`configured, no report on head <sha>`** (§ Configured) — first report after a
  `TERMINAL_PASS` or `TERMINAL_FAIL` CI verdict: next action "re-run the CI wait
  once for `<sha>`, then invoke with `codecov`" (`dev` 7.2). After
  `NOT_CONFIGURED` there is no CI to re-wait, so it is the hand-back below at once.
- **`not configured`** — absent; gates nothing.
- **Hand-back**, the user's decision:
  - **§ Configured read `unknown`** — a GitHub read failed; name it.
  - **Codecov did not report on this head** — `configured, no report` reported a
    second time, after the caller's one re-wait, or once on a head with no CI at
    all, with no failed `codecov/*`
    status (a failed one is a coverage gap, § Assess). Report "Codecov did not
    report on head `<sha>`" with any status states; not a pass, not a gap.
  - **A `codecov/*` status fails with no patch gap** (§ Assess).
  - **Gaps remain after the one fix iteration** (§ Hand-off to Step 3).
