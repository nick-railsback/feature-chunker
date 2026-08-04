#!/usr/bin/env bash
# chunk-check.sh — deterministic backstop for the feature-chunker lifecycle.
# Usage: chunk-check.sh <readiness|freeze|verify|log|gate|bypass|block|status>
#          <chunk-dir> [args]
#
# Guarantees live here as executed code, not as prose asking anyone to be
# careful. No -e: every diagnostic prints; failures are counted and reported.
# Fixture suite: bash bin/test-chunk-check.sh — run it after any edit here.
set -u -o pipefail

FAIL=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
warn() { printf 'WARN  %s\n' "$1"; }
info() { printf 'INFO  %s\n' "$1"; }
die()  { printf 'ERROR %s\n' "$1" >&2; exit 2; }

usage() { die "usage: chunk-check.sh <readiness|predict|freeze|verify|log|gate|bypass|block|status> <chunk-dir> [args]
       flags: --rebaseline (readiness), --refreeze (freeze), --log-path <file> (log),
              --downgrade (bypass), --one-pass (predict)"; }

[ $# -ge 2 ] || usage
OP="$1"; CHUNK_ARG="$2"; shift 2

OPT_REBASELINE=0
OPT_REFREEZE=0
OPT_DOWNGRADE=0
OPT_ONE_PASS=0
OPT_LOG_PATH=""
EXTRA1=""
EXTRA2=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rebaseline) OPT_REBASELINE=1 ;;
    --refreeze)   OPT_REFREEZE=1 ;;
    --downgrade)  OPT_DOWNGRADE=1 ;;
    --one-pass)   OPT_ONE_PASS=1 ;;
    --log-path)   shift; [ $# -gt 0 ] || die "--log-path needs a file path"; OPT_LOG_PATH="$1" ;;
    --*)          die "unknown option: $1" ;;
    *)            if [ -z "$EXTRA1" ]; then EXTRA1="$1"; else EXTRA2="${EXTRA2:+$EXTRA2 }$1"; fi ;;
  esac
  shift
done

# --downgrade changes which stages an op will accept, so a typo that lands it on
# the wrong op must not read as "accepted and had no effect".
[ "$OPT_DOWNGRADE" -eq 0 ] || [ "$OP" = "bypass" ] \
  || die "--downgrade applies to 'bypass' only (given: $OP)"
# --one-pass downgrades what the predict stamp claims. Same reasoning: a typo
# that lands it on another op must not silently read as accepted.
[ "$OPT_ONE_PASS" -eq 0 ] || [ "$OP" = "predict" ] \
  || die "--one-pass applies to 'predict' only (given: $OP)"

