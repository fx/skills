---
name: upstream-contrib
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. Contributes a local change in a consumer repository upstream to the dependency it belongs in, then rewires the consumer onto it."
---

# Upstream Contribution

> **Path note:** `[SKILLS_DIR]` below is the directory holding this skill's own folder —
> the parent of the directory containing this `SKILL.md`. Substitute its absolute path;
> every skill referenced below is installed as a sibling there.

A change was made in a consumer repository that really belongs in one of its dependencies. This skill moves it there: clone the upstream, implement it under *that project's* conventions, verify the consumer against a local build, open the upstream PR through the normal `dev` lifecycle, and — after the upstream merges and releases — rewire the consumer onto the published version.

It is deliberately ecosystem-neutral. Nothing here assumes a language, package manager, or upstream project; everything specific is **discovered** in Phase 0 and used as a variable thereafter.

## When to Use

- A local component, module, or fix duplicates or extends something a dependency already owns
- A patch is being carried locally (a vendored file, a `patches/` entry, a fork) that should go upstream instead
- The user says "upstream this", "contribute this to <project>", "send this to <dependency>"

**Not for:** opening a PR on a repository you are already working in — that is `dev`. This skill exists for the two-repository case, where the change has to cross a dependency boundary and the consumer has to be re-pointed afterwards.

## Prerequisites

- `gh auth status` succeeds
- The consumer repo declares the upstream as a dependency
- The consumer repo is on a feature branch, not its default branch
- The change to upstream already exists locally, or is clearly specified

---

## Phase 0: Establish Context

Everything the rest of the workflow needs is resolved here. Do not hardcode any of it.

### 0.1 Consumer repo

```bash
CONSUMER_ROOT=$(git rev-parse --show-toplevel)
CONSUMER_BRANCH=$(git branch --show-current)
CONSUMER_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

### 0.2 Identify the upstream repository

Ask the user if they named it. Otherwise resolve it from the dependency itself — the manifest names the package, the registry names the repository:

| Ecosystem | Package named in | Repository URL from |
|---|---|---|
| JS/TS | `package.json` | `npm view <pkg> repository.url` |
| Python | `pyproject.toml`, `requirements.txt` | `pip show <pkg>`, or PyPI `project_urls` |
| Rust | `Cargo.toml` | `cargo info <crate>`, or crates.io `repository` |
| Go | `go.mod` | the module path is the repository |
| Ruby | `Gemfile` | `gem info <gem>`, or rubygems `source_code_uri` |

Record:

```bash
UPSTREAM_SLUG=<owner/repo>
UPSTREAM_PKG=<package name as the consumer imports it>
```

**Confirm both with the user before cloning.** Guessing the wrong upstream sends someone else's project a PR built on assumptions.

### 0.3 Visibility

This determines whether the confidentiality rules below are in force:

```bash
gh repo view "$UPSTREAM_SLUG" --json isPrivate -q '.isPrivate'   # upstream
gh repo view "$CONSUMER_SLUG" --json isPrivate -q '.isPrivate'   # consumer
```

Record `UPSTREAM_PUBLIC` and `CONSUMER_PRIVATE`.

### 0.4 Consumer tooling

Detect once, reuse throughout — the commands differ per project even within one ecosystem:

```bash
ls "$CONSUMER_ROOT" | grep -E 'bun.lock|pnpm-lock.yaml|yarn.lock|package-lock.json|uv.lock|poetry.lock|Cargo.lock|go.sum|Gemfile.lock'
```

Record `CONSUMER_PM` and the consumer's own build/test commands (from its manifest scripts or its `AGENTS.md`).

---

## CRITICAL: Consumer Confidentiality

**Applies whenever the upstream is public and the consumer is not** (`UPSTREAM_PUBLIC && CONSUMER_PRIVATE` from 0.3). Skip it only when both are public — and when in doubt, apply it: over-generalizing a PR description costs nothing, and a leak cannot be un-published.

- **NEVER** name the consumer project, its org, its repo, its URL, or its authors in any upstream commit message, PR title, PR body, code comment, test name, story, fixture, or doc
- **NEVER** write motivation as "needed by X" or "for use in Y app"
- **ALWAYS** describe the change on its own terms: "Add status variants to Badge", not "Add Badge variants for the internal dashboard"
- **ALWAYS** justify it generically: "Status variants let consumers indicate workflow state", not "Required for our workspace status display"

This covers every upstream artifact, not just the PR body. Write as though the consumer project does not exist.

**Also: no `#<number>` in the upstream PR title** unless that number is a real PR or issue **on the upstream repo**. A consumer-repo issue number silently links to an unrelated upstream issue. No wave, phase, step, or change-doc numbers in the title either — see the `github` skill's "`#<number>` PR-Title Rule".

