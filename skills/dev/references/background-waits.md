# Background waits

**The canonical rules for waiting on an EXTERNAL completion** — a reviewer, a CI run, a teammate agent, or any long-running one-shot tool that finishes on its own schedule and reports when it does. Every skill in this catalog that waits on one of those names this file rather than restating it (`fx-review` § The two canonical sources applies the same define-once rule to review definitions).

`[AGENT_DIR]` below is the host's own per-repo agent directory — substitute your host's value from `host-adapters.md` § `[AGENT_DIR]`.

**This file and `host-adapters.md` § Long waits split one subject between them; neither restates the other.** § Long waits is canonical for the **per-host mechanism**: which spelling runs a 900 s waiter on your host, which ceiling that shape evades, and whether a completion notification exists at all. This file is canonical for the **discipline**: what counts as an external completion, that you never invent a wait of your own, how a hand-rolled wait fails, and that the rule binds the agents you delegate to. Read your host's row there for the mechanism; read this for the rule.

A skill that waits still documents its **own** invocation — which script, which arguments, which log path, and how to branch on the result. What it must not restate is anything below.

### What this does NOT govern

**A bounded readiness or teardown wait inside a single command is not one of these, and this file does not forbid it.** A loop that polls a service it just started — `for i in $(seq 1 30); do curl -sf "$URL" && break; sleep 2; done` — is part of one command whose next step depends on it, is bounded by its own iteration count, and has no completion notification to wait for. Backgrounding it would break the sequence it exists to order. `verify-web-change` uses exactly these for Docker, Compose health, and dev-server readiness, and they are correct.

The line is **who signals completion**: if something outside your command will tell you it finished, run it as a long wait and wait for that signal. If nothing will, and you are gating the next line of your own script, a bounded in-command poll is right.

## The rule

**⛔ Never `sleep`, poll, or block waiting on one of these.** Every such wait runs in the shape your host's row prescribes in `host-adapters.md` § Long waits, redirecting stdout and stderr to a log file, and you read that log when the wait resolves. On Claude Code that shape is `run_in_background: true` with the completion notification as your only scheduling mechanism; on Codex it is a small-tier teammate that runs the script and reports its `STATUS=` line, with `wait_agent` on that teammate. Take the shape from the table, not from the example syntax in a skill.

```bash
mkdir -p [AGENT_DIR]/team/waits && \
bash <wait-script> <args> > [AGENT_DIR]/team/waits/<name>.log 2>&1
```

Your context does not change the answer — root session, `team` coordinator, and delegate all follow the same row — so there is no "which mode am I in?" branch to agonise over. What the row prescribes is another matter, and it differs per host.

**Never launch a wait without the redirect.** The caller reacts to what the script prints; without a log there is nothing to read when the wait resolves.

Launch independent waits **concurrently** — on Claude Code, every call in one message — so they overlap instead of queueing. Where your host's row makes each waiter a delegate, they also spend its concurrency slots; count them before launching a third.

## Why not the foreground

Every host caps the call that holds a wait below the 900 s budget these scripts run to, so a wait held in the calling turn is *guaranteed* to be cut off mid-poll, printing no `STATUS` and no exit code — which is exactly what used to force blind re-runs. `host-adapters.md` § Long waits names each host's ceiling and the shape that survives it.

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
