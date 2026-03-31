# Changelog

## 0.28.0

### Features

- Add GitHub-compatible WASM sidecar execution for `node*` actions on self-hosted runners
- Add explicit WASM runtime selection with `--wasm-runner` / `ACTRUN_WASM_RUNNER` (`wasmtime`, `deno`, `v8`)
- Add plan API, in-process shell execution, and MoonBit-generated WASI runner / worker paths
- Add slim container image and compat CI coverage for GitHub-hosted JS fallback and self-hosted WASM execution

### Security

- Harden WASI sandbox path validation and cleanup to prevent traversal and leftover tempdir issues

### CI / Tooling

- Pin the MoonBit toolchain in workflows and replace deprecated setup actions to keep CI reproducible
- Tighten the public API boundary docs and mark protocol extensions such as `wasm://...` and `runs-on: wasi` as internal / experimental

## 0.27.0

### Security

- Fix expression injection via matrix values in `if` conditions — matrix values are now quoted as string literals to prevent injection like `'true' || always()` from bypassing conditionals
- Add path traversal protection for local action references (`uses: ./path`) — reject paths that escape the workspace via `..` segments
- Clean up script files after step execution to avoid leaving interpolated secrets on disk

### Bug Fixes

- **Composite action outputs not propagated** — `steps.<composite-id>.outputs.*` now works correctly for composite actions (#18, reported by @bmthd)
- **Composite action outcome/conclusion not set** — `steps.<composite-id>.outcome` and `steps.<composite-id>.conclusion` are now propagated from inner steps
- **JS SyntaxError on startup** — fix `${}` in MoonBit-generated JS template literals causing `SyntaxError: Missing } in template expression` (#17, reported by @bmthd)
- **Matrix substitution in complex expressions** — `${{ matrix.key != 'true' }}` no longer replaces the entire expression with empty string; matrix refs within larger expressions are now substituted inline while preserving the `${{ }}` wrapper
- **Job-level `if` not matrix-substituted** — `if: ${{ matrix.skip != 'true' }}` at the job level now works correctly

### Tests

- 13 new matrix strategy test fixtures: three axes, job/step if/env/name, continue-on-error, include extra keys, matrix chain, working-directory, unquoted YAML values
- 5 composite action test fixtures: single output, multiple outputs, outcome/conclusion, output in if condition, GITHUB_ENV propagation
- 28 unit tests for `substitute_matrix_text` edge cases (special characters, complex expressions, injection attempts)
- 3 executor tests for output/env with special characters and heredoc format

## 0.26.0

### Documentation

- Add performance benchmark to README and `docs/perf.md`
- Benchmarks cover startup overhead, workspace modes, Node.js CPU, and file I/O across local, nix-packages, and apple-container modes

## 0.25.0

### Bug Fixes

- Fix matrix substitution in complex expressions and job-level `if` (#22)

## 0.24.0

### Features

- Add `--sandbox ronly` support for read-only step execution
- Add Nix flake with `nix run github:mizchi/actrun`, `nix build`, and `devShell` (PR #19 by @ryoppippi)
- Fix `--nix` flag to actually force nix-shell wrapping (PR #20 by @ryoppippi)

## 0.23.0

### Features

- Add local GitHub context auto-detection (`github.repository`, `github.ref_name`, `github.sha`, `github.actor`) from local git
- Add `[local_context]` override in `actrun.toml`
- Install via Nix overlay (PR #15 by @myuron)

## 0.22.0

### Features

- Add `--jq` flag powered by pure MoonBit jq implementation (`mizchi/jq`)

## 0.21.0

### Features

- Add `--jq` flag for JSON filtering in `run view`, `run logs`, etc.

## 0.20.0

### Features

- Align CLI output format with `gh` for run/workflow/cache/artifact commands
- Add `--log` flag to `run view`, run list filters, JSON aliases

## 0.19.0

### Features

- Add `--include-dirty` flag for worktree/tmp workspace modes (#13)

## 0.18.0

### Features

- Add experimental `actrun export` to convert GitHub Actions workflows to standalone shell scripts
- Export supports: expression resolution, matrix defaults, parallel execution, reusable workflow inlining, `GITHUB_OUTPUT` conversion

## 0.17.0

### Security

- Canonicalize paths in `validate_workspace_path` to prevent directory traversal via `..` segments (#8, by @hyperfinitism)
- Add symlink resolution to `validate_workspace_path_real` to prevent symlink-based path traversal (#10)

### Features

- Support `!cancelled()` in `runs.post-if` and `runs.pre-if` for compatibility with actions like `gradle/actions/setup-gradle` (#9, by @maehata-fairy)

### Refactoring

- Remove stale `src/core/` package (3,630 lines of diverged dead code) (#11)

## 0.13.0

- Add `local_override_actions`: replace actions with custom shell scripts via `actrun.toml`
- Add `--podman` shorthand for `--docker --container-runtime podman`
- Add `--apple-container` shorthand for `--docker --container-runtime container`

## 0.12.0

- Default workspace mode changed from `local` to `--worktree` for safety
- Fix `--docker` mode: pass `--trust --local` to container, forward more flags
- Fix workspace dir collision when multiple runs happen in same millisecond
- Add examples matrix to CI (66+ jobs across worktree/local/tmp modes)
- Fix `--tmp` and `--worktree` clone from subdirectories (detect git root)

## 0.11.0

- Local mode checkout never deletes files — only overwrites
- Remove unused checkout deletion code (clean parameter, tracked file removal)
- Add `--docker` shorthand

## 0.10.0

- Improve `--dry-run` output: show step names, shell type, job dependencies
- Add `--dry-run --json` for structured execution plan output
- Allow `--affected --dry-run` combination
- Document `--affected` in README and `--help`

## 0.9.0

- Add JS backend support via Node.js `child_process` shim
- npm package: `@mizchi/actrun` with esbuild/oxc-minify (2.4MB → 1.2KB)
- Remove `#cfg(target="native")` gates from executor
- Multi-arch Docker: amd64 native + arm64 JS bundle
- Add `package.json` and `scripts/bundle-js.js`

## 0.8.0

- Harden against symlink attacks and path traversal
- Add `validate_workspace_path()` for consistent boundary checks
- Local mode safety: confirmation prompt, .git protection
- Fix Docker image accessibility (issue #4, multi-arch build)
- Fix checkout clean mode destroying untracked files (issue #3)
- Add Claude Code skills (actrun, actrun-debug, actrun-init)
- Enhanced `--affected`: rev expressions (`HEAD~3`), `on:push:paths` fallback
- Fix `actrun.toml` affected syntax to valid TOML (`[affected."ci.yml"]`)
- Resolve reusable workflows from caller directory

## [Unreleased]

### Added

- Minimal builtin emulator for `actions/setup-node@*` (`node-version`, `cache: npm`, `registry-url`)
- Minimal support for `actions/checkout@*` under job `container` to make the workspace materialized on the host visible to subsequent container `run` steps
- Minimal support for `actions/setup-node@*` under job `container` to propagate PATH shim / output to subsequent `run` steps
- Minimal support for `actions/upload-artifact@*` / `actions/download-artifact@*` roundtrip under job `container` accessible from subsequent `run` steps
- Minimal support for `actions/cache@*` miss -> deferred save -> next job restore under job `container` accessible from subsequent `run` steps
- Minimal support for job `services` detached service container start / cleanup via native docker adapter
- Minimal support for `${{ job.services.<id>.ports[...] }}` context
- Minimal support for job `services` health check wait
- Minimal support for creating a docker network per job for job `services`, sharing the same network / service alias with job `container`
- unit/docs/E2E coverage for job `services` + job `container` networking
- Added backend capability model (`host` / `docker` / `wasm`) to `ResolvedAction`
- resolver / lowering coverage for backend capability assignment on builtin / node / docker actions
- Minimal support for resolving manifest-backed custom registry actions (`bit://...`) from `ACTRUN_ACTION_REGISTRY_ROOT/<scheme>/<name>/<version>` and lowering/executing composite / `node*` / `runs.using: docker` backends
- unit/E2E coverage for custom registry node action resolution and execution
- Minimal support for `required` / implicit default / type validation of reusable workflow `workflow_call.inputs`
- docs/unit/E2E coverage for typed reusable workflow inputs
- Minimal support for reusable workflow caller job `strategy.matrix`
- Minimal support for reusable workflow caller matrix + `workflow_call.outputs` aggregation
- docs/unit/E2E coverage for matrix caller reusable workflow execution and `workflow_call.outputs` aggregation
- all vendored upstream fixtures are now validated for `supported` / `unsupported` / `known_diff` classification metadata in compat tests
- Added minimal `--run-root` and `--workspace-mode` contract to CLI, with foundation for saving local run records to `_build/actrun/runs/run-<n>/run.json` and `tasks/*.stdout.log|stderr.log|summary.md`
- Added job state and artifact/cache index to `run.json`
- Added `started_at_ms` / `finished_at_ms` and `jobs.json` / `artifacts.json` / `caches.json` sidecars to run store, fixing the `_build/actrun/runs/<run-id>/` layout
- whitebox/E2E coverage for run store persistence, task log persistence, artifact/cache indexing, and workspace-mode parsing
- Added minimal read-only subcommand `actrun run view <run-id>` and `actrun run logs <run-id>`
- whitebox/E2E coverage for run store readback via `run view` / `run logs`
- Added minimal read-only subcommand `actrun run list`
- whitebox/E2E coverage for run store listing via `run list`
- Added minimal read-only subcommand `actrun run watch <run-id>`
- whitebox/E2E coverage for run store polling via `run watch`
- Added minimal read-only subcommand `actrun run download <run-id>`
- whitebox/E2E coverage for downloading all artifacts from a persisted run store
- Added minimal read-only subcommands `actrun artifact list <run-id>` and `actrun artifact download <run-id>`
- whitebox/E2E coverage for artifact index listing and artifact download from persisted run store
- Added minimal read-only subcommand `actrun cache list`
- whitebox/E2E coverage for cache store listing across workspace roots
- Added minimal delete subcommand `actrun cache prune --key <cache-key>`
- whitebox/E2E coverage for cache store pruning by exact key
- Added minimal read-only subcommand `actrun workflow list --repo <repo_root>`
- whitebox/E2E coverage for listing `.github/workflows/*.yml|*.yaml` with file-stem fallback for unnamed workflows
- Added minimal subcommand `actrun workflow run <workflow>`
- Unified positional execution and `workflow run` into the same code path
- Added `--json` support for `run logs` / `run download` / `artifact download`
- Added `exit_code` to `run.json` and fixed non-zero exit for `run watch` on failed/cancelled runs
- Added `--artifact-root`, `--cache-root`, `--github-action-cache-root`, `--registry-root`, `--wasm-action-root` to CLI, allowing local injection points to be controlled via flags instead of env overrides
- black-box coverage for CLI root override flags via run store / remote reusable workflow / custom registry / wasm scenarios
- Minimal adapter for resolving/lowering `wasm://...` actions as Wasm backend contract and executing file-based Wasm modules via `ACTRUN_WASM_BIN` + `ACTRUN_WASM_ACTION_ROOT`
- unit/E2E coverage for Wasm runner adapter and missing-module failure
- Added `restore-keys` prefix hit support for `actions/cache@*` / `actions/cache/restore@*`
- `compat-cache-restore-keys.yml` and local/GitHub-hosted cache restore-keys compat coverage
- Added `lookup-only` support for `actions/cache@*` / `actions/cache/restore@*`
- `compat-cache-lookup-only.yml` and local/GitHub-hosted cache lookup-only compat coverage
- Added `fail-on-cache-miss` support for `actions/cache@*` / `actions/cache/restore@*`
- `compat-cache-fail-on-cache-miss.yml` and local/GitHub-hosted cache fail-on-cache-miss compat coverage
- Added `directory`, wildcard path, and download-all directory mode support for `actions/upload-artifact@*` / `actions/download-artifact@*`
- `compat-artifact-glob-directory.yml` and local/GitHub-hosted artifact glob/directory compat coverage
- Added `if-no-files-found` (`warn` / `ignore` / `error`) support for `actions/upload-artifact@*`
- `compat-artifact-if-no-files-found.yml` and local/GitHub-hosted artifact if-no-files-found compat coverage
- Added `overwrite` support for `actions/upload-artifact@*`
- `compat-artifact-overwrite.yml` and local/GitHub-hosted artifact overwrite compat coverage
- Added `merge-multiple` support for `actions/download-artifact@*`
- `compat-artifact-merge-multiple.yml` and local/GitHub-hosted artifact merge-multiple compat coverage
- `compat-setup-node-cache-npm.yml` and `gha-compat-*` script live compare pipeline
- Minimal subset of expression functions (`contains`, `startsWith`, `endsWith`, `fromJSON`, `toJSON`, `hashFiles`)
- docs/E2E coverage for `fromJSON()` / `toJSON()` and `contains(fromJSON(...), ...)`
- docs/E2E coverage for `hashFiles()` in script/env and step `if:`
- minimal `${{ vars.* }}` support backed by `ACTRUN_VAR_<NAME>`
- docs/E2E coverage for `${{ vars.* }}` in script/env and step `if:`
- minimal `${{ secrets.* }}` support backed by `ACTRUN_SECRET_<NAME>`
- docs/E2E coverage for `${{ secrets.* }}` in script/env
- workflow/job `permissions` parse + contract support with explicit lowering reject in MVP
- docs/E2E coverage for unsupported `permissions`
- workflow/job `concurrency` parse + contract support with explicit lowering reject in MVP
- docs/E2E coverage for unsupported `concurrency`
- `workflow_call` trigger and `inputs` / `outputs` / `secrets` parse + contract support with explicit lowering reject in MVP
- docs/E2E coverage for unsupported `workflow_call`
- local reusable workflow (`jobs.<job_id>.uses: ./.github/workflows/*.yml`) minimum execution support
- docs/E2E coverage for local reusable workflow execution
- local reusable workflow caller/callee `with`, `workflow_call.outputs`, and secret mapping support
- remote reusable workflow (`owner/repo/.github/workflows/*.yml@ref`) minimum execution support
- unit/E2E coverage for remote reusable workflow prefetch + caller/callee `with`, `workflow_call.outputs`, and secret mapping
- nested reusable workflow execution support across local / remote reusable workflow chains
- unit/docs/E2E coverage for nested reusable workflow execution
- job `container` string / mapping parse + contract support with explicit lowering reject in MVP
- docs/E2E coverage for unsupported `job.container`
- minimal job `container` execution for `run` steps via the docker adapter
- unit/docs/E2E coverage for job `container` `run` execution
- Minimal support for executing cached / prefetched GitHub repo `node*` actions via docker adapter under job `container`
- unit/E2E coverage for job `container` GitHub repo `node*` action execution
- Minimal support for executing GitHub repo / direct `runs.using: docker` actions as sibling containers under job `container`, sharing the job container's volume mounts
- unit/E2E coverage for job `container` GitHub repo `runs.using: docker` action sibling execution
- job `services` mapping parse + contract support with explicit lowering reject in MVP
- docs/E2E coverage for unsupported `job.services`

- `push` trigger matcher for MVP CI workflows
- workflow YAML subset parser for `on.push`, `jobs`, `steps`, `env`, and `defaults.run`
- workflow/job/step contract types
- lowering from workflow spec to `bitflow` IR
- native host executor for `run` steps
- bit workspace materialization from push `after_sha`
- minimal CLI that parses, lowers, and executes a workflow on native target
- CLI repo mode with `--repo`, `--workspace`, `--ref`, `--after`, `--changed`
- automatic changed-path calculation in CLI repo mode, with `--before` support
- minimal `uses: actions/checkout@*` support as a no-op workspace step
- `ActionRef` parser and resolver layer for GitHub, docker, local, and custom action refs
- `builtin://checkout` alias for runner-native checkout semantics
- generic action-task dispatch in the native executor
- workspace-aware `./local-action` composite expansion
- local composite action `with` inputs and `${{ inputs.* }}` substitution
- basic GitHub runner environment injection for native `run` steps
- minimal `GITHUB_ACTION` support for native execution
- `GITHUB_ACTION_REPOSITORY` and `GITHUB_ACTION_REF` injection for cached / prefetched GitHub actions
- `GITHUB_ACTION_PATH` injection for local composite action inner steps
- `GITHUB_ENV` and `GITHUB_OUTPUT` heredoc-style multiline file command support
- workspace-scoped file command paths to avoid cross-run collisions
- `GITHUB_ENV`, `GITHUB_PATH`, and `GITHUB_OUTPUT` file command support
- `GITHUB_STEP_SUMMARY` support with per-step summary capture in task reports
- local composite action-scoped `GITHUB_STATE` propagation for later inner steps
- minimal `${{ env.* }}` substitution for native `run` step script/env/shell/cwd
- minimal direct-dependency `${{ needs.<job>.outputs.<name> }}` and `${{ needs.<job>.result }}` substitution
- minimal push-event `${{ github.ref }}`, `${{ github.ref_name }}`, `${{ github.sha }}` substitution and matching `GITHUB_REF*` env injection
- minimal push-event `${{ github.event_name }}` substitution and `GITHUB_EVENT_NAME` env injection
- minimal push-event `${{ github.repository }}` substitution and `GITHUB_REPOSITORY` env injection
- minimal push-event `${{ github.repository_owner }}` substitution and `GITHUB_REPOSITORY_OWNER` env injection
- minimal push-event `${{ github.actor }}` substitution and `GITHUB_ACTOR` env injection
- CLI repo mode infers `github.repository` from the `origin` remote URL when `--repository` is omitted
- CLI `--event` support for GitHub push webhook payload JSON, with explicit flag overrides
- minimal `${{ github.workflow }}`, `${{ github.job }}`, `${{ github.workspace }}` substitution for native `run` steps
- minimal `${{ github.action }}` substitution for native `run` steps
- minimal `${{ github.action_repository }}` and `${{ github.action_ref }}` substitution for cached / prefetched GitHub actions
- minimal `${{ github.action_path }}` substitution for local composite action inner steps
- minimal `${{ runner.os }}`, `${{ runner.arch }}`, `${{ runner.temp }}`, `${{ runner.environment }}` substitution for native `run` steps
- file-based shell execution for `bash` / `sh` / `pwsh` and `{0}` custom shell templates
- nested `uses` support inside local composite actions for local actions and builtin checkout
- native GitHub action prefetch that clones `owner/repo[/path]@ref` into the action cache before lowering
- workspace-aware expansion for cached GitHub repo composite actions under `_build/actrun/github_actions`
- native execution for cached / prefetched GitHub repo `node*` actions via `runs.main`
- native docker execution for `docker://...` actions and cached / prefetched GitHub repo `runs.using: docker` actions
- deferred `post` cleanup scheduling and `GITHUB_STATE` sharing for cached / prefetched GitHub repo `node*` actions
- deferred `post-entrypoint` cleanup scheduling and `GITHUB_STATE` sharing for cached / prefetched GitHub repo `runs.using: docker` actions
- job-local `${{ steps.<id>.outputs.<name> }}` substitution for later native `run` steps
- absolute `GITHUB_WORKSPACE` / `${{ github.workspace }}` resolution during native execution
- compat fixture testdata scaffold under `testdata/`
- test-only compat fixture loader for `fixture.txt + workflow.yml`
- docs-based compat fixtures for `on: push` scalar / array / object forms
- docs-based compat fixtures for `branches`, `branches-ignore`, `paths`, and `paths-ignore`
- docs-based compat fixtures for env precedence and `defaults.run` resolution
- docs-based compat fixtures for `jobs.needs`, `steps.id`, and multiline `steps.run`
- docs-based compat fixtures for `steps.uses`, `steps.shell`, `steps.working-directory`, `steps.env`, and `steps.with`
- docs-based compat fixtures for missing context properties and unsupported `GITHUB_STATE`
- docs-based compat fixtures for `GITHUB_STEP_SUMMARY` file command behavior
- docs-based compat fixtures for positive `env` / `steps.*.outputs.*` contexts and env precedence
- docs-based compat fixtures for minimal `github.*` context support
- docs-based compat fixtures for minimal `runner.*` context support
- docs-based compat fixture for custom shell template execution
- docs-based compat fixtures for `GITHUB_ENV`, `GITHUB_OUTPUT`, and `GITHUB_PATH` workflow commands
- compat fixture `event.json` support wired through `PushEvent` parsing for black-box runs
- docs-based `github.*` context fixtures migrated from inline events to `event.json`
- docs-based compat run tests share a common fixture/workspace preparation helper
- docs-based compat parse/lower tests share common fixture parsing and lowering helpers
- compat suites derive workspace names from fixture paths via shared helpers
- compat suites share workspace preparation primitives for absolute and copied workspaces
- compat suites share workflow fixture preparation helpers
- compat suites share sync workflow lowering helpers
- compat suites resolve fixture names relative to suite roots
- act compat tests also use relative fixture names
- compat suites share assertion helpers for workflow/task/step lookups
- compat suite-specific wrapper helpers moved into a shared helper test file
- compat suite roots/workspace policies are centralized as suite config data
- languageservices / act compat tests share common fixture parsing helpers and thinner workspace setup
- vendored `actions/languageservices` parser success fixtures for the MVP push subset
- vendored `actions/languageservices` parser error fixtures with `known_diff` tracking for MVP mismatches
- vendored `actions/languageservices` expression fixtures for `env` and `steps.*.outputs.*`, including case-insensitive property access
- vendored normalized `nektos/act` fixtures for `set-env-*`, `steps-context`, and `stepsummary`
- vendored normalized `nektos/act` shell fixtures for `bash`, `sh`, runner default shell, and custom shell known diff
- `docs_urls` metadata and validation for upstream `nektos/act` fixtures against GitHub Docs
- smoke tests for multiline/default shell, explicit `sh`, and checkout action aliases
- unsupported feature guards for `uses`, advanced `matrix`, reusable workflow, container, non-`success()` step conditions
- Expanded the `just e2e` black-box CLI harness with trigger skip, workflow file commands, remote node lifecycle, and remote docker lifecycle scenarios
- Added black-box CLI scenarios for artifact action roundtrip, failure/blocking, unsupported `uses` / `matrix`, `--event` override precedence, `head_commit` fallback, direct `docker://...` actions, nested remote composite prefetch, nested remote composite cache hits, remote composite cache hits, remote `node` / `docker` failure cleanup, cached remote `node` / `docker` failure cleanup, nested remote `node` / `docker` prefetch, nested remote `node` / `docker` cache hits, cached remote `node` / `docker` action lifecycle, repo-mode `needs.outputs`, repo-mode job-scoped file commands, repo-mode multi-job summary, repo-mode `needs.outputs + GITHUB_STEP_SUMMARY`, repo-mode remote `node` / `docker` failure cleanup, repo-mode cached remote `node` / `docker` failure cleanup, repo-mode `head_commit` fallback, `--repo + --event` execution, and repo `origin` based repository auto-detection
- Added builtin emulators for `actions/upload-artifact` and `actions/download-artifact`, plus dispatchable GitHub-hosted compat workflows that upload observed values as artifacts
- Added builtin emulators for `actions/cache/save` and `actions/cache/restore`, plus local / GitHub-hosted cache roundtrip compat scenarios
- Added builtin `actions/cache` restore + deferred post-save emulation, plus local / GitHub-hosted auto-save compat scenarios
- Added builtin `actions/checkout` support for `path` and `sparse-checkout`, plus local / GitHub-hosted sparse checkout compat scenarios
- Added minimal `strategy.matrix` support for axes-only, include-only, exclude filtering, mixed axes+include workflows, `fail-fast`, `max-parallel` throttling, matrix-job `needs` fan-in, and aggregated matrix `needs.<job>.result` / `needs.<job>.outputs.*`, plus docs/E2E coverage for `${{ matrix.* }}` substitution
- Added minimal job-level `if:` support with status functions and simple `github.*` / `needs.*` comparisons, plus docs/E2E coverage for default skip and `if: always()`
- Added minimal step-level `if:` support for `always()` / `failure()` / `cancelled()`, plus docs/E2E coverage for default skip after failure
- Added minimal step-level `continue-on-error` support, preserving failed task outcome while letting later steps run and the workflow stay green
- Added minimal `${{ steps.<id>.outcome }}` / `${{ steps.<id>.conclusion }}` support for later step script/env/if expressions, and upgraded act `steps-context-*` fixtures to supported
- Added minimal builtin `actions/checkout` `fetch-depth` support, plus docs/E2E coverage for shallow default and `fetch-depth: 0`
- Added minimal builtin `actions/checkout` `ref` support, with branch-selection coverage in docs and E2E scenarios
- Added minimal builtin `actions/checkout` `clean` support, preserving untracked files on `clean: false` while keeping default cleanup semantics, plus docs/E2E coverage
- Added minimal builtin `actions/checkout` `submodules` support for `true` and `recursive`, plus docs/E2E coverage for direct vs nested submodule initialization
- Added remote reusable workflow support for `uses: ./.github/actions/*` local actions by rewriting them against the fetched repo root, plus unit and E2E coverage
- Added reusable workflow `secrets: inherit` docs/E2E coverage and a GitHub-hosted compat workflow that compares inherited `GITHUB_TOKEN` presence against the local runner
- Added `gha-compat-compare` to replay dispatchable compat workflows locally and compare downloaded GitHub-hosted artifacts against local emulator output
- Added `gha-compat-live` to dispatch a GitHub-hosted compat workflow, wait for completion, download artifacts, and compare against local emulator output in one step
- Fixed builtin `actions/checkout` sparse-checkout to match default cone-mode semantics on GitHub-hosted runners, and added `sparse-checkout-cone-mode: false` regression coverage
