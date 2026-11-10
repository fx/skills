#!/usr/bin/env bash
# run-claude-review.sh
# Runs a scoped, one-shot, read-only `claude -p` review of the current branch with
# every MCP server disabled. The `claude` counterpart of run-codex-review.sh: the
# local reviewer `fx-review with local` resolves to when the host is Codex.
#
# Usage:
#   ./run-claude-review.sh <SCOPE_PROMPT_FILE>
#   ./run-claude-review.sh -                  # read the scope prompt from stdin
#
# Env:
#   CLAUDE_REVIEW_OUT=<path>    also tee the review to this file
#   CLAUDE_REVIEW_DRY_RUN=1     print the resolved command and exit 0 without running
#   CLAUDE_REVIEW_MODEL=<id>    override the review model     (default below)
#   CLAUDE_REVIEW_EFFORT=<lvl>  override reasoning effort     (default below)
#   CLAUDE_REVIEW_BASE=<ref>    override the base the branch is diffed against
#
# MODEL AND EFFORT ARE OVERRIDDEN PER INVOCATION, NEVER IN THE USER'S SETTINGS — the
# same reasoning as run-codex-review.sh. The model is an alias, not a pinned id, so
# the CLI resolves it to the current release.
#
# ⛔ NO TIMEOUT, and run it in the BACKGROUND — exactly as run-codex-review.sh's header
#    says, and for the same reasons. `claude -p` prints nothing until it finishes.
#
# COMPLETION CONTRACT — identical to run-codex-review.sh's, with `CLAUDE_EXIT=` in
# place of `CODEX_EXIT=`. The LAST line of stdout is always `STATUS=<state>`:
# COMPLETED (exit = claude's own, or 128+N if a signal lands after the outcome was
# recorded), DRY_RUN (0), ERROR (3 setup failure, 4 internal abort, 128+N signal). No
# `STATUS=` tail means running or dead. The full rationale for every clause — the
# reap-before-sentinel, PIPESTATUS capture, the recording gap — is that script's header
# and is not restated here; the mechanics below are the same code.
#
# Exit 3 covers exactly: a usage error, `claude` or `git` missing, an unreadable or
# empty scope prompt, no resolvable base, and an empty branch diff.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THESE FLAGS
#
# 1. READ-ONLY BY CONSTRUCTION, NOT BY REQUEST. `--tools` limits the built-ins to
#    Read/Grep/Glob/Bash, `--allowedTools` pre-approves only read-only git
#    subcommands, and `--permission-mode dontAsk` denies everything not pre-approved
#    instead of waiting for an answer nobody can give. A reviewer that can edit the
#    tree it reviews changes the branch under the coordinator. Verified: `touch` is
#    denied and `git log` runs.
# 2. NO MCP SERVERS. `--strict-mcp-config` with no `--mcp-config` loads none —
#    verified, the session reports no MCP tools. The same hang hazard as Codex's
#    (a stalled tool call with no TTY to answer it), removed the same way: wholesale.
# 3. NO SESSION FILE. `--no-session-persistence` keeps one-shot reviews out of the
#    user's resume list.
# 4. NOT `--bare`. It would skip hooks and CLAUDE.md, but it also forces API-key auth
#    and so breaks every OAuth-logged-in user. The prompt preamble below names
#    AGENTS.md and REVIEW.md explicitly instead.
#
# THE BASE IS RESOLVED HERE, NOT BY THE REVIEWER. `codex review` derives the diff
# itself; `claude -p` has no review mode, so the script computes the merge-base and
# names it in the prompt. The work must be committed on a branch — same rule as Codex.
#
# Nested-session variables are cleared so the run behaves the same whether the caller
# is Codex, another harness, or a Claude Code session the user pointed at `claude`.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

CLAUDE_REVIEW_MODEL="${CLAUDE_REVIEW_MODEL:-opus}"
CLAUDE_REVIEW_EFFORT="${CLAUDE_REVIEW_EFFORT:-medium}"

PROMPT_SRC="${1:-}"

STATUS_EMITTED=0
COMPLETION_EXIT=""
CLAUDE_EXIT_EMITTED=0

emit_status() {
    echo "STATUS=$1" && return 0
    echo "STATUS=$1" >&2 && return 0
    return 1
}

emit_claude_exit() {
    if (( CLAUDE_EXIT_EMITTED == 0 )); then
        if echo "CLAUDE_EXIT=$1"; then CLAUDE_EXIT_EMITTED=1; fi
    fi
    return 0
}

