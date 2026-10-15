---
name: shell
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. Rules for agent-run shell commands: stopping and waiting on processes by PID instead of pattern, the shell dialect actually running, visible exit statuses, and non-interactive invocation."
---

# Shell — Rules for Agent-Run Commands

> **Path note:** `[SKILLS_DIR]` below is the directory holding this skill's own folder —
> the parent of the directory containing this `SKILL.md`. Substitute its absolute path;
> every skill referenced below is installed as a sibling there.

Shell mistakes agents have actually made, most damaging first — each is the rule, the failure that was observed, and the idiom to use instead. Host-specific behaviour is in § Host notes and nowhere else.

**The one fact behind most of this:** your whole command, patterns included, is the command line of a shell that is still running while it executes — and so is a string you send through `ssh`, or through `sh -c` under `kubectl exec` / `docker exec`. Anything that searches command lines can find that shell. Mechanics: `references/process-control.md`.

## Stop a process by PID or through what owns it, never by pattern

**Never stop a process with `pkill -f`, `killall`, `kill $(pgrep -f …)` or `ps | grep … | xargs kill`.** The pattern matches your own shell, which dies with the target. Observed 26 times in 15 sessions: `pkill -f "<cli> package start"; yarn build | tail -6` killed its own shell and the build never ran. Filtering the matches in a loop does not help — the loop's own command line passes its filter.