command -v jq  >/dev/null 2>&1 || die "jq is required"
command -v git >/dev/null 2>&1 || die "git is required"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# CANDIDATES.md ships WITH the skill — unlike the field log, which is
# machine-local by design — so it is found relative to this script rather than
# to the repo under test, and resolved here, before the cd to the repo root
# below. Both install shapes work: a symlinked skill directory resolves through
# to the real file, and a copied one carries its own.
# CHUNK_CHECK_CANDIDATES overrides it; that exists for the fixture suite, which
# must assert on a ledger it controls rather than on whatever this repo's real
# one happens to say today.
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || SKILL_ROOT=""
CANDIDATES_FILE="${CHUNK_CHECK_CANDIDATES:-${SKILL_ROOT:+$SKILL_ROOT/CANDIDATES.md}}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
CHUNK_DIR="$(cd "$CHUNK_ARG" 2>/dev/null && pwd)" || die "chunk dir not found: $CHUNK_ARG"
case "$CHUNK_DIR" in "$REPO_ROOT"/*) ;; *) die "chunk dir must be inside the repo";; esac
CHUNK_REL="${CHUNK_DIR#"$REPO_ROOT"/}"
FEATURE_REL="$(dirname "$CHUNK_REL")"
STATE="$CHUNK_DIR/state.json"
cd "$REPO_ROOT" || die "cannot cd to repo root"

[ -f "$STATE" ] || die "missing $CHUNK_REL/state.json (stamp from templates/state.json)"
jq -e . "$STATE" >/dev/null 2>&1 || die "state.json is not valid JSON"

SCHEMA_MAX=10
sv="$(jq -r '.schema_version // 0' "$STATE")"
case "$sv" in
  ''|*[!0-9]*) die "schema_version is not an integer — state.json is malformed" ;;
esac
[ "$sv" -le "$SCHEMA_MAX" ] || die "state.json is schema_version $sv; this script understands up to $SCHEMA_MAX — update chunk-check.sh"
[ "$sv" -ge "$SCHEMA_MAX" ] || warn "state.json is schema_version $sv (current: $SCHEMA_MAX) — new keys will be added on the next write"

stray="$(ls "$CHUNK_DIR"/.state.?????? 2>/dev/null | head -3)"
[ -z "$stray" ] || warn "stray .state.* files in $CHUNK_REL — a previous state write was interrupted; state.json may be behind the transcript"

JSET_TMP=""
cleanup_tmp() { [ -n "$JSET_TMP" ] && rm -f "$JSET_TMP"; JSET_TMP=""; return 0; }
trap cleanup_tmp EXIT INT TERM

jset() { # jset '<jq filter>' [jq-args...] — atomic state update; filter may use $now
  local filter="$1"; shift
  # The temp file lives beside state.json, not in a system temp dir: the repo
  # is writable by construction (a sandboxed agent's $TMPDIR may not be), and
  # mv is only rename(2) — i.e. actually atomic — within one filesystem.
  JSET_TMP="$(mktemp "$CHUNK_DIR/.state.XXXXXX")" || {
    fail "cannot create a temp file in $CHUNK_REL — is the chunk directory writable?"
    return 1
  }
  if jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$@" "$filter | .updated=\$now" \
       "$STATE" > "$JSET_TMP" && mv "$JSET_TMP" "$STATE"; then
    JSET_TMP=""
    return 0
  fi
  cleanup_tmp
  fail "state update failed: $filter"
  return 1
}
jget() { jq -r "$1" "$STATE"; }

# Expand test_paths to the sorted list of TRACKED files under them. Tracked
# only: .gitignore is honoured for free, build artifacts (__pycache__,
# .pytest_cache, coverage output, __snapshots__, .DS_Store) never enter the
# hash map, and an untracked test file cannot be silently frozen.
# -c core.quotePath=false stops git octal-escaping non-ASCII filenames, which
# would produce hash-map keys that never match the on-disk path. Filenames
# containing newlines remain unhandled: this script is line-oriented throughout.
list_test_files() {
  jq -r '.test_paths[]?' "$STATE" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    git -c core.quotePath=false ls-files -- "$p"
  done | sort -u
}

# Every declared test_paths entry must resolve to at least one tracked file,
# and must not hide untracked ones. Called by freeze and verify, not readiness.
# `git ls-files -- <nonexistent>` exits 0 with empty output, so the check is on
# emptiness, not exit status.
check_test_paths() {
  local entry n_tracked untracked missing=0
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    n_tracked="$(git -c core.quotePath=false ls-files -- "$entry" | wc -l | tr -d ' ')"
    untracked="$(git -c core.quotePath=false ls-files --others --exclude-standard -- "$entry")"
    if [ "$n_tracked" -eq 0 ]; then
      fail "test_paths entry '$entry' matches no tracked file — a typo, or the oracle was never written"
      missing=$((missing+1))
    else
      pass "test_paths entry '$entry': $n_tracked tracked file(s)"
    fi
    if [ -n "$untracked" ]; then
      fail "untracked file(s) under test_paths entry '$entry' — the oracle must be tracked to be frozen and reviewable ('git add' them, or .gitignore them if they are artifacts):"
      printf '%s\n' "$untracked" | sed 's/^/        /'
      missing=$((missing+1))
    fi
  done < <(jq -r '.test_paths[]?' "$STATE")
  [ "$missing" -eq 0 ]
}

compute_hashes_json() {
  local out="{}" f h
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    h="$(hash_file "$f")"
    out="$(jq -n --argjson o "$out" --arg k "$f" --arg v "$h" '$o + {($k):$v}')"
  done < <(list_test_files)
  printf '%s' "$out"
}

run_suite() {
  local cmd; cmd="$(jget '.suite_cmd // empty')"
  [ -n "$cmd" ] || { fail "suite_cmd not set in state.json"; return 1; }
  info "running suite: $cmd"
  if bash -c "$cmd"; then pass "suite green"; return 0
  else fail "suite red"; return 1; fi
}

# --- the trivial path's baseline evidence -----------------------------------
# `audit-readiness` step 0 sends a `trivial` chunk straight to `bypass`, and the
# one part of `readiness` it keeps is the suite run. That run is diagnostic: it
# is what makes a red suite *after* a two-minute change known to be yours. Step
# 0 asked for it in prose and nothing executed it — an instruction to remember,
# in the skill whose entire argument is that instructions to remember are not
# mechanisms. It is the same shape as the field-log append, which was prose for
# months while the log sat empty at every install path.
#
# It records; it does not gate. A red baseline predates the chunk and is not its
# problem, and blocking a comment-sized change behind someone else's broken
# suite is the disproportion non-negotiable #7 exists to prevent — the escape
# hatch would cost more than every chunk it rescued. Red is recorded and warned
# about loudly; what it means is the review gate's call.
#
# Sets SUITE_JSON rather than printing it: pass/warn/info write to stdout, so a
# command substitution around this would capture the diagnostics into the JSON.
#
# Shared by `bypass` (bypass_suite) and `freeze` (freeze_suite) — same shell
# command, two different moments in the lifecycle, so the message has to say
# which. `label` names the state.json field this run will be recorded under;
# `context` is the one-line reason the exit code means what it means at this
# particular call site, since "red" is alarming at `bypass` (nothing has
# touched the repo yet) and routine at `freeze` (the chunk's own new, still-
# unimplemented oracle is *supposed* to be red inside this same suite run).
SUITE_JSON="null"
record_suite_result() { # record_suite_result <label> <context-for-red>
  local label="$1" red_context="$2" cmd rc=0
  cmd="$(jget '.suite_cmd // empty')"
  if [ -z "$cmd" ]; then
    SUITE_JSON="null"
    warn "suite_cmd is not set — this $label records no baseline evidence"
    return 0
  fi
  info "running suite (recorded, not gated): $cmd"
  bash -c "$cmd" || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "suite green — recorded as $label"
  else
    warn "suite RED (exit $rc) — recorded as $label, not gated"
    warn "  $red_context"
  fi
  SUITE_JSON="$(jq -n --arg c "$cmd" --argjson e "$rc" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{at: $at, cmd: $c, exit: $e}')"
}

# --- oracle evidence -------------------------------------------------------
# Node-id capture is opportunistic. PYTEST_ADDOPTS makes pytest emit one
# "PASSED|FAILED <nodeid>" line per test without touching the user's command
# string — no flag-appending, no quoting hazard. Runners that ignore the
# variable emit no such lines and fall back to exit-code-only evidence, which
# is recorded as such rather than overstated.
run_oracle() { # run_oracle <logfile> — returns the oracle command's exit status
  local cmd; cmd="$(jget '.oracle_cmd // empty')"
  [ -n "$cmd" ] || { fail "oracle_cmd not set in state.json"; return 127; }
  info "running oracle: $cmd"
  PYTEST_ADDOPTS="${PYTEST_ADDOPTS:+$PYTEST_ADDOPTS }-rA" bash -c "$cmd" 2>&1 | tee "$1"
}

oracle_ids() { # oracle_ids <logfile> <PASSED|FAILED|ERROR> — real node-ids only
  grep -E "^$2[[:space:]]+[^[:space:]]+" "$1" 2>/dev/null \
    | awk '{print $2}' | grep '::' | sort -u
}

# A collection/setup error is reported as "ERROR <location>", where the
# location is a node-id or a file path. Captured *log* records share the prefix
# — pytest's default log format is "%(levelname)-8s %(name)s:%(file)s:%(line)d",
# so an ERROR-level log line printed under a failing test reads
# "ERROR    pkg.mod:mod.py:474 ...". Matching bare '^ERROR' conflated the two
# and refused the freeze of a correctly-red oracle whose code under test logs at
# ERROR level — which is normal behaviour, often the very behaviour under test,
# not a broken oracle. Discriminate on the subject's SHAPE: a location carries
# '::' or ends in '.py'; a logger name carries neither. Padding is not the
# discriminator — log_format is configurable and the shape is not.
# Earned 2026-08-04 (supply-chain-ops-assistant 02-adjust-inventory-action,
# whose oracle asserts a dispatch failure the handler logs at ERROR).
oracle_error_lines() {
  grep -E '^ERROR[[:space:]]+[^[:space:]]+' "$1" 2>/dev/null \
    | awk '{ if ($2 ~ /::/ || $2 ~ /\.py$/) print }'
}

ids_to_json() { jq -R -s 'split("\n") | map(select(length > 0)) | unique'; }

path_allowed() { # path_allowed <path> — under scope_paths, test_paths, or chunk docs
  local p="$1" e
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    e="${e%/}"
    [ "$p" = "$e" ] && return 0
    case "$p" in "$e"/*) return 0;; esac
  done < <({ jq -r '.scope_paths[]?, .test_paths[]?' "$STATE"; printf '%s\n' "$CHUNK_REL"; })
  # The feature's own top-level docs sit one level above the chunk directory.
  # feature.md carries the chunk queue and templates/feature.md asks you to keep
  # it current, so editing it mid-chunk must not read as scope creep. A *sibling
  # chunk's* directory is a different matter and stays out: one chunk, one diff,
  # one review. Hence the two-segment case arm, which matches first and falls
  # through to the reject.
  if [ "$FEATURE_REL" != "." ] && [ "$FEATURE_REL" != "$CHUNK_REL" ]; then
    case "$p" in
      "$FEATURE_REL"/*/*) ;;
      "$FEATURE_REL"/*)   return 0 ;;
    esac
  fi
  return 1
}

# --- spec.md <-> state.json reconciliation ---------------------------------
# spec.md is the contract a human reads and approves; state.json is what this
# script enforces. Two copies of one contract with nothing comparing them is
# exactly the "recorded state that disk contradicts" class readiness exists to
# catch — and the dangerous direction is silent: a spec declaring a narrow scope
# while state declares a wide one lets the diff exceed what was approved and
# still prints "all changes within declared scope".
#
# So the enforced fields live in spec.md as fenced blocks with an info string,
# and are compared here. Fences rather than prose bullets because a block
# delimiter is unambiguous — no nested lists, no inline commentary, no
# <placeholder> text to mistake for a value — while the human still reads an
# ordinary markdown document.
spec_block() { # spec_block <info-string> — body lines of the first matching fence
  awk -v want="$1" '
    /^```/ {
      if (inblock) exit
      info = $0
      sub(/^`+/, "", info)
      gsub(/[ \t]/, "", info)
      if (info == want) inblock = 1
      next
    }
    inblock { print }
  ' "$CHUNK_DIR/spec.md"
}

# Trim, drop blanks, drop one trailing slash, sort -u. The trailing slash is
# normalised because path_allowed already strips it when enforcing: "src/" and
# "src" mean the same thing downstream, so they must compare equal here too.
norm_list() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#/$##' \
    | grep -v '^$' | sort -u
}

spec_cmp() { # spec_cmp <info-string> <jq-filter> <label>
  local block spec_v state_v
  block="$(spec_block "$1")"
  if [ -z "$(printf '%s' "$block" | norm_list)" ]; then
    fail "spec.md has no '$1' fenced block — state.json's $3 cannot be reconciled"
    fail "  against the contract the human approves. Add one; see templates/spec.md."
    return 1
  fi
  spec_v="$(printf '%s\n' "$block" | norm_list)"
  state_v="$(jq -r "$2" "$STATE" | norm_list)"
  if [ "$spec_v" = "$state_v" ]; then
    pass "spec.md '$1' matches state.json $3"
  else
    fail "spec.md '$1' disagrees with state.json $3 — the human approves spec.md,"
    fail "  this script enforces state.json, and nothing else compares them:"
    printf '%s\n' "$spec_v"  | sed 's/^/        spec.md:    /'
    printf '%s\n' "$state_v" | sed 's/^/        state.json: /'
    return 1
  fi
}

# oracle_cmd is set by Track V during plan, not at readiness — so readiness
# reconciles the three fields it already gates and freeze reconciles all four.
check_spec_contract() { # check_spec_contract <with-oracle:0|1>
  if [ ! -f "$CHUNK_DIR/spec.md" ]; then
    fail "spec.md missing — there is no contract to reconcile state.json against"
    return 1
  fi
  spec_cmp scope       '.scope_paths[]?'     scope_paths
  spec_cmp test-paths  '.test_paths[]?'      test_paths
  spec_cmp size-class  '.size_class // empty' size_class
  [ "$1" = "1" ] && spec_cmp oracle '.oracle_cmd // empty' oracle_cmd
  return 0
}

changed_paths() { # everything different from baseline: commits, index, tree, untracked
  local base="$1"
  { git diff --name-only "$base" HEAD 2>/dev/null
    git diff --name-only
    git diff --name-only --cached
    git ls-files --others --exclude-standard
  } | sort -u
}

# --- the field log ----------------------------------------------------------
# Non-negotiable #6 makes the gates answerable to accumulated evidence: they
# "earn their keep via the field log or get demoted — by data, not by mood". A
# 2026-07 audit found the log empty at every install path. The demotion rule
# could therefore never reach its n, and the append was the one step in the
# lifecycle standing on nothing but an instruction to remember — inside a skill
# whose entire argument is that an agent attesting to its own work is not
# evidence. So `log` checks that the entry is really on disk, and `gate
# approved` refuses to stamp `done` without one.
#
# The script VERIFIES the entry; it never writes it. That split is forced and
# also correct: the default log lives under ~/.claude, where the Bash sandbox
# denies writes (reads are fine), so the append is a Write/Edit the agent makes
# and this is the check that it happened.
FIELD_LOG_DEFAULT="${HOME}/.claude/feature-chunker-field-log.md"

# --log-path wins, then the path this chunk recorded earlier, then the default.
# Recording it means a team pointing the log at a repo-local file states that
# once and every later op finds the same file.
resolve_log_path() {
  if [ -n "$OPT_LOG_PATH" ]; then printf '%s' "$OPT_LOG_PATH"; return; fi
  local rec; rec="$(jget '.field_log.path // empty')"
  if [ -n "$rec" ]; then printf '%s' "$rec"; return; fi
  printf '%s' "$FIELD_LOG_DEFAULT"
}

# Find this chunk's entry and report what is wrong with it if anything is.
# A line belongs to this chunk when its first three pipe-separated fields are a
# date, this repo and this chunk — the entry format's own leading columns.
FL_LINE=""; FL_GATE=""; FL_PLACEHOLDERS=""
# The `gate:` value the field-log entry must carry, DERIVED from state rather
# than transcribed from it. It is deliberately not `.gates.plan`: `freeze`
# refuses the verdict `adjust` ("apply it and re-gate; freeze records approval
# only"), so `.gates.plan` can only ever hold approve / auto-pass / n/a, and an
# adjustment survives solely in `.gates.plan_adjusted`. Copying `.gates.plan`
# into the log therefore makes `gate:adjust` unreachable — and the demotion rule
# reads exactly that field, arguing at length in the log's own header that
# counting only rejections "lets a run of ten chunks in which the human adjusted
# eight plans read as 'zero rejections' — retiring the gate on the strength of
# its own catches." The rule and the recording convention were written from the
# same analysis and implemented against different halves of it. This function is
# the single place the mapping lives so the two cannot drift again.
expected_field_log_gate() {
  local g
  [ "$(jget '.gates.plan_adjusted // false')" = "true" ] && { printf 'adjust'; return 0; }
  g="$(jget '.gates.plan // empty')"
  case "$g" in
    approve|adjust|reject|auto-pass) printf '%s' "$g" ;;
    # `n/a` (bypassed) and an unset gate both mean no gate happened: logged for
    # the proportionality question, excluded from the streak in either direction.
    *) printf 'none' ;;
  esac
}

# The demotion streak, computed from the entries rather than hand-maintained
# in the log's header. The header's manual count went stale within days of
# the rule landing — 18 clean gated chunks accumulated while it still read
# "streak 0" — which put an instruction-to-remember at the heart of the one
# mechanism that adapts ceremony downward from data. The log stays the data;
# this is the arithmetic. gate:none never counts (bypassed chunks are
# evidence about proportionality, not about the gate); adjust and reject
# reset the run; approve and auto-pass extend it.
field_log_streak() { # field_log_streak <log-path>
  awk -F'|' '
    $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ \t]*$/ && NF >= 4 {
      gate = ""
      for (i = 4; i <= NF; i++) {
        if ($i ~ /^[ \t]*chafe:/) break
        if ($i ~ /^[ \t]*gate:/) {
          gate = $i; sub(/^[ \t]*gate:/, "", gate); sub(/[ \t]+$/, "", gate)
          break
        }
      }
      if (gate == "adjust" || gate == "reject") streak = 0
      else if (gate == "approve" || gate == "auto-pass") streak++
    }
    END { print streak + 0 }
  ' "$1"
}

scan_field_log() { # scan_field_log <log-path>
  FL_LINE=""; FL_GATE=""; FL_PLACEHOLDERS=""
  local scanned
  scanned="$(awk -F'|' -v repo="$(basename "$REPO_ROOT")" -v chunk="$(jget '.chunk')" '
    found { next }
    {
      n = NF
      if (n < 4) next
      # Assigning to a field makes awk rebuild $0 with OFS, which would turn
      # the pipe-separated entry into a space-separated one. The record has to
      # be the bytes actually in the file: `gate approved` re-reads the log and
      # matches this line whole, so a normalised copy would never be found.
      orig = $0
      for (i = 1; i <= n; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      if ($1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) next
      if ($2 != repo || $3 != chunk) next
      found = 1
      print "LINE\t" orig
      gate = ""
      for (i = 4; i <= n; i++) {
        if ($i ~ /^chafe:/) {
          # chafe is the last field and free text, so the scan stops here: a
          # sentence containing a pipe would otherwise be re-split into fields
          # whose fragments match the placeholder pattern below. The field
          # still has to be ANSWERED though, and for a long time nothing asked
          # — `bypass` printed the work description into it, a plausible wrong
          # value in the one field carrying qualitative evidence, sitting
          # inside the break that made it unreachable. Tested on the WHOLE
          # value, never a substring: a real chafe line containing a question
          # mark is a sentence, not a placeholder.
          v = $i; sub(/^chafe:[ \t]*/, "", v)
          if (v == "" || v == "?") print "PLACEHOLDER\t" $i
          break
        }
        if ($i ~ /^gate:/) { gate = substr($i, 6); continue }
        # A field whose value is empty or still "?" is a question the retro
        # never answered. freeze refuses an unfilled predictions.md for the
        # same reason: a template standing in for a gate that happened.
        if ($i ~ /^[a-z][a-z-]*:[ \t]*\??$/) print "PLACEHOLDER\t" $i
      }
      print "GATE\t" gate
    }
  ' "$1")"
  # Extracted with awk rather than a `read` loop fed by a here-string: bash
  # materialises both here-docs and here-strings as real files in the system
  # temp directory, which a sandboxed agent may not be allowed to write. Command
  # substitution needs no temp file, and assigns to the caller's variables.
  FL_LINE="$(printf '%s\n' "$scanned" | awk -F'\t' '$1=="LINE"{print substr($0, 6); exit}')"
  FL_GATE="$(printf '%s\n' "$scanned" | awk -F'\t' '$1=="GATE"{print $2; exit}')"
  FL_PLACEHOLDERS="$(printf '%s\n' "$scanned" \
    | awk -F'\t' '$1=="PLACEHOLDER"{p = p (p ? ", " : "") $2} END{print p}')"
  [ -n "$FL_LINE" ]
}

