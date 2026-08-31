---
name: dev
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. Runs the complete attended SDLC lifecycle through requirements, implementation, review, CI, and finalization."
---

# Dev — SDLC Workflow Skill

> **Path note:** `[SKILLS_DIR]` below is the directory holding this skill's own folder —
> the parent of the directory containing this `SKILL.md`. Substitute its absolute path;
> every skill referenced below is installed as a sibling there.
>
> `[AGENT_DIR]` is your host's in-repo agent directory — `.claude` on Claude Code,
> `.agents` on Codex (`[SKILLS_DIR]/dev/references/host-adapters.md` § `[AGENT_DIR]`).
> Substitute it; never write a literal `.claude/` path on another host.

This skill defines the **mandatory** workflow for one explicitly invoked `/dev` lifecycle. Follow its steps in order for that lifecycle; do not infer or auto-start it from an ordinary coding request.

## Invocation Boundary (CRITICAL)

- Start this lifecycle only when the user explicitly invokes `/dev`, names `dev`, or directly asks to use the dev lifecycle.
- Do not load it merely because a request involves coding, implementation, GitHub, planning, review, or a phrase that resembles one of its stages.
- Its authority covers the lifecycle request through the Step 8 handoff. Once that handoff is complete, later user messages are standalone requests unless the user explicitly invokes `/dev` again.
- Incidental questions and operations are not new lifecycle stages. Handle status checks, branch synchronization, PR metadata edits, and an explicitly authorized merge directly when they require no substantive implementation judgment.
- A user may explicitly narrow, waive, or stop a procedural pass. Mandatory correctness, security, privacy, and merge-gate requirements remain in force, but the skill must not argue that its own orchestration mechanics outrank a direct user instruction.

## CRITICAL RULES

**Delegate the substantive roles this lifecycle owns — requirements analysis, planning, implementation, and independent review — each to its own sub-agent that loads the matching skill. Do not delegate a mechanical operation the coordinator can perform directly.**

### How to Launch Sub-Agents with Skills

A delegate is defined by four things, whatever your host calls them:

| Field | Value |
|---|---|
| handle | A short addressable name, so it can be messaged and its report attributed |
| tier | `large` / `medium` / `small`, per the size table below |
| skill | The skill it loads **before** doing anything else |
| prompt | The task, plus the Scope Brief verbatim |

In Claude Code that renders as:

```
Agent tool:
  prompt: "Load the [skill-name] skill (Skill tool: skill='[skill-name]'), then:
           [task details]"
  description: "[3-5 word summary]"
  model: "[per the size table below]"
```

Every example in this document uses that syntax. **Read it as the operation, not the only spelling** — `[SKILLS_DIR]/dev/references/host-adapters.md` maps all seven operations this skill assumes onto Claude Code and Codex, and is where a new host gets added.

**A skill is not an agent type.** Delegates are general-purpose; the skill is loaded *inside* the delegate, by its prompt. In Claude Code specifically, do not put a skill name in `subagent_type` — that parameter selects built-in agent types (`Explore`, `Plan`) and will not find a skill.

#### Pick an agent SIZE for every spawn

Choose by the **shape of the task**, not by how important it feels. Every Agent template in this document omits the model for brevity; supply it from here on every call.

| Size | Use for |
|---|---|
| **large** | Implementation (Step 4). Planning (Step 3). Requirements analysis (Step 2). Independent review. Fix agents on an **undiagnosed** failure. Anything requiring design judgment. |
| **medium** | PR preparation. Browser/test-plan verification. Fix agents handed an **exact, specified** patch. Mechanical work with a clear spec. |
| **small** | Pure inspection or summarisation with no judgment call. |

**Request the tier, not a model name.** "Spawn a large-model sub-agent" resolves to whatever the host currently offers at that tier, so this table does not go stale every time a model ships — and a hardcoded name silently becomes wrong rather than failing loudly. Where the host requires an explicit model, map the tier to its general-purpose **coding** models and nothing else; a model specialised for another domain is the wrong choice at every tier regardless of its size. In Claude Code that means the three coding tiers only — **never select `fable`.**

**Never downgrade an implementation or review agent.** Those are judgment-heavy, and a weaker agent that needs more iterations costs *more* than a stronger one that needs fewer — turn count, not per-turn price, dominates. A downgrade that adds two review rounds is a large net loss that looks like a saving.

Two constraints worth knowing rather than rediscovering:

- **Tier and reasoning effort are different dials, and not every host exposes both.** Where effort is settable per spawn (Codex), raise it too for the judgment-heavy roles, not just the tier. Where it is not (Claude Code, which inherits it from the session), the tier is the only lever you have — do not expect a `large` delegate to think harder merely because the task is hard.
- **The smallest tier may carry a reduced context ceiling.** For read-heavy roles that is a feature: it bounds context growth for free. Check your host's limit in `[SKILLS_DIR]/dev/references/host-adapters.md` rather than assuming.

`team` carries the same table for its coordinator spawns; keep the two in step.

### Coder Task Reporting (Sub-Agent Restriction)

**Where a task-reporting integration is configured** — e.g. the Coder dashboard's `mcp__coder__coder_report_task` — **sub-agents MUST NEVER send "idle" or "complete".** Only the root session reports those; a delegate may report `"state": "working"` and nothing else. Skip this entirely if no such integration exists. This prevents sub-agents from overwriting the coordinator's dashboard status and falsely signaling task completion.

<!--
duvet= docs/specs/fx-dev-authority/index.md#the-dev-coordinator-delegates-implementation-writes
duvet= type=implication
duvet# During an explicitly invoked `dev` lifecycle, the coordinator MUST delegate repository implementation edits and commits to sub-agents; it MAY perform mechanical coordination and GitHub operations directly.
-->

- ❌ NEVER author repository implementation code or documentation yourself
- ❌ NEVER create implementation commits yourself
- ❌ NEVER skip tests (`test.skip`, `it.skip`, `describe.skip` are FORBIDDEN)
- ❌ NEVER select a skill as an agent type — the delegate loads it from its prompt (in Claude Code: not via `subagent_type`)
- ✅ ALWAYS delegate requirements analysis, planning, implementation, and independent review roles
- ✅ ALWAYS instruct delegated role agents to load their named skills via the Skill tool
- ✅ ALWAYS perform straightforward status checks, branch synchronization, PR metadata updates, and an explicitly approved merge directly when delegation adds no independent judgment
- ✅ ALWAYS verify each lifecycle gate before proceeding, except where the user explicitly waives a procedural pass that is not a mandatory correctness, security, privacy, test, or merge gate
- ✅ ALWAYS fix, replace, refactor, or remove tests - never skip them
- ✅ ALWAYS carry the Scope Brief (Step 2.5) verbatim into every delegated lifecycle role and reviewer call

**FAILURE TO DELEGATE A SUBSTANTIVE LIFECYCLE ROLE = WORKFLOW FAILURE. Spawning a sub-agent for a mechanical coordinator operation is also a workflow failure.**

### Head Discipline (push once, wait once)

**Every push invalidates the head-scoped evidence collected before it.** That is why this lifecycle is ordered around a **candidate head** (Step 4.7) rather than pushing whenever something is ready.

`references/head-discipline.md` defines the rules; they are not restated here or in the steps below, which name the section they are applying. Read all five before running this workflow: § The candidate head, § Evidence is SHA-scoped, § Batch findings, § Waiter scheduling order, § Reviewer availability is cached for the run.

### Scope Discipline (STOP rule)

**When the work outgrows the request, stop and tell the user.** Do not silently
deliver more than was asked. Full rule and calibration:
`references/scope-contract.md`.

Stop when you discover the task needs materially more than its own framing
implies: subsystems the user never named, a migration or breaking change, several
PRs where one was implied, or an architectural decision the user has not made.
Report in two or three sentences — what you found, why it exceeds the request,
the cheapest path forward — offer the narrow option first, and wait. Deliver
everything unambiguously in scope first; never stop with nothing done.

The threshold moves with the Scope Brief's size signal: a `narrow` request stops
at any overrun, `normal` stops at an unmade decision or a reach beyond the named
subsystem, `open-ended` stops only at architectural forks or irreversible actions.

**Do NOT stop for work inside the request's natural boundary:** tests for code you
just wrote, docs the change invalidates, fixing a build you broke, following an
approved change document to completion, or resolving findings classified
`required-by-contract` / `regression-caused-by-change`. Over-triggering is its own
failure mode.

### Test Policy

