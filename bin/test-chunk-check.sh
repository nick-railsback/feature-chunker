#!/usr/bin/env bash
# test-chunk-check.sh — fixture suite for the deterministic backstop.
# The skill's thesis is that guarantees belong in executed code and that
# executed code needs an oracle demonstrated red. This is that oracle.
# Run: bash bin/test-chunk-check.sh   (no executable bit required)
#
# CALIBRATE IT THE WAY THE SKILL ASKS YOU TO CALIBRATE ANYTHING ELSE.
# Green here means "no fixture noticed", which is not the same as "the guarantee
# holds". After adding a check to chunk-check.sh, delete that check in a scratch
# copy and confirm this suite goes red:
#
#   d=$(mktemp -d); cp bin/chunk-check.sh bin/test-chunk-check.sh "$d/"
#   # ...remove the check in $d/chunk-check.sh...
#   bash "$d/test-chunk-check.sh"      # MUST fail; if it passes, the check is unpinned
#
# A 2026-07 audit ran that trial across eight checks and five survived — the
# green-at-birth refusal, the collection-ERROR refusal, and all three plan-gate
# parse failures. Cases 26-30 exist because of it. A guarantee this suite does
# not notice the deletion of is a guarantee this suite does not hold.
#
# Zero language dependencies: the fixture "runner" is a shell script inside a
# throwaway git repo, so this suite runs anywhere git and jq do. A suite that
# only runs where pytest is installed is a suite that stops being run.
set -u -o pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/chunk-check.sh"
TEMPLATES="$(cd "$(dirname "$0")/.." && pwd)/templates"
CHUNK="docs/chunks/f/01-x"
# -P: git resolves symlinks when it reports the repo root, and on macOS /tmp is
# a symlink to /private/tmp. Without the physical path chunk-check.sh would
# correctly refuse every fixture as "outside the repo".
FIXROOT="$(mktemp -d "${TMPDIR:-/tmp}/chunkfix.XXXXXX")" || { echo "cannot create fixture root"; exit 2; }
FIXROOT="$(cd "$FIXROOT" && pwd -P)"
trap 'chmod -R u+w "$FIXROOT" 2>/dev/null; rm -rf "$FIXROOT"' EXIT INT TERM
PASSED=0; FAILED=0

command -v jq  >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required"; exit 2; }

# --- assertions ------------------------------------------------------------

expect() { # expect <label> <want-rc> <want-substring> -- <cmd...>
  local label="$1" want_rc="$2" want_txt="$3"; shift 4
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" != "$want_rc" ] || ! printf '%s' "$out" | grep -qF "$want_txt"; then
    printf 'FAIL  %s (rc=%s want=%s; looking for: %s)\n' "$label" "$rc" "$want_rc" "$want_txt"
    printf '%s\n' "$out" | sed 's/^/      | /'
    FAILED=$((FAILED+1))
  else
    printf 'ok    %s\n' "$label"
    PASSED=$((PASSED+1))
  fi
}

expect_absent() { # expect_absent <label> <forbidden-substring> -- <cmd...>
  local label="$1" bad_txt="$2"; shift 3
  local out
  out="$("$@" 2>&1)" || true
  if printf '%s' "$out" | grep -qF "$bad_txt"; then
    printf 'FAIL  %s (output must NOT contain: %s)\n' "$label" "$bad_txt"
    printf '%s\n' "$out" | sed 's/^/      | /'
    FAILED=$((FAILED+1))
  else
    printf 'ok    %s\n' "$label"
    PASSED=$((PASSED+1))
  fi
}

assert_eq() { # assert_eq <label> <actual> <want>
  if [ "$2" = "$3" ]; then
    printf 'ok    %s\n' "$1"
    PASSED=$((PASSED+1))
  else
    printf 'FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"
    FAILED=$((FAILED+1))
  fi
}

# --- fixture plumbing ------------------------------------------------------

chunk_check() { # chunk_check <repo_dir> <op> [args...]
  local repo_dir="$1" op="$2"; shift 2
  ( cd "$repo_dir" && bash "$CHECK" "$op" "$CHUNK" "$@" )
}

quiet_check() { chunk_check "$@" >/dev/null 2>&1 || true; }

# Same, with HOME overridden — the only safe way to exercise the default field
# log path (~/.claude/feature-chunker-field-log.md) without touching the
# operator's real one.
chunk_check_home() { # chunk_check_home <repo_dir> <home> <op> [args...]
  local repo_dir="$1" home="$2" op="$3"; shift 3
  ( cd "$repo_dir" && HOME="$home" bash "$CHECK" "$op" "$CHUNK" "$@" )
}

state_get() { # state_get <repo_dir> <jq filter>
  jq -r "$2" "$1/$CHUNK/state.json"
}