# --- the candidates ledger --------------------------------------------------
# CANDIDATES.md's escalation rule — "second incident in a class → mechanism, in
# that session" — was prose with no reader for exactly one day before it was
# violated in writing: the cross-chunk seam entry sat `open` at three sightings,
# annotated "overdue for a mechanism", while the class it describes shipped two
# regressions two days later. Three chunks had logged the class through three
# different mechanisms. The log was working; the loop was open.
#
# So the ledger gets a read path. Each entry carries a machine-readable line
# (`Status: open · Occurrences: N · Last: …`) and this prints the ones that have
# reached the escalation threshold. It runs at `log`, which is where the retro is
# being written and the counts are being updated anyway.
#
# It warns and never fails. A mechanism cannot be built mid-chunk, and a gate
# that blocks a chunk over a maintainer's backlog is the disproportion
# non-negotiable #7 exists to prevent. What it removes is the dependence on
# someone happening to re-read the file.
candidates_overdue() { # candidates_overdue <ledger-path> — "<N>\t<title>" per overdue entry
  [ -f "$1" ] || return 0
  awk '
    /^###[ \t]/ { title = $0; sub(/^###[ \t]+/, "", title); next }
    /^Status:/ {
      st = ""; occ = 0
      if (match($0, /Status:[ \t]*[a-z]+/)) {
        st = substr($0, RSTART, RLENGTH); sub(/Status:[ \t]*/, "", st)
      }
      if (match($0, /Occurrences:[ \t]*[0-9]+/)) {
        occ = substr($0, RSTART, RLENGTH); sub(/Occurrences:[ \t]*/, "", occ); occ = occ + 0
      }
      if (st == "open" && occ >= 2 && title != "") print occ "\t" title
    }
  ' "$1"
}

# --- reconciliation: declared intent vs what git is actually doing ----------
# `artifacts` records whether this feature's chunk docs are committed. Both
# values are legitimate — see references/audit-readiness.md. What is never
# legitimate is the declaration disagreeing with git, which is the
# "state contradicts disk" class this op exists to catch.
#
# The two probes are genuinely exclusive: `git check-ignore` consults the index
# first and reports a TRACKED path as *not* ignored even when a pattern matches
# it. So ignored=0 means "untracked and actively excluded", and a tracked file
# can never masquerade as an ignored one.
check_artifacts_mode() {
  local mode ignored=1 n_tracked
  mode="$(jget '.artifacts // empty')"
  git check-ignore -q "$CHUNK_REL" 2>/dev/null && ignored=0
  n_tracked="$(git -c core.quotePath=false ls-files -- "$CHUNK_REL" | wc -l | tr -d ' ')"

  case "$mode" in
    untracked)
      if [ "$n_tracked" -gt 0 ]; then
        fail "artifacts is 'untracked' but $n_tracked file(s) under $CHUNK_REL are tracked —"
        fail "  the next commit publishes the specs against the declared intent."
        fail "  Fix: git rm -r --cached $CHUNK_REL, then add the ignore rule below."
      elif [ "$ignored" -ne 0 ]; then
        fail "artifacts is 'untracked' but nothing ignores $CHUNK_REL — the next"
        fail "  'git add -A' commits it. Fix: append 'docs/chunks/' to"
        fail "  .git/info/exclude (per-clone, never committed, so the repo carries"
        fail "  no trace of the choice — unlike a .gitignore entry)."
      else
        pass "artifacts: untracked — chunk docs excluded, no tracked strays"
      fi
      ;;
    tracked)
      if [ "$ignored" -eq 0 ]; then
        fail "artifacts is 'tracked' but an ignore rule matches $CHUNK_REL — git is"
        fail "  silently dropping the docs you believe you are committing."
        fail "  Check .gitignore and .git/info/exclude."
      else
        pass "artifacts: tracked"
      fi
      ;;
    "")
      warn "artifacts mode not declared (tracked|untracked) — set it once per feature;"
      warn "  see references/audit-readiness.md. No tracking check was performed."
      ;;
    *)
      fail "artifacts '$mode' is not tracked|untracked"
      ;;
  esac
}

# An untracked chunk directory survives a branch switch, so a chunk from
# another branch can sit there looking live. Recorded-vs-current is a warning,
# not a failure: a branch rename or a deliberate move is legitimate, and the op
# that would block on it is the one you run to recover. Visibility is the goal.
check_branch() {
  local rec cur
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  rec="$(jget '.branch // empty')"
  if [ "$cur" = "HEAD" ]; then
    warn "detached HEAD — no branch to reconcile against"
    return 0
  fi
  if [ -z "$rec" ]; then
    info "no branch recorded yet — a full readiness will pin '$cur'"
  elif [ "$rec" = "$cur" ]; then
    pass "branch matches recorded: $cur"
  else
    warn "branch drift: state records '$rec', HEAD is on '$cur'."
    warn "  Confirm this is the right chunk for this branch before planning."
    warn "  Chunk docs that are untracked outlive a branch switch; tracked ones"
    warn "  would have disappeared with it."
  fi
}

# --- what a bypassed chunk actually shipped ---------------------------------
# There is no `implement` op and a bypassed chunk never runs `verify`, so its
# work happens in the gap between `bypass` and this gate and appears in no
# transcript, no `status` output and no state field. `bypass_note` records what
# the work *would be*, in the future tense, and nothing ever reconciles it
# against what was done. A maintainer closing a bypassed chunk in 2026-07 asked
# "don't we have to implement this chunk?" — the work was on disk and already
# approved, and nothing the harness printed said so.
#
# This is a record, not a check: it cannot fail the gate. The human has read the
# diff and the diff is the authority. What it buys is that next session's
# `status` can answer "what shipped here?" without a git archaeology detour.
record_bypass_shipped() {
  local base src paths n
  # Two anchors, in order of authority. `baseline_sha` is the real one, but a
  # trivial chunk frequently has none: readiness hard-fails on its empty
  # test_paths, so the pin never happens. `bypass_base` is HEAD at the moment
  # `bypass` ran — recorded precisely so this op has something to measure from
  # when the chunk skipped the pin. Both use changed_paths, which spans commits,
  # index, worktree and untracked files.
  base="$(jget '.baseline_sha // empty')"
  if [ -n "$base" ] && git rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1; then
    src="baseline:${base:0:12}"
    paths="$(changed_paths "$base")"
  elif base="$(jget '.bypass_base // empty')"; [ -n "$base" ] \
       && git rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1; then
    src="bypass-base:${base:0:12}"
    paths="$(changed_paths "$base")"
  else
    # Last resort: the uncommitted delta only. This is where a bypassed chunk's
    # work sits *until* the human commits it — and the human committing is the
    # design's intended exit, so a chunk gated after its commit lands here with
    # nothing to show. That combination is what motivated bypass_base; chunks
    # bypassed before it existed still fall through to this arm.
    src="worktree"
    paths="$( { git diff --name-only
                git diff --name-only --cached
                git ls-files --others --exclude-standard
              } 2>/dev/null | sort -u )"
  fi
  # Chunk docs are bookkeeping, never the work. In `tracked` mode they would
  # otherwise dominate the record for exactly the chunks that shipped least.
  paths="$(printf '%s\n' "$paths" | grep -v '^$' | grep -v "^$FEATURE_REL/")"
  n="$(printf '%s\n' "$paths" | grep -c '^..*$')"
  if [ "$n" -eq 0 ]; then
    warn "no changed paths visible at gate time — recording an empty shipped set."
    warn "  If the work was committed past a baseline this chunk never pinned, the"
    warn "  record cannot see it. That is a gap in the record, not in the work."
  fi
  # --slurp/--raw-input rather than a loop: paths may contain anything but a
  # newline, and jq is already a dependency.
  jset '.bypass_shipped = {at: $now, source: $src, n: ($p | length), paths: $p}' \
    --arg src "$src" \
    --argjson p "$(printf '%s\n' "$paths" | grep -v '^$' | jq -R . | jq -s .)" \
    || return 1
  info "shipped ($src): $n path(s)"
  printf '%s\n' "$paths" | grep -v '^$' | sed 's/^/        /'
  return 0
}

