# CodeRabbit

`resolve-pr-feedback` loads this file only when its Step 1 detection finds
CodeRabbit on the PR's head and CodeRabbit is in its `sources:` scope. It holds
CodeRabbit's mechanics only. The procedure — Scope Brief, triage, dispositions,
review-rule entries, convergence — is `fx-review` Steps 1–8, and none of it is
restated here.

## Identify

A CodeRabbit thread's author login contains `coderabbitai` (`coderabbitai[bot]`).
Its PR check is named `CodeRabbit`.

## Comment anatomy

CodeRabbit comments follow a structured markdown format:

```
_🧹 Nitpick_ | _🔵 Trivial_    <- severity indicator (optional)

[Main feedback text]

<details>
<summary>💡 Optional suggestion</summary>
[Expanded suggestion content]
</details>

<details>
<summary>📝 Committable suggestion</summary>
[Code block with suggested changes]
</details>

<details>
<summary>🤖 Prompt for AI Agents</summary>
[Explicit instructions for AI to follow]
</details>
```

Severity labels — `_🧹 Nitpick_`, `_🔵 Trivial_`, `🟠 Major`, `🟡 Minor` — are
CodeRabbit's own, and inputs to triage, never verdicts. A project-rule, security,
privacy or correctness defect carrying `Nitpick` still blocks.

An AI prompt or a committable suggestion says nothing about materiality: a
formatted comment can still rank immaterial, and then it is replied to with no
edit like any other.

## AI-prompt handler (blocking only)

1. Extract the prompt (§ Parsing helper).
2. **Verify the premise.** If it fails and the `blocking` disposition is the
   coordinator's, return the thread with the evidence for reclassification and
   leave it open. If you assigned the disposition yourself, treat the thread as a
   false premise — outdated or incorrect, with the `fx-review` Step 6 entry where
   a deliberate convention was misread.
3. Pass the extracted instructions **verbatim** to whoever fixes — the caller's
   batched fix or the standalone implementer (`resolve-pr-feedback` Step 3).

## Committable-suggestion handler (blocking only)

A committable suggestion attached to an immaterial observation is still
immaterial; applying it produces the push that reopens the loop.

**Verify a committable suggestion against the tree before applying it** — one
applied as written has been observed to introduce the very bug it reported. If
the premise fails, take the AI-prompt handler's route. A verified suggestion goes
to the fix (`resolve-pr-feedback` Step 3), never applied on sight.

## Parsing helper

```bash
# Content between "🤖 Prompt for AI Agents" and its closing </details>
echo "$COMMENT_BODY" | sed -n '/🤖 Prompt for AI Agents/,/<\/details>/p' | sed '1d;$d' | sed 's/^```$//'
```

If parsing fails, read the comment and work from its main text.

## Configuration check — read-only

Run once per run. **Never write `.coderabbit.yaml` or `REVIEW.md` from here** — a
configuration change mid-PR is an unrelated behavioural change inside a review
fix. Gate on the one file (`fx-setup` → `references/adoption.md` § Who gates on
what), from the repository root:

```bash
ROOT=$(git rev-parse --show-toplevel)
if [ -f "$ROOT/REVIEW.md" ] && [ ! -L "$ROOT/REVIEW.md" ]; then
  if [ -L "$ROOT/.coderabbit.yaml" ]; then echo ".coderabbit.yaml is a symlink — not read"
  elif [ -f "$ROOT/.coderabbit.yaml" ]; then cat "$ROOT/.coderabbit.yaml"
  else echo "no .coderabbit.yaml"; fi
else
  echo "REVIEW.md absent — config check skipped"
fi
```

| State | Report |
|---|---|
| `REVIEW.md` absent | Nothing — skip the check entirely; CodeRabbit reads `AGENTS.md` by default |
| `.coderabbit.yaml` absent, or `filePatterns` lacks `**/REVIEW.md` (case-sensitive) | "CodeRabbit cannot see REVIEW.md", with the instruction-layer block from `fx-setup` → `references/adoption.md` § Report. The fix is `fx-upgrade`'s M1.5 |
| `knowledge_base.code_guidelines.enabled: false` | Report it as deliberate — CodeRabbit reviews without the project's conventions — and never flip it |
| `.coderabbit.yaml` is a symlink | Report it; do not read through it |
| Enabled, with `**/REVIEW.md` in `filePatterns` | Nothing |

`enabled: true` alone is not enough: CodeRabbit's default patterns cover
`**/AGENTS.md` and `**/CLAUDE.md` but never root `REVIEW.md`. The canonical
configuration is `fx-setup` → `references/instruction-files.md` § CodeRabbit
needs explicit configuration — do not copy it here.

## Waiting, re-review and convergence

The waiter, rate-limit degradation and `NOT_CONFIGURED` handling are
`coderabbit-review`'s. CodeRabbit re-reviews every push by itself; there is no
nudge.

CodeRabbit's condition for `resolve-pr-feedback` Step 5: the most recent
`CodeRabbit` check is terminal with `success` (or `skipped` / `neutral` where the
repo configures that), and zero unresolved CodeRabbit threads —
`coderabbit-review` Step 3, conditions 1–2. The ledger condition is `fx-review`
Step 7.