set_state() { # set_state <repo_dir> <jq filter> [jq args...]
  local repo_dir="$1" filter="$2"; shift 2
  jq "$@" "$filter" "$repo_dir/$CHUNK/state.json" > "$FIXROOT/state.tmp" \
    && mv "$FIXROOT/state.tmp" "$repo_dir/$CHUNK/state.json"
}

# Note on style: this file writes fixture content with printf, never with a
# here-document. Bash materialises a here-doc in a script as a real temp file
# in the system temp directory, which a sandboxed agent may not be allowed to
# write — the same class of failure as Finding 21. printf needs no temp file.
# spec.md is reconciled against state.json, so the fixture writes the fenced
# blocks chunk-check.sh parses. Every case therefore exercises the
# reconciliation implicitly, and a case that wants divergence has to ask for it.
write_spec() { # write_spec <repo_dir> <oracle_cmd> <size_class> [extra_test_path]
  {
    printf '%s\n' '# spec' '' '## Declared scope' '' '```scope' 'src' '```' ''
    printf '%s\n' '## Test paths' '' '```test-paths' 'tests/chunk'
    [ -n "${4:-}" ] && printf '%s\n' "$4"
    printf '%s\n' '```' ''
    printf '%s\n' '## Oracle command' '' '```oracle' "$2" '```' ''
    printf '%s\n' '## Size class' '' '```size-class' "$3" '```'
  } > "$1/$CHUNK/spec.md"
}

write_state() { # write_state <repo_dir> <oracle_cmd> [artifacts] [size_class]
  jq -n --arg ocmd "$2" --arg art "${3:-tracked}" --arg sz "${4:-small}" '{
    schema_version: 4,
    chunk: "01-x",
    stage: "specified",
    size_class: $sz,
    artifacts: $art,
    branch: null,
    suite_cmd: "true",
    oracle_cmd: $ocmd,
    oracle_red: null,
    oracle_green: null,
    baseline_sha: null,
    baseline_prev_sha: null,
    plan_approved_sha: null,
    test_paths: ["tests/chunk"],
    scope_paths: ["src"],
    test_hashes: {},
    deviations: [],
    blockers: [],
    gates: { plan: null, review: null },
    updated: null
  }' > "$1/$CHUNK/state.json"
}

write_predictions() { # write_predictions <repo_dir> <verdict> <adjusted>
  printf '%s\n' \
    '# plan gate (predict-then-compare)' \
    '' \
    '- Expected approach: create the feature file' \
    '- Expected files touched: src/feature.txt' \
    '- Biggest risk: none' \
    '' \
    '## Verdict' \
    '' \
    "Verdict: $2      (approve | adjust | reject)" \
    "Adjusted: $3     (y/n - was the plan changed as a result of this gate?)" \
    > "$1/$CHUNK/predictions.md"
}

new_fixture() { # new_fixture <name> [oracle_cmd] [tracked|untracked] [size_class]
  local name="$1"
  local oracle="${2:-bash tests/chunk/oracle.sh}"
  local artifacts="${3:-tracked}"
  local size_class="${4:-small}"
  local repo_dir="$FIXROOT/$name"
  mkdir -p "$repo_dir/src" "$repo_dir/tests/chunk" "$repo_dir/$CHUNK"
  printf 'baseline\n' > "$repo_dir/src/base.txt"
  printf '%s\n' '*.pyc' '__pycache__/' > "$repo_dir/.gitignore"

  # Exit-code-only oracle: red until src/feature.txt exists.
  printf '%s\n' \
    'if [ -f src/feature.txt ]; then exit 0; fi' \
    'exit 1' \
    > "$repo_dir/tests/chunk/oracle.sh"

  # Oracle that speaks pytest's short-summary dialect, so the node-id parser,
  # the subset check and the skip dodge are all exercised without pytest.
  # src/skip_b stands in for a conftest.py outside test_paths skipping a
  # frozen test while the frozen bytes stay identical.
  printf '%s\n' \
    'if [ -f src/feature.txt ]; then' \
    '  echo "PASSED tests/chunk/t.py::test_a"' \
    '  if [ -f src/skip_b ]; then' \
    '    echo "SKIPPED [1] tests/chunk/t.py:4: conftest said so"' \
    '  else' \
    '    echo "PASSED tests/chunk/t.py::test_b"' \
    '  fi' \
    '  exit 0' \
    'fi' \
    'echo "FAILED tests/chunk/t.py::test_a - feature absent"' \
    'echo "FAILED tests/chunk/t.py::test_b - feature absent"' \
    'exit 1' \
    > "$repo_dir/tests/chunk/nodes.sh"

  # Red overall, but one test passed before the feature existed — the realistic
  # green-at-birth shape. case08's fully-green oracle does not cover it.
  printf '%s\n' \
    'echo "PASSED tests/chunk/t.py::test_a"' \
    'echo "FAILED tests/chunk/t.py::test_b - feature absent"' \
    'exit 1' \
    > "$repo_dir/tests/chunk/birth.sh"

  # Red for the wrong reason: the tests never ran.
  printf '%s\n' \
    'echo "ERROR tests/chunk/t.py::test_a - fixture (db) not found"' \
    'exit 1' \
    > "$repo_dir/tests/chunk/collect.sh"

  # The feature-level doc that carries the chunk queue. It lives one level above
  # the chunk directory, which is why the scope check has to know about it.
  printf '%s\n' '# feature' '' '| 01 | x | small | specified |' \
    > "$repo_dir/docs/chunks/f/feature.md"

  write_spec "$repo_dir" "$oracle" "$size_class"
  write_predictions "$repo_dir" approve n

  write_state "$repo_dir" "$oracle" "$artifacts" "$size_class"

  ( cd "$repo_dir" \
    && git init -q . \
    && git config user.email fixture@example.invalid \
    && git config user.name fixture \
    && git config commit.gpgsign false ) >/dev/null 2>&1

  # Untracked-artifacts mode. The rule goes in .git/info/exclude, not
  # .gitignore: it is per-clone and never committed, so choosing it leaves no
  # trace in the repo — which is the whole point of the mode. Written before
  # the baseline `git add -A`, so the chunk dir is never tracked at all.
  if [ "$artifacts" = "untracked" ]; then
    printf '%s\n' 'docs/chunks/' >> "$repo_dir/.git/info/exclude"
  fi

  ( cd "$repo_dir" \
    && git add -A \
    && git commit -q --no-gpg-sign -m baseline ) >/dev/null 2>&1

  printf '%s' "$repo_dir"
}