# --- the handoff ------------------------------------------------------------
# `done` is terminal for the chunk and used to be a dead end for the session:
# the gate printed "the human commits from here" and the trail stopped there.
# The next session had to re-derive what to do next from feature.md's queue, and
# the operator had to compose the resume prompt from memory. Every other handoff
# in this skill is a file — non-negotiable #3 is that an answer living in chat
# scrollback does not exist next session — and this was the one transition that
# handed off nothing.
#
# The next chunk is found without parsing any markdown: sibling directories of
# this one, glob-sorted, first whose state.json is not `done`. feature.md's queue
# table stays the human's document; this reads the state the script itself wrote,
# so the two cannot drift.
next_msg() { printf 'NEXT  %s\n' "$1"; }
print_handoff() {
  local d rel st next_rel="" next_st="" next_name="" branch
  for d in "$REPO_ROOT/$FEATURE_REL"/*/; do
    [ -f "${d}state.json" ] || continue
    rel="${d%/}"; rel="${rel#"$REPO_ROOT"/}"
    st="$(jq -r '.stage // "specified"' "${d}state.json" 2>/dev/null)" || continue
    [ "$st" = "done" ] && continue
    next_rel="$rel"; next_st="$st"; next_name="$(basename "$rel")"
    break
  done
  if [ -z "$next_rel" ]; then
    # Deliberately NOT "the queue is clear". Chunk directories are stamped as
    # each chunk comes up, so a queue of 24 can have two directories on disk and
    # twenty-two rows that exist only in feature.md. This op reads state.json and
    # therefore cannot see those — announcing an empty queue from an empty
    # directory scan is a confidently wrong pointer, which is worse than
    # silence. Caught by running this against a real feature after writing it;
    # the fixtures agreed with the bug because every fixture chunk is stamped.
    next_msg "no unfinished chunk directory under $FEATURE_REL."
    next_msg "  That means every *stamped* chunk is done — not that the queue is empty."
    next_msg "  Chunk directories are stamped as each chunk comes up, so check the queue"
    next_msg "  table in $FEATURE_REL/feature.md for the next chunk to stamp."
    return 0
  fi
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ "$branch" = "HEAD" ] && branch="(detached)"
  next_msg "next chunk: $next_name (stage: $next_st)"
  next_msg "resume in a fresh session with:"
  next_msg ""
  next_msg "  /feature-chunker Repo: $REPO_ROOT, branch $branch."
  next_msg "  Feature: $FEATURE_REL/feature.md — read it and"
  next_msg "  $CHUNK_REL/retro.md first."
  next_msg "  Chunk $(basename "$CHUNK_REL") is done. Start $next_name."
  next_msg ""
  next_msg "Adjust the last line if the queue says this one is blocked on a decision."
  return 0
}

# --- the blind-predictions stamp (predict op) --------------------------------
# predictions.md is two halves: the top is filled BEFORE the plan is read
# (expected approach/files/risk), the bottom (disagreements, verdict) after.
# The unfilled-blank check and the verdict-vocabulary check both pass on a
# file filled in one pass, verdict included — they confirm the blanks are
# gone, which is not the property the gate needs. The property is ORDER, and
# `predict` is what observes it: it stamps a hash of the top half into
# state.json while the verdict is still blank, and `freeze` requires the
# stamped bytes to be identical when the verdict finally arrives. Found
# 2026-07-29 (a chunk whose whole predictions file was written in one pass,
# recording a gate about a plan that did not yet exist); designed the same
# day, built 2026-08-03.
#
# The original design keyed on plan.md's mtime ("the stamp must precede the
# plan being written"). Deliberately not built that way: under draft-ahead
# (references/plan.md § Draft-ahead) a drafted plan legitimately predates the
# arrival that fills the predictions, and mtimes are the least trustworthy
# fact in a tree that clones and checks out. What is provable without them:
# the top half existed filled at stamp time (predict refuses blanks), the
# verdict did not (predict refuses one), and whether plan.md existed on disk
# is recorded rather than guessed. Absence at stamp time plus presence at
# freeze proves the plan came after — no clock consulted. Presence at stamp
# time is the draft-ahead case, where blindness rests on the plan having been
# withheld; the honesty is on the human, and recording the condition is what
# makes the claim inspectable instead of assumed.
#
# § The one-pass recovery (--one-pass). Refusing a one-pass fill is correct and
# leaves the operator with exactly one route back to a stamp: blank the verdict,
# stamp, restore the verdict. That motion is byte-identical to what someone would
# do to launder a prediction written AFTER reading the plan — so the refusal
# manufactured, as its only recovery, the very act it exists to prevent, and the
# script then had to take the reconstruction on trust with nothing recorded.
# Observed twice: supply-chain-ops-assistant 01-inventory-patch-contract
# (2026-08-04, recovered by reconstruction, and named in that chunk's field-log
# line as the harness's one real gap) and 02-adjust-inventory-action the same
# day, which is the occurrence that built this.
#
# So: --one-pass accepts the already-filled file, stamps the top half, and writes
# `one_pass: true` plus the verdict that was sitting there. It does not pretend
# the strong claim holds. The tier is reported by freeze and by status, and the
# retro's field-log line is expected to name it. Three properties keep the flag
# from becoming the habitual invocation:
#   - it is REFUSED when the verdict is still blank, so it cannot be used where
#     the strong path was free (the --refreeze principle: keep the honest case
#     available and the quiet one out of reach);
#   - the top-half hash is stamped and bound exactly as on the strong path, so
#     everything the stamp did prove, it still proves;
#   - what it drops is stated in the record rather than in a comment, which is
#     the whole difference between a weaker claim and a false one.
# The hash is unaffected by the verdict either way: predictions_top_half() stops
# at the compare-half markers, so a one-pass file hashes the same bytes a blind
# one would.
predictions_top_half() { # everything above the compare-half markers
  awk '/^## Disagreements/ || /^## Verdict/ || /^Verdict:/ { exit } { print }' "$1"
}
predictions_top_hash() {
  if command -v sha256sum >/dev/null 2>&1; then predictions_top_half "$1" | sha256sum | awk '{print $1}'
  else predictions_top_half "$1" | shasum -a 256 | awk '{print $1}'; fi
}
pred_line_token() { # pred_line_token <file> <Verdict|Adjusted> — first word after the colon
  grep -E "^$2:[[:space:]]*" "$1" | head -1 | sed -E "s/^$2:[[:space:]]*//" | awk '{print $1}'
}

case "$OP" in

