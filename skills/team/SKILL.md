---
name: team
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. Runs an explicitly requested coordinated multi-agent, multi-task implementation workflow."
---

# Team (Coordinated Sub-Agent Implementation)

> **Path note:** `[SKILLS_DIR]` below is the directory holding this skill's own folder —
> the parent of the directory containing this `SKILL.md`. Substitute its absolute path;
> every skill referenced below is installed as a sibling there.
>
> `[AGENT_DIR]` is your host's in-repo agent directory — `.claude` on Claude Code,
> `.agents` on Codex (`[SKILLS_DIR]/dev/references/host-adapters.md` § `[AGENT_DIR]`).
> Substitute it; never write a literal `.claude/` path on another host.

<!--
duvet= docs/specs/fx-dev-authority/index.md#the-team-coordinator-delegates-all-implementation
duvet= type=implication
duvet# The `team` coordinator MUST NOT implement a task's code itself and MUST route all implementation work through agents it spawns.
-->

Spawn a coordinated sub-agent team to implement a spec or multi-task feature. The main session (you) acts strictly as coordinator — no code, no commits, only delegation and quality control.

## ⛔ Critical Architecture Rule: Coordinator Owns the SDLC

**YOU (the coordinator) orchestrate each SDLC step per task.** You spawn focused, single-purpose agents for each step and handle cross-cutting concerns (reviewer passes, CI, merge gates) directly.

**Never tell an agent to "load the dev skill and follow all steps." Instead, give each agent ONE focused job.** An agent handed a whole lifecycle inlines the implementation instead of delegating it, fills its context, and skips the later stages — observed in production, repeatedly.

That failure is about **prompt scope, not host capability**, which is why the rule holds everywhere. On a host whose delegates cannot themselves delegate (Claude Code) the platform also enforces it; on one where they can (Codex) it is a deliberate design constraint and still binding. Do not read a host that permits nesting as permission to hand one agent the lifecycle.

What nesting *does* buy, where the host supports it: a delegate may spawn helpers **inside its own single focused job** — a coder fanning out reads across a large tree. That is not delegating the lifecycle, and this rule does not forbid it.

See `[SKILLS_DIR]/dev/references/host-adapters.md` for the operations this skill assumes and their mapping on your host.

---

## STEP 0: Understand the Work

1. **If given a spec file path:** Read it to extract all tasks.
2. **If given an issue URL:** Fetch it with `gh issue view`.
3. **If given a description:** Break it into discrete, parallelizable tasks.

Identify:
- Total tasks and their dependencies
- Which tasks can run in parallel vs. which must be sequential
- A sensible task grouping (1 coder agent can own 1-3 related tasks)

### Do NOT pause to confirm scope on clearly-scoped requests (BLOCKING)

When the user's invocation is unambiguous — e.g. `implement all pending changes fully`, `ship all of these`, `do everything in docs/changes/`, a concrete list of PR numbers, or a single spec file — **treat that as the authoritative scope and proceed immediately to Step 1**. Do NOT pause to ask "should I do all 6 now or just wave 1 first to sanity-check?" Do NOT report `failure` to the Coder dashboard asking for scope confirmation when the user already gave it. Words like "all", "fully", "every", "the whole list" are explicit scope — honor them.

**You can still split execution into waves internally.** Wave-based execution (Wave 1: independent tasks in parallel; Wave 2: their dependents once unblocked; etc.) is the correct way to run a multi-PR team, and you should plan it that way. The rule is about **not stopping to ask the user** whether to do waves or which wave to start with — just plan the waves and execute them.

> **⛔ Waves are an INTERNAL execution concept — they MUST NEVER leak into a PR title (BLOCKING).** A wave/phase/step number is not a PR or issue. A `#<number>` in a PR title (`#4`, `(#4)`, `#123`) looks like plain text in the title bar, but on squash-merge the title becomes the commit subject, where `#N` auto-links to PR/issue #N in the repo. Writing `(#4)` to mean "wave 4" wrongly cross-links the merged commit (and PR) to whatever PR/issue #4 is — this has happened repeatedly and is exactly what we are stamping out. When you spawn coders and when you author/verify titles before merge:
> - **No `#<number>` in any PR title** unless N is a real, existing PR/issue on the target repo that the PR actually references. Never pre-add a `(#N)` suffix — GitHub appends the real PR number at squash-merge time.
> - **No "Wave N", "Phase N", "Step N", batch/iteration labels, or change-doc numbers in titles.** They belong in the PR body only.
> - **Gate-check this before merge:** if a PR title contains a stray `#N` or wave/phase wording, rename it with `gh pr edit <N> --title "..."` before merging. A squash merge bakes the title into `main`'s history — a wrong cross-link there is permanent. See the `github` skill's "`#<number>` PR-Title Rule".

**Reserve confirmation for genuine ambiguity only:**
- Conflicting instructions ("ship 0051 — actually wait, also 0055?")
- Vague scope ("clean up the changes folder" without saying which)
- Destructive operations not implied by the request (deleting branches, force-pushing, dropping data)

If you find yourself drafting a "before I burn that compute, one quick check…" message in response to a clearly-scoped instruction, stop. Delete the draft. Spawn the team.