**Values, not just words.** Do not carry consumer-specific constants upstream: brand colors, internal hostnames, tenant IDs, feature-flag names, copy strings. Upstream gets a neutral default; the consumer overrides it locally. A hex code is as identifying as a sentence.

---

## Phase 1: Upstream Working Copy

### 1.1 Clone or reuse

Place it beside the consumer repo, and reuse an existing clone rather than re-cloning:

```bash
UPSTREAM_DIR="$(dirname "$CONSUMER_ROOT")/$(basename "$UPSTREAM_SLUG")"

if [ -d "$UPSTREAM_DIR/.git" ]; then
  git -C "$UPSTREAM_DIR" fetch origin
  DEFAULT_BRANCH=$(gh repo view "$UPSTREAM_SLUG" --json defaultBranchRef -q '.defaultBranchRef.name')
  git -C "$UPSTREAM_DIR" checkout "$DEFAULT_BRANCH"
  git -C "$UPSTREAM_DIR" pull origin "$DEFAULT_BRANCH"
else
  gh repo clone "$UPSTREAM_SLUG" "$UPSTREAM_DIR"
  DEFAULT_BRANCH=$(git -C "$UPSTREAM_DIR" branch --show-current)
fi
```

**Never assume the default branch is `main`.** Read it, as above.

**If the reused clone has uncommitted changes or is on a feature branch**, stop and report it — do not reset over someone's work in progress.

### 1.2 Check contribution policy before writing anything

```bash
ls "$UPSTREAM_DIR" | grep -iE 'CONTRIBUTING|CODE_OF_CONDUCT|GOVERNANCE'
gh repo view "$UPSTREAM_SLUG" --json hasIssuesEnabled,isArchived,licenseInfo
```

Read `CONTRIBUTING.md` if present and follow it — it outranks this skill on branch naming, commit format, DCO/CLA sign-off, changelog entries, and whether an issue must be filed first.

**Stop and ask the user if:** the repo is archived, the license does not permit the contribution, a CLA is required, or `CONTRIBUTING.md` requires discussion before a PR. Submitting into a project that does not accept drive-by PRs wastes a maintainer's time.

**If you lack push access**, fork first — `gh repo fork "$UPSTREAM_SLUG" --clone=false --remote=false` — and branch from the fork. Most upstreams are contributed to this way.

### 1.3 Branch

```bash
git -C "$UPSTREAM_DIR" checkout -b <type>/<descriptive-name>
```

Match the upstream's own branch-naming convention (`git branch -a` shows the recent shape). Name the change, not its origin — `feat/badge-status-variants`, never `feat/for-consumer-x`.

---

## Phase 2: Implement Upstream

### 2.1 Read the local change

Read the consumer's implementation and identify precisely what crosses the boundary: new API surface, new behavior, new theme or config tokens, whether this extends something existing or adds something new. **What stays behind matters as much as what goes** — consumer-specific wiring does not go upstream.

### 2.2 Learn the upstream's conventions

```bash
for f in AGENTS.md CLAUDE.md CONTRIBUTING.md README.md .cursorrules; do
  test -f "$UPSTREAM_DIR/$f" && echo "=== $f ===" && cat "$UPSTREAM_DIR/$f"
done
```

If none exist, infer conventions from the code: open the two or three files nearest to the change and match their structure, naming, test layout, and export mechanics.

Then find the upstream's own commands, whatever they are named:

```bash
cat "$UPSTREAM_DIR/package.json" 2>/dev/null | jq -r '.scripts // empty'
cat "$UPSTREAM_DIR/Makefile" "$UPSTREAM_DIR/justfile" "$UPSTREAM_DIR/Taskfile.yml" 2>/dev/null
ls "$UPSTREAM_DIR/.github/workflows/"
```

The CI workflow is the authoritative list of what must pass. Record them as `UPSTREAM_TEST`, `UPSTREAM_BUILD`, `UPSTREAM_LINT`.

**Follow the upstream's conventions, not the consumer's.** Two projects that disagree on formatting, test framework, or file layout are both right in their own repo. A PR that imports the consumer's style is a PR the maintainer has to rewrite.

### 2.3 Implement

Delegate to the `coder` skill:

```
Agent tool:
  prompt: "Load the coder skill (Skill tool: skill='coder'), then:

           In the [UPSTREAM_SLUG] repo at [UPSTREAM_DIR], implement [DESCRIPTION].

           [If confidentiality applies:]
           CRITICAL: [UPSTREAM_SLUG] is a public repository and the requesting
           project is private. NEVER reference that project's name, org, URL, or
           authors in any commit message, comment, test, or doc, and do not carry
           over its brand colors, hostnames, IDs, or copy. Describe the change on
           its own terms.

           Follow the upstream's conventions:
           - [key rules read from its AGENTS.md / CONTRIBUTING.md in 2.2]
           - [file layout for code, tests, docs, exports, as they exist there]

           Match the commit convention this repo already uses.
           Run: [UPSTREAM_TEST] && [UPSTREAM_BUILD] && [UPSTREAM_LINT]
           Do NOT create a PR."
  description: "Implement change upstream"
```

**Generalize what you move.** The upstream serves every consumer, so anything the change needs — a config value, a theme token, a default — lands upstream as a neutral default that consumers override. Copying the consumer's specific value both leaks it and makes it wrong for everyone else.

### 2.4 Verify upstream is green

Run `UPSTREAM_TEST`, `UPSTREAM_BUILD`, and `UPSTREAM_LINT` in `$UPSTREAM_DIR`. Fix failures before going further — a PR that fails the upstream's own CI will not be reviewed.

---

## Phase 3: Verify the Consumer Against the Local Build

This is what makes the contribution real rather than plausible: it proves the consumer can actually use what was written.

### 3.1 Link the local build

| Ecosystem | Link | Unlink |
|---|---|---|
| npm / yarn / pnpm / bun | `<pm> link` in upstream, then `<pm> link <pkg>` in consumer | reinstall from the lockfile |
| Python | `pip install -e <upstream>` / `uv pip install -e <upstream>` | reinstall the pinned version |
| Rust | `[patch.crates-io]` entry in the consumer's `Cargo.toml` | remove the patch entry |
| Go | `replace <module> => <upstream>` in `go.mod` | `go mod edit -dropreplace` |
| Ruby | `gem '<name>', path: '<upstream>'` in the `Gemfile` | restore the version constraint |

**Do not commit the link.** A `replace`, `[patch]`, or `path:` directive that reaches the consumer's PR points its build at a directory that exists only on this machine.

### 3.2 Confirm it works

Run the consumer's own build and tests against the linked upstream. Failures here mean the upstream API does not fit the consumer — fix it upstream and repeat, rather than working around it in the consumer.

### 3.3 Rewire the consumer

```
Agent tool:
  prompt: "Load the coder skill (Skill tool: skill='coder'), then:

           In [CONSUMER_ROOT], switch the local implementation over to the new
           API from [UPSTREAM_PKG] (currently linked to a local build).

           - Remove the local implementation, or reduce it to a thin re-export
             if genuine local extensions remain
           - Update imports across the codebase
           - Remove local config/theme values now provided upstream
           - Run the consumer's build and tests
           - Commit: refactor(<area>): use upstreamed <thing> from <pkg>
           - Do NOT push"
  description: "Rewire consumer onto upstream"
```

### 3.4 Unlink

Restore the published dependency (right column of 3.1). The consumer now holds commits written against the *new* upstream API while still depending on the *current* published version — that is expected, and Phase 5 closes the gap.

**Verify the link is gone** before moving on: `git -C "$CONSUMER_ROOT" diff` must show no `replace`, `[patch]`, `path:`, or `link:` directive.