**⛔ NEVER skip tests.** If a test cannot pass:
- **Fix it** - Update assertions to match correct behavior
- **Replace it** - Write a new test that properly validates the behavior
- **Refactor it** - Restructure to test what's actually testable
- **Remove it** - Delete entirely if it tests something that no longer exists

If tests require infrastructure (auth, database, external services), SET UP that infrastructure. Do not skip tests because setup is hard.

---

## MANDATORY STEPS (Execute in Order)

### STEP 0: GitHub Authentication

**Execute FIRST before anything else.**

```bash
gh auth status
```

If fails: STOP. Tell user to run `gh auth login`. Do NOT proceed.

---

### STEP 1: Workspace Preparation

**Create clean feature branch BEFORE any implementation.**

#### 1.1 Check for uncommitted changes

```bash
git status
```

If uncommitted changes exist:
- Ask user: "Uncommitted changes found. Stash them or abort?"
- If stash: `git stash push -m "SDLC auto-stash"`
- If abort: STOP

#### 1.2 Sync and create branch

```bash
git fetch origin
git checkout main
git pull origin main
git checkout -b <type>/<short-description>
```

Branch types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

**⛔ DO NOT PROCEED until branch is created**

---

### STEP 2: Requirements Analysis

**MANDATORY: Launch a sub-agent that loads the requirements-analyzer skill.**

```
Agent tool:
  prompt: "Load the requirements-analyzer skill (Skill tool: skill='requirements-analyzer'), then:

           Analyze requirements for: [TASK DESCRIPTION]

           - Analyze task/issue/error to understand requirements
           - Use WebSearch to research technologies
           - Use WebFetch for referenced URLs
           - Use AskUserQuestion for ambiguities
           - Analyze codebase for patterns

           Output: Complete requirements with acceptance criteria"
  description: "Analyze requirements"
```

For GitHub issues, fetch first:
```bash
gh issue view [NUMBER] --json title,body,labels,comments
```

**⛔ DO NOT PROCEED until requirements are complete**

---

### STEP 2.5: Freeze the Scope Brief and Implementation Contract, and Open the Finding Ledger

**First, build the Scope Brief.** It is the user's own framing, and it must
survive every sub-agent hop and every reviewer call. Full definition and field
rules: `references/scope-contract.md` (beside this skill).

```markdown
### Scope Brief
- **Verbatim request:** "<the user's exact words, quoted, never paraphrased>"
- **Interpreted scope:** <files, subsystems, deliverable>
- **Deliverable type:** <docs | code | spec | research | config | mixed>
- **Explicitly out of scope:** <what must NOT be touched or flagged, with reasons>
- **Size signal:** <narrow | normal | open-ended>
- **Known-and-accepted:** <deliberate states a reviewer would otherwise flag>
```

Derive **size signal** from the user's own language: "just", "real quick",
"only", "small", "minimal" → `narrow`; "thoroughly", "comprehensive", "audit",
"properly" → `open-ended`; otherwise `normal`. A `narrow` request is a budget,
not filler — honour it.

**The Scope Brief MUST be included verbatim in every downstream sub-agent prompt
and every reviewer invocation in Steps 3, 4, 4.5, 6, and 8.** A reviewer without
it reports the work you deliberately did not do, and every such finding costs a
full review cycle to filter by hand.

**Then freeze the implementation contract.** If the task is sourced from, names, or discovers a relevant `docs/changes/*.md` file, read it and the spec sections it links. Confirm implementation approval from the conversation or the change's recorded workflow state; if approval is unclear, STOP and ask the user. Record the contract path and approval evidence in the working brief. The change document, its linked specs, and all mandatory project rules form the implementation contract: the plan and coder prompt MUST map work to that contract and MUST NOT infer adjacent product or architecture work.

The coordinator owns one in-memory finding ledger for the run; reviewer sub-agents return findings to the coordinator and MUST NOT mutate the ledger concurrently. Give every finding a stable fingerprint (`category + file + line/range + normalized claim`) and record its source, first-seen revision, classification, materiality tier, disposition, and verification evidence. Classification and materiality are independent fields — see Step 4.5 for how the tier is assigned. The tier is `n/a` for a contract blocker: filter 2 stops before the bar, so a rule violation is never ranked, and inventing a tier for one is the mistake that lets it be argued down. Classify each finding exactly once as:

- **required-by-contract** — Necessary to satisfy the change document, its linked specs, or any mandatory project, security, privacy, test, or merge rule.
- **regression-caused-by-change** — A demonstrable correctness, security, privacy, or data-loss regression caused by this branch anywhere within its behavioral impact, including downstream consumers or integrations.
- **follow-up/out-of-scope** — A pre-existing issue, hardening, cleanup, product addition, architecture expansion, or improvement not required by either category above.

Fix the first two classes, and any entry that is blocking by tier — a reviewer-originated Material or Substantive finding blocks even where no written rule names it (`references/scope-contract.md` § Blocking). Deduplicate repeated or reworded findings by fingerprint and update the existing ledger entry. Record every **non-blocking** entry for the PR or later tracking without implementing it — `follow-up/out-of-scope` at tier `n/a` or `immaterial`. An entry of that class that blocks by tier is fixed like any other blocker; the class name never decides remediation. When reviewer resolvers are invoked by `/dev`, their deferred-feedback paths MUST return follow-ups to the coordinator instead of modifying task trackers in the implementation PR. To implement out-of-scope product or architecture work, first amend the change document and obtain user approval.

---

### STEP 3: Planning

**MANDATORY: Launch a sub-agent that loads the planner skill.**

```
Agent tool:
  prompt: "Load the planner skill (Skill tool: skill='planner'), then:

           [PASTE THE STEP 2.5 SCOPE BRIEF VERBATIM HERE]

           Create implementation plan for:

           [REQUIREMENTS FROM STEP 2]

           - Keep the plan inside the Scope Brief; if the work cannot be done
             within it, stop and report that rather than planning around it
           - Break into atomic steps
           - Identify files to modify
           - Determine test requirements
           - Flag if multiple PRs needed
           - Treat the approved change document as the implementation contract
           - Do not include non-blocking follow-up/out-of-scope work, or expand product/architecture, without an approved amendment

           Output: Numbered implementation steps"
  description: "Plan implementation"
```

For GitHub issues, also update issue:
```
Agent tool:
  prompt: "Load the issue-updater skill (Skill tool: skill='issue-updater'), then:

           Update issue #[NUMBER] with plan. Add label: in-progress"
  description: "Update issue"
```

**⛔ DO NOT PROCEED until plan exists**

---

### STEP 4: Implementation

**MANDATORY: Launch a sub-agent that loads the coder skill.**

```
Agent tool:
  prompt: "Load the coder skill (Skill tool: skill='coder'), then:

           [PASTE THE STEP 2.5 SCOPE BRIEF VERBATIM HERE]

           Implement this plan:

           [PLAN FROM STEP 3]

           Requirements:
           - Stay inside the Scope Brief; if implementation cannot be completed
             within it, stop and report rather than widening the change
           - Atomic commits (format: type(scope): message)
           - Follow existing patterns
           - Run tests
           - Treat the approved change document as the implementation contract
           - Do not implement non-blocking findings, or expand product/architecture, without an approved amendment (an entry blocking by tier is fixed whatever its class)
           - TASK TRACKING RIDES WITH THE IMPLEMENTATION: if [DOC_PATH or 'none']
             tracks this work, mark the items this change actually completes
             (- [x] Task name), and if this change completes the whole document
             flip its Status to complete and sync docs/index.yml and docs/index.md.
             Same commit series as the code — never a separate later commit.
           - Do NOT create PR"
  description: "Implement changes"
```

Identify `[DOC_PATH]` before spawning — the change document or task list named in the request, or:

```bash
grep -rl "keyword from task" docs/changes/ docs/tasks.md 2>/dev/null || true
```

**Tracking updates belong here, not at finalization** — step 5 of `references/head-discipline.md` § The candidate head. Nothing about them needs the PR to exist.

Verify commits exist:
```bash
git log --oneline -5
git diff main --stat
```

**⛔ DO NOT PROCEED until commits exist on feature branch**

---

### STEP 4.5: Pre-PR Self-Review (simplify → review → Codex)

**MANDATORY: Run one complete local review matrix before creating the PR.** Run each available pass once in order against the current `HEAD`, record the revision that each channel reviewed, and classify its findings before accepting fixes. If `/simplify` edits directly, retain only changes that satisfy the contract classification and record the resulting revision before starting the next pass.

