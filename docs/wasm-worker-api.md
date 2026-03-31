# WASM Worker API Design

actrun のワークフローセマンティクスを、軽量ワーカー環境 (Cloudflare Workers, Spin.io, Fastly Compute) で実行するための API 設計。

## Design Goals

1. **GitHub Actions YAML 互換**: 既存のワークフロー定義をそのまま使える
2. **WASI-first**: ステップの実行単位は WASI モジュール
3. **HTTP ベースの I/O**: ファイルシステム依存を排除し、KV/HTTP で入出力を行う
4. **ステートレス**: 各ステップは独立した関数呼び出し。状態はストアで管理

## Architecture

```
Workflow YAML
    │
    ▼
┌─────────────┐
│  Scheduler   │  ← actrun core (WASM module)
│  (planner)   │  ワークフローをパースし、実行計画を生成
└──────┬──────┘
       │ TaskPlan[]
       ▼
┌─────────────┐
│  Dispatcher  │  ← Worker runtime (CF Workers / Spin / Fastly)
│              │  各タスクをワーカーに dispatch
└──────┬──────┘
       │
       ├──► Worker A: run step (shell → WASI sh module)
       ├──► Worker B: wasm:// action (WASI module)
       └──► Worker C: run step
       │
       ▼
┌─────────────┐
│    Store     │  ← KV / R2 / Durable Objects
│              │  step outputs, env, artifacts
└─────────────┘
```

## Step Execution Contract

各ステップは以下のインターフェースを満たす WASI モジュール:

### Input (環境変数)

```
INPUT_<NAME>=<value>          # Action inputs
ACTRUN_STEP_ID=<step_id>     # Current step identifier
ACTRUN_JOB_ID=<job_id>       # Current job identifier
ACTRUN_RUN_ID=<run_id>       # Current run identifier
ACTRUN_STORE_URL=<url>       # Store endpoint for I/O
ACTRUN_STORE_TOKEN=<token>   # Auth token for store
```

### Output (HTTP API)

GitHub Actions のファイルベース I/O を HTTP に射影:

| GitHub Actions | Worker API | Method |
|---------------|------------|--------|
| `echo "key=value" >> $GITHUB_OUTPUT` | `POST /store/{run_id}/{step_id}/outputs` | `{"key": "value"}` |
| `echo "key=value" >> $GITHUB_ENV` | `POST /store/{run_id}/env` | `{"key": "value"}` |
| `echo "text" >> $GITHUB_STEP_SUMMARY` | `POST /store/{run_id}/{step_id}/summary` | `"text"` |
| Upload artifact | `PUT /store/{run_id}/artifacts/{name}` | Binary |
| Download artifact | `GET /store/{run_id}/artifacts/{name}` | Binary |

### Step Result

```json
{
  "status": "success" | "failed",
  "outputs": {"key": "value"},
  "env_updates": {"KEY": "VALUE"},
  "conclusion": "success" | "failure" | "skipped"
}
```

## Scheduler API

Scheduler は actrun のパーサー + lowering をそのまま WASI モジュール化したもの。

### `POST /plan`

ワークフロー YAML → 実行計画

```json
// Request
{
  "workflow": "<yaml string>",
  "event": {"ref": "refs/heads/main", ...},
  "context": {"repository": "owner/repo", ...}
}

// Response
{
  "tasks": [
    {
      "id": "build/step_1",
      "kind": "run",
      "needs": [],
      "script": "echo hello",
      "shell": "bash",
      "env": {"CI": "true"}
    },
    {
      "id": "build/step_2",
      "kind": "wasm",
      "needs": ["build/step_1"],
      "entrypoint": "my-lint@v1",
      "with": {"config": ".lintrc"}
    }
  ],
  "job_outputs": {...},
  "job_needs": {...}
}
```

### `POST /dispatch`

実行計画を受け取り、依存関係を解決しながら順次/並列にステップを dispatch。