readiness)
  [ -z "$EXTRA1" ] || die "readiness takes no positional arguments"
  stage="$(jget '.stage')"
  info "stage: $stage"

  case "$stage" in
    specified|ready|blocked) mode="full" ;;
    *) if [ "$OPT_REBASELINE" -eq 1 ]; then mode="full"; else mode="reconcile"; fi ;;
  esac

  # --- read-only reconciliation: runs in both modes -----------------------
  check_spec_contract 0

  base="$(jget '.baseline_sha // empty')"
  if [ -n "$base" ]; then
    if git rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1; then
      pass "recorded baseline_sha is a real commit: ${base:0:12}"
    else
      fail "recorded baseline_sha $base is not a commit in this repo — state contradicts disk"
    fi
  fi

  size_class="$(jget '.size_class // empty')"
  case "$size_class" in
    trivial|small|standard) pass "size_class: $size_class" ;;
    "") fail "size_class not set — audit-readiness gates it (trivial|small|standard)" ;;
    *)  fail "size_class '$size_class' is not trivial|small|standard" ;;
  esac

  n_tp="$(jq -r '.test_paths | length' "$STATE")"
  [ "$n_tp" -gt 0 ] && pass "test_paths declared: $n_tp entry(ies)" \
    || fail "test_paths is empty — the oracle has nowhere to live"

  n_sp="$(jq -r '.scope_paths | length' "$STATE")"
  [ "$n_sp" -gt 0 ] && pass "scope_paths declared: $n_sp path(s)" \
    || fail "scope_paths is empty — declared scope is what verify enforces"

  check_artifacts_mode
  check_branch

  [ -n "$(git status --porcelain)" ] && warn "working tree not clean — baseline pins HEAD, not the dirty files"

  if [ "$mode" = "reconcile" ]; then
    info "stage is '$stage' — reconcile-only: nothing was written, the baseline was NOT re-pinned."
    info "  To check an in-flight chunk, run: chunk-check.sh verify $CHUNK_REL"
    info "  To genuinely restart it, run: chunk-check.sh readiness $CHUNK_REL --rebaseline"
    info "  (--rebaseline clears the freeze and returns the chunk to 'ready'.)"
  else
    run_suite || true
    if [ "$FAIL" -eq 0 ]; then
      head_sha="$(git rev-parse HEAD)"
      cur_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
      [ "$cur_branch" = "HEAD" ] && cur_branch=""
      if [ "$OPT_REBASELINE" -eq 1 ] && [ -n "$base" ]; then
        warn "--rebaseline: moving baseline ${base:0:12} -> ${head_sha:0:12}"
        warn "  clearing test_hashes, oracle_red and gates.plan — the plan gate must run again"
      fi
      # The pin is also the migration point: it materialises keys a newer
      # schema added (as null), renames keys a newer schema renamed, and stamps
      # the version — so the "older schema" warning clears itself instead of
      # nagging forever. `.segment` was schema 3's name for `.chunk`.
      if jset '.baseline_prev_sha = (.baseline_sha // null)
               | .baseline_sha = $sha | .stage = "ready" | .blockers = []
               | .branch = (if $br == "" then null else $br end)
               | .artifacts = (.artifacts // null)
               | .field_log = (.field_log // null)
               | .size_class_corrected = (.size_class_corrected // null)
               | .bypass_shipped = (.bypass_shipped // null)
               | .bypass_base = (.bypass_base // null)
               | .bypass_suite = (.bypass_suite // null)
               | .freeze_suite = (.freeze_suite // null)
               | .predict = (.predict // null)
               | .chunk = (.chunk // .segment) | del(.segment)
               | .schema_version = $smax
               | if $rebase then
                     .test_hashes = {} | .oracle_red = null | .oracle_green = null
                   | .gates.plan = null | .gates.plan_adjusted = null
                   | .plan_approved_sha = null | .predict = null
                   # bypass_note is what tells `verify` this chunk took the
                   # bypass route. A rebaseline puts it back into the
                   # lifecycle, so leaving it set would refuse the very op the
                   # rebaseline exists to re-enable.
                   | .bypass_note = null | .bypass_base = null
                 else . end' \
          --arg sha "$head_sha" --arg br "$cur_branch" --argjson smax "$SCHEMA_MAX" \
          --argjson rebase "$( [ "$OPT_REBASELINE" -eq 1 ] && echo true || echo false )"
      then
        pass "baseline pinned: ${head_sha:0:12}, stage=ready"
      fi
    else
      fail "not ready — fix blockers above before planning"
    fi
  fi
  ;;

predict)
  [ -z "$EXTRA1" ] || die "predict takes no positional arguments"
  stage="$(jget '.stage')"
  case "$stage" in
    ready) pass "predict legal from stage 'ready'" ;;
    *) fail "predict is legal from stage 'ready' only — the top half is stamped after readiness, before the plan is read; found '$stage'" ;;
  esac
  pred="$CHUNK_DIR/predictions.md"
  one_pass=false
  v_tok=""
  a_tok=""
  if [ ! -f "$pred" ]; then
    fail "predictions.md missing — stamp it from templates/predictions.md and fill the top half first"
  else
    if predictions_top_half "$pred" | grep -q '___'; then
      fail "the top half still has unfilled blanks — predict stamps a prediction, and an untouched template is not one"
    fi
    v_tok="$(pred_line_token "$pred" Verdict)"
    a_tok="$(pred_line_token "$pred" Adjusted)"
    compare_half_filled=0
    case "$v_tok" in ""|___) ;; *) compare_half_filled=1 ;; esac
    case "$a_tok" in ""|___) ;; *) compare_half_filled=1 ;; esac
    if [ "$OPT_ONE_PASS" -eq 1 ]; then
      # The recovery path for a file already filled in one pass. See the op's
      # header comment, § The one-pass recovery.
      if [ "$compare_half_filled" -eq 0 ]; then
        fail "--one-pass given, but predictions.md carries no verdict yet — the strong path is"
        fail "  available, so take it: run predict without the flag. --one-pass records a weaker"
        fail "  claim, and a weaker claim taken when the strong one was free is just a worse record."
      else
        one_pass=true
        warn "--one-pass: predictions.md already carries Verdict='$v_tok' Adjusted='$a_tok'."
        warn "  Stamping the top half anyway, and RECORDING that it happened this way. What this"
        warn "  stamp still proves: the top half was filled at stamp time, and freeze will prove it"
        warn "  did not change afterwards. What it does NOT prove: that the top half was written"
        warn "  before the plan was read. That ordering is ATTESTED by the operator, not observed"
        warn "  by this script. freeze and status report the weaker tier; say so in the field log."
      fi
    else
      case "$v_tok" in
        ""|___) ;;
        *) fail "predictions.md already carries a verdict ('$v_tok') — predict stamps the blind top"
           fail "  half BEFORE the plan is read. A file filled in one pass records a gate's outcome"
           fail "  about a plan that did not exist yet, which is the incident this op closes."
           fail "  If the fill really was predict-then-read, do NOT blank the verdict and restamp:"
           fail "  that motion is indistinguishable from laundering a prediction written after the"
           fail "  plan. Re-run with --one-pass, which stamps it and records the weaker claim." ;;
      esac
      case "$a_tok" in
        ""|___) ;;
        *) fail "predictions.md already answers Adjusted ('$a_tok') — that line belongs to the verdict, after the plan is read" ;;
      esac
    fi
  fi
  if [ "$FAIL" -eq 0 ]; then
    prior="$(jget '.predict.at // empty')"
    [ -n "$prior" ] && warn "replacing predict stamp from $prior — legal while the plan is unread; freeze checks the final stamp"
    plan_present=false
    if [ -f "$CHUNK_DIR/plan.md" ]; then
      plan_present=true
      warn "plan.md already on disk — recording plan_present=true (draft-ahead). Blindness now"
      warn "  rests on the plan having been withheld until the blanks were filled; recording"
      warn "  the condition is what keeps that claim inspectable instead of assumed."
    fi
    if jset '.predict = {at: $now, top_hash: $h, plan_present: $pp, one_pass: $op,
                         verdict_at_stamp: (if $op then $v else null end)}' \
        --arg h "$(predictions_top_hash "$pred")" --argjson pp "$plan_present" \
        --argjson op "$one_pass" --arg v "$v_tok"; then
      if [ "$one_pass" = "true" ]; then
        pass "top half stamped — one_pass=true recorded; freeze reports the attested tier, not the observed one"
      elif [ "$plan_present" = "true" ]; then
        pass "top half stamped — plan_present=true recorded; freeze will report this tier"
      else
        pass "top half stamped — no plan.md on disk: blind by construction"
      fi
    fi
  fi
  ;;