**Run all three passes, then fix once** (`references/head-discipline.md` § Batch findings). Do not fix and re-run between passes. This is the last stage where a fix costs nothing but a local rerun, so spend the thoroughness here rather than after the push.

**Every pass below follows `fx-review`** — the canonical review procedure
(Skill tool: `skill="fx-review"`), which each reviewer skill loads first. This
step does not restate it. In particular: **every pass MUST receive the Step 2.5
Scope Brief verbatim**, and a pass run without it is incomplete — rerun it with
the brief rather than filtering its output.

**1. `/simplify`** — reuse, quality, efficiency cleanup:

```
Skill tool: skill="simplify", args="<Scope Brief>"
```

Reviews changed code for **reuse** (duplicated logic), **quality** (copy-paste, leaky abstractions, nesting), and **efficiency** (redundant computation, missed concurrency).

**2. `/code-review`** — correctness bugs in the diff:

```
Skill tool: skill="code-review", args="<Scope Brief>"
```

**3. Codex (local, via `codex`)** — independent one-shot branch review:

```
Skill tool: skill="codex-review", args="<Scope Brief>"
```

**Codex is the ONLY local reviewer.** There is no local CodeRabbit pass — the `cr` CLI is not used anywhere in this SDLC. CodeRabbit applies only at the PR level in Step 6.3, and only when the repo's GitHub App is installed.

The Codex CLI takes the scope as its review prompt, so this pass is the one where a missing brief is most expensive — it will confidently report every deliberate omission. If the `codex` CLI is unavailable or not authenticated, report it once and proceed without this pass. NEVER run `codex login`.

#### Remediation and Delta Verification

**Record each finding's class, not just its location** (`references/scope-contract.md` § Fix the class, not the instance). A reviewer reports the instance it read; the ledger entry names the defect pattern and every site in the change's surface that exhibits it, so a fix closes the class rather than buying the next cycle its input. A ledger entry is not resolved while a sibling of its class is open, and a reviewer MUST NOT be re-run with a class half-closed.

Fix every **blocking** ledger entry (`references/scope-contract.md` § Blocking): everything classified `required-by-contract` or `regression-caused-by-change`, plus any entry blocking by tier — a reviewer-originated Material or Substantive finding blocks even where no written rule names it. After a fix commit:

1. Rerun the reviewer or check that originated the blocking finding.
2. Rerun tests affected by the delta.
3. Rerun another reviewer only when the delta touches the risk area that reviewer covered or invalidates its recorded evidence.

Do not restart the full matrix merely because `HEAD` changed. Deduplicate repeated or reworded findings against the ledger; they do not start a new cycle. When `/dev` invokes reviewer subskills, this contract classification and bounded stopping policy takes precedence over generic instructions to resolve every actionable finding or rerun until clean.

**The materiality bar applies to judgment-originated findings only** — things a reviewer raised on its own reading, rather than violations of a rule the project wrote down (`references/scope-contract.md`). One of those must clear the bar before it can be treated as blocking. Materiality is a **separate ledger field**, not a fourth classification — every entry still carries exactly one of the three classifications above, plus a materiality tier. An observation that would change nothing if it shipped uncorrected is recorded as `follow-up/out-of-scope` with materiality `immaterial`, and never triggers a rerun.

**Rule violations are blocking regardless of materiality.** Anything Step 2.5 defines as `required-by-contract` — project, security, privacy, test and merge rules the project wrote down — is blocking by virtue of being a rule, whatever its direct behavioural impact. The contract filter runs before the bar, exactly as `references/scope-contract.md` § Three filters specifies, so the coordinator can never demote a violation the reviewer correctly marked blocking. Two shapes in particular are non-findings and MUST NOT enter the ledger **at all**, at any tier — not as blocking, and not as an immaterial entry either: a missing entry in a list the artifact does not present as exhaustive, whether it says "for example" or declares the list illustrative, and a decision the artifact records with its rationale **where the disagreement is about preference**. Recording them as immaterial keeps the churn and merely renames it. The second, raised again in the very next pass, is an escalation to the user rather than a third cycle (`references/scope-contract.md` § Convergence defines that trigger) — but a recorded rationale never makes a decision safe. The full carve-out is in `references/scope-contract.md` § Three things that are not findings and is not narrowed here: if the decision itself leaks a credential or private identifier, loses data, violates a security or privacy invariant, **or contradicts a contract the project mandates**, it is `required-by-contract` and stays blocking.

#### Local-Convergence Stopping Condition

Proceed to Step 4.6 when all of the following are true:

1. Every **blocking** ledger entry is resolved with evidence. Blocking is defined once, in `references/scope-contract.md` § Blocking; this gate does not restate it.

   **A finding excluded at filter 1 can never carry a Material or Substantive tier.** The two fields are assigned by different filters and cannot disagree, so that one pair is illegal. Note the rule is about the *filter*, not the class name: `follow-up/out-of-scope` holds entries of two different origins, and all three tiers can be legal for it — a finding excluded at filter 1 never reaches the bar, so its tier is `n/a`; an in-scope observation that reached filter 3 and failed it is tier `immaterial`. A finding that reaches the bar at all is one no written rule covers — a written-rule violation stops at filter 2, unranked, as a contract blocker with tier `n/a` and class `required-by-contract`, and never reaches filter 3. So a finding ranked Material or Substantive is in scope by construction, is a defect in work this change actually did, and is *not* `required-by-contract`: it is `regression-caused-by-change` where the branch caused a regression, and otherwise — a two-way ambiguity in something this change wrote, say — it stays in this class and **still blocks, by tier**. The classification answers what obliges the fix; the tier answers whether it blocks, exactly as the stopping condition below states. What is illegal is that tier pair on a finding excluded at filter 1, which never reached the bar. **The filter outcome decides the resolver disposition — not the class name, and not the tier** (§ Resolver dispositions). Tier `n/a` is carried by two unrelated outcomes and so cannot pick one: a contract blocker is `n/a` because filter 2 stopped before the bar, and it is **blocking** — fixed and pushed; a finding excluded at filter 1 is `n/a` because it never reached the bar, and it is **deferred**, replied to with the exclusion. Tier `immaterial` settles as `immaterial`, replying with the materiality reasoning. Read the outcome, never the tier alone. Citing an exclusion for an in-scope observation invents one that does not exist. If you are about to record that pair, one of the two filters was misapplied — re-run them rather than writing an entry the gate can neither clear nor waive. Materiality never promotes an out-of-scope finding back into scope (`references/scope-contract.md` § Three filters); this rule is that principle applied to the ledger.
2. Contract-required tests and tests affected by the latest delta pass.
3. Every available review channel completed its initial pass or has a documented permitted degradation.
4. The review has **converged** as `references/scope-contract.md` § Convergence defines it — no blocking finding left unresolved, ledger-wide, not merely none new in the latest pass. As an additional gate, that state is confirmed by one verification pass over the latest affected delta.

`follow-up/out-of-scope` entries with tier `n/a` — the class and the tier together, which is what identifies a filter-1 exclusion — and immaterial observations, do not block PR creation. Tier `n/a` alone does not qualify: a `required-by-contract` entry carries it too, and blocks. Nothing else is waivable here: a reviewer-originated Material or Substantive finding blocks even though no written requirement names it, exactly as item 1 above and `references/scope-contract.md` § Blocking say. Each review channel caps at the single bound defined in `references/scope-contract.md` § The iteration bound, which counts the initial pass as iteration 1 and which no skill restates or overrides — count reviewer invocations in total, not remediation rounds on top of the first pass. **Convergence is the goal, and the bound is a runaway backstop, not a target.** Reaching it means the loop failed to converge; report it that way. Reaching the bound is a failure to converge and does not authorize Step 5. STOP, report the per-pass trend and everything still open, and let the user decide whether to create the PR — including when every remaining entry is `follow-up/out-of-scope` with tier `n/a`. A blocking entry at the bound is always an escalation; the bound never waives one. A contract amendment may change product scope, but it cannot waive mandatory correctness, security, privacy, testing, or merge rules.

**Do not spend the headroom.** The bound is far above what a healthy channel needs; the signals that should actually end a loop — converged, and the same disagreement in successive passes (`references/scope-contract.md` § Convergence) — fire in single digits, as does a rising blocking count of one class, which is a cause to fix rather than an exit: address the cause and continue, and escalate only where the cause is a design choice with two defensible answers (`references/scope-contract.md` § The iteration bound). A round that resolves only immaterial items is churn at any iteration number, and the convergence rule already forbids it.

---

### STEP 4.6: Test Plan Construction and Verification (MANDATORY, PRE-PR)

