# fx Layout Adoption

**This file is the single owner of three things:** what it means for a repository to have adopted the fx docs layout or the fx instruction-file layout, how a skill reports that it has not, and how a skill follows the repository's own convention instead. Every skill that would write an fx-layout file gates on it and cites it by section; none restates it. Several skills run this check, and a check copied into each one drifts — this catalog has already shipped two cwd-relative copies of a check that must be root-relative.

**Only an explicit user invocation of `/fx-setup` or `/fx-upgrade` adopts a layer.** No other skill creates the layout as a side effect, and none loads `fx-setup` as a prerequisite.

## The two layers

| Layer | Files |
|---|---|
| **docs** | `docs/specs/`, `docs/changes/NNNN-*.md`, `docs/index.yml`, `docs/index.md`, `docs/tasks.md` |
| **instruction** | `AGENTS.md`, `REVIEW.md`, the `CLAUDE.md` pointer, the `## Code Review Rules` pointer in `AGENTS.md`, `.coderabbit.yaml` |

## Running the check

The check is `fx-setup`'s `scripts/check-docs-layout.sh`; a `SKILL.md` runs it as `bash [SKILLS_DIR]/fx-setup/scripts/check-docs-layout.sh`. It takes no arguments, resolves the repository root itself, never writes, never reads through a symlink, and always exits 0.

| Key | Meaning |
|---|---|
| `REPO_ROOT` | The root every other value is relative to |
| `FX_DOCS` | `adopted` or `not-adopted` — § What "adopted" means |
| `FX_DOCS_MISSING` | Printed only when adopted: the docs-layer paths that do not exist yet |
| `FX_INSTRUCTIONS` | `adopted`, `partial` or `not-adopted` — for reporting; writers gate per file (§ Who gates on what) |
| `FX_INSTRUCTIONS_PRESENT` | Which of `AGENTS.md` and `REVIEW.md` exist; a symlink is suffixed `(symlink)` |
| `NATIVE_SPECS` | Existing spec, ADR, RFC, design or proposal directories holding at least one `.md` — `docs/specs` among them only when the docs layer is not adopted, plus the directory adr-tools' `.adr-dir` names |
| `NATIVE_TRACKING` | Existing tracker files (`TODO.md`, `ROADMAP.md`, …, and `docs/tasks.md` when the docs layer is not adopted), plus `task-tracking:<value>` when a plain `AGENTS.md` names one |
| `NATIVE_REVIEW_RULES` | In this order: `AGENTS.md` when it has a review heading other than the fx `## Code Review Rules` pointer, then `.github/copilot-instructions.md`. The order is the write preference — `AGENTS.md` reaches Codex, Copilot and CodeRabbit, the Copilot file only Copilot — so `fx-review` Step 6 takes the first entry |
| `NATIVE_CHANGELOG` | Changelog files or fragment directories, plus `generated-by:<tool>` when release tooling owns them |
| `DOCS_SITE` | Docs-site configuration (MkDocs, Docusaurus, mdBook, Sphinx, VitePress) |

GitHub issues are not checked — that needs the network. A caller that needs a tracker runs `gh repo view --json hasIssuesEnabled` itself.

**A coordinator runs the check once per run.** `dev` records the output in the working brief at Step 2.5, and `team` once at STEP 0 for the whole run; later steps read it from there, the same way `dev`'s `references/head-discipline.md` § Reviewer availability is cached for the run caches `NOT_CONFIGURED`. A skill running on its own runs it once at its start.

## What "adopted" means

| Layer | Adopted iff | Why |
|---|---|---|
| docs (`FX_DOCS`) | `docs/index.yml` is a regular file, **or** `docs/changes/` holds a file matching `[0-9][0-9][0-9][0-9]-*.md` | Only these two are fx-specific. `docs/specs/` alone is a common native name — this catalog keeps `docs/specs/` and nothing else, deliberately with no index — and `docs/tasks.md` alone is a generic tracker name |
| instruction (`FX_INSTRUCTIONS`) | `adopted`: `AGENTS.md` and `REVIEW.md` are both regular files. `not-adopted`: neither exists. `partial`: anything else, a symlinked one included | `AGENTS.md` alone is the cross-tool agents.md convention, not an fx signal. Whether the bridges are complete is `fx-upgrade` Step 1's M1 detector, not this check |
| duvet | `.duvet/` at the root | Unchanged; owned by `references/duvet-adoption.md`. The script does not report it |

**Adopted means present, not current.** A legacy or incomplete fx layout is still adopted; legacy detection stays with `fx-setup` Step 5.5 and `fx-upgrade` Step 1.

## Who gates on what