freeze)
  # Freeze is a transition, and every other transition op enforces where it may
  # run from. A warn here meant a `done`, `blocked` or `bypassed` chunk could be
  # re-opened to `approved` with a fresh plan_approved_sha and a new gates.plan,
  # which is not a state the lifecycle diagram admits.
  #
  # `approved` is legal behind --refreeze rather than forbidden outright,
  # because re-freezing after the gate adjusts the tests is a documented
  # workflow (plan.md, "Freezing early"). Requiring the flag is what stops the
  # legitimate case from doubling as a silent way to re-pin an oracle that was
  # edited during implement.
  stage="$(jget '.stage')"
  case "$stage" in
    ready) pass "freeze legal from stage 'ready'" ;;
    approved)
      if [ "$OPT_REFREEZE" -eq 1 ]; then
        warn "--refreeze from 'approved': the previous oracle pin and plan approval are being replaced"
      else
        fail "chunk is already 'approved' — freeze re-pins the oracle, so re-running it would"
        fail "  silently replace the pin the last plan gate approved. If the gate adjusted the"
        fail "  tests and this is a deliberate re-freeze, pass --refreeze."
      fi
      ;;
    *)
      fail "freeze is legal from stage 'ready' (or 'approved' with --refreeze); found '$stage'."
      fail "  To genuinely restart this chunk: chunk-check.sh readiness $CHUNK_REL --rebaseline"
      ;;
  esac
  check_spec_contract 1
  # -- the plan gate must have actually happened (predict-then-compare) ----
  pred="$CHUNK_DIR/predictions.md"
  verdict=""
  GATE_ADJUSTED=false
  if [ ! -f "$pred" ]; then
    fail "predictions.md missing — the plan gate is predict-then-compare and it did not happen"
  else
    # Blind predictions gate `standard` chunks only — softened 2026-07-31 by
    # operator decision after field-log entries 07–12 showed the blanks
    # degrading on smaller chunks (unfilled placeholders four chunks running,
    # then boilerplate). The gate itself still runs at every size: the
    # Verdict/Adjusted parse below stays mandatory, so the demotion rule keeps
    # its input and an untouched template is still refused — on the verdict
    # line rather than the blanks.
    if grep -q '___' "$pred"; then
      if [ "$(jget '.size_class // empty')" = "standard" ]; then
        fail "predictions.md still has unfilled blanks (___) — the gate was not run"
      else
        warn "predictions blanks left unfilled — tolerated below 'standard' (softened 2026-07-31); Verdict/Adjusted are still required"
      fi
    fi
    verdict="$(grep -E '^Verdict:[[:space:]]*' "$pred" | head -1 \
               | sed -E 's/^Verdict:[[:space:]]*//' | awk '{print $1}')"
    case "$verdict" in
      approve|auto-pass) pass "plan gate verdict: $verdict" ;;
      adjust) fail "plan gate verdict is 'adjust' — apply it and re-gate; freeze records approval only" ;;
      reject) fail "plan gate verdict is 'reject' — this chunk blocks (chunk-check.sh block), it does not freeze" ;;
      "")     fail "predictions.md has no 'Verdict:' line — the gate's outcome was never recorded" ;;
      *)      fail "predictions.md verdict '$verdict' unrecognised (approve|adjust|reject|auto-pass)" ;;
    esac
    adjusted="$(grep -E '^Adjusted:[[:space:]]*' "$pred" | head -1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]')"
    case "$adjusted" in
      y|yes) GATE_ADJUSTED=true ;;
      n|no)  GATE_ADJUSTED=false ;;
      *)     fail "predictions.md has no 'Adjusted: y|n' line — the demotion rule counts adjustments, not just rejections" ;;
    esac

    # -- the predict stamp: 'blind' as a checkable property (see the predict
    #    op's header comment for the full argument). The stamp is required on
    #    `standard` chunks — non-negotiable #6 claims both gates are
    #    instrumented, and before this check the blind half of predict-then-
    #    compare was instrumented in vocabulary only. Below `standard` the
    #    stamp is optional (the 2026-07-31 softening), but a stamp that
    #    exists is held to at every size: `small` relaxes whether you must
    #    predict, never whether a recorded prediction is honest.
    stamp_at="$(jget '.predict.at // empty')"
    if [ -n "$stamp_at" ]; then
      if [ "$(predictions_top_hash "$pred")" = "$(jget '.predict.top_hash // empty')" ]; then
        if [ "$(jget '.predict.one_pass // false')" = "true" ]; then
          # The weakest tier that still stamps. Loud, but not a failure: the
          # flag would be pointless if it blocked, and the point is to record
          # the weaker claim rather than force a reconstruction nobody can check.
          warn "predict stamp was taken with --one-pass: predictions.md already carried a verdict"
          warn "  ('$(jget '.predict.verdict_at_stamp // empty')') when the top half was stamped."
          warn "  The top half is unchanged since — that much is proven. Blind-before-plan is"
          warn "  ATTESTED by the operator, not observed here. Name it in the retro's field-log line."
          pass "predict stamp verified ($stamp_at) — attested tier (one-pass); see the warning above"
        elif [ "$(jget '.predict.plan_present')" = "true" ]; then
          pass "predict stamp verified ($stamp_at) — plan.md was on disk at stamp time: blindness rests on it having been withheld (draft-ahead)"
        else
          pass "predict stamp verified ($stamp_at) — stamped before plan.md existed: blind by construction"
        fi
      else
        fail "predictions.md's top half changed after the predict stamp ($stamp_at) — the stamp no"
        fail "  longer proves the predictions predate the plan. If the edit was honest (made before"
        fail "  the plan was read), re-run: chunk-check.sh predict $CHUNK_REL"
      fi
    elif [ "$(jget '.size_class // empty')" = "standard" ]; then
      fail "no predict stamp — on a 'standard' chunk the blind half of the gate is instrumented:"
      fail "  fill the top half, then run chunk-check.sh predict $CHUNK_REL before reading the plan"
    else
      info "no predict stamp (optional below 'standard' — softened 2026-07-31)"
    fi
  fi

  n_scope="$(jq -r '.scope_paths | length' "$STATE")"
  [ "$n_scope" -gt 0 ] && pass "declared scope: $n_scope path(s)" || fail "scope_paths is empty — plan must declare scope before freeze"
  check_test_paths
  files="$(list_test_files)"
  count=0
  if [ -z "$files" ]; then
    fail "no tracked files under test_paths — the oracle must exist (and be red) before freeze"
  else
    count="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
    pass "oracle files found: $count tracked file(s)"
  fi

  # -- the oracle must be demonstrably red before it is pinned (non-neg. #1)
  red_log="$CHUNK_DIR/oracle-red.log"
  oracle_rc=0
  if run_oracle "$red_log"; then
    fail "oracle_cmd exited 0 at freeze — a green oracle was never calibrated and"
    fail "  cannot be shown to detect absence; see $CHUNK_REL/oracle-red.log"
  else
    oracle_rc=$?
    pass "oracle red at freeze (exit $oracle_rc) — evidence in $CHUNK_REL/oracle-red.log"
  fi

  # Red for the wrong reason, checked at EVERY node-id tier. This used to sit
  # inside the id-capture branch below, which skipped it in precisely the worst
  # case: a module that fails to import produces no node-ids at all, so the run
  # where *nothing executed* was the one run the check did not inspect. Case 27
  # had pinned the check on a fixture whose ERROR line happened to carry a
  # node-id — which made it reachable and the gap invisible, the "passes for the
  # wrong reason" class this suite's header warns about. Found 2026-08-04.
  err_lines="$(oracle_error_lines "$red_log")"
  if [ -n "$err_lines" ]; then
    fail "the red run reports collection/setup ERRORs — red for the wrong reason:"
    printf '%s\n' "$err_lines" | sed 's/^/        /'
  fi

  red_ids="$(oracle_ids "$red_log" FAILED; oracle_ids "$red_log" ERROR)"
  red_ids="$(printf '%s' "$red_ids" | sort -u)"
  id_source="unparsed"
  if [ -n "$red_ids" ]; then
    id_source="pytest-summary"
    pass "oracle red node-ids captured: $(printf '%s\n' "$red_ids" | wc -l | tr -d ' ')"
    green_at_birth="$(oracle_ids "$red_log" PASSED)"
    if [ -n "$green_at_birth" ]; then
      fail "green-at-birth tests — these passed before the feature exists, so they assert nothing:"
      printf '%s\n' "$green_at_birth" | sed 's/^/        /'
    fi
  else
    warn "no per-test node-ids in the oracle output — evidence is exit-code only."
    warn "  (pytest emits them via PYTEST_ADDOPTS=-rA unless oracle_cmd sets its own -r.)"
  fi

  if [ "$FAIL" -eq 0 ]; then
    # Non-gating suite probe, run once before the stamp. `suite_cmd` is
    # *expected* to be red here — the file(s) just hash-pinned above are this
    # chunk's own oracle, unimplemented by construction, and the chunk's own
    # tests usually sit inside `suite_cmd`, so from freeze until
    # implementation goes green the suite carries their red. So a red exit
    # alone proves nothing new. What this catches is a break that has nothing
    # to do with that expected redness: a lint/doctrine/schema failure baked
    # into the newly-pinned test file itself, which today stays invisible
    # until implement's first full-suite run — discovered the hard way twice
    # (skill-engine chunks 14 and 15: a stray path reference and a dead
    # variable respectively, both inside the frozen oracle's own header,
    # both shellcheck/doctrine-only breaks unrelated to any test assertion).
    # Read the captured output above (or freeze_suite.exit below) for *where*
    # it failed, not just whether — a suite that dies in shellcheck before
    # ever reaching the tests phase looks identical, exit-code-wise, to one
    # that reached the tests phase and hit only the expected new-oracle red.
    record_suite_result "freeze_suite" \
      "expected while this chunk's own oracle is unimplemented — but read the output above: if it died somewhere other than this chunk's new test(s) (shellcheck, doctrine, json, another suite's tests), that's a break baked into the files just hash-pinned, not this chunk's normal red state"
    hashes="$(compute_hashes_json)"
    head_sha="$(git rev-parse HEAD)"
    ids_json="$(printf '%s' "$red_ids" | ids_to_json)"
    if jset '
          .test_hashes         = $h
        | .plan_approved_sha   = $sha
        | .gates.plan          = $verdict
        | .gates.plan_adjusted = $adjusted
        | .stage               = "approved"
        | .oracle_red = { cmd: $ocmd, exit_code: $orc, node_ids: $ids,
                          id_source: $isrc, at: $now }
        | .freeze_suite       = $fsuite' \
        --argjson h        "$hashes" \
        --arg     sha      "$head_sha" \
        --arg     verdict  "$verdict" \
        --argjson adjusted "$GATE_ADJUSTED" \
        --arg     ocmd     "$(jget '.oracle_cmd')" \
        --argjson orc      "$oracle_rc" \
        --argjson ids      "$ids_json" \
        --arg     isrc     "$id_source" \
        --argjson fsuite   "$SUITE_JSON"
    then
      pass "oracle frozen ($count tracked file(s) hash-pinned), plan approved at ${head_sha:0:12}, stage=approved"
    fi
  fi
  ;;

