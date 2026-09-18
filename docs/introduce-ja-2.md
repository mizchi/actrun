# actrun 0.18: lint, viz, export — ワークフローを分析・変換する

前回の記事で actrun の基本を紹介した。今回は最近追加した静的解析、可視化、シェルスクリプト変換の機能を紹介する。

## actrun lint — actionlint インスパイアの静的解析

`actrun lint` でワークフローの問題を検出できるようにした。

```bash
$ actrun lint .github/workflows/ci.yml
lint: all clean (1 files)
```

何もなければ静か。問題があるとこうなる。

```
$ actrun lint bad-workflow.yml
bad-workflow.yml:
  [build/step0] run: error[undefined-context]: undefined context 'foobar'
  [build/step1] run: error[unknown-function]: unknown function 'myFunc'
  [build/step2] if: warning[unreachable-step]: step is unreachable: condition is always false
  [deploy/step-1] needs: error[undefined-needs]: job 'deploy' depends on undefined job 'nonexistent'

lint: 3 error(s), 1 warning(s)
```

### 何をチェックするか

式パーサーを一から書いた。`${{ }}` 内の式をトークナイズ → AST → 型チェックする。

**式の型チェック**: `github.ref` は string、`github.nonexistent_field` は unknown property。`contains('one')` は引数不足。actionlint と同じ 7 型（any, null, number, bool, string, array, object）のシステムで、`github`, `env`, `steps`, `needs` などのコンテキスト型を定義している。

**デッドコード検出**: `if: false` の到達不能ステップ、定義前のステップ参照（`steps.foo` が foo より後にある）、循環 needs、未使用の job outputs。

**構造検証**: 重複ステップ ID、空ジョブ、不正な `uses` 構文、不正な glob パターン。

**セキュリティ**: これが一番実用的。

```yaml
# actrun lint がこれらを検出する:

# script-injection: run: に ${{ github.event.issue.title }} を直接書くな
- run: echo "${{ github.event.issue.title }}"

# dangerous-checkout-in-prt: pull_request_target で PR head を checkout するな
on: pull_request_target
steps:
  - uses: actions/checkout@v4
    with:
      ref: ${{ github.event.pull_request.head.sha }}

# if-always: always() は cancelled でも動く。success() || failure() を使え
- if: always()

# secrets-to-third-party: 信頼できない action に secrets を env で渡すな
- uses: random-org/random-action@v1
  env:
    TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### --online: SHA ピンと存在確認

`--online` をつけると `git ls-remote` でアクションの SHA を解決する。

```bash
$ actrun lint --online .github/workflows/release.yml
release.yml:
  [build/step0] uses: warning[mutable-action-ref]: action 'actions/checkout@v4' uses a mutable ref. Pin to SHA: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11
```

`--update-hash` で自動書き換え。

```bash
$ actrun lint --update-hash .github/workflows/release.yml
updated: .github/workflows/release.yml
```

Before/After:
```yaml
# Before
- uses: actions/checkout@v4

# After
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4
```

これでサプライチェーン攻撃を防げる。タグは第三者が書き換えられるが、SHA は不変。

### プリセットと設定

```bash
actrun lint                     # デフォルト（十分実用的）
actrun lint --preset strict     # + missing-timeout
actrun lint --preset oss        # + SHA ピン + 存在確認（OSS 向け）
```

```toml
# actrun.toml
[lint]
preset = "default"
ignore_rules = ["unknown-property", "unused-outputs"]
```

## actrun viz — ワークフロー可視化

ジョブの依存関係を ASCII で表示する。CI が複雑化してきたときに便利。

```
$ actrun viz .github/workflows/release.yml

┌───────┐    ┌─────┐    ┌────────┐
│ build │    │ npm │    │ docker │
└───────┘    └─────┘    └────────┘
    │
    └────────────┐
                 │
            ┌─────────┐
            │ release │
            └─────────┘
```

`--mermaid` で Mermaid テキストを出力。PR の description にそのまま貼れる。

```bash
$ actrun viz .github/workflows/ci.yml --mermaid
graph TD
  lint["lint (9 steps)"]
  test["test (8 steps)"]
  e2e["e2e (7 steps)"]
```

`--detail` でステップレベルの subgraph も出る。`--svg` で画像出力。ASCII / SVG の描画は actrun 組み込みのレイヤードレンダラーで行う。

## actrun export — ワークフローをシェルスクリプトに変換

これは実験的機能。GitHub Actions のワークフローを、同等の bash スクリプトに変換する。

```bash
$ actrun export examples/04-multi-job.yml
```

```bash
#!/usr/bin/env bash
set -eo pipefail

