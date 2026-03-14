#!/usr/bin/env bash
set -euo pipefail

# Run compat workflows locally and save result snapshots
# Usage: bash scripts/snapshot_local.sh [workflow...]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI_BIN="$REPO_ROOT/_build/native/debug/build/cmd/actrun/actrun.exe"
SNAPSHOT_DIR="$REPO_ROOT/testdata/snapshots"

if [ ! -x "$CLI_BIN" ]; then
  echo "Building CLI..."
  (cd "$REPO_ROOT" && moon build src/cmd/actrun --target native >/dev/null)
fi

SIMPLE_WORKFLOWS=(
  compat-env-output.yml
  compat-job-needs-output.yml
  compat-continue-on-error.yml
  compat-step-summary.yml
  compat-expressions.yml
)

if [ "$#" -gt 0 ]; then
  workflows=("$@")
else
  workflows=("${SIMPLE_WORKFLOWS[@]}")
fi

pass=0
fail=0

for wf in "${workflows[@]}"; do
  wf_src="$REPO_ROOT/.github/workflows/$wf"
  if [ ! -f "$wf_src" ]; then
    echo "SKIP $wf (not found)"
    continue
  fi

  slug="${wf%.yml}"
  report_name="${slug}-report"
  local_root="$REPO_ROOT/_build/compat-snapshot/$slug"
  workspace="$local_root/actrun/actrun"
  rm -rf "$local_root"
  mkdir -p "$(dirname "$workspace/.github/workflows/$wf")"
  cp "$wf_src" "$workspace/.github/workflows/$wf"
  cp "$REPO_ROOT/README.md" "$workspace/README.md"

  cat > "$workspace/event.json" <<EOF
{
  "ref": "refs/heads/main",
  "before": "1111111111111111111111111111111111111111",
  "after": "2222222222222222222222222222222222222222",
  "repository": { "full_name": "mizchi/actrun" },
  "sender": { "login": "snapshot-bot" },
  "commits": [{ "added": [".github/workflows/$wf"], "modified": [], "removed": [] }]
}
EOF

  echo -n "RUN  $slug... "
  if "$CLI_BIN" "$workspace/.github/workflows/$wf" >/dev/null 2>&1; then
    report="$workspace/report/result.txt"
    if [ -f "$report" ]; then
      mkdir -p "$SNAPSHOT_DIR"
      value="$(cat "$report")"
      echo "$value" > "$SNAPSHOT_DIR/$slug.txt"
      echo "ok ($value)"
      pass=$((pass + 1))
    else
      echo "ok (no report file)"
      pass=$((pass + 1))
    fi
  else
    echo "FAIL"
    fail=$((fail + 1))
  fi
done

echo ""
echo "Snapshots: $pass passed, $fail failed"
if [ "$pass" -gt 0 ]; then
  echo "Saved to: $SNAPSHOT_DIR/"
fi

if [ "$fail" -gt 0 ]; then
  exit 1
fi
