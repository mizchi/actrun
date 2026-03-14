#!/usr/bin/env bash
set -euo pipefail

# Verify local snapshots match committed golden files
# Usage: bash scripts/snapshot_verify.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT_DIR="$REPO_ROOT/testdata/snapshots"

if [ ! -d "$SNAPSHOT_DIR" ]; then
  echo "No snapshots found in $SNAPSHOT_DIR"
  exit 1
fi

# Re-run local snapshots
bash "$REPO_ROOT/scripts/snapshot_local.sh" >/dev/null 2>&1

FRESH_DIR="$REPO_ROOT/_build/compat-snapshot-verify"
rm -rf "$FRESH_DIR"
mkdir -p "$FRESH_DIR"

# Copy fresh results
for f in "$SNAPSHOT_DIR"/*.txt; do
  slug="$(basename "$f" .txt)"
  fresh="$REPO_ROOT/_build/compat-snapshot/$slug/actrun/actrun/report/result.txt"
  if [ -f "$fresh" ]; then
    cp "$fresh" "$FRESH_DIR/$slug.txt"
  fi
done

pass=0
fail=0

for golden in "$SNAPSHOT_DIR"/*.txt; do
  slug="$(basename "$golden" .txt)"
  fresh="$FRESH_DIR/$slug.txt"
  if [ ! -f "$fresh" ]; then
    echo "SKIP $slug (no fresh result)"
    continue
  fi
  golden_value="$(cat "$golden")"
  fresh_value="$(cat "$fresh")"
  if [ "$golden_value" = "$fresh_value" ]; then
    echo "ok   $slug: $golden_value"
    pass=$((pass + 1))
  else
    echo "FAIL $slug"
    echo "  golden: $golden_value"
    echo "  actual: $fresh_value"
    fail=$((fail + 1))
  fi
done

echo ""
echo "Verify: $pass passed, $fail failed"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