tracked_count() { # tracked_count <repo_dir> <pathspec>
  ( cd "$1" && git ls-files -- "$2" | wc -l | tr -d ' ' )
}

implement() { printf 'feature\n' > "$1/src/feature.txt"; }

# The field log lives OUTSIDE the repo by design (default
# ~/.claude/feature-chunker-field-log.md), so every fixture points --log-path at
# FIXROOT. Nothing here may touch the operator's real log: a suite that appends
# to the evidence base corrupts the dataset the demotion rule reads.
field_log_path() { printf '%s/%s-field-log.md' "$FIXROOT" "$(basename "$1")"; }

log_line() { # log_line <repo_dir> <gate-verdict> [chunk] [ceremony-ok]
  printf '2026-07-28 | %s | %s | gate:%s | oracle-caught:y(2) | freeze-trip:n | scope-dev:n | bypass:n | ceremony-ok:%s | context:none | chafe: none' \
    "$(basename "$1")" "${3:-01-x}" "$2" "${4:-y}"
}

write_field_log() { # write_field_log <repo_dir> [line...]
  local f; f="$(field_log_path "$1")"; shift
  printf '%s\n' '# feature-chunker field log' '' '## Entry format' '' '---' > "$f"
  local line
  for line in "$@"; do printf '%s\n' "$line" >> "$f"; done
}

# Every fixture that closes a chunk needs a logged entry now, so the common
# path gets one helper rather than three lines repeated at each call site.
log_and_gate() { # log_and_gate <repo_dir> [verdict]
  write_field_log "$1" "$(log_line "$1" "${2:-approve}")"
  quiet_check "$1" log --log-path "$(field_log_path "$1")"
}

commit_all() { # commit_all <repo_dir> <message>
  ( cd "$1" && git add -A && git commit -q --no-gpg-sign -m "$2" ) >/dev/null 2>&1
}

# --- cases -----------------------------------------------------------------

# 1 — clean run: readiness -> freeze -> implement -> verify
d="$(new_fixture case01)"
expect "01 clean run: readiness pins the baseline"  0 "stage=ready"    -- chunk_check "$d" readiness
expect "01 clean run: freeze pins the oracle"       0 "stage=approved" -- chunk_check "$d" freeze
implement "$d"
expect "01 clean run: verify stamps verified"       0 "stage=verified" -- chunk_check "$d" verify
assert_eq "01 clean run: final stage is verified" "$(state_get "$d" .stage)" "verified"

# 2 — jset cannot write. Finding 21 + 13: the total silent write failure.
d="$(new_fixture case02)"
chmod a-w "$d/$CHUNK"
expect        "02 unwritable chunk dir: readiness fails" 1 "cannot create a temp file" -- chunk_check "$d" readiness
expect_absent "02 unwritable chunk dir: no false green"    "PASS  baseline pinned"      -- chunk_check "$d" readiness
chmod u+w "$d/$CHUNK"

# 3 — a frozen test file edited after freeze
d="$(new_fixture case03)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
printf '# edited after freeze\n' >> "$d/tests/chunk/oracle.sh"
expect "03 edited frozen test: verify fails" 1 "oracle integrity violated" -- chunk_check "$d" verify

# 4 — a file touched outside scope_paths
d="$(new_fixture case04)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
mkdir -p "$d/other"; printf 'x\n' > "$d/other/x.txt"
expect "04 out-of-scope edit: verify fails" 1 "out of declared scope: other/x.txt" -- chunk_check "$d" verify

