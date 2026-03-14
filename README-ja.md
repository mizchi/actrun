# action_runner

[MoonBit](https://docs.moonbitlang.com) で構築された GitHub Actions ローカルランナー。`gh` 互換の CLI でワークフローをローカル実行・デバッグできます。

## インストール

```bash
# ソースからビルド（MoonBit CLI が必要）
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
moon build src/main --target native
# バイナリ: _build/native/debug/build/main/main.exe
```

## クイックスタート

```bash
# ワークフローをローカル実行
action_runner workflow run .github/workflows/ci.yml

# 実行計画だけ表示（実行しない）
action_runner workflow run .github/workflows/ci.yml --dry-run

# ローカルに不要な action をスキップ
action_runner workflow run .github/workflows/ci.yml \
  --skip-action actions/checkout \
  --skip-action extractions/setup-just

# worktree で隔離実行
action_runner workflow run .github/workflows/ci.yml \
  --workspace-mode worktree

# 結果確認
action_runner run view run-1
action_runner run logs run-1 --task build/test
```

## CLI リファレンス

### ワークフロー操作

```bash
action_runner workflow list                 # .github/workflows/ のワークフロー一覧
action_runner workflow run <workflow.yml>    # ワークフローをローカル実行
```

### 実行結果の操作

```bash
action_runner run list                      # 過去の実行一覧
action_runner run view <run-id>             # 実行サマリー
action_runner run view <run-id> --json      # JSON で表示
action_runner run watch <run-id>            # 完了まで監視
action_runner run logs <run-id>             # 全ログ表示
action_runner run logs <run-id> --task <id> # 特定タスクのログ
action_runner run download <run-id>         # 全アーティファクトをダウンロード
```

### アーティファクト・キャッシュ操作

```bash
action_runner artifact list <run-id>                          # アーティファクト一覧
action_runner artifact download <run-id> --name <name>        # アーティファクトをダウンロード
action_runner cache list                                      # キャッシュ一覧
action_runner cache prune --key <key>                         # キャッシュ削除
```

### ワークフロー実行フラグ

| フラグ | 説明 |
|--------|------|
| `--dry-run` | 実行計画を表示して終了 |
| `--skip-action <pattern>` | パターンに一致する action をスキップ（繰り返し可） |
| `--workspace-mode <mode>` | `local`（デフォルト）, `worktree`, `tmp`, `docker` |
| `--repo <path>` | git リポジトリから実行 |
| `--event <path>` | push イベント JSON ファイル |
| `--repository <owner/repo>` | GitHub リポジトリ名 |
| `--ref <ref>` | Git ref 名 |
| `--run-root <path>` | 実行記録の保存先 |
| `--json` | 読み取りコマンドの JSON 出力 |

## ワークスペースモード

| モード | 説明 |
|--------|------|
| `local` | カレントディレクトリで直接実行（デフォルト） |
| `worktree` | `git worktree` で隔離されたコピーを作成 |
| `tmp` | `git clone` で一時ディレクトリにコピー |
| `docker` | Docker コンテナ内で実行（計画中） |

## 対応する GitHub Actions

### ビルトイン Action（決定論的エミュレーション）

| Action | 対応入力 |
|--------|----------|
| `actions/checkout@*` | `path`, `ref`, `fetch-depth`, `clean`, `sparse-checkout`, `submodules`, `lfs`, `fetch-tags`, `persist-credentials`, `set-safe-directory`, `show-progress` |
| `actions/upload-artifact@*` | `name`, `path`, `if-no-files-found`, `overwrite`, `include-hidden-files` |
| `actions/download-artifact@*` | `name`, `path`, `pattern`, `merge-multiple` |
| `actions/cache@*` | `key`, `path`, `restore-keys`, `lookup-only`, `fail-on-cache-miss` |
| `actions/cache/save@*` | `key`, `path` |
| `actions/cache/restore@*` | `key`, `path`, `restore-keys`, `lookup-only`, `fail-on-cache-miss` |
| `actions/setup-node@*` | `node-version`, `node-version-file`, `cache`, `registry-url`, `always-auth`, `scope` |

### リモート Action（fetch + 実行）

- GitHub リポジトリの `node` action（`pre`/`main`/`post` ライフサイクル）
- GitHub リポジトリの `docker` action（`pre-entrypoint`/`entrypoint`/`post-entrypoint` ライフサイクル）
- Composite action（ローカル・リモート）
- `docker://image` 直接実行
- `wasm://name@version` モジュール実行

## シークレットと変数

```bash
# 環境変数でシークレットを提供
ACTION_RUNNER_SECRET_MY_TOKEN=xxx action_runner workflow run ci.yml

# 変数を提供
ACTION_RUNNER_VAR_MY_VAR=value action_runner workflow run ci.yml
```

シークレットは stdout, stderr, ログ, 実行記録で自動的にマスクされます。`::add-mask::` ワークフローコマンドにも対応。

## 環境変数

| 変数 | 説明 |
|------|------|
| `ACTION_RUNNER_SECRET_<NAME>` | `${{ secrets.<name> }}` |
| `ACTION_RUNNER_VAR_<NAME>` | `${{ vars.<name> }}` |
| `ACTION_RUNNER_NODE_BIN` | Node.js バイナリパス |
| `ACTION_RUNNER_DOCKER_BIN` | Docker バイナリパス |
| `ACTION_RUNNER_WASM_BIN` | Wasm ランタイムバイナリ（デフォルト: `wasmtime`） |
| `ACTION_RUNNER_GIT_BIN` | Git バイナリパス |
| `ACTION_RUNNER_GITHUB_BASE_URL` | GitHub API ベース URL |
| `ACTION_RUNNER_ARTIFACT_ROOT` | アーティファクト保存先 |
| `ACTION_RUNNER_CACHE_ROOT` | キャッシュ保存先 |
| `ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT` | リモート action キャッシュ先 |
| `ACTION_RUNNER_ACTION_REGISTRY_ROOT` | カスタムレジストリルート |
| `ACTION_RUNNER_WASM_ACTION_ROOT` | Wasm action モジュールルート |

## ワークフロー機能

- Push トリガーフィルタ（`branches`, `paths`）
- `strategy.matrix`（axes, include, exclude, fail-fast, max-parallel）
- Job/step `if` 条件（`success()`, `always()`, `failure()`, `cancelled()`）
- `needs` 依存とアウトプット/結果の伝搬
- 再利用可能ワークフロー（`workflow_call`）— inputs, outputs, secrets, `secrets: inherit`, ネスト展開
- Job `container` と `services`（Docker ネットワーキング）
- 式関数: `contains`, `startsWith`, `endsWith`, `fromJSON`, `toJSON`, `hashFiles`
- ファイルコマンド: `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`
- シェル: `bash`, `sh`, `pwsh`, カスタムテンプレート（`{0}`）
- `step.continue-on-error`, `steps.*.outcome` / `steps.*.conclusion`

## 開発

```bash
just              # check + test
just fmt          # コードフォーマット
just check        # 型チェック
just test         # テスト実行
just e2e          # E2E シナリオ実行
just release-check  # fmt + info + check + test + e2e
```

### ライブ互換性テスト

```bash
# 一括実行: dispatch → wait → download → compare
just gha-compat-live compat-checkout-artifact.yml

# 段階的に実行
just gha-compat-dispatch compat-checkout-artifact.yml
just gha-compat-download <run-id>
just gha-compat-compare compat-checkout-artifact.yml _build/gha-compat/<run-id>
```

## アーキテクチャ

| ファイル | 役割 |
|----------|------|
| `src/lib.mbt` | 契約型 |
| `src/parser.mbt` | ワークフロー YAML パーサー |
| `src/trigger.mbt` | Push トリガーマッチャー |
| `src/lowering.mbt` | Bitflow IR への変換、action/再利用ワークフローの展開 |
| `src/executor.mbt` | ネイティブホストエグゼキュータ |
| `src/runtime.mbt` | Git ワークスペースの物質化 |
| `src/main/main.mbt` | CLI エントリポイント |
| `testdata/` | 互換性テスト fixture |

## ライセンス

Apache-2.0
