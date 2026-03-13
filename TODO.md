# TODO

現在の目標は、`action_runner` を「ローカルで GitHub Actions workflow を再現し、標準 actions を一通り扱え、`gh` 互換の CLI で制御できる runner」に持っていくこと。

優先順位は次の 3 本柱で切る。

1. GitHub 標準 actions の互換率を上げる
2. 同じ workflow を `worktree` / `/tmp` / `docker` で安定して実行できるようにする
3. 実行・観測・artifact/cache 操作を `gh` 互換の CLI で制御できるようにする

## ゴール

- [ ] 主要な GitHub 標準 actions を local で再現できる
- [ ] 同じ workflow が `worktree` / `/tmp` / `docker` の各 substrate で同じ結果を返す
- [ ] run / logs / artifacts / cache を `gh` 互換の subcommand で扱える
- [ ] README に書いた対応範囲が docs/upstream/live compat で裏付けられている

## 設計方針

- [ ] 仕様の正本は GitHub Docs に置く
- [ ] parser / expression の補助 fixture は `actions/languageservices`
- [ ] runtime 挙動の補助 fixture は `nektos/act`
- [ ] unsupported は黙って無視せず、明示 reject
- [ ] 新機能は `upstream source 付き Red -> Green -> Refactor`
- [ ] feature claim は docs-based compat または live compat で裏付ける

## Source of Truth

- Workflow syntax: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- Contexts: https://docs.github.com/en/actions/reference/workflows-and-actions/contexts
- Expressions: https://docs.github.com/en/actions/reference/workflows-and-actions/expressions
- Workflow commands: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
- `actions/languageservices`: https://github.com/actions/languageservices
- `workflow-parser/testdata/reader`: https://github.com/actions/languageservices/tree/main/workflow-parser/testdata/reader
- `expressions/testdata`: https://github.com/actions/languageservices/tree/main/expressions/testdata
- `nektos/act` runner testdata: https://github.com/nektos/act/tree/master/pkg/runner/testdata

## 現在地

- [x] docs / languageservices / act fixture の compat 基盤
- [x] GitHub-hosted live compat (`gha-compat-live`, `gha-compat-compare`)
- [x] `checkout`, `artifact`, `cache`, `setup-node`, reusable workflow, job `container`, `services` の最小対応
- [x] local / remote action lifecycle と matrix / `if` / file commands の主要 slice
- [x] Wasm backend contract / adapter と backend capability model

## P0: 実行基盤を固める

「どこで実行するか」を先に固定する。ここが曖昧だと actions 互換も CLI もぶれる。

- [x] run record の永続化
  - [x] `_build/action_runner/runs/<run-id>/run.json` の最小保存
  - [x] `_build/action_runner/runs/<run-id>/` の layout を固定
  - [x] `run.json` / step 状態 / task 状態 / exit code / task log path を保存
  - [x] step log / summary を保存
  - [x] job 状態 / artifact index / cache index を保存
  - [x] `timestamps` を保存
- [ ] workspace substrate の明確化
  - [x] `--workspace-mode` contract (`local=worktree`, `repo=tmp` の default)
  - [ ] `--workspace-mode worktree`
  - [ ] `--workspace-mode tmp`
  - [ ] `--workspace-mode docker`
  - [ ] 各 mode の cleanup / isolation policy を固定
- [x] local injection point を CLI flag に昇格
  - [x] `--run-root`
  - [x] `--artifact-root`
  - [x] `--cache-root`
  - [x] `--github-action-cache-root`
  - [x] `--registry-root`
  - [x] `--wasm-action-root`
- [ ] substrate parity E2E
  - [ ] 同一 workflow を `worktree` / `/tmp` / `docker` で流す共通 scenario 群
  - [ ] artifact / cache / summary / logs が substrate を跨いで一致することを確認
  - [ ] repo mode / `--event` / `head_commit` fallback も substrate matrix に入れる

## P1: `gh` 互換 CLI を作る

今の positional CLI を product にする段階。最終的には local runner を `gh` ライクに操作できるようにする。

- [ ] command family の導入
  - [x] `action_runner workflow list`
  - [x] `action_runner workflow run <workflow>`
  - [x] `action_runner run list`
  - [x] `action_runner run view <run-id>`
  - [x] `action_runner run watch <run-id>`
  - [x] `action_runner run logs <run-id>`
  - [x] `action_runner run download <run-id>`
  - [x] `action_runner artifact list <run-id>`
  - [x] `action_runner artifact download <run-id>`
  - [x] `action_runner cache list`
  - [x] `action_runner cache prune`
