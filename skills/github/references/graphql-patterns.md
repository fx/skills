# GitHub GraphQL Patterns

Common GraphQL query and mutation patterns for GitHub operations via `gh api graphql`.

Every list query below shows **one page**. `first: 100` is a page size, not a
promise that the connection fits in it, so any snippet whose result is read as a
complete set has to be driven by § Pagination Pattern — that section is the
canonical mechanism, and the examples above it show field shape only.

## Pull Request Operations

### Get PR Details with Review Threads

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        id
        title
        body
        state
        reviewThreads(first: 100) {
          totalCount
          nodes {
            id
            isResolved
            isOutdated
            comments(first: 10) {
              nodes {
                id
                body
                author {
                  login
                }
              }
            }
          }
        }
      }
    }
  }' -f owner="owner" -f repo="repo" -F pr=13
```

### Get Unresolved Review Threads Only

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 1) {
              nodes {
                id
                body
                path
                line
              }
            }
          }
        }
      }
    }
  }' -f owner="owner" -f repo="repo" -F pr=13 \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)'
```

## Review Thread Management

### Resolve a Review Thread

```bash
# Get thread ID first
THREAD_ID="RT_kwDOQipvu86RqL7d"

# Resolve the thread
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread {
        id
        isResolved
      }
    }
  }' -f threadId="$THREAD_ID"
```

### Reply to Review Thread Comment

```bash
# Get the pull request review thread comment ID
COMMENT_ID="PRRC_kwDOQipvu86RqL7e"

# Add a reply to the thread
gh api graphql -f query='
  mutation($body: String!, $inReplyTo: ID!) {
    addPullRequestReviewComment(input: {
      body: $body
      inReplyTo: $inReplyTo
    }) {
      comment {
        id
        body
      }
    }
  }' -f body="Fixed in latest commit" -f inReplyTo="$COMMENT_ID"
```

### Unresolve a Review Thread

```bash
gh api graphql -f query='
  mutation($threadId: ID!) {
    unresolveReviewThread(input: {threadId: $threadId}) {
      thread {
        id
        isResolved
      }
    }
  }' -f threadId="$THREAD_ID"
```

## Automated Review Workflows

### Count Unresolved Bot Review Threads

```bash
# Filter by bot author (e.g., copilot-pull-request-reviewer, github-copilot[bot])
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 1) {
              nodes {
                author {
                  login
                }
              }
            }
          }
        }
      }
    }
  }' -f owner="owner" -f repo="repo" -F pr=13 \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false and .comments.nodes[0].author.login == "copilot-pull-request-reviewer")] | length'
```

**⛔ That count is only valid on a PR you already know fits in one page, and it is
the wrong shape for a gate.** The `--jq` consumes the response `pageInfo` would
have arrived in — which is what `--paginate` reads the next cursor from, and why
`gh` forbids the two together — and the `length` is taken per page. Any count a
decision rests on uses § Pagination Pattern instead: accumulate `nodes` across all
pages first, then filter, then count.

### Get All Bot Review Comments

```bash
# Filter by bot author (e.g., copilot-pull-request-reviewer, github-copilot[bot])
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            isOutdated
            comments(first: 10) {
              nodes {
                id
                body
                path
                line
                author {
                  login
                }
              }
            }
          }
        }
      }
    }
  }' -f owner="owner" -f repo="repo" -F pr=13 \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.comments.nodes[0].author.login == "copilot-pull-request-reviewer")'
```

**"All" is the filter's intent, not what this call returns.** It shows one page,
and its `--jq` consumes the response `pageInfo` would have arrived in — the field
`--paginate` needs to reach page 2. To actually enumerate every bot comment,
accumulate with § Pagination Pattern and apply this `select` to `ALL_THREADS`.

## Batch Operations

### Resolve Multiple Threads

**This step needs every thread, so it cannot read a single page.** Unlike the
field-shape examples above, its whole purpose is to enumerate the set exhaustively
and act on all of it: a one-page read resolves the first 100 and silently leaves
the rest open — under a merge gate that requires zero unresolved. Build
`ALL_THREADS` with § Pagination Pattern first, then filter it.

```bash
# ALL_THREADS comes from § Pagination Pattern — its `--paginate --slurp` read
# fails closed, so reaching this line means the accumulation is complete, not
# merely non-empty.
THREAD_IDS=$(jq -r '.[] | select(.isResolved == false) | .id' <<< "$ALL_THREADS")

# Resolve each thread
while IFS= read -r thread_id; do
  [ -n "$thread_id" ] || continue   # empty accumulator yields one blank line
  echo "Resolving $thread_id..."
  gh api graphql -f query='
    mutation($threadId: ID!) {
      resolveReviewThread(input: {threadId: $threadId}) {
        thread { id isResolved }
      }
    }' -f threadId="$thread_id"
done <<< "$THREAD_IDS"
```

