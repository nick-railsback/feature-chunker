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
#   d=$(mktemp -d); mkdir "$d/bin"; cp bin/chunk-check.sh bin/test-chunk-check.sh "$d/bin/"
#   cp -r templates "$d/templates"     # $TEMPLATES below is bin/../templates —
#                                       # a flat copy (no templates/ sibling)
#                                       # false-fails cases 25/38/39 regardless
#                                       # of what you mutated. Found 2026-07-31
#                                       # doing exactly this trial for real.
#   # ...remove the check in $d/bin/chunk-check.sh...
#   bash "$d/bin/test-chunk-check.sh"  # MUST fail; if it passes, the check is unpinned
#
# A 2026-07 audit ran that trial across eight checks and five survived — the
# green-at-birth refusal, the collection-ERROR refusal, and all three plan-gate
# parse failures. Cases 26-30 exist because of it. A guarantee this suite does
# not notice the deletion of is a guarantee this suite does not hold.
#
# Two things the 2026-07-29 trial added, both worth not re-learning:
#   - `bypass`'s original stage guard ("a frozen chunk cannot be bypassed") had
#     been live and unpinned since it was written. Nothing noticed until the
#     guard was modified. Pin a check when you touch it, not when you add it.
#   - The trial's real value was catching a bad test, not a bad check: case 55
#     asserted the --downgrade stage guard on a fixture that was already
#     `trivial`, so the already-trivial refusal fired first and produced the
#     right exit code for the wrong reason. Deleting the stage guard left the
#     suite green. Hence 55a/55b/55c on separate fixtures. A case that passes
#     for the wrong reason is worse than a missing one: it reads as coverage.
#
# And a third class, from 2026-07-29's second pass (cases 58/59). Both bugs it
# found were invisible here because THE FIXTURE WORLD IS MORE UNIFORM THAN THE
# REAL ONE: every fixture chunk directory is stamped, so "no unfinished chunk
# dir" and "the queue is empty" are the same statement in a fixture and wildly
# different in a 24-chunk feature where 22 rows have no directory yet; and every
# fixture left its work uncommitted, so a record that could only see the worktree
# looked complete until a human committed first — which is the design's intended
# exit. Both were caught by running the new code against the real chunk that
# motivated it, after this suite was green. Green here means no fixture noticed.
# Run it against the real thing before believing it.
#
# A fourth class, from 2026-07-29's third pass (case 25). An assertion can be
# blind to its own subject: `.some_key | type` is `"null"` in jq whether the key
# was materialised as null or was never written at all, so six migration
# assertions written that way passed no matter what the migration did. The
# mutation that exposed it deleted a migration line and the suite stayed green.
# ASSERT ON has(), not on the type of a missing key — and when a new assertion
# uses the same shape as an existing one, note that the shape itself has never
# been mutation-tested just because its neighbours are old.
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

# expect/expect_absent re-run the command, which is wrong for a one-shot
# transition: `gate approved` is legal exactly once, and the second call fails
# from stage 'done' for an unrelated reason. These assert over output captured
# from a single run instead.
assert_contains() { # assert_contains <label> <haystack> <needle>
  if printf '%s' "$2" | grep -qF -- "$3"; then
    printf 'ok    %s\n' "$1"
    PASSED=$((PASSED+1))
  else
    printf 'FAIL  %s (looking for: %s)\n' "$1" "$3"
    printf '%s\n' "$2" | sed 's/^/      | /'
    FAILED=$((FAILED+1))
  fi
}

