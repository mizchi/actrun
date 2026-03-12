# TODO

`action_runner` の次段階は、機能追加より先に compat test を増やして挙動を固定する。
方針は `探索 -> Red -> Green -> Refactoring` を維持し、まず GitHub Docs から読める範囲を black-box test に落とす。

## 原則

- [ ] 仕様の正本は GitHub Docs に置く
- [ ] parser / expression の補助 fixture は `actions/languageservices` を使う
- [ ] runtime 挙動の補助 fixture は `nektos/act` を使う
- [ ] unsupported は黙って無視せず、明示的な reject test にする
- [ ] 取り込む fixture には upstream URL と採用理由をコメントで残す

## Source of Truth

- Workflow syntax: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- Contexts: https://docs.github.com/en/actions/reference/workflows-and-actions/contexts
- Expressions: https://docs.github.com/en/actions/reference/workflows-and-actions/expressions
- Workflow commands: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
- `actions/languageservices`: https://github.com/actions/languageservices
- `workflow-parser/testdata/reader`: https://github.com/actions/languageservices/tree/main/workflow-parser/testdata/reader
- `expressions/testdata`: https://github.com/actions/languageservices/tree/main/expressions/testdata
- `nektos/act` runner testdata: https://github.com/nektos/act/tree/master/pkg/runner/testdata

## P0: テスト基盤

- [x] `testdata/docs/` を作り、docs 由来 workflow fixture の置き場を決める
- [x] `testdata/upstream/act/` を作り、移植した fixture の置き場を決める
- [x] `testdata/upstream/languageservices/` を作り、parser / expression fixture の置き場を決める
- [x] 1 workflow = 1 black-box test の loader を作る
- [x] `supported`, `unsupported`, `known_diff` を表現できる test metadata を決める
- [ ] upstream URL, 採用日, 期待結果を残す README を testdata 配下に置く

## P1: Docs から先にテスト化する

### Workflow Syntax

- [x] `on: push` の scalar / array / object form
- [x] `on.push.branches`
- [x] `on.push.branches-ignore`
- [x] `on.push.paths`
- [x] `on.push.paths-ignore`
- [x] workflow / job / step の `env` 優先順位
- [x] `defaults.run.shell`
- [x] `defaults.run.working-directory`
- [x] `jobs.<job_id>.needs`
- [x] `jobs.<job_id>.steps[*].id`
- [x] `jobs.<job_id>.steps[*].run`
- [x] `jobs.<job_id>.steps[*].uses`
- [x] `jobs.<job_id>.steps[*].shell`
- [x] `jobs.<job_id>.steps[*].working-directory`
- [x] `jobs.<job_id>.steps[*].env`
- [x] `jobs.<job_id>.steps[*].with`

### Contexts / Expressions

- [x] `${{ env.NAME }}` の step script 利用
- [x] `${{ env.NAME }}` の step `env:` 利用
- [x] `${{ steps.<id>.outputs.<name> }}` の後続 step 利用
- [x] workflow / job / step で同名 env があるときの「より具体的な値が勝つ」ケース
- [x] 未定義 `env.*` / `steps.*.outputs.*` の期待挙動を docs と照合して固定する

### Workflow Commands

- [x] `GITHUB_ENV` の single-line
- [x] `GITHUB_ENV` の multiline delimiter
- [x] `GITHUB_OUTPUT` の single-line
- [x] `GITHUB_OUTPUT` の multiline delimiter
- [x] `GITHUB_PATH` が「後続 step にだけ」効くこと
- [x] `GITHUB_STEP_SUMMARY` の summary 内容を docs fixture で固定する
- [x] top-level `run` step の `GITHUB_STATE` は未対応として reject test を先に置く

## P2: `actions/languageservices` fixture を取り込む

- [x] `workflow-parser/testdata/reader` から、現在の MVP 範囲に収まるケースを選定する
- [x] parser success case を `src/lib_test.mbt` か専用 compat test に移す
- [x] parser error case を「unsupported error を返す」形に合わせて移植する
- [x] `expressions/testdata` から `env` / `steps` に関係する最小 subset を移植する
- [x] languageservices と解釈がズレるものは `known_diff` として記録する

## P3: `nektos/act` fixture を移植する

- [x] `set-env-new-env-file-per-step`
  - source: https://raw.githubusercontent.com/nektos/act/master/pkg/runner/testdata/set-env-new-env-file-per-step/push.yml
- [x] `set-env-step-env-override`
  - source: https://github.com/nektos/act/tree/master/pkg/runner/testdata/set-env-step-env-override
- [x] `steps-context`
  - source: https://github.com/nektos/act/tree/master/pkg/runner/testdata/steps-context
- [x] `shells`
  - source: https://github.com/nektos/act/tree/master/pkg/runner/testdata/shells
- [x] `stepsummary`
  - source: https://github.com/nektos/act/tree/master/pkg/runner/testdata/stepsummary
- [x] 移植時に `bit` / `bitflow` 非依存の black-box test に正規化する
- [x] `act` 固有実装に引っ張られないよう、期待値は GitHub Docs と突き合わせる

## P4: テスト駆動で実装を広げる

- [x] `GITHUB_STEP_SUMMARY`
- [x] local composite action scope に閉じた最小 `GITHUB_STATE`
- [x] action lifecycle (`pre` / `main` / `post`) を含む完全な `GITHUB_STATE`
- [x] GitHub repo `node*` action の `pre` / `main` / `post` lifecycle
- [x] Docker action の `pre-entrypoint` / `post-entrypoint` lifecycle
- [x] `github.*` context の最小 subset
- [x] direct dependency に対する `needs.<job>.outputs.*` / `needs.<job>.result`
- [x] `runner.*` context の最小 subset
- [x] shell 差分の吸収 (`bash`, `sh`, `pwsh`)
- [x] local composite action 内の nested `uses`
- [x] cache 済み GitHub repo composite action の metadata 解決
- [x] GitHub repo action の remote fetch / cache fill
- [x] GitHub repo action の `node*` backend 実行
- [x] GitHub repo action の `docker` backend 実行

## 完了条件

- [ ] README に書いてある対応範囲に対して docs-based compat test が一通りある
- [ ] 主要な upstream fixture に対して `supported` / `unsupported` / `known_diff` が分類済み
- [ ] 新機能を足す前に、対応する Red test が upstream source 付きで追加される運用にする