- [ ] 現行 CLI との互換レイヤ
  - [ ] 既存の `action_runner <workflow.yml> ...` を `workflow run` に寄せる
  - [ ] repo mode / event mode / substrate mode を subcommand に整理する
- [ ] CLI 出力 contract
  - [ ] `--json` を全 read command に追加
  - [ ] run state / artifact metadata / cache metadata の JSON schema を固定
  - [ ] non-zero exit code と run state の対応を固定
- [ ] CLI black-box
  - [x] run store を前提にした `view/watch/logs/download` E2E
  - [ ] `gh run` / `gh workflow` の naming に寄せた usage docs

## P2: GitHub 標準 actions を広げる

方針は 2 段階。

1. deterministic に再現したいものは builtin / emulator にする
2. builtin にしない official action は remote `node` action として通し、smoke/live compat で保証する

### P2-A: builtin 優先 actions

- [ ] `actions/checkout`
  - [ ] `lfs`
  - [ ] `persist-credentials: false`
  - [ ] `fetch-tags`
  - [ ] `show-progress`
  - [ ] `set-safe-directory`
  - [ ] token / ssh-key / ssh-known-hosts の policy 決定
- [ ] `actions/upload-artifact` / `actions/download-artifact`
  - [ ] `pattern`
  - [ ] `artifact-ids`
  - [ ] `retention-days`
  - [ ] `compression-level`
  - [ ] `include-hidden-files`
- [ ] `actions/cache`
  - [ ] `enableCrossOsArchive`
  - [ ] cache version semantics
  - [ ] path list normalization
  - [ ] failure/cancel 時の post-save edge case
- [ ] `actions/setup-node`
  - [ ] `node-version-file`
  - [ ] `check-latest`
  - [ ] package-manager-cache auto detection
  - [ ] `always-auth` / `scope` / `.npmrc` nuance
- [ ] `actions/github-script`
  - [ ] builtin にするか remote official node action 扱いにするか決める
  - [ ] どちらにせよ local E2E と live compat を付ける

### P2-B: official actions の実行保証

- [ ] official node action coverage policy を決める
  - [ ] builtin 化するもの
  - [ ] remote fetch + node 実行で保証するもの
- [ ] smoke/live compat を張る official actions
  - [ ] `actions/setup-python`
  - [ ] `actions/setup-go`
  - [ ] `actions/setup-java`
  - [ ] `actions/setup-dotnet`
  - [ ] `actions/setup-ruby`

## P3: workflow/runtime 互換を締める

- [ ] reusable workflow の広い互換対応
  - [ ] caller matrix + reusable outputs の live compat
  - [ ] nested reusable workflow の docs/live compat matrix
  - [ ] remote reusable workflow + `secrets: inherit` の main branch live compat
- [ ] container / services の hardening
  - [ ] builtin action coverage matrix を container job で揃える
  - [ ] service `volumes` / `options` / `credentials` semantics
  - [ ] service log capture と run store 保存
- [ ] shell / host 差分
  - [ ] `pwsh` 実行環境差分
  - [ ] shell template compatibility の fixture 拡張

## P4: registry / backend を product にする

- [ ] custom registry action の remote fetch / protocol 解決
- [ ] registry cache layout / versioning / auth policy
- [ ] Wasm backend の広い互換対応
  - [ ] env / input / output contract
  - [ ] pre/post lifecycle policy
  - [ ] artifact / cache integration
- [ ] backend selection policy を CLI / config から制御可能にする

## P5: 互換性運用を固定する

- [ ] README の feature claim と docs-based compat の対応表を作る
- [ ] fixture metadata から support matrix を自動生成する
- [ ] 新機能テンプレートを用意する
  - [ ] source URL
  - [ ] Red fixture
  - [ ] Green 実装
  - [ ] live compat の有無
- [ ] release checklist
  - [ ] local `just test`
  - [ ] local `just e2e`
  - [ ] main branch live compat
  - [ ] CLI contract diff

## 完了条件

- [ ] `gh` 互換 CLI で local run / logs / artifacts / cache を操作できる
- [ ] 主要 workflow が `worktree` / `/tmp` / `docker` で同じ結果になる
- [ ] GitHub 標準 actions の優先セットに docs/E2E/live compat が揃う
- [ ] README に書いた対応範囲が compat test で裏付けられている