# 5 — gitignored build artifact under test_paths must not break anything
d="$(new_fixture case05)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
mkdir -p "$d/tests/chunk/__pycache__"; printf 'junk\n' > "$d/tests/chunk/__pycache__/x.pyc"
expect "05 gitignored artifact under test_paths: verify passes" 0 "stage=verified" -- chunk_check "$d" verify

# 6 — an untracked test file appearing under test_paths
d="$(new_fixture case06)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
printf 'exit 0\n' > "$d/tests/chunk/test_extra.sh"
expect "06 untracked file under test_paths: verify fails" 1 "untracked file(s) under test_paths entry 'tests/chunk'" -- chunk_check "$d" verify

# 7 — a typo'd test_paths entry. The typo goes in BOTH spec.md and state.json:
#     they agree with each other and are jointly wrong about the repo, which is
#     the failure freeze is meant to catch and not the one readiness catches.
d="$(new_fixture case07)"
set_state "$d" '.test_paths = ["tests/chunk", "tests/chunkk"]'
write_spec "$d" 'bash tests/chunk/oracle.sh' small 'tests/chunkk'
quiet_check "$d" readiness
expect "07 typo'd test_paths entry: freeze fails, naming it" 1 "test_paths entry 'tests/chunkk' matches no tracked file" -- chunk_check "$d" freeze

# 8 — an oracle that is already green at freeze was never calibrated
d="$(new_fixture case08 'true')"
quiet_check "$d" readiness
expect "08 green oracle at freeze: freeze fails" 1 "exited 0 at freeze" -- chunk_check "$d" freeze

# 9 — pytest-shaped runner: frozen red node-ids all pass at verify
d="$(new_fixture case09 'bash tests/chunk/nodes.sh')"
quiet_check "$d" readiness; quiet_check "$d" freeze
assert_eq "09 node-ids: two captured at freeze" "$(state_get "$d" '.oracle_red.node_ids | length')" "2"
implement "$d"
expect "09 node-ids: verify passes at the node-ids tier" 0 "evidence: node-ids" -- chunk_check "$d" verify

# 10 — the skip dodge: bytes identical, but a frozen test no longer runs
d="$(new_fixture case10 'bash tests/chunk/nodes.sh')"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; printf 'skip\n' > "$d/src/skip_b"
expect "10 skipped frozen test: verify fails" 1 "did not pass in this run" -- chunk_check "$d" verify

# 11 — oracle_cmd swapped between freeze and verify
d="$(new_fixture case11)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
set_state "$d" '.oracle_cmd = "true"'
expect "11 oracle_cmd swapped after freeze: verify fails" 1 "oracle_cmd changed since freeze" -- chunk_check "$d" verify

# 12 — readiness on an in-flight chunk is reconcile-only
d="$(new_fixture case12)"
quiet_check "$d" readiness; quiet_check "$d" freeze
base_before="$(state_get "$d" .baseline_sha)"
expect "12 readiness on approved: reconcile-only" 0 "reconcile-only" -- chunk_check "$d" readiness
assert_eq "12 readiness on approved: baseline unmoved" "$(state_get "$d" .baseline_sha)" "$base_before"

# 13 — --rebaseline restarts the clock and clears the freeze
d="$(new_fixture case13)"
quiet_check "$d" readiness; quiet_check "$d" freeze
quiet_check "$d" readiness --rebaseline
assert_eq "13 --rebaseline: test_hashes cleared" "$(state_get "$d" '.test_hashes | length')" "0"
assert_eq "13 --rebaseline: stage back to ready"  "$(state_get "$d" .stage)" "ready"

# 14 — size_class is gated mechanically, not in prose
d="$(new_fixture case14)"
set_state "$d" '.size_class = null'
expect "14 null size_class: readiness fails, naming it" 1 "size_class not set" -- chunk_check "$d" readiness

# 15 — a commit before the review gate collapses the outer gate
d="$(new_fixture case15)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; commit_all "$d" "implement the feature"
expect "15 commit before review gate: verify fails, naming the commits" 1 "commit(s) since baseline with the review gate not approved" -- chunk_check "$d" verify

# 16 — the same commit, once the human's review verdict is on record
d="$(new_fixture case16)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; commit_all "$d" "implement the feature"
set_state "$d" '.gates.review = "approved"'
expect "16 commit after review approved: verify passes" 0 "stage=verified" -- chunk_check "$d" verify

# 17 — the review gate closes the lifecycle
d="$(new_fixture case17)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
log_and_gate "$d"
expect    "17 gate approved from verified: stage done" 0 "stage=done" -- chunk_check "$d" gate approved
assert_eq "17 gate approved from verified: state records done" "$(state_get "$d" .stage)" "done"

# 18 — the review gate is not a stage you can jump to
d="$(new_fixture case18)"
quiet_check "$d" readiness
expect "18 gate approved from ready: refused" 1 "legal from stage 'verified'" -- chunk_check "$d" gate approved