### Build the Scope Brief (MANDATORY)
Before spawning anything, write down the **Scope Brief**. It is what every teammate and every reviewer will be judged against, and it must carry the user's own framing — not your summary of it. Full definition: `[SKILLS_DIR]/dev/references/scope-contract.md`.

```markdown
### Scope Brief
- **Verbatim request:** "<the user's exact words, quoted, never paraphrased>"
- **Interpreted scope:** <tasks, change docs, specs in play>
- **Deliverable type:** <docs | code | spec | research | config | mixed>
- **Explicitly out of scope:** <what must NOT be touched or flagged, with reasons>
- **Size signal:** <narrow | normal | open-ended>
- **Known-and-accepted:** <deliberate states a reviewer would otherwise flag>
```

**Every coder prompt, every verify prompt, and every reviewer invocation MUST include this brief verbatim.** A reviewer that does not know what was asked for reports the work the team deliberately did not do, and the coordinator pays for it in filtering time on every PR.

### The sprawl STOP rule for autonomous runs

<!--
duvet= docs/specs/fx-dev-authority/index.md#team-runs-may-merge-within-approved-scope
duvet= type=implication
duvet# A `team` run MAY merge a pull request it produced without seeking further user approval, provided that pull request's work falls within the scope the user already approved.
-->

`/team` exists to run unattended for a long time, so **duration, task count, PR count, and effort are NEVER reasons to stop**. Working through an approved backlog is the job — do not check in between waves, and do not ask permission for the next approved task.

Stop and inform the user **only** when a task requires something the approved contract does not cover:

- Work outside the spec, change document, or task list the user pointed you at
- An architectural decision no approved document has made
- A migration, dependency, or breaking change the contract never mentioned
- A destructive or irreversible action not implied by the request

When that happens, finish every task that IS covered, then report what is blocked and why in two or three sentences. Never halt the whole run for one out-of-contract task.

This rule and the "do NOT pause to confirm scope" rule above are the same rule seen from two sides: **the user's scope is authoritative — execute all of it without asking, and none of what lies outside it without asking.**

## STEP 1: Do NOT Provision a Team

**There is nothing to create.** The set of delegates is whatever you have spawned; it needs no name, no manifest, and no teardown. Skip straight to STEP 2 and start defining tasks — the team exists the moment you spawn the first coder in STEP 3.

Treat any urge to "set up the team" first as a bug in your plan. If your host has a provisioning call, you still do not need it here; if it does not, nothing is missing.

**Host notes** — check these against `[SKILLS_DIR]/dev/references/host-adapters.md` for your host before assuming a failure is yours:

- **Claude Code:** the team is implicit and session-scoped, forming on the first `Agent` spawn with the main session permanently the lead. `TeamCreate`/`TeamDelete` no longer exist — calling one, or waiting on it, is a bug, and `team_name` is accepted-but-ignored. Teams are gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (in `settings.json` `env` or the environment); if teammates never appear when you spawn them, that is almost certainly unset — report it rather than retrying. Config and the shared task list live at `~/.claude/teams/session-<first 8 chars of session id>/` and `~/.claude/tasks/<same>/`, written automatically — never edit or pre-author them.
- **Codex:** delegates form a tree rather than a flat roster, and concurrency is bounded per session — four slots *including you* on 0.145.0, so three live teammates. A spawn past the limit queues silently and looks exactly like one that hung. Three further facts decide whether a team forms at all, all detailed in the adapter file: spawn with `fork_turns: "none"` or you cannot set a teammate's tier; **`wait_agent` before your turn ends or the run terminates and takes every live teammate with it**; and delegation only happens because a skill explicitly asked for it — the session-level `<multi_agent_mode>` instruction suppresses sub-agents otherwise, which is why this skill says "spawn sub-agents" in those words and why a teammate that should fan out must be told to in its `message`.

## STEP 2: Create and Organize Tasks

Use `TaskCreate` for every task identified in Step 0. Set up dependencies with `TaskUpdate` (`addBlockedBy`/`addBlocks`) so work proceeds in the correct order.

**Where the host has no shared task list** (Codex has none), keep the same information in the ledger under `[AGENT_DIR]/team/` — one row per task, with its dependencies and state. Do not skip the step and do not invent a tool: the dependency order is what decides which teammates may run in the same wave.

**Task descriptions MUST include:**
- Exactly what to implement (files, components, endpoints)
- Acceptance criteria
- Which spec task(s) it maps to (if from a spec)

## STEP 2.5: Worktree Isolation Setup (MANDATORY for concurrent coders)

**Why this step exists:** `isolation: "worktree"` on the Agent tool does nothing for teammates — a spawned teammate runs as a full independent session in the lead's working directory, not in an isolated worktree (see STEP 3). Without real isolation, every concurrent coder shares the coordinator's single working tree and git HEAD and they corrupt each other. The coordinator MUST pre-create one git worktree per coder that will run concurrently, each on its own branch, and pin each teammate to its worktree via a prompt preamble.

**Skip this step only if you will run coders strictly one-at-a-time** (fully sequential, never two coders alive at once). In that single-writer case the shared tree is safe. The moment you want parallelism, this step is required.

