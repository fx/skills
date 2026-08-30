# Host Adapters

**The workflow skills describe operations. This file maps each operation to the host you are running on.**

Every orchestration skill in this catalog — `dev`, `team`, `workflow-runner`, `fix`, and the reviewer adapters — is written against the seven operations below. None of them is Claude-Code-specific as an *operation*; only the syntax is. Where a skill shows a concrete call, read it as an example of the operation, not as the only spelling of it.

**If your host is not listed here, map the operations yourself before running the skill, and add the mapping to this file.** An operation you cannot map is a real blocker — say so rather than improvising a substitute, because every one of these carries a guarantee the workflow depends on.

---

## The operations

| # | Operation | Guarantee the workflow relies on |
|---|---|---|
| 1 | **Delegate** | Work runs in a *separate context* with its own instructions, at a chosen capability tier, and reports back |
| 2 | **Load a skill** | The delegate begins with a named skill's full instructions in context |
| 3 | **Wait** | The coordinator can block on one or more delegates and read each result |
| 4 | **Message** | A correction reaches a *running* delegate without restarting it |
| 5 | **Ask the user** | Execution stops until a human answers; the answer is not inferred |
| 6 | **Run long, concurrently** | A multi-minute command runs without blocking the coordinator, and its output is retrievable |
| 7 | **Scratch space** | A working directory for coordination artifacts that is not part of any change |

---

## Host mappings

### Claude Code

| Op | Mapping |
|---|---|
| Delegate | `Agent` tool. `name` (addressable handle), `prompt`, `description`, `model` (tier), `isolation`, `run_in_background` |
| Load a skill | `Skill` tool inside the delegate's prompt: `Skill tool: skill='<name>'` |
| Wait | Completion notification for a backgrounded `Agent`; `TaskOutput` for its report |
| Message | `SendMessage` to the agent's `name` or id |
| Ask the user | `AskUserQuestion` |
| Run long, concurrently | `Bash` with `run_in_background: true`, redirect to a log, read the log on notification |
| Scratch space | `.claude/team/` |

Capabilities that shape orchestration here:

- **Delegates cannot themselves delegate.** One implicit, session-scoped team; teammates cannot spawn teammates. This is why the coordinator owns every SDLC step rather than handing one agent the whole lifecycle.
- **No per-spawn reasoning effort.** Effort is inherited from the session (`effortLevel` / `CLAUDE_EFFORT`). The tier selects a model; it does not select how hard the delegate thinks.
- **The `small` tier carries a 200k context ceiling** — a feature for read-heavy roles, since it bounds context growth for free.
- A foreground `Bash` timeout is capped below the 900 s waiter budget, which is why waiters *must* be backgrounded.

### Codex

| Op | Mapping |
|---|---|
| Delegate | `spawn_agent`, with per-spawn model and `reasoning_effort` |
| Load a skill | Name the skill in the child's prompt; the child reads its `SKILL.md` |
| Wait | `wait_agent`; `list_agents` to see what is outstanding |
| Message | `send_message`, or `followup_task` |
| Ask the user | A normal user turn — or structured user input where the host exposes it |
| Run long, concurrently | A persistent command session, polled via its stdin/stdout handle |
| Scratch space | `.agents/team/`, or the host's own agent working directory |

Capabilities that shape orchestration here:

- **Delegates CAN delegate.** Codex children spawn their own children, so the agent tree is not flat. The coordinator-owns-the-SDLC rule still applies (see below), but as a design choice rather than a platform limit.
- **Reasoning effort is settable per spawn**, independently of the model. Where this catalog says a role is judgment-heavy, raise effort as well as tier.
- Concurrency is bounded per session — check the limit rather than assuming it is unbounded.

> **Verify these names against your host before relying on them.** Tool surfaces move, and a mapping table is exactly the kind of document that rots into confident wrongness. If a name here is wrong, the fix is to correct this file, not to work around it in a skill.

---

## Reading the skills' example syntax

The workflow skills show Claude Code syntax inline, because writing every call twice would double their length and guarantee the two copies drift. Translate as you read:

| Written in a skill | Means |
|---|---|
| `Skill tool: skill="<name>"` | Load skill `<name>` (op 2) |
| `Agent tool:` + a field block | Delegate (op 1) with those fields |
| `run_in_background: true` | Run long, concurrently (op 6) |
| `AskUserQuestion` | Ask the user (op 5) |
| `SendMessage` | Message a running delegate (op 4) |
| `.claude/team/...` | A path under scratch space (op 7) |

The **fields** of a delegate call, which every host needs in some spelling:

| Field | Purpose | Required? |
|---|---|---|
| handle | Addressable name, so the delegate can be messaged and its report attributed | Yes |
| tier | `large` / `medium` / `small` — see the size table in `dev` or `team` | Yes |
| skill | Which skill the delegate loads first | Usually |
| prompt | The task, plus the Scope Brief verbatim | Yes |
| isolation | Whether it works in a separate checkout | Where the skill says so |
| background | Whether the coordinator continues while it runs | Where the skill says so |

---

## The coordinator-owns-the-SDLC rule is not a platform limit

`team` requires the coordinator to orchestrate each SDLC step and give every delegate one focused job, rather than handing a single agent "the whole lifecycle."

On Claude Code that is also enforced by the platform, since delegates cannot delegate. **On a host where they can — Codex — it remains the rule anyway**, for the reason that motivated it in the first place: an agent told to run a whole lifecycle inlines the implementation instead of delegating it, fills its context, and skips the later stages. That failure is about prompt scope, not about capability, so a host that permits the nesting does not remove it.

What *does* change on such a host: a delegate may legitimately spawn helpers **within its one focused job** — a coder fanning out reads across a large tree, say. That is not the same as handing it the lifecycle, and the rule does not forbid it.