# 19 — bypass is proportionality, not convenience
d="$(new_fixture case19)"
expect "19 bypass with size_class small: refused" 1 "non-negotiable #7" -- chunk_check "$d" bypass "tiny tweak"

# 20 — an unfilled predictions.md is not a plan gate
d="$(new_fixture case20)"
write_predictions "$d" '___' '___'
quiet_check "$d" readiness
expect "20 unfilled predictions.md: freeze refused" 1 "unfilled blanks" -- chunk_check "$d" freeze

# 21 — the whole claim of untracked-artifacts mode: the backstop does not care
#      whether the chunk docs are committed. Every guarantee is pinned to
#      test_paths and to commit SHAs, neither of which the docs participate in.
#      The two asserts below come FIRST because without them this case could
#      pass while the fixture quietly tracked the docs anyway, proving nothing.
d="$(new_fixture case21 'bash tests/chunk/oracle.sh' untracked)"
assert_eq "21 untracked docs: nothing under docs/chunks is tracked" "$(tracked_count "$d" docs/chunks)" "0"
assert_eq "21 untracked docs: the oracle itself is still tracked"   "$(tracked_count "$d" tests/chunk)" "4"
expect "21 untracked docs: readiness pins the baseline" 0 "stage=ready"    -- chunk_check "$d" readiness
expect "21 untracked docs: freeze pins the oracle"      0 "stage=approved" -- chunk_check "$d" freeze
implement "$d"
expect "21 untracked docs: verify stamps verified"      0 "stage=verified" -- chunk_check "$d" verify
log_and_gate "$d"
expect "21 untracked docs: the review gate still closes it" 0 "stage=done" -- chunk_check "$d" gate approved
assert_eq "21 untracked docs: still nothing tracked at the end" "$(tracked_count "$d" docs/chunks)" "0"

# 22 — and it does not blind the scope check: ignoring docs/chunks must not
#      make anything else invisible to verify.
d="$(new_fixture case22 'bash tests/chunk/oracle.sh' untracked)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
mkdir -p "$d/other"; printf 'x\n' > "$d/other/x.txt"
expect "22 untracked docs: out-of-scope edit still fails" 1 "out of declared scope: other/x.txt" -- chunk_check "$d" verify

# 23 — a declared tracking mode that disagrees with git is state contradicting
#      disk, in both directions.
d="$(new_fixture case23a)"
set_state "$d" '.artifacts = "untracked"'
expect "23a untracked declared, docs tracked: readiness fails" 1 "file(s) under $CHUNK are tracked" -- chunk_check "$d" readiness

d="$(new_fixture case23b 'bash tests/chunk/oracle.sh' untracked)"
set_state "$d" '.artifacts = "tracked"'
expect "23b tracked declared, ignore rule present: readiness fails" 1 "silently dropping the docs" -- chunk_check "$d" readiness

d="$(new_fixture case23c)"
( cd "$d" && git rm -r -q --cached docs/chunks ) >/dev/null 2>&1
set_state "$d" '.artifacts = "untracked"'
expect "23c untracked declared, no ignore rule: readiness fails" 1 "nothing ignores" -- chunk_check "$d" readiness

# 24 — branch drift. Untracked docs outlive a branch switch, so a chunk
#      directory from another branch can sit there looking live.
d="$(new_fixture case24 'bash tests/chunk/oracle.sh' untracked)"
quiet_check "$d" readiness
assert_eq "24 branch is pinned at readiness" "$(state_get "$d" .branch)" "$( cd "$d" && git rev-parse --abbrev-ref HEAD )"
( cd "$d" && git checkout -q -b other-branch ) >/dev/null 2>&1
expect "24 branch drift: readiness warns, naming both" 0 "branch drift" -- chunk_check "$d" readiness

# 25 — a state file from an older schema still runs, and the baseline pin
#      migrates it rather than warning about it forever. Two migration kinds
#      in one fixture: keys a newer schema *added* (branch, artifacts — the
#      2->3 step) and the key it *renamed* (segment -> chunk, the 3->4 step,
#      which is the rename this skill went through).
d="$(new_fixture case25)"
set_state "$d" '.schema_version = 2 | .segment = .chunk | del(.chunk) | del(.branch) | del(.artifacts)'
expect    "25 older schema: readiness warns but proceeds" 0 "stage=ready" -- chunk_check "$d" readiness
assert_eq "25 older schema: version migrated on the pin" "$(state_get "$d" .schema_version)" "5"
assert_eq "25 older schema: artifacts key materialised"  "$(state_get "$d" '.artifacts | type')" "null"
assert_eq "25 older schema: field_log key materialised"  "$(state_get "$d" '.field_log | type')" "null"
assert_eq "25 older schema: segment key renamed to chunk" "$(state_get "$d" .chunk)" "01-x"
assert_eq "25 older schema: the old key is gone"          "$(state_get "$d" '.segment | type')" "null"