## Error Handling

### Check for GraphQL Errors

```bash
RESULT=$(gh api graphql -f query='...')

# Check if errors exist
if echo "$RESULT" | jq -e '.errors' > /dev/null; then
  echo "GraphQL error occurred:"
  echo "$RESULT" | jq '.errors'
  exit 1
fi

# Process successful result
echo "$RESULT" | jq '.data'
```

## Best Practices

1. **Use Variables** - Always use GraphQL variables (`-f` or `-F` flags) instead of string interpolation
2. **Filter with jq** - Use `--jq` to filter results client-side rather than complex GraphQL queries — but never on a paging call, see § Pagination Pattern
3. **Paginate Always** - A connection read as a complete set must be paged to exhaustion, whatever its size; `first: 100` is not a bound on what exists
4. **Check Errors** - Always check for `.errors` in the response before processing `.data`
5. **Node IDs** - PR review thread IDs start with `RT_`, comment IDs start with `PRRC_` or `IC_`

## Pagination Pattern

`reviewThreads(first: 100)` returns **at most** the first 100 threads. A truncated
read raises no error — the response is well-formed and simply shorter — so every
count taken off it reads as complete. This section is the canonical mechanism for
reading a connection to exhaustion; skills point here rather than restating it,
because four copies of a pagination recipe drift and the stale copy is the one that
silently truncates.

**`gh` owns the cursor — never hand-roll the loop.** `gh api graphql --paginate`
does GraphQL cursor pagination natively: declare an `$endCursor: String` variable,
pass it as `after: $endCursor`, select `pageInfo { hasNextPage endCursor }`, and
`gh` re-requests until `hasNextPage` is false. `--slurp` wraps the pages into one
outer JSON array. So there is no `while`, no `$AFTER` to carry, no `endCursor` to
read and no `hasNextPage` to test — **and therefore no pagination metadata left for
this script to validate**, which is the whole point. A hand-rolled cursor loop has
no principled terminus: every `pageInfo` field it reads is another field that can
arrive missing or corrupt, and hardening one of them only moves the next fail-open
one field along. Two consecutive review passes found exactly that, one field apart.
Delegating the cursor deletes the class rather than the instance.

**The invariant survives unchanged: accumulate `nodes` across all pages first, then
filter, then count.** Filtering or counting per page is still its own bug — a
per-page `group_by` splits one reviewer's threads across pages and reports each
slice as that reviewer's total, and a per-page `length` has exactly the same shape.

**Never hang a reducing `--jq` on the paging call.** Under `--slurp` that is no
longer a rule you can quietly break: `gh` refuses the combination outright
(`the "--slurp" option is not supported with "--jq" or "--template"`), and refuses
`--slurp` without `--paginate` too. The reason it was a rule still holds — a
`--jq '... | length'` collapses the very document the pages live in, and a
first-page `0` is indistinguishable from a genuine `0`. Fetch pages raw; filter the
accumulated array afterwards.

### Version requirement: `gh` >= 2.48.0

`--slurp` was added in `gh` v2.48.0 (2024-04-17). On an older `gh` this pattern
fails with `unknown flag: --slurp` before any request is made — loud, not silent,
which is the correct failure mode. Check with `gh --version` and upgrade.

**Do not fall back to a hand-rolled cursor loop**; that reinstates the exact
fail-open surface this pattern exists to remove. If upgrading is genuinely
impossible, drop `--slurp` and keep `--paginate`: `gh` then streams one JSON object
per page, and `jq -s` collects them into the same array of pages, so every check
below applies verbatim.

```bash
PAGES=$(gh api graphql --paginate -f query='...' | jq -s '.')   # gh < 2.48.0 only
```

**Failing closed is mandatory — not defensive style.** A read that errors and then
reports a number is worse than a read that errors and stops, because the number is
acted on: the accumulator is `[]`, the filter below returns **zero**, and every
caller reads that as "no unresolved threads, gate met". A transient API error would
merge the PR. So a failed request, a GraphQL `errors` payload, a body that is not
the pages this query asked for, or a short read must abort with a non-zero status
and a message naming what failed; a partial accumulation must never be handed on as
though it were the whole set.

Check the four separately; none of them implies the others:

- **`gh api`'s exit status**, explicitly. `--paginate` exits non-zero if *any* page
  request fails, which is precisely why this is now one check instead of a loop
  invariant. Status-based, never emptiness-based: `gh` can exit non-zero *with*
  output — it prints the pages it managed to fetch before the failure — and a legal
  response can be short.