---

## Phase 4: Open the Upstream PR

Change working directory to `$UPSTREAM_DIR` and run the normal lifecycle:

```
Skill tool: skill="dev"
```

Steps 0–4 of `dev` (auth, branch, requirements, plan, implementation) are already done. Run its PR creation, review, and CI stages — `pr-preparer`, the reviewers under `fx-review`, and `pr-check-monitor` — inside the upstream repo.

**Re-check the PR body against the confidentiality rules above before it is opened.** The `dev` lifecycle writes PR descriptions from the branch diff and commit messages, which is exactly where a consumer-specific detail survives.

Then report:

```
Upstream PR [UPSTREAM_SLUG]#[NUMBER] ready: [URL]

Changes:
- [summary]

⚠️ Do not merge the consumer PR until this one merges and a version is released.
```

**Stop here.** Phase 5 needs a merge that has not happened yet, and it is not yours to wait on silently.

---

## Phase 5: Post-Merge — Move the Consumer to the Released Version

**Runs only after the user confirms the upstream PR merged.** Do not poll for it and do not proceed on your own.

### 5.1 Confirm

```bash
gh pr view [PR_NUMBER] --repo "$UPSTREAM_SLUG" --json state -q '.state'
```

Must be `MERGED`. Otherwise stop and report.

### 5.2 Find a usable version

Determine how the upstream releases before waiting on anything:

```bash
ls "$UPSTREAM_DIR/.github/workflows/" | grep -iE 'release|publish'
gh release list --repo "$UPSTREAM_SLUG" --limit 5
```

Three common shapes:

- **Publishes a prerelease on every merge** (commit-SHA versions like `0.0.0-<sha>`, often tagged `next`/`preview`/`canary`). Fastest path — match the merge commit:
  ```bash
  MERGE_SHA=$(gh pr view [PR_NUMBER] --repo "$UPSTREAM_SLUG" --json mergeCommit --jq '.mergeCommit.oid' | head -c 7)
  ```
  then look for a published version containing that SHA. Give the publish workflow a minute or two before concluding there is none.
- **Release-PR based** (release-please, changesets, semantic-release). A release PR must merge first.
- **Manual tagging.** Wait for the maintainer.

**⛔ NEVER merge a release PR.** Those control versioning and are the maintainer's to merge — including on repos where you have write access.

If no usable version exists yet, say so plainly and stop:

> Upstream merged, but no release published yet (project uses [strategy]). The consumer PR stays blocked until [what has to happen].

### 5.3 Update, verify, commit

Update the consumer's dependency to that exact version, run its build and tests, and commit the manifest and lockfile together:

```bash
git -C "$CONSUMER_ROOT" add <manifest> <lockfile>
git -C "$CONSUMER_ROOT" commit -m "chore(deps): update <pkg> to <version>"
```

A prerelease pin is temporary. Note in the consumer PR that it should move to the stable release once one exists.

---

## Error Handling

| Error | Action |
|---|---|
| Upstream repo cannot be resolved from the manifest | Ask the user directly — do not guess |
| Clone fails | Check `gh auth status`; for a private upstream, confirm access |
| No push access to upstream | Fork and branch from the fork (1.2) |
| Upstream archived, or CLA required | Stop and ask the user |
| Reused clone is dirty | Stop — do not reset over uncommitted work |
| Upstream tests fail | Fix upstream before proceeding; never skip its CI |
| Link step unsupported for the ecosystem | Ask the user how they normally test a local build; do not invent a mechanism |
| Consumer fails against the linked build | Fix the API upstream, not around it in the consumer |
| Upstream PR CI fails | `resolve-ci-failures` in the upstream working directory |
| No release after merge | Report the strategy and what is blocking; never merge a release PR |

## Success Criteria

- Upstream PR opened against the correct repository, following that project's conventions and passing its CI
- No consumer-identifying content — names, URLs, or values — in any upstream artifact, when confidentiality applies
- Consumer verified against a local build of the upstream, with the link removed before committing
- Consumer's local implementation removed or reduced to a re-export
- Consumer dependency bumped only after the upstream merged and released