# --- 26-30: the plan gate and the oracle calibration ------------------------
# Five checks that a mutation trial showed this suite did not hold: deleting any
# of them left the suite green. They carry non-negotiable #1 (the oracle was
# calibrated) and #6 (the gate actually happened), so they were the two least
# affordable to leave unpinned.

# 26 — red overall, but a test that passed before the feature existed asserts
#      nothing. case08 covers the fully-green oracle; this is the partial one.
d="$(new_fixture case26 'bash tests/chunk/birth.sh')"
quiet_check "$d" readiness
expect "26 green-at-birth test in a red run: freeze fails, naming it" 1 "green-at-birth tests" -- chunk_check "$d" freeze

# 27 — red for the wrong reason: collection or fixture failure, no test ran.
d="$(new_fixture case27 'bash tests/chunk/collect.sh')"
quiet_check "$d" readiness
expect "27 collection ERROR in the red run: freeze fails" 1 "red for the wrong reason" -- chunk_check "$d" freeze

# 28 — no predictions.md at all. The gate did not happen.
d="$(new_fixture case28)"
quiet_check "$d" readiness
rm -f "$d/$CHUNK/predictions.md"
expect "28 missing predictions.md: freeze refused" 1 "predictions.md missing" -- chunk_check "$d" freeze

# 29 — freeze records approvals, not open questions or refusals.
d="$(new_fixture case29a)"
quiet_check "$d" readiness; write_predictions "$d" adjust y
expect "29a verdict 'adjust': freeze refused" 1 "apply it and re-gate" -- chunk_check "$d" freeze

d="$(new_fixture case29b)"
quiet_check "$d" readiness; write_predictions "$d" reject n
expect "29b verdict 'reject': freeze refused" 1 "this chunk blocks" -- chunk_check "$d" freeze

# 30 — the Adjusted: line is the demotion rule's only input. Without it an
#      adjusted-then-approved plan logs as a clean approval and the gate's modal
#      success disappears from its own estimator.
d="$(new_fixture case30)"
quiet_check "$d" readiness
printf '%s\n' '# plan gate' '- Expected approach: a' '- Expected files touched: b' \
  '- Biggest risk: c' 'Verdict: approve' > "$d/$CHUNK/predictions.md"
expect "30 missing 'Adjusted:' line: freeze refused" 1 "the demotion rule counts adjustments" -- chunk_check "$d" freeze

# --- 31-32: feature-level docs vs sibling chunks ----------------------------

# 31 — feature.md carries the chunk queue and templates/feature.md asks you to
#      keep it current. Doing so mid-chunk must not read as scope creep. Only
#      reachable in tracked mode: untracked docs are invisible to the diff.
d="$(new_fixture case31)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
printf '%s\n' '# feature' '' '| 01 | x | small | verified |' > "$d/docs/chunks/f/feature.md"
expect "31 feature.md updated mid-chunk (tracked): verify passes" 0 "stage=verified" -- chunk_check "$d" verify

# 32 — and the allowance stops there. A sibling chunk's directory is a different
#      review's diff.
d="$(new_fixture case32)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
mkdir -p "$d/docs/chunks/f/02-y"; printf '# spec\n' > "$d/docs/chunks/f/02-y/spec.md"
expect "32 sibling chunk dir stamped mid-chunk: verify fails" 1 "out of declared scope: docs/chunks/f/02-y/spec.md" -- chunk_check "$d" verify

# --- 33-35: spec.md is the approved contract, state.json is the enforced one -
# Divergence is silent in the dangerous direction: a spec declaring a narrow
# scope and a state declaring a wide one passes the scope check on a diff the
# human never agreed to.

# 33 — state widens the scope past what spec.md declares.
d="$(new_fixture case33)"
set_state "$d" '.scope_paths = ["src", "other"]'
expect "33 state scope wider than spec: readiness fails" 1 "'scope' disagrees with state.json scope_paths" -- chunk_check "$d" readiness

# 34 — a spec with no fenced blocks cannot be reconciled at all.
d="$(new_fixture case34)"
printf '# spec with no machine-readable blocks\n' > "$d/$CHUNK/spec.md"
expect "34 spec without fenced blocks: readiness fails" 1 "has no 'scope' fenced block" -- chunk_check "$d" readiness

# 35 — oracle_cmd is set by Track V after readiness, so freeze owns that one.
d="$(new_fixture case35)"
quiet_check "$d" readiness
set_state "$d" '.oracle_cmd = "bash tests/chunk/nodes.sh"'
expect "35 oracle_cmd diverged from spec: freeze fails" 1 "'oracle' disagrees with state.json oracle_cmd" -- chunk_check "$d" freeze
expect_absent "35 readiness does not gate oracle_cmd (Track V sets it later)" "'oracle' disagrees" -- chunk_check "$d" readiness

# --- 36: freeze is a transition and enforces where it runs from -------------

