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

# Requires actrun.toml:
#   [affected.ci.yml]
#   patterns = ["src/**", "package.json"]
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

## View Results

```bash
# List past runs
actrun run list

# View run summary
actrun run view run-1

# View as JSON
actrun run view run-1 --json

# View logs
actrun run logs run-1

# View specific task logs
actrun run logs run-1 --task build/step_1

# Download artifacts
actrun run download run-1
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

# Nix
# nix_mode = ""
# nix_packages = ["python312"]

# Container runtime
# container_runtime = "podman"

# Workflow patterns for `actrun list`
includes = [".github/workflows/*.yml", "ci/**/*.yaml"]

# Affected file patterns per workflow
[affected.ci.yml]
patterns = ["src/**", "package.json"]

[affected.lint.yml]
patterns = ["src/**", "*.config.*"]
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