verify)
  # A bypassed chunk's exit is the review gate, not this op. It has no plan
  # gate and no freeze, so verify's first three checks are all asking about an
  # oracle that was never supposed to exist — and after `bypass --downgrade`,
  # about one that was deliberately deleted. Refusing here is cheap; not
  # refusing costs a full suite run and then reports the intended state of the
  # world as a wall of failures, which teaches the operator to read this op's
  # output as noise. `die`, not `fail`: this is the wrong op, not a failed check.
  #
  # Keyed on bypass_note, NOT on stage == "bypassed". The first version of this
  # guard used the stage and was useless the moment the chunk it was written for
  # passed its gate: `bypassed` -> `done` is one op, and the `done` chunk still
  # had no oracle. bypass_note is set by both bypass paths and survives that
  # transition, so it marks "this chunk took the bypass route" for as long as
  # that stays true. `readiness --rebaseline` clears it, because that genuinely
  # restarts the chunk into the lifecycle.
  [ "$(jget '.bypass_note // empty')" = "" ] \
    || die "verify does not apply to a bypassed chunk — it has no frozen oracle to check.
      A bypassed chunk's only exit is the human: chunk-check.sh gate $CHUNK_REL approved
      (the commit prohibition still covers it; the gate is what enforces that).
      To put this chunk through the full lifecycle instead:
      chunk-check.sh readiness $CHUNK_REL --rebaseline"

  base="$(jget '.baseline_sha // empty')"
  [ -n "$base" ] || die "baseline_sha not set — run readiness first"
  frozen="$(jget '.test_hashes')"
  [ "$frozen" != "{}" ] && [ "$frozen" != "null" ] || die "test_hashes empty — run freeze at plan approval first"

  # 1) Oracle integrity: recomputed map must equal frozen map exactly.
  check_test_paths
  current="$(compute_hashes_json)"
  if jq -n --argjson a "$frozen" --argjson b "$current" -e '$a == $b' >/dev/null; then
    pass "oracle unchanged since freeze"
  else
    fail "oracle integrity violated:"
    jq -n --argjson a "$frozen" --argjson b "$current" -r '
      ( $a | keys - ($b | keys) | .[] | "        removed/missing: " + . ),
      ( $b | keys - ($a | keys) | .[] | "        added:           " + . ),
      ( $a | keys as $ks | $ks[] | select($b[.] != null and $b[.] != $a[.]) | "        modified:        " + . )'
  fi

  # 2) Scope integrity: every changed path must be allowed.
  viol=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if ! path_allowed "$p"; then
      fail "out of declared scope: $p"; viol=$((viol+1))
    fi
  done < <(changed_paths "$base")
  [ "$viol" -eq 0 ] && pass "all changes within declared scope"

  # 3) Oracle red->green. Run oracle_cmd separately from suite_cmd, so a suite
  #    narrowed away from test_paths cannot produce a verified stamp, and pin
  #    the command itself so the thing calibrated red is the thing running.
  evidence_tier="none"
  frozen_cmd="$(jget '.oracle_red.cmd // empty')"
  live_cmd="$(jget '.oracle_cmd // empty')"
  green_log="$CHUNK_DIR/oracle-green.log"

  if [ -z "$live_cmd" ]; then
    fail "oracle_cmd not set — verify cannot prove the frozen oracle ran at all"
  elif [ -n "$frozen_cmd" ] && [ "$frozen_cmd" != "$live_cmd" ]; then
    fail "oracle_cmd changed since freeze — the command calibrated red is not the one running:"
    fail "        frozen: $frozen_cmd"
    fail "        now:    $live_cmd"
  else
    if [ -z "$frozen_cmd" ]; then
      evidence_tier="legacy"
      warn "state records no oracle_red — this chunk was frozen by a pre-schema-2 script."
      warn "  This verify proves the oracle passes; it does NOT prove the oracle could ever fail."
      warn "  Say so in the review packet."
    fi
    if run_oracle "$green_log"; then
      pass "oracle green (evidence in $CHUNK_REL/oracle-green.log)"
      [ "$evidence_tier" = "legacy" ] || evidence_tier="exit-code"
      red_json="$(jq -c '(.oracle_red.node_ids // []) | unique' "$STATE")"
      # `$a | length`, not bare `length`: under -n the input is null and bare
      # `length` would measure that (always 0), silently disabling this tier.
      n_red="$(jq -n --argjson a "$red_json" -r '$a | length')"
      if [ "$n_red" -gt 0 ]; then
        passed_json="$(oracle_ids "$green_log" PASSED | ids_to_json)"
        missing="$(jq -n --argjson a "$red_json" --argjson b "$passed_json" -r '($a - $b) | .[]')"
        if [ -z "$missing" ]; then
          pass "all $n_red frozen red node-id(s) now pass"
          evidence_tier="node-ids"
        else
          fail "frozen red node-ids that did not pass in this run (skipped, renamed, or no longer collected):"
          printf '%s\n' "$missing" | sed 's/^/        /'
        fi
      elif [ "$evidence_tier" = "exit-code" ]; then
        warn "no node-ids were captured at freeze — evidence is exit-code only"
      fi
    else
      fail "the frozen oracle is red at verify — see $CHUNK_REL/oracle-green.log"
    fi
  fi

  # 4) Suite green — rerun now, not recalled.
  run_suite || true

  # 5) Premature commits. The harness makes none; a commit before the review
  #    gate is a process fact, independent of whether the green just proven
  #    above is honest — so it must not block *recording* that green. It
  #    used to: this check failed outright, which kept stage from ever
  #    reaching `verified`, which is the one stage `gate` (the only op that
  #    can acknowledge a premature commit) is legal from — a chunk whose
  #    first-ever verify happened after a commit had no path out. Recording
  #    the fact in `gates.review` as `premature` instead of `pending` keeps
  #    `stage=verified` reachable on its own honest terms, and moves
  #    enforcement to where a human actually acts: `gate approved` below now
  #    refuses a `premature` chunk without an explicit note. Found 2026-07-31
  #    (skill-engine 12-make-sync): a bundled human commit landed before
  #    verify had ever succeeded once, and the chunk was stuck at `approved`
  #    with no legal op that could move it.
  n_commits="$(git rev-list --count "$base"..HEAD 2>/dev/null || echo 0)"
  review="$(jget '.gates.review // empty')"
  premature_commit=0
  if [ "$n_commits" -gt 0 ] && [ "$review" != "approved" ]; then
    warn "$n_commits commit(s) since baseline, before the review gate."
    warn "  Review-before-commit is the outer gate; committing first bypassed it."
    warn "  Recording gates.review=premature — 'gate approved' will require an"
    warn "  explicit note acknowledging this before it can stamp done."
    git --no-pager log --oneline "$base"..HEAD | sed 's/^/        /'
    premature_commit=1
  elif [ "$n_commits" -gt 0 ]; then
    info "commits since baseline: $n_commits — review gate already approved; these are the human's"
  else
    pass "no commits since baseline"
  fi

  if [ "$FAIL" -eq 0 ]; then
    review_stamp="pending"
    [ "$premature_commit" -eq 1 ] && review_stamp="premature"
    [ "$review" = "approved" ] && review_stamp="approved"
    if jset '.stage="verified" | .gates.review=$r
             | .oracle_green = { evidence_tier: $tier, at: $now }' \
        --arg tier "$evidence_tier" --arg r "$review_stamp"; then
      pass "stage=verified (oracle evidence: $evidence_tier) — assemble the review packet; human reviews BEFORE commit"
      [ "$premature_commit" -eq 1 ] && warn "gates.review=premature — gate approved must acknowledge the early commit with a note"
    fi
  else
    fail "verify failed — green is not honest; do not spend human review time on this"
  fi
  ;;

log)
  # Legal only once there is something honest to report: the retro's
  # observations (did the oracle catch a defect, how many red->green
  # iterations) describe a run that has to have happened. An entry written at
  # 'ready' is fiction, and fiction in the evidence base is worse than a gap,
  # because the demotion rule cannot tell the difference.
  stage="$(jget '.stage')"
  case "$stage" in
    verified|bypassed) pass "log legal from stage '$stage'" ;;
    *) fail "log is legal from stage 'verified' or 'bypassed'; found '$stage' — the retro reports a run that has not happened yet" ;;
  esac

  if [ "$FAIL" -eq 0 ]; then
    log_path="$(resolve_log_path)"
    if [ ! -f "$log_path" ]; then
      fail "field log not found: $log_path"
      fail "  stamp it from templates/field-log.md, then append this chunk's line."
      fail "  Use Write or Edit, never a shell '>>': the Bash sandbox denies writes"
      fail "  under ~/.claude, and a denied append that looks like it worked is how a"
      fail "  log silently stops being kept."
    elif ! scan_field_log "$log_path"; then
      fail "no field-log entry for chunk '$(jget '.chunk')' in $log_path"
      fail "  a line belongs to this chunk when its first three fields are the date,"
      fail "  the repo ($(basename "$REPO_ROOT")) and the chunk name. Entry format is in the log's header."
    else
      case "$FL_GATE" in
        approve|adjust|reject|auto-pass|none)
          exp_gate="$(expected_field_log_gate)"
          if [ "$FL_GATE" = "$exp_gate" ]; then
            pass "field-log entry found: gate:$FL_GATE"
          else
            fail "field-log says gate:$FL_GATE but the gate did something else (state.json: plan=$(jget '.gates.plan') adjusted=$(jget '.gates.plan_adjusted') -> gate:$exp_gate)"
            fail "  This is not cosmetic: the demotion rule reads this field, so logging an"
            fail "  adjusted plan gate as 'approve' counts a catch toward retiring the gate"
            fail "  that caught it. Fix the line, not state.json."
          fi ;;
        "") fail "the field-log entry has no legal gate: field — the demotion rule reads it, so an entry without one counts in neither direction" ;;
        *)  fail "the field-log entry has no legal gate: field (found 'gate:$FL_GATE'; expected approve|adjust|reject|auto-pass|none)" ;;
      esac
      [ -z "$FL_PLACEHOLDERS" ] \
        || fail "the field-log entry has unfilled placeholder(s): $FL_PLACEHOLDERS — an unanswered observation is not an observation"
      if [ "$FAIL" -eq 0 ]; then
        if jset '.field_log = {path: $p, line: $l, gate: $g, recorded: $now}' \
            --arg p "$log_path" --arg l "$FL_LINE" --arg g "$FL_GATE"; then
          pass "field-log entry verified and recorded"
          info "  $FL_LINE"
          info "the review gate will re-read this file rather than trust the record"
          info "demotion streak: $(field_log_streak "$log_path") consecutive clean gated chunk(s) — adjust/reject reset it, gate:none excluded; the rule and its n live in the log's header"
          overdue="$(candidates_overdue "$CANDIDATES_FILE")"
          if [ -n "$overdue" ]; then
            warn "the feature-chunker skill has open candidate(s) at 2+ occurrences —"
            warn "  its own escalation rule says the second incident builds the mechanism:"
            printf '%s\n' "$overdue" | while IFS="$(printf '\t')" read -r n title; do
              warn "  · $title ($n sightings)"
            done
            warn "  These are gaps in the skill, not in this repo. If this chunk's chafe line is"
            warn "  another sighting of one of them, raise its Occurrences in ${CANDIDATES_FILE:-CANDIDATES.md}"
            warn "  and build the fix while the incident is still in the window."
          fi
        fi
      fi
    fi
  fi
  ;;

gate)
  [ -n "$EXTRA1" ] || die "usage: chunk-check.sh gate <chunk-dir> <approved|changes-requested|rejected> [note]"
  stage="$(jget '.stage')"
  case "$stage" in
    verified|bypassed) pass "review gate legal from stage '$stage'" ;;
    *) fail "the review gate is legal from stage 'verified' or 'bypassed'; found '$stage'" ;;
  esac
  new_stage=""; gate_note=""
  case "$EXTRA1" in
    approved)
      new_stage="done"
      # A `premature` gates.review (verify recorded a commit that landed
      # before the review gate — see the verify op's step 5) must be
      # explicitly acknowledged here, in the one verdict that makes the
      # chunk terminal. Reusing gate_note's existing "append to blockers"
      # path rather than a new field: the acknowledgment is exactly the same
      # shape of evidence a rejection reason is, just attached to the
      # opposite verdict.
      prior_review="$(jget '.gates.review // empty')"
      if [ "$prior_review" = "premature" ]; then
        gate_note="$EXTRA2"
        if [ -z "$gate_note" ]; then
          fail "gates.review is 'premature' — a commit landed before verify first passed."
          fail "  approved requires a note acknowledging the human's after-the-fact review:"
          fail "  chunk-check.sh gate $CHUNK_REL approved \"<note>\""
        else
          pass "premature-commit acknowledgment recorded: $gate_note"
        fi
      fi
      # `done` is terminal, so it is the last moment the evidence can be
      # required at all. Only this verdict demands it: a chunk going back to
      # implement or to blocked has not finished, and charging it for a retro
      # it cannot yet write is ceremony at the wrong moment.
      #
      # Re-read the file rather than trust `.field_log.line` — non-negotiable
      # #3 applied to this record like every other. A recorded entry is a claim
      # about a file that anything could have edited since.
      fl_line="$(jget '.field_log.line // empty')"
      fl_path="$(jget '.field_log.path // empty')"
      if [ -z "$fl_line" ]; then
        fail "no field-log entry recorded — the retro is what the demotion rule runs on,"
        fail "  and a gate nobody has evidence about can never be retired or defended."
        fail "  Append the line, then: chunk-check.sh log $CHUNK_REL"
      elif [ ! -f "$fl_path" ]; then
        fail "the recorded field-log entry is no longer present: $fl_path is missing"
      elif ! grep -qxF "$fl_line" "$fl_path"; then
        fail "the recorded field-log entry is no longer present in $fl_path"
        fail "  recorded: $fl_line"
        fail "  re-append it (or re-run log) rather than editing the record to match"
      else
        pass "field-log entry still present in $fl_path"
      fi
      ;;
    changes-requested) new_stage="approved" ;;
    rejected)
      new_stage="blocked"
      gate_note="$EXTRA2"
      [ -n "$gate_note" ] || fail "a rejected review needs a reason — the retro will want it"
      ;;
    *) fail "unknown verdict '$EXTRA1' (approved|changes-requested|rejected)" ;;
  esac
  if [ "$FAIL" -eq 0 ]; then
    if jset '.gates.review = $v | .stage = $s
             | .blockers = (if $note == "" then .blockers else .blockers + [$note] end)' \
        --arg v "$EXTRA1" --arg s "$new_stage" --arg note "$gate_note"; then
      pass "review gate: $EXTRA1 — stage=$new_stage"
      if [ "$EXTRA1" = "approved" ]; then
        info "the human commits from here; the harness still does not"
        # Ordered deliberately: the shipped record is about the chunk closing,
        # the handoff is about the session continuing, and the handoff prints
        # last so it is what the operator's eye lands on.
        [ -n "$(jget '.bypass_note // empty')" ] && record_bypass_shipped
        print_handoff
      fi
    fi
  fi
  ;;

