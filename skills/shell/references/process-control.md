# Process control

The mechanics behind `shell` § Stop a process by PID or through what owns it, never by pattern, and § Start only what you can stop. Waiting on an external completion is not covered here — `[SKILLS_DIR]/dev/references/background-waits.md` owns that, where `[SKILLS_DIR]` is the directory holding the `shell` skill's folder.

## Why a pattern matches its own shell

`pgrep -f`, `pkill -f` and `ps | grep` match against the **full command line** of every process on the machine. `pgrep` and `pkill` exclude only their own process. Everything else whose command line contains the pattern is a match, and that always includes:

- **The shell running your command.** Its command line is your entire command, as source text — every pattern, every literal, every comment in it.
- **Any wrapper around it** — the host's own shell, `timeout`, `xargs`, a parent script whose arguments carry the string.
- **On a remote host, the shell that runs your string.** `ssh <host> '<cmd>'` hands `<cmd>` to the remote login shell as `<shell> -c '<cmd>'`; `kubectl exec` and `docker exec` do the same when you wrap the command in `sh -c`. Whether that shell stays alive or replaces itself with your one command depends on the shell and the string — never rely on it. Anything compound (`;`, `&&`, a pipe, a loop) keeps it alive, and it matches.

So `pkill -f <pattern>` kills the shell running it, `pgrep -f <pattern>` always succeeds, and `ps aux | grep <pattern>` lists the `grep` and the shell. The trap is general: **any** `pgrep -f`, `ps | grep`, or `pkill -f` whose pattern appears in its own invocation self-matches.

**A filter loop does not help.** `for p in $(pgrep -f chrome); do grep -q '<profile-dir>' "/proc/$p/cmdline" && kill "$p"; done` checks each candidate for `<profile-dir>` — and the loop's own shell has `<profile-dir>` in its command line, so it passes its own filter and kills itself.

**Do not reach for a "safer" process check — there isn't one.** `pgrep -x <name>` drops the self-match but cannot tell your run from any other process of the same name. `pgrep -f <pattern> | grep -v $$` is worse: it filters PID *text* by substring (so `$$` of `123` also drops `1234`), and it removes only the current shell, leaving any parent or wrapper whose command line contains the pattern to keep the check true.

## Start it tracked

**Save `$!` on the statement right after the `&`.** Any other background job started in between overwrites it.

**A launcher that forks needs its own process group.** `npm run dev`, `yarn start`, an `sh -c` wrapper, a `make` target — the PID in `$!` is the launcher, and the server is its child. Kill the launcher and the child is reparented and keeps running, holding its port. Put the job in its own process group, whose ID is the launcher's PID, and stop the group.

In bash, `set -m` turns on job control, which gives every background job its own process group. **zsh refuses `set -m` without a terminal** (`can't change option: -m`), so run this from a bash script file (`bash start.sh`):

```bash
#!/usr/bin/env bash
dir=${1:?usage: start.sh <scratch-dir>}
set -m
npm run dev > "$dir/server.log" 2>&1 &
pid=$!
set +m
echo "$pid" > "$dir/server.pid"
```

`setsid <cmd> &` gives the same separation on Linux (util-linux); macOS does not ship it, so prefer `set -m`.

## Stop it

**TERM the group, wait a bounded time, then KILL.** The leading `-` addresses the process group; `--` keeps `kill` from reading `-<pid>` as a signal name.

```bash
pid=$(cat "$dir/server.pid")
kill -TERM -- "-$pid" 2>/dev/null
for i in $(seq 1 10); do
  kill -0 -- "-$pid" 2>/dev/null || break
  sleep 0.5
done
kill -0 -- "-$pid" 2>/dev/null && kill -KILL -- "-$pid"
rm -f "$dir/server.pid"
```

For a single process, not a group, drop the `-` in front of `$pid`.

**A job you started without its own group** is stopped by walking its children by parent PID — `pgrep -P "$pid"`, repeated for each child's children — then stopping them by PID. `pgrep -P` matches on the parent PID, not the command line, so it cannot match itself. `codex-review`'s bundled `run-codex-review.sh` reaps its process tree this way.

## Stale and reused PIDs

A PID identifies a process only while that process lives.

- **`kill -0 "$pid"` reports whether *some* process holds that PID**, not whether yours does. After yours exits the number is reused, and `kill -0` — or a `kill` — hits a stranger. It also succeeds on a zombie that exited but has not been reaped.
- **Before a KILL, confirm the PID is still yours:** `ps -o lstart=,args= -p "$pid"`, compared with what you started. That is an identity check on one PID you hold, not a search, so it cannot self-match.
- **A pid file from an earlier run names a stranger.** Keep pid files in a fresh `mktemp -d` directory per run, never a fixed path, and delete them when you stop the process.
- **`wait "$pid"` works only on a child of the current shell.** A later call runs in a new shell that never started it; check liveness with `kill -0` plus the identity check above. `disown` breaks `wait` even in the same shell — `background-waits.md` § The rule.

## The bracket trick

`pgrep -f '[s]erver --port 4000'` — the regex `[s]erver` matches the text `server`, but your own command line contains `[s]erver`, which it does not match. It is allowed **only for a one-time stop of something you did not start and that has no owner and no PID.** Its limits:

- **It breaks if the plain string appears anywhere else in the same command** — a launch in the same call, an `echo`, a log grep, a comment. The shell's command line then contains `server --port 4000` unbracketed, and the self-match is back.
- **It matches every other process with that string** — another user's, another agent's, a concurrent session's. List with `pgrep -af`, check each PID, then `kill` those PIDs; never `pkill` straight through.
- **It is never a wait condition.** It still cannot tell your run from anyone else's, so "until nothing matches" can outlive a stranger forever. Wait on the state you need instead (`shell` § Wait on the thing itself).
