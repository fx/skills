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
| 3 | **Wait** | The coordinator can block on one or more delegates and read each result. **Whether a finished delegate wakes the coordinator, or the coordinator must ask, is host-specific — check your row before writing a wait loop or omitting one** |
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
| Wait | Completion notification for a backgrounded `Agent` wakes the coordinator; `TaskOutput` for its report. Nothing to poll, and a live teammate survives the coordinator's turn ending |
| Message | `SendMessage` to the agent's `name` or id |
| Ask the user | `AskUserQuestion` |
| Run long, concurrently | `Bash` with `run_in_background: true`, redirect to a log, read the log on notification |
| Scratch space | `.claude/team/` (`[AGENT_DIR]` = `.claude`) |

Capabilities that shape orchestration here:

- **Delegates cannot themselves delegate.** One implicit, session-scoped team; teammates cannot spawn teammates. This is why the coordinator owns every SDLC step rather than handing one agent the whole lifecycle.
- **No per-spawn reasoning effort.** Effort is inherited from the session (`effortLevel` / `CLAUDE_EFFORT`). The tier selects a model; it does not select how hard the delegate thinks.
- **The `small` tier carries a 200k context ceiling** — a feature for read-heavy roles, since it bounds context growth for free.
- A foreground `Bash` timeout is capped below the 900 s waiter budget, which is why waiters *must* be backgrounded.

### Codex

| Op | Mapping |
|---|---|
| Delegate | `spawn_agent` — `task_name`, `message`, `fork_turns`, and (only with `fork_turns` set) `model` / `reasoning_effort`. Returns the canonical name `/root/<task_name>`. **`task_name` accepts only lowercase letters, digits, and underscores** — a hyphenated handle is rejected outright, so `coder-0105a` must be spelled `coder_0105a` |
| Load a skill | Name the skill in the child's `message` **and give the absolute path to its `SKILL.md`** — there is no `Skill` tool, the child just reads the file |
| Wait | `wait_agent` (explicit, takes `timeout_ms`); `list_agents` for a status snapshot |
| Message | `send_message` (delivers without triggering a turn), `followup_task` (delivers and triggers one), `interrupt_agent` to stop one |
| Ask the user | A normal user turn — or structured user input where the host exposes it |
| Run long, concurrently | `exec_command`, which returns a `session_id` when its `yield_time_ms` elapses (**max 30 000 ms**, verified) and leaves the command running; re-read that session to collect the rest. See § Long waits below — a 900 s waiter needs a different shape here |
| Scratch space | `.agents/team/` (`[AGENT_DIR]` = `.agents`), or the host's own agent working directory |

Capabilities that shape orchestration here — all of the following verified against codex-cli 0.145.0 **and re-verified unchanged on 0.151.0**, on 2026-08-30, by reading the session's own developer instructions and by running spawn tests:

