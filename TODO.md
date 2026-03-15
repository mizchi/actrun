# TODO

The current goal is to make `actrun` a "runner that reproduces GitHub Actions workflows locally, handles all standard actions, and can be controlled via a `gh`-compatible CLI."

Priorities are structured around three pillars:

1. Increase compatibility with GitHub standard actions
2. Enable stable execution of the same workflow across `worktree` / `/tmp` / `docker`
3. Enable control of execution, observation, and artifact/cache operations via a `gh`-compatible CLI

## Goals

- [x] Reproduce major GitHub standard actions locally
- [x] Same workflow returns the same results across `local` / `worktree` / `tmp` / `docker` substrates
- [x] Handle run / logs / artifacts / cache via `gh`-compatible subcommands
- [x] Coverage claims in README are backed by docs/upstream/live compat

## Design Principles

- [x] Use GitHub Docs as the source of truth for specifications
- [x] Use `actions/languageservices` as supplementary fixtures for parser / expressions
- [x] Use `nektos/act` as supplementary fixtures for runtime behavior
- [x] Explicitly reject unsupported features instead of silently ignoring them
- [x] New features follow `Red -> Green -> Refactor with upstream source`
- [x] Feature claims are backed by docs-based compat or live compat

## Source of Truth

- Workflow syntax: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- Contexts: https://docs.github.com/en/actions/reference/workflows-and-actions/contexts
- Expressions: https://docs.github.com/en/actions/reference/workflows-and-actions/expressions
- Workflow commands: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
- `actions/languageservices`: https://github.com/actions/languageservices
- `workflow-parser/testdata/reader`: https://github.com/actions/languageservices/tree/main/workflow-parser/testdata/reader
- `expressions/testdata`: https://github.com/actions/languageservices/tree/main/expressions/testdata
- `nektos/act` runner testdata: https://github.com/nektos/act/tree/master/pkg/runner/testdata

## Current Status

- [x] Compat infrastructure for docs / languageservices / act fixtures
- [x] GitHub-hosted live compat (`gha-compat-live`, `gha-compat-compare`)
- [x] Minimal support for `checkout`, `artifact`, `cache`, `setup-node`, reusable workflow, job `container`, `services`
- [x] Major slice of local / remote action lifecycle and matrix / `if` / file commands
- [x] Wasm backend contract / adapter and backend capability model

## P0: Solidify the Execution Foundation

Lock down "where to execute" first. If this is ambiguous, both actions compatibility and CLI will be unstable.

- [x] Run record persistence
  - [x] Minimal save to `_build/actrun/runs/<run-id>/run.json`
  - [x] Fix the layout of `_build/actrun/runs/<run-id>/`
  - [x] Save `run.json` / step state / task state / exit code / task log path
  - [x] Save step log / summary
  - [x] Save job state / artifact index / cache index
  - [x] Save `timestamps`
- [x] Clarify workspace substrate
  - [x] `--workspace-mode` contract (`local`, `repo=tmp` default)
  - [x] `--workspace-mode local` (in-place execution, default)
  - [x] `--workspace-mode worktree` (isolation via `git worktree add`)
  - [x] `--workspace-mode tmp` (isolation via `git clone`)
  - [x] `--workspace-mode docker` (run workflow in container via ghcr.io/mizchi/actrun)
  - [x] Container runtime backends: Docker, Podman, Lima, Apple Containers (`container` framework)
  - [x] Fix cleanup / isolation policy for each mode
  - [x] Security test confirming `_build/actrun/file_commands` / `runner_temp` (which may contain secrets) are cleaned up after runs
  - [x] Security test confirming step scripts / `.npmrc` / file command files are not world-readable
- [x] Promote local injection points to CLI flags
  - [x] `--run-root`
  - [x] `--artifact-root`
  - [x] `--cache-root`
  - [x] `--github-action-cache-root`
  - [x] `--registry-root`
  - [x] `--wasm-action-root`
- [x] Substrate parity E2E
  - [x] Common scenario set running the same workflow across `local` / `worktree` / `tmp`
  - [x] Confirm artifact / cache / summary / logs match across substrates
  - [x] Include repo mode / `--event` / `head_commit` fallback in substrate matrix

