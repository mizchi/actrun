# actrun

A local GitHub Actions runner built with [MoonBit](https://docs.moonbitlang.com). Run and debug GitHub Actions workflows locally with a `gh`-compatible CLI.

## Install

```bash
# npx (no install required)
npx @mizchi/actrun workflow run .github/workflows/ci.yml

# curl (Linux / macOS)
curl -fsSL https://raw.githubusercontent.com/mizchi/actrun/main/install.sh | sh

# Docker
docker run --rm -v "$PWD":/workspace -w /workspace ghcr.io/mizchi/actrun workflow run .github/workflows/ci.yml

# npm global install
npm install -g @mizchi/actrun

# moon install
moon install mizchi/actrun/cmd/actrun

# Build from source
git clone https://github.com/mizchi/actrun.git && cd actrun
moon build src/cmd/actrun --target native
```

## Quick Start

```bash
# Run a workflow locally
actrun workflow run .github/workflows/ci.yml

# Show execution plan without running
actrun workflow run .github/workflows/ci.yml --dry-run

# Skip actions not needed locally (e.g. setup tools already installed)
actrun workflow run .github/workflows/ci.yml \
  --skip-action actions/checkout \
  --skip-action extractions/setup-just

# Run in isolated worktree
actrun workflow run .github/workflows/ci.yml \
  --workspace-mode worktree

# Generate config file
actrun init

# View results
actrun run view run-1
actrun run logs run-1 --task build/test
```

## Configuration

`actrun init` generates an `actrun.toml` in the current directory:

```toml
# Workspace mode: local, worktree, tmp, docker
workspace_mode = "local"

# Skip actions not needed locally
local_skip_actions = ["actions/checkout"]

# Trust all third-party actions without prompt
trust_actions = true

# Nix integration: "auto" (force), "off" (disable), or empty (auto-detect)
nix_mode = ""

# Additional nix packages
nix_packages = ["python312", "jq"]

# Container runtime: docker, podman, container, lima, nerdctl
container_runtime = "docker"

# Affected file patterns per workflow
# [affected.ci.yml]
# patterns = ["src/**", "package.json"]
```

CLI flags always override `actrun.toml` settings. See [Cheatsheet](docs/cheatsheet.md) for quick reference and [Advanced Workflow](docs/advanced-workflow.md) for details.

## CLI Reference

### Workflow Commands

```bash
actrun workflow list                 # List workflows in .github/workflows/
actrun workflow run <workflow.yml>    # Run a workflow locally
```

### Run Commands

```bash
actrun run list                      # List past runs
actrun run view <run-id>             # View run summary
actrun run view <run-id> --json      # View run as JSON
actrun run watch <run-id>            # Watch until completion
actrun run logs <run-id>             # View all logs
actrun run logs <run-id> --task <id> # View specific task log
actrun run download <run-id>         # Download all artifacts
```

### Artifact & Cache Commands

```bash
actrun artifact list <run-id>                          # List artifacts
actrun artifact download <run-id> --name <name>        # Download artifact
actrun cache list                                      # List cache entries
actrun cache prune --key <key>                         # Delete cache entry
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
| `--nix` | Force nix wrapping for run steps |
| `--no-nix` | Disable nix wrapping even if flake.nix/shell.nix exists |
| `--nix-packages <pkgs>` | Ad-hoc nix packages (space-separated) |
| `--container-runtime <name>` | Container runtime: `docker`, `podman`, `container`, `lima`, `nerdctl` |
| `--affected` | Only run if files matching `actrun.toml` patterns changed since last success |
| `--retry` | Re-run only failed jobs from the latest run |
| `--json` | JSON output for read commands |

## Workspace Modes

| Mode | Description |
|------|-------------|
| `local` | Run in-place in the current directory (default) |
| `worktree` | Create an isolated `git worktree` for execution |
| `tmp` | Clone to a temp directory via `git clone` |
| `docker` | Run in a Docker container |

## Container Runtime

actrun supports multiple container runtimes for job `container:`, `services:`, and `docker://` actions.

| Runtime | Binary | Notes |
|---------|--------|-------|
| `docker` | `docker` | Default |
| `podman` | `podman` | Docker-compatible CLI |
| `container` | `container` | Apple container runtime (macOS) |
| `nerdctl` | `nerdctl` | containerd CLI |
| `lima` | `lima nerdctl` | Lima VM with nerdctl (wrapper script auto-generated) |

```bash
# CLI flag
actrun workflow run ci.yml --container-runtime podman

# actrun.toml
container_runtime = "podman"

# Environment variable (also works)
ACTRUN_CONTAINER_RUNTIME=podman actrun workflow run ci.yml
```

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

actrun sets `ACTRUN_LOCAL=true` in the execution environment. Use this in `if:` conditions to skip steps locally or run steps only locally:

```yaml
steps:
  # Skipped when running locally (runs on GitHub Actions)
  - uses: actions/checkout@v5
    if: ${{ !env.ACTRUN_LOCAL }}

  # Runs only locally (skipped on GitHub Actions)
  - run: echo "local debug info"
    if: ${{ env.ACTRUN_LOCAL }}
```

On GitHub Actions, `ACTRUN_LOCAL` is not set, so `!env.ACTRUN_LOCAL` evaluates to `true` and all steps run normally.

## Secrets & Variables

```bash
# Provide secrets via environment variables
ACTRUN_SECRET_MY_TOKEN=xxx actrun workflow run ci.yml

# Provide variables
ACTRUN_VAR_MY_VAR=value actrun workflow run ci.yml
```

Secrets are automatically masked in stdout, stderr, logs, and run store. The `::add-mask::` workflow command is also supported.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ACTRUN_SECRET_<NAME>` | `${{ secrets.<name> }}` |
| `ACTRUN_VAR_<NAME>` | `${{ vars.<name> }}` |
| `ACTRUN_NODE_BIN` | Node.js binary path |
| `ACTRUN_DOCKER_BIN` | Docker binary path |
| `ACTRUN_WASM_BIN` | Wasm runtime binary (default: `wasmtime`) |
| `ACTRUN_GIT_BIN` | Git binary path |
| `ACTRUN_GITHUB_BASE_URL` | GitHub API base URL |
| `ACTRUN_ARTIFACT_ROOT` | Artifact storage root |
| `ACTRUN_CACHE_ROOT` | Cache storage root |
| `ACTRUN_GITHUB_ACTION_CACHE_ROOT` | Remote action cache root |
| `ACTRUN_ACTION_REGISTRY_ROOT` | Custom registry root |
| `ACTRUN_WASM_ACTION_ROOT` | Wasm action module root |
| `ACTRUN_NIX` | Set to `false` to disable nix wrapping |

## Nix Integration

actrun automatically detects `flake.nix` or `shell.nix` in the workspace root and wraps `run:` steps in the corresponding nix environment. This lets workflows written for `ubuntu-latest` run locally with nix-managed toolchains.

### Auto-detection

| Condition | Wrapping |
|-----------|----------|
| `flake.nix` exists | `nix develop --command <shell> <script>` |
| `shell.nix` exists | `nix-shell --run '<shell> <script>'` |
| Neither exists | No wrapping (host environment) |

Detection requires `nix` to be installed. If `nix` is not found, wrapping is silently skipped.

### Examples

```bash
# Auto-detect flake.nix / shell.nix
actrun workflow run .github/workflows/ci.yml

# Disable nix wrapping
actrun workflow run .github/workflows/ci.yml --no-nix

# Ad-hoc packages without flake.nix
actrun workflow run .github/workflows/ci.yml --nix-packages "python312 jq"

# Disable via environment variable
ACTRUN_NIX=false actrun workflow run .github/workflows/ci.yml
```

### Typical flake.nix for Rust

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in { default = pkgs.mkShell { packages = [ pkgs.rustc pkgs.cargo ]; }; });
    };
}
```

### Typical flake.nix for Python + uv

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in { default = pkgs.mkShell { packages = [ pkgs.python312 pkgs.uv ]; }; });
    };
}
```

### Notes

- Only `run:` steps are wrapped. `uses:` action steps are not affected.
- Job `container:` steps skip nix wrapping (container has its own environment).
- `nix develop` / `nix-shell` is invoked per step, so the nix environment is consistent across steps.

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
