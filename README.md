# action_runner

A local GitHub Actions runner built with [MoonBit](https://docs.moonbitlang.com). Run and debug GitHub Actions workflows locally with a `gh`-compatible CLI.

## Install

```bash
# Build from source (requires MoonBit CLI)
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
moon build src/main --target native
# Binary at _build/native/debug/build/main/main.exe
```

## Quick Start

```bash
# Run a workflow locally
action_runner workflow run .github/workflows/ci.yml

# Show execution plan without running
action_runner workflow run .github/workflows/ci.yml --dry-run

# Skip actions not needed locally (e.g. setup tools already installed)
action_runner workflow run .github/workflows/ci.yml \
  --skip-action actions/checkout \
  --skip-action extractions/setup-just

# Run in isolated worktree
action_runner workflow run .github/workflows/ci.yml \
  --workspace-mode worktree

# View results
action_runner run view run-1
action_runner run logs run-1 --task build/test
```

## CLI Reference

### Workflow Commands

```bash
action_runner workflow list                 # List workflows in .github/workflows/
action_runner workflow run <workflow.yml>    # Run a workflow locally
```

### Run Commands

```bash
action_runner run list                      # List past runs
action_runner run view <run-id>             # View run summary
action_runner run view <run-id> --json      # View run as JSON
action_runner run watch <run-id>            # Watch until completion
action_runner run logs <run-id>             # View all logs
action_runner run logs <run-id> --task <id> # View specific task log
action_runner run download <run-id>         # Download all artifacts
```

### Artifact & Cache Commands

```bash
action_runner artifact list <run-id>                          # List artifacts
action_runner artifact download <run-id> --name <name>        # Download artifact
action_runner cache list                                      # List cache entries
action_runner cache prune --key <key>                         # Delete cache entry
```

### Workflow Run Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Show execution plan without running |
| `--skip-action <pattern>` | Skip actions matching pattern (repeatable) |
| `--workspace-mode <mode>` | `local` (default), `worktree`, `tmp`, `docker` |
| `--repo <path>` | Run from a git repository |
| `--event <path>` | Push event JSON file |
| `--repository <owner/repo>` | GitHub repository name |
| `--ref <ref>` | Git ref name |
| `--run-root <path>` | Run record storage root |
| `--json` | JSON output for read commands |

## Workspace Modes

| Mode | Description |
|------|-------------|
| `local` | Run in-place in the current directory (default) |
| `worktree` | Create an isolated `git worktree` for execution |
| `tmp` | Clone to a temp directory via `git clone` |
| `docker` | Run in a Docker container (planned) |

## Supported GitHub Actions

### Builtin Actions (deterministic emulation)

| Action | Supported Inputs |
|--------|-----------------|
| `actions/checkout@*` | `path`, `ref`, `fetch-depth`, `clean`, `sparse-checkout`, `submodules`, `lfs`, `fetch-tags`, `persist-credentials`, `set-safe-directory`, `show-progress` |
| `actions/upload-artifact@*` | `name`, `path`, `if-no-files-found`, `overwrite`, `include-hidden-files` |
| `actions/download-artifact@*` | `name`, `path`, `pattern`, `merge-multiple` |
| `actions/cache@*` | `key`, `path`, `restore-keys`, `lookup-only`, `fail-on-cache-miss` |
| `actions/cache/save@*` | `key`, `path` |
| `actions/cache/restore@*` | `key`, `path`, `restore-keys`, `lookup-only`, `fail-on-cache-miss` |
| `actions/setup-node@*` | `node-version`, `node-version-file`, `cache`, `registry-url`, `always-auth`, `scope` |

### Remote Actions (fetch + execute)

- GitHub repo `node` actions with `pre`/`main`/`post` lifecycle
- GitHub repo `docker` actions with `pre-entrypoint`/`entrypoint`/`post-entrypoint` lifecycle
- Composite actions (local and remote)
- `docker://image` direct execution
- `wasm://name@version` module execution

## Local-Only Execution Flag

action_runner sets `ACTION_RUNNER_LOCAL=true` in the execution environment. Use this in `if:` conditions to skip steps locally or run steps only locally:

```yaml
steps:
  # Skipped when running locally (runs on GitHub Actions)
  - uses: actions/checkout@v5
    if: ${{ !env.ACTION_RUNNER_LOCAL }}

  # Runs only locally (skipped on GitHub Actions)
  - run: echo "local debug info"
    if: ${{ env.ACTION_RUNNER_LOCAL }}
```

On GitHub Actions, `ACTION_RUNNER_LOCAL` is not set, so `!env.ACTION_RUNNER_LOCAL` evaluates to `true` and all steps run normally.

## Secrets & Variables

```bash
# Provide secrets via environment variables
ACTION_RUNNER_SECRET_MY_TOKEN=xxx action_runner workflow run ci.yml

# Provide variables
ACTION_RUNNER_VAR_MY_VAR=value action_runner workflow run ci.yml
```

Secrets are automatically masked in stdout, stderr, logs, and run store. The `::add-mask::` workflow command is also supported.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ACTION_RUNNER_SECRET_<NAME>` | `${{ secrets.<name> }}` |
| `ACTION_RUNNER_VAR_<NAME>` | `${{ vars.<name> }}` |
| `ACTION_RUNNER_NODE_BIN` | Node.js binary path |
| `ACTION_RUNNER_DOCKER_BIN` | Docker binary path |
| `ACTION_RUNNER_WASM_BIN` | Wasm runtime binary (default: `wasmtime`) |
| `ACTION_RUNNER_GIT_BIN` | Git binary path |
| `ACTION_RUNNER_GITHUB_BASE_URL` | GitHub API base URL |
| `ACTION_RUNNER_ARTIFACT_ROOT` | Artifact storage root |
| `ACTION_RUNNER_CACHE_ROOT` | Cache storage root |
| `ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT` | Remote action cache root |
| `ACTION_RUNNER_ACTION_REGISTRY_ROOT` | Custom registry root |
| `ACTION_RUNNER_WASM_ACTION_ROOT` | Wasm action module root |

## Workflow Features

- Push trigger filter (`branches`, `paths`)
- `strategy.matrix` (axes, include, exclude, fail-fast, max-parallel)
- Job/step `if` conditions (`success()`, `always()`, `failure()`, `cancelled()`)
- `needs` dependencies with output/result propagation
- Reusable workflows (`workflow_call`) with inputs, outputs, secrets, `secrets: inherit`, nested expansion
- Job `container` and `services` with Docker networking
- Expression functions: `contains`, `startsWith`, `endsWith`, `fromJSON`, `toJSON`, `hashFiles`
- File commands: `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`
- Shell support: `bash`, `sh`, `pwsh`, custom templates (`{0}`)
- `step.continue-on-error`, `steps.*.outcome` / `steps.*.conclusion`

## Development

```bash
just              # check + test
just fmt          # format code
just check        # type check
just test         # run tests
just e2e          # run E2E scenarios
just release-check  # fmt + info + check + test + e2e
```

### Live Compatibility Testing

```bash
# One-shot: dispatch, wait, download, compare
just gha-compat-live compat-checkout-artifact.yml

# Step by step
just gha-compat-dispatch compat-checkout-artifact.yml
just gha-compat-download <run-id>
just gha-compat-compare compat-checkout-artifact.yml _build/gha-compat/<run-id>
```

## Architecture

| File | Purpose |
|------|---------|
| `src/lib.mbt` | Contract types |
| `src/parser.mbt` | Workflow YAML parser |
| `src/trigger.mbt` | Push trigger matcher |
| `src/lowering.mbt` | Bitflow IR lowering, action/reusable workflow expansion |
| `src/executor.mbt` | Native host executor |
| `src/runtime.mbt` | Git workspace materialization |
| `src/main/main.mbt` | CLI entry point |
| `testdata/` | Compatibility fixtures |

## License

Apache-2.0