bypass)
  stage="$(jget '.stage')"
  size_class="$(jget '.size_class // empty')"
  if [ "$OPT_DOWNGRADE" -eq 1 ]; then
    # The correction path. A chunk escalated out of `trivial` by mistake used to
    # have no exit: `bypass` was illegal past `ready`, so once the misjudgement
    # was visible the only moves were `blocked` (which means unfinished work,
    # and this work is finished) or grinding through gates nobody needed. Both
    # lose the escalation error, which is the single most valuable thing the
    # proportionality dataset can record.
    #
    # What this path does NOT do is skip the review gate: `bypassed` still
    # exits through `gate`, and `gate approved` still re-reads the field log.
    # What it does skip is `verify` — so it is deliberately explicit (a flag,
    # never inferred), it demands a reason, and it records where it was used
    # from. The freeze evidence is left in place on purpose: `test_hashes` and
    # `oracle_red` are the receipt for what the over-escalation cost.
    case "$stage" in
      done)     fail "--downgrade is legal from any stage before 'done'; found 'done' — a closed chunk is not re-opened here" ;;
      bypassed) fail "--downgrade is legal from any stage before 'done'; found 'bypassed' — this chunk is already bypassed" ;;
      *)        pass "bypass --downgrade legal from stage '$stage'" ;;
    esac
    [ "$size_class" != "trivial" ] \
      || fail "--downgrade corrects an over-escalation, but size_class is already 'trivial' — run bypass without the flag"
  else
    case "$stage" in
      specified|ready) ;;
      *) fail "bypass is legal only from 'specified' or 'ready'; found '$stage' — a frozen chunk cannot be bypassed. If the escalation itself was the error, correct it: bypass --downgrade" ;;
    esac
    [ "$size_class" = "trivial" ] \
      || fail "bypass requires size_class 'trivial' (found '${size_class:-unset}') — non-negotiable #7 is proportionality, not convenience"
  fi
  [ -n "$EXTRA1" ] || fail "bypass needs a one-line description of the work — it is the entire log entry"
  # Join the positionals the way `block` does: bypass_note is the entire record
  # of a bypassed chunk, so an unquoted description silently truncated to its
  # first word loses the only evidence the ceremony was disproportionate.
  bypass_note="$EXTRA1${EXTRA2:+ $EXTRA2}"
  if [ "$FAIL" -eq 0 ]; then
    # Before the stamp, not after: the value of this run is knowing the repo was
    # green BEFORE the work, so it has to happen while "before" is still true.
    record_suite_result "bypass_suite" "it predates this chunk; whether that blocks the work is the review gate's call"
    if [ "$OPT_DOWNGRADE" -eq 1 ]; then
      # The plan gate really ran here, so its verdict is real data the demotion
      # streak is entitled to — unlike a straight bypass, which prints
      # `gate:none` because no gate ever happened. Everything the partial
      # lifecycle can answer is left as `?` for the retro to fill; only
      # `ceremony-ok` is pre-filled, because `n` is what this path *means*.
      # Same derivation `log` will check this line against, from one function:
      # a line this script printed and then refused would be the worst of both.
      fl_gate="$(expected_field_log_gate)"
      if jset '.stage="bypassed" | .gates.review="pending" | .bypass_note=$n
               | .bypass_base=(if $base == "" then null else $base end)
               | .bypass_suite=$suite
               | .size_class_corrected={from: .size_class, to: "trivial", from_stage: $st, reason: $n, at: $now}
               | .size_class="trivial"' --arg n "$bypass_note" --arg st "$stage" \
               --argjson suite "$SUITE_JSON" \
               --arg base "$(git rev-parse HEAD 2>/dev/null || printf '')"; then
        pass "stage=bypassed, size_class $size_class -> trivial (correction recorded)"
        warn "update spec.md's \`size-class\` block to 'trivial' as well — readiness hard-fails on the divergence"
        info "freeze evidence left in place: it is the record of what the over-escalation cost"
        info "record the verdict with: chunk-check.sh gate $CHUNK_REL approved"
        printf 'FIELDLOG %s | %s | %s | gate:%s | oracle-caught:? | freeze-trip:? | scope-dev:? | bypass:y | ceremony-ok:n | context:? | chafe: ?\n' \
          "$(date -u +%Y-%m-%d)" "$(basename "$REPO_ROOT")" "$(jget '.chunk')" "$fl_gate"
        info "append the FIELDLOG line above to the field log using Write/Edit (a shell append may be denied by the sandbox); default path ~/.claude/feature-chunker-field-log.md, or the repo-local path feature.md names for a team"
        info "fill every '?' from retro.md — 'log' refuses a line with a '?' left in it — then: chunk-check.sh log $CHUNK_REL"
      fi
    elif jset '.stage="bypassed" | .gates.plan="n/a" | .gates.plan_adjusted=false
             | .gates.review="pending" | .bypass_note=$n
             | .bypass_base=(if $base == "" then null else $base end)
             | .bypass_suite=$suite' \
             --arg n "$bypass_note" --argjson suite "$SUITE_JSON" \
             --arg base "$(git rev-parse HEAD 2>/dev/null || printf '')"; then
      pass "stage=bypassed — do the work, then hand the diff to the human"
      info "record the verdict with: chunk-check.sh gate $CHUNK_REL approved"
      printf 'FIELDLOG %s | %s | %s | gate:none | oracle-caught:n/a | freeze-trip:n/a | scope-dev:n/a | bypass:y | ceremony-ok:? | context:? | chafe: ?\n' \
        "$(date -u +%Y-%m-%d)" "$(basename "$REPO_ROOT")" "$(jget '.chunk')"
      info "append the FIELDLOG line above to the field log using Write/Edit (a shell append may be denied by the sandbox); default path ~/.claude/feature-chunker-field-log.md, or the repo-local path feature.md names for a team"
      info "fill every '?' from retro.md, chafe: included — 'log' refuses a line with a '?' left in it — then: chunk-check.sh log $CHUNK_REL"
    fi
  fi
  ;;

block)
  [ -n "$EXTRA1" ] || die "usage: chunk-check.sh block <chunk-dir> \"<reason>\""
  reason="$EXTRA1${EXTRA2:+ $EXTRA2}"
  if jset '.stage="blocked" | .blockers += [$r]' --arg r "$reason"; then
    pass "stage=blocked — blocker recorded: $reason"
    info "recovery: resolve it, then chunk-check.sh readiness $CHUNK_REL"
  fi
  ;;

status)
  jq -r '"chunk:          \(.chunk)",
         "stage:          \(.stage)",
         "size_class:     \(.size_class)\(if .size_class_corrected then "  (corrected from \(.size_class_corrected.from) at stage \(.size_class_corrected.from_stage))" else "" end)",
         "artifacts:      \(.artifacts // "undeclared")",
         "branch:         \(.branch // "-")",
         "suite_cmd:      \(.suite_cmd)",
         "oracle_cmd:     \(.oracle_cmd)",
         "oracle red:     exit \(.oracle_red.exit_code // "-") · \((.oracle_red.node_ids // []) | length) node-id(s) · \(.oracle_red.id_source // "-")",
         "oracle green:   \(.oracle_green.evidence_tier // "-")",
         "predict:        \(if .predict then "stamped \(.predict.at) · plan_present=\(.predict.plan_present)\(if .predict.one_pass then " · ONE-PASS (attested, not observed)" else "" end)" else "-" end)",
         "freeze suite:   \(if .freeze_suite then "exit \(.freeze_suite.exit) · \(.freeze_suite.cmd)" else "-" end)",
         "baseline_sha:   \(.baseline_sha)",
         "baseline_prev:  \(.baseline_prev_sha)",
         "plan_approved:  \(.plan_approved_sha)",
         "oracle files:   \(.test_hashes | length)",
         "scope paths:    \(.scope_paths | length)",
         "deviations:     \(.deviations | length)",
         "blockers:       \(.blockers | length)",
         "bypass_note:    \(.bypass_note)",
         "bypass suite:   \(if .bypass_suite then "exit \(.bypass_suite.exit) · \(.bypass_suite.cmd)" else "-" end)",
         "shipped:        \(if .bypass_shipped then "\(.bypass_shipped.n) path(s) via \(.bypass_shipped.source): \((.bypass_shipped.paths // []) | join(", "))" else "-" end)",
         "gates:          plan=\(.gates.plan) adjusted=\(.gates.plan_adjusted) review=\(.gates.review)",
         "updated:        \(.updated)"' "$STATE"
  ;;

*) usage ;;
esac

if [ "$OP" != "status" ]; then
  if [ "$FAIL" -eq 0 ]; then printf 'RESULT PASS (%s)\n' "$OP"; exit 0
  else printf 'RESULT FAIL (%s) — %d failure(s)\n' "$OP" "$FAIL"; exit 1; fi
fi