**Verification happens before the PR exists** — step 4 of `references/head-discipline.md` § The candidate head. Everything here runs against the local branch, so only the items that genuinely require a human or an external system survive into Step 5.5.

This step is MANDATORY for every change, not only web/UI ones. Backend changes, platform integrations, CLI tools, and infrastructure changes all have test plans.

#### 4.6.1 Construct and classify the test plan

Write the test plan now — it becomes the `## Test plan` section of the PR body in Step 5. Derive it from the Step 3 plan and the branch diff (`git diff main --stat`): each item is one verification target.

**Classify each item:**

| Category | Description | Action |
|----------|-------------|--------|
| **Browser-verifiable** | Testable via Playwright MCP (UI routes, visual changes, interactions) | Step 4.6.2 |
| **Programmatically verifiable** | Testable via CLI, API calls, log inspection, or automated scripts | Step 4.6.3 |
| **Manual-only** | Requires external systems, user accounts, or physical interaction (e.g. "send a Discord message", "check email") | Deferred to Step 5.5 — annotate, never silently drop |

#### 4.6.2 Browser Verification (for browser-verifiable items)

**Skip this sub-step if no test plan items are browser-verifiable.**

Detect if browser verification is possible:

```bash
WEB_FILES=$(git diff main --name-only | grep -E '\.(tsx|jsx|vue|svelte|html|css|scss|less)$' || true)

HAS_WEB_STACK=false
for cfg in vite.config.ts vite.config.js next.config.js next.config.ts next.config.mjs nuxt.config.ts svelte.config.js angular.json astro.config.mjs; do
    if [[ -f "$cfg" ]]; then
        HAS_WEB_STACK=true
        break
    fi
done
```

If web changes exist and browser-verifiable items are present, launch the verify-web-change sub-agent. It works from the branch diff against `main`, so it needs no PR:

```
Agent tool:
  prompt: "Load the verify-web-change skill (Skill tool: skill='verify-web-change'), then:

           Verify the following Test Plan items on the current branch [BRANCH]
           (no PR exists yet — work from the branch diff against main):

           [BROWSER-VERIFIABLE TEST PLAN ITEMS]

           For each item:
           1. Navigate to the relevant page/route
           2. Use Playwright MCP snapshots to verify the element/behavior exists
           3. Test any interactions described in the test plan item
           4. Check for console errors
           5. Report PASS/FAIL per item with evidence (what you observed)

           Output: A list of each test plan item with its result (PASS/FAIL/SKIPPED) and evidence."
  description: "Verify web changes in browser"
```

#### 4.6.3 Programmatic Verification (for programmatically verifiable items)

**Skip this sub-step if no test plan items are programmatically verifiable.**

Run the verification directly:

- Check test output: `bun --bun run test` — confirm relevant tests pass
- Inspect logs: check dev server output for expected behavior
- Call APIs: use `curl` or similar to verify endpoint behavior
- Check database state: verify schema/data changes applied correctly

Record PASS/FAIL per item with evidence.

#### 4.6.4 Handle Failures

If any item failed, fold its failures into the Step 4.5 ledger and fix them **with the rest of the current batch** — one fix agent, one commit series, not one push per failure:

```
Agent tool:
  prompt: "Load the coder skill (Skill tool: skill='coder'), then:

           Fix these verification failures:
           [FAILURE DETAILS]
           Commit locally. Do NOT push — the branch is not yet at its candidate head."
  description: "Fix verification failures"
```

Re-run only the verification whose evidence the fix invalidated, plus the Step 4.5 passes and tests the delta invalidated — Step 4.5's remediation rules apply here unchanged, and a fix nothing reviewed is not converged.

**Maximum 2 fix iterations, and the bound is an escalation, not a bypass.** If a non-manual item still fails after 2 attempts, **STOP and report it to the user** with what fails, what the two attempts changed, and the cheapest path forward. Do not open the PR on the strength of having hit the bound: a failed browser or programmatic item is a known defect, and no later step accepts one — the Step 8.1 merge gates require every test plan item verified, user-confirmed, or manual-only, and "failed twice" is none of those. The user may accept the failure explicitly, in which case record it in the ledger as accepted-by-user with their reason and carry it into the PR body annotated `— FAILED: <reason> (accepted by user)`. Only that recorded acceptance lets the item past the gate.

Record every item's result — they are written into the PR body in Step 5, already checked off.

**⛔ DO NOT PROCEED until every browser-verifiable and programmatically verifiable item has a recorded result**

---

### STEP 4.7: Freeze the Candidate Head

**This is the last step that may change the tree before hosted review and CI.** Confirm, in order:

1. Every blocking ledger entry from Step 4.5 is resolved and the local matrix has converged.
2. Step 4.6 recorded a result for every non-manual test plan item.
3. **Task tracking is already committed** — the change document, `docs/tasks.md`, `docs/index.yml`, and `docs/index.md` reflect what this branch completes, from the Step 4 commits. If it is missing, send the Step 4 coder back for it **now**, before the push (the coordinator never authors it — see CRITICAL RULES); it must never become a post-gate commit.
4. Generated files, lockfiles, and snapshots are regenerated and committed.

Then push and record the SHA:

```bash
git push -u origin HEAD
git rev-parse HEAD    # ← the CANDIDATE HEAD; every review and CI result is evidence about this SHA and no other
```

Record the candidate head in the ledger. From here on `references/head-discipline.md` § Evidence is SHA-scoped and § Batch findings govern every result you read and every fix you push; each later push replaces the candidate head.

---

### STEP 5: Pull Request Creation

**MANDATORY: Prepare the PR directly from the coordinator, optionally loading `pr-preparer` in the coordinator session. Do not spawn a sub-agent solely to push a branch or create/edit PR metadata. ALL PRs MUST be created READY FOR REVIEW — never as drafts.**

**⛔ NEVER use the `--draft` flag. NEVER create draft PRs.** Draft PRs have repeatedly been used as an excuse to skip downstream steps (reviewer waits, CI monitoring, CodeRabbit/Copilot resolution). The SDLC ALWAYS executes the full review/CI cycle from PR creation onward — opening as draft defeats this. If the work isn't ready for review, don't open the PR yet.

**Before creating the PR, identify related spec and change documents:**

```bash
# Find related change documents (check if task was sourced from a change doc)
ls docs/changes/ 2>/dev/null
# Find related specs
ls docs/specs/ 2>/dev/null
cat docs/index.yml 2>/dev/null
```

If the work was driven by a specific change document or spec, note the paths for inclusion in the PR description.

```
Skill tool: skill="pr-preparer", args="
           Create PR (ready for review, NOT draft) for current branch.
           Task: [ORIGINAL TASK]
           Summary: [WHAT WAS IMPLEMENTED]

           Spec/Change context (include in PR body if applicable):
           - Spec: [SPEC_PATH or 'none']
           - Change: [CHANGE_DOC_PATH or 'none']

           CRITICAL: Do NOT pass --draft. The PR must be opened ready for review so
           CI, Copilot, and CodeRabbit run from the start.
           - The branch is already pushed at its candidate head [SHA] (Step 4.7).
             Do NOT commit or amend anything — create the PR on that exact SHA.
           - Create PR with: gh pr create  (NO --draft flag)
           - Body MUST carry the Step 4.6 Test plan with its recorded results:
             verified items already '- [x]', failed items the user accepted
             '- [ ] … — FAILED: reason (accepted by user)', manual-only items
             '- [ ] … — requires manual testing'. An unaccepted failure must not
             reach here at all — Step 4.6.4 escalates it instead.
             [PASTE THE STEP 4.6 TEST PLAN WITH RESULTS]
           - Include links to related spec/change docs in the PR body
             (use relative paths from repo root, e.g. docs/specs/auth/ or docs/changes/0003-add-oauth.md)
           - Do NOT put spec/change references in the PR title — not as a number,
             slug, or path, even when the PR finalizes a change doc. Describe the
             work itself in the title; reference the doc by path in the body only.
           - ⛔ NEVER put '#<number>' in the PR title ('#4', '(#4)', '#123')
             unless N is a REAL existing PR/issue on the target repo that this PR
             references. On squash-merge the title becomes the commit subject,
             where '#N' auto-links to PR/issue #N. NEVER use '#N' for an
             implementation wave, phase, step, or change-doc number, and NEVER
             pre-add a '(#N)' suffix (GitHub appends the real PR number at squash
             merge). No waves/phases/steps in the title at all — those go in the
             body. See the github skill's '#<number> PR-Title Rule'.
           - Reference related issues
           - Do NOT include any 'this is a draft' / 'draft for review' language
             anywhere in the title or body
           - Return PR number and URL"
```

