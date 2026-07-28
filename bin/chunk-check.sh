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

usage() { die "usage: chunk-check.sh <readiness|freeze|verify|log|gate|bypass|block|status> <chunk-dir> [args]
       flags: --rebaseline (readiness), --refreeze (freeze), --log-path <file> (log)"; }

[ $# -ge 2 ] || usage
OP="$1"; CHUNK_ARG="$2"; shift 2

OPT_REBASELINE=0
OPT_REFREEZE=0
OPT_LOG_PATH=""
EXTRA1=""
EXTRA2=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rebaseline) OPT_REBASELINE=1 ;;
    --refreeze)   OPT_REFREEZE=1 ;;
    --log-path)   shift; [ $# -gt 0 ] || die "--log-path needs a file path"; OPT_LOG_PATH="$1" ;;
    --*)          die "unknown option: $1" ;;
    *)            if [ -z "$EXTRA1" ]; then EXTRA1="$1"; else EXTRA2="${EXTRA2:+$EXTRA2 }$1"; fi ;;
  esac
  shift
done

command -v jq  >/dev/null 2>&1 || die "jq is required"
command -v git >/dev/null 2>&1 || die "git is required"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
CHUNK_DIR="$(cd "$CHUNK_ARG" 2>/dev/null && pwd)" || die "chunk dir not found: $CHUNK_ARG"
case "$CHUNK_DIR" in "$REPO_ROOT"/*) ;; *) die "chunk dir must be inside the repo";; esac
CHUNK_REL="${CHUNK_DIR#"$REPO_ROOT"/}"
FEATURE_REL="$(dirname "$CHUNK_REL")"
STATE="$CHUNK_DIR/state.json"
cd "$REPO_ROOT" || die "cannot cd to repo root"

[ -f "$STATE" ] || die "missing $CHUNK_REL/state.json (stamp from templates/state.json)"
jq -e . "$STATE" >/dev/null 2>&1 || die "state.json is not valid JSON"

SCHEMA_MAX=5
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

oracle_error_lines() { grep -E '^ERROR[[:space:]]' "$1" 2>/dev/null; }

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
        if ($i ~ /^chafe:/) break
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
               | .chunk = (.chunk // .segment) | del(.segment)
               | .schema_version = $smax
               | if $rebase then
                     .test_hashes = {} | .oracle_red = null | .oracle_green = null
                   | .gates.plan = null | .gates.plan_adjusted = null
                   | .plan_approved_sha = null
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
    grep -q '___' "$pred" && fail "predictions.md still has unfilled blanks (___) — the gate was not run"
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
    err_lines="$(oracle_error_lines "$red_log")"
    if [ -n "$err_lines" ]; then
      fail "the red run reports collection/setup ERRORs — red for the wrong reason:"
      printf '%s\n' "$err_lines" | sed 's/^/        /'
    fi
  else
    warn "no per-test node-ids in the oracle output — evidence is exit-code only."
    warn "  (pytest emits them via PYTEST_ADDOPTS=-rA unless oracle_cmd sets its own -r.)"
  fi

  if [ "$FAIL" -eq 0 ]; then
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
                          id_source: $isrc, at: $now }' \
        --argjson h        "$hashes" \
        --arg     sha      "$head_sha" \
        --arg     verdict  "$verdict" \
        --argjson adjusted "$GATE_ADJUSTED" \
        --arg     ocmd     "$(jget '.oracle_cmd')" \
        --argjson orc      "$oracle_rc" \
        --argjson ids      "$ids_json" \
        --arg     isrc     "$id_source"
    then
      pass "oracle frozen ($count tracked file(s) hash-pinned), plan approved at ${head_sha:0:12}, stage=approved"
    fi
  fi
  ;;

verify)
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

  # 5) No commits. The harness makes none; a commit before the review gate
  #    collapses the outer gate the whole design is built around.
  n_commits="$(git rev-list --count "$base"..HEAD 2>/dev/null || echo 0)"
  review="$(jget '.gates.review // empty')"
  if [ "$n_commits" -gt 0 ] && [ "$review" != "approved" ]; then
    fail "$n_commits commit(s) since baseline with the review gate not approved."
    fail "  Review-before-commit is the outer gate; committing first deletes it."
    fail "  If the human has already reviewed, record it with"
    fail "  chunk-check.sh gate $CHUNK_REL approved, then re-run verify."
    fail "  Otherwise surface these to the human:"
    git --no-pager log --oneline "$base"..HEAD | sed 's/^/        /'
  elif [ "$n_commits" -gt 0 ]; then
    info "commits since baseline: $n_commits — review gate already approved; these are the human's"
  else
    pass "no commits since baseline"
  fi

  if [ "$FAIL" -eq 0 ]; then
    if jset '.stage="verified" | .gates.review="pending"
             | .oracle_green = { evidence_tier: $tier, at: $now }' \
        --arg tier "$evidence_tier"; then
      pass "stage=verified (oracle evidence: $evidence_tier) — assemble the review packet; human reviews BEFORE commit"
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
          pass "field-log entry found: gate:$FL_GATE" ;;
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
      [ "$EXTRA1" = "approved" ] && info "the human commits from here; the harness still does not"
    fi
  fi
  ;;

bypass)
  stage="$(jget '.stage')"
  case "$stage" in
    specified|ready) ;;
    *) fail "bypass is legal only from 'specified' or 'ready'; found '$stage' — a frozen chunk cannot be bypassed" ;;
  esac
  size_class="$(jget '.size_class // empty')"
  [ "$size_class" = "trivial" ] \
    || fail "bypass requires size_class 'trivial' (found '${size_class:-unset}') — non-negotiable #7 is proportionality, not convenience"
  [ -n "$EXTRA1" ] || fail "bypass needs a one-line description of the work — it is the entire log entry"
  # Join the positionals the way `block` does: bypass_note is the entire record
  # of a bypassed chunk, so an unquoted description silently truncated to its
  # first word loses the only evidence the ceremony was disproportionate.
  bypass_note="$EXTRA1${EXTRA2:+ $EXTRA2}"
  if [ "$FAIL" -eq 0 ]; then
    if jset '.stage="bypassed" | .gates.plan="n/a" | .gates.plan_adjusted=false
             | .gates.review="pending" | .bypass_note=$n' --arg n "$bypass_note"; then
      pass "stage=bypassed — do the work, then hand the diff to the human"
      info "record the verdict with: chunk-check.sh gate $CHUNK_REL approved"
      printf 'FIELDLOG %s | %s | %s | gate:none | oracle-caught:n/a | freeze-trip:n/a | scope-dev:n/a | bypass:y | ceremony-ok:? | context:? | chafe: %s\n' \
        "$(date -u +%Y-%m-%d)" "$(basename "$REPO_ROOT")" "$(jget '.chunk')" "$bypass_note"
      info "append the FIELDLOG line above to the field log using Write/Edit (a shell append may be denied by the sandbox); default path ~/.claude/feature-chunker-field-log.md, or the repo-local path feature.md names for a team"
      info "fill ceremony-ok:? and context:? in — 'log' refuses a line with a '?' left in it — then: chunk-check.sh log $CHUNK_REL"
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
         "size_class:     \(.size_class)",
         "artifacts:      \(.artifacts // "undeclared")",
         "branch:         \(.branch // "-")",
         "suite_cmd:      \(.suite_cmd)",
         "oracle_cmd:     \(.oracle_cmd)",
         "oracle red:     exit \(.oracle_red.exit_code // "-") · \((.oracle_red.node_ids // []) | length) node-id(s) · \(.oracle_red.id_source // "-")",
         "oracle green:   \(.oracle_green.evidence_tier // "-")",
         "baseline_sha:   \(.baseline_sha)",
         "baseline_prev:  \(.baseline_prev_sha)",
         "plan_approved:  \(.plan_approved_sha)",
         "oracle files:   \(.test_hashes | length)",
         "scope paths:    \(.scope_paths | length)",
         "deviations:     \(.deviations | length)",
         "blockers:       \(.blockers | length)",
         "bypass_note:    \(.bypass_note)",
         "gates:          plan=\(.gates.plan) adjusted=\(.gates.plan_adjusted) review=\(.gates.review)",
         "updated:        \(.updated)"' "$STATE"
  ;;

*) usage ;;
esac

if [ "$OP" != "status" ]; then
  if [ "$FAIL" -eq 0 ]; then printf 'RESULT PASS (%s)\n' "$OP"; exit 0
  else printf 'RESULT FAIL (%s) — %d failure(s)\n' "$OP" "$FAIL"; exit 1; fi
fi
