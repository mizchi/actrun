#!/bin/sh
set -eu
printf '%s' "${INPUT_MESSAGE:-}" > "$GITHUB_WORKSPACE/registry-node.txt"
printf 'result=from-registry-node\n' > "$GITHUB_OUTPUT"