## P1: Build a `gh`-Compatible CLI

Stage for turning the current positional CLI into a product. Ultimately enable `gh`-like operation of the local runner.

- [x] Introduce command families
  - [x] `actrun workflow list`
  - [x] `actrun workflow run <workflow>`
  - [x] `actrun run list`
  - [x] `actrun run view <run-id>`
  - [x] `actrun run watch <run-id>`
  - [x] `actrun run logs <run-id>`
  - [x] `actrun run download <run-id>`
  - [x] `actrun artifact list <run-id>`
  - [x] `actrun artifact download <run-id>`
  - [x] `actrun cache list`
  - [x] `actrun cache prune`
- [x] Compatibility layer with the existing CLI
  - [x] Migrate existing `actrun <workflow.yml> ...` to `workflow run` (add deprecation warning)
  - [x] Organize repo mode / event mode / substrate mode into subcommands
- [x] CLI output contract
  - [x] Add `--json` to all read commands
  - [x] Fix JSON schema for run state / artifact metadata / cache metadata (add schema validation tests)
  - [x] Fix correspondence between non-zero exit codes and run states
- [x] CLI black-box
  - [x] `view/watch/logs/download` E2E based on run store
  - [x] Security test confirming run store / `run logs` / `run view` mask secrets when displaying and saving
  - [x] Usage docs aligned with `gh run` / `gh workflow` naming

## P2: Expand GitHub Standard Actions

The approach has two stages:

1. Things we want to reproduce deterministically become builtin / emulators
2. Official actions not made builtin are passed through as remote `node` actions, guaranteed by smoke/live compat

### P2-A: Builtin-Priority Actions

- [x] `actions/checkout`
  - [x] `lfs`
  - [x] `persist-credentials: false`
  - [x] `fetch-tags`
  - [x] `show-progress`
  - [x] `set-safe-directory`
  - [x] Policy decision for token / ssh-key / ssh-known-hosts (local runner uses host git credentials; no GITHUB_TOKEN auth needed)
- [x] `actions/upload-artifact` / `actions/download-artifact`
  - [x] `pattern` (glob filter for download-artifact)
  - [x] `artifact-ids` (unsupported — no ID system in local runner, by design)
  - [x] `retention-days` (no-op locally, silently ignored)
  - [x] `compression-level` (no-op locally, silently ignored)
  - [x] `include-hidden-files`
- [x] `actions/cache`
  - [x] `enableCrossOsArchive` (no-op locally)
  - [x] cache version semantics (local runner uses key-string matching; no path-based versioning needed for single-OS)
  - [x] `save-always` (save cache even on step failure)
  - [x] cache eviction (`cache prune --all`, `cache prune --max-age <days>`)
  - [x] path list normalization (`~` expansion, trim)
  - [x] Post-save edge case on failure/cancel (correctly skips post on always() + cancel)
- [x] `actions/setup-node`
  - [x] `node-version-file` (`.nvmrc`, `.node-version`, `.tool-versions`, `package.json`)
  - [x] `check-latest` (local runner uses system node; no version download)
  - [x] package-manager-cache auto detection (`npm` / `yarn` / `pnpm`)
  - [x] `always-auth` / `scope` / `.npmrc` nuance
- [x] `actions/github-script`
  - [x] Decided to treat as remote official node action (not making it builtin)
  - [x] Add local E2E and live compat (live compat workflow exists; local E2E covered by remote action tests)

### P2-B: Execution Guarantee for Official Actions

- [x] Decide official node action coverage policy
  - [x] builtin: checkout, upload/download-artifact, cache, setup-node
  - [x] remote fetch + node execution: github-script, setup-python/go/java/dotnet/ruby
- [x] Official actions to cover with smoke/live compat
  - [x] `actions/setup-python` (added live compat workflow)
  - [x] `actions/setup-go` (added live compat workflow)
  - [x] `actions/setup-java` (added live compat workflow)
  - [x] `actions/setup-dotnet` (added live compat workflow)
  - [x] `ruby/setup-ruby` (added live compat workflow)
  - [x] `actions/github-script` (added live compat workflow)

## P3: Tighten Workflow/Runtime Compatibility

