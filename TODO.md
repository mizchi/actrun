# TODO

compat fixture 基盤と GitHub-hosted live compat の導線は一通り入った。
次は「実 workflow の通過率をどれだけ上げるか」を基準に優先度を組み直して、`探索 -> Red -> Green -> Refactoring` で進める。

## 原則

- [ ] 仕様の正本は GitHub Docs に置く
- [ ] parser / expression の補助 fixture は `actions/languageservices` を使う
- [ ] runtime 挙動の補助 fixture は `nektos/act` を使う
- [ ] unsupported は黙って無視せず、明示的な reject test にする
- [ ] 取り込む fixture には upstream URL と採用理由を metadata / README に残す

## Source of Truth

- Workflow syntax: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- Contexts: https://docs.github.com/en/actions/reference/workflows-and-actions/contexts
- Expressions: https://docs.github.com/en/actions/reference/workflows-and-actions/expressions
- Workflow commands: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
- `actions/languageservices`: https://github.com/actions/languageservices
- `workflow-parser/testdata/reader`: https://github.com/actions/languageservices/tree/main/workflow-parser/testdata/reader
- `expressions/testdata`: https://github.com/actions/languageservices/tree/main/expressions/testdata
- `nektos/act` runner testdata: https://github.com/nektos/act/tree/master/pkg/runner/testdata

## 既にできていること

- [x] docs / languageservices / act fixture の compat test 基盤
- [x] live compat artifact compare (`gha-compat-live`, `gha-compat-compare`)
- [x] `checkout`, `artifact`, `cache`, local/remote action lifecycle の MVP
- [x] `strategy.matrix` の P0 最小 slice
  - axes-only と include-only の展開
  - `${{ matrix.* }}` の `runs-on` / `run` / `env` / `with` / shell / cwd 置換
  - docs fixture と E2E 追加

## P0: 実 workflow 通過率を先に上げる

- [x] `strategy.matrix` の最小対応
- [x] `strategy.matrix.exclude`
- [x] `strategy.matrix` の axes + include 混在
- [x] `strategy.matrix.fail-fast` の実行意味論
- [x] `strategy.matrix.max-parallel`
- [x] matrix job に対する `needs` / `needs.<job>.result` / `needs.<job>.outputs.*`
- [x] matrix job outputs の意味論
- [x] job-level `if:`
- [ ] step-level `if:` の `always()` / `failure()` / `cancelled()`
- [ ] `continue-on-error`
- [ ] `steps.<id>.outcome` / `steps.<id>.conclusion`
- [ ] `actions/checkout` の `fetch-depth`
- [ ] `actions/checkout` の `ref`
- [ ] `actions/checkout` の `clean`
- [ ] `actions/checkout` の `submodules`
- [ ] `actions/setup-node` の最小 builtin
  - `node-version`
  - `cache`
  - `registry-url`

## P1: expressions / builtins の互換率を上げる

- [ ] expression function の最小 subset
  - `contains`
  - `startsWith`
  - `endsWith`
  - `fromJSON`
  - `toJSON`
  - `hashFiles`
- [ ] `${{ vars.* }}` の最小対応
- [ ] `${{ secrets.* }}` の最小対応
- [ ] `permissions` の parse / contract / reject policy 明確化
- [ ] `actions/cache` の拡張
  - `restore-keys`
  - `lookup-only`
  - `fail-on-cache-miss`
- [ ] `actions/upload-artifact` / `actions/download-artifact` の拡張
  - glob / directory
  - `if-no-files-found`
  - `overwrite`
  - `merge-multiple`

## P2: workflow 構成要素を広げる

- [ ] reusable workflow (`workflow_call`)
- [ ] workflow inputs / outputs
- [ ] job container
- [ ] services
- [ ] concurrency の parse / contract / reject policy 明確化

## P3: runner 独自価値

- [ ] Wasm backend contract
- [ ] Wasm runner adapter
- [ ] backend capability model (`host` / `docker` / `wasm`)
- [ ] custom registry action の backend 解決強化

## 完了条件

- [ ] README に書いてある対応範囲に対して docs-based compat test が一通りある
- [ ] 主要な upstream fixture に対して `supported` / `unsupported` / `known_diff` が分類済み
- [ ] 新機能を足す前に、対応する Red test が upstream source 付きで追加される運用にする