### 2.5.1 Create one worktree per concurrent coder

Worktrees **MUST** live under the repo's own `[AGENT_DIR]/worktrees/` directory — that is Claude Code's native worktree convention and the same shape works on any host, it keeps them inside the (writable) repo, and it survives a read-only parent filesystem. **NEVER** put them in `/tmp`, `$HOME`, or a sibling path outside the repo.

```bash
cd <REPO_ROOT>
git fetch origin --quiet
mkdir -p [AGENT_DIR]/worktrees
# one per coder — name the worktree after the task/change, branch off origin/main
git worktree add [AGENT_DIR]/worktrees/<slug> -b <branch> origin/main
# e.g. git worktree add [AGENT_DIR]/worktrees/0004 -b refactor/0004-unified-config-service origin/main
```

**Ensure `[AGENT_DIR]/worktrees/` is ignored** before creating any (most projects already ignore their agent directory, but verify — this one may not). A nested worktree dir otherwise shows up as untracked in the main repo and can get swept into a coder's `git add`. Use the repo-local, **untracked** `.git/info/exclude` so this scaffolding never dirties the coordinator's working tree or risks landing in a feature PR — do NOT append to the tracked `.gitignore`:

```bash
git check-ignore [AGENT_DIR]/worktrees/x >/dev/null 2>&1 || \
  printf '\n# team scaffolding (local only)\n[AGENT_DIR]/worktrees/\n[AGENT_DIR]/team/\n' >> .git/info/exclude
mkdir -p [AGENT_DIR]/team/waits
```

`.git/info/exclude` is never committed, so there is nothing to clean up later and `git status` stays clean.

**Symlink `node_modules`** (and any other gitignored, install-only dir the toolchain needs) into each worktree so `vitest`/`biome`/`tsc` resolve — a fresh worktree has no `node_modules`:

```bash
ln -s <REPO_ROOT>/node_modules <REPO_ROOT>/[AGENT_DIR]/worktrees/<slug>/node_modules
```

### 2.5.2 Smoke-test isolation BEFORE spawning real coders

Spawn ONE cheap probe teammate (size **small** — see the size table in STEP 3) pinned to a worktree. Have it write a marker file in the worktree and confirm (a) the marker is **absent** in the main repo, (b) `pwd`/branch/toplevel are the worktree's, then clean up. Only proceed once it reports isolation OK. This catches a broken setup before any real code is written. (If the probe lands in the main repo, the workaround failed — stop and re-check paths.)

A confirmed gotcha: **the teammate's shell cwd RESETS to the main repo root after EVERY bash command** ("Shell cwd was reset to …"). That is exactly why the preamble below forces an absolute `cd` on every command — relative paths silently resolve against the MAIN repo, not the worktree.

### 2.5.3 Pin each coder to its worktree (prompt preamble)

Every coder/verify/fix teammate that must operate in a worktree **MUST** have its spawn `prompt` START with this preamble (substitute the absolute path):

```
CRITICAL — WORKTREE ISOLATION. Your working directory is <ABS_WORKTREE_PATH>.
The shell cwd resets to the main repo after every command, so:
- Prefix EVERY bash command with `cd <ABS_WORKTREE_PATH> && `.
- Use ABSOLUTE paths (under <ABS_WORKTREE_PATH>/) for ALL file reads, writes, and edits.
- Pass `path: <ABS_WORKTREE_PATH>` to EVERY Glob and Grep call.
- Relative paths resolve to the MAIN repo, NOT your worktree — never rely on them.
Your branch <branch> is already created and checked out in this worktree; do NOT
create a new branch or run `git checkout`. Commit and push from inside the worktree.
```

### 2.5.4 Track the worktrees for cleanup

Remember each `(worktree path, branch, node_modules symlink)` triple you created — STEP 4 must tear them all down.

## STEP 3: Execute Tasks (Coordinator-Driven SDLC)

**Load the dev skill** (`Skill tool: skill='dev'`) and read its SDLC steps. The dev skill is the single source of truth for the development workflow — do not duplicate its instructions here.

For each task (or group of parallel tasks), walk through the dev skill's SDLC steps yourself. For each step, decide:

1. **Can I handle this step directly?** (e.g., invoking a skill, running a `gh` command) → Do it yourself.
2. **Does this step require writing/modifying code?** → Spawn a focused agent with a single-purpose prompt for just that step.

### ⛔ ALL Agent spawns MUST pass `name` (BLOCKING)

**Every spawn you make as the team coordinator — coder, verify, fix, anything — MUST carry a handle** (`name` on Claude Code, `task_name` on Codex). The handle is what makes a teammate addressable for a mid-flight correction and identifiable in its own report — on Claude Code it is also what puts it in the team config's `members[]`, and on Codex it becomes the canonical `/root/<task_name>` that `list_agents` and `wait_agent` speak. Omitting it produces an effectively anonymous worker you can't message or steer by name, defeating the point of `/team`.

**Do not try to name or route the team.** Every delegate joins the coordinator's set automatically; there is no roster to address. On Claude Code specifically, the `team_name` input is accepted but ignored (and deprecated in hook payloads) — passing it does nothing, so drop it.