- **⛔ Waiting is explicit, and ending a turn kills live children.** A child's `FINAL_ANSWER` is delivered to the parent with `trigger_turn: false` — it lands in the parent's context but does **not** wake it. There is no completion notification. If the coordinator ends its turn while a teammate is running, the run terminates and the teammate is interrupted mid-task (observed: child aborted 0.2 s after the root's turn ended, `reason: interrupted`). **The coordinator must `wait_agent` before it stops.** This is the single largest behavioural difference from Claude Code, where the notification does wake you and blocking is the bug. Codex itself asks for long waits — *"prefer longer waits (minutes) to avoid busy polling"* — so give `timeout_ms` minutes, not seconds; a short timeout turns the blocking primitive back into a poll loop.

- **Teammates are first-class threads, so they are inspectable from outside the session.** Every spawn writes its own row to the shared thread store (`~/.codex/state_5.sqlite`) with `source = {"subagent":{"thread_spawn":{parent_thread_id, depth, agent_path, agent_nickname}}}`, plus an edge in `thread_spawn_edges(parent_thread_id, child_thread_id, status)` and its own rollout under `~/.codex/sessions/`. That holds for `codex exec` runs too, not just daemon-hosted ones. The in-session view is `list_agents` (`/root` plus each child and its state); out of session, the store and the rollouts are the ground truth. Note that `thread_spawn_edges.status` has been observed still reading `open` for children that finished long ago — do not treat it as liveness.
- **Delegation must be explicitly asked for.** Every session carries `<multi_agent_mode>`: *"Do not spawn sub-agents unless the user or applicable AGENTS.md/skill instructions explicitly ask for sub-agents, delegation, or parallel agent work."* A skill that means to fan out must say so in those words. Prose about "the Agent tool" does not read as an ask, and a child inherits the same restriction — so a child that should fan out has to be told to, in its `message`.
- **Four concurrency slots, including the coordinator** — at most three teammates active at once. Spawns beyond that queue, and a queued spawn looks exactly like a hung one. Size waves to the slot count.
- **`fork_turns` decides what the child sees, and gates the tier.** Omitted or `"all"` means a full-history fork: the child inherits the parent's whole context *and* its model and effort, and **override attempts are rejected**. Pass `fork_turns: "none"` (or a positive integer string) to set `model`/`reasoning_effort` per spawn — which the size table in `dev`/`team` requires. With `"none"` the child sees only the `message`, so the Scope Brief must be in it verbatim.
- **Delegates CAN delegate.** Codex children spawn their own children, so the agent tree is not flat. The coordinator-owns-the-SDLC rule still applies (see below), but as a design choice rather than a platform limit.
- **No isolation flag exists, and all agents share one filesystem and one working directory.** Edits by one are immediately visible to the others. Worktree pinning by prompt preamble (`team` STEP 2.5) is the only isolation there is.
- **There is no three-model ladder to map the tiers onto.** Codex currently exposes two general-purpose coding models, so resolve the tier with the effort dial as well: `large` = the stronger model at `high`, `medium` = the same model at `medium`, `small` = the faster model at `low`. Do not report the tier as unmappable and silently default the spawn — that puts every teammate at the coordinator's model.
- **Collaboration tools are not callable from inside `functions.exec`.** They are deliberately absent from the `tools.*` namespace, so a spawn attempted inside a code-mode batch does not happen. Call them as direct tool calls (`to=functions.collaboration.spawn_agent`).

### Long waits: the 900 s waiter scripts, per host

Every reviewer and CI waiter in this catalog runs to a 900 s budget and prints a `STATUS=` line on exit. The workflow skills forbid polling because on Claude Code polling is pure waste — but *how you learn the script finished* is an operation (op 6 plus op 3), and it does not have the same answer everywhere. Take the shape from this table, not from the example syntax in a skill:

| Host | Shape |
|---|---|
| Claude Code | `Bash` with `run_in_background: true` and a redirect to a log; the completion notification wakes you; read the log then. A foreground call is capped at 600 000 ms — below the 900 s budget — so it is killed mid-poll. **Do not delegate the wait to a sub-agent: it buys nothing over the notification.** |
| Codex | There is no completion notification and `exec_command` yields after at most 30 s, so a single call cannot span the budget. **Delegate the waiter to a teammate** — `spawn_agent` a small-tier child whose only job is to run the script and report its `STATUS=` line, then `wait_agent` on that child with a `timeout_ms` of minutes. That converts ~30 collection reads at full coordinator context into one blocking wait, and the child pays the context cost. Re-reading the `exec_command` session yourself is the fallback when delegation is unavailable, and it is the only case in this catalog where a bounded re-read is the correct behaviour rather than the forbidden one. |

The rule the skills state — *never spend coordinator turns on a timer* — is unchanged by either row. What changes is which mechanism satisfies it.

### `[AGENT_DIR]` — the in-repo agent directory

Scratch space (op 7) and team worktrees live under the host's own agent directory inside the repo. The skills write it as `[AGENT_DIR]`; substitute your host's value, with no trailing slash:

| Host | `[AGENT_DIR]` |
|---|---|
| Claude Code | `.claude` |
| Codex | `.agents` |
| Anything else | Whatever directory that host already keeps its per-repo state in — add the row here |

**A literal `.claude/` path on a non-Claude host is a bug, not a harmless default.** It puts coordination artifacts, waiter logs, and review findings into another agent's state directory, where the running host neither ignores nor cleans them and the user does not look for them. If a skill in this catalog still shows a bare `.claude/` path outside a Claude-Code-specific note, fix the skill.

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
| `[AGENT_DIR]/team/...` | A path under scratch space (op 7) — `.claude/team/...` on Claude Code, `.agents/team/...` on Codex |

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
