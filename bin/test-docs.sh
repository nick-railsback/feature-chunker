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

assert_contains() { # assert_contains <label> <haystack> <needle>
  if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else
    no "$1"
    printf '        looking for: %s\n' "$3"
  fi
}

md_section() { # md_section <file> <heading-text> — body up to the next '## '
  awk -v h="$2" '
    !inb && /^#+ / && index($0, h) { inb=1; next }
    inb && /^## / { exit }
    inb { print }
  ' "$1"
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

# rsync does not create missing parent directories of its destination, and GNU
# rsync and macOS's disagree about it: macOS creates the whole path, GNU fails
# with "No such file or directory". So the command ran fine on the maintainer's
# machine and on the macOS runner, and produced an empty install on ubuntu —
# meaning it was broken for exactly the person it is written for, someone
# installing their first skill on a machine with no ~/.claude/skills yet. Caught
# by the first CI run this repository ever did (2026-08-07). --mkpath would be
# the tidier fix and needs rsync 3.2.3+, which is younger than plenty of
# installs; mkdir -p is portable to everything.
assert_contains "the install creates its destination (rsync will not make parents)" \
  "$readme_cmd" "mkdir -p"

# Execute it. HOME is redirected so the command's own `~/.claude/skills/...`
# target lands in the scratch dir and the operator's real install is untouched.
# That redirection is also what makes this a real test: the scratch HOME has no
# `.claude` tree, so the command has to work on a machine that has never had one
# — which is exactly the machine a first-time installer is sitting at.
#
# The output is captured and printed on failure. It was discarded in the first
# version of this file, and the first CI run to go red said only "the install
# ran dirty" with rsync's reason thrown away. A check that cannot say why it
# failed costs more than it saves.
if install_out="$( cd "$ROOT" && HOME="$SCRATCH" bash -c "$readme_cmd" 2>&1 )"; then
  ok "the documented install command runs clean"
else
  no "the documented install command runs clean"
  printf '%s\n' "$install_out" | sed 's/^/      | /'
fi

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

# --- the documented upgrade path --------------------------------------------
# The check above redirects HOME to a virgin scratch dir, so it only ever
# measures the first-time install. The README prescribes a different path for
# everyone who already has the skill — "improvements land here, versioned, and
# re-run the rsync" — and rsync writes into the destination without removing
# what it finds there. So an install made by the denylist-era command kept its
# `.claude/`, `.github/` and stray `docs/` through every subsequent upgrade, and
# "nothing else" was false for exactly the population that had been following
# the instructions longest (2026-08-07 PR review, finding 1).
#
# --delete does not close this. It prunes the directories rsync transfers, so a
# file dropped from bin/ does go away, but the destination root is not itself a
# transferred directory in this argument form and its extraneous entries
# survive. The residue is on the destination side, so the command has to clear
# the destination.
#
# Compared against the fresh install rather than a literal: an upgrade that
# ends anywhere other than where a first-time install ends is the finding,
# whatever the difference turns out to be.

UPGRADE="$SCRATCH/upgrade"
UPINST="$UPGRADE/.claude/skills/feature-chunker"
mkdir -p "$UPINST/.claude/hooks" "$UPINST/.github/workflows" "$UPINST/docs/audits" "$UPINST/bin"
touch "$UPINST/.claude/hooks/chunk-no-commit.py" \
      "$UPINST/.github/workflows/checks.yml" \
      "$UPINST/docs/audits/2026-08-05-health-audit.md" \
      "$UPINST/README.md" \
      "$UPINST/bin/dropped-last-release.sh"

if upgrade_out="$( cd "$ROOT" && HOME="$UPGRADE" bash -c "$readme_cmd" 2>&1 )"; then
  ok "the documented install command runs clean over an older install"
else
  no "the documented install command runs clean over an older install"
  printf '%s\n' "$upgrade_out" | sed 's/^/      | /'
fi

assert_eq "re-running the install over an older one leaves a fresh install's tree" \
  "$(cd "$UPINST" 2>/dev/null && find . | LC_ALL=C sort)" \
  "$(cd "$INST"   2>/dev/null && find . | LC_ALL=C sort)"

# --- the one cheaply checkable number ---------------------------------------
# The README said "sixteen files, ~150 KB" in a document that stakes its
# comparison table on "numbers taken, not recalled". Measured at the 2026-08-05
# audit: 329 KB. It had been stale by more than 2x since the suite grew from 91
# assertions to 273, and a reviewer who checks the one number they can check
# finds it wrong — which taxes the credibility of every adjacent number they
# cannot check. That is the actual cost of a stale measurement in a document
# arguing from measurements.
#
# So it is measured from the install this file just built, rather than recalled.
# The file count is exact. The size is held to +/-10 KB, which is what the "~"
# in the claim is worth: gating on the byte would redden CI on every edit to a
# script and teach people to bump the number without reading it, which is how a
# number stops being a measurement again.

claim="$(grep -F 'installs into' "$ROOT/README.md" | head -1)"
[ -n "$claim" ] && ok "README states what the install weighs" \
  || no "README states what the install weighs"

claim_files="$(printf '%s' "$claim" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) files.*/\1/p')"
claim_kb="$(printf '%s' "$claim"    | sed -n 's/.*[^0-9]\([0-9][0-9]*\) KB.*/\1/p')"

real_files="$(find "$INST" -type f | wc -l | tr -d ' ')"
real_kb="$(( $(find "$INST" -type f -exec wc -c {} + \
             | awk '$2 != "total" { s += $1 } END { print s+0 }') / 1024 ))"

assert_eq "the README's install file count is the install's" "$claim_files" "$real_files"

if [ -n "$claim_kb" ] \
   && [ "$(( claim_kb > real_kb ? claim_kb - real_kb : real_kb - claim_kb ))" -le 10 ]; then
  ok "the README's install size is within 10 KB of measured (~$claim_kb KB vs $real_kb KB)"
else
  no "the README's install size is within 10 KB of measured (claims ~${claim_kb:-none} KB, measured $real_kb KB)"
fi

# --- contracts restated in two places ---------------------------------------
# Each of these is a qualification the script implements and SKILL.md states,
# which the README's parallel copy dropped. They are checked as presence of the
# qualification, never as matching prose: the two documents are deliberately
# different lengths, and a text comparison would be a style gate that people
# learn to route around. What must not happen is one document stating a rule
# while the other states its exception — a README-first reader then learns a
# model the script contradicts. All three found by the 2026-08-05 audit (F4),
# which also found the maintenance cost already paid: two dedicated "bring the
# README in step" commits in two days, with these three surviving both.

NONNEG="$(md_section "$ROOT/README.md" "The seven non-negotiables")"
[ -n "$NONNEG" ] && ok "README.md states the non-negotiables" \
  || no "README.md states the non-negotiables"

# #7 said bypass "refuses from any stage past ready" flat, while the op table
# eighteen lines later documented --downgrade as the exit from exactly that.
# A reader who stopped at the non-negotiable concluded a mis-sized frozen chunk
# had no way out, when the correction is the designed one.
assert_contains "README's non-negotiables name --downgrade, the exit from an over-escalation" \
  "$NONNEG" "--downgrade"

# #6 presented predict-then-compare unqualified after the 2026-07-31 softening
# made blind predictions gate 'standard' chunks only.
assert_contains "README's non-negotiables name the standard-only blind prediction" \
  "$NONNEG" "standard"

# SKILL.md's audit-readiness row told the operator to run the suite by hand
# before bypass. The 2026-08-02 change made bypass run it and record the exit
# code in bypass_suite — "that the script runs it is the point", precisely so it
# stops being a step someone was told to remember.
SKILL_OPS="$(md_section "$ROOT/SKILL.md" "Operations — load only the stage in play")"
[ -n "$SKILL_OPS" ] && ok "SKILL.md states the operations table" \
  || no "SKILL.md states the operations table"
assert_absent "SKILL.md does not ask for a manual suite run before bypass (bypass runs it)" \
  "$SKILL_OPS" "run the suite"

# --- the state tree is stated once ------------------------------------------
# The README carried a second copy of SKILL.md's state layout. Nothing compared
# them, and the audit named this pair and the op table as the two highest-drift
# restatements in the repository. The repo's own rule, from references/plan.md:
# "Two copies of a rule is one too many." It applied duplicate-then-reconcile to
# state.json — where spec_cmp hard-fails on divergence in either direction, and
# where nothing has ever drifted — and not to its own prose.
#
# So the README links instead, and this counts. A summary that links cannot
# drift out of step with what it summarises; a second copy always can.

tree_blocks() { # tree_blocks <file> — fenced blocks opening with the state tree root
  awk '
    /^```/ { if (inb) { inb=0 } else { inb=1; first=1 } ; next }
    inb && first { if ($0 ~ /^docs\/chunks\/<feature>\/$/) n++; first=0 }
    END { print n+0 }
  ' "$1"
}

assert_eq "the chunk state tree is drawn once, in SKILL.md" \
  "$(tree_blocks "$ROOT/SKILL.md")" "1"
assert_eq "the README links to that tree rather than redrawing it" \
  "$(tree_blocks "$ROOT/README.md")" "0"

# --- the repository layout is complete --------------------------------------
# It listed two scripts under bin/ and there are three. A layout diagram that
# silently omits a file is the same class as the install command that silently
# omitted the ledger: a claim about what exists, going stale without a reader.

LAYOUT="$(md_section "$ROOT/README.md" "Repository layout")"
[ -n "$LAYOUT" ] && ok "README.md states a repository layout" \
  || no "README.md states a repository layout"
for f in "$ROOT"/bin/*.sh; do
  b="$(basename "$f")"
  assert_contains "README's repository layout names bin/$b" "$LAYOUT" "$b"
done

# --- the shipped seed carries what the changelog says it carries ------------
# references/setup.md calls the field log's header "the single authoritative
# copy" of the demotion rule, and the demotion rule is the one mechanism that
# adapts ceremony downward from data. On 2026-08-03 it gained the streak-pooling
# caveat — and the caveat landed only in the operator-local file at
# ~/.claude/feature-chunker-field-log.md, which by design never travels. Every
# install since stamped a seed without it (2026-08-05 audit, F6).
#
# The operator-local copy cannot be checked from here and should not be: it is
# machine-local evidence, deliberately outside every repo. The shipped seed is
# the half that can be checked, and the half that reaches new installs.

SEED_RULE="$(md_section "$ROOT/templates/field-log.md" "Demotion rule")"
[ -n "$SEED_RULE" ] && ok "the field-log seed states the demotion rule" \
  || no "the field-log seed states the demotion rule"
assert_contains "the seed's demotion rule carries the streak-pooling caveat" \
  "$SEED_RULE" "pooled"

# --- the script's two self-descriptions agree -------------------------------
# Line 3's usage comment is the first thing a reader of chunk-check.sh sees;
# usage() fifteen lines below is what the script prints when it is called wrong.
# They are two statements of one list, and they disagreed: `predict` landed on
# 2026-08-03 (schema 9 -> 10) and only usage() was updated (2026-08-05 audit,
# F7). The same class as the README/SKILL.md divergences, inside a single file,
# eighteen lines apart — which is the argument that proximity is not a
# comparator and never was.

ops_list() { # ops_list <file> <line-regex> — the <a|b|c> op list on the first match
  grep -m1 -E "$2" "$1" | sed -n 's/.*<\([a-z|]*\)>.*/\1/p'
}

HEADER_OPS="$(ops_list "$ROOT/bin/chunk-check.sh" '^# Usage: chunk-check\.sh')"
USAGE_OPS="$(ops_list "$ROOT/bin/chunk-check.sh" '^usage\(\)')"

[ -n "$HEADER_OPS" ] && ok "chunk-check.sh's header comment states its op list" \
  || no "chunk-check.sh's header comment states its op list"
[ -n "$USAGE_OPS" ] && ok "chunk-check.sh's usage() states its op list" \
  || no "chunk-check.sh's usage() states its op list"
assert_eq "chunk-check.sh's header op list matches usage()'s" \
  "$HEADER_OPS" "$USAGE_OPS"

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
    # The invocation, not the mention. `bin/$b` alone is satisfied by the step's
    # own `name:` line — both of them read "… — bin/test-*.sh" — so the check
    # certified a workflow with every `run:` line deleted, which is finding F3
    # reproduced inside the check written to prevent it. A checker nothing runs
    # is the thing being tested for; a name is not a runner.
    if grep -qF "run: bash bin/$b" "$WORKFLOW"; then ok "CI runs bin/$b"
    else no "CI runs bin/$b — it is a checker nothing runs on push"; fi
  done
else
  no "a CI workflow exists at .github/workflows/checks.yml"
fi

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