# --- GitHub Actions expression helpers ---
gha_contains() { [[ "$1" == *"$2"* ]]; }
gha_toJSON() { jq -n --argjson v "$(printenv | jq -Rs ...)" '$v'; }
# ...

job_BUILD() {
  _STEP_COMPUTE_RESULT=42

  # Job outputs
  _NEEDS_BUILD_OUT_RESULT=$_STEP_COMPUTE_RESULT  # ← ${{ steps.compute.outputs.result }}
}

job_DEPLOY() {
  # depends on: build
  echo "Build result was $_NEEDS_BUILD_OUT_RESULT"  # ← ${{ needs.build.outputs.result }}
}

# Run jobs
job_BUILD && _rc=0 || _rc=$?
if [ "$_rc" -eq 0 ]; then _NEEDS_BUILD_RESULT=success; else _NEEDS_BUILD_RESULT=failure; fi

job_DEPLOY && _rc=0 || _rc=$?
if [ "$_rc" -eq 0 ]; then _NEEDS_DEPLOY_RESULT=success; else _NEEDS_DEPLOY_RESULT=failure; fi
```

実際に動く。

```bash
$ actrun export examples/04-multi-job.yml | bash
Build result was 42
```

### 何が変換されるか

- `${{ env.VAR }}` → `$VAR`
- `${{ secrets.TOKEN }}` → `$SECRET_TOKEN`
- `${{ github.ref }}` → `$GITHUB_REF`
- `${{ steps.id.outputs.key }}` → `$_STEP_ID_KEY`
- `${{ needs.job.outputs.key }}` → `$_NEEDS_JOB_OUT_KEY`
- `echo "key=val" >> "$GITHUB_OUTPUT"` → `_STEP_ID_KEY=val`
- `echo "KEY=val" >> "$GITHUB_ENV"` → `export KEY=val`
- `actions/checkout` → `git fetch`
- `actions/setup-node` → コメント化（`mise use` / `fnm` / `nvm` を選択）
- 関数呼び出し → jq ベースのヘルパ関数

変換された行には `# ← ${{ original }}` でオリジナルの式がコメントとして残る。レビューしやすい。

### --parallel

`--parallel` をつけると、依存関係のないジョブを `&` + `wait` で並列実行する。

```bash
$ actrun export examples/33-deep-dependencies.yml --parallel | bash
lint done
build-a done
build-b done
version: 1.0.0
hash: abc123
integration done
deploy done
```

`build-a` と `build-b` が並列で走る。outputs は一時ファイル経由で受け渡す。

### reusable workflow

callee の steps を inline する。

```bash
$ actrun export examples/10-reusable-workflow/caller.yml | bash
hello from caller
```

`${{ inputs.message }}` は `$INPUT_MESSAGE` に変換される。

### 何に使えるか

- **CI デバッグ**: ワークフローの構造を bash で理解する
- **ポータビリティ**: GitHub Actions なしで同等の処理を実行する
- **教育**: GitHub Actions の式がシェルでどう表現されるかを見る

36 examples 中 32 が `export | bash` で正常実行できる。残り 3 つは意図的な `exit 1`（failure テスト）。

## ワークスペースの改善

### --worktree がデフォルトに

以前は `--local`（カレントディレクトリで実行）がデフォルトだった。便利だが、ワークフローがファイルを消したり上書きする場合がある。

今は `--worktree` がデフォルト。`git worktree add` で一時的なワーキングツリーを作り、そこで実行する。元のディレクトリは一切触らない。

```bash
# デフォルト: worktree で隔離
actrun ci.yml

# 明示的にローカル実行
actrun ci.yml --local
```

### --local の安全性改善

`--local` で `actions/checkout` を実行しても、untracked ファイルや `.git` を消さなくなった。`checkout@v5` の `clean: true`（デフォルト）は git tracked ファイルのリセットだけを行い、ユーザーの作業中ファイルは保護する。

## Prior Art

- [actionlint](https://github.com/rhysd/actionlint) — `actrun lint` の型システムとルール設計に影響を受けた
- [nektos/act](https://github.com/nektos/act) — Docker ベースのローカルランナー。actrun はホスト実行がメイン

## リンク

- GitHub: https://github.com/mizchi/actrun
- npm: https://www.npmjs.com/package/@mizchi/actrun
- 前回の記事: [actrun: GitHub Actions をローカルで回す](./introduce-ja.md)