**Capture the PR number for remaining steps.**

**⛔ DO NOT PROCEED until PR is created (as ready for review)**

---

### STEP 5.5: Test Plan Reconciliation (MANDATORY)

Step 4.6 already verified everything verifiable without a PR, and Step 5 wrote those results into the PR body. This step handles only what a PR is actually needed for, and it must not produce a push.

#### 5.5.1 Confirm the body matches the recorded results

```bash
gh pr view [PR_NUMBER] --json body --jq '.body'
```

Every browser-verifiable and programmatically verifiable item must already carry its Step 4.6 result. If the section is missing or does not match, fix it with `gh pr edit` — a PR-body edit does not change the head, so it costs nothing.

#### 5.5.2 Manual-only items

**⛔ NEVER silently skip manual-only test plan items.**

For items requiring external services, physical devices, or user accounts, you MUST:

1. **Tell the user** which items require their manual verification
2. **Explain what to test** — be specific about the steps
3. **Ask them to confirm** each item passes or fails
4. **Collect their response before the Step 8.1 merge gates** — see below; do not idle on it

Example:
```
The following test plan items require manual verification:
- [ ] Send a message to the Discord bot and verify the typing indicator appears immediately
- [ ] Confirm the typing indicator stays active for responses > 10 seconds

Please test these and let me know the results.
```

**Post the request, then keep working.** Launch Step 6.3's reviewer waiters and continue; collect the user's answer on a wake rather than idling for it, so their reply and the reviewers' latency overlap instead of stacking. Items still unanswered are annotated `— requires manual testing`, and the user's confirmation is collected before the Step 8.1 merge gates.

#### 5.5.3 Update the PR body

```bash
BODY=$(gh pr view [PR_NUMBER] --json body --jq '.body')
```

Per item:
- **Verified (pass)**: `- [x]`
- **Verified (fail)**: leave `- [ ]` and append `— FAILED: [reason]`. A failure the user has not explicitly accepted **blocks the merge gates** — it is not an annotation you may ship past them (Step 4.6.4)
- **Verified (fail), accepted by user**: leave `- [ ]` and append `— FAILED: [reason] (accepted by user)`
- **Manual — confirmed by user**: `- [x]` and append `(manually verified)`
- **Manual — not yet verified**: leave `- [ ]` and append `— requires manual testing`

```bash
gh pr edit [PR_NUMBER] --body "$UPDATED_BODY"
```

#### 5.5.4 Handle failures

A failure here is a defect that escaped Step 4.6, so treat it as one more input to the current batch rather than its own cycle: record it in the ledger and let it ride with the Step 6.2 fix push (`references/head-discipline.md` § Batch findings). Only a failure that blocks every other channel justifies a push of its own. **Maximum 2 fix iterations**, counted together with Step 4.6's — and as there, reaching the bound is an escalation: STOP, report the failing item to the user, and let them decide. An item they explicitly accept is annotated `— FAILED: <reason> (accepted by user)`; an unaccepted failure blocks the merge gates.

Re-verify only the item that failed, on the new head.

**⛔ DO NOT REACH THE STEP 8.1 MERGE GATES until every test plan item is verified, explicitly accepted by the user as a known failure, confirmed by the user as a manual pass, or annotated as requiring manual testing.** A non-manual item that simply failed is none of those and blocks. Waiting on a manual-only *answer* never blocks Step 6 — post the request and proceed.

---

### STEP 6: Review & Quality

**MANDATORY: Execute ALL sub-steps.**

**The sub-step numbers are stable identifiers other skills reference, not a running order.** This step runs as a loop, and 6.2 is entered from a wake, never from the clock:

1. **6.1** — costs no push and needs nobody, so it runs first. Record its findings in the ledger.
2. **If 6.1 produced a blocking finding, fix it now** — one **6.2** pass, one push, and that SHA becomes the candidate head. Do this **before** launching anything in 6.3: a hosted review started on a head you already know must change is a full reviewer cycle spent on a diff that will not survive. Nothing is waiting yet, so this fix costs nothing but the push it was always going to need.
3. **6.3's waiter launch**, on a head with no known blocking finding. The hosted reviewers are the long pole, so from here on nothing waits on them that could have gone first.
4. **On each reviewer wake** — read that log, classify its threads (6.3, per-reviewer steps 1–2), then re-enter **6.2 once** for everything currently on the table across every channel, and push once.
5. **Only after that push** do the resolvers run, with their blocking entries annotated `already fixed in <sha>`. A resolver is never invoked with an un-fixed `blocking` disposition, because its own blocking path pushes independently — the per-reviewer push this ordering exists to prevent.
6. **The push in 4 created a new head, so re-cover it** (6.3, per-reviewer step 4) before repeating from 4 on the next wake.

If a wake arrives while nothing else is outstanding and its channel is the only one with findings, 6.2 still runs once for that channel — a batch of one is not a violation. What is forbidden is fixing channel A, pushing, and then fixing channel B (`references/head-discipline.md` § Batch findings).

#### 6.1 Self-Review — delta and integration only

**The branch was already reviewed at Step 4.5. Do not restart a generic code-quality review here.** The local matrix ran `/simplify`, `/code-review`, and Codex against this same code with the same Scope Brief; a second broad pass rediscovers the same ground, costs a full cycle, and its findings are indistinguishable from new ones.

This pass verifies only the three things that Step 4.5 could not:

1. **The pushed diff matches the reviewed SHA** — the candidate head from Step 4.7 is what the PR actually contains:
   ```bash
   git rev-parse HEAD
   gh pr view [NUMBER] --json headRefOid --jq '.headRefOid'   # must equal the candidate head
   ```
2. **PR metadata is accurate** — title, body, linked spec/change docs, and the test plan describe what the diff does.
3. **No integration-only issue appeared** — conflicts with `main` merged since the branch started, cross-PR interactions in a multi-PR change, or anything only visible with the change in its target context.

Run a full `pr-reviewer` pass **only** when the diff changed materially since Step 4.5 converged — a hosted-reviewer fix push that touched new files or new behaviour, not a one-line correction:

```
Agent tool:
  prompt: "Load the pr-reviewer skill (Skill tool: skill='pr-reviewer'), then:

           [PASTE THE STEP 2.5 SCOPE BRIEF VERBATIM HERE — the reviewer must
            know what was asked for before it reads the diff, and must report
            out-of-scope findings as deferred rather than blocking]

           Review PR #[NUMBER]. The branch already passed a full local review
           matrix at revision [SHA REVIEWED AT STEP 4.5] (simplify, code-review,
           codex-review) with all blocking findings resolved. Review the delta
           since that revision, plus integration concerns only:
           - Correctness of the delta
           - Test coverage of the delta
           - Security issues in the delta
           - Interaction with main and with sibling PRs

           Do NOT re-review code unchanged since [SHA] — it has been reviewed.

           Output: Issues found (if any), each marked in-scope or deferred"
  description: "Review PR delta"
```

The coordinator MUST classify and deduplicate these findings in the Step 2.5 ledger before invoking a coder. Pass every **blocking** entry to implementation and nothing else (`references/scope-contract.md` § Blocking) — which includes a `follow-up/out-of-scope` entry blocking by tier, and excludes an entry that is not blocking. Select on blocking, never on the tier: `n/a` marks a contract blocker (filter 2 stopped before the bar) just as it marks a filter-1 exclusion, so dropping every `n/a` entry drops every mandatory rule violation.

#### 6.2 Batched Fix Pass

**Run this once per head, after draining every channel that has already reported** — 6.1, each hosted reviewer whose waiter has woken, Step 5.5 verification failures, and any CI failure already known for this head. Classify and deduplicate the whole set, sweep each finding's class, then spawn **one** fix agent for the entire blocking set:

```
Agent tool:
  prompt: "Load the coder skill (Skill tool: skill='coder'), then:

           Fix only these blocking issues in PR #[NUMBER], in one commit series:
           [EVERY BLOCKING LEDGER ENTRY FROM EVERY CHANNEL THAT HAS REPORTED —
            REQUIRED-BY-CONTRACT, REGRESSION-CAUSED-BY-CHANGE, AND ANY ENTRY
            BLOCKING BY TIER]

           Do not implement ledger entries that are not blocking. Judge that by
           the blocking flag, not the tier: a required-by-contract entry also
           carries tier n/a, and it MUST be fixed.
           Push once, at the end."
  description: "Fix review issues"
```

