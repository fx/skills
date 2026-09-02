# skills

An agent-skill catalog for the software development lifecycle: requirements → plan → implement → review → CI → merge, plus the review adapters, feedback resolvers, and documentation skills that lifecycle depends on.

Installable into Claude Code, Codex, Cursor, OpenCode, and 70+ other agents via the [`skills`](https://github.com/vercel-labs/skills) CLI.

## Install

```bash
# Everything, globally
npx skills add fx/skills --skill '*' -g

# Just the lifecycle
npx skills add fx/skills --skill dev --skill coder --skill planner --skill fx-review

# List first
npx skills add fx/skills --list
```

Symlink installs (the default) read straight through to the checkout, so `git pull` in the clone updates every agent at once. `npx skills update` refreshes `--copy` installs.

## Skills

| Skill | Purpose |
|---|---|
| `dev` | Runs the complete attended SDLC lifecycle through requirements, implementation, review, CI, and finalization. |
| `team` | Runs an explicitly requested coordinated multi-agent, multi-task implementation workflow. |
| `fix` | Runs a test-first bug-fix lifecycle and then enters the explicitly requested SDLC workflow. |
| `workflow-runner` | Runs an explicitly selected workflow through its own completion criteria without stopping between phases. |
| `requirements-analyzer` | Analyzes supplied implementation requirements, repository context, and acceptance criteria. |
| `planner` | Creates a detailed implementation plan from supplied requirements and scope. |
| `coder` | Implements code changes while following the supplied scope and project conventions; PR creation remains a separate lifecycle stage. |
| `fx-review` | The canonical Scope Brief, triage, materiality, convergence, and reporting procedure that every reviewer skill in this catalog follows. |
| `codex-review` | Runs a scoped one-shot Codex CLI branch review as an external review adapter. |
| `copilot-review` | Requests, waits for, inspects, and settles a head-scoped GitHub Copilot review. |
| `coderabbit-review` | Handles CodeRabbit's PR-level review as an optional review adapter with Scope Brief triage and rate-limit degradation. |
| `resolve-pr-feedback` | Coordinates explicitly requested automated PR-feedback resolution for the reviewers it has adapters for — Copilot, CodeRabbit and Codecov; any other configured reviewer is settled by hand by the caller. |
| `copilot-feedback-resolver` | Processes and resolves existing GitHub Copilot review threads without creating PR-level comments. |
| `rabbit-feedback-resolver` | Processes and resolves existing CodeRabbit review threads. |
| `resolve-codecov-feedback` | Processes Codecov feedback and adds coverage required by an active workflow. |
| `pr-preparer` | Prepares and opens a ready-for-review pull request from completed branch changes. |
| `pr-check-monitor` | Monitors pull-request checks and coordinates explicitly requested CI remediation. |
| `resolve-ci-failures` | Analyzes and fixes CI failures within an active explicitly requested PR workflow. |
| `github` | Reference guidance for GitHub CLI, pull-request, review-thread, and GitHub API operations. |
| `issue-updater` | Updates GitHub issues with planning, status, and implementation progress within an active workflow. |
| `project-management` | Manages project tracking through `docs/tasks.md`, `docs/changes/`, or an explicitly selected external tracker. |
| `spec-writer` | Writes and maintains living specs and proposed change documents within an explicitly requested documentation lifecycle. |
| `fx-setup` | Creates the default docs and instruction-file layout as a prerequisite of an explicitly invoked documentation workflow. |
| `fx-upgrade` | Migrates repository instruction files to the current conventions after explicit request and confirmation. |
| `verify-web-change` | Verifies specified web changes using the real application and Playwright. |
| `upstream-contrib` | Contributes a local change in a consumer repository upstream to the dependency it belongs in, then rewires the consumer onto it. |
| `tech-scout` | Researches and recommends technologies or libraries when explicitly requested by name. |
| `learn` | Updates this catalog from an explicit `/learn` request and leaves changes uncommitted for review. |

## Explicit invocation

**Every skill here is explicit-use only.** None auto-triggers on generic task semantics — "write some code", "review this", "fix the bug", "make a PR" do not load anything. A skill runs when you name it (`/dev`, "use the planner skill") or when a workflow you already invoked calls it by name.

That is deliberate. These are opinionated multi-step lifecycles that create branches, open pull requests, and drive external reviewers. Loading one because a request merely resembled a stage of it is a worse failure than not loading it at all.

A workflow's authority ends at its documented handoff. A later status question or PR metadata edit is a standalone request, not a resumption.

## `[SKILLS_DIR]`

Several skills invoke scripts bundled with a *sibling* skill — `dev` runs `coderabbit-review`'s waiter, for example. Those paths are written as `[SKILLS_DIR]/<skill>/scripts/<script>.sh`, where `[SKILLS_DIR]` is the directory the skills are installed into (`.claude/skills/`, `~/.agents/skills/`, …). Each affected `SKILL.md` restates this at the top.

For sibling scripts to resolve, install the skills that reference each other into the same directory. Installing `dev` alone will leave its waiter invocations unresolvable.

## `[AGENT_DIR]`

The same treatment for the host's *own* per-repo directory, where the workflow skills put scratch artifacts — waiter logs, the `team` ledger, worktrees. Written as `[AGENT_DIR]/team/...`, it resolves to `.claude` on Claude Code and `.agents` on Codex; the table is in `skills/dev/references/host-adapters.md`. A skill that hardcoded `.claude/` would drop a Codex run's artifacts into Claude Code's state directory.

## Naming

Skills install flat: `skills/<name>/` becomes `<agent>/skills/<name>/`, and the directory name is what you invoke. There is no namespace, so a name matching a host agent's built-in silently shadows it.

Names here are therefore **bare by default, `fx-`-prefixed where a collision is real or likely.** Three currently are:

| Skill | Why |
|---|---|
| `fx-review` | Claude Code reserves `review` |
| `fx-upgrade` | Claude Code reserves `upgrade` |
| `fx-setup` | Not reserved, but `setup` is generic enough that another catalog will claim it |

Everything else keeps its plain name. `AGENTS.md` has the avoid-list and the check.

## Requirements

Most skills assume `git` and the GitHub CLI (`gh`), authenticated. Beyond that: `codex-review` needs the Codex CLI; `verify-web-change` needs the Playwright MCP server; `coderabbit-review` and `copilot-review` need those GitHub Apps installed on the repository, and degrade to a `NOT_CONFIGURED` status when they are not. Review is exactly those three: Codex locally before the PR, then Copilot and CodeRabbit on the PR.

## Contributing

Read `AGENTS.md`. Use `/learn` to make changes — it locates the checkout, edits the right `SKILL.md`, and leaves the diff uncommitted for you.

## License

MIT