```json
// Request
{
  "run_id": "run-42",
  "plan": { /* from /plan */ },
  "store_url": "https://store.example.com",
  "wasm_registry": "https://registry.example.com"
}

// Response (streaming)
{"task_id": "build/step_1", "status": "running"}
{"task_id": "build/step_1", "status": "success", "outputs": {...}}
{"task_id": "build/step_2", "status": "running"}
{"task_id": "build/step_2", "status": "success", "outputs": {...}}
{"run_id": "run-42", "status": "completed", "ok": true}
```

## WASM Module Registry

ワーカー環境ではファイルシステムがないため、WASM モジュールは HTTP レジストリから取得。

### Registry API

```
GET /modules/{name}/{version}/main.wasm
  → 200 + application/wasm

GET /modules/{name}/{version}/action.yml
  → 200 + text/yaml (metadata)

PUT /modules/{name}/{version}/main.wasm
  → 201 (publish)
```

### Resolution

```yaml
# Workflow
- uses: wasm://my-lint@v1

# Resolved to:
# GET {ACTRUN_WASM_REGISTRY}/modules/my-lint/v1/main.wasm
```

## Platform Mappings

### Cloudflare Workers

| Concept | Cloudflare |
|---------|-----------|
| Scheduler | Worker (actrun WASM) |
| Dispatcher | Durable Object |
| Step execution | Worker (per-step WASI) |
| Store | KV + R2 |
| Module registry | R2 bucket |
| Streaming output | WebSocket / SSE |

### Spin.io

| Concept | Spin |
|---------|------|
| Scheduler | Spin component (actrun) |
| Dispatcher | Spin component |
| Step execution | Spin component (per-step) |
| Store | Spin KV |
| Module registry | OCI registry |
| Streaming output | HTTP response stream |

### Fastly Compute

| Concept | Fastly |
|---------|--------|
| Scheduler | Compute service |
| Dispatcher | Compute service |
| Step execution | Compute service |
| Store | KV Store |
| Module registry | Object Store |

## Migration Path

```
Phase 1: actrun-wasm container (current)
  └── WASI modules + bash, file-based I/O

Phase 2: actrun-wasm + HTTP store adapter
  └── File I/O → HTTP store bridge (shim layer)
  └── WASI modules use GITHUB_OUTPUT etc. unchanged
  └── Bridge translates to HTTP store calls

Phase 3: Native worker deployment
  └── Scheduler as WASM module on worker platform
  └── Direct HTTP store I/O from WASI modules
  └── No filesystem dependency
```

> Experimental / internal document.
> The `wasm://...` references and `runs-on: wasi` examples in this page describe internal protocol experiments, not the stable release contract.
> For the supported public surface, see [Public API](public-api.md).

## `run:` Steps in Worker Environment

`run:` ステップ (shell scripts) は worker 環境では直接実行できない。選択肢:

1. **WASI shell**: `busybox` を WASI にコンパイルして shell を提供
2. **Transpile to WASM**: shell script を WASM に変換 (limited)
3. **Proxy execution**: shell ステップを外部の shell runner に HTTP dispatch
4. **Disallow**: worker 環境では `run:` を禁止し、`wasm://` のみ許可

推奨は **Phase 2 では option 3** (既存 workflow 互換)、**Phase 3 では option 1** (完全 WASI) に移行。

## Example: Full WASI Workflow (Phase 3, Experimental)

The workflow below is an internal design sketch. It is not part of the supported public API.

```yaml
name: portable-ci
on: push
jobs:
  build:
    runs-on: wasi  # ← new runner type
    steps:
      - uses: wasm://git-checkout@v1
        with:
          repository: ${{ github.repository }}
          ref: ${{ github.ref }}

      - uses: wasm://rust-build@v1
        with:
          target: wasm32-wasip1
          profile: release

      - uses: wasm://test-runner@v1
        with:
          pattern: "tests/**/*.wasm"

      - uses: wasm://artifact-upload@v1
        with:
          name: build-output
          path: target/wasm32-wasip1/release/*.wasm
```

`runs-on: wasi` は全ステップが WASI モジュールであることを宣言し、worker 環境での実行を保証する。
