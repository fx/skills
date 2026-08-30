# Contributing to this skill catalog

Conventions for writing and changing skills in this repository. `CLAUDE.md` is a pointer to this file.

## Code Review Rules

Read `REVIEW.md` at the repository root and apply it in full as the review rules for this repo. It is the canonical review-conventions file.

Put a rule about **writing** skills here. Put a rule about **reviewing** them in `REVIEW.md`. Never edit `CLAUDE.md` to add content — edit this file, which it imports.

## Layout

```
skills/<name>/
├── SKILL.md          # required — frontmatter + instructions
├── references/       # optional — long-form docs the skill reads on demand
└── scripts/          # optional — executable helpers the skill runs
```

Flat only. The [`skills`](https://github.com/vercel-labs/skills) CLI supports category subdirectories, but they do not namespace anything — the installed name is still the leaf directory name — so they would add nesting without buying separation.

`docs/specs/` holds the specs that constrain skill behavior; `.duvet/config.toml` links spec requirements to the `SKILL.md` sentences that carry them.

## Naming

**The directory name is the invocable name.** Claude Code takes the command from the directory, not from frontmatter, and the [Agent Skills spec](https://agentskills.io) requires `name:` to match the directory. Keep them identical.

Format: `[a-z0-9-]+`, 1–64 chars, no leading/trailing hyphen, no `--`. That satisfies the spec, Codex (≤64 chars), and Pi (which warns but still loads on violation).

**Names are bare by default.** `dev`, `coder`, `planner`, `github` — no vanity prefix, because it costs a keystroke on every invocation and buys nothing when the name is already distinctive.

**Prefix `fx-` when a collision is real or likely.** Two triggers, in order:

1. **The name is reserved by a host agent** — mandatory. `review` → `fx-review`, `upgrade` → `fx-upgrade`.
2. **The name is a bare common noun another catalog would plausibly claim** — judgement, applied sparingly. `setup` → `fx-setup`. The flat namespace has no tiebreak, so the loser of a collision is whichever skill the host happens to load second.

Everything else stays bare. Do not prefix a name that is already distinctive (`pr-preparer`, `tech-scout`, `coderabbit-review`), and do not rename an existing bare skill without one of the two triggers above — a rename breaks every cross-reference and every user's muscle memory.

### Reserved names

Skills install into a flat shared directory, so a name that matches a host agent's built-in **silently shadows it** — no warning, no error, the built-in just stops working. Check any new name before using it, and if it collides, add the `fx-` prefix rather than inventing a descriptive substitute.

**Claude Code** reserves the names of all built-in slash commands and bundled skills, *including when those are disabled in the session*. Overriding is silent (docs: "A skill at any of these levels also overrides a bundled skill with the same name"). Verify against the current [commands reference](https://code.claude.com/docs/en/commands) rather than a stale copy; the list has ~127 entries and grows. Names this catalog specifically avoids: `review`, `upgrade`, `code-review`, `run`, `init`, `verify`, `debug`, `doctor`, `simplify`, `loop`, `schedule`, `security-review`, `plan`, `team-onboarding`, `workflows`, `workflow-authoring`. The directory name `synced` is reserved outright.

**Codex** ships six system skills — `imagegen`, `openai-docs`, `plugin-creator`, `review-agent`, `skill-creator`, `skill-installer`. Codex does not shadow: a duplicate name yields two ambiguous entries in the picker, which is its own failure mode. Avoid them.

**Pi** has no bundled skills and namespaces commands as `/skill:<name>`, so it constrains nothing. On a collision it keeps the first found and warns.

Renaming a skill means: `git mv`, update `name:`, then `grep -rn '<old>' skills/ docs/` and fix every reference. A dangling cross-reference is invisible until a workflow reaches that step at runtime.

## Frontmatter

```yaml
---
name: <matches directory name>
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. <what it does>"
---
```

Both fields required — the `skills` CLI will not discover a skill missing either.

## Explicit invocation

**Every skill here is explicit-use only.** A skill may run when:

1. the user explicitly names or invokes it (`/dev`, "use the planner skill"), or
2. an already-active, explicitly invoked workflow calls it by name.

Do not write descriptions that auto-trigger on generic task semantics — "coding", "GitHub", "planning", "review", "fix", "create". Do not use `MUST BE USED`, `MUST BE LOADED`, "automatically invoked", or trigger-phrase lists to turn an ordinary request into a lifecycle invocation.

A workflow's instructions apply only to the request that invoked it and end at its documented handoff. Later standalone requests do not inherit the old workflow's orchestration rules: a status query, branch sync, PR metadata change, or explicitly approved merge is handled directly unless the user starts another workflow.

Internal delegation stays valid — `dev` may name `coder`, `planner`, and the reviewer skills as part of its active lifecycle. That does not authorize those skills to load themselves for unrelated requests.

## Cross-skill paths

A skill referencing a sibling's bundled script writes it as:

```
[SKILLS_DIR]/<other-skill>/scripts/<script>.sh
```

`[SKILLS_DIR]` is the directory holding the skill's own folder — the parent of the directory containing its `SKILL.md`. Any `SKILL.md` using the placeholder must define it in a note directly under its H1; copy the wording from an existing one so it stays uniform.

Never hardcode `.claude/skills/` — these skills install into 70+ different agent directories.

## Security and privacy

**Never include private or sensitive information** in skills, docs, or examples: private repository names, internal URLs or endpoints, API keys, company-specific identifiers, infrastructure details.

Use generic placeholders:

```bash
gh api repos/owner/repo/pulls/13
gh api graphql -f owner="owner" -f repo="repo"
```

Bad examples must use angle-bracket placeholders (`<real-org>/<real-private-repo>`) rather than plausible-looking names. An illustration of the mistake must not commit the mistake — a realistic-looking name inside a "don't do this" block is still a realistic-looking name in the repo, and it gets copied.

This applies to skill bodies, references, scripts, test fixtures, and commit messages.

## Writing style

- **Imperative.** "Do X", "Never do Y" — not "you should consider".
- **Explain non-obvious rules.** A rule whose reason is missing gets relaxed by the next editor who cannot see the failure it prevents.
- **One source of truth.** Shared review procedure lives in `fx-review`; adapters describe only their own tool's mechanics. A copied rule is a rule that will drift, and the stale copy is reliably the narrower one.
- **Prefer `references/`** over inflating `SKILL.md`. The body is always in context; references are read on demand.

## Specs and duvet

`docs/specs/fx-dev-authority/index.md` states the authority boundaries of `dev`, `team`, and `spec-writer` — who may merge, who may write. Skill sentences carrying those requirements are annotated:

```markdown
<!--
duvet= docs/specs/fx-dev-authority/index.md#<section-anchor>
duvet= type=implication
duvet# <the requirement text>
-->
```

The `<!--` and `-->` delimiters must sit on their own lines; duvet reads the whole line after the meta prefix and a single-line form folds the closing delimiter into the value.

Regenerate the report with `rm -rf .duvet/requirements && duvet report`. The `rm -rf` is not optional — duvet writes one TOML per current spec section and never deletes stale ones, so a renamed heading leaves an orphan behind.

Snapshot and CI enforcement are not yet wired up in this repository.

## Testing

Before opening a PR:

```bash
npx skills add . --list          # every skill discovered, no parse errors
grep -rn '<renamed-skill>' skills/ docs/   # no dangling cross-references
bash -n skills/*/scripts/*.sh    # scripts parse
```

Then invoke the changed skill by name in a real session and check it does what the diff claims. Structural validation does not catch a workflow that reads correctly and behaves wrong.