# By PID, never by pattern, deepest first — see run-codex-review.sh.
descendants_deepest_first() {
    local pid="$1" kid
    for kid in $(pgrep -P "$pid" 2>/dev/null || true); do
        descendants_deepest_first "$kid"
        printf '%s\n' "$kid"
    done
}

reap_descendants() {
    local pids pid alive i
    pids=$(descendants_deepest_first $$ 2>/dev/null || true)
    [[ -n "$pids" ]] || return 0

    for pid in $pids; do kill -TERM "$pid" 2>/dev/null || true; done

    for ((i = 0; i < 40; i++)); do
        alive=""
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then alive="$alive $pid"; fi
        done
        [[ -n "$alive" ]] || return 0
        sleep 0.1 || true
    done

    for pid in $alive; do kill -KILL "$pid" 2>/dev/null || true; done
    return 0
}

emit_recorded_outcome() {
    if [[ -n "$COMPLETION_EXIT" ]]; then
        emit_claude_exit "$COMPLETION_EXIT"
        emit_status COMPLETED
        exit "$COMPLETION_EXIT"
    fi
    emit_status ERROR
    exit 4
}

trap 'if (( STATUS_EMITTED == 0 )); then reap_descendants; emit_recorded_outcome; fi' EXIT

finish() {
    local status="$1"
    if emit_status "$status"; then STATUS_EMITTED=1; fi
    # COMPLETED passes claude's own exit code through unchanged via `$2`.
    case "$status" in
        COMPLETED) exit "${2:-0}" ;;
        DRY_RUN)   exit 0 ;;
        ERROR)     exit 3 ;;
        *)         exit 4 ;;
    esac
}

if [[ -z "$PROMPT_SRC" ]]; then
    echo "Usage: $0 <SCOPE_PROMPT_FILE>|-" >&2
    echo "" >&2
    echo "The scope prompt is MANDATORY. Build it per fx-review Step 1." >&2
    finish ERROR
fi

for bin in claude git; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "Error: \`$bin\` is not on PATH. The review never started." >&2
        finish ERROR
    fi
done

if [[ "$PROMPT_SRC" == "-" ]]; then
    SCOPE_PROMPT=$(cat)
else
    if [[ ! -r "$PROMPT_SRC" ]]; then
        echo "Error: scope prompt file not readable: $PROMPT_SRC" >&2
        finish ERROR
    fi
    SCOPE_PROMPT=$(cat "$PROMPT_SRC")
fi

if [[ -z "${SCOPE_PROMPT//[[:space:]]/}" ]]; then
    echo "Error: the scope prompt is empty. Refusing to run a promptless review," >&2
    echo "which would report the work this change deliberately did not do." >&2
    finish ERROR
fi

if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    echo "Error: not inside a git repository." >&2
    finish ERROR
fi
cd "$ROOT"

# The reviewer reads the committed branch, so uncommitted edits are not reviewed. A
# warning, not a refusal: unrelated local edits must not block a review of the branch,
# and the caller is the one who knows whether the work itself is committed.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "WARNING: uncommitted changes to tracked files are NOT reviewed — the review reads"
    echo "         <base>...HEAD only. Commit the work under review before relying on it."
fi

# Base: explicit override, else the remote default branch, else main/master.
if [[ -n "${CLAUDE_REVIEW_BASE:-}" ]]; then
    BASE_REF="$CLAUDE_REVIEW_BASE"
else
    BASE_REF=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [[ -z "$BASE_REF" ]]; then
        for cand in origin/main origin/master main master; do
            if git rev-parse --verify --quiet "$cand^{commit}" >/dev/null; then
                BASE_REF="$cand"; break
            fi
        done
    fi
fi

if [[ -z "${BASE_REF:-}" ]] || ! BASE_SHA=$(git merge-base "$BASE_REF" HEAD 2>/dev/null); then
    echo "Error: could not resolve a base to diff against${BASE_REF:+ (tried $BASE_REF)}." >&2
    echo "Set CLAUDE_REVIEW_BASE=<ref>." >&2
    finish ERROR
fi

HEAD_SHA=$(git rev-parse HEAD)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BASE_SHA" == "$HEAD_SHA" ]]; then
    echo "Error: HEAD ($BRANCH) has no commits beyond $BASE_REF — nothing to review." >&2
    finish ERROR