```
Agent tool:
  name:      "<short-descriptive-handle>"    # ← REQUIRED, NO EXCEPTIONS
  subagent_type: "general-purpose"            # Claude Code; a skill is never an agent type
  model:     "<per the size table below>"     # ← pick deliberately, do not default
  isolation: "worktree"                      # NO-OP for teammates — see STEP 2.5; pre-create real worktrees instead
  mode: "bypassPermissions"
  prompt: "..."
  run_in_background: true                    # usually
```

That block is Claude Code syntax, shown as an example of the delegate operation (host-adapters.md, op 1). The same spawn on Codex:

```
spawn_agent:
  task_name:        "<short-descriptive-handle>"   # ← the handle; becomes /root/<task_name>
  fork_turns:       "none"                         # ← REQUIRED to set model/effort at all — see below
  model:            "<per the size table below>"
  reasoning_effort: "<raise it for judgment-heavy roles>"
  message:          "..."                          # the ONLY context the child gets under "none"
```

**On Codex, `fork_turns` is not optional bookkeeping.** Omitting it (or passing `"all"`) makes the child a full-history fork that inherits the coordinator's entire context *and* its model and effort, and the host then **rejects** a `model`/`reasoning_effort` override outright — so the size table below becomes unreachable and every teammate silently runs at the coordinator's tier. Pass `"none"` and put the whole job, including the Scope Brief verbatim, in `message`.

The handle should be specific and human-readable so it's useful in logs and when messaging a teammate (e.g., `coder-0105A`, `verify-pr-371`, `fix-0106-types`). One-shot generic names like `agent1` are bad. **Codex accepts only lowercase letters, digits, and underscores in `task_name`** and rejects the spawn outright otherwise, so spell those handles `coder_0105a`, `verify_pr_371`, `fix_0106_types` there.

Paths under `[AGENT_DIR]/team/` in this document are **scratch space** (host-adapters.md, op 7) — coordination artifacts, never part of a change. `[AGENT_DIR]` is your host's in-repo agent directory, per the Path note above.

**Self-check before EVERY Agent call:** "Did I pass `name`? Did I pick a `model` size?" If either is missing, fix the call before sending it. This rule is non-negotiable.

### Pick an agent SIZE for every spawn

Choose by the **shape of the task**, not by how important it feels.

| Size | Use for |
|---|---|
| **large** | Coder agents doing implementation. Fix agents on an **undiagnosed** bug. Anything requiring design judgment. |
| **medium** | PR preparer. Browser verification. Fix agents handed an **exact, specified** patch. Mechanical work with a clear spec. |
| **small** | The worktree isolation probe (STEP 2.5.2). Pure inspection or summarisation with no judgment call. |

**Request the tier, not a model name.** "Spawn a large-model sub-agent" resolves to whatever the host currently offers at that tier, so this table does not go stale every time a model ships — and a hardcoded name silently becomes wrong rather than failing loudly. Where the host requires an explicit model, map the tier to its general-purpose **coding** models and nothing else; a model specialised for another domain is the wrong choice at every tier regardless of its size. In Claude Code that means the three coding tiers only — **never select `fable`.**

**Coders stay `large`. Do not "optimise" them downward.** Implementation is judgment-heavy, and a weaker coder that needs more iterations costs *more* than a stronger one that needs fewer — turn count, not per-turn price, is what dominates. A downgrade that adds two review rounds is a large net loss that looks like a saving.

Two constraints worth knowing rather than rediscovering:

- **Tier and reasoning effort are different dials, and not every host exposes both.** Where effort is settable per spawn (Codex), raise it too for the judgment-heavy roles, not just the tier. Where it is not (Claude Code, which inherits it from the session), the tier is the only lever you have — do not expect a `large` delegate to think harder merely because the task is hard.
- **The smallest tier may carry a reduced context ceiling.** For read-heavy roles that is a feature: it bounds context growth for free. Check your host's limit in `[SKILLS_DIR]/dev/references/host-adapters.md` rather than assuming.

### Key orchestration principles

