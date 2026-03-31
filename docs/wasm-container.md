# WASM Container: Portable CI Foundation

> Experimental / internal document.
> This page describes legacy `wasm://...` and `ACTRUN_WASM_ACTION_ROOT` paths that are intentionally outside the release contract.
> For the supported public surface, see [Public API](public-api.md).

A minimal container image that enforces a strict contract: only WASM+WASI modules and shell scripts can execute. No Node.js, no Docker-in-Docker, no language-specific runtimes.

## Why

Standard CI containers include Node.js, Python, Docker, and dozens of tools — creating a sprawling, hard-to-audit attack surface. The WASM container inverts this: you bring your own toolchain, compiled to WASI. If it compiles to `.wasm`, it runs anywhere this container runs.

This makes CI **portable** and **reproducible**:
- Same binary runs on Linux x86_64, Linux arm64, and any WASI-compatible runtime
- No "works on CI but not locally" — the execution contract is the WASI ABI
- Auditable: the only runtime is wasmtime, the only shell is bash

## Contract

| Capability | Available | Notes |
|------------|-----------|-------|
| `run:` steps | bash + coreutils | Shell scripts for glue logic |
| `uses: wasm://` | wasmtime (WASI) | Rust, Go, C, MoonBit → `.wasm` |
| `uses: actions/*` | No | No Node.js runtime |
| `uses: docker://` | No | No container runtime |
| `uses: ./local` | Composite only | No node/docker local actions |
| `git` | Yes | For checkout/workspace |

## Build

```bash
docker build -f Dockerfile.wasm -t actrun-wasm .
```

## Usage

```bash
# Run a workflow
docker run --rm -v "$PWD":/workspace -w /workspace \
  actrun-wasm workflow run .github/workflows/ci.yml

# With WASM action root mounted
docker run --rm \
  -v "$PWD":/workspace \
  -v "$PWD/wasm-actions":/workspace/wasm-actions \
  -w /workspace \
  actrun-wasm workflow run ci.yml
```

## Example Workflow

The workflow below demonstrates the internal `wasm://...` path. It is not part of the stable public API.

```yaml
name: wasm-ci
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      ACTRUN_WASM_ACTION_ROOT: wasm-actions
    steps:
      - run: echo "starting WASM CI"

      # Run your test suite compiled to WASI
      - uses: wasm://my-tests@v1

      # Run linter compiled to WASI
      - uses: wasm://my-lint@v1
        with:
          config: .lintrc.toml

      # Shell glue for reporting
      - run: |
          if [ -f test-results.xml ]; then
            echo "Tests passed"
          fi
```

## Building WASM Actions

The layout below is the internal module-root convention used by the legacy `wasm://...` execution path.

Any language that compiles to WASI works:

```bash
# Rust
cargo build --target wasm32-wasip1 --release
cp target/wasm32-wasip1/release/my_tool.wasm wasm-actions/my-tool/v1/main.wasm

# Go
GOOS=wasip1 GOARCH=wasm go build -o wasm-actions/my-tool/v1/main.wasm

# C (wasi-sdk)
$WASI_SDK/bin/clang -o wasm-actions/my-tool/v1/main.wasm main.c

# MoonBit
moon build --target wasm
cp _build/wasm/release/build/my_tool.wasm wasm-actions/my-tool/v1/main.wasm
```

## WASM Action I/O

WASM actions interact with actrun through the same file-based protocol as GitHub Actions:

| File | Environment Variable | Purpose |
|------|---------------------|---------|
| Output file | `GITHUB_OUTPUT` | `key=value` or heredoc |
| Env file | `GITHUB_ENV` | Set env for subsequent steps |
| Summary file | `GITHUB_STEP_SUMMARY` | Markdown step summary |

Inputs are passed as `INPUT_<NAME>` environment variables.

## Image Size

The WASM container is intentionally minimal:

| Component | Size |
|-----------|------|
| Ubuntu 24.04 base | ~30MB |
| actrun binary | ~15MB |
| wasmtime | ~25MB |
| git + bash + coreutils | ~30MB |
| **Total** | **~100MB** |

Compare: standard CI images are 500MB–2GB+.
