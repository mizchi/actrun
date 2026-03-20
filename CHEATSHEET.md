# actrun Cheatsheet

## Run Workflows

```bash
# Run a workflow
actrun workflow run .github/workflows/ci.yml

# Dry run (show plan, don't execute)
actrun workflow run .github/workflows/ci.yml --dry-run

# Skip specific actions
actrun workflow run .github/workflows/ci.yml \
  --skip-action actions/checkout \
  --skip-action actions/setup-node

# Isolated execution (git worktree)
actrun workflow run .github/workflows/ci.yml --workspace-mode worktree

# Isolated execution (temp clone)
actrun workflow run .github/workflows/ci.yml --workspace-mode tmp
```

## Inspect Results (gh-compatible)

```bash
# List runs (gh-style output)
actrun run list
actrun run list --status failure --limit 5
actrun run list --workflow ci --branch main --event push

# View run summary
actrun run view run-1
actrun run view run-1 -v              # show steps (like gh -v)
actrun run view run-1 --job build -v  # filter by job

# View logs (like gh run view --log)
actrun run view run-1 --log
actrun run view run-1 --log-failed
actrun run logs run-1 --task build/test
actrun run logs run-1 --job build --log-failed

# JSON with field selection (like gh --json fields)
actrun run view run-1 --json status,conclusion,jobs
actrun run view run-1 --json workflowName,headBranch,startedAt
actrun run list --json status,conclusion --limit 5

# Exit code check (like gh --exit-status)
actrun run view run-1 --exit-status && echo "passed"

# Delete a run
actrun run delete run-1

# Watch until done
actrun run watch run-1
```

## Artifacts & Cache

```bash
# List artifacts (with field selection)
actrun artifact list run-1
actrun artifact list run-1 --json name

# Download artifact
actrun artifact download run-1 --name report --dir ./out

# Download all artifacts
actrun run download run-1 --dir ./out

# List cache entries (with limit and field selection)
actrun cache list
actrun cache list --limit 10 --json key,files

# Delete cache
actrun cache prune --key my-cache-key
```

## Secrets & Variables

```bash
# Pass secrets
ACTRUN_SECRET_TOKEN=xxx actrun workflow run ci.yml

# Pass variables
ACTRUN_VAR_ENV=staging actrun workflow run ci.yml

# Load from .env file
actrun workflow run ci.yml --env .env

# Combine
ACTRUN_SECRET_TOKEN=xxx ACTRUN_VAR_ENV=staging \
  actrun workflow run ci.yml
```

`.env` file format:
```bash
# comments are ignored
ACTRUN_SECRET_TOKEN=your-token
ACTRUN_VAR_ENV="staging"     # quotes are stripped
ACTRUN_VAR_DEBUG='true'      # single quotes too
```

## Local/Remote Conditional Steps

```yaml
steps:
  # Skip locally (runs on GitHub Actions)
  - uses: actions/checkout@v5
    if: ${{ !env.ACTRUN_LOCAL }}

  # Run only locally (skips on GitHub Actions)
  - run: echo "debug"
    if: ${{ env.ACTRUN_LOCAL }}
```

## Debug a Real CI Workflow

```bash
# 1. See what would run
actrun workflow run .github/workflows/ci.yml \
  --skip-action actions/checkout \
  --skip-action extractions/setup-just \
  --dry-run

# 2. Run it
actrun workflow run .github/workflows/ci.yml \
  --skip-action actions/checkout \
  --skip-action extractions/setup-just

# 3. Check failures
actrun run logs run-1 --task test/step_3

# 4. Fix and re-run
actrun workflow run .github/workflows/ci.yml \
  --skip-action actions/checkout \
  --skip-action extractions/setup-just
```

## Examples

```bash
# Run example workflows
actrun workflow run examples/01-hello.yml
actrun workflow run examples/02-env-and-outputs.yml
actrun workflow run examples/03-matrix.yml
actrun workflow run examples/04-multi-job.yml
actrun workflow run examples/06-local-skip.yml
actrun workflow run examples/07-artifacts.yml
actrun workflow run examples/08-cache.yml
actrun workflow run examples/09-conditional.yml

# With secrets
ACTRUN_SECRET_API_TOKEN=test123 \
  actrun workflow run examples/05-secrets.yml
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `ACTRUN_SECRET_<NAME>` | Secret: `${{ secrets.<name> }}` |
| `ACTRUN_VAR_<NAME>` | Variable: `${{ vars.<name> }}` |
| `ACTRUN_LOCAL` | Set to `true` by actrun (for `if:` conditions) |
| `ACTRUN_NODE_BIN` | Custom node binary |
| `ACTRUN_DOCKER_BIN` | Custom docker binary |
| `ACTRUN_GIT_BIN` | Custom git binary |
| `ACTRUN_ARTIFACT_ROOT` | Artifact storage path |
| `ACTRUN_CACHE_ROOT` | Cache storage path |

## Workspace Modes

| Mode | Command | Use Case |
|------|---------|----------|
| `local` | (default) | Fast, in-place |
| `worktree` | `--workspace-mode worktree` | Isolated, same repo |
| `tmp` | `--workspace-mode tmp` | Full isolation |