**Implementation steps** (planning, coding, testing) → Spawn focused agents. For any coder that will run **concurrently** with another, give it an isolated worktree via STEP 2.5 and start its prompt with the worktree preamble — do NOT rely on `isolation: "worktree"` (it's a no-op for teammates; see the prohibition above). Give each agent ONLY its specific job — the change doc path, spec path, plan, and acceptance criteria. Do NOT tell it to follow the full SDLC. Always pass `name` (see above).

When you spawn the coder for the FINAL piece of a change, your prompt MUST include: "This is the final implementing PR for <change>. In the same commit, flip `**Status:** draft` → `**Status:** complete` in `docs/changes/<NNNN>-*.md` AND flip `status: draft` → `status: complete` for that change's entry in `docs/index.yml`. Sync `docs/index.md` if present." For every NON-final coder on the same change, your prompt MUST include: "Leave the change-doc `**Status:**` field and `docs/index.yml` entry untouched — the final PR flips them." This split prevents rebase-conflict storms across multi-PR changes and ensures the final PR carries the Status flip atomically.

**PR creation** → Either do it yourself via `gh pr create` or spawn a focused PR preparer agent. Load `github` skill first. **⛔ If you create the PR yourself, the `--title` MUST be a conventional-commit subject — `type(scope): description` — matching the canonical regex `^(feat|fix|docs|refactor|chore|test|perf|build|ci|style|revert)(\(.+\))?!?: .+` (see the github skill's "Use Conventional Formats"). Do NOT write a prose title; running `gh pr create` directly does NOT exempt you from the conventional-commit rule. Verify the title against the regex before AND after creation.** (Prose titles the coordinator wrote directly — bypassing pr-preparer — are exactly how non-conventional titles have slipped onto `main`.)

**Review and CI steps** (Copilot review, CodeRabbit review, CI monitoring, feedback resolution) → **Handle these DIRECTLY as the coordinator.** These are lightweight skill/command invocations that must not be delegated. **Pass the STEP 0 Scope Brief into every reviewer invocation that accepts one, and apply it when triaging every reviewer that does not** (Copilot and the CodeRabbit GitHub App accept nothing). A finding covered by the brief's out-of-scope list is recorded as deferred with the covering exclusion — never silently fixed, never silently dropped, and never a reason to widen a teammate's PR. Use each reviewer's waiter or read-only inspection first, classify and deduplicate findings under `dev` Step 2.5, then invoke feedback resolvers only for the classified disposition. Never let a resolver implement unclassified feedback or modify task trackers for deferred feedback.

**⛔ NEVER `sleep` or poll waiting for anything.** Every wait — Copilot, CodeRabbit, CI — runs as a long-running wait script (host-adapters.md, op 6), never in a foreground call and never as a chain of sleeps, and never as `gh pr checks --watch`. How its completion reaches you, and whether waiting on a teammate is forbidden or mandatory, is host-specific — see **Waiting and reconciliation** below before you decide to idle. This is the single largest source of wasted coordinator turns and it is non-negotiable.

**Merge gates** → Always handle directly. See MANDATORY MERGE GATE CHECKLIST below.

**Browser verification** → Spawn a dedicated verify agent if the task has UI changes.

### Parallelization

- **Size every wave to your host's concurrency limit, and read the limit rather than assuming it.** Codex 0.145.0 gives four slots *including the coordinator* — three live teammates, and a fourth spawn queues silently, which is indistinguishable from a hung one. Claude Code does not publish a fixed number; treat a wave beyond a handful as its own risk.
- Spawn multiple coder agents simultaneously for independent tasks — but ONLY after giving each its own **pre-created worktree** per STEP 2.5 (the `isolation: "worktree"` flag does NOT work for teammates). Each coder works in its own worktree on its own branch.
- For dependent tasks, wait until the blocking task's PR is merged before spawning the next coder
- After merging, repeat for newly-unblocked tasks
- If you skip STEP 2.5, you MUST run coders strictly one-at-a-time (never two alive at once) — concurrent coders without real worktrees share one working tree and clobber each other

### Waiting and reconciliation (NON-NEGOTIABLE)

**⛔ The rule: never burn coordinator turns on a timer.** No `sleep` loops, no `gh pr checks --watch`, no re-reading state every 30 seconds to see whether anything moved. Every wake costs a full read of your entire context, and your context is the largest in the team — a poll loop is the single most expensive thing you can do, and it gets more expensive with every turn you add.

**The mechanism that replaces polling is host-specific, and getting it backwards ends the run.** Check `[SKILLS_DIR]/dev/references/host-adapters.md` (op 3) for your host:

- **Claude Code — completion notifies you.** Reviewer waiters, CI waiters, and teammate agents all wake you on exit; that is your only scheduling mechanism, and blocking on one is the bug. Teammates keep running while you are idle.
- **⛔ Codex — nothing notifies you, and ending your turn kills every live teammate.** A child's `FINAL_ANSWER` is delivered with `trigger_turn: false`: it sits in your context until your *next* turn rather than waking you, and if you stop before it lands, the run terminates and the teammate is interrupted mid-task. So you **must** `wait_agent` on your outstanding teammates before your turn ends — that is not polling, it is the host's blocking primitive, and it costs one turn rather than one per check. Give it a `timeout_ms` measured in minutes; Codex asks for long waits precisely so the primitive does not degrade into busy polling. Use `list_agents` for a status snapshot inside the same turn.

A coordinator that reads the Claude Code line on Codex spawns one teammate, declines to "block", ends its turn, and takes the teammate down with it — which looks exactly like a team that never formed.

#### The ledger

Keep `[AGENT_DIR]/team/waits/ledger.json` — one row per tracked teammate and per tracked PR, recording its last known state and what you are waiting on for it. It exists so a wake is a cheap diff instead of a re-derivation of the whole run.

#### Reconcile on wake, never on a timer

When **any** wake arrives — a notification where the host sends one, or a `wait_agent` returning where it does not — do **one batched pass**:

1. Read the ledger.
2. Read every log whose waiter has completed since the last pass.
3. Update every row that changed, in one go.
4. Dispatch whatever is now unblocked.
5. Go idle again.

**Batch the inspection.** One pass over all open PRs, not one `gh` call per PR per wake. While anything is in flight you get free wakes, so stall detection costs you no dedicated turns at all.

#### The silence backstop

The only case reconcile-on-wake misses is *everything* going quiet at once. Guard it with a single long-interval `ScheduleWakeup` (~30 minutes) — **not** a `sleep`, which holds a turn open. This applies only where the host both schedules wakeups and keeps teammates alive across an idle coordinator; on a host where ending the turn ends the run (Codex), there is no idle to guard — the `wait_agent` you are already inside *is* the backstop, so give it a generous `timeout_ms` instead.

Every waiter has its own 900 s budget and always exits, so it will notify you well inside that window. The backstop should essentially never fire. **Do not shorten it**: a short interval is polling at full coordinator context wearing a different hat.

#### Re-launching a `PENDING` waiter

`STATUS=PENDING` means the reviewer or check is still running — not a verdict, not a failure. Relaunch it (backgrounded) if you still need that gate.

**Prefer to have other work in flight while it runs.** If you have other PRs to advance, do that and let the relaunched waiter notify you; that is strictly cheapest. Only when you have nothing else to do is it worth relaunching immediately and waiting on it alone.

---

## MANDATORY MERGE GATE CHECKLIST (BLOCKING)

**BEFORE running `gh pr merge` on ANY PR — no matter how small — you MUST verify ALL of the following. This is non-negotiable. A single unmet condition means DO NOT MERGE.**

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

| # | Gate | How to verify | Blocking? |
|---|------|--------------|-----------|
| 1 | **Required CI checks green** | `gh pr checks <NUMBER>` — every required non-CodeRabbit check must pass | YES |
| 2 | **Copilot review RECEIVED and feedback RESOLVED** | Invoke `copilot-review` skill — confirm 0 unresolved Copilot threads | YES |
| 2b | **CodeRabbit reviewed or correctly degraded** | Invoke `coderabbit-review`: prefer a passing check with received feedback resolved; if CodeRabbit rate-limits, report once, resolve what it already delivered (blocking findings fixed, every posted thread settled), and record `skipped (rate-limited)` without blocking | NO when rate-limited |
| 3 | **Implementation matches spec/task** | Read the diff and verify against requirements | YES |
| 4 | **Spec task marked complete** | Check via project-management skill | YES |
| 5 | **PR description is clear** | Read PR body | YES |
| 5b | **PR title is clean AND conventional** | Title (a) is a conventional-commit subject — run the canonical check from the `github` skill's "Use Conventional Formats" (a plain prose title with no `type:` prefix FAILS) — AND (b) has NO stray `#<number>` (only a real PR/issue ref) and NO wave/phase/step/change-doc number. Fix with `gh pr edit <N> --title "type(scope): …"` before merge — squash bakes the title into `main` | YES |
| 6 | **Browser verification completed** | Spawn a verify agent if needed (see below) | YES |

### ⛔ Reviewer Gates (Gates 2 + 2b) — CRITICAL

> **Codex runs LOCALLY first — and it is the ONLY local reviewer.** Implementing sub-agents run local Codex via the `codex-review` skill during pre-PR self-review, passing the Scope Brief. **Not `codex review --base main`** — that CLI rejects `--base` together with a prompt, so the promptless form cannot carry the brief and reports the work the change deliberately did not do. Prefer it **converged** (`[SKILLS_DIR]/dev/references/scope-contract.md` § Convergence — no blocking finding left unresolved, not zero output). **There is no local CodeRabbit pass; the `cr` CLI is not used.** Gate 2b is the PR-level CodeRabbit review, which applies only when the GitHub App is configured — its waiter reports `STATUS=NOT_CONFIGURED` otherwise, which is terminal and expected for most repos. If CodeRabbit rate-limits, resolve findings already received, record `skipped (rate-limited)`, and continue; never wait for its cooldown.

**As coordinator, YOU handle reviewer waits directly, and you never spend turns polling them.** Launch every configured reviewer's waiter concurrently — on Claude Code that means one message with every call backgrounded, each redirecting to its own log, and a completion notification per reviewer; on a host without those notifications, keep the handles and collect them per **Waiting and reconciliation**. No sub-agents are involved and there is no execution mode to pick.

```
# ALL in one message, every one run_in_background: true.
# Each command creates the log dir itself: if it does not exist the REDIRECT fails
# before the waiter ever starts, so you get no STATUS line at all — the one failure
# the whole protocol exists to prevent. `mkdir -p` is idempotent; never rely on an
# earlier step having created it.
Bash: mkdir -p [AGENT_DIR]/team/waits && bash [SKILLS_DIR]/copilot-review/scripts/wait-for-copilot-review.sh <PR_NUMBER> \
        > [AGENT_DIR]/team/waits/copilot-<PR_NUMBER>.log 2>&1
Bash: mkdir -p [AGENT_DIR]/team/waits && bash [SKILLS_DIR]/coderabbit-review/scripts/wait-for-coderabbit-review.sh <PR_NUMBER> \
        > [AGENT_DIR]/team/waits/rabbit-<PR_NUMBER>.log 2>&1
Bash: mkdir -p [AGENT_DIR]/team/waits && bash [SKILLS_DIR]/dev/scripts/wait-for-ci-checks.sh <PR_NUMBER> \
        > [AGENT_DIR]/team/waits/ci-<PR_NUMBER>.log 2>&1

# On each notification: read the log, branch on its STATUS= line, classify
# findings in the ledger, THEN invoke that reviewer's resolver skill.
```

**Never run a waiter in a call that cannot outlive it** — on Claude Code the Bash tool caps a foreground `timeout` at 600 000 ms, below every waiter's 900 s budget, so a foreground call is killed mid-poll with no STATUS and no exit code and the caller re-runs it blindly. Each host's surviving shape is in `[SKILLS_DIR]/dev/references/host-adapters.md` § Long waits; on Codex it is a teammate running the script that you `wait_agent` on. **Never launch one without the redirect**: the cycle is driven by what the script prints.

Apply `dev` Steps 2.5 and 6.3 as the canonical reviewer policy: maintain the coordinator-owned finding ledger, fix every **blocking** finding and only those (`[SKILLS_DIR]/dev/references/scope-contract.md` § Blocking — the class name does not decide it; a reviewer-originated Material or Substantive entry blocks whatever its class), and rerun only reviewer state invalidated by the latest delta. Do not restart every reviewer after each push or seek zero suggestions. Settle all required threads within the bounded remediation rounds. **If CodeRabbit reports a rate/quota limit or cooldown at any point, stop its loop immediately, report once, record `skipped (rate-limited)`, and continue without waiting or escalating — after fixing the blocking findings it already delivered and settling every thread it already posted.** The degradation waives only the passes that never ran (`coderabbit-review`, rate-limit rule), never work already on the PR. Copilot must still satisfy its mandatory review gate.

If CodeRabbit is not configured (its waiter reports `STATUS=NOT_CONFIGURED`, exit 3), report once and proceed — that status is terminal, so never retry or wait it out. Do not silently skip ordinary failures; the optional exception is specifically for CodeRabbit throttling.

### Browser Verification Gate (Gate 6)

For tasks with UI changes, spawn a dedicated verify agent:

```
Agent tool:
  name: "verify-<pr-number>"            # REQUIRED — addressable handle
  model:     "<medium — see the size table>"  # verification is mechanical
  prompt: "Load the verify-web-change skill (Skill tool: skill='verify-web-change').
           Verify PR #<NUMBER> on branch <branch-name>.
           Check out the branch, start the dev server, and confirm the app loads without errors.
           Report back whether verification passed or failed, with details of any errors."
  description: "Verify PR #<NUMBER> in browser"
  mode: "bypassPermissions"
```

**Why this gate exists:** CI does NOT catch runtime-only errors like circular dependencies, SSR failures, or broken module initialization.

<!--
duvet= docs/specs/fx-dev-authority/index.md#merge-gates-apply-regardless-of-change-size
duvet= type=implication
duvet# The size, triviality, or follow-up status of a pull request MUST NOT be treated as grounds for waiving any merge gate.
-->

**If a "small" or "follow-up" PR:** Same rules. No exceptions. PR size is NEVER a reason to skip merge gates.

## PRE-MERGE: Change-Doc Status Flip (BLOCKING)

**The FINAL PR for a change document MUST mark the change `complete` IN that PR — NOT in a follow-up.** A change doc still showing `**Status:** draft` after its last implementing PR merges is a bug; the docs lie about state and the index is out of sync with reality on `main`.

There are two places to flip:

1. **Change doc body** — `docs/changes/<NNNN>-<slug>.md` — flip the front-matter line `**Status:** draft` → `**Status:** complete`.
2. **Index** — `docs/index.yml` — flip `status: draft` → `status: complete` on that change's entry. Sync `docs/index.md` if the project keeps both.

### Whose job is it?

**The implementing coder is responsible for the flip** when they are shipping the final piece of a change. That coder's PR description should already note "this completes 0094"; they MUST also include the Status flip in the same PR.

**The coordinator's job, BEFORE merging, is to verify the flip is in the PR's diff.** Add this to your PR-inspection step (Gate 3 — implementation matches spec). If the flip is missing:

1. **Do NOT merge.**
2. Push a tiny commit to the PR branch yourself (or via a focused fix agent) flipping both files. Commit message: `docs(changes): mark <NNNN> complete`.
3. Wait for CI to re-pass on the new commit.
4. Then merge.

This MUST NOT become a follow-up PR. Doing it post-merge means main spent some window in a wrong state, and the user sees a stale `draft` for every change you ship.

### Multi-PR changes

When a change decomposes into multiple PRs (e.g., 0090 split into 0090A and 0090B): only the LAST implementing PR flips Status. Earlier sub-PRs MUST leave Status as `draft`. The coordinator decides which PR is "last" — typically the final task in the change doc's task list. Tell THAT coder explicitly in their spawn prompt to include the Status flip; tell every other coder to leave Status alone (multi-PR rebases against a flipped Status field create spurious conflicts).

If you mis-identified which PR was last and you've already merged a sub-PR with `Status: complete` flipped early, the doc is wrong on main until the remaining PRs land — open a tiny corrective PR flipping it back to `draft` until the real final PR lands.

### Partial implementations

If a single PR is only a partial implementation of its change doc (more PRs to come), the PR MUST leave Status as `draft`. The Status flip rides only with the final piece.

## STEP 4: Shutdown

When all tasks are complete and all PRs merged:

1. Verify all spec tasks are marked done (load `project-management` to check)
2. **Verify every implemented change is `status: complete`** on `main` — check both `docs/changes/<NNNN>-*.md` front-matter AND `docs/index.yml`. If any are still `draft`, you missed the pre-merge gate; open a corrective PR right now (the goal is the gate catches it pre-merge, but if it slipped, fix it before declaring done).
3. Send shutdown requests to all active teammates (refer to each by `name`); each teammate approves and exits gracefully
4. **Tear down every worktree created in STEP 2.5.** For each one, in order: remove the `node_modules` symlink first (so `git worktree remove` doesn't traverse into the shared deps), then `git worktree remove --force <path>`, then `git worktree prune`. Delete the branch with `git branch -D <branch>` only if it's unmerged/abandoned (a merged PR's branch is already gone from origin). Confirm `git worktree list` shows only the main repo and `git status` is clean before continuing.

   ```bash
   rm -f <REPO_ROOT>/[AGENT_DIR]/worktrees/<slug>/node_modules
   git worktree remove --force <REPO_ROOT>/[AGENT_DIR]/worktrees/<slug>
   git worktree prune
   git branch -D <branch>   # only if unmerged/abandoned
   ```
5. **There is no teardown step.** Do not look for one, and on Claude Code do not call `TeamDelete` — it no longer exists. Session-scoped team state is cleaned up automatically on exit; a shared task list that persists locally does so by design, so resumed sessions keep their tasks. That is expected, not a leak. Your only manual cleanup is the worktrees in step 4.
6. Report final summary to user

---

## Coordinator Rules (NON-NEGOTIABLE)

- **ALWAYS pass `name` to EVERY `Agent` call** — coder, verify, fix, anything. `name` is what makes the teammate addressable via `SendMessage` and visible in `members[]`; omitting it produces an anonymous worker you can't steer by name. No exceptions.
- **NEVER provision or tear down a team.** On Claude Code that means never passing `team_name` (accepted-but-ignored) and never calling `TeamCreate`/`TeamDelete` (removed) — the team is implicit, session-scoped, and cleaned up on exit. On any host: there is nothing to create, so an attempt to create it is a bug.
- **NEVER rely on `isolation: "worktree"` for a teammate** — a teammate runs as a full session in the lead's working directory, so the flag is a no-op. For any coders that run concurrently, pre-create real worktrees under `[AGENT_DIR]/worktrees/` and pin each via the prompt preamble (STEP 2.5). If you don't, run coders strictly one-at-a-time. Always tear the worktrees down in STEP 4.
- **NEVER write code yourself** — all implementation goes through coder agents
- **NEVER create branches or commits** — coder agents handle this
- **NEVER delegate the full SDLC to a single agent** — it inlines everything and skips the later steps. True on every host: the failure is prompt scope, not whether delegates can nest
- **NEVER skip PR inspection** — every PR gets reviewed before marking ready
- **NEVER merge without completing the MERGE GATE CHECKLIST** — every gate must pass, every time, for every PR
- **NEVER merge without Copilot review** — always invoke `copilot-review` yourself. No exceptions.
- **ALWAYS attempt CodeRabbit when configured, but never block on its rate limits** — invoke `coderabbit-review`; resolve feedback already received, then record `skipped (rate-limited)` and continue immediately if throttled.
- **NEVER `sleep` or poll on a wait.** Every reviewer and CI wait is a long-running script whose result you reconcile once, on the wake your host provides (notification on Claude Code, a returning `wait_agent` on Codex — **Waiting and reconciliation**). On Claude Code a foreground waiter is killed at the Bash tool's 600 s cap anyway, and the only timer permitted in a run is one long `ScheduleWakeup` silence backstop.
- **NEVER mark a teammate's PR as ready** until you've inspected it
- **ALWAYS handle Copilot review and CI monitoring directly** — these are coordinator responsibilities, not sub-agent responsibilities. Launch their waiters backgrounded, all in one message.
- **ALWAYS pass a deliberate `model` size to every `Agent` call** — see the size table in STEP 3. Coders are `large`; never downgrade them.
- **ALWAYS use `project-management`** to verify task tracking
- **ALWAYS run the full merge gate checklist** even for "trivial" or "follow-up" PRs
- **NEVER merge without browser verification** — spawn a verify agent if needed. CI alone does NOT catch runtime errors.
- **NEVER merge the FINAL PR of a change doc with `Status: draft` still in the diff.** The flip to `complete` rides in that PR, in both `docs/changes/<NNNN>-*.md` and `docs/index.yml`. If the coder forgot, push a fix commit to their branch and wait for CI before merging. Do NOT defer to a follow-up PR. See PRE-MERGE: Change-Doc Status Flip above.

## Handling Agent Issues

If a coder agent reports problems:

1. Read the error details from their message
2. Spawn a new focused agent to fix the specific issue
3. If stuck after 2 retries, report to user and ask for guidance