- **`.errors`, in *any* page.** GraphQL reports failure in the response body with
  **HTTP 200**, so it is not an HTTP-level error. `gh` 2.98.0 does surface it as a
  non-zero exit as well, including a partial failure that returns `data` alongside
  `errors` — but check the body anyway: it costs one `jq`, and it does not depend on
  a particular `gh` version's error handling. With `--slurp` the body is an **array
  of pages**, so the predicate has to be `any`, not `.errors` on the document and
  not `.errors` on page 1 — a partial failure on page 3 leaves pages 1 and 2
  looking perfectly well-formed. This is the one place `--slurp` makes a check less
  obvious than it was per-page.
- **The connection is present in every page.** This also closes the case where the
  body is not the JSON the checks above assumed.
- **The accumulated count equals `totalCount`.** This is the terminus the
  hand-rolled loop never had. `gh` decides when to stop by reading `pageInfo` out of
  each response, so that judgement is now its own; the check that it walked the
  whole connection is therefore no longer "was the metadata well-formed" but "did we
  end up with everything the server says exists". A mismatch means a short read or a
  concurrent change to the PR, and in both cases the answer is re-read, never
  proceed.

```bash
OWNER="owner"; REPO="repo"; PR=13

# --paginate walks the cursor; --slurp wraps every page into one JSON array.
# $endCursor is declared but never bound by a -f/-F flag: gh supplies it, and
# omits it on the first request. No --jq here — gh rejects it under --slurp.
if ! PAGES=$(gh api graphql --paginate --slurp -f query='
  query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
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
  }' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR"); then
  echo "FATAL: gh api graphql --paginate failed reading reviewThreads for $OWNER/$REPO#$PR" >&2
  exit 1
fi

# HTTP 200 + an errors array is a failed read. --slurp yields an array of pages,
# so this must be "any page" — errors on page 3 with pages 1-2 clean is the case.
if jq -e 'any(.[]?; type == "object" and has("errors"))' <<< "$PAGES" > /dev/null 2>&1; then
  echo "FATAL: GraphQL errors reading reviewThreads for $OWNER/$REPO#$PR:" >&2
  jq '[.[] | select(type == "object" and has("errors")) | .errors[]]' <<< "$PAGES" >&2
  exit 1
fi

# Positive shape check — the body is an array of pages and every page carries the
# connection. Also catches a body that is not the JSON the query asked for.
if ! jq -e 'type == "array" and length > 0
      and all(.[]; (.data.repository.pullRequest.reviewThreads.nodes | type) == "array")' \
     <<< "$PAGES" > /dev/null 2>&1; then
  echo "FATAL: response carried no reviewThreads pages for $OWNER/$REPO#$PR" >&2
  printf '%s\n' "$PAGES" >&2
  exit 1
fi

# One jq, flattening nodes across every slurped page into the accumulator.
ALL_THREADS=$(jq '[.[].data.repository.pullRequest.reviewThreads.nodes[]]' \
  <<< "$PAGES") || exit 1

# Did gh walk the whole connection? totalCount is the server's own count.
EXPECTED=$(jq '.[0].data.repository.pullRequest.reviewThreads.totalCount' <<< "$PAGES")
ACTUAL=$(jq 'length' <<< "$ALL_THREADS")
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "FATAL: read $ACTUAL of $EXPECTED reviewThreads for $OWNER/$REPO#$PR — short read or concurrent change" >&2
  exit 1
fi
```

Every exit from that sequence other than running off the end is an `exit 1`, so
nothing downstream can run against a half-read `ALL_THREADS` — if control reached
past the last check, the accumulator is complete. A PR with genuinely zero threads
passes every check and yields `ALL_THREADS='[]'` at status `0`, which is what makes
a true zero distinguishable from a failed read.

`ALL_THREADS` now holds every thread, unfiltered. Only now apply the filter — once,
over the whole set:

```bash
# One reviewer's unresolved threads, counted over every page
jq '[.[] | select(.isResolved == false
       and (.comments.nodes[0].author.login | tostring | contains("<login>")))]
    | length' <<< "$ALL_THREADS"

# Per-reviewer breakdown, grouped over every page
jq '[.[] | select(.isResolved == false) | .comments.nodes[0].author.login]
    | group_by(.) | map({reviewer: .[0], unresolved: length})' <<< "$ALL_THREADS"
```

Request only the fields the caller needs. A page of 100 threads each carrying ten
comment bodies is a large response to hold and re-parse on every iteration.
