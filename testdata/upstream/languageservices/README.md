# actions-languageservices fixtures

`actions/languageservices` 由来の parser / expression fixture を置く。

現時点で vendoring している reader success case:

- `events-single.yml`
- `workflow-env.yml`
- `workflow-defaults.yml`
- `job-needs.yml`
- `step-id.yml`

error / diff case:

- `errors-step-run-missing.yml`
- `errors-step-uses-missing.yml`
- `errors-step-uses-syntax.yml`

expression-derived case:

- `expr-env-basic`
- `expr-env-case-insensitive`
- `expr-step-output-basic`
- `expr-step-output-case-insensitive`

選定基準:

- `push` trigger の MVP subset に収まる
- `workflow_dispatch` や reusable workflow を含まない
- `github.*` / `vars.*` の未実装 expression 展開に依存しない
- `expressions/testdata` は workflow runner で直接消費できないので、対応する workflow fixture に正規化している

known diff:

- `errors-step-uses-missing.yml`
  - upstream は `with` 単独を `uses` 欠落として報告する
  - `actrun` は `run` / `uses` のどちらも無い step として lowering error にまとめる
- `errors-step-uses-syntax.yml`
  - upstream は `$$docker://...` や `...docker://...` を syntax error にする
  - `actrun` は custom registry scheme を許すため unsupported action として扱う
  - upstream では有効な `actions/aws/ec2@main` と local action も、MVP では未対応として error に落ちる
  - `docker://` 空 image も upstream の sample output には出ないが、`actrun` では parse error にする