fi

echo "Branch: $BRANCH  Base: $BASE_REF (${BASE_SHA:0:12})  Head: ${HEAD_SHA:0:12}"

# Codex needs an AGENTS.md pointer to see REVIEW.md; this reviewer is simply told.
# Neither file is created or required — absence is reported and the review continues.
RULES=()
for f in AGENTS.md REVIEW.md CLAUDE.md; do
    if [[ -f "$f" && ! -L "$f" ]]; then RULES+=("$f"); fi
done
if (( ${#RULES[@]} == 0 )); then
    echo "Project rules: none found (AGENTS.md, REVIEW.md, CLAUDE.md) — reviewing on the scope prompt alone."
    RULES_LINE="This repository has no AGENTS.md, REVIEW.md or CLAUDE.md at its root."
else
    echo "Project rules: ${RULES[*]}"
    RULES_LINE="Before reviewing, read these files at the repository root in full — they are this project's written rules, and a violation of any of them is a blocking finding: ${RULES[*]}."
fi

PREAMBLE="You are a code reviewer running non-interactively. You cannot edit files, and
you must not try: report findings only.

Review the changes on branch '$BRANCH' against its base: the diff is
\`git diff $BASE_SHA...$HEAD_SHA\`, and \`git log $BASE_SHA..$HEAD_SHA\` lists its
commits. Read any surrounding file you need for context. Report findings ordered
highest-risk first, each with file:line, what is wrong, and the concrete failure.

$RULES_LINE

---
"
FULL_PROMPT="${PREAMBLE}${SCOPE_PROMPT}"

CLAUDE_OPTS=(
    -p
    --strict-mcp-config
    --tools "Read,Grep,Glob,Bash"
    --allowedTools Read Grep Glob
        "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)"
        "Bash(git blame:*)" "Bash(git status:*)" "Bash(git ls-files:*)"
        "Bash(git rev-parse:*)" "Bash(git merge-base:*)" "Bash(git grep:*)"
    --permission-mode dontAsk
    --no-session-persistence
    --output-format text
    --model "$CLAUDE_REVIEW_MODEL"
    --effort "$CLAUDE_REVIEW_EFFORT"
)
echo "MCP servers: none (--strict-mcp-config)"
echo "Model: ${CLAUDE_REVIEW_MODEL}  Effort: ${CLAUDE_REVIEW_EFFORT}"

if [[ -n "${CLAUDE_REVIEW_DRY_RUN:-}" ]]; then
    echo ""
    echo "DRY RUN — resolved command:"
    echo "  claude ${CLAUDE_OPTS[*]} <PROMPT (${#FULL_PROMPT} chars)>"
    finish DRY_RUN
fi

echo ""
echo "Running claude review (one-shot, no timeout — this takes many minutes)..."
echo ""

# The prompt goes on stdin, not argv: `--allowedTools` is variadic and would swallow a
# trailing positional prompt. stdin also keeps a long brief out of the process list.
CLAUDE_ENV=(env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SESSION_ID
            -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_PID -u CLAUDE_EFFORT)

# Under `set +e`, PIPESTATUS captured by the very next statement — see
# run-codex-review.sh for both ways this has gone wrong.
if [[ -n "${CLAUDE_REVIEW_OUT:-}" ]]; then
    set +e
    printf '%s\n' "$FULL_PROMPT" | "${CLAUDE_ENV[@]}" claude "${CLAUDE_OPTS[@]}" | tee "$CLAUDE_REVIEW_OUT"
    pipe_status=("${PIPESTATUS[@]}")
    COMPLETION_EXIT="${pipe_status[1]}"
    set -e
    if (( ${pipe_status[2]:-0} != 0 )); then
        echo "WARNING: could not write the review to CLAUDE_REVIEW_OUT=${CLAUDE_REVIEW_OUT}"
        echo "         (tee exited ${pipe_status[2]}). The review itself COMPLETED and its"
        echo "         findings are on stdout above — read them there, not from that file."
    fi
else
    set +e
    printf '%s\n' "$FULL_PROMPT" | "${CLAUDE_ENV[@]}" claude "${CLAUDE_OPTS[@]}"
    pipe_status=("${PIPESTATUS[@]}")
    COMPLETION_EXIT="${pipe_status[1]}"
    set -e
fi

emit_claude_exit "${pipe_status[1]}"
finish COMPLETED "${pipe_status[1]}"
