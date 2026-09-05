---
name: learn
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. Updates the installed skill catalog from an explicit /learn request and leaves changes uncommitted for review."
---

# Learn

This skill updates the skills in this catalog based on learnings from the current conversation. It modifies `SKILL.md` definitions to prevent future mistakes or improve behavior.

## Prerequisites

### Step 0: Locate the catalog checkout

Skills are installed into an agent directory (`.claude/skills/`, `.agents/skills/`, …), but edits must land in the **git checkout** of the catalog, not in an installed copy. When `skills add` installs by symlink — the default and recommended method — the installed entry points back at that checkout.

**The invocation's own base directory is the strongest evidence of which copy ran.** A skill's prompt states the directory it was loaded from; that path, resolved through any symlink, is the copy that actually executed. Prefer it over anything the search below infers.

Otherwise, resolve it:

```bash
# Find where an installed skill from this catalog actually lives.
for base in .claude/skills ~/.claude/skills .agents/skills ~/.agents/skills \
            ~/.codex/skills ~/.config/opencode/skills ~/.cursor/skills; do
  [ -e "$base/learn" ] && printf '%s -> %s\n' "$base/learn" "$(readlink -f "$base/learn")"
done
```

From the resolved path, walk up to the repository root (the directory containing `skills/` and `.git`):

```bash
git -C <resolved-path> rev-parse --show-toplevel
```

Then verify it is the right repo and is clean:

```bash
cd <repo-root> && git remote -v && git status
```

**If nothing resolves** — the skills were installed with `--copy`, or the checkout has moved — do not edit the installed copy. Editing a copy makes the change invisible to `skills update` and it is silently reverted on the next update. Ask the user for the path to their clone of the catalog, or tell them to clone it, and abort until you have one. The same holds for any other build-artifact copy a host keeps: an edit there is overwritten by the next sync and never reaches a repo.

**If the resolved copy belongs to a different repository, the fix belongs in that repository.** Clone it (prefer SSH — HTTPS may have no credential helper configured), edit there, and leave the change uncommitted for review exactly as Step 6 requires. Do **not** silently redirect the fix into this catalog because this catalog is the repo this skill knows; the redirected edit is reviewed, merged, and completely inert.

**If several trees carry the same defect, fix the authoritative one first, then apply the same fix to the others.** A catalog cloned twice — symlinked into one agent directory and `--copy`-installed into another — will otherwise keep a stale divergent copy that some session eventually loads.

**If the working tree is dirty**, report what is uncommitted and ask before proceeding — this skill leaves its own changes uncommitted, and mixing them with unrelated work makes the diff unreviewable.

**Always tell the user which tree you edited and why.** A learning applied to the wrong copy is worse than none: it reports success and changes nothing, so the skill keeps misbehaving while everyone believes it was fixed. Name the resolved path when you report, not just the file.

### Read AGENTS.md and respect it

**CRITICAL:** Read `AGENTS.md` at the root of the catalog repo and follow every instruction it contains. It is authoritative — its rules apply to every operation this skill performs in the repo.

## Workflow

### Step 1: Analyze the Learning Request

Examine the current conversation to understand:

1. **What went wrong** - Identify the specific behavior that needs correction
2. **Root cause** - Determine which skill caused the issue
3. **Desired behavior** - Understand what should happen instead

Common scenarios:

- **Explicitly invoked skill did not load** → Verify its directory name, its frontmatter `name`, and its explicit-use description without adding semantic auto-trigger phrases
- **Skill auto-loaded without being named** → Add or repair the explicit-use boundary in its description and instructions
- **Skill produced incorrect behavior** → Add explicit prohibition to skill instructions
- **Skill missed a step** → Add the step to the skill's workflow
- **Instruction was ambiguous** → Clarify the wording

### Step 2: Locate Relevant Files

Search the catalog for relevant files:

```bash
# Find all skill definitions
find <repo-root>/skills -name 'SKILL.md' -type f

# Search for specific content
grep -rn "keyword" <repo-root>/skills/
```

Key locations:
- **Skills**: `skills/<skill>/SKILL.md`
- **Bundled resources**: `skills/<skill>/references/`, `skills/<skill>/scripts/`

### Step 3: Make Targeted Modifications

Edit the relevant files to address the learning. Follow these principles:

1. **Be specific** - Add concrete instructions, not vague guidance
2. **Use imperative form** - Write "Do X" or "Never do Y", not "You should..."
3. **Add context** - Explain why the rule exists if non-obvious
4. **Preserve structure** - Maintain existing formatting and organization

For prohibitions, use clear language:
```markdown
**CRITICAL:** Never do X because Y.
```

For required actions:
```markdown
**IMPORTANT:** Always do X before Y.
```

#### Renaming or adding a skill

The directory name is what agents actually invoke, and the spec requires the frontmatter `name` to match it. If you rename a skill:

1. `git mv skills/<old> skills/<new>`
2. Update `name:` in its `SKILL.md`
3. Update every cross-reference: `grep -rn '<old>' skills/`
4. Check the new name against the reserved names listed in `AGENTS.md` — a skill whose name collides with a host agent's built-in silently shadows it

### Step 4: No Sync Step

Symlink installs read straight through to the checkout, so edits take effect on the next skill load — there is nothing to copy or rebuild.

**If the user installed with `--copy`**, their installed copies are now stale. Tell them to run `npx skills update` once the changes are committed and pushed.

### Step 5: Verify Changes

After editing, show the diff to the user:

```bash
cd <repo-root> && git diff
```

Confirm no cross-reference was left dangling:

```bash
cd <repo-root> && grep -rn '<any-renamed-skill>' skills/
```

### Step 6: Leave for Manual Review

**CRITICAL:** Do NOT commit the changes. Inform the user:

> Changes have been made to the following files:
> - `path/to/file1.md`
> - `path/to/file2.md`
>
> Review the changes with `git diff` in `<repo-root>`.
> Commit manually when satisfied.

## Examples

### Example 1: Skill Skipped a Step

User says: "use /learn to update our sdlc skills - they should update PROJECT.md when creating PRs"

1. Locate `skills/pr-preparer/SKILL.md`
2. Add instruction to check PROJECT.md and update completed tasks
3. Show diff, leave uncommitted

### Example 2: Explicit Skill Invocation Failed

User says: "I explicitly ran /github, but the skill did not load"

1. Locate `skills/github/SKILL.md`
2. Verify the directory name, the frontmatter `name`, and the explicit-use description are correct and consistent
3. Check whether the name collides with a host agent built-in (see `AGENTS.md`)
4. Do not add generic GitHub phrases as auto-trigger conditions
5. Show diff, leave uncommitted

### Example 3: Explicit Prohibition

User says: "/learn to never leave comments on PRs"

1. Locate relevant skills (pr-preparer, resolve-pr-feedback, etc.)
2. Add explicit prohibition with rationale
3. Show diff, leave uncommitted