- [x] Broad compatibility for reusable workflows
  - [x] Live compat for caller matrix + reusable outputs (added workflow)
  - [x] Docs/live compat matrix for nested reusable workflows (E2E: remote-nested-reusable-workflow)
  - [x] Main branch live compat for remote reusable workflow + `secrets: inherit` (existing)
- [x] Hardening container / services
  - [x] Align builtin action coverage matrix for container jobs (E2E: checkout-container, artifact-actions-roundtrip-container, cache-auto-save-container, setup-node-container)
  - [x] Service `volumes` / `options` / `credentials` semantics (covered by existing implementation)
  - [x] Service log capture and run store persistence (fetch `docker logs` during cleanup)
  - [x] Security test confirming `docker login` credentials do not appear in plaintext in argv / stderr / run store (`--password-stdin` + mask_secrets)
  - [x] Alternative container runtimes: Podman, Lima, Apple Containers (`container` framework)
  - [x] `ACTRUN_CONTAINER_RUNTIME` env var to select runtime (default: `docker`)
- [x] Shell / host differences
  - [x] `pwsh` execution environment differences (works when pwsh is available; graceful skip otherwise)
  - [x] Expanded shell template compatibility fixtures (bash/sh/custom template E2E)

## P4: Productionize Registry / Backend

- [x] Remote fetch / protocol resolution for custom registry actions (GitHub repo actions via git clone prefetch)
- [x] Registry cache layout / versioning / auth policy
  - [x] GitHub actions: `_build/actrun/github_actions/{owner}/{repo}/{version}/`
  - [x] Custom registry: `_build/actrun/registry_actions/{scheme}/{name}/{version}/`
  - [x] Environment variable override: `ACTRUN_GITHUB_ACTION_CACHE_ROOT`, `ACTRUN_ACTION_REGISTRY_ROOT`
- [x] Broad compatibility for Wasm backend
  - [x] env / input / output contract (via file commands: GITHUB_ENV/OUTPUT/STATE)
  - [x] pre/post lifecycle policy (wasm has no manifest, single entrypoint model. pre/post to be extended when action.yml support is added)
  - [x] artifact / cache integration (covered by host-side builtin actions)
- [x] Make backend selection policy controllable from CLI / config
  - [x] Auto-selection: determine backend by action ref type (builtin/node/docker/wasm)
  - [x] Environment variable override: `ACTRUN_WASM_BIN`, `ACTRUN_DOCKER_BIN`, `ACTRUN_NODE_BIN`, `ACTRUN_GIT_BIN`

## P5: Establish Compatibility Operations

- [x] Create a correspondence table between README feature claims and docs-based compat (README tables cover all features)
- [x] Auto-generate support matrix from fixture metadata (snapshot framework covers this)
- [x] Prepare a new feature template (snapshot framework + compat workflows)
  - [x] source URL (compat workflow references GitHub docs)
  - [x] Red fixture (snapshot_local.sh generates expected values)
  - [x] Green implementation (snapshot_verify.sh compares)
  - [x] Whether live compat exists (compat-live.yml dispatch workflow)
- [x] Release checklist
  - [x] local `just release-check` (fmt + info + check + test + e2e)
  - [x] Main branch live compat (compat-live.yml)
  - [x] CLI contract diff (JSON schema tests in main_wbtest.mbt)

## P6: Remaining GitHub Actions Features

- [x] `timeout-minutes` (step and job level, parsed and stored, not enforced)
- [x] `on.push.tags` / `on.push.tags-ignore` filter
- [x] `run-name` (workflow run display name)
- [x] `pull_request` trigger (branches/paths filters, treated same as push locally)
- [x] `environment` (deployment environments, parsed as metadata)
- [ ] `concurrency` enforcement (group + cancel-in-progress)
- [ ] `schedule` trigger (cron, local dry-run only)
- [ ] Other event triggers (issues, release, deployment, etc. — low priority)

## Completion Criteria

- [x] Can operate local run / logs / artifacts / cache via `gh`-compatible CLI
- [x] Major workflows produce the same results across `local` / `worktree` / `tmp`
- [x] Docs/E2E/live compat is in place for the priority set of GitHub standard actions
- [x] Coverage claims in README are backed by compat tests (snapshot framework + live compat workflows)
