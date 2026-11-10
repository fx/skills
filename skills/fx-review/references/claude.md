# Claude

`fx-review` loads this file when it is invoked `with claude`, or `with local` on
a host that resolves to Claude (its § Picking the local reviewer). It holds the
`claude` CLI's mechanics only. The procedure — carrying the Scope Brief, triaging
in filter order, sweeping a class, converging, reporting — is `fx-review` Steps
1–8, and none of it is restated here.

In this file, **"this skill" means `fx-review` invoked `with claude`**. A bare step
number names a step of this file; "`fx-review` Step N" names the procedure's.

Claude is a **local, one-shot** reviewer against the current branch, run through
`claude -p`. It fills the same slot as Codex — the pre-PR review (`dev` Step 4.5) —
and is picked when the session itself runs on Codex, so the reviewer is never the
model family that wrote the change.

## Project conventions: named in the prompt, no bridge needed

`claude` reads `CLAUDE.md` on its own, and nothing else. Rather than depend on a
`CLAUDE.md` → `@AGENTS.md` import the repo may not have, **the bundled script
names every one of `AGENTS.md`, `REVIEW.md` and `CLAUDE.md` that exists at the
repository root in the prompt** and tells the reviewer to read them first. No
repository file is created or required, so unlike Codex there is no missing-pointer
warning to report.

If Claude flags something `REVIEW.md` explicitly permits, say so rather than
silently applying the finding.

## The prompt IS the Scope Brief

Build it exactly as `references/codex.md` § The prompt IS the Scope Brief
describes — the same six parts, in the same order, ending with `fx-review` § The
external-reviewer block (Part 2 every pass; Part 1 above it from pass 2). Write it
to a file and hand the file to the script. The script prepends a short preamble —
read-only role, the resolved `<base>...<head>` range, the rules files — and
nothing else.

**A run without the scope prompt is an incomplete pass.** The script refuses to
start without a non-empty one.

## Running it

```bash
mkdir -p [AGENT_DIR]/team/waits && \
bash [SKILLS_DIR]/fx-review/scripts/run-claude-review.sh /tmp/scope-prompt.md \
  > [AGENT_DIR]/team/waits/claude-review.log 2>&1
```

**⛔ Run it as a long wait** (`[SKILLS_DIR]/dev/references/host-adapters.md`
§ Long waits), never a hand-rolled one —
`[SKILLS_DIR]/dev/references/background-waits.md` holds the rule. `claude -p`
prints nothing until it finishes, so the log stays short until then.

What the script does, so none of it is half-remembered:

- **Read-only by construction.** `--tools Read,Grep,Glob,Bash`, `--allowedTools`
  pre-approving only read-only `git` subcommands, and `--permission-mode dontAsk`,
  which denies everything else instead of waiting for an answer nobody can give.
  The reviewer cannot edit the branch it reviews.
- **No MCP servers.** `--strict-mcp-config` with no `--mcp-config` loads none,
  removing the same stalled-tool-call hang `references/codex.md` documents.
- **The base is resolved by the script.** `claude` has no review mode, so the
  script computes the merge-base with the remote default branch (override with
  `CLAUDE_REVIEW_BASE=<ref>`) and names the range in the prompt. Every run reads
  the whole branch; a delta re-run is scoped by the prompt, exactly as for Codex
  (`dev` Step 6.1).
- **Committed work only.** The review reads `<base>...HEAD`; uncommitted edits
  are not reviewed, and the script prints a warning when tracked files are
  dirty. Commit the work to a branch first and say you did.
- **No session file** (`--no-session-persistence`), and nested-session variables
  are cleared so the run behaves the same from any caller.
- **Not `--bare`.** It skips hooks and `CLAUDE.md`, but it also forces API-key
  auth and breaks every OAuth login.

### Model and effort

Defaults: `opus` at `medium`, applied per invocation and overridable with
`CLAUDE_REVIEW_MODEL` / `CLAUDE_REVIEW_EFFORT`. The model is the CLI's alias, so it
tracks the current release. Never edit the user's `~/.claude/settings.json` to
change them.

### Read the `STATUS=` line

The contract is `references/codex.md` § Read the `STATUS=` line, unchanged, with
`CLAUDE_EXIT=<n>` in place of `CODEX_EXIT=<n>`. Branch on `STATUS=`, read the
findings on `COMPLETED`, and report `CLAUDE_EXIT=` rather than `$?`. Exit 3 here
also covers an unresolvable base and a branch with no commits beyond its base.

`CLAUDE_REVIEW_DRY_RUN=1` prints the resolved command and exits `STATUS=DRY_RUN`;
`CLAUDE_REVIEW_OUT=<path>` also tees the review to a file.

### Availability

- Requires `claude` installed and already authenticated. If it is not, STOP and
  report to the user — never run `claude login` or `/login`.
- If the CLI is unavailable or unauthenticated, report once and skip this pass,
  as for Codex.

## Claude-specific triage notes

Identical to `references/codex.md` § Codex-specific triage notes: no threads to
resolve — an immaterial observation goes into the closing note — and a fix is a
commit, not a push.

## The gate

A **converged** run is the local gate to PR creation (`dev` Step 4.5 → Step 5),
exactly as `references/codex.md` § The gate states for Codex. It is one local
reviewer, not a second one: `fx-review with local` picks Claude *instead of*
Codex, never alongside it.
