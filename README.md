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

# Nix (run without installing)
nix run github:mizchi/actrun -- workflow run .github/workflows/ci.yml

# Nix (install into profile)
nix profile install github:mizchi/actrun

# moon install
moon install mizchi/actrun/cmd/actrun

# Build from source
git clone https://github.com/mizchi/actrun.git && cd actrun
moon build src/cmd/actrun --target native
```

## Nix

### Run directly

```bash
nix run github:mizchi/actrun -- workflow run .github/workflows/ci.yml
```

### Build from source

```bash
nix build github:mizchi/actrun
./result/bin/actrun workflow run .github/workflows/ci.yml
```

### Development shell

<details>
<summary>With direnv (recommended)</summary>

With [direnv](https://direnv.net/) and [nix-direnv](https://github.com/nix-community/nix-direnv):

```bash
echo "use flake" > .envrc
direnv allow
```

</details>

Or without direnv:

```bash
nix develop
```

### Adding the overlay to your flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    actrun.url = "github:mizchi/actrun";
  };

  outputs = { nixpkgs, actrun, ... }:
    let
      system = "aarch64-darwin"; # or "x86_64-linux"
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ actrun.overlays.default ];
      };
    in
    {
      packages.${system}.default = pkgs.actrun;
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.actrun ];
      };
    };
}
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

# Include uncommitted changes in worktree/tmp workspace
# include_dirty = true

# Default local GitHub context when `--event` is omitted
# [local_context]
# repository = "owner/repo"
# ref_name = "main"
# before_rev = "HEAD^"
# after_rev = "HEAD"
# actor = "your-name"

# Override actions with local commands
# [override."actions/setup-node"]
# run = "echo 'using local node' && node --version"

# Affected file patterns per workflow
# [affected."ci.yml"]
# patterns = ["src/**", "package.json"]
```

When `--event` is omitted, actrun auto-detects `github.repository`, `github.ref_name`, `github.sha`, and `github.actor` from the local git repository when possible. Use `[local_context]` only when you need to pin or override those values. See [Local GitHub Context](docs/local-context.md) for precedence and examples.

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

### Analysis Commands

```bash
# Lint: type check expressions and detect dead code
actrun lint                          # Lint all .github/workflows/*.yml
actrun lint .github/workflows/ci.yml # Lint a specific file
actrun lint --ignore W001            # Suppress a rule (repeatable)

# Visualize: render workflow job dependency graph
actrun viz .github/workflows/ci.yml              # ASCII art (terminal)
actrun viz .github/workflows/ci.yml --mermaid    # Mermaid text (for Markdown)
actrun viz .github/workflows/ci.yml --detail     # Mermaid with step subgraphs
actrun viz .github/workflows/ci.yml --svg        # SVG image
actrun viz .github/workflows/ci.yml --svg --theme github-light
```

#### Lint Diagnostics

| Rule | Severity | Description |
|------|----------|-------------|
| `undefined-context` | error | Undefined context (e.g. `foobar.x`) |
| `wrong-arity` | error | Wrong function arity (e.g. `contains('one')`) |
| `unknown-function` | error | Unknown function (e.g. `myFunc()`) |
| `unknown-property` | warning | Unknown property (e.g. `github.nonexistent`) |
| `type-mismatch` | warning | Comparing incompatible types |
| `unreachable-step` | warning | Unreachable step (`if: false`) |
| `future-step-ref` | error | Reference to future step |
| `undefined-step-ref` | error | Reference to undefined step |
| `undefined-needs` | error | Undefined `needs` job reference |
| `circular-needs` | error | Circular `needs` dependency |
| `unused-outputs` | warning | Unused job outputs |
| `duplicate-step-id` | error | Duplicate step IDs in same job |
| `missing-runs-on` | error | Missing `runs-on` |
| `empty-job` | error | Empty job (no steps) |
| `uses-and-run` | error | Step has both `uses` and `run` |
| `empty-matrix` | warning | Matrix with empty rows |
| `invalid-uses` | error | Invalid `uses` syntax |
| `invalid-glob` | warning | Invalid glob pattern in trigger filter |
| `redundant-condition` | warning | Always-true/false condition |
| `script-injection` | warning | Script injection risk (untrusted input in `run:`) |
| `permissive-permissions` | warning | Overly permissive permissions |
| `deprecated-command` | warning | Deprecated workflow command (`::set-output` etc.) |
| `missing-prt-permissions` | warning | `pull_request_target` without explicit `permissions` |
| `if-always` | warning | Bare `always()` — prefer `success() \|\| failure()` |
| `dangerous-checkout-in-prt` | error | Checkout PR head in `pull_request_target` |
| `secrets-to-third-party` | warning | Secrets passed via env to third-party action |
| `missing-timeout` | warning | No `timeout-minutes` (opt-in: `--strict`) |
| `mutable-action-ref` | warning | Tag ref instead of SHA pin (opt-in: `--online`) |
| `action-not-found` | error | Action ref not found on GitHub (opt-in: `--online`) |

Configure lint behavior in `actrun.toml`:

```toml
[lint]
preset = "default"  # default, strict, oss
ignore_rules = ["unknown-property", "unused-outputs"]
```

| Preset | Includes |
|--------|----------|
| `default` | All rules except `missing-timeout` and online checks |
| `strict` | `default` + `missing-timeout` |
| `oss` | `strict` + `mutable-action-ref` / `action-not-found` (network) |

