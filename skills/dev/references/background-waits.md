# Background waits

**The canonical rules for waiting on an EXTERNAL completion — a long-running script or one-shot tool that finishes on its own schedule and reports through a log it writes.** A reviewer waiter and a CI waiter are the common cases. So is that same script wrapped in the waiter teammate a host's row prescribes for running it: the teammate returns through your host's agent result, but the script is what writes the log, and these rules govern the wait either way. Every skill in this catalog that needs such a wait names this file instead of restating the rules (`fx-review` § The two canonical sources applies the same define-once rule to review definitions).

`[AGENT_DIR]` below is the host's own per-repo agent directory — substitute your host's value from `host-adapters.md` § `[AGENT_DIR]`.

**This file and `host-adapters.md` § Long waits split one subject between them; neither restates the other.** § Long waits is canonical for the **per-host mechanism**: which spelling runs a 900 s waiter on your host, which ceiling that shape evades, and whether a completion notification exists at all. This file is canonical for the **discipline**: what counts as an external completion, that you never invent a wait of your own, how a hand-rolled wait fails, and that the rule binds the agents you delegate to. Read your host's row there for the mechanism; read this for the rule.

A skill that waits still documents its **own** invocation — which script, which arguments, which log path, and how to branch on the result. What it must not restate is anything below.

### What this does NOT govern

**A bounded readiness or teardown wait inside a single command is not one of these, and this file does not forbid it.** A loop that polls a service it just started — `for i in $(seq 1 30); do curl -sf "$URL" && break; sleep 2; done` — is part of one command whose next step depends on it, is bounded by its own iteration count, and has no completion notification to wait for. Backgrounding it would break the sequence it exists to order. `verify-web-change` uses exactly these for Docker, Compose health, and dev-server readiness, and they are correct.

The line is **who signals completion**: if something outside your command will tell you it finished, run it as a long wait and wait for that signal. If nothing will, and you are gating the next line of your own script, a bounded in-command poll is right.

**An ordinary delegate is not one of these either, and nothing below applies to waiting on one.** A coder, a verify agent, a reviewer sub-agent — anything whose result your host hands back to you directly — reports through its own agent result, not through a log you read. The only teammate this file governs is the **waiter** child a host's row prescribes for running a wait script and reporting its `STATUS=` line.

**Where your host requires a blocking wait on outstanding teammates before your turn ends, that wait is mandatory and is not the polling forbidden below.** On Codex, ending the turn kills every live child, so `wait_agent` on each outstanding teammate is the host's own blocking primitive and skipping it destroys the run. `host-adapters.md` § Long waits and op 3 are canonical for which hosts require it and how; read your row there before deciding whether to wait on a delegate at all.

## The rule

**⛔ Never `sleep`-loop, poll, or hand-roll a wait of your own on one of these.** Every such wait runs in the shape your host's row prescribes in `host-adapters.md` § Long waits, redirecting stdout and stderr to a log file, and you read that log when the wait resolves. On Claude Code that shape is `run_in_background: true` with the completion notification as your only scheduling mechanism; on Codex it is a small-tier teammate that runs the script and reports its `STATUS=` line, with `wait_agent` on that teammate. **Where your host's row prescribes a blocking primitive — Codex's `wait_agent` — calling it IS this rule, not an exception to it**; what is forbidden is the wait you invent, never the one the host hands you. Take the shape from the table, not from the example syntax in a skill.

```bash
mkdir -p [AGENT_DIR]/team/waits && \
bash <wait-script> <args> > [AGENT_DIR]/team/waits/<name>.log 2>&1
```

Your context does not change the answer — root session, `team` coordinator, and delegate all follow the same row — so there is no "which mode am I in?" branch to agonise over. What the row prescribes is another matter, and it differs per host.

**Never launch a wait without the redirect.** The caller reacts to what the script prints; without a log there is nothing to read when the wait resolves.

Launch independent waits **concurrently** — on Claude Code, every call in one message — so they overlap instead of queueing. Where your host's row makes each waiter a delegate, they also spend its concurrency slots; count them before launching a third.

## Why not the foreground

**Every host with a row in `host-adapters.md` § Long waits** caps the call that holds a wait below the 900 s budget these scripts run to, so on those hosts a wait held in the calling turn is *guaranteed* to be cut off mid-poll, printing no `STATUS` and no exit code — which is exactly what used to force blind re-runs. That table names each ceiling and the shape that survives it. A host whose row establishes no ceiling is not covered by this paragraph — but read the row before concluding that, because the reason travels: 900 s is a long time to hold one call open, and a host that cannot is the common case, not the exception.

Polling the log yourself is no better: a buffered tool writes nothing until it finishes, so an early read teaches you nothing and costs a full context read every time. For a coordinator this is the single most expensive thing you can do — every wake re-reads the largest context in the team, and it gets more expensive with every turn added.

## ⛔ Never invent your own wait

Use your host's own mechanism and nothing else. A hand-rolled wait has failed in production in a way that is silent and total.

**Never poll with a pattern that can match the watching command itself.** This loop deadlocked a run for 49 minutes:

```bash
# ⛔ BROKEN — never exits, even after the watched process has finished
until ! pgrep -f 'codex review -c' >/dev/null 2>&1; do sleep 15; done
```

`pgrep -f` matches against **full command lines**, and the watching shell's own command line contains the literal `codex review -c`. The pattern matches the watcher, `pgrep` always succeeds, the `until` condition is never true, and the loop spins long after the real process exited and wrote its output. Nothing errors and nothing is logged; the wait simply never ends.

The trap is general: **any** `pgrep -f`, `ps | grep`, or `pkill -f` whose pattern appears in its own invocation self-matches.

**Do not reach for a "safer" process check — there isn't one.** `pgrep -x <name>` drops the self-match but cannot tell your run from any other process of the same name. `pgrep -f <pattern> | grep -v $$` is worse: it filters PID *text* by substring (so `$$` of `123` also drops `1234`), and it removes only the current shell, leaving any parent or wrapper whose command line contains the pattern to keep the check true. Either one can recreate the very wait this section exists to prevent.

**The output file is the signal** — a finished run is a log that has stopped growing, with a `STATUS`/summary at its tail. Read it when the wait resolves.

## When a wait seems hung

Check the log's **mtime against the clock before assuming the tool is slow.** A log that stopped growing minutes ago means the tool finished and the *wait* is what broke. Suspect the wait, not the tool.

## The rule binds delegates too

A delegate left to invent its own wait writes exactly the loop above. **Any prompt you hand an agent that could wait on a long-running tool MUST carry this rule explicitly** — no `sleep` polling, and no self-matching process patterns.
