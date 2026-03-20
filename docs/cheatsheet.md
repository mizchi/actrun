# actrun Cheatsheet

## Basic

```bash
# Run a workflow
actrun .github/workflows/ci.yml

# Shorthand (same as above)
actrun workflow run .github/workflows/ci.yml

# List available workflows
actrun list

# List with custom glob
actrun list examples/*.yml

# Dry run (show plan, don't execute)
actrun .github/workflows/ci.yml --dry-run

# Check dependencies
actrun doctor
```

## Job & Step Selection

```bash
# Run only the "build" job
actrun ci.yml --job build

# Run only the "test" step in the "build" job
actrun ci.yml --job build --step test

# Step can be matched by name
actrun ci.yml --job build --step "Run tests"
```

## Skip Actions

```bash
# Skip checkout and setup (use local tools)
actrun ci.yml --skip-action actions/checkout --skip-action actions/setup-node

# Or configure in actrun.toml:
#   local_skip_actions = ["actions/checkout", "actions/setup-node"]
actrun ci.yml
```

## Affected Runs

```bash
# Only run if relevant files changed since last success
actrun ci.yml --affected

# Compare against a specific revision (instead of last success)
actrun ci.yml --affected HEAD~3
actrun ci.yml --affected abc123

# Requires actrun.toml or on:push:paths in workflow:
#   [affected."ci.yml"]
#   patterns = ["src/**", "package.json"]
# If no patterns configured, falls back to on:push:paths from the workflow
```

## Retry Failed

```bash
# Re-run only failed jobs (skip succeeded ones)
actrun ci.yml --retry
```

## Trigger Selection

```bash
# Force schedule trigger (skip trigger matching)
actrun ci.yml --trigger schedule

# Force workflow_dispatch with inputs
actrun ci.yml --trigger workflow_dispatch --input env=staging

# Force pull_request trigger
actrun ci.yml --trigger pull_request
```

## Local GitHub Context

```bash
# Usually auto-detected from the local git checkout
actrun ci.yml

# Pin deterministic values in actrun.toml when needed
#   [local_context]
#   repository = "owner/repo"
#   ref_name = "feature/local-demo"
#   before_rev = "HEAD^"
#   after_rev = "HEAD"
#   actor = "your-name"
```

See `docs/local-context.md` for precedence and a full example.

## Cron Schedules

```bash
# Show cron entries from workflow schedules
actrun cron show

# Install to system crontab
actrun cron install

# Remove actrun entries from crontab
actrun cron uninstall
```

## Nix Integration

```bash
# Auto-detect flake.nix/shell.nix (default)
actrun ci.yml

# Disable nix wrapping
actrun ci.yml --no-nix

# Ad-hoc nix packages (no flake needed)
actrun ci.yml --nix-packages "python312 jq"

# Environment variable
ACTRUN_NIX=false actrun ci.yml
```

## Workspace Modes

```bash
# Run in current directory (default)
actrun ci.yml --local

# Isolated git worktree
actrun ci.yml --worktree

# Clone to temp directory
actrun ci.yml --tmp

# Run in Docker container
actrun ci.yml --workspace-mode docker
```

## Container Runtime

```bash
# Use podman instead of docker
actrun ci.yml --container-runtime podman

# Apple container runtime
actrun ci.yml --container-runtime container

# Lima (nerdctl via VM)
actrun ci.yml --container-runtime lima
```

## Secrets & Variables

```bash
# Provide secrets
ACTRUN_SECRET_MY_TOKEN=xxx actrun ci.yml

# Provide variables
ACTRUN_VAR_MY_VAR=value actrun ci.yml

# Load from .env file
actrun ci.yml --env .env.local
```

## View Results (gh-compatible)

```bash
# List past runs
actrun run list

# Filter: by status, workflow, branch, event
actrun run list --status failure
actrun run list --workflow ci --branch main --event push
actrun run list --limit 5

# View run summary
actrun run view run-1

# View with step details (like gh run view -v)
actrun run view run-1 -v

# Filter by job
actrun run view run-1 --job build -v

# View logs (like gh run view --log)
actrun run view run-1 --log
actrun run view run-1 --log-failed

# View logs (separate command)
actrun run logs run-1
actrun run logs run-1 --task build/step_1
actrun run logs run-1 --job build
actrun run logs run-1 --log-failed

# Exit with non-zero if failed (like gh run view --exit-status)
actrun run view run-1 --exit-status && echo "passed"

# Delete a run
actrun run delete run-1

# Download artifacts
actrun run download run-1
```

## JSON Output (gh-compatible)

```bash
# Full JSON
actrun run view run-1 --json

# Select specific fields (like gh --json fields)
actrun run view run-1 --json status,conclusion,jobs

# gh-compatible field names work
actrun run view run-1 --json workflowName,headBranch,event,startedAt

# Field selection on list commands
actrun run list --json status,conclusion,workflowName --limit 5
actrun workflow list --json name
actrun cache list --json key,files
actrun artifact list run-1 --json name
```

## Configuration (`actrun.toml`)

```bash
# Generate config (auto-detects local tools)
actrun init
```

```toml
# Workspace
workspace_mode = "local"

# Skip setup actions — use local toolchain
local_skip_actions = ["actions/checkout", "actions/setup-node"]

# Trust third-party actions
trust_actions = true

# Optional local GitHub context override
# [local_context]
# repository = "owner/repo"
# ref_name = "main"
# before_rev = "HEAD^"
# after_rev = "HEAD"
# actor = "your-name"

# Nix
# nix_mode = ""
# nix_packages = ["python312"]

# Container runtime
# container_runtime = "podman"

# Workflow patterns for `actrun list`
includes = [".github/workflows/*.yml", "ci/**/*.yaml"]

# Affected file patterns per workflow
[affected."ci.yml"]
patterns = ["src/**", "package.json"]

[affected."lint.yml"]
patterns = ["src/**", "*.config.*"]

# Lint configuration
[lint]
preset = "default"  # default, strict, oss
ignore_rules = ["unknown-property", "unused-outputs"]
```

## Lint

```bash
# Lint all workflows in .github/workflows/
actrun lint

# Lint specific files
actrun lint .github/workflows/ci.yml .github/workflows/release.yml

# Strict mode (adds missing-timeout check)
actrun lint --strict

# Online mode (verify action existence, suggest SHA pins)
actrun lint --online

# Auto-pin action refs to SHA (rewrites files in-place)
actrun lint --update-hash

# Use preset (default, strict, oss)
actrun lint --preset oss

# Suppress a rule
actrun lint --ignore unknown-property --ignore unused-outputs
```

## Visualize

```bash
# ASCII art (terminal)
actrun viz .github/workflows/ci.yml

# Mermaid text (paste into Markdown)
actrun viz .github/workflows/ci.yml --mermaid

# Mermaid with step-level subgraphs
actrun viz .github/workflows/ci.yml --detail

# SVG image
actrun viz .github/workflows/ci.yml --svg

# SVG with theme
actrun viz .github/workflows/ci.yml --svg --theme github-light
```

## Combining Flags

```bash
# Run specific job with nix, skipping checkout
actrun ci.yml --job test --skip-action actions/checkout

# Affected + retry workflow
actrun ci.yml --affected     # first: skip if unchanged
actrun ci.yml --retry        # then: retry only failed jobs

# Schedule trigger on specific job
actrun ci.yml --trigger schedule --job nightly --trust

# Dry run with job filter
actrun ci.yml --job build --dry-run
```
