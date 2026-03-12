# act fixtures

`nektos/act` 由来の fixture を置く。
移植時は upstream URL と `known_diff` の有無を `fixture.txt` に残す。

現時点で vendoring している case:

- `set-env-new-env-file-per-step`
- `set-env-step-env-override`
- `steps-context-outcome`
- `steps-context-conclusion`
- `stepsummary`
- `shells-bash`
- `shells-sh`
- `shells-defaults`
- `shells-custom`

方針:

- upstream workflow をそのまま使えないものは、GitHub Docs と現在の MVP 対応範囲に合わせて black-box fixture に正規化する
- local action や workflow command のように runner 依存の挙動は、remote action 依存を外して最小ケースに潰す
- `shells` は container variant と環境依存の `pwsh` / `python` を外し、host で再現できる subset に絞る
- `shells-sh` は `/bin/sh` 実装差分に依存しないよう、POSIX script が走ることの確認に正規化する

known diff:

- `steps-context-outcome`
- `steps-context-conclusion`
  - upstream は `continue-on-error` と `steps.*.outcome` / `steps.*.conclusion` を前提に通る
  - `action_runner` でも同じ前提で supported として回す
- `shells-custom`
  - `action_runner` でも `{0}` 付き custom shell template 自体は実行できる
  - ただしこの upstream fixture は `pwsh` binary を前提にしており、host 環境に `pwsh` が無いと失敗する
