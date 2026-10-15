#!/usr/bin/env bash
# check-docs-layout.sh
# Reports whether the current repository has adopted the fx docs layout and the
# fx instruction-file layout, and which native documentation conventions it
# already uses. Read-only.
#
# Usage:
#   bash check-docs-layout.sh          # no arguments; run from anywhere in the repo
#
# The meaning of every line, the partial-adoption rules and the exact report
# wording live in fx-setup/references/adoption.md. This script only detects.
#
# CONTRACT
#   - Resolves the repository root itself; every check is relative to that root,
#     so a run from a subdirectory prints the same values as a run from the root.
#   - Never writes anything, anywhere.
#   - Never reads through a symlink, at any component. Every probe goes through
#     safe(), which rejects a path that is absolute, contains "..", or has a
#     symlink at ANY component below the root — ancestors and the final one —
#     and notes it in WARNING. A rejected path is absent, per key:
#       FX_DOCS           a symlinked marker (docs/index.yml, docs/changes, or an
#                         ancestor) is no marker: never adopted on a link.
#       FX_DOCS_MISSING   a symlinked docs-layer path is listed as missing.
#       FX_INSTRUCTIONS*  the one place a link is named in a value: a symlinked
#                         AGENTS.md / REVIEW.md is listed as "<file>(symlink)",
#                         found by lstat only and never read, and makes the layer
#                         partial, never adopted. fx-upgrade migrates it.
#       NATIVE_*, DOCS_SITE  a symlinked path is omitted.
#     Directory scans (find) never follow links; a link found inside a scanned
#     directory is noted, not read.
#   - Always exits 0. A missing file is an answer, not an error.
#   - Every exit path prints every key below, through the one emit function. A
#     caller parsing the output never has to tell "key missing" from "empty".
#
# Output: KEY=VALUE lines, in this order. List values are space-separated and may
# be empty.
#   REPO_ROOT=<abs path>
#   FX_DOCS=adopted|not-adopted
#   FX_DOCS_MISSING=<subset of: docs/specs/ docs/changes/ docs/tasks.md docs/index.yml docs/index.md>
#                   (printed only when FX_DOCS=adopted)
#   FX_INSTRUCTIONS=adopted|partial|not-adopted
#   FX_INSTRUCTIONS_PRESENT=<subset of: AGENTS.md REVIEW.md; a symlink is suffixed "(symlink)">
#   NATIVE_SPECS=<directories holding at least one .md>
#   NATIVE_TRACKING=<tracker files> [task-tracking:<value from a plain AGENTS.md>]
#   NATIVE_REVIEW_RULES=<AGENTS.md if plain and it has a review heading other than the
#                       fx "## Code Review Rules" pointer> <.github/copilot-instructions.md if plain>
#                       (in that order: fx-review Step 6 writes to the first entry, and
#                       AGENTS.md reaches every reviewer where the Copilot file reaches one)
#   NATIVE_CHANGELOG=<files/dirs> [generated-by:<release-please|semantic-release|changesets>]
#   DOCS_SITE=<config files/dirs>
#   WARNING=<note>[ | <note>]...
#                       (printed only when there is a note: "could not enter <root>;
#                       nothing was checked" — every value above is then a default,
#                       not a finding — or "<path> is a symlink; not read",
#                       "<path> is a symlink; nothing under it was read" (an
#                       ancestor), "<dir> contains symlinks; they were not read",
#                       or "<path> leaves the repository; not read")
#
# GitHub issues are deliberately not checked: that needs the network. A caller
# that needs a tracker runs `gh repo view --json hasIssuesEnabled` itself.

set -u

# Every key, with the value it carries when nothing could be checked. The detection
# below overwrites them; emit prints them all, so no exit path drops a key.
FX_DOCS=not-adopted
FX_DOCS_MISSING=
FX_INSTRUCTIONS=not-adopted
FX_INSTRUCTIONS_PRESENT=
NATIVE_SPECS=
NATIVE_TRACKING=
NATIVE_REVIEW_RULES=
NATIVE_CHANGELOG=
DOCS_SITE=
WARNING=

