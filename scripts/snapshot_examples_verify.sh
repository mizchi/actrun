#!/usr/bin/env bash
set -euo pipefail

# Verify example snapshots match. Re-runs examples and compares with golden files.
# Usage: bash scripts/snapshot_examples_verify.sh [example...]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI_BIN="$REPO_ROOT/_build/native/debug/build/cmd/actrun/actrun.exe"
SNAPSHOT_DIR="$REPO_ROOT/testdata/snapshots/examples"
ACTUAL_DIR="$REPO_ROOT/_build/snapshot-verify-examples"

if [ ! -x "$CLI_BIN" ]; then
  echo "Building CLI..."
  (cd "$REPO_ROOT" && moon build src/cmd/actrun --target native >/dev/null)
fi

if [ ! -d "$SNAPSHOT_DIR" ]; then
  echo "error: no snapshots found in $SNAPSHOT_DIR"
  echo "Run 'just snapshot-examples-update' first"
  exit 1
fi

# Collect snapshot files
if [ "$#" -gt 0 ]; then
  snapshots=()
  for arg in "$@"; do
    slug="$(basename "${arg%.yml}")"
    snapshots+=("$SNAPSHOT_DIR/$slug.txt")
  done
else
  snapshots=("$SNAPSHOT_DIR"/*.txt)
fi

rm -rf "$ACTUAL_DIR"
mkdir -p "$ACTUAL_DIR"

pass=0
fail=0

for snapshot_file in "${snapshots[@]}"; do
  slug="$(basename "${snapshot_file%.txt}")"
  example="$REPO_ROOT/examples/$slug.yml"

  if [ ! -f "$example" ]; then
    echo "SKIP $slug (example not found)"
    continue
  fi

  if [ ! -f "$snapshot_file" ]; then
    echo "SKIP $slug (no snapshot)"
    continue
  fi

  echo -n "VERIFY $slug... "

  # Run example
  output=$("$CLI_BIN" "$example" --local --trust --trigger push 2>&1) || true
  run_id=$(echo "$output" | grep "^run_id=" | head -1 | cut -d= -f2)

  if [ -z "$run_id" ]; then
    echo "FAIL (no run_id)"
    fail=$((fail + 1))
    continue
  fi

  run_json=$("$CLI_BIN" run view "$run_id" --json 2>&1) || true
  ok=$(echo "$run_json" | grep -o '"ok": *[a-z]*' | head -1 | awk '{print $2}')
  state=$(echo "$run_json" | grep -o '"state": *"[^"]*"' | head -1 | sed 's/.*"state": *"//;s/"//')
  steps=$(echo "$run_json" | grep -o '"id": "[^"]*", "status": "[^"]*"' | sed 's/"id": "//;s/", "status": "/:/;s/"//' | grep -v '__finish' || true)

  actual="ok=$ok state=$state"
  if [ -n "$steps" ]; then
    actual="$actual
$steps"
  fi

  echo "$actual" > "$ACTUAL_DIR/$slug.txt"

  expected="$(cat "$snapshot_file")"
  if [ "$actual" = "$expected" ]; then
    echo "ok"
    pass=$((pass + 1))
  else
    echo "MISMATCH"
    echo "  expected: $(head -1 "$snapshot_file")"
    echo "  actual:   $(echo "$actual" | head -1)"
    diff --color=auto <(echo "$expected") <(echo "$actual") || true
    fail=$((fail + 1))
  fi
done

echo ""
echo "Verify: $pass passed, $fail failed"

[ "$fail" -eq 0 ]
