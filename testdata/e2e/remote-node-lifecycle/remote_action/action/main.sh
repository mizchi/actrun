printf '%s' "$STATE_phase" > "$GITHUB_WORKSPACE/main.txt"
printf 'phase=main\n' >> "$GITHUB_STATE"
