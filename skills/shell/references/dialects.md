# Shell dialects

The differences that break agent commands, for the three shells a host is likely to hand you. Behaviour is as observed on bash 5, zsh 5.9 and fish 4 with default options; a user's own options can change any row. When in doubt, put the command in a file and run it with `bash <file>`.

| Behaviour | bash | zsh | fish |
|---|---|---|---|
| Word starting with `=` | Literal | Expanded to the path of that command: `echo ===` → `== not found`, and the **rest of the command list is skipped** | Literal |
| Glob that matches nothing | Passed through as the literal pattern | `no matches found`: that command does not run, the list carries on, overall exit can be 0 | `No matches for wildcard`: same as zsh |
| Unquoted `$var` holding spaces | Split into words, then globbed | One word, not split | One word (lists are separate elements instead) |
| Command stored in a string, run as `$cmd args` | Works by accident of splitting | Exit 127: looks for a program named the whole string | `Unknown command` |
| Per-stage pipe statuses | `${PIPESTATUS[@]}` | `${pipestatus[@]}` | `$pipestatus` |
| `set -o pipefail` | Yes | Yes | No such option; read `$pipestatus` |
| Array indexing | From 0: `${a[0]}` | From 1: `$a[1]` | From 1: `$a[1]` |
| `[[ … ]]` | Yes | Yes | No; use `test` |
| Aliases in a `-c` command | Not expanded unless `expand_aliases` is set | Expanded if a sourced file defined them | Functions and abbreviations, not aliases |
| `set -m` (job control) without a terminal | Works | Refused: `can't change option: -m` | — |
| `VAR=value cmd` | Yes | Yes | Yes |

## Portable forms

Each of these behaves the same in bash and zsh:

```bash
echo '==='
grep -rn TODO --include='*.md' .
ssh_cmd=(ssh -o BatchMode=yes "$host")
"${ssh_cmd[@]}" uptime
command grep -rn TODO .
```

The zsh-only spellings, for reading output a zsh host produced:

```zsh
false | true; print -r -- "${pipestatus[@]}"
a=(x y); print -r -- $a[1]
```
