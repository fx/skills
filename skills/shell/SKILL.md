---
name: shell
description: "Explicit-use only — invoke when the user explicitly names this skill, or when an active explicitly invoked workflow calls it. Rules for agent-run shell commands: stopping and waiting on processes by PID instead of pattern, the shell dialect actually running, visible exit statuses, and non-interactive invocation."
---

# Shell — Rules for Agent-Run Commands

> **Path note:** `[SKILLS_DIR]` below is the directory holding this skill's own folder —
> the parent of the directory containing this `SKILL.md`. Substitute its absolute path;
> every skill referenced below is installed as a sibling there.

The shell mistakes agents actually make, most damaging first: each is a rule, the reason, and the idiom to use instead. Which shell your host wraps your command in, and how a failure shows up there, is in § Host notes and nowhere else.

Pid and log files go in the host's scratch space or a fresh `mktemp -d` directory — never a fixed `/tmp/<name>` path, which a concurrent run overwrites, and never the repository.

## The one fact behind most of this

**Your whole command, patterns included, is the command line of a shell process that is still running while the command executes.** Anything that searches command lines — `pgrep -f`, `pkill -f`, `ps | grep`, `killall -r` — can find that shell and act on it. The same holds for a string you send through `ssh`, or through `sh -c` under `kubectl exec` / `docker exec`: the far end runs it in a shell whose command line contains your pattern. Mechanics, and why every "safer" variant fails: `references/process-control.md`.

## Stop a process by PID or through what owns it, never by pattern

**Never stop a process with `pkill -f`, `killall`, `kill $(pgrep -f …)`, or `ps | grep … | xargs kill`.** The pattern matches the shell running your command, that shell dies with the target, and every later step in the command silently never runs — observed: a build that never started, and a trailing `; true` that never ran.

Stop it, in this order of preference:

1. **Through its owner.** What a tool started, that tool stops: `docker compose down`, `docker stop <container>`, `kubectl delete`, `systemctl --user stop <unit>`, the host's own stop for a task it backgrounded.
2. **By the PID you kept at launch** (§ Start only what you can stop) — the process, or its whole process group (`references/process-control.md` § Stop it).
3. **By the stack's own pid file**, when it writes one.

**Killing a client that waits on a remote operation stops only the waiting** — `helm … --wait`, `kubectl rollout status`, a deploy CLI's `--wait`. The operation carries on; cancel it through its owner.

**Last resort, for something you did not start that has no owner and no PID: a one-time stop with the bracket trick.** `pgrep -af '[s]erver --port 4000'` matches `server --port 4000` but not the literal `[s]erver` in your own command line. List first, check the PIDs are what you mean, then `kill` those PIDs. It fails when the target string appears unbracketed anywhere else in the same command — a launch, an `echo`, a log grep — and it is **never a wait condition** (§ Wait on the thing itself). Limits: `references/process-control.md` § The bracket trick.

## Start only what you can stop

**Every process you start in the background must leave you its PID.** Without one, cleanup falls back to a pattern: most sessions observed killing their own shell had launched something untracked first.

- **Prefer the host's run-long mechanism** (`[SKILLS_DIR]/dev/references/host-adapters.md` op 6) — the host tracks the process and can stop it.
- **Otherwise, `&` with `$!` saved on the very next statement**, output to a log:

```bash
dir=$(mktemp -d)
./start-server > "$dir/server.log" 2>&1 &
pid=$!
echo "$pid" > "$dir/server.pid"
```

- **Never `( … &)`, `nohup … &`, `setsid` or `disown` without keeping the PID.** Each one detaches the process from anything that could find it again; `( … &)` loses `$!` inside the subshell.
- **A launcher that forks** — a package-manager script, an `sh -c` wrapper — leaves the real server as a *child* of the PID you kept, and stopping only that PID orphans it on its port. Start it in its own process group and stop the group (`references/process-control.md` § Start it tracked).
- **Stop what you started before you report done.** A forgotten dev server holds its port against the next run; some have been observed alive more than a day later.
- **A launch the host already backgrounds gets no `&`, `nohup` or `disown` of its own** — `[SKILLS_DIR]/dev/references/background-waits.md` § The rule says how each breaks it.

## Wait on the thing itself

**Never wait on a process pattern.** `until ! pgrep -f <pattern>` matches its own shell and never ends — one ran for most of a day; remotely, `until ! ssh <host> 'pgrep -f <pattern>'` did the same for hours.

- **An external completion** — a reviewer, CI, a long script that reports through a log — follows `[SKILLS_DIR]/dev/references/background-waits.md`: the host's mechanism, a log, and no wait of your own.
- **Inside one command**, a poll that gates your next line is allowed only when it is bounded by an iteration count **and** checks that the producer is still alive:

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

`exit 1` ends the whole command with a failing status, so nothing after the poll runs and the failure is visible; inside a function, use `return 1` instead. Never end a failure branch on its diagnostic (`echo`, `tail`) — that branch then exits 0 and the gate passes.

- **The condition is the state you need** — a ready line in the log, an HTTP 2xx, a resource reporting `Ready` — never "the process is gone". Waits on real state were the ones observed finishing in under a minute.

## Know which shell runs your command

