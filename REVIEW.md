# PR Review

Canonical review conventions for this repository. Every automated reviewer reads
this file: GitHub Copilot and Claude Code Review natively, CodeRabbit via
`.coderabbit.yaml`, and Codex via the `## Code Review Rules` pointer in
`AGENTS.md`.

Rules here improve review quality and suppress known false positives. This file
is pasted verbatim into reviewer prompts — write rules out in full, never
reference another file.

## PR Review Checklist (CRITICAL)
<!-- KEEP THIS SECTION UNDER 4000 CHARS - Copilot only reads the first ~4000 -->

### Security and Privacy

- **Do not allow private information leaks**: Flag any use of private repository names, internal URLs, API keys, credentials, or company-specific identifiers in code, documentation, or examples.
- **Require generic placeholders**: Examples should use generic placeholders like `owner/repo`, `example.com`, `your-org`, etc.
- **Check all files**: This applies to documentation (README.md, AGENTS.md, REVIEW.md), code examples, skill references, test cases, and commit messages.

### Skill Naming

- A skill's directory name is what agents invoke, and the frontmatter `name` must match it exactly. Flag any mismatch.
- Flag any new skill whose name collides with a Claude Code built-in slash command or bundled skill — the collision silently shadows the built-in. The avoid-list and its source are in `AGENTS.md`.
- Names are bare by default and take an `fx-` prefix **only** on a collision with a host agent built-in. Flag a new skill that adds the prefix without a collision, and flag one that omits it despite having a collision. `fx-review` and `fx-upgrade` are the two current cases — do not suggest shortening them.
- A renamed skill must have every cross-reference updated. Flag a rename whose old name still appears anywhere under `skills/` or `docs/`.

### Cross-Skill Paths

- `[SKILLS_DIR]/<skill>/scripts/<script>.sh` is the correct form for referencing a sibling skill's bundled script, and it is intentionally a placeholder. Do not flag it as an unresolved path or suggest a literal path in its place.
- Any `SKILL.md` using `[SKILLS_DIR]` must define it in a note under its H1. Flag a file that uses the placeholder without the note.
- Flag hardcoded `.claude/skills/` paths — these skills install into many different agent directories.

### Explicit-Use Descriptions

- Every skill description opens with the explicit-use boundary sentence. Flag a new or edited description that drops it.
- Flag descriptions that add semantic auto-trigger phrasing — trigger-word lists, `MUST BE USED`, `MUST BE LOADED`, "automatically invoked", or generic task semantics like "coding", "review", "fix".

### GitHub CLI (gh) Capabilities

- The `gh` CLI does NOT have built-in commands like `gh pr review-thread resolve` or `gh pr review-thread list`.
- Do not suggest these non-existent commands as alternatives to the GraphQL API approach.
- The correct method for programmatically resolving PR review threads is using the GitHub GraphQL API via `gh api graphql` with the `resolveReviewThread` mutation.
- Verify command existence before suggesting `gh` CLI alternatives.

### jq Semantics

- `jq`'s `group_by(f)` sorts its input by `f` internally before grouping — that is documented behaviour, not incidental. A missing `sort` before `group_by` is NOT a defect and MUST NOT be flagged; `group_by` does not require pre-sorted input and does not only group adjacent elements.

### Instruction File Layout

- `AGENTS.md` holds project conventions; `REVIEW.md` holds review conventions. Do not suggest moving rules between them or reviving `CLAUDE.md` as a conventions file.
- `CLAUDE.md` is intentionally a one-line `@AGENTS.md` import. Do not flag it as empty or incomplete.
- There is intentionally **no** `.github/copilot-instructions.md`. Copilot code review reads `REVIEW.md` directly, so a second copy would only drift. Do not suggest adding one.

## Repository Context

This repository is an agent-skill catalog installed via the [`skills`](https://github.com/vercel-labs/skills) CLI. Each `skills/<name>/SKILL.md` is a prompt document read by a coding agent — not executable code. Review it as instructions: check that a rule is unambiguous, that it cannot be satisfied in a way its author did not intend, and that it does not contradict another skill. Do not apply code-style expectations to prose.

`docs/specs/` states the authority boundaries the skills must honor, linked to skill text by duvet annotations in HTML comments. Those annotations are load-bearing — do not suggest removing them as noise.