**Do not hold the batch open for a channel that has not reported** (`references/head-discipline.md` § Batch findings) — late findings are the next batch, against the new head. After the push, record the new SHA as the candidate head and supersede every outstanding wait bound to the previous one.

Then invoke each reviewer's resolver to settle its threads, passing its blocking entries annotated `already fixed in <sha>` (`references/scope-contract.md` § Resolver dispositions). The resolvers reply, resolve, and record `REVIEW.md` entries — they do not edit or push again. Letting two resolvers fix in parallel instead races them on the same branch and buys two CI cycles for one round of feedback.

#### 6.3 Automated Reviewer Wait (Copilot + CodeRabbit + future)

**MANDATORY: Wait for and resolve EVERY automated reviewer configured on the repo.** Copilot and CodeRabbit are the two we know about today; future integrations slot in here. Reviewers are **independent feedback channels** with different latencies (Copilot 85 s to 12 m 42 s observed — do not budget for it being quick; CodeRabbit 2–10+ min and re-runs after every push).

> **CodeRabbit is PR-level only.** There is no local CodeRabbit pass — Step 4.5 runs Codex alone. CodeRabbit applies here when the repo's GitHub App auto-reviews PRs, and its waiter reports `STATUS=NOT_CONFIGURED` when it does not, which is the common case and is terminal. Prefer a passing check and resolve received feedback; if CodeRabbit rate-limits, resolve what it already delivered — blocking findings fixed, every posted thread settled — then record `skipped (rate-limited)` and continue without blocking.

##### Reviewer-by-reviewer skills

| Reviewer | Skill | Notes |
|----------|-------|-------|
| GitHub Copilot | `copilot-review` | Auto-reviews; we explicitly request via API as a defensive belt. Does NOT re-review on push by default. |
| CodeRabbit | `coderabbit-review` | PR-level only — there is no local pass. Applies when the GitHub App auto-reviews PRs: re-reviews after pushes and exposes state via the `CodeRabbit` check. Classify new feedback in the shared ledger and settle its threads within the bounds below. `STATUS=NOT_CONFIGURED` means the App is absent — report once and skip. |

##### Run every waiter concurrently — there is no mode selection

**⛔ Launch each configured reviewer's wait script concurrently, each redirecting to its own log file.** Take the shape of the wait from `references/host-adapters.md` § Long waits — on Claude Code it is one message with every call `run_in_background: true`, woken per reviewer by its completion notification, and spawning sub-agents for the wait buys nothing; on Codex the same table says to delegate each waiter to a teammate and `wait_agent` on it. Either way the concurrency is the same and there is no "can I spawn sub-agents?" branch to agonise over: root session, `team` coordinator, and sub-agent all follow their host's row. **Where the row makes each waiter a child, those children spend the host's concurrency slots** — Codex has three for teammates, so two reviewer waiters already take two of them. That is the other reason the CI wait is Step 7 rather than a third child launched here: it would leave no slot for the fix work its own result might require. Launch at most three waiters at a time and reconcile between batches; a spawn past the limit queues, and a queued waiter looks exactly like a hung one.

**Reviewer waiters go first; the CI waiter is Step 7 and waits its turn** (`references/head-discipline.md` § Waiter scheduling order).

**Skip a reviewer whose absence this run already established** (`references/head-discipline.md` § Reviewer availability is cached for the run). It matters most under `team`, which runs many PRs against one repository.

```bash
# Claude Code spelling: both in ONE message, both run_in_background: true.
# On another host, same two waiters, that host's shape (§ Long waits).
mkdir -p [AGENT_DIR]/team/waits && \
bash [SKILLS_DIR]/copilot-review/scripts/wait-for-copilot-review.sh [PR_NUMBER] \
     > [AGENT_DIR]/team/waits/copilot-[PR_NUMBER].log 2>&1

mkdir -p [AGENT_DIR]/team/waits && \
bash [SKILLS_DIR]/coderabbit-review/scripts/wait-for-coderabbit-review.sh [PR_NUMBER] \
     > [AGENT_DIR]/team/waits/rabbit-[PR_NUMBER].log 2>&1
```

**Never run a waiter in a call that cannot outlive it.** On Claude Code that means never in the foreground: the Bash tool caps a foreground `timeout` at 600 000 ms, below every waiter's 900 s budget, so the call is killed mid-poll, printing no STATUS and no exit code, and the caller then re-runs it blindly. Every host has some equivalent ceiling — Codex yields `exec_command` after 30 s — which is why `references/host-adapters.md` § Long waits gives each one a shape that survives the budget. **Never launch one without the redirect**: the cycle is driven by what the script prints.

###### Then, per reviewer, on its wake

1. Read the log and branch on its `STATUS=` line (each reviewer skill documents its own table; the five states are shared):
   - `TERMINAL_PASS` / `TERMINAL_FAIL` — settled. Do **not** re-run for a better answer.
   - `PENDING` — not a verdict and not a failure. Re-running is safe if you still need it. **Never** record it as "no findings" or "CI passed".
   - `NOT_CONFIGURED` — that reviewer does not apply to this repo. Terminal: report once, proceed without it, never retry.
   - `ERROR` — the wait never started. Report it.
2. Read its unresolved threads and classify them in the shared ledger **before** invoking any resolver. Neither Copilot nor the CodeRabbit GitHub App accepts a scope prompt, so the brief cannot reach them — you apply it at triage. Record the SHA each result observed; a result with no SHA is not evidence (`references/head-discipline.md` § Evidence is SHA-scoped).
3. **Fix before you dispatch.** Take every blocking entry this wake produced, together with every other channel's outstanding blocking entries, through **one** Step 6.2 pass, and push once. Then invoke each reviewer's resolver, passing a disposition for every thread that carries a finding — `blocking` annotated `already fixed in <sha>`, `immaterial`, or `deferred` (`references/scope-contract.md` § Resolver dispositions) — so every one of them is settled without a further edit or push. A thread whose premise you verified and rejected is listed as undisposed with the reason, not forced into one of the three. Handing a resolver an un-fixed `blocking` disposition puts it on its own fixing path, which pushes per reviewer — the churn this ordering exists to prevent.
4. **After the Step 6.2 push** — that push, not a resolver's, is what moves the head under this ordering — record the new SHA as the candidate head and re-cover it:
   - **Relaunch the waiter of every reviewer whose evidence the delta invalidated**, and only those. Do not restart a reviewer the delta did not touch merely because `HEAD` changed. **Copilot does not re-review a push on its own** — its waiter must be relaunched, or the fix you just pushed ships unreviewed by it; CodeRabbit re-reviews by itself and its waiter is relaunched only to observe that.
   - On the next wake, inspect only feedback added or changed since that reviewer's previously reviewed SHA, and classify and deduplicate it in the shared ledger.
   - **Any CI wait outstanding for the prior SHA is superseded** — stop it, reclaim its slot, and never read its verdict as evidence about this head.
5. Stop when the channel has **converged** per `references/scope-contract.md` § Convergence — no blocking finding left unresolved, ledger-wide — confirmed by one latest-delta pass, and every required reviewer thread is settled.

Never let a reviewer's findings reach an implementer before you have classified them.

##### Bounded delta review

Fix every **blocking** finding and only those (`references/scope-contract.md` § Blocking), whatever its ledger class. Record the non-blocking remainder without implementing it, and settle its thread with the disposition that actually fits (`references/scope-contract.md` § Resolver dispositions): `deferred` — citing the exclusion — for a finding excluded by scope, and `immaterial` — replying with the materiality reasoning — for an in-scope observation that fails the bar. Both are no-edit, and they are not interchangeable: citing a scope exclusion for an in-scope observation invents an exclusion that does not exist. Each reviewer channel caps at the canonical bound in `references/scope-contract.md` § The iteration bound, which counts the initial pass as iteration 1 and which no local instruction restates or overrides. Convergence, not the bound, is what should end it: the early signals (converged, and the same disagreement in successive passes, both per `references/scope-contract.md` § Convergence) fire in single digits, as does a rising blocking count of one class — which is a cause to fix and continue, not an exit, and an escalation only where that cause is a design choice. Reaching the bound is a failure to converge, not an exit you may take: STOP, report the per-pass trend and what remains, and hand the decision to the user. Do not advance to the next workflow step on the strength of having hit it, even when only follow-up/out-of-scope entries remain. Do not seek zero suggestions or restart unrelated review channels.

##### Skip rules

