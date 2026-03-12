#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 <workflow-file> [repo] [ref]" >&2
  exit 1
fi

workflow_file="$1"
repo="${2:-mizchi/action_runner}"
ref="${3:-main}"
compat_key=""
compat_node_version=""
dispatch_args=()

case "$workflow_file" in
  compat-cache-auto-save.yml)
    compat_key="compat-cache-auto-save-$(date +%s)-$$"
    dispatch_args=(-f "compat_key=$compat_key")
    ;;
  compat-cache-restore-keys.yml)
    compat_key="compat-cache-restore-keys-$(date +%s)-$$"
    dispatch_args=(-f "compat_key=$compat_key")
    ;;
  compat-setup-node-basic.yml)
    compat_node_version="${ACTION_RUNNER_COMPAT_NODE_VERSION:-$(node --version | sed 's/^v//')}"
    dispatch_args=(-f "compat_node_version=$compat_node_version")
    ;;
  compat-setup-node-cache-npm.yml)
    compat_key="compat-setup-node-cache-npm-$(date +%s)-$$"
    compat_node_version="${ACTION_RUNNER_COMPAT_NODE_VERSION:-$(node --version | sed 's/^v//')}"
    dispatch_args=(
      -f "compat_key=$compat_key"
      -f "compat_node_version=$compat_node_version"
    )
    ;;
esac

echo "dispatching $workflow_file on $repo@$ref"
if [ "${#dispatch_args[@]}" -gt 0 ]; then
  gh workflow run "$workflow_file" -R "$repo" --ref "$ref" "${dispatch_args[@]}"
else
  gh workflow run "$workflow_file" -R "$repo" --ref "$ref"
fi

run_id=""
for _ in $(seq 1 24); do
  run_id="$(
    gh run list \
      -R "$repo" \
      --workflow "$workflow_file" \
      --limit 10 \
      --json databaseId,headBranch,event,createdAt \
      --jq 'map(select(.event=="workflow_dispatch" and .headBranch=="'"$ref"'")) | sort_by(.createdAt) | last | .databaseId // empty'
  )"
  if [ -n "$run_id" ]; then
    break
  fi
  sleep 5
done

if [ -z "$run_id" ]; then
  echo "failed to locate dispatched run for $workflow_file" >&2
  exit 1
fi

run_url=""
for _ in $(seq 1 24); do
  run_url="$(
    gh run view "$run_id" -R "$repo" --json url --jq '.url' 2>/dev/null || true
  )"
  if [ -n "$run_url" ]; then
    break
  fi
  sleep 5
done

if [ -z "$run_url" ]; then
  echo "failed to load run url for $run_id" >&2
  exit 1
fi

echo "watching run $run_id"
echo "$run_url"
conclusion=""
for _ in $(seq 1 120); do
  status_json="$(
    gh run view \
      "$run_id" \
      -R "$repo" \
      --json status,conclusion \
      --jq '{status: .status, conclusion: (.conclusion // "")}' \
      2>/dev/null || true
  )"
  if [ -z "$status_json" ]; then
    echo "status=pending conclusion=pending"
    sleep 5
    continue
  fi
  status="$(printf '%s' "$status_json" | jq -r '.status')"
  conclusion="$(printf '%s' "$status_json" | jq -r '.conclusion')"
  echo "status=$status conclusion=${conclusion:-pending}"
  if [ "$status" = "completed" ]; then
    break
  fi
  sleep 5
done

if [ "${status:-}" != "completed" ]; then
  echo "run did not complete in time: $run_id" >&2
  exit 1
fi

if [ "$conclusion" != "success" ]; then
  echo "run failed: $run_url" >&2
  gh run view "$run_id" -R "$repo"
  exit 1
fi

download_dir="_build/gha-compat/$run_id"
rm -rf "$download_dir"
mkdir -p "$download_dir"
gh run download "$run_id" -R "$repo" --dir "$download_dir"

cli_bin="_build/native/debug/build/main/main.exe"
if [ ! -x "$cli_bin" ]; then
  moon build src/main --target native >/dev/null
fi
ACTION_RUNNER_COMPAT_CACHE_KEY="$compat_key" \
ACTION_RUNNER_COMPAT_NODE_VERSION="$compat_node_version" \
  bash scripts/gha_compat_compare.sh "$workflow_file" "$download_dir"