emit() {
    echo "REPO_ROOT=$REPO_ROOT"
    echo "FX_DOCS=$FX_DOCS"
    [ "$FX_DOCS" = adopted ] && echo "FX_DOCS_MISSING=$FX_DOCS_MISSING"
    echo "FX_INSTRUCTIONS=$FX_INSTRUCTIONS"
    echo "FX_INSTRUCTIONS_PRESENT=$FX_INSTRUCTIONS_PRESENT"
    echo "NATIVE_SPECS=$NATIVE_SPECS"
    echo "NATIVE_TRACKING=$NATIVE_TRACKING"
    echo "NATIVE_REVIEW_RULES=$NATIVE_REVIEW_RULES"
    echo "NATIVE_CHANGELOG=$NATIVE_CHANGELOG"
    echo "DOCS_SITE=$DOCS_SITE"
    [ -n "$WARNING" ] && echo "WARNING=$WARNING"
    exit 0
}

# Accumulate one note per distinct reason into the single WARNING key.
note() {
    case " | $WARNING | " in *" | $1 | "*) return ;; esac
    WARNING="${WARNING:+$WARNING | }$1"
}

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P 2>/dev/null)
if [ -z "$REPO_ROOT" ] || ! cd "$REPO_ROOT" 2>/dev/null; then
    WARNING="could not enter ${REPO_ROOT:-the repository root}; nothing was checked"
    emit
fi