- If a reviewer is **not configured** for the repo (its waiter reports `STATUS=NOT_CONFIGURED` — e.g. no `CodeRabbit` check ever appears), report this once and proceed without that reviewer. That status is terminal: never retry or wait it out.
- If **CodeRabbit reports a rate/quota limit or cooldown**, report it once, mark CodeRabbit `skipped (rate-limited)`, and proceed immediately. Do not raise timeouts, sleep, poll, or retry for CodeRabbit throttling. **The degradation waives only the review passes that never ran** (`coderabbit-review`, rate-limit rule): anything CodeRabbit already delivered still counts — fix its blocking findings and settle every thread it already posted before recording the skip, or the PR carries an open thread past a gate that requires none.
- Do not apply this exception to Copilot or other reviewers. A merely slow CodeRabbit check with no rate-limit signal still follows the normal timeout behavior.

**⛔ DO NOT PROCEED until every required reviewer has settled. CodeRabbit is satisfied by a passing result, or by an explicit `skipped (rate-limited)` degradation once everything it already delivered is resolved.**

---

### STEP 7: CI/CD Monitoring

**MANDATORY: Execute ALL sub-steps. Maximum 3 fix iterations.**

Because Step 5 opens the PR ready for review (NOT draft), CI workflows that
trigger on `pull_request` start immediately. There is no draft → ready
transition to manage in this workflow.

#### 7.0 Enter this step only on a converged head

**Do not start the CI wait until Step 6.3 has converged on the current head** — no unresolved blocking review finding anywhere in the ledger (`references/head-discipline.md` § Waiter scheduling order). CI has been running since the push regardless; what this step schedules is the coordinator's attention.

The one exception: when there is genuinely nothing else to advance — no other PR, no other work in flight — start the CI wait early. An idle coordinator loses nothing by watching.

Record the SHA you are waiting on:

```bash
CANDIDATE_HEAD=$(gh pr view [PR_NUMBER] --json headRefOid --jq '.headRefOid')
```

**If the head changes while this wait is outstanding, the wait is superseded** (`references/head-discipline.md` § Evidence is SHA-scoped): stop it, discard its verdict, and re-enter 7.0 on the new head. Do not count a superseded run's failures against the iteration budget below.

#### 7.1 Wait for CI Checks to Start and Complete

**⛔ Run the bundled CI check script as a long wait** — `references/host-adapters.md` § Long waits — redirecting to a log file and reading that log on the wake. On Claude Code that is `run_in_background: true` plus the completion notification:

```bash
mkdir -p [AGENT_DIR]/team/waits && \
bash [SKILLS_DIR]/dev/scripts/wait-for-ci-checks.sh [PR_NUMBER] \
     > [AGENT_DIR]/team/waits/ci-[PR_NUMBER].log 2>&1
```

**Do NOT run it in a call that cannot outlive it.** On Claude Code the Bash tool caps a foreground `timeout` at 600 000 ms, below the script's 900 s budget, so a foreground call is killed mid-poll and the output is lost; backgrounded processes are not subject to that cap. **Never launch it without the redirect**: the workflow reacts to what the script prints.

Script behavior:
- Phase 1 (discovery): waits up to 90 s for any check to appear.
- Phase 2: polls every 30 s until all checks settle, against a shared 900 s wall-clock budget.

**Check the SHA before the STATUS, on every verdict.** `TERMINAL_PASS`, `TERMINAL_FAIL`, and `NOT_CONFIGURED` are each evidence about the commit named on the `PR_HEAD_SHA=` line, and **only** that commit — including the last, since "this PR has no CI" is a terminal claim about a specific head. `PENDING` and `ERROR` are not verdicts and carry no SHA line.

- `PR_HEAD_SHA=` equals `CANDIDATE_HEAD` → read the STATUS below.
- Anything else — a different SHA, or `unknown` — → **the verdict is superseded or unattributable. Discard it, do not act on it, and relaunch the wait against `CANDIDATE_HEAD`.** `unknown` is not "probably fine": the script emits it precisely because it could not tie the result to one commit, and re-reading the head yourself afterwards cannot retroactively attribute a `gh pr checks` response taken earlier. A failure on a superseded SHA is not this head's failure either — never send one to Step 7.2.

Then branch on the trailing `STATUS=` line:

| STATUS | Exit | What to do |
|---|---|---|
| `TERMINAL_PASS` | 0 | Every check completed, none failed → **proceed to Step 8** |
| `TERMINAL_FAIL` | 1 | Every check completed, at least one failed → **proceed to Step 7.2** |
| `PENDING` | 2 | Still running at budget expiry. Not a verdict. Re-run to keep waiting, or report the wait as unfinished. **Never** record it as "CI passed". |
| `NOT_CONFIGURED` | 3 | No checks appeared within the discovery grace — this PR has no CI configured. **This is NOT a pass**: a merge gate requiring green CI is not satisfied by the absence of CI. Report it and confirm against branch protection. |
| `ERROR` | 4 | Bad arguments, `gh` unauthenticated, or the checks API could not be read → report. A failed read is not "no checks". |

#### 7.2 Handle CI Failures (LOOP — max 3 iterations)

**If Step 7.1 reports `STATUS=TERMINAL_FAIL` (failures detected):**

```
Skill tool: skill="resolve-ci-failures"
```

Pass the failure details from the script output to the skill. The skill will:
1. Analyze failure logs and identify root causes
2. Delegate fixes to a sub-agent with the coder skill
3. Push the fixes

**Batch the CI failures with anything else outstanding before that push** (`references/head-discipline.md` § Batch findings): a still-open reviewer thread or a still-failing verification item goes into the same commit series.

**After the skill completes and fixes are pushed, record the new SHA as `CANDIDATE_HEAD` and GO BACK TO Step 7.0** — re-run the wait script against the new head. This creates a loop:

```
Step 7.1 (wait) → fail → Step 7.2 (batched fix) → Step 7.0 (new head) → Step 7.1 (wait) → ...
```

**⚠️ Maximum 3 iterations.** Track the current iteration count. If checks still fail after 3 fix attempts, STOP and report the persistent failures to the user with full details.

**⛔ DO NOT PROCEED until all checks pass or max iterations reached**

---

### STEP 8: Finalization

#### 8.1 Final Verification (MANDATORY MERGE GATES)

**⛔ ALL of the following must be verified before ANY PR can be merged. No exceptions.**

**Every gate below is evidence about one SHA.** Read the head once, verify all gates against it, and merge that commit:

```bash
MERGE_HEAD=$(gh pr view [NUMBER] --json headRefOid --jq '.headRefOid')   # must equal CANDIDATE_HEAD
```

**Nothing in Step 8 may push.** Tracking docs were committed in Step 4 and confirmed in Step 4.7 precisely so this step does not invalidate the evidence it is collecting. If a gate does force a commit anyway, that SHA is a new candidate head: re-run Step 7 and re-verify these gates against it rather than merging on the old evidence.

```bash
# 1. CI checks — ALL must be green (includes the CodeRabbit check)
gh pr checks [NUMBER]

# 2. Automated reviewers — MUST be settled and resolved (if not already done in Step 6.3)
# Reuse Step 6.3 evidence when it covers the current head SHA. Invoke a dedicated
# reviewer skill only when its check, threads, or reviewed SHA changed; do not restart
# a settled review loop solely because finalization was reached.
# Use the dedicated skills — NEVER raw gh api commands.
```
```
Skill tool: skill="copilot-review",     args="[NUMBER] — [STEP 2.5 SCOPE BRIEF VERBATIM]"
Skill tool: skill="coderabbit-review",  args="[NUMBER] — [STEP 2.5 SCOPE BRIEF VERBATIM]"
```
```bash
# 3. Unresolved review threads — MUST be 0 (across ALL reviewers)
gh pr view [NUMBER] --json reviewThreads \
  --jq '[.reviewThreads[] | select(.isResolved == false)] | length'

# 4. Codecov — patch and project checks must pass
gh pr checks [NUMBER]  # verify codecov/patch and codecov/project
```

<!--
duvet= docs/specs/fx-dev-authority/index.md#required-checks-gate-every-merge
duvet= type=implication
duvet# A pull request MUST NOT be merged while any required check on it is failing or has not completed.
-->

<!--
duvet= docs/specs/fx-dev-authority/index.md#unresolved-reviewer-threads-gate-every-merge
duvet= type=implication
duvet# A pull request MUST NOT be merged while any review thread on it from a configured automated reviewer remains unresolved.
-->