**Do not assume bash.** The host may run your command under the user's shell, often zsh, whatever the environment reports (§ Host notes). The traps that bite there:

- **Quote any word that starts with `=`.** zsh expands `=word` to the path of command `word`, so `echo ===` fails with `== not found` and aborts the rest of the command list. Use `echo '==='` or another separator.
- **Quote every glob.** zsh refuses to run a command whose glob matches nothing (`no matches found`) but carries on with the list, so the overall exit can still be 0 — `grep -rn x --include=*.md` simply never ran. Write `--include='*.md'`.
- **Never store a command in a string.** zsh does not word-split `$cmd`, so `cmd="ssh -i key <host>"; $cmd uptime` looks for a program named `ssh -i key <host>`. Use an array or a function.
- **Use `command <tool>` to get past an alias** the user's shell defines — `grep` aliased to a different tool with different flags is common.
- **Anything longer than a one-liner goes in a script file run with `bash <file>`** — one known dialect, no aliases, job control that works, and `bash -n <file>` checks it before it runs.

The full bash / zsh / fish table: `references/dialects.md`.

## Keep exit statuses and output visible

**A pipeline reports the status of its last command.** `make test | tail -20` exits 0 when the tests fail, and when the call times out it shows nothing at all, because `tail` prints only at the end.

- **Redirect to a log, then read it:** `make test > "$dir/test.log" 2>&1; rc=$?; tail -n 40 "$dir/test.log"; exit "$rc"` — the `tail` is for you, the status is the command's.
- **When you must pipe**, `set -o pipefail` or read `PIPESTATUS` (bash) / `pipestatus` (zsh). Under `pipefail`, a producer that `head` cut off exits 141 (SIGPIPE) — that is `head` closing early, not a failure.
- **Cap what you read.** `head -n`, `grep -m`, `cut -c1-200`; read big files in slices (`sed -n '200,260p'`). A dump of tens of kilobytes costs the context of everything that follows it.

## Never block on a prompt

Stdin may be closed and nobody may be there to answer, so a prompt fails, hangs the call, or waits for a human to rescue it.

- `-y` / `--yes` / `--non-interactive` on anything that asks.
- `ssh -n -o BatchMode=yes -o ConnectTimeout=10 <host> '<cmd>'` — no password prompt, no stdin read, no hang on a dead host.
- `sudo -n` — fail at once instead of asking for a terminal.
- `GIT_EDITOR=true` and `GIT_PAGER=cat` (or `git --no-pager`); never `git rebase -i` or `git add -i` / `-p`.
- `DEBIAN_FRONTEND=noninteractive` for `apt-get`.
- `timeout <seconds>` on a network call that has no timeout of its own (GNU coreutils; `gtimeout` on macOS via Homebrew coreutils).
- Never run an interactive login — `[SKILLS_DIR]/fx-review/SKILL.md` § Shared rules that bite in every platform owns that rule.

## Never put a secret in a command

**Every user on the machine can read a command line through `ps`** — the same visibility behind § Stop a process by PID — and the transcript keeps it. No token in `curl -H`, no `sshpass -p` or `SSHPASS=` in the command, no password typed with `tmux send-keys`. An environment variable expanded into an argument is on the command line again.

Read the secret from a file, or pass it through a builtin on stdin, populated from the secret store:

```bash
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - https://example.com/api
sshpass -f "$dir/pass" ssh "$host" uptime
```

`printf` is a shell builtin, so the value never reaches any process's argv. If a secret shows up in output, do not repeat it — tell the user so it can be rotated.

## Guard destructive commands

`rm -rf "$dir"/*` with `$dir` empty or unset removes `/*`. Write `rm -rf -- "${dir:?}"/*` — `${var:?}` aborts when the variable is unset or empty, and `--` stops a name that starts with `-` being read as a flag. Look at the target before anything recursive: `ls -d -- "${dir:?}"`.

## Use absolute paths

The host may reset the working directory between calls, so a `cd` in one call does not carry into the next. Use absolute paths, or `cd <dir> && <cmd>` within the one call.

## Host notes

Observed behaviour, each on the version named — verify on yours before relying on it. The per-host mechanisms for long runs and waits are `[SKILLS_DIR]/dev/references/host-adapters.md`'s; they are not restated here.

**Claude Code** (observed on 2.1.296):

- A command runs as `/usr/bin/zsh -c "source <snapshot> && … eval '<cmd>' < /dev/null"` — the user's own zsh or bash, regardless of what the environment reports, with the user's aliases loaded from the snapshot. Your entire command is inside that `-c` string, which is why a pattern taken from it self-matches.
- A self-kill shows as **exit 144** with no output from the steps after it.
- Stdin is `/dev/null`, so most prompts fail at once rather than hang.
- A command that hits the foreground timeout is moved to the background rather than killed; older versions killed it with exit 143. The run-long mechanism is `run_in_background: true`.
- The working directory is reset between calls, with a "Shell cwd was reset" notice.

**Codex** (observed on codex-cli 0.159.0):

- `exec_command` runs a command as `/usr/bin/bash -lc '<cmd>'` — a login bash, so the self-match is the same and the zsh traps are not; incident write-ups that say `bash -c` describe this shape.
- `exec_command` returns control after at most 30 s and leaves the command running (`host-adapters.md` § Long waits).
