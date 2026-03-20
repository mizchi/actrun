# actrun

[MoonBit](https://docs.moonbitlang.com) で構築された GitHub Actions ローカルランナー。`gh` 互換の CLI でワークフローをローカル実行・デバッグできます。

## インストール

```bash
# curl（Linux / macOS）
curl -fsSL https://raw.githubusercontent.com/mizchi/actrun/main/install.sh | sh

# Docker
docker run --rm -v "$PWD":/workspace -w /workspace ghcr.io/mizchi/actrun workflow run .github/workflows/ci.yml

# moon install
moon install mizchi/actrun/cmd/actrun

# ソースからビルド
git clone https://github.com/mizchi/actrun.git && cd actrun
moon build src/cmd/actrun --target native
```

## flake.nixにoverlayを追加

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

## クイックスタート

```bash
# ワークフローをローカル実行
actrun workflow run .github/workflows/ci.yml

# 実行計画だけ表示（実行しない）
actrun workflow run .github/workflows/ci.yml --dry-run

# ローカルに不要な action をスキップ
actrun workflow run .github/workflows/ci.yml \
  --skip-action actions/checkout \
  --skip-action extractions/setup-just

# worktree で隔離実行
actrun workflow run .github/workflows/ci.yml \
  --workspace-mode worktree

# 結果確認
actrun run view run-1
actrun run logs run-1 --task build/test
```

## 設定

`actrun init` で `actrun.toml` を生成できます。

```toml
# Workspace mode: local, worktree, tmp, docker
workspace_mode = "local"

# ローカル実行では不要な action をスキップ
local_skip_actions = ["actions/checkout"]

# `--event` 未指定時のローカル GitHub context（必要なときだけ固定）
# [local_context]
# repository = "owner/repo"
# ref_name = "main"
# before_rev = "HEAD^"
# after_rev = "HEAD"
# actor = "your-name"
```

`--event` を渡さない場合でも、actrun は可能ならローカル git リポジトリから `github.repository` / `github.ref_name` / `github.sha` / `github.actor` を自動推定します。`[local_context]` はその上書きや固定が必要なときだけ使ってください。優先順位や利用例は [docs/local-context.md](docs/local-context.md) を参照してください。

## CLI リファレンス

### ワークフロー操作

```bash
actrun workflow list                 # .github/workflows/ のワークフロー一覧
actrun workflow run <workflow.yml>    # ワークフローをローカル実行
```

### 実行結果の操作

```bash
actrun run list                      # 過去の実行一覧
actrun run view <run-id>             # 実行サマリー
actrun run view <run-id> --json      # JSON で表示
actrun run watch <run-id>            # 完了まで監視
actrun run logs <run-id>             # 全ログ表示
actrun run logs <run-id> --task <id> # 特定タスクのログ
actrun run download <run-id>         # 全アーティファクトをダウンロード
```

### アーティファクト・キャッシュ操作

```bash
actrun artifact list <run-id>                          # アーティファクト一覧
actrun artifact download <run-id> --name <name>        # アーティファクトをダウンロード
actrun cache list                                      # キャッシュ一覧
actrun cache prune --key <key>                         # キャッシュ削除
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

## ローカル実行フラグ

actrun は実行環境に `ACTRUN_LOCAL=true` を自動設定します。`if:` 条件でローカル実行時のみステップをスキップ/実行できます：

```yaml
steps:
  # ローカルではスキップ（GitHub Actions では実行）
  - uses: actions/checkout@v5
    if: ${{ !env.ACTRUN_LOCAL }}

  # ローカルでのみ実行（GitHub Actions ではスキップ）
  - run: echo "local debug info"
    if: ${{ env.ACTRUN_LOCAL }}
```

GitHub Actions では `ACTRUN_LOCAL` は未設定なので、`!env.ACTRUN_LOCAL` は `true` に評価され全ステップが通常通り実行されます。

## シークレットと変数

```bash
# 環境変数でシークレットを提供
ACTRUN_SECRET_MY_TOKEN=xxx actrun workflow run ci.yml

# 変数を提供
ACTRUN_VAR_MY_VAR=value actrun workflow run ci.yml
```

シークレットは stdout, stderr, ログ, 実行記録で自動的にマスクされます。`::add-mask::` ワークフローコマンドにも対応。

## 環境変数

| 変数 | 説明 |
|------|------|
| `ACTRUN_SECRET_<NAME>` | `${{ secrets.<name> }}` |
| `ACTRUN_VAR_<NAME>` | `${{ vars.<name> }}` |
| `ACTRUN_NODE_BIN` | Node.js バイナリパス |
| `ACTRUN_DOCKER_BIN` | Docker バイナリパス |
| `ACTRUN_WASM_BIN` | Wasm ランタイムバイナリ（デフォルト: `wasmtime`） |
| `ACTRUN_GIT_BIN` | Git バイナリパス |
| `ACTRUN_GITHUB_BASE_URL` | GitHub API ベース URL |
| `ACTRUN_ARTIFACT_ROOT` | アーティファクト保存先 |
| `ACTRUN_CACHE_ROOT` | キャッシュ保存先 |
| `ACTRUN_GITHUB_ACTION_CACHE_ROOT` | リモート action キャッシュ先 |
| `ACTRUN_ACTION_REGISTRY_ROOT` | カスタムレジストリルート |
| `ACTRUN_WASM_ACTION_ROOT` | Wasm action モジュールルート |

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