#### Visualization Example

```
$ actrun viz .github/workflows/release.yml

┌───────┐    ┌────────┐
│ build │    │ docker │
└───────┘    └────────┘
    └┐
     │
┌─────────┐
│ release │
└─────────┘
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
| `--workspace-mode <mode>` | `worktree` (default), `local`, `tmp`, `docker` |
| `--repo <path>` | Run from a git repository |
| `--event <path>` | Push event JSON file |
| `--repository <owner/repo>` | GitHub repository name |
| `--ref <ref>` | Git ref name |
| `--run-root <path>` | Run record storage root |
| `--nix` | Force nix wrapping for run steps |
| `--no-nix` | Disable nix wrapping even if flake.nix/shell.nix exists |
| `--nix-packages <pkgs>` | Ad-hoc nix packages (space-separated) |
| `--container-runtime <name>` | Container runtime: `docker`, `podman`, `container`, `lima`, `nerdctl` |
| `--affected [base]` | Only run if files matching patterns changed (see below) |
| `--retry` | Re-run only failed jobs from the latest run |
| `--include-dirty` | Include uncommitted changes in worktree/tmp workspace |
| `--json` | JSON output for read commands and `--dry-run` |

## Affected Runs

Skip workflows when no relevant files have changed. Patterns are resolved in order:

1. `actrun.toml` `[affected."<workflow>"]` patterns
2. `on:push:paths` from the workflow file (automatic fallback)

```bash
# Compare against last successful run (default)
actrun ci.yml --affected

# Compare against a specific rev
actrun ci.yml --affected HEAD~3
actrun ci.yml --affected abc1234

# Preview what would happen (shows plan even if skipped)
actrun ci.yml --affected HEAD~1 --dry-run
```

Configure patterns in `actrun.toml`:

```toml
[affected."ci.yml"]
patterns = ["src/**", "package.json"]

[affected.".github/workflows/lint.yml"]
patterns = ["src/**", "*.config.*"]
```

If `actrun.toml` has no patterns, `on:push:paths` from the workflow is used automatically:

```yaml
on:
  push:
    paths: ["src/**", "*.toml"]  # actrun --affected uses these
```

## Workspace Modes

| Mode | Description |
|------|-------------|
| `local` | Run in-place in the current directory |
| `worktree` | Create an isolated `git worktree` for execution (default) |
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

## Action Overrides

Replace specific `uses:` action steps with custom `run:` commands via `actrun.toml`. This is useful when you have tools installed locally and want to skip the action's setup logic.

```toml
[override."actions/setup-node"]
run = "echo 'using local node' && node --version"
```

When a workflow step matches `uses: actions/setup-node@*`, actrun replaces it with the specified `run:` command before execution.

Combine with `local_skip_actions` for full control:

```toml
local_skip_actions = ["actions/checkout"]

[override."actions/setup-node"]
run = "echo 'using local node'"

[override."actions/setup-python"]
run = "python3 --version"
```

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

## Performance

Benchmark on Apple Silicon (M-series). Nix measurements use warm nix store cache.

### Startup overhead (1 job, 1 step, `echo ok`)

| Mode | Startup |
|------|--------:|
| `local` | ~0.13s |
| `nix-packages` | ~0.70s |
| `apple-container` | ~0.93s |

### Workspace modes (2 jobs, 7 steps, file I/O)

| Mode | Run 1 | Run 2 | Run 3 |
|------|------:|------:|------:|
| `local` | 0.277s | 0.420s | 0.265s |
| `worktree` | 0.260s | 0.258s | 0.256s |
| `tmp` | 0.631s | 0.599s | 0.586s |

### CPU-heavy workload (prime sieve to 50000, sh)

| Mode | Startup | Total | Exec |
|------|--------:|------:|-----:|
| `local` | ~0.13s | ~5.35s | ~5.22s |
| `nix-packages` | ~0.70s | ~4.27s | ~3.57s |
| `apple-container` | ~0.93s | ~3.18s | ~2.25s |

Shell implementation affects execution speed significantly:

| Mode | Shell | Version |
|------|-------|---------|
| `local` | macOS `/bin/sh` | bash 3.2.57 (POSIX mode) |
| `nix-packages` | nix bash | bash 5.3.9 |
| `apple-container` | Alpine `/bin/sh` | BusyBox 1.36.1 ash |

### Summary

- **local / worktree** have minimal startup (~0.13s) — ideal for iterative development
- **nix-packages** adds ~0.6s startup for `nix develop` shell initialization (warm cache; first run fetches packages)
- **apple-container** adds ~0.9s startup for container lifecycle, but BusyBox ash executes shell scripts ~2.3x faster than macOS bash 3.2
- For CPU-heavy shell workloads, **apple-container is the fastest end-to-end** despite higher startup cost

```bash
# Try it yourself
nix run github:mizchi/actrun -- workflow run .github/workflows/ci.yml
```

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
| `src/lint/` | Expression parser, type checker, dead code detection, workflow visualization |
| `src/cmd/actrun/main.mbt` | CLI entry point |
| `testdata/` | Compatibility fixtures |

## Prior Art

- [actionlint](https://github.com/rhysd/actionlint) — Static checker for GitHub Actions workflow files. `actrun lint` is inspired by its rule design and type system.

## License

Apache-2.0
