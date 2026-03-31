# Public API

actrun の release contract は、できるだけ GitHub Actions の既存表現に収める。

この document は、どこまでを stable public API として扱い、どこから先を runner 実装詳細または experimental extension とみなすかを定義する。

背景と判断理由は [ADR 0001](adr/0001-public-api-boundary.md) を参照。

## Stable

### Workflow surface

- workflow syntax は GitHub Actions の既存 YAML contract に従う
- `runs-on` は GitHub Actions の label / group semantics に従う
- action metadata は GitHub Actions の `node*` / `composite` / `docker` だけを public surface とする
- self-hosted runner 向けの capability routing は label で表現する

例:

```yaml
jobs:
  test:
    runs-on: [self-hosted, linux, x64, wasi]
    steps:
      - uses: actions/checkout@v5
      - uses: owner/example-action@v1
```

`wasi` は custom label であり、workflow grammar を切り替える keyword ではない。

### Runner configuration

stable な runner-local configuration は次の通り:

- `--wasm-runner <wasmtime|deno|v8>`
- `ACTRUN_WASM_RUNNER`
- `ACTRUN_WASM_BIN`

`ACTRUN_WASM_RUNNER` は runtime family を選び、`ACTRUN_WASM_BIN` はその family に対する binary override として扱う。

### GitHub-compatible WASM packaging

WASM を使う action も、public metadata は標準の GitHub Actions action として表現する。

```yaml
runs:
  using: node24
  main: dist/index.js
```

この形の action は GitHub-hosted runner では通常の JavaScript action として動作する。

## Provisional

### Node action sidecar WASM

actrun の self-hosted runner は、標準 `node*` action に対して `runs.main` の sibling `*.wasm` を検出した場合、WASM 実行へ最適化してよい。

例:

- `dist/index.js`
- `dist/index.wasm`

この discovery rule は ecosystem contract としてはまだ provisional とする。

理由:

- sidecar file naming を将来調整する余地を残したい
- metadata に明示 field を足すかどうかをまだ固定しない

ただし、GitHub-hosted runner で JS fallback が成功することは互換 contract として保証する。

## Experimental / Internal

次は release contract に含めない。

- `wasm://...`
- `runs-on: wasi`
- `runs.using: wasi`
- `ACTRUN_WASM_ACTION_ROOT`
- WASM runner shim の argv / tempdir / sandbox layout
- sidecar discovery 以外の internal resolution rule

repo 内にこれらの code path が存在しても、semver での後方互換は約束しない。

## Compatibility policy

- actrun が public に約束するのは GitHub-compatible workflow / action surface
- WASM support は self-hosted runner optimization として提供する
- GitHub Actions 上で同じ workflow / action metadata が通ることを CI で継続確認する

## Release checklist

release 前に少なくとも次を満たす:

1. `README.md` は GitHub-compatible surface を primary path として説明している
2. GitHub-hosted runner 上で JS fallback が成功する compat CI がある
3. actrun self-hosted runner 上で sidecar WASM path が成功する compat CI がある
4. experimental / internal extension は docs 上で stable contract と分離されている
