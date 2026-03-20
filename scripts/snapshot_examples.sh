#!/usr/bin/env bash
set -euo pipefail

# Run example workflows locally with actrun and save step-status snapshots.
# Usage: bash scripts/snapshot_examples.sh [example...]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI_BIN="$REPO_ROOT/_build/native/debug/build/cmd/actrun/actrun.exe"
SNAPSHOT_DIR="$REPO_ROOT/testdata/snapshots/examples"

if [ ! -x "$CLI_BIN" ]; then
  echo "Building CLI..."
  (cd "$REPO_ROOT" && moon build src/cmd/actrun --target native >/dev/null)
fi

EXAMPLES=(
  examples/01-hello.yml
  examples/02-env-and-outputs.yml
  examples/03-matrix.yml
  examples/04-multi-job.yml
  examples/05-secrets.yml
  examples/09-conditional.yml
  examples/22-working-directory.yml
  examples/24-multiline-run.yml
  examples/25-continue-on-error.yml
  examples/26-step-outputs.yml
  examples/27-github-env.yml
  examples/28-job-outputs.yml
  examples/29-expressions.yml
  examples/30-step-if.yml
  examples/33-deep-dependencies.yml
  examples/35-matrix-fan-in.yml
  examples/37-local-context.yml
)

if [ "$#" -gt 0 ]; then
  examples=("$@")
else
  examples=("${EXAMPLES[@]}")
fi

mkdir -p "$SNAPSHOT_DIR"
pass=0
fail=0

for example in "${examples[@]}"; do
  slug="$(basename "${example%.yml}")"
  example_path="$REPO_ROOT/$example"

  if [ ! -f "$example_path" ]; then
    echo "SKIP $slug (not found)"
    continue
  fi

  echo -n "RUN  $slug... "

  # Run with actrun, capture output
  output=$("$CLI_BIN" "$example_path" --local --trust --trigger push 2>&1) || true
  run_id=$(echo "$output" | grep "^run_id=" | head -1 | cut -d= -f2)

  if [ -z "$run_id" ]; then
    echo "FAIL (no run_id)"
    fail=$((fail + 1))
    continue
  fi

  # Extract step statuses from run view
  run_json=$("$CLI_BIN" run view "$run_id" --json 2>&1) || true

  # Build snapshot: extract ok, state, and step id:status pairs
  ok=$(echo "$run_json" | grep -o '"ok": *[a-z]*' | head -1 | awk '{print $2}')
  state=$(echo "$run_json" | grep -o '"state": *"[^"]*"' | head -1 | sed 's/.*"state": *"//;s/"//')

  # Extract steps as "id:status" lines (robust jq-free parsing)
  steps=$(echo "$run_json" | grep -o '"id": "[^"]*", "status": "[^"]*"' | sed 's/"id": "//;s/", "status": "/:/;s/"//' | grep -v '__finish' || true)

  snapshot="ok=$ok state=$state"
  if [ -n "$steps" ]; then
    snapshot="$snapshot
$steps"
  fi

  echo "$snapshot" > "$SNAPSHOT_DIR/$slug.txt"
  echo "ok"
  pass=$((pass + 1))
done

echo ""
echo "Examples: $pass passed, $fail failed"
if [ "$pass" -gt 0 ]; then
  echo "Saved to: $SNAPSHOT_DIR/"
fi

[ "$fail" -eq 0 ]