# 36a — a blocked chunk still has a red oracle, so the stage gate is the only
#       thing standing between it and a fresh plan_approved_sha.
d="$(new_fixture case36a)"
quiet_check "$d" readiness
quiet_check "$d" block "spec contradicts reality"
expect "36a freeze from 'blocked': refused" 1 "freeze is legal from stage 'ready'" -- chunk_check "$d" freeze

# 36b — re-freezing after the gate adjusts the tests is legitimate, but it
#       replaces an approved pin, so it has to be asked for.
d="$(new_fixture case36b)"
quiet_check "$d" readiness; quiet_check "$d" freeze
expect "36b re-freeze without the flag: refused" 1 "pass --refreeze" -- chunk_check "$d" freeze
expect "36b re-freeze with --refreeze: allowed" 0 "stage=approved" -- chunk_check "$d" freeze --refreeze

# --- 37: bypass, the whole path ---------------------------------------------
# bypass_note is the entire record of a bypassed chunk and the field-log line is
# the only evidence the ceremony was ever disproportionate. An unquoted
# description silently truncated to its first word loses both.
d="$(new_fixture case37 'bash tests/chunk/oracle.sh' tracked trivial)"
expect    "37 bypass keeps the whole description in the field-log line" 0 "chafe: rename the timeout constant" -- chunk_check "$d" bypass rename the timeout constant
assert_eq "37 bypass keeps the whole description in state" "$(state_get "$d" .bypass_note)" "rename the timeout constant"
log_and_gate "$d" none
expect    "37 a bypassed chunk still exits through the review gate" 0 "stage=done" -- chunk_check "$d" gate approved

# --- 38: the shipped templates, checked against their own checker -----------
# Every case above builds its fixture files programmatically, which means none
# of them had ever run chunk-check.sh against the documents a real user actually
# stamps. An end-to-end run found that templates/predictions.md explained the
# unfilled-blank rule by quoting the blank marker — so freeze rejected a fully
# filled gate, permanently, on the strength of its own instructions. These
# assertions pin the templates themselves.

d="$(new_fixture case38)"
cp "$TEMPLATES/predictions.md" "$d/$CHUNK/predictions.md"
expect "38 untouched template predictions.md: freeze refused" 1 "unfilled blanks" -- chunk_check "$d" freeze

# Fill it the way a human would: replace the blanks, leave the prose alone.
sed -e 's/^- Expected approach: .*/- Expected approach: add the thing/' \
    -e 's/^- Expected files touched: .*/- Expected files touched: src\/base.txt/' \
    -e 's/^- Biggest risk: .*/- Biggest risk: none/' \
    -e 's/^Verdict: .*/Verdict: approve/' \
    -e 's/^Adjusted: .*/Adjusted: n/' \
    "$TEMPLATES/predictions.md" > "$d/$CHUNK/predictions.md"
quiet_check "$d" readiness
expect_absent "38 filled template predictions.md: no phantom blanks" "unfilled blanks" -- chunk_check "$d" freeze
expect        "38 filled template predictions.md: gate recorded"  0 "plan gate verdict: approve" -- chunk_check "$d" freeze --refreeze

# The four fenced blocks in templates/spec.md must be the ones chunk-check.sh
# parses — an info string renamed on one side only is silent until a real chunk.
d="$(new_fixture case39)"
cp "$TEMPLATES/spec.md" "$d/$CHUNK/spec.md"
expect "39 template spec.md: all four blocks are found (values differ, blocks exist)" \
  1 "'scope' disagrees with state.json" -- chunk_check "$d" readiness
expect_absent "39 template spec.md: no block reported missing" "fenced block" -- chunk_check "$d" readiness

# --- 40-48: the field log is the evidence base, so it is enforced -----------
# Non-negotiable #6 says the gates "earn their keep via the field log or get
# demoted — by data, not by mood". A 2026-07 audit found the log empty at every
# install path: zero entries, so the demotion rule could never reach its n and
# every proportionality claim in this skill was unfalsified rather than
# validated. The append was the one step in the lifecycle backed by nothing but
# an instruction to remember — in a skill whose whole argument is that an agent
# attesting to its own work is not evidence.
#
# `log` verifies the entry is on disk and records it; `gate approved` refuses
# without one and re-reads the file rather than trusting the record.

# 40 — the terminal transition requires the evidence
d="$(new_fixture case40)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
expect    "40 gate approved with no field-log entry: refused" 1 "no field-log entry recorded" -- chunk_check "$d" gate approved
assert_eq "40 the chunk did not reach done" "$(state_get "$d" .stage)" "verified"

# 41 — a log path that does not exist is named, not silently skipped
d="$(new_fixture case41)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
expect "41 missing field log: log fails and names the path" 1 "field log not found" -- \
  chunk_check "$d" log --log-path "$FIXROOT/case41-absent.md"