Stop it **through its owner** (`docker compose down`, `docker stop <container>`, the host's own stop for a task it backgrounded), or **by the PID you kept** at launch.

**The one exception — a one-time stop of something you did not start, with no owner and no PID:** list with the bracket trick, `pgrep -af '[s]erver --port 4000'`, check the PIDs, then `kill` those PIDs. `[s]erver` does not match its own command line, but it stops working the moment the unbracketed string appears anywhere else in the same command, and it is **never a wait condition**.

## Start only what you can stop

**Every process you start in the background must leave you its PID.** Without one, cleanup falls back to a pattern: 11 of the 15 self-kill sessions had launched something untracked first, such as `(kubectl port-forward svc/<svc> <port> &)` followed later by `pkill -f "port-forward …"`.

- Prefer the host's run-long mechanism (`[SKILLS_DIR]/dev/references/host-adapters.md` op 6). Otherwise `&`, with `$!` saved on the next statement:

```bash
dir=$(mktemp -d)
./start-server > "$dir/server.log" 2>&1 &
pid=$!
```

- **Never `( … &)`, `nohup`, `setsid` or `disown` without keeping the PID** — `( … &)` loses `$!` inside the subshell.
- **A launch the host already backgrounds gets no `&`, `nohup` or `disown` of its own.** `&` hands back the wrapper's status in milliseconds — observed read as a finished review over a truncated log; `disown` drops the job, so `wait` returns 0 at once even for a live or failed job (reproduced); `nohup` does nothing once output is redirected. The wait rules around it are `[SKILLS_DIR]/dev/references/background-waits.md`'s.
- **A launcher that forks** (`npm run dev`, an `sh -c` wrapper) leaves the server as a child of the PID you kept; killing only that PID orphans the server. Start it in its own process group and stop the group (`references/process-control.md`).
- **Stop what you started before you report done.** Dev servers have been left running for up to 32 hours.

## Wait on the thing itself

**Never wait on a process pattern.** `until ! pgrep -f '<runner> eval --filter <x>'; do sleep 15; done` matched its own shell and ran 23.3 hours; `until ! ssh <host> 'pgrep -f <mover> >/dev/null'; do sleep 60; done` ran 4.2 hours, because the remote shell matched too.

An external completion — a reviewer, CI, a long script that reports through a log — follows `[SKILLS_DIR]/dev/references/background-waits.md`. Inside one command, a poll that gates the next line must be bounded, must check that the producer is still alive, and must fail when the gate fails:

```bash
ready=false
for i in $(seq 1 30); do
  if grep -q 'listening on' "$dir/server.log"; then ready=true; break; fi
  kill -0 "$pid" 2>/dev/null || break
  sleep 2
done
if ! "$ready"; then
  echo "server not ready" >&2
  tail -n 20 "$dir/server.log" >&2
  exit 1
fi
```

`exit 1` ends the command with a failing status so nothing after the poll runs (`return 1` inside a function); a failure branch that ends on its `echo` or `tail` exits 0 and the gate passes. The waits observed finishing in under a minute all checked real state like this — a ready line, a `Ready` status, a ping.

## Know which shell runs your command

**Do not assume bash** — the host may run your command under the user's zsh (§ Host notes). The traps observed there:

- **`=word` is expanded.** `cat a; echo ===; cat b` fails with `== not found` and `b` never runs (54 times in 37 sessions). Quote it: `echo '==='`.
- **A glob that matches nothing aborts its command.** `grep -rn x --include=*.md` reports `no matches found` and never runs (165 times), while the list carries on and can still exit 0. Quote it: `--include='*.md'`.
- **`$cmd` is not word-split.** `S="ssh -i k <host>"; $S cmd` fails with `no such file or directory: ssh -i k <host>`. Use an array: `s=(ssh -i k "$host"); "${s[@]}" cmd`.
- **Aliases are loaded.** `grep` aliased to `ugrep` errored in 20 calls across 16 sessions. `command grep` bypasses the alias.

## Keep exit statuses and output visible

**A pipeline reports the status of its last command, and `tail` prints only at the end.** `<installer> --install 2>&1 | tail -20` hit the call timeout showing nothing at all, then ran on for 14.8 hours.

- Redirect to a log, then read it: `<cmd> > "$dir/out.log" 2>&1; rc=$?; tail -n 40 "$dir/out.log"; exit "$rc"`.
- When you must pipe, `set -o pipefail` or read `PIPESTATUS` (bash) / `pipestatus` (zsh); under `pipefail` a producer cut off by `head` exits 141, which is not a failure.
- Cap what you read — `head -n`, `grep -m`, `sed -n '200,260p'`. Thirty-two results over 30 KB were observed, each spending context on noise.

## Never block on a prompt

Nobody is there to answer. Observed: `ssh <host> '… sudo …'` failed with "a terminal is required"; nine commands, mostly `ssh`, hung until the user backgrounded them by hand; a debconf prompt; a `git rebase -i`; a pager.

- `sudo -n`, and `ssh -n -o BatchMode=yes -o ConnectTimeout=10 <host> '<cmd>'`.
- `DEBIAN_FRONTEND=noninteractive apt-get -y …`.
- `GIT_EDITOR=true`, `GIT_PAGER=cat`; never `git rebase -i`.

## Never put a secret in a command

**A command line is readable by every user through `ps`, and the transcript keeps it.** Observed in three transcripts: an API key in a `curl` header, a password in `SSHPASS=`, and a password typed with `tmux send-keys`. Pass it through a builtin on stdin, or from a file:

```bash
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - https://example.com/api
sshpass -f "$dir/pass" ssh "$host" uptime
```

If a secret shows up in output, do not repeat it — tell the user so it can be rotated.

## Host notes

Observed on the version named — verify on yours. The per-host mechanisms for long runs and waits are `[SKILLS_DIR]/dev/references/host-adapters.md`'s and are not restated here.

**Claude Code** (2.1.296):

- A command runs as `/usr/bin/zsh -c "source <snapshot> && … eval '<cmd>' < /dev/null"` — the user's zsh, whatever the environment reports, with their aliases loaded from the snapshot. Your whole command is inside that `-c` string, which is why a pattern from it self-matches.
- A self-kill shows as **exit 144**, with no output from the steps after it.
- Stdin is `/dev/null`, so most prompts fail at once rather than hang.
- zsh refuses `set -m` without a terminal (`can't change option: -m`), so the process-group start in `references/process-control.md` runs from a bash script file.
- A command that hits the foreground timeout is moved to the background, not killed; older versions killed it with exit 143. The run-long mechanism is `run_in_background: true`.
- The working directory is reset between calls ("Shell cwd was reset"); use absolute paths.

**Codex** (codex-cli 0.159.0):

- `exec_command` runs a command as `/usr/bin/bash -lc '<cmd>'` — a login bash, so the self-match is the same and the zsh traps are not. Incident write-ups that say `bash -c` describe this shape.