- **Docs-layer writers gate on `FX_DOCS`:** `spec-writer`, `project-management`, and `dev`/`team` task tracking.
- **Instruction-layer writers gate on the one file they would write**, never on `FX_INSTRUCTIONS`: `fx-review` Step 6 on `REVIEW.md`; `codex-review` on `REVIEW.md` before it reports a missing Codex pointer; `resolve-pr-feedback`'s CodeRabbit reference on `REVIEW.md` before it checks `filePatterns`.
- **Completing an adopted docs layer is not adoption.** Where `FX_DOCS=adopted` and `FX_DOCS_MISSING` names a path, the skill that owns that path may create it inside `docs/` when it first needs it (§ Partial adoption).

## Partial adoption

| Repo state | `FX_DOCS` | Behaviour |
|---|---|---|
| `docs/specs/` only (this catalog) | not-adopted | The native spec directory is `docs/specs/`. `spec-writer` writes `docs/specs/<name>/index.md` in the existing specs' shape and creates no `index.*`, no `docs/changes/` and no `tasks.md` |
| `docs/index.yml` present, `docs/changes/` missing | adopted (missing `docs/changes/`) | `spec-writer` creates `docs/changes/` when it writes the first change document; `project-management` creates `docs/tasks.md` from its template when it adds the first orphan task |
| `docs/changes/0001-x.md`, no index | adopted (missing the index files) | `spec-writer` recreates the index from its own templates the next time it updates the index |
| `docs/tasks.md` only | not-adopted | `docs/tasks.md` is a native tracker, edited in its own format |
| `REVIEW.md` only | instruction: partial | `fx-review` Step 6 writes to `REVIEW.md`; `codex-review` reports the missing Codex pointer; the CodeRabbit reference reports a missing `filePatterns` entry |
| `AGENTS.md` only | instruction: partial | `fx-review` Step 6 uses its fallback; `codex-review` says nothing about the pointer — there is no `REVIEW.md` to point at |

## Following the repo's convention

When a layer is not adopted, skip the steps that only make sense in the fx layout and make a best effort to follow what the repository already does:

1. **Use a convention only on evidence:** a directory that already holds a document, a file the repository's own `AGENTS.md`, `CLAUDE.md` or `CONTRIBUTING.md` names, or a tracker the request or issue names.
2. **Mirror the newest existing document** — file naming and numbering (an ADR's `NNNN-title.md`), front-matter, section headings, status vocabulary (an ADR's `Proposed` / `Accepted`). If the convention keeps its own index, such as a `docs/adr/README.md` listing every ADR, update it the same way.
3. **Register outside your authority by report, not by edit.** A new page a `mkdocs.yml` nav would need is reported, not added.
4. **Ask when several conventions fit,** with AskUserQuestion, naming the candidates.
5. **When none exists, create no directory, index or tracker.** Put the content where the request already points — the run's report, the PR body, or an issue the user named. Creating an issue, or any other write to a shared system, needs the user's confirmation first.
6. **Never fabricate fields.** Do not add a `Status:` line, an index entry or a checkbox to a native document whose format has none.

| Artifact | Native target, in order | Owner |
|---|---|---|
| Spec, design or decision | A `NATIVE_SPECS` directory chosen by document type — a decision goes to the ADR directory, a feature or behaviour to a specs, RFC or design directory | `spec-writer` Phase 0.0 |
| Implementation plan | The plan section the native convention already has (an RFC's implementation plan, an ADR's consequences); otherwise the run's report | `spec-writer` Phase 5 |
| Task tracking | The `AGENTS.md` `task-tracking:` value, then a `NATIVE_TRACKING` file, then open GitHub issues | `project-management`; `dev` Step 4 |
| Review rules | `REVIEW.md` where it is a regular file, then the first `NATIVE_REVIEW_RULES` entry (append only), then a proposed rule in the report | `fx-review` Step 6 |
| Changelog, docs site | Reported so the writer knows they exist; nothing here writes them | — |

## Report

Emit each block **once per run**, in the run's final report, and only when a step was actually skipped or redirected because a layer is not adopted. Do not repeat it at every step.

```
fx docs layout: not adopted here (no docs/index.yml, no docs/changes/NNNN-*.md).
Skipped: <fx steps skipped, comma-separated>.
Used instead: <repo convention + path(s) written> | none found — <where the content went: this report / PR body / issue #N>; no new structure created.
To adopt the fx layout, run /fx-setup.
```

```
fx instruction files: <not adopted (no AGENTS.md, no REVIEW.md) | partial (present: <files>; missing: <files>)>.
Skipped: <steps>. <Wrote <rule> to <native file> | Nothing written — proposed rule below>.
To adopt, run /fx-setup; to complete or migrate an existing layout, run /fx-upgrade.
```

**The last line of each block is the only remediation text any other skill may emit about the fx layout** — `fx-setup` and `fx-upgrade` word their own findings. A second phrasing elsewhere is a second rule to drift, and the wrong one tells the owner of a perfectly good native layout to replace it.