**Merge gate checklist (every item must pass):**
- [ ] PR is open and mergeable
- [ ] Every gate below was verified against `MERGE_HEAD`, and the head has not moved since
- [ ] **PR title is a conventional-commit subject** (`type(scope): description`) — verify `gh pr view [NUMBER] --json title -q .title | grep -Eq '^(feat|fix|docs|refactor|chore|test|perf|build|ci|style|revert)(\(.+\))?!?: .+'`; a plain prose title FAILS — rename with `gh pr edit [NUMBER] --title "type(scope): …"` BEFORE merging (squash bakes the title into `main`). Also no stray `#<number>`/wave/phase wording.
- [ ] ALL CI checks green
- [ ] Copilot review RECEIVED and ALL threads resolved (via `copilot-review` skill — NEVER raw `gh api`)
- [ ] CodeRabbit is passing with all received threads resolved, not configured, or explicitly recorded as `skipped (rate-limited)`. CodeRabbit throttling is optional and never blocks merge.
- [ ] Zero unresolved **blocking** ledger entries (`references/scope-contract.md` § Blocking) — `required-by-contract`, `regression-caused-by-change`, and any entry blocking by tier; the latest affected delta is verified within the stopping bounds
- [ ] Every test plan item verified, user-confirmed, annotated manual-only, or recorded as a failure the user explicitly accepted (Step 5.5)
- [ ] Codecov coverage passing with 0 missing lines
- [ ] No unresolved review threads from any reviewer (Copilot, CodeRabbit, human, or future automated reviewer); follow-up/out-of-scope threads are settled without expanding implementation

<!--
duvet= docs/specs/fx-dev-authority/index.md#merge-gates-apply-regardless-of-change-size
duvet= type=implication
duvet# The size, triviality, or follow-up status of a pull request MUST NOT be treated as grounds for waiving any merge gate.
-->

**PR size is NEVER a reason to skip merge gates.** A 1-line fix gets the same verification as a 1000-line feature.

The PR was opened ready-for-review in Step 5, so there is no draft → ready
transition to perform here. Do NOT run `gh pr ready` — it is unnecessary and
will fail on a non-draft PR.

#### 8.2 Verify Task Tracking Is Already In the Diff

**Task tracking is written in Step 4 and confirmed in Step 4.7. This step verifies it; it does not push.**

```bash
git diff main --name-only | grep -E 'docs/(changes/|tasks\.md|index\.ya?ml|index\.md)' || true
```

Confirm in the diff:
- Items this PR actually completes are checked off (`- [ ]` → `- [x]`); items it did not address are untouched
- If this PR completes the whole change document, its Status is `complete`
- `docs/index.yml` and `docs/index.md` agree with it

**A missing tracking update here is a Step 4 defect, and fixing it costs a full re-verification cycle.** Have a coder sub-agent write and push it anyway — the docs must not lie on `main` — then treat the new SHA as a candidate head: re-run Step 7 and re-verify Step 8.1 against it (`references/head-discipline.md` § The candidate head). Do not merge on the gates you collected for the parent commit.

**`(PR #N)` annotations are optional and never worth a commit.** The PR number is unknown when tracking is written in Step 4; add it only if some other batched push happens to be going out anyway. A tracking line without it is not a defect — the merge commit links the two.

If no relevant tracking doc exists, skip this step.

#### 8.3 Update Issue (if applicable)

```
Agent tool:
  prompt: "Load the issue-updater skill (Skill tool: skill='issue-updater'), then:

           Update issue #[NUMBER]: Link PR, set label ready-for-review"
  description: "Update issue"
```

#### 8.4 Report to User

```
✅ PR #[NUMBER] ready: [URL]

Changes:
- [summary bullets]

Awaiting your approval to merge.
```

<!--
duvet= docs/specs/fx-dev-authority/index.md#dev-runs-require-user-approval-before-merge
duvet= type=implication
duvet# A `dev` run MUST obtain explicit approval from the user before merging any pull request it produced.
-->

**⚠️ NEVER MERGE WITHOUT USER APPROVAL**
**⚠️ NEVER MERGE WITHOUT ALL MERGE GATES PASSING (Step 8.1)**
**⚠️ NEVER MERGE WITHOUT COPILOT REVIEW RECEIVED AND ADDRESSED**

After this handoff, a later user message such as "merge it" is a standalone mechanical request, not a new `/dev` phase. Recheck the live gates and merge directly in the coordinator session. Do not re-invoke `/dev`, reload its internal skills, or spawn a merge sub-agent.

---

## Workflow Variations

### GitHub Issue URL

1. STEP 0: Auth check
2. STEP 1: Branch as `fix/issue-123-description`
3. Fetch issue: `gh issue view [NUMBER] --json title,body,labels,comments`
4. STEP 2-8: Standard (use issue-updater in Steps 3 and 8)

### Quick Fix (fix:, error:, bug: prefix)

1. STEP 0: Auth check
2. STEP 1: Branch as `fix/short-error-desc`
3. STEP 2: Focus on error analysis, root cause
4. STEPS 3-8: Standard

### Multi-PR Tasks

1. Complete STEPS 1-8 for first PR
2. **STOP** - Wait for user approval
3. Only after approval: Start next PR
4. Track with TodoWrite

**NEVER have multiple PRs open simultaneously**

---

## Error Handling

| Error | Action |
|-------|--------|
| Sub-agent fails | Retry once with adjusted params, then STOP and report |
| Git conflict | STOP, report to user, wait for resolution |
| Tests fail | coder sub-agent fixes, rerun until pass |
| Auth fails | STOP, request `gh auth login` |

---

## Sub-Agent Quick Reference

All sub-agents are launched via the Agent tool. Each loads its skill via the Skill tool inside the sub-agent.

| Step | Skill to Load | Skill Name |
|------|---------------|------------|
| 2 | Requirements Analyzer | `requirements-analyzer` |
| 3 | Planner | `planner` |
| 3,8 | Issue Updater | `issue-updater` |
| 4,4.6.4,6.2 | Coder | `coder` (Step 4 also writes the task-tracking update; Step 6.2 is ONE batched fix pass, not one per finding) |
| 4.5 | Pre-PR Self-Review | `simplify`, then `code-review`, then `codex-review` (local `codex`, the ONLY local reviewer) — all three passes run, then one batched fix; blocking findings resolved, latest affected delta verified |
| 4.6.2 | Browser Verification | `verify-web-change` (pre-PR, against the branch) |
| 5 | PR Preparer | `pr-preparer` |
| 6.1 | PR Reviewer | `pr-reviewer` (delta and integration only; full pass only if the diff changed materially since 4.5) |
| 6.3 | Copilot Review | `copilot-review` (waiter backgrounded, concurrent with coderabbit-review) |
| 6.3 | CodeRabbit Review | `coderabbit-review` (PR-level only, waiter backgrounded, concurrent with copilot-review; classify/deduplicate feedback and verify only affected deltas within bounds) |
| 6.3 | PR Feedback Resolver | `resolve-pr-feedback` (meta — called by reviewer skills) |
| 7.2 | CI Failure Resolver | `resolve-ci-failures` |

**Pattern for every sub-agent call:**
```
Agent tool:
  prompt: "Load the [skill-name] skill (Skill tool: skill='[full-skill-name]'), then: [task]"
  description: "[summary]"
```

---

## Success Criteria

Workflow complete when ALL true:
- ✅ Feature branch created from main
- ✅ Requirements documented
- ✅ Plan created
- ✅ Code implemented with atomic commits, task tracking included
- ✅ Pre-PR review matrix completed (or permitted degradation documented), findings classified in the shared ledger, blocking findings resolved, and the latest affected delta verified within the stopping bounds
- ✅ Browser and programmatic test-plan verification done BEFORE the PR was opened
- ✅ Candidate head frozen and recorded before hosted review and CI (Step 4.7)
- ✅ PR created with description (including links to related specs/changes and the verified test plan)
- ✅ ALL test plan items addressed: browser-verified, programmatically verified, user-confirmed manual verification, or a failure the user explicitly accepted (NEVER silently skipped, and never a failure shipped past the gates unaccepted)
- ✅ PR test plan items checked off or annotated with verification results in the PR description
- ✅ Self-review done as a delta/integration pass, findings batched into the same fix push as the hosted reviewers'
- ✅ Automated review feedback classified and settled; blocking findings resolved and the latest affected delta verified without unrelated review restarts
- ✅ CI waited on only after review converged, and green on the exact merge SHA
- ✅ Task tracking docs verified present in the diff — not committed after the merge gates ran
- ✅ User notified, awaiting merge approval
