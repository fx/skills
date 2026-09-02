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
have arrived in, so there is no cursor left to continue with, and the `length` is
taken per page. Any count a decision rests on uses § Pagination Pattern instead:
accumulate `nodes` across all pages first, then filter, then count.

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
and its `--jq` consumes the response `pageInfo` would have arrived in, so there is
no cursor left to continue with. To actually enumerate every bot comment,
accumulate with § Pagination Pattern and apply this `select` to `ALL_THREADS`.

## Batch Operations

### Resolve Multiple Threads

**This step needs every thread, so it cannot read a single page.** Unlike the
field-shape examples above, its whole purpose is to enumerate the set exhaustively
and act on all of it: a one-page read resolves the first 100 and silently leaves
the rest open — under a merge gate that requires zero unresolved. Build
`ALL_THREADS` with § Pagination Pattern first, then filter it.

```bash
# ALL_THREADS comes from § Pagination Pattern — that loop fails closed, so
# reaching this line means the accumulation is complete, not merely non-empty.
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
reading a connection to exhaustion; skills point here rather than restating the
loop, because four copies of a cursor loop drift and the stale copy is the one that
silently truncates.

**The invariant: accumulate `nodes` across all pages first, then filter, then
count.** Filtering or counting per page is its own bug — a per-page `group_by`
splits one reviewer's threads across pages and reports each slice as that
reviewer's total, and a per-page `length` has exactly the same shape.

**Never hang a reducing `--jq` on the paging call.** `--jq '... | length'` or
`--jq '[... | select(...)]'` discards `pageInfo`, so the response you needed the
cursor from no longer carries one: there is nothing left to page with, and a
first-page `0` becomes indistinguishable from a genuine `0`. Fetch each page raw;
filter the accumulated array afterwards.

**The loop fails closed, and that is mandatory — not defensive style.** A read
that errors and then reports a number is worse than a read that errors and stops,
because the number is acted on: the accumulator is still `[]`, the
`hasNextPage` test on a body with no `data` is false, the loop `break`s, and the
filter below returns **zero** — which every caller reads as "no unresolved
threads, gate met". A transient API error would merge the PR. So a failed request,
a GraphQL `errors` payload, or a body missing the connection must abort with a
non-zero status and a message naming what failed, and a partial accumulation must
never be handed on as if it were the whole set.

Check the three separately; none of them implies the others:

- **`gh api`'s exit status**, explicitly. Do not infer failure from empty output —
  `gh` can exit non-zero *with* output, and a legal response can be short.
- **`.errors`**, separately. GraphQL returns **HTTP 200** with an `errors` array,
  so `gh` exits `0` on a request that wholly or partly failed.
- **The connection itself is present.** This also closes the case where the body
  is not the JSON either check assumed.

```bash
OWNER="owner"; REPO="repo"; PR=13
AFTER=null            # gh -F converts the literal null to a JSON null
ALL_THREADS='[]'

while :; do
  if ! PAGE=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $pr: Int!, $after: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100, after: $after) {
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
    }' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR" -F after="$AFTER"); then
    echo "FATAL: gh api graphql failed paging reviewThreads for $OWNER/$REPO#$PR (after=$AFTER)" >&2
    exit 1
  fi
  # No --jq on that call — pageInfo has to survive to the next iteration.

  # HTTP 200 + an errors array is a failed read that gh reports as success.
  if jq -e 'has("errors")' <<< "$PAGE" > /dev/null 2>&1; then
    echo "FATAL: GraphQL errors paging reviewThreads for $OWNER/$REPO#$PR (after=$AFTER):" >&2
    jq '.errors' <<< "$PAGE" >&2
    exit 1
  fi

  # Positive shape check — also catches a body that is not the JSON above.
  if ! jq -e '.data.repository.pullRequest.reviewThreads.nodes | arrays' \
       <<< "$PAGE" > /dev/null 2>&1; then
    echo "FATAL: response carried no reviewThreads page for $OWNER/$REPO#$PR (after=$AFTER)" >&2
    printf '%s\n' "$PAGE" >&2
    exit 1
  fi

  ALL_THREADS=$(jq -n --argjson acc "$ALL_THREADS" --argjson page "$PAGE" \
    '$acc + $page.data.repository.pullRequest.reviewThreads.nodes') || exit 1

  jq -e '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' \
    <<< "$PAGE" > /dev/null || break
  AFTER=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' \
    <<< "$PAGE") || exit 1
done
```

Only the `break` on `hasNextPage: false` is a legitimate exit. Every other way out
of that loop is an `exit 1`, so nothing downstream can run against a half-read
`ALL_THREADS` — if the loop returned, the accumulator is complete.

`ALL_THREADS` now holds every thread, unfiltered. `totalCount` on any page is the
expected total, so `jq 'length' <<< "$ALL_THREADS"` against it is a free check that
the loop actually finished. Only now apply the filter — once, over the whole set:

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
