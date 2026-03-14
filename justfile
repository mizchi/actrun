# MoonBit Project Commands

# Default target (native for local CI execution)
target := "native"

# Default task: check and test
default: check test

# Format code
fmt:
    moon fmt

# Check formatting without rewriting files
fmt-check:
    moon fmt --check

# Type check
check:
    moon check --deny-warn --target {{target}}

# Run tests
test:
    moon test --target {{target}}

# Update snapshot tests
test-update:
    moon test --update --target {{target}}

# Run main
run workflow:
    moon run src/cmd/actrun --target native -- {{workflow}}

# Run black-box CLI E2E scenarios
e2e:
    moon build src/cmd/actrun --target native
    moon run src/e2e/main --target native

# Update local snapshots (run compat workflows and save golden files)
snapshot-update:
    moon build src/cmd/actrun --target native
    bash scripts/snapshot_local.sh

# Verify snapshots match (re-run and compare with golden files)
snapshot-verify:
    moon build src/cmd/actrun --target native
    bash scripts/snapshot_verify.sh

# Dispatch a GitHub-hosted compat workflow
gha-compat-dispatch workflow ref="main":
    gh workflow run {{workflow}} --ref {{ref}}

# Download artifacts from a GitHub Actions run
gha-compat-download run_id dest="_build/gha-compat/{{run_id}}":
    gh run download {{run_id}} --dir {{dest}}

# Compare downloaded GitHub-hosted artifacts with local emulator output
gha-compat-compare workflow downloaded_dir:
    moon build src/cmd/actrun --target native
    bash scripts/gha_compat_compare.sh {{workflow}} {{downloaded_dir}}

# Dispatch, wait, download, and compare in one shot
gha-compat-live workflow repo="mizchi/action_runner" ref="main":
    bash scripts/gha_compat_live.sh {{workflow}} {{repo}} {{ref}}

# Generate type definition files
info:
    moon info --target native

# Verify generated type definition files are up to date
info-check:
    moon info --target native
    git diff --exit-code -- ':(glob)**/*.generated.mbti'

# Clean build artifacts
clean:
    moon clean

# Pre-release check (local only)
release-check: fmt info check test e2e

# Pre-release check on the supported runtime target
release-check-all:
    just release-check

# CI checks for the default target on a clean worktree
ci: fmt-check info-check check test

# CI checks across the supported runtime target
ci-all:
    just ci