# A probe path is safe when it is relative, has no ".." component, and NO component
# — ancestors and the final one — is a symlink. -f/-d/-e follow a link at any
# component silently, so every test below runs only after safe() passed; a path
# that fails is absent, with a WARNING note naming the link.
safe() {
    local p=$1 acc="" c i n
    case "$p" in
        /*|..|../*|*/..|*/../*) note "$p leaves the repository; not read"; return 1 ;;
    esac
    local -a parts
    IFS='/' read -ra parts <<<"$p"
    n=${#parts[@]}
    for ((i = 0; i < n; i++)); do
        c=${parts[i]}
        [ -z "$c" ] || [ "$c" = . ] && continue
        acc=${acc:+$acc/}$c
        if [ -L "$acc" ]; then
            if [ "$i" -eq $((n - 1)) ]; then note "$acc is a symlink; not read"
            else note "$acc is a symlink; nothing under it was read"; fi
            return 1
        fi
    done
    return 0
}
exists()   { safe "$1" && [ -e "$1" ]; }
is_plain() { safe "$1" && [ -f "$1" ]; }
is_dir()   { safe "$1" && [ -d "$1" ]; }
# find never follows links (no -L); note any link a scan of a real directory meets,
# so a link inside it is reported rather than silently skipped.
scan_links() { [ -n "$(find "$1" -maxdepth "$2" -type l -print -quit 2>/dev/null)" ] && note "$1 contains symlinks; they were not read"; return 0; }
# A real directory holding at least one markdown file, at most two levels down
# (docs/specs/<name>/index.md, docs/adr/0001-x.md).
has_md()   { is_dir "$1" && scan_links "$1" 2 && [ -n "$(find "$1" -maxdepth 2 -type f -name '*.md' -print -quit 2>/dev/null)" ]; }

join() { local out="" x; for x in "$@"; do [ -n "$x" ] && out="${out:+$out }$x"; done; printf '%s' "$out"; }

# ── docs layer ────────────────────────────────────────────────────────────────
# Adopted iff one of the two fx-specific markers exists. docs/specs/ alone is a
# common native name, and docs/tasks.md alone is a generic tracker name.
FX_DOCS=not-adopted
if is_plain docs/index.yml; then
    FX_DOCS=adopted
elif is_dir docs/changes && scan_links docs/changes 1 && [ -n "$(find docs/changes -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' -print -quit 2>/dev/null)" ]; then
    FX_DOCS=adopted
fi

if [ "$FX_DOCS" = adopted ]; then
    missing=()
    is_dir docs/specs     || missing+=("docs/specs/")
    is_dir docs/changes   || missing+=("docs/changes/")
    exists docs/tasks.md  || missing+=("docs/tasks.md")
    exists docs/index.yml || missing+=("docs/index.yml")
    exists docs/index.md  || missing+=("docs/index.md")
    FX_DOCS_MISSING=$(join "${missing[@]+"${missing[@]}"}")
fi

# ── instruction layer ─────────────────────────────────────────────────────────
# A symlinked file is named "(symlink)" — found by lstat, never read — so fx-upgrade
# can migrate it; it makes the layer partial, never adopted.
present=()
plain=0
for f in AGENTS.md REVIEW.md; do
    if is_plain "$f"; then present+=("$f"); plain=$((plain + 1))
    elif [ -L "$f" ]; then present+=("$f(symlink)")
    elif exists "$f"; then present+=("$f")
    fi
done
if [ "$plain" -eq 2 ]; then
    FX_INSTRUCTIONS=adopted
elif [ ${#present[@]} -eq 0 ]; then
    FX_INSTRUCTIONS=not-adopted
else
    FX_INSTRUCTIONS=partial
fi
FX_INSTRUCTIONS_PRESENT=$(join "${present[@]+"${present[@]}"}")

# ── native conventions ────────────────────────────────────────────────────────
specs=()
spec_candidates=(docs/adr doc/adr docs/decisions docs/architecture/decisions adr decisions
                 docs/rfcs docs/rfc rfcs docs/design design docs/proposals proposals)
[ "$FX_DOCS" = not-adopted ] && spec_candidates=(docs/specs "${spec_candidates[@]}")
if is_plain .adr-dir; then
    adr_dir=$(head -n 1 .adr-dir 2>/dev/null | tr -d '\r' | sed 's:/*$::')
    [ -n "$adr_dir" ] && spec_candidates+=("$adr_dir")
fi
for d in "${spec_candidates[@]}"; do
    has_md "$d" || continue
    case " ${specs[*]-} " in *" $d "*) continue ;; esac
    specs+=("$d")
done
NATIVE_SPECS=$(join "${specs[@]+"${specs[@]}"}")

tracking=()
tracking_candidates=(TODO.md TODO TASKS.md ROADMAP.md docs/TODO.md docs/roadmap.md)
[ "$FX_DOCS" = not-adopted ] && tracking_candidates+=(docs/tasks.md)
for f in "${tracking_candidates[@]}"; do is_plain "$f" && tracking+=("$f"); done
if is_plain AGENTS.md; then
    tt=$(grep -m 1 -oiE 'task-tracking:[[:space:]]*[A-Za-z0-9_.-]+' AGENTS.md 2>/dev/null | sed -E 's/^[^:]*:[[:space:]]*//')
    [ -n "$tt" ] && tracking+=("task-tracking:$tt")
fi
NATIVE_TRACKING=$(join "${tracking[@]+"${tracking[@]}"}")

review=()
# AGENTS.md first: fx-review Step 6 appends to the first entry, and AGENTS.md is
# read by Codex, Copilot and CodeRabbit where copilot-instructions.md reaches
# Copilot alone. The fx "## Code Review Rules" section is a pointer to REVIEW.md,
# not a rules section — never count it as a native review-rules file.
if is_plain AGENTS.md && grep -iE '^#+[[:space:]].*review' AGENTS.md 2>/dev/null \
        | grep -qviE '^##[[:space:]]+Code Review Rules[[:space:]]*$'; then
    review+=(AGENTS.md)
fi
is_plain .github/copilot-instructions.md && review+=(.github/copilot-instructions.md)
NATIVE_REVIEW_RULES=$(join "${review[@]+"${review[@]}"}")

changelog=()
for f in CHANGELOG.md CHANGES.md HISTORY.md; do is_plain "$f" && changelog+=("$f"); done
for d in .changeset changelog.d newsfragments; do is_dir "$d" && changelog+=("$d/"); done
releaserc=0
for f in .releaserc*; do exists "$f" && releaserc=1; done
if exists release-please-config.json || exists .release-please-manifest.json; then
    changelog+=("generated-by:release-please")
elif [ "$releaserc" = 1 ]; then
    changelog+=("generated-by:semantic-release")
elif exists .changeset/config.json; then
    changelog+=("generated-by:changesets")
fi
NATIVE_CHANGELOG=$(join "${changelog[@]+"${changelog[@]}"}")

site=()
exists mkdocs.yml && site+=(mkdocs.yml)
for f in docusaurus.config.*; do exists "$f" && site+=("$f"); done
exists book.toml && site+=(book.toml)
exists docs/conf.py && site+=(docs/conf.py)
is_dir docs/.vitepress && site+=(docs/.vitepress/)
DOCS_SITE=$(join "${site[@]+"${site[@]}"}")

emit