# 42 — a log that exists but says nothing about this chunk is not evidence
d="$(new_fixture case42)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
write_field_log "$d" "$(log_line "$d" approve 09-other)"
expect "42 entry for a different chunk: log fails" 1 "no field-log entry for chunk '01-x'" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"

# 43 — the happy path, and it records what it verified
d="$(new_fixture case43)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
write_field_log "$d" "$(log_line "$d" approve)"
expect    "43 well-formed entry: log passes" 0 "field-log entry verified" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"
assert_eq "43 the verdict is parsed out of the line" "$(state_get "$d" .field_log.gate)" "approve"
assert_eq "43 the path is recorded for re-verification" "$(state_get "$d" .field_log.path)" "$(field_log_path "$d")"
expect    "43 gate approved now closes the chunk" 0 "stage=done" -- chunk_check "$d" gate approved

# 44 — an unfilled placeholder is not a filled-in line. `bypass` prints
#      `ceremony-ok:?` for the human to answer; a `?` that survives to the log
#      is the same failure `freeze` refuses in predictions.md.
d="$(new_fixture case44)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
write_field_log "$d" "$(log_line "$d" approve 01-x '?')"
expect "44 unfilled placeholder in the entry: log fails" 1 "unfilled placeholder" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"

# 45 — the demotion rule reads gate:, so an entry without a legal one is a line
#      that cannot count in either direction
d="$(new_fixture case45)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
write_field_log "$d" "2026-07-28 | $(basename "$d") | 01-x | gate:probably | oracle-caught:n | ceremony-ok:y | chafe: none"
expect "45 illegal gate verdict: log fails" 1 "legal gate: field" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"

# 45b — and an entry with no gate: field at all. Found by a mutation trial:
#       deleting the missing-field branch left the suite green, because 45
#       only ever exercised an illegal verdict. Two failure shapes, two cases.
d="$(new_fixture case45b)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
write_field_log "$d" "2026-07-28 | $(basename "$d") | 01-x | oracle-caught:n | ceremony-ok:y | chafe: none"
expect "45b entry with no gate: field: log fails" 1 "legal gate: field" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"

# 46 — verify, don't trust: a recorded entry is a claim about a file, and the
#      file can change between the retro and the gate
d="$(new_fixture case46)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
log_and_gate "$d"
write_field_log "$d"                      # the entry is removed after recording
expect    "46 recorded entry deleted from the log: gate refused" 1 "no longer present" -- chunk_check "$d" gate approved
assert_eq "46 the chunk did not reach done" "$(state_get "$d" .stage)" "verified"

# 47 — bypassed chunks need the entry MORE, not less: they are the only
#      evidence the ceremony was ever disproportionate, and they are invisible
#      to a dataset made only of chunks that paid for it
d="$(new_fixture case47 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" bypass "rename the timeout constant"
expect "47 bypassed chunk without an entry: gate refused" 1 "no field-log entry recorded" -- chunk_check "$d" gate approved
write_field_log "$d" "$(log_line "$d" none)"
expect "47 bypassed chunk with an entry: log passes" 0 "field-log entry verified" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"
expect "47 bypassed chunk then closes" 0 "stage=done" -- chunk_check "$d" gate approved

# 48 — only the terminal verdict requires evidence. A chunk going back to
#      implement or to blocked has not finished, so demanding a retro line for
#      it would be ceremony charged at the wrong moment.
d="$(new_fixture case48)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
expect "48 changes-requested needs no entry" 0 "stage=approved" -- chunk_check "$d" gate changes-requested "tighten the error path"
quiet_check "$d" verify
expect "48 rejected needs no entry" 0 "stage=blocked" -- chunk_check "$d" gate rejected "the spec was wrong"

# 49 — `log` is legal only once there is something honest to report. An entry
#      written at 'specified' would be reporting an oracle that has not run.
d="$(new_fixture case49)"
quiet_check "$d" readiness
write_field_log "$d" "$(log_line "$d" approve)"
expect "49 log before the work is done: refused" 1 "legal from stage 'verified'" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"

# 50 — the recorded path is what later ops use, so a team names it once.
#      Every case above passes --log-path explicitly, which left this branch
#      unexercised: the flag and the fallback are different code paths.
d="$(new_fixture case50)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
write_field_log "$d" "$(log_line "$d" approve)"
quiet_check "$d" log --log-path "$(field_log_path "$d")"
expect "50 log with no flag reuses the recorded path" 0 "field-log entry verified" -- chunk_check "$d" log

# 51 — and with nothing recorded and no flag, the default is
#      ~/.claude/feature-chunker-field-log.md. HOME is overridden so this
#      asserts the path string without going near the operator's real log —
#      which a fixture must never read or write: a suite that appends to the
#      evidence base corrupts the dataset the demotion rule runs on.
d="$(new_fixture case51)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
expect "51 no flag, nothing recorded: the default path is named" 1 \
  ".claude/feature-chunker-field-log.md" -- \
  chunk_check_home "$d" "$FIXROOT/fakehome" log

# --- summary ---------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
