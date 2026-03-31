# ADR 0001: Public API Boundary For WASM Support

- Status: Accepted
- Date: 2026-03-31

## Context

actrun は GitHub Actions 互換 runner として公開したいが、WASM support を入れるにあたって独自 protocol を public API に含めると、将来の GitHub 互換性と self-hosted runner drop-in replacement の目標を損ないやすい。

特に次の独自表現は、workflow / action metadata の GitHub-compatible surface から外れる。

- `wasm://...`
- `runs-on: wasi`
- `runs.using: wasi`

一方で、self-hosted runner 側に WASM runtime を実装し、標準 `node*` action を最適化して実行すること自体は GitHub Actions の既存表現内で実現できる。

## Decision

actrun の release contract は、できるだけ GitHub Actions の既存表現に収める。

### Stable public API

- workflow YAML syntax は GitHub Actions 互換 surface とする
- `runs-on` は self-hosted labels / groups の semantics に従う
- action metadata は `node*` / `composite` / `docker` を public surface とする
- WASM runtime choice は runner-local configuration として公開する
  - `--wasm-runner`
  - `ACTRUN_WASM_RUNNER`
  - `ACTRUN_WASM_BIN`

### Provisional public API

- 標準 `node*` action の `runs.main` sibling `*.wasm` を sidecar として検出し、self-hosted runner が優先実行する最適化

この rule は GitHub-compatible な packaging だが、ecosystem contract としてはまだ固定しきらないため provisional とする。

### Experimental / internal API

- `wasm://...`
- `runs-on: wasi`
- `runs.using: wasi`
- `ACTRUN_WASM_ACTION_ROOT`
- WASM shim argv / sandbox layout / tempdir などの internal execution details

これらは repo 内に code path が残っていても release contract には含めない。

## Consequences

- README と公開 docs は GitHub-compatible surface を primary path として説明する
- WASM support は self-hosted runner optimization として説明する
- GitHub-hosted runner では JS fallback が通ることを CI で継続確認する
- self-hosted runner では sidecar WASM path が通ることを CI で継続確認する
- experimental / internal API は semver で後方互換を約束しない

## Notes

この ADR の規範的 contract は [docs/public-api.md](../public-api.md) に置く。ADR は「なぜその boundary にしたか」を保持する。
