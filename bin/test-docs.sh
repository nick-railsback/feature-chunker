#!/usr/bin/env bash
# test-docs.sh — doctrine checks over the prose surfaces.
# Run: bash bin/test-docs.sh   (no executable bit required)
#
# bin/test-chunk-check.sh is the oracle for chunk-check.sh's behaviour. This is
# the oracle for the claims the documentation makes ABOUT that behaviour, and it
# exists because those claims have a demonstrated drift rate: two dedicated
# "bring the README in step" commits in two days (22172db, 91891a6), and a
# 2026-08-05 health audit that still found three live divergences plus an
# install command that silently disabled a shipped mechanism. Prose had no
# comparator; the data did, and the data did not drift. The repo applied its own
# best idea — duplicate, then reconcile — to state.json and not to itself.
#
# WHAT BELONGS HERE. A claim that is cheap to check and expensive to have wrong:
# a command the reader will paste, a number stated as measured, a contract
# restated in two places. Not style, not wording, not anything requiring a
# judgement call — a doctrine check that argues about prose is a doctrine check
# people start ignoring.
#
# The install checks EXECUTE the documented command rather than restating it.
# Restating it here would be a third copy of the contract, drifting the way the
# first two did. Extracting and running it means the documentation is the
# subject, not a paraphrase of it.
set -u -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASSED=0; FAILED=0

# This checks a repository, not an install. The installed copy carries no
# README.md, so say that plainly rather than failing every check as "missing".
[ -f "$ROOT/README.md" ] || {
  printf 'ERROR %s\n' "no README.md at $ROOT — test-docs.sh checks the repository's prose surfaces; run it from a clone" >&2
  exit 2
}
command -v rsync >/dev/null 2>&1 || {
  printf 'ERROR %s\n' "rsync is required (the install checks run the documented command)" >&2
  exit 2
}

ok()  { printf 'ok    %s\n' "$1"; PASSED=$((PASSED+1)); }
no()  { printf 'FAIL  %s\n' "$1"; FAILED=$((FAILED+1)); }

assert_eq() { # assert_eq <label> <actual> <want>
  if [ "$2" = "$3" ]; then ok "$1"; else
    no "$1"
    printf '        got:  %s\n' "$2"
    printf '        want: %s\n' "$3"
  fi
}

assert_absent() { # assert_absent <label> <haystack> <needle>
  if printf '%s' "$2" | grep -qF -- "$3"; then
    no "$1"
    printf '%s\n' "$2" | sed 's/^/      | /'
  else ok "$1"; fi
}

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/chunkdocs.XXXXXX")" || { echo "cannot create scratch dir"; exit 2; }
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

# --- the install command ----------------------------------------------------
# One command, stated in two documents, and the two disagreed: the README's
# excluded CANDIDATES.md while references/setup.md's shipped it along with four
# repo-only files. The ledger's read path resolves relative to the installed
# script (chunk-check.sh's SKILL_ROOT), and candidates_overdue() opens with
# "[ -f ] || return 0" — so the README's install produced a harness whose
# escalation warning could never fire, with nothing anywhere saying so. Silent
# no-op of a designed check is the failure class this skill names as its worst.
# Found by the 2026-08-05 health audit (F2).

install_cmd() { # install_cmd <markdown-file> — first fenced block containing rsync
  awk '
    /^```/ {
      if (inb) { if (buf ~ /rsync/) { printf "%s", buf; exit } buf=""; inb=0 }
      else inb=1
      next
    }
    inb { buf = buf $0 "\n" }
  ' "$1"
}

readme_cmd="$(install_cmd "$ROOT/README.md")"
setup_cmd="$(install_cmd "$ROOT/references/setup.md")"

[ -n "$readme_cmd" ] && ok "README.md states an rsync install command" \
  || no "README.md states an rsync install command"
[ -n "$setup_cmd" ] && ok "references/setup.md states an rsync install command" \
  || no "references/setup.md states an rsync install command"

assert_eq "the two documented install commands are byte-identical" \
  "$setup_cmd" "$readme_cmd"

# Named on its own rather than left to the tree comparison below. When this
# regresses, the tree diff says "CANDIDATES.md missing" and this says why that
# matters — the finding, not just the symptom.
assert_absent "the install does not exclude CANDIDATES.md (it carries the ledger's read path)" \
  "$readme_cmd" "CANDIDATES.md'"

# Execute it. HOME is redirected so the command's own `~/.claude/skills/...`
# target lands in the scratch dir and the operator's real install is untouched.
( cd "$ROOT" && HOME="$SCRATCH" bash -c "$readme_cmd" ) >/dev/null 2>&1 \
  && ok "the documented install command runs clean" \
  || no "the documented install command runs clean"

INST="$SCRATCH/.claude/skills/feature-chunker"
got="$(cd "$INST" 2>/dev/null && ls -A | LC_ALL=C sort | tr '\n' ' ')"

# The README says "SKILL.md, references/, bin/, templates/, CANDIDATES.md, and
# nothing else". This is that sentence, executed.
#
# It also pins the ALLOWLIST shape. The command was a denylist of excludes until
# 2026-08-07, which meant anything new at the repo root shipped by default and
# the "nothing else" claim decayed without anyone touching the sentence: at the
# time this check was written the denylist form shipped a .claude/ directory and
# an untracked docs/ tree into every install. A denylist cannot hold a
# "nothing else" claim — only an allowlist can, so this check would go red on a
# reversion to excludes even if the exclude list were complete on the day.
assert_eq "the install contains exactly what the README says it contains" \
  "$got" "CANDIDATES.md SKILL.md bin references templates "

# --- CI runs every checker --------------------------------------------------
# A checker nothing runs automatically is an instruction to remember, which is
# the whole of finding F3 and the thing this repository argues against
# everywhere else. Adding bin/test-<something>.sh and wiring it into no workflow
# would reproduce that quietly, so the wiring is asserted rather than trusted.

WORKFLOW="$ROOT/.github/workflows/checks.yml"
if [ -f "$WORKFLOW" ]; then
  ok "a CI workflow exists"
  for f in "$ROOT"/bin/test-*.sh; do
    b="$(basename "$f")"
    if grep -qF "bin/$b" "$WORKFLOW"; then ok "CI runs bin/$b"
    else no "CI runs bin/$b — it is a checker nothing runs on push"; fi
  done
else
  no "a CI workflow exists at .github/workflows/checks.yml"
fi

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