assert_absent() { # assert_absent <label> <haystack> <needle>
  if printf '%s' "$2" | grep -qF -- "$3"; then
    printf 'FAIL  %s (output must NOT contain: %s)\n' "$1" "$3"
    printf '%s\n' "$2" | sed 's/^/      | /'
    FAILED=$((FAILED+1))
  else
    printf 'ok    %s\n' "$1"
    PASSED=$((PASSED+1))
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

# Same, with the candidates ledger overridden. The escalation warning has to be
# asserted against a ledger this suite controls: pointed at the real
# CANDIDATES.md the cases would pass or fail depending on what the maintainer's
# backlog happens to say today, which is a test of the wrong thing.
chunk_check_cand() { # chunk_check_cand <repo_dir> <ledger> <op> [args...]
  local repo_dir="$1" ledger="$2" op="$3"; shift 3
  ( cd "$repo_dir" && CHUNK_CHECK_CANDIDATES="$ledger" bash "$CHECK" "$op" "$CHUNK" "$@" )
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

# The predict-op fixtures need the two halves of predictions.md at different
# moments: top half filled while the verdict is still blank (that is what
# `predict` stamps), verdict filled later WITHOUT the top half changing a byte
# (that is what freeze verifies). Both emit through one top-half printer so
# the two files cannot drift apart and quietly break the hash comparison the
# cases exist to exercise.
predictions_top_lines() {
  printf '%s\n' \
    '# plan gate (predict-then-compare)' \
    '' \
    '- Expected approach: create the feature file' \
    '- Expected files touched: src/feature.txt' \
    '- Biggest risk: none' \
    ''
}
write_blind_predictions() { # top half filled, verdict not yet recorded
  { predictions_top_lines
    printf '%s\n' '## Verdict' '' 'Verdict: ___' 'Adjusted: ___'
  } > "$1/$CHUNK/predictions.md"
}
fill_verdict() { # fill_verdict <repo_dir> <verdict> <adjusted> — top half stays byte-identical
  { predictions_top_lines
    printf '%s\n' '## Verdict' '' "Verdict: $2" "Adjusted: $3"
  } > "$1/$CHUNK/predictions.md"
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

  # Green at birth with NO red node-id to parse: every test that reported
  # reported PASSED, and the run still exited non-zero — a wrapper whose
  # trailing non-test step fails, or a runner that exits non-zero for a
  # non-assertion reason. birth.sh cannot reach this: it always leaves a FAILED
  # id behind. See case 26b.
  printf '%s\n' \
    'echo "PASSED tests/chunk/t.py::test_a"' \
    'echo "PASSED tests/chunk/t.py::test_b"' \
    'exit 1' \
    > "$repo_dir/tests/chunk/allpass.sh"

  # Red for the wrong reason: the tests never ran.
  printf '%s\n' \
    'echo "ERROR tests/chunk/t.py::test_a - fixture (db) not found"' \
    'exit 1' \
    > "$repo_dir/tests/chunk/collect.sh"

  # Same, with no node-id — a module that failed to import is reported against
  # the file. The discriminator must not narrow to '::' and lose this.
  printf '%s\n' \
    'echo "ERROR tests/chunk/t.py - ImportError: cannot import name qux"' \
    'exit 1' \
    > "$repo_dir/tests/chunk/collectfile.sh"

  # Legitimately red, but the code under test logged at ERROR level and pytest
  # echoed the record under "Captured log call". Shares the '^ERROR' prefix and
  # is not a collection error — often it is the behaviour under test.
  printf '%s\n' \
    'echo "FAILED tests/chunk/t.py::test_b - feature absent"' \
    'echo "--------------------------- Captured log call ----------------------------"' \
    'echo "ERROR    pkg.mod:mod.py:474 Action failed for INV-00000001: unknown ID prefix."' \
    'exit 1' \
    > "$repo_dir/tests/chunk/logerror.sh"

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

log_line() { # log_line <repo_dir> <gate-verdict> [chunk] [ceremony-ok] [closed]
  printf '2026-07-28 | %s | %s | gate:%s | oracle-caught:y(2) | freeze-trip:n | scope-dev:n | bypass:n | ceremony-ok:%s | closed:%s | context:none | chafe: none' \
    "$(basename "$1")" "${3:-01-x}" "$2" "${4:-y}" "${5:-pending}"
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

# The handoff reads sibling chunk directories, not feature.md's queue table —
# state.json is what the script itself wrote, so the two cannot drift. A fixture
# that wants a queue therefore has to put one on disk.
add_sibling() { # add_sibling <repo_dir> <chunk-name> <stage>
  local dir="$1/docs/chunks/f/$2"
  mkdir -p "$dir"
  jq -n --arg c "$2" --arg s "$3" '{
    schema_version: 8, chunk: $c, stage: $s, size_class: "small",
    artifacts: "tracked", branch: null, suite_cmd: "true", oracle_cmd: null,
    oracle_red: null, oracle_green: null, baseline_sha: null,
    baseline_prev_sha: null, plan_approved_sha: null, test_paths: [],
    scope_paths: [], test_hashes: {}, deviations: [], blockers: [],
    bypass_note: null, bypass_base: null, bypass_shipped: null, field_log: null,
    gates: {plan: null, plan_adjusted: null, review: null}, updated: null
  }' > "$dir/state.json"
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

# 15 — a commit before the review gate is recorded, not blocked. It used to
# fail verify outright, which also made `gate` (the only op that can
# acknowledge it) unreachable, since `gate` requires stage `verified` and this
# was what stood between the chunk and that stage.
d="$(new_fixture case15)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; commit_all "$d" "implement the feature"
expect "15 commit before review gate: verify passes, stage verified" 0 "stage=verified" -- chunk_check "$d" verify
assert_eq "15 commit before review gate: gates.review recorded as premature" "$(state_get "$d" .gates.review)" "premature"

# 15b — gate approved refuses a premature chunk without an acknowledgment note
d="$(new_fixture case15b)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; commit_all "$d" "implement the feature"
quiet_check "$d" verify
log_and_gate "$d"
expect "15b gate approved without a note: refused" 1 "requires a note acknowledging" -- chunk_check "$d" gate approved
assert_eq "15b gate approved without a note: stage stays verified" "$(state_get "$d" .stage)" "verified"

# 15c — the note is what lets a premature commit close the chunk
d="$(new_fixture case15c)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; commit_all "$d" "implement the feature"
quiet_check "$d" verify
log_and_gate "$d"
expect "15c gate approved with a note: stage done" 0 "stage=done" -- chunk_check "$d" gate approved "reviewed the bundled commit by hand"
assert_eq "15c gate approved with a note: gates.review ends approved" "$(state_get "$d" .gates.review)" "approved"

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

# 20 — an unfilled predictions.md is not a plan gate. Standard chunks only
#      since 2026-07-31: blind predictions were softened to `standard` after
#      field-log entries 07–12 showed the blanks degrading on smaller chunks.
#      The fixture pins the size explicitly — the suite default is `small`, so
#      relying on it here would assert the softened path and read as coverage
#      of the strict one.
d="$(new_fixture case20 "bash tests/chunk/oracle.sh" tracked standard)"
write_predictions "$d" '___' '___'
quiet_check "$d" readiness
expect "20 unfilled predictions.md: freeze refused" 1 "unfilled blanks" -- chunk_check "$d" freeze

# 20b — the softened path: a `small` chunk freezes with the prediction blanks
#       unfilled, but the verdict lines are still parsed and still mandatory.
#       Three assertions on separate fixtures so each refusal is its own
#       evidence: blanks tolerated (small), verdict still required (small),
#       and the tolerance is a warn the operator can see.
d="$(new_fixture case20b)"
printf '%s\n' '- Expected approach: ___' '- Expected files touched: ___' \
  'Verdict: approve' 'Adjusted: n' > "$d/$CHUNK/predictions.md"
quiet_check "$d" readiness
expect "20b small chunk, blanks unfilled, verdict recorded: freeze passes" 0 "tolerated below 'standard'" -- chunk_check "$d" freeze

d="$(new_fixture case20c)"
printf '%s\n' '- Expected approach: ___' 'Adjusted: n' > "$d/$CHUNK/predictions.md"
quiet_check "$d" readiness
expect "20c small chunk, blanks tolerated but no Verdict: freeze refused" 1 "no 'Verdict:' line" -- chunk_check "$d" freeze

# 21 — the whole claim of untracked-artifacts mode: the backstop does not care
#      whether the chunk docs are committed. Every guarantee is pinned to
#      test_paths and to commit SHAs, neither of which the docs participate in.
#      The two asserts below come FIRST because without them this case could
#      pass while the fixture quietly tracked the docs anyway, proving nothing.
d="$(new_fixture case21 'bash tests/chunk/oracle.sh' untracked)"
assert_eq "21 untracked docs: nothing under docs/chunks is tracked" "$(tracked_count "$d" docs/chunks)" "0"
# The literal is new_fixture's oracle-script count, so it moves whenever a case
# needs a new oracle dialect (6 -> 7 on 2026-08-07, adding allpass.sh). Left as
# a literal deliberately: it went red the moment the count changed, which is the
# assertion working. Deriving it from the directory would make it pass at 0 too.
assert_eq "21 untracked docs: the oracle itself is still tracked"   "$(tracked_count "$d" tests/chunk)" "7"
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
# Compared against the shipped template rather than a literal, so this also pins
# the two in step: a script that migrates to a version the template does not
# stamp would make every freshly stamped chunk warn on its first write.
assert_eq "25 older schema: version migrated to the version the template ships" \
  "$(state_get "$d" .schema_version)" "$(jq -r .schema_version "$TEMPLATES/state.json")"
# has(), NOT `| type == "null"`. jq answers `null` for a key that is absent and
# for a key that is present and null, so the type form cannot tell "materialised"
# from "never written" — it passes either way. Every assertion here was that
# shape until a 2026-07-29 mutation trial deleted the bypass_suite migration and
# the suite stayed green. The materialisation is the whole point of this case:
# an un-materialised key leaves the older-schema warning firing forever, which
# is the nagging this migration exists to stop.
for k in artifacts field_log size_class_corrected bypass_base bypass_shipped bypass_suite predict; do
  assert_eq "25 older schema: $k key materialised" "$(state_get "$d" "has(\"$k\")")" "true"
  assert_eq "25 older schema: $k materialised as null" "$(state_get "$d" ".$k")" "null"
done
assert_eq "25 older schema: segment key renamed to chunk" "$(state_get "$d" .chunk)" "01-x"
assert_eq "25 older schema: the old key is really gone"   "$(state_get "$d" 'has("segment")')" "false"

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

# 26b — the same refusal one tier down, where it used to disappear. Every test
#       that reported reported PASSED and the run still exited non-zero, so no
#       FAILED/ERROR id parses — and the PASSED scan sat INSIDE the branch that
#       captures those ids, exactly where the collection-ERROR check sat until
#       2026-08-04. That fix hoisted the ERROR scan and left this one behind:
#       the run where nothing asserts anything was the one run the flagship
#       refusal never inspected. A live probe froze such an oracle at
#       stage=approved (2026-08-05 audit, F1). Case 26 cannot reach the shape —
#       birth.sh always leaves a FAILED id to parse.
d="$(new_fixture case26b 'bash tests/chunk/allpass.sh')"
quiet_check "$d" readiness
out="$(chunk_check "$d" freeze 2>&1)"; rc=$?
assert_eq       "26b all-PASSED red-exit run: freeze fails"  "$rc" "1"
assert_contains "26b and names the green-at-birth tests"     "$out" "green-at-birth tests"
# Matched with the refusal's own 8-space indent, not bare. The oracle echoes
# "PASSED tests/chunk/t.py::test_b" into the same captured output, so the bare
# node-id is present whether or not the check fires — the assertion passed on
# the unfixed script when it was written that way.
assert_contains "26b naming the ones no red id accompanied" \
  "$out" "        tests/chunk/t.py::test_b"
# And the WARN was false in this shape: it reported "no per-test node-ids" with
# two of them in the output, because it spoke to the absence of RED ids while
# claiming the absence of any. The exit-code tier is a real tier; announcing it
# over parsed ids misdescribes the evidence at the moment it is pinned.
assert_absent   "26b the no-node-ids warning does not fire when ids are present" \
  "$out" "no per-test node-ids"
assert_eq       "26b the oracle is not pinned" "$(state_get "$d" .stage)" "ready"

# 27 — red for the wrong reason: collection or fixture failure, no test ran.
d="$(new_fixture case27 'bash tests/chunk/collect.sh')"
quiet_check "$d" readiness
expect "27 collection ERROR in the red run: freeze fails" 1 "red for the wrong reason" -- chunk_check "$d" freeze

# 27b — the discriminator. An ERROR-level LOG record shares the '^ERROR' prefix
#       with a collection error and is not one: code under test logging at
#       ERROR is normal, and is sometimes the behaviour the oracle asserts.
#       Matching bare '^ERROR' refused a correctly-red oracle for it
#       (2026-08-04, supply-chain-ops-assistant 02-adjust-inventory-action).
d="$(new_fixture case27b 'bash tests/chunk/logerror.sh')"
quiet_check "$d" readiness
out="$(chunk_check "$d" freeze 2>&1)"; rc=$?
assert_eq "27b red run carrying an ERROR log record: freeze passes" "$rc" "0"
assert_absent "27b the log record is not read as a collection error" "$out" "red for the wrong reason"

# 27c — and the narrowing must not overshoot. A module that fails to import is
#       reported against the file, with no node-id; that is still a collection
#       error. A discriminator keyed on '::' alone would wave it through.
d="$(new_fixture case27c 'bash tests/chunk/collectfile.sh')"
quiet_check "$d" readiness
expect "27c collection ERROR with no node-id: freeze still fails" 1 "red for the wrong reason" -- chunk_check "$d" freeze

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
# bypass_note is the entire record of a bypassed chunk, so an unquoted
# description silently truncated to its first word loses it. Asserted on state
# rather than on the printed line: the line no longer carries the description at
# all (37b/37c), and state is the stronger pin anyway — it compares the joined
# string whole instead of grepping for a substring of it.
d="$(new_fixture case37 'bash tests/chunk/oracle.sh' tracked trivial)"
expect    "37 bypass stamps from specified" 0 "stage=bypassed" -- chunk_check "$d" bypass rename the timeout constant
assert_eq "37 bypass keeps the whole description in state" "$(state_get "$d" .bypass_note)" "rename the timeout constant"
log_and_gate "$d" none
expect    "37 a bypassed chunk still exits through the review gate" 0 "stage=done" -- chunk_check "$d" gate approved

# 37b/37c — the printed line must leave `chafe:` UNANSWERED. It used to ship
#   with bypass_note pre-filled there: a plausible wrong value in the one field
#   that carries qualitative evidence, and unreachable by the placeholder scan
#   because that scan breaks at `chafe:` (chafe is free text and may contain
#   pipes). Both prior bypassed chunks corrected it by hand, which is the
#   failure mode, not the mitigation. Separate fixtures on purpose: `bypass` is
#   legal only from `specified`, so a second run against one fixture would be
#   refused and expect_absent would pass on an error message.
d="$(new_fixture case37b 'bash tests/chunk/oracle.sh' tracked trivial)"
expect        "37b bypass leaves chafe unanswered in the printed line" 0 "chafe: ?" -- \
  chunk_check "$d" bypass rename the timeout constant
d="$(new_fixture case37c 'bash tests/chunk/oracle.sh' tracked trivial)"
expect_absent "37c the work description never lands in chafe:" "chafe: rename the timeout constant" -- \
  chunk_check "$d" bypass rename the timeout constant

# 37d/37e — the trivial path's baseline evidence is EXECUTED, not remembered.
#   audit-readiness step 0 sends a trivial chunk straight here and used to print
#   `bash -c "<suite_cmd>"` for the operator to run, which is the shape this
#   skill refuses everywhere else. `bypass` runs it and records the exit code.
d="$(new_fixture case37d 'bash tests/chunk/oracle.sh' tracked trivial)"
expect    "37d bypass runs the suite before stamping" 0 "suite green — recorded as bypass_suite" -- \
  chunk_check "$d" bypass "rename the timeout constant"
assert_eq "37d the exit code is on disk, not in a retro" "$(state_get "$d" .bypass_suite.exit)" "0"
assert_eq "37d the command that produced it is on disk"  "$(state_get "$d" .bypass_suite.cmd)"  "true"

# 37e — recorded, NOT gated. A red baseline predates this chunk, and blocking a
#   two-minute change behind someone else's broken suite is the disproportion
#   non-negotiable #7 exists to prevent. It must warn loudly and stamp anyway.
d="$(new_fixture case37e 'bash tests/chunk/oracle.sh' tracked trivial)"
set_state "$d" '.suite_cmd = "exit 3"'
expect    "37e red baseline is warned about" 0 "suite RED (exit 3)" -- \
  chunk_check "$d" bypass "rename the timeout constant"
assert_eq "37e red baseline does not block the bypass" "$(state_get "$d" .stage)" "bypassed"
assert_eq "37e the red exit code is recorded"          "$(state_get "$d" .bypass_suite.exit)" "3"

# --- 38: the shipped templates, checked against their own checker -----------
# Every case above builds its fixture files programmatically, which means none
# of them had ever run chunk-check.sh against the documents a real user actually
# stamps. An end-to-end run found that templates/predictions.md explained the
# unfilled-blank rule by quoting the blank marker — so freeze rejected a fully
# filled gate, permanently, on the strength of its own instructions. These
# assertions pin the templates themselves.

# `standard` explicitly: since the 2026-07-31 softening the blanks only gate
# standard chunks, and this case is about the template's blanks, not its
# verdict line (an untouched template on a `small` chunk is still refused,
# but via the unrecognised verdict — case 20c's territory).
d="$(new_fixture case38 "bash tests/chunk/oracle.sh" tracked standard)"
cp "$TEMPLATES/predictions.md" "$d/$CHUNK/predictions.md"
expect "38 untouched template predictions.md: freeze refused" 1 "unfilled blanks" -- chunk_check "$d" freeze

# Fill it the way a human would — in two passes, because the two passes ARE the
# gate: top half first, stamped by `predict` while the verdict is still blank;
# verdict only after the plan is read. This also runs `predict` against the
# shipped template's real structure (the Disagreements section sits between the
# halves, and the top-half hash must stop before it).
sed -e 's/^- Expected approach: .*/- Expected approach: add the thing/' \
    -e 's/^- Expected files touched: .*/- Expected files touched: src\/base.txt/' \
    -e 's/^- Biggest risk: .*/- Biggest risk: none/' \
    "$TEMPLATES/predictions.md" > "$d/$CHUNK/predictions.md"
quiet_check "$d" readiness
expect "38 top half filled on the shipped template: predict stamps it" 0 "top half stamped" -- chunk_check "$d" predict
sed -e 's/^Verdict: .*/Verdict: approve/' \
    -e 's/^Adjusted: .*/Adjusted: n/' \
    "$d/$CHUNK/predictions.md" > "$FIXROOT/pred.tmp" && mv "$FIXROOT/pred.tmp" "$d/$CHUNK/predictions.md"
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

# 44b/44c — `chafe:` is the one qualitative field in the entry, and it sat
#      inside the scan's `break` where nothing could see it. The break itself is
#      correct (chafe is free text and may contain pipes, whose fragments would
#      match the placeholder pattern), so the field needs its own check on the
#      WHOLE value. 44c is the over-matching guard: a real chafe sentence that
#      ends in a question mark is an answer, not a placeholder.
d="$(new_fixture case44b 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" bypass "rename the timeout constant"
fl_bypass() { # fl_bypass <chafe-text>
  printf '2026-07-28 | %s | 01-x | gate:none | oracle-caught:n/a | freeze-trip:n/a | scope-dev:n | bypass:y | ceremony-ok:y | closed:pending | context:none | chafe: %s' \
    "$(basename "$d")" "$1"
}
write_field_log "$d" "$(fl_bypass '?')"
expect "44b unanswered chafe: log refuses the line" 1 "unfilled placeholder" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"
write_field_log "$d" "2026-07-28 | $(basename "$d") | 01-x | gate:none | oracle-caught:n/a | freeze-trip:n/a | scope-dev:n | bypass:y | ceremony-ok:y | closed:pending | context:none | chafe:"
expect "44b empty chafe: log refuses the line too" 1 "unfilled placeholder" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"
write_field_log "$d" "$(fl_bypass 'why does readiness gate test_paths before it reaches the bypass rule?')"
expect "44c a chafe sentence ending in '?' is an answer, not a placeholder" 0 "field-log entry verified" -- \
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

# 45c/45d/45e — the gate: field has to agree with what the gate DID, not merely
#       be spelled legally. `freeze` refuses the verdict `adjust` ("apply it and
#       re-gate; freeze records approval only"), so `.gates.plan` can never hold
#       it and the adjustment survives only in `.gates.plan_adjusted`. An agent
#       transcribing `.gates.plan` — which is what audit-implementation.md used
#       to say to do — logs every adjusted gate as `approve`, and the demotion
#       rule reads this field: the human's catch would count TOWARD retiring the
#       gate that caught it. Earned 2026-07-29 (skill-engine
#       04-eval-corpus-split, retro candidate 4), where the rule and the
#       recording convention turned out to have been written from the same
#       analysis and implemented against different halves of it.
d="$(new_fixture case45c)"
quiet_check "$d" readiness; write_predictions "$d" approve y; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
# The fixture is only meaningful if it really is an adjusted gate — asserted, not
# assumed, because a case that passes for the wrong reason reads as coverage.
assert_eq "45c the fixture really is an adjusted gate" "$(state_get "$d" .gates.plan_adjusted)" "true"
assert_eq "45c and freeze recorded it as approve, not adjust" "$(state_get "$d" .gates.plan)" "approve"
write_field_log "$d" "$(log_line "$d" approve)"
expect    "45c adjusted gate logged as approve: log fails" 1 "counts a catch toward retiring the gate" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"
assert_eq "45c nothing was recorded" "$(state_get "$d" '.field_log == null')" "true"

# 45d — the correct spelling passes and records `adjust` even though
#       `.gates.plan` reads `approve`. Without this, 45c would also be satisfied
#       by a check that refused every gate: value it was handed.
write_field_log "$d" "$(log_line "$d" adjust)"
expect    "45d adjusted gate logged as adjust: log passes" 0 "field-log entry verified" -- \
  chunk_check "$d" log --log-path "$(field_log_path "$d")"
assert_eq "45d the streak-visible verdict is adjust" "$(state_get "$d" .field_log.gate)" "adjust"
assert_eq "45d while state.json still records what froze" "$(state_get "$d" .gates.plan)" "approve"

# 45e — the other half of the mapping. A bypassed chunk's `n/a` becomes `none`:
#       no gate happened, so it is logged for proportionality and excluded from
#       the streak. Case 47 pins that `none` passes; this pins that a line
#       claiming a gate DID happen is refused.
d="$(new_fixture case45e 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" bypass "rename the timeout constant"
write_field_log "$d" "$(log_line "$d" approve)"
expect "45e bypassed chunk logged as approve: log fails" 1 "the gate did something else" -- \
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

# --- 52-56: bypass --downgrade, the over-escalation correction ---------------
# Added 2026-07-29 after a chunk was escalated trivial -> small at readiness on
# "17 files, not 1-2" plus "an oracle is writable", ran the whole lifecycle on a
# `git add`, and had its oracle deleted at review as a tautology. `bypass` was
# illegal past `ready`, so the honest outcome -- work complete, ceremony was
# wrong -- had no state to land in and got recorded as `blocked`, which means
# unfinished. Note that case 52 pins the ORIGINAL stage guard, which no fixture
# had ever noticed: it was live and unpinned for the whole life of the script.

# 52 — the guard the correction path relaxes still holds without the flag.
d="$(new_fixture case52)"
quiet_check "$d" readiness; quiet_check "$d" freeze
set_state "$d" '.size_class = "trivial"'
expect "52 bypass past ready without --downgrade: refused" 1 "a frozen chunk cannot be bypassed" -- \
  chunk_check "$d" bypass "should have been trivial"

# 53 — with the flag, from a frozen chunk: allowed, and the correction is
#      recorded rather than papered over. The freeze evidence stays: it is the
#      receipt for what the over-escalation cost.
d="$(new_fixture case53)"
quiet_check "$d" readiness; quiet_check "$d" freeze
pinned_before="$(state_get "$d" '.test_hashes | length')"
expect    "53 bypass --downgrade from approved: allowed" 0 "small -> trivial" -- \
  chunk_check "$d" bypass --downgrade "escalated by mistake; the oracle was a tautology"
assert_eq "53 size_class is corrected"        "$(state_get "$d" .size_class)" "trivial"
assert_eq "53 the correction records its origin stage" "$(state_get "$d" .size_class_corrected.from_stage)" "approved"
assert_eq "53 the correction records the old class"    "$(state_get "$d" .size_class_corrected.from)" "small"
assert_eq "53 the whole reason survives, not its first word" \
  "$(state_get "$d" .size_class_corrected.reason)" "escalated by mistake; the oracle was a tautology"
assert_eq "53 freeze evidence is left in place" "$(state_get "$d" '.test_hashes | length')" "$pinned_before"
assert_eq "53 the correction path records baseline evidence too" "$(state_get "$d" .bypass_suite.exit)" "0"

# 54 — the demotion streak is entitled to a plan gate that really ran. A plain
#      bypass prints gate:none because no gate happened; this path must not.
d="$(new_fixture case54)"
quiet_check "$d" readiness; quiet_check "$d" freeze
expect "54 downgrade field-log line carries the real plan verdict" 0 "| gate:approve |" -- \
  chunk_check "$d" bypass --downgrade "escalated by mistake"
expect_absent "54 downgrade field-log line is not gate:none" "gate:none" -- \
  chunk_check "$d" status

# 55 — the flag is a correction, not a second spelling of bypass, and not a
#      way to re-open a closed chunk. 55a and 55b use SEPARATE fixtures on
#      purpose: the first mutation trial run against this case had both
#      assertions on one already-`trivial` fixture, so the already-trivial
#      refusal fired first and the stage guard could be deleted with the suite
#      staying green. A case that passes for the wrong reason is worse than a
#      missing one, because it reads as coverage.
d="$(new_fixture case55a 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" readiness
expect "55a --downgrade on an already-trivial chunk: refused" 1 "already 'trivial'" -- \
  chunk_check "$d" bypass --downgrade "nothing to correct"

# 55b — reaches `done` the long way, so size_class is still `small` and the
#       stage guard is the only thing that can refuse.
d="$(new_fixture case55b)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
log_and_gate "$d"; quiet_check "$d" gate approved
assert_eq "55b the fixture really reached done"        "$(state_get "$d" .stage)" "done"
assert_eq "55b and its size_class is still correctable" "$(state_get "$d" .size_class)" "small"
expect "55b --downgrade from done: refused" 1 "found 'done'" -- \
  chunk_check "$d" bypass --downgrade "too late"
expect "55b --downgrade on the wrong op: refused, not silently ignored" 2 "applies to 'bypass' only" -- \
  chunk_check "$d" verify --downgrade

# 55c — the `bypassed` arm of that guard is unreachable through the ops alone
#       (a bypassed chunk is already `trivial`, so the already-trivial refusal
#       would fire first), so the fixture forces the state a hand-edit or an
#       older script could leave behind. Pinning it is the point: an arm no
#       fixture can reach is an arm the next refactor deletes for free.
d="$(new_fixture case55c)"
quiet_check "$d" readiness
set_state "$d" '.stage = "bypassed"'
expect "55c --downgrade on an already-bypassed chunk: refused" 1 "found 'bypassed'" -- \
  chunk_check "$d" bypass --downgrade "already there"

# 56 — relaxing the stage guard must not relax the review gate. A downgraded
#      chunk skips `verify`; it does not skip the human, and `gate approved`
#      still re-reads the field log.
d="$(new_fixture case56)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
quiet_check "$d" bypass --downgrade "escalated by mistake"
expect "56 downgraded chunk without a field-log entry: gate refused" 1 "no field-log entry recorded" -- \
  chunk_check "$d" gate approved
log_and_gate "$d"
expect "56 downgraded chunk still exits through the review gate" 0 "stage=done" -- \
  chunk_check "$d" gate approved

# --- 57: verify is not the exit for a bypassed chunk -------------------------
# Added 2026-07-29. `verify` had no stage guard, so running it against a
# bypassed chunk ran the entire suite and then reported the *intended* state of
# the world — no frozen oracle — as a wall of failures. Observed on a chunk
# closed via `bypass --downgrade`, where the oracle had been deliberately
# deleted at review: 9 failures, 8 of them noise, one real. An op that reports
# correct states as failures trains the operator to skim its output.
d="$(new_fixture case57 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" readiness
quiet_check "$d" bypass "rename the timeout constant"
expect "57 verify against a bypassed chunk: refused as the wrong op" 2 "has no frozen oracle" -- \
  chunk_check "$d" verify
# rc 2 (die), not 1 (a failed check) — the distinction is the whole point, and
# it is what routes the operator to the gate instead of to a debugging session.
expect "57 and it names the op that does apply" 2 "gate" -- chunk_check "$d" verify
# The guard must not cost the suite run it exists to avoid.
expect_absent "57 refusal happens before the suite runs" "suite green" -- chunk_check "$d" verify

# 57b — the guard keys on bypass_note, not on stage. The first version keyed on
#       stage == "bypassed" and stopped working the moment the chunk passed its
#       gate: `bypassed` -> `done` is one op, and the `done` chunk still had no
#       oracle. This case is the one that caught it.
d="$(new_fixture case57b 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" readiness
quiet_check "$d" bypass "rename the timeout constant"
log_and_gate "$d" none; quiet_check "$d" gate approved
assert_eq "57b bypassed chunk reached done" "$(state_get "$d" .stage)" "done"
expect "57b verify still refused after a bypassed chunk closes" 2 "has no frozen oracle" -- \
  chunk_check "$d" verify

# 57c — and it must not catch a chunk that paid for the full lifecycle. At
#       `done` that chunk's oracle is real, so re-verifying means something.
d="$(new_fixture case57c)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify
log_and_gate "$d"; quiet_check "$d" gate approved
assert_eq "57c fixture reached done" "$(state_get "$d" .stage)" "done"
expect "57c verify from done is still legal" 0 "oracle unchanged since freeze" -- chunk_check "$d" verify

# 57d — a rebaseline genuinely restarts a bypassed chunk into the lifecycle, so
#       it must clear the marker. Otherwise the guard would refuse the very op
#       the rebaseline exists to re-enable — a one-way door out of `bypass`.
d="$(new_fixture case57d 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" readiness
quiet_check "$d" bypass "turned out to be bigger than it looked"
quiet_check "$d" readiness --rebaseline
assert_eq "57d rebaseline clears the bypass marker" "$(state_get "$d" .bypass_note)" "null"
quiet_check "$d" freeze
expect "57d and verify applies again" 1 "the frozen oracle is red at verify" -- chunk_check "$d" verify

# --- 58: the gate hands off to the next session ------------------------------
# Added 2026-07-29, raised by a maintainer at a closing gate. `done` is terminal
# for the chunk and used to be a dead end for the session: the gate said "the
# human commits from here" and stopped. Everything needed to resume — which
# chunk is next, what to load first — had to be re-derived from feature.md or
# recomposed from memory. In a skill whose non-negotiable #3 is that an answer
# living in chat scrollback does not exist next session, this was the one
# transition that handed off nothing.

# A sibling chunk's directory is deliberately OUT of a chunk's declared scope —
# one chunk, one diff, one review (see path_allowed's two-segment case arm). So
# a queue has to exist at the baseline, not appear mid-chunk, or `verify` counts
# it as scope creep and never reaches `verified`. The first draft of 58a got
# this wrong and 58d passed anyway, for the wrong reason: the gate had already
# failed, so "no next chunk in the output" was trivially true. Hence the
# stage assertion in every case below before the handoff is asserted at all.

# 58a — names the next chunk and emits a pasteable resume prompt.
d="$(new_fixture case58a)"
add_sibling "$d" "02-y" specified
commit_all "$d" "queue"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify; log_and_gate "$d"
assert_eq "58a fixture reached verified before the gate" "$(state_get "$d" .stage)" "verified"
out="$(chunk_check "$d" gate approved 2>&1)"
assert_contains "58a gate names the next chunk and its stage" "$out" "next chunk: 02-y (stage: specified)"
assert_contains "58a and emits a resume prompt, not just a name"  "$out" "/feature-chunker Repo:"
assert_contains "58a which points at the feature file"           "$out" "docs/chunks/f/feature.md"
assert_contains "58a and at the retro this chunk just wrote"     "$out" "docs/chunks/f/01-x/retro.md"
# The handoff is an addition, not a replacement: the commit prohibition is the
# other thing this gate has to say, and it must survive.
assert_contains "58a the commit prohibition still prints"        "$out" "the harness still does not"

# 58b — no unfinished chunk DIRECTORY is not the same as an empty queue, and the
#       message must not claim otherwise. Chunk dirs are stamped as each chunk
#       comes up, so a 24-row queue can have two directories on disk. The first
#       version of this said "the feature queue is clear" and was caught the
#       first time it ran against a real feature with 22 unstamped chunks — the
#       fixtures agreed with the bug because every fixture chunk is stamped.
#       A confidently wrong pointer is worse than silence.
d="$(new_fixture case58b)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify; log_and_gate "$d"
assert_eq "58b fixture reached verified before the gate" "$(state_get "$d" .stage)" "verified"
out="$(chunk_check "$d" gate approved 2>&1)"
assert_contains "58b no unfinished chunk dir is reported as such" "$out" "no unfinished chunk directory"
assert_contains "58b and points at the queue table for unstamped chunks" "$out" "feature.md"
assert_absent   "58b it never claims the queue is empty"          "$out" "queue is clear"
assert_absent   "58b and emits no resume prompt"                  "$out" "/feature-chunker Repo:"

# 58b2 — and it names the feature-close the feature now owes. That stage was
#        prose, optional by omission, and the only thing that caught anything on
#        the feature that earned this rule: two instrumented gates, 78 oracle
#        assertions and a 295-test suite found none of seven correctness defects
#        one independent reviewer found in a single pass (2026-08-04,
#        supply-chain-ops-assistant). This is the last moment anything prints
#        about the feature, so it is the only place its absence can be named.
assert_contains "58b2 the owed feature-close is named at the last chunk's gate" \
  "$out" "owes a feature-close"
assert_contains "58b2 and says who may do it"     "$out" "did not write the chunks"
assert_contains "58b2 and ties it to closed:pending" "$out" "closed:pending"
assert_contains "58b2 and admits nothing checks it"  "$out" "Nothing checks this"

# The line must NOT appear when there is a next chunk: a feature mid-queue owes
# no close, and a reminder that fires every chunk is a reminder nobody reads.
#        The sibling is stamped after verify on purpose: a chunk directory
#        appearing mid-flight is out of declared scope and verify refuses it
#        (case 32), so stamping it earlier would never reach the gate at all.
d="$(new_fixture case58b2)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify; log_and_gate "$d"
mkdir -p "$d/docs/chunks/f/02-y"
printf '{"schema_version":10,"chunk":"02-y","stage":"specified"}\n' > "$d/docs/chunks/f/02-y/state.json"
out="$(chunk_check "$d" gate approved 2>&1)"
assert_contains "58b2 a mid-queue gate still names the next chunk" "$out" "next chunk: 02-y"
assert_absent   "58b2 and does not ask for a feature-close yet"    "$out" "owes a feature-close"

# 58c — skips chunks already closed. Glob order is lexicographic and the queue
#       is numbered, so "first non-done sibling" is the next one to work on.
d="$(new_fixture case58c)"
add_sibling "$d" "02-y" "done"   # quoted: bare `done` reads as the loop keyword (SC1010)
add_sibling "$d" "03-z" specified
commit_all "$d" "queue"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify; log_and_gate "$d"
assert_eq "58c fixture reached verified before the gate" "$(state_get "$d" .stage)" "verified"
out="$(chunk_check "$d" gate approved 2>&1)"
assert_contains "58c skips a done sibling"          "$out" "next chunk: 03-z"
assert_absent   "58c and does not offer the done one" "$out" "next chunk: 02-y"

# 58d — only `approved` hands off. changes-requested and rejected mean the chunk
#       is still live, and pointing at the next one would be telling the operator
#       to walk away from work that just came back to them.
d="$(new_fixture case58d)"
add_sibling "$d" "02-y" specified
commit_all "$d" "queue"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify; log_and_gate "$d"
assert_eq "58d fixture reached verified before the gate" "$(state_get "$d" .stage)" "verified"
out="$(chunk_check "$d" gate changes-requested 2>&1)"
# Assert the gate SUCCEEDED first. Without this the absence assertion below is
# satisfied by any failure that stops the gate before the handoff — which is
# exactly how the first draft of this case passed while 58a was broken.
assert_contains "58d changes-requested is recorded"    "$out" "stage=approved"
assert_absent   "58d changes-requested does not hand off" "$out" "next chunk:"

# --- 59: what a bypassed chunk shipped ---------------------------------------
# Same session, same root cause. A bypassed chunk has no `implement` op and never
# runs `verify`, so its work happens between `bypass` and `gate` and shows up in
# no transcript and no state field. `bypass_note` says what the work *would be*,
# in the future tense, and nothing reconciles it against what was done. The
# maintainer's question was literally "don't we have to implement this chunk?" —
# the work was on disk and approved, and nothing the harness printed said so.
#
# This is a record, not a check. It never fails the gate: the human has read the
# diff and the diff is the authority.

# 59a — baseline present: the delta since baseline is what shipped.
d="$(new_fixture case59a 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" readiness
quiet_check "$d" bypass "rename the timeout constant"
implement "$d"
log_and_gate "$d" none
out="$(chunk_check "$d" gate approved 2>&1)"
assert_contains "59a bypassed gate records the work that shipped" "$out" "src/feature.txt"
assert_contains "59a and names the baseline it measured from"     "$out" "shipped (baseline:"
assert_eq "59a the record is in state.json, not only on stdout" \
  "$(state_get "$d" '.bypass_shipped.paths | index("src/feature.txt") != null')" "true"
# Chunk docs are bookkeeping, never the work. state.json changes on every op, so
# without the filter it would top the list for exactly the chunks that shipped
# least.
assert_eq "59a chunk docs excluded from the shipped record" \
  "$(state_get "$d" '[.bypass_shipped.paths[] | select(startswith("docs/chunks/"))] | length')" "0"
assert_eq "59a status surfaces it" \
  "$(chunk_check "$d" status | grep -c 'shipped: .*src/feature.txt')" "1"

# 59b — neither anchor: the legacy shape, a chunk bypassed before bypass_base
#       existed. It must still record what it can see rather than nothing, so
#       the worktree arm stays reachable instead of becoming dead code.
d="$(new_fixture case59b 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" bypass "three lines in a settings file"
set_state "$d" '.bypass_base = null'    # as if bypassed by an older script
implement "$d"
log_and_gate "$d" none
assert_eq "59b fixture really has no baseline" "$(state_get "$d" .baseline_sha)" "null"
assert_eq "59b and no bypass anchor either"    "$(state_get "$d" .bypass_base)" "null"
out="$(chunk_check "$d" gate approved 2>&1)"
assert_contains "59b falls back to the worktree delta" "$out" "shipped (worktree)"
assert_contains "59b and still finds the work"         "$out" "src/feature.txt"

# 59c — a chunk that paid for the full lifecycle records nothing here. Its work
#       is already evidenced by oracle-red.log, oracle-green.log and verify's
#       scope check; a second, weaker record would be noise.
d="$(new_fixture case59c)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"; quiet_check "$d" verify; log_and_gate "$d"
quiet_check "$d" gate approved
assert_eq "59c non-bypassed chunk records no shipped set" \
  "$(state_get "$d" .bypass_shipped)" "null"

# 59d — it is a record, not a gate. A bypassed chunk with nothing to show still
#       closes; it warns instead of blocking, because the human already read the
#       diff and a record cannot overrule them.
d="$(new_fixture case59d 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" bypass "work that leaves no visible delta"
log_and_gate "$d" none
out="$(chunk_check "$d" gate approved 2>&1)"
assert_contains "59d empty shipped set warns"        "$out" "no changed paths visible at gate time"
assert_contains "59d but the gate still closes"      "$out" "stage=done"
assert_eq "59d and the chunk really is done" "$(state_get "$d" .stage)" "done"

# 59e — THE motivating case, and the one the first draft got wrong. The harness
#       does not commit; the human does, and that is the design's intended exit.
#       So the common shape is: bypass, do the work, human commits, then gate.
#       With only a worktree fallback that records nothing at all — the delta is
#       committed and the chunk never pinned a baseline (readiness hard-fails a
#       trivial chunk's empty test_paths). `bypass` therefore records HEAD as
#       bypass_base precisely so this op has an anchor. Found by running the
#       feature against the real chunk that motivated it, after the fixtures
#       were green: every fixture left its work uncommitted.
d="$(new_fixture case59e 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" bypass "three lines in a settings file"
assert_eq "59e bypass recorded an anchor to measure from" \
  "$(state_get "$d" '.bypass_base | length')" "40"
implement "$d"
commit_all "$d" "the human commits the bypassed work"
assert_eq "59e the work really is committed, worktree clean" \
  "$( cd "$d" && git status --porcelain | wc -l | tr -d ' ' )" "0"
log_and_gate "$d" none
out="$(chunk_check "$d" gate approved 2>&1)"
assert_contains "59e committed work is still recorded"   "$out" "src/feature.txt"
assert_contains "59e measured from the bypass anchor"    "$out" "shipped (bypass-base:"
assert_absent   "59e and does not warn about an empty set" "$out" "no changed paths visible"

# 59f — a rebaseline returns a bypassed chunk to the lifecycle, so the anchor
#       goes with the marker. Leaving it would have the next bypass measure from
#       a point two baselines back.
d="$(new_fixture case59f 'bash tests/chunk/oracle.sh' tracked trivial)"
quiet_check "$d" bypass "turned out to be bigger than it looked"
quiet_check "$d" readiness --rebaseline
assert_eq "59f rebaseline clears the bypass anchor too" "$(state_get "$d" .bypass_base)" "null"

# 60 — freeze runs suite_cmd once and records it, even when it's green. Control
#      case for 61: proves the field gets populated at all before 61 proves the
#      red case doesn't gate.
d="$(new_fixture case60)"
quiet_check "$d" readiness
quiet_check "$d" freeze
assert_eq "60 freeze records a green freeze_suite" "$(state_get "$d" '.freeze_suite.exit')" "0"
assert_eq "60 freeze_suite carries the suite_cmd string" \
  "$(state_get "$d" '.freeze_suite.cmd')" "true"

# 61 — THE motivating case (skill-engine chunks 14 and 15: a stray doc-path
#      reference and a dead shell variable, both baked into the frozen oracle's
#      own header/body, both lint-only breaks unrelated to any test assertion,
#      both invisible until implement's first full-suite run because freeze
#      only ever executed oracle_cmd — a narrow slice of suite_cmd). suite_cmd
#      here is green at readiness (baseline, before this chunk touched
#      anything) and red at freeze (something now on disk trips it) — the
#      exact shape of a lint break arriving with the files freeze is about to
#      hash-pin. freeze must still succeed: the probe records, it does not
#      gate, for the same proportionality reason bypass_suite doesn't gate.
d="$(new_fixture case61)"
set_state "$d" '.suite_cmd = "[ ! -f lint-marker.txt ]"'
quiet_check "$d" readiness
assert_eq "61 readiness reached ready on a clean baseline" "$(state_get "$d" .stage)" "ready"
printf 'tripped\n' > "$d/lint-marker.txt"
out="$(chunk_check "$d" freeze 2>&1)"; rc=$?
assert_eq "61 freeze still succeeds despite a red freeze_suite probe" "$rc" "0"
assert_contains "61 freeze prints the red suite as a WARN, not a FAIL" \
  "$out" "WARN  suite RED (exit 1) — recorded as freeze_suite, not gated"
assert_eq "61 freeze_suite.exit is recorded" "$(state_get "$d" '.freeze_suite.exit')" "1"
assert_eq "61 stage still reaches approved" "$(state_get "$d" .stage)" "approved"

# --- 62-66: the predict op — 'blind' as a checkable property ----------------
# THE motivating incident (skill-engine chunk 04, 2026-07-29): predictions.md
# was filled in one pass, verdict included, so the gate's outcome was recorded
# about a plan that did not yet exist. The unfilled-blank check and the
# verdict-vocabulary check both passed — they confirm the blanks are gone,
# which is not the property the gate needs. The property is ORDER, and
# `predict` is the mechanism that observes it: stamp the top half while the
# verdict is still blank; freeze verifies the stamped bytes never moved.

# 62 — the op itself: stage guard, the one-pass refusal, the blank refusal,
#      the stamp, and the re-stamp path
d="$(new_fixture case62 'bash tests/chunk/oracle.sh' tracked standard)"
expect "62 predict before readiness: refused" 1 "legal from stage 'ready'" -- chunk_check "$d" predict
quiet_check "$d" readiness
expect "62 one-pass predictions (verdict already filled): predict refused" 1 "already carries a verdict" -- chunk_check "$d" predict
printf '%s\n' '# gate' '' '- Expected approach: ___' '' 'Verdict: ___' 'Adjusted: ___' > "$d/$CHUNK/predictions.md"
expect "62 unfilled top half: predict refused" 1 "unfilled blanks" -- chunk_check "$d" predict
write_blind_predictions "$d"
expect "62 blind top half, no plan on disk: predict stamps it" 0 "blind by construction" -- chunk_check "$d" predict
assert_eq "62 stamp recorded with plan_present=false" "$(state_get "$d" '.predict.plan_present')" "false"
expect "62 re-predict while the plan is unread: replaced with a warning" 0 "replacing predict stamp" -- chunk_check "$d" predict
out="$(chunk_check "$d" status 2>&1)"
assert_contains "62 status prints the stamp" "$out" "predict:"
fill_verdict "$d" approve n
expect "62 stamped standard chunk: freeze passes, naming the blind tier" 0 "blind by construction" -- chunk_check "$d" freeze

# 63 — the stamp binds content: a top half rewritten after the stamp (i.e.
#      after the plan may have been read) is exactly what the stamp exists to
#      catch, so freeze refuses the hash mismatch
d="$(new_fixture case63 'bash tests/chunk/oracle.sh' tracked standard)"
quiet_check "$d" readiness
write_blind_predictions "$d"
quiet_check "$d" predict
printf '%s\n' \
  '# plan gate (predict-then-compare)' '' \
  '- Expected approach: entirely rewritten after reading the plan' \
  '- Expected files touched: src/feature.txt' \
  '- Biggest risk: none' '' \
  '## Verdict' '' 'Verdict: approve' 'Adjusted: n' \
  > "$d/$CHUNK/predictions.md"
expect "63 top half rewritten after the stamp: freeze refused" 1 "changed after the predict stamp" -- chunk_check "$d" freeze

# 64 — the closed hole, demonstrated on its original shape: fixture predictions
#      are fully filled in one pass, verdict included, and no predict ever ran.
#      On a standard chunk that used to sail through; now it cannot.
d="$(new_fixture case64 'bash tests/chunk/oracle.sh' tracked standard)"
quiet_check "$d" readiness
expect "64 standard chunk, one-pass predictions, no stamp: freeze refused" 1 "no predict stamp" -- chunk_check "$d" freeze
# The softening survives: below `standard` the stamp is optional, and the
# refusal above must not leak down a size class.
d="$(new_fixture case64b)"
quiet_check "$d" readiness
expect "64b small chunk, no stamp: freeze passes, stamp optional" 0 "optional below 'standard'" -- chunk_check "$d" freeze

# 65 — a stamp that exists is held to at every size: `small` relaxes whether
#      you must predict, never whether a recorded prediction is honest
d="$(new_fixture case65)"
quiet_check "$d" readiness
write_blind_predictions "$d"
quiet_check "$d" predict
printf '%s\n' \
  '# plan gate (predict-then-compare)' '' \
  '- Expected approach: entirely rewritten after reading the plan' \
  '- Expected files touched: src/feature.txt' \
  '- Biggest risk: none' '' \
  '## Verdict' '' 'Verdict: approve' 'Adjusted: n' \
  > "$d/$CHUNK/predictions.md"
expect "65 small chunk, stamped then edited: freeze refused" 1 "changed after the predict stamp" -- chunk_check "$d" freeze

# 66 — draft-ahead: a plan.md already on disk at stamp time is recorded and
#      reported, never refused — the design predates draft-ahead, and mtimes
#      prove nothing a checkout can't fake. Absence-at-stamp + presence-at-
#      freeze is the provable tier; presence-at-stamp is the honest record of
#      the weaker one.
d="$(new_fixture case66 'bash tests/chunk/oracle.sh' tracked standard)"
quiet_check "$d" readiness
write_blind_predictions "$d"
printf 'draft plan\n' > "$d/$CHUNK/plan.md"
out="$(chunk_check "$d" predict 2>&1)"; rc=$?
assert_eq "66 predict with a drafted plan on disk: still legal" "$rc" "0"
assert_contains "66 the draft's presence is recorded, not ignored" "$out" "plan.md already on disk"
assert_eq "66 plan_present recorded true" "$(state_get "$d" '.predict.plan_present')" "true"
fill_verdict "$d" approve n
expect "66 freeze names the draft-ahead tier, not blind-by-construction" 0 "withheld" -- chunk_check "$d" freeze
quiet_check "$d" readiness --rebaseline
assert_eq "66 rebaseline clears the predict stamp with the rest of the gate" "$(state_get "$d" '.predict')" "null"

# --- 68: the one-pass recovery (--one-pass) ---------------------------------
# Case 62 pins the refusal. This pins what the operator is left holding after
# it. The only route back to a stamp used to be: blank the verdict, stamp,
# restore it — byte-identical to laundering a prediction written AFTER the plan
# was read, and taken on trust with nothing recorded. So the refusal
# manufactured, as its own recovery, the act it exists to prevent. --one-pass
# stamps the file as it stands and records the weaker claim instead.
# Earned twice on supply-chain-ops-assistant, 2026-08-04 (chunks 01 and 02).

# 68a — the flag is scoped to its op, like --downgrade. A typo landing it
#       elsewhere must not read as "accepted and had no effect".
d="$(new_fixture case68a 'bash tests/chunk/oracle.sh' tracked standard)"
expect "68a --one-pass on another op: refused" 2 "applies to 'predict' only" -- chunk_check "$d" readiness --one-pass

# 68b — refused when the strong path was free. This is what keeps the flag from
#       becoming the habitual invocation (the --refreeze principle: keep the
#       honest case available and the quiet one out of reach).
d="$(new_fixture case68b 'bash tests/chunk/oracle.sh' tracked standard)"
quiet_check "$d" readiness
write_blind_predictions "$d"
expect "68b --one-pass with the verdict still blank: refused" 1 "the strong path is" -- chunk_check "$d" predict --one-pass
assert_eq "68b nothing stamped on the refusal" "$(state_get "$d" '.predict')" "null"

# 68c — the recovery itself, on the shape that motivated it: a file filled in
#       one pass, verdict included, which plain predict refuses.
d="$(new_fixture case68c 'bash tests/chunk/oracle.sh' tracked standard)"
quiet_check "$d" readiness
write_predictions "$d" approve n
expect "68c plain predict still refuses the one-pass fill" 1 "already carries a verdict" -- chunk_check "$d" predict
expect "68c the refusal names the flag, not blank-and-restamp" 1 "Re-run with --one-pass" -- chunk_check "$d" predict
expect "68c the refusal names blanking as the thing NOT to do" 1 "do NOT blank the verdict and restamp" -- chunk_check "$d" predict
out="$(chunk_check "$d" predict --one-pass 2>&1)"; rc=$?
assert_eq "68c --one-pass stamps it" "$rc" "0"
assert_contains "68c the weaker claim is stated at stamp time" "$out" "ATTESTED by the operator, not observed"
assert_eq "68c one_pass recorded true" "$(state_get "$d" '.predict.one_pass')" "true"
assert_eq "68c the verdict that was sitting there is recorded" "$(state_get "$d" '.predict.verdict_at_stamp')" "approve"
out="$(chunk_check "$d" status 2>&1)"
assert_contains "68c status flags the attested tier" "$out" "ONE-PASS (attested, not observed)"
expect "68c freeze accepts the stamp" 0 "attested tier (one-pass)" -- chunk_check "$d" freeze --refreeze
expect "68c freeze names the tier loudly rather than passing quietly" 0 "not observed here" -- chunk_check "$d" freeze --refreeze

# 68d — the flag drops the ORDERING claim and nothing else. Everything the
#       stamp did prove, it still proves: a top half edited after a one-pass
#       stamp is refused exactly as case 63 refuses it on the strong path. If
#       this ever passes, --one-pass has become "skip the gate".
d="$(new_fixture case68d 'bash tests/chunk/oracle.sh' tracked standard)"
quiet_check "$d" readiness
write_predictions "$d" approve n
quiet_check "$d" predict --one-pass
printf '%s\n' \
  '# plan gate (predict-then-compare)' '' \
  '- Expected approach: entirely rewritten after reading the plan' \
  '- Expected files touched: src/feature.txt' \
  '- Biggest risk: none' '' \
  '## Verdict' '' 'Verdict: approve' 'Adjusted: n' \
  > "$d/$CHUNK/predictions.md"
expect "68d one-pass stamp still binds the top half" 1 "changed after the predict stamp" -- chunk_check "$d" freeze

# 68e — the strong path keeps its own tier. A one_pass flag that leaked onto an
#       ordinary stamp would quietly downgrade every honest gate, and the tier
#       lines are the only place the difference is visible.
d="$(new_fixture case68e 'bash tests/chunk/oracle.sh' tracked standard)"
quiet_check "$d" readiness
write_blind_predictions "$d"
quiet_check "$d" predict
assert_eq "68e ordinary stamp records one_pass=false" "$(state_get "$d" '.predict.one_pass')" "false"
assert_eq "68e ordinary stamp records no verdict" "$(state_get "$d" '.predict.verdict_at_stamp')" "null"
fill_verdict "$d" approve n
expect_absent "68e ordinary stamp is not reported as attested" "attested tier" -- chunk_check "$d" freeze
out="$(chunk_check "$d" status 2>&1)"
assert_absent "68e status does not flag an ordinary stamp" "$out" "ONE-PASS"

# 67 — `log` computes the demotion streak from the entries themselves. The
#      live log's hand-maintained header count went stale within days — a
#      manual counter feeding the one mechanism that adapts ceremony downward
#      from data. The log stays the data; the script does the arithmetic.
#      gate:none is excluded but does not break the run; adjust and reject
#      both reset it; approve and auto-pass extend it — but only once the
#      chunk has survived a feature-close (see 67b).
d="$(new_fixture case67)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
quiet_check "$d" verify
fl="$(field_log_path "$d")"
write_field_log "$d" \
  "$(log_line "$d" approve   00-a y clean)" \
  "$(log_line "$d" adjust    00-b y clean)" \
  "$(log_line "$d" approve   00-c y clean)" \
  "$(log_line "$d" none      00-d y clean)" \
  "$(log_line "$d" auto-pass 00-e y clean)" \
  "$(log_line "$d" approve   01-x y clean)"
out="$(chunk_check "$d" log --log-path "$fl" 2>&1)"; rc=$?
assert_eq "67 log passes with the entry present" "$rc" "0"
assert_contains "67 streak computed: adjust resets it, none is excluded" "$out" "demotion streak: 3"
write_field_log "$d" \
  "$(log_line "$d" approve 00-a y clean)" \
  "$(log_line "$d" reject  00-b y clean)" \
  "$(log_line "$d" approve 01-x y clean)"
out="$(chunk_check "$d" log --log-path "$fl" 2>&1)"
assert_contains "67 reject resets the streak too" "$out" "demotion streak: 1"

# 67b — the streak counts SHIPPED quality, not gate verdicts. It used to count
#       a chunk the moment its gate was recorded, which is before anyone but
#       the author has read the code — so the 20th consecutive "clean" gated
#       chunk was one that shipped two regressions, and it was that chunk that
#       made the demotion rule eligible to fire (2026-08-04,
#       supply-chain-ops-assistant). Only closed:clean extends it now.
write_field_log "$d" \
  "$(log_line "$d" approve 00-a y clean)" \
  "$(log_line "$d" approve 00-b y clean)" \
  "$(log_line "$d" approve 01-x y clean)"
out="$(chunk_check "$d" log --log-path "$fl" 2>&1)"
assert_contains "67b three closed-clean chunks: streak 3" "$out" "demotion streak: 3"

write_field_log "$d" \
  "$(log_line "$d" approve 00-a y clean)" \
  "$(log_line "$d" approve 00-b y 'defects(2)')" \
  "$(log_line "$d" approve 01-x y clean)"
out="$(chunk_check "$d" log --log-path "$fl" 2>&1)"
assert_contains "67b a chunk that shipped defects resets it, gate notwithstanding" \
  "$out" "demotion streak: 1"

# pending is an UNKNOWN outcome, not a catch: it neither extends nor resets.
# The streak recomputes from the file each run, so a pending entry that later
# becomes defects(N) resets it retroactively and correctly.
write_field_log "$d" \
  "$(log_line "$d" approve 00-a y clean)" \
  "$(log_line "$d" approve 00-b y pending)" \
  "$(log_line "$d" approve 01-x y clean)"
out="$(chunk_check "$d" log --log-path "$fl" 2>&1)"
assert_contains "67b pending neither extends nor resets" "$out" "demotion streak: 2"

# Entries predating the field are unknown for the same reason, so a log that
# has never been closed reads 0 rather than reading as a long clean run.
write_field_log "$d" \
  "2026-07-28 | $(basename "$d") | 00-a | gate:approve | oracle-caught:n(0) | freeze-trip:n | scope-dev:n | bypass:n | ceremony-ok:y | context:none | chafe: none" \
  "$(log_line "$d" approve 01-x y pending)"
out="$(chunk_check "$d" log --log-path "$fl" 2>&1)"
assert_contains "67b an entry with no closed: field does not extend the streak" \
  "$out" "demotion streak: 0"

# 67c — `log` requires the field, written as pending. Optional-by-omission is
#       how the old streak came to count chunks nobody had reviewed.
write_field_log "$d" \
  "2026-07-28 | $(basename "$d") | 01-x | gate:approve | oracle-caught:n(0) | freeze-trip:n | scope-dev:n | bypass:n | ceremony-ok:y | context:none | chafe: none"
expect "67c an entry with no closed: field is refused" 1 "no closed: field" -- \
  chunk_check "$d" log --log-path "$fl"
write_field_log "$d" "$(log_line "$d" approve 01-x y 'sort of')"
expect "67c an illegal closed: value is refused" 1 "illegal closed: value" -- \
  chunk_check "$d" log --log-path "$fl"
write_field_log "$d" "$(log_line "$d" approve 01-x y pending)"
expect "67c closed:pending is a legal answer at log time" 0 "closed:pending" -- \
  chunk_check "$d" log --log-path "$fl"

# 69 — the candidates ledger's escalation rule, read rather than remembered.
#      CANDIDATES.md says "second incident in a class -> mechanism, in that
#      session" and had no reader: an entry sat open at three sightings,
#      annotated overdue, while its class shipped two regressions two days
#      later (2026-08-04, supply-chain-ops-assistant). `log` now prints the
#      entries that have reached the threshold. It warns and never fails —
#      a maintainer's backlog must not block someone else's chunk.
d="$(new_fixture case69)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
quiet_check "$d" verify
write_field_log "$d" "$(log_line "$d" approve 01-x)"
fl="$(field_log_path "$d")"

ledger="$FIXROOT/case69-overdue.md"
printf '%s\n' \
  '## Open' \
  '' \
  '### Cross-chunk caller sweep' \
  '' \
  'Status: open · Occurrences: 3 · Last: 2026-08-02 skill-engine 21-eval-runs' \
  '' \
  'prose about the class.' \
  '' \
  '### Something seen once' \
  '' \
  'Status: open · Occurrences: 1 · Last: 2026-07-30 skill-engine 05-repo-claude-md' \
  '' \
  'prose.' > "$ledger"
out="$(chunk_check_cand "$d" "$ledger" log --log-path "$fl" 2>&1)"; rc=$?
assert_eq "69 an overdue candidate does not fail the op" "$rc" "0"
assert_contains "69 the overdue entry is named"        "$out" "Cross-chunk caller sweep"
assert_contains "69 with its sighting count"           "$out" "(3 sightings)"
assert_contains "69 said to be about the skill, not this repo" "$out" "not in this repo"
assert_absent   "69 an entry seen once is below the threshold" "$out" "Something seen once"

ledger="$FIXROOT/case69-quiet.md"
printf '%s\n' \
  '## Open' \
  '' \
  '### Seen once' \
  '' \
  'Status: open · Occurrences: 1 · Last: 2026-07-30 skill-engine 05-repo-claude-md' \
  '' \
  '## Landed' \
  '' \
  '### Already built' \
  '' \
  'Status: landed · Occurrences: 4 · Last: 2026-08-03 skill-engine 24-dogfood' > "$ledger"
out="$(chunk_check_cand "$d" "$ledger" log --log-path "$fl" 2>&1)"
assert_absent "69 nothing overdue: no warning at all" "$out" "escalation rule"
assert_absent "69 a landed entry never warns, whatever its count" "$out" "Already built"

out="$(chunk_check_cand "$d" "$FIXROOT/case69-absent.md" log --log-path "$fl" 2>&1)"; rc=$?
assert_eq     "69 a missing ledger is silent, not an error" "$rc" "0"
assert_absent "69 and prints no escalation warning"         "$out" "escalation rule"

# 69b — the DEFAULT resolution, which is the branch that actually shipped
#       broken. Every assertion above overrides CHUNK_CHECK_CANDIDATES, so the
#       SKILL_ROOT branch — the one every real install takes — had no case at
#       all, and this suite runs from the repo, where the ledger is always
#       present. That is how a documented install command excluding
#       CANDIDATES.md disabled the escalation warning in every install made from
#       it while the suite stayed green (2026-08-05 audit, F2). The script is
#       run here from a scratch skill root, the way an install runs it.
skill_root="$FIXROOT/skillroot"
mkdir -p "$skill_root/bin"
cp "$CHECK" "$skill_root/bin/chunk-check.sh"
printf '%s\n' \
  '## Open' \
  '' \
  '### Cross-chunk caller sweep' \
  '' \
  'Status: open · Occurrences: 3 · Last: 2026-08-02 skill-engine 21-eval-runs' \
  > "$skill_root/CANDIDATES.md"

d="$(new_fixture case69b)"
quiet_check "$d" readiness; quiet_check "$d" freeze
implement "$d"
quiet_check "$d" verify
write_field_log "$d" "$(log_line "$d" approve 01-x)"
fl="$(field_log_path "$d")"

# The `unset` is the point of the case, not housekeeping: with the variable
# inherited from the operator's environment this would quietly re-test the
# override that case 69 already covers, and pass while proving nothing.
installed_log() { # installed_log — run `log` through the scratch skill root
  ( cd "$d" && unset CHUNK_CHECK_CANDIDATES
    bash "$skill_root/bin/chunk-check.sh" log "$CHUNK" --log-path "$fl" 2>&1 )
}

out="$(installed_log)"
assert_contains "69b the ledger resolves beside the installed script, no override" \
  "$out" "Cross-chunk caller sweep"
assert_contains "69b and it is the installed copy that was read" \
  "$out" "$skill_root/CANDIDATES.md"

# The other half of the finding, and the reason it stayed invisible for three
# days: an install that omits the ledger degrades in perfect silence. Asserting
# the silence is what makes the install checks in bin/test-docs.sh load-bearing
# — nothing else anywhere would notice the mechanism was gone.
rm -f "$skill_root/CANDIDATES.md"
out="$(installed_log)"; rc=$?
assert_eq     "69b an install missing the ledger still succeeds" "$rc" "0"
assert_absent "69b and says nothing about the mechanism it lost" "$out" "escalation rule"

# 70 — out-of-scope exclusions that assert facts about existing behaviour.
#      Non-negotiable #1 puts an oracle behind every acceptance criterion and
#      nothing behind an exclusion — which is where a wrong belief is most
#      expensive, because it decides what is never built. A spec excluded a
#      defect class as "inherits this from every existing action type; it is
#      pre-existing behaviour", which was false in the way that mattered
#      (2026-08-04, supply-chain-ops-assistant). The check demands the claim be
#      MARKED, not that it be true: cite a test, or write (unverified).
oos() { # oos <repo_dir> <line...> — give the fixture spec an Out of scope section
  local d="$1"; shift
  { printf '\n%s\n\n' '## Out of scope'; printf '%s\n' "$@"; } >> "$d/$CHUNK/spec.md"
}

d="$(new_fixture case70a)"
oos "$d" '- empty-changes proposals: `adjust_inventory` inherits this from every' \
         '  existing action type; it is pre-existing behaviour.'
expect "70a an unmarked claim about existing behaviour: readiness fails" \
  1 "asserts facts about existing behaviour" -- chunk_check "$d" readiness
expect "70a the offending exclusion is quoted back" \
  1 "empty-changes proposals" -- chunk_check "$d" readiness

# 70b — the one-word escape hatch. The check cannot know whether a claim is
#       true; it can insist the author says which.
d="$(new_fixture case70b)"
oos "$d" '- empty-changes proposals: inherited from every existing action type' \
         '  (unverified).'
expect_absent "70b (unverified) satisfies it" "asserts facts" -- chunk_check "$d" readiness

# 70c — a cited test satisfies it too, and is the stronger answer.
d="$(new_fixture case70c)"
oos "$d" '- empty-changes proposals: pre-existing behaviour, held by' \
         '  `tests/dispatch/test_empty_changes.py`.'
expect_absent "70c a backticked test citation satisfies it" "asserts facts" -- chunk_check "$d" readiness

# 70d — entries are bullets, not lines. A citation in the NEXT bullet must not
#       excuse the claim in this one, or the check reads a section top to bottom
#       and passes on any single citation anywhere in it.
d="$(new_fixture case70d)"
oos "$d" '- empty-changes proposals: pre-existing behaviour.' \
         '- batching, covered by `tests/queue/test_batch.py`.'
expect "70d a citation in a sibling bullet does not cover this one" \
  1 "asserts facts about existing behaviour" -- chunk_check "$d" readiness

# 70e — no section, and the untouched template placeholder, are both silent.
#       templates/spec.md ships '## Out of scope' with a <placeholder> body;
#       a check that fired on it would fail every chunk stamped from template.
d="$(new_fixture case70e)"
expect_absent "70e no Out of scope section: nothing to check" "asserts facts" -- chunk_check "$d" readiness
oos "$d" '<adjacent things this chunk deliberately does not do>'
expect_absent "70e the template placeholder is not a claim" "asserts facts" -- chunk_check "$d" readiness

# 70f — an HTML comment is guidance, not an exclusion. This is what lets
#       templates/spec.md document the rule inside the section the rule
#       governs. Without it the shipped template either trips its own check or
#       -- worse, and this is how it was first written -- quietly satisfies it
#       because the explanatory prose happens to contain the escape hatch it is
#       describing. Same class as skill-engine 19's self-matching grep.
#       The comment here deliberately carries a claim phrase and NEITHER escape
#       hatch. Written the obvious way -- quoting the rule, marker and all -- it
#       would satisfy the check whether or not comments are skipped, and pass
#       for the wrong reason. (It was written that way first; the delete-the-
#       check trial is what caught it.)
d="$(new_fixture case70f)"
oos "$d" '<!--' \
         'Reminder: an earlier draft claimed this was pre-existing behaviour.' \
         '-->' \
         '- rendering the SKU column; that is chunk 03.'
expect_absent "70f an HTML comment is not an exclusion" "asserts facts" -- chunk_check "$d" readiness
oos "$d" '- empty-changes proposals: pre-existing behaviour.'
expect "70f and skipping it does not swallow the entries after it" \
  1 "asserts facts about existing behaviour" -- chunk_check "$d" readiness

# 70g — the shipped template must pass its own check, whatever its guidance
#       says. Case 39 pins the fenced blocks; this pins the prose.
d="$(new_fixture case70g)"
cp "$TEMPLATES/spec.md" "$d/$CHUNK/spec.md"
expect_absent "70g the shipped template does not trip the out-of-scope check" \
  "asserts facts" -- chunk_check "$d" readiness

# --- summary ---------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
