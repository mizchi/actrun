# action_runner

`mizchi/moonbit-template` を土台にした新規 MoonBit project。

現時点のスコープは GitHub Actions 互換ランナーの MVP で、`push` trigger の簡単な CI を parse して `bitflow` に lower し、native target では host shell 上で実行できます。`bit` repo から `after_sha` の作業ツリーを scratch workspace に materialize する runtime も入りました。

## 現在あるもの

- `push` trigger filter 判定
- workflow YAML subset parser
- workflow/job/step の契約型
- `bitflow` IR への lowering
- native host executor
- `bit` repo から push commit を materialize する runtime
- `ActionRef` / resolver による `uses:` 解決
- `uses: actions/checkout@*` と `uses: builtin://checkout` の最小 builtin 対応
- `actions/checkout` の `path` / `sparse-checkout` / `sparse-checkout-cone-mode` / `fetch-depth` / `ref` / `clean` / `submodules` の最小 builtin 対応
- `strategy.matrix` の最小対応 (`axes` / `include` / `exclude` / mixed `axes + include` / `fail-fast` / `max-parallel`, `${{ matrix.* }}` の `runs-on` / `run` / `env` / `with`)
- matrix job に対する `needs` fan-in と aggregated `${{ needs.<job>.result }}` / `${{ needs.<job>.outputs.* }}`
- minimal job-level `if:` (`success()` default, `always()` / `failure()` / `cancelled()`, simple `github.*` / `needs.*` comparison)
- minimal step-level `if:` (`success()` default, `always()` / `failure()` / `cancelled()`)
- minimal expression functions (`contains`, `startsWith`, `endsWith`, `fromJSON`, `toJSON`, `hashFiles`)
- `${{ vars.* }}` の最小対応 (`ACTION_RUNNER_VAR_<NAME>` から供給)
- `${{ secrets.* }}` の最小対応 (`ACTION_RUNNER_SECRET_<NAME>` から供給, `if:` 直接参照は未対応)
- workflow/job `permissions` の parse / contract 対応と lowering reject
- step-level `continue-on-error`
- `${{ steps.<id>.outcome }}` / `${{ steps.<id>.conclusion }}` の最小対応
- `uses: actions/upload-artifact@*` / `uses: actions/download-artifact@*` の最小 builtin emulator (`directory`, wildcard path, `if-no-files-found`, `overwrite`, download-all directory mode)
- `uses: actions/cache/save@*` / `uses: actions/cache/restore@*` の最小 builtin emulator
- `uses: actions/cache@*` の restore + deferred post-save builtin emulator (`restore-keys`, `lookup-only`, `fail-on-cache-miss` 対応)
- `uses: actions/setup-node@*` の最小 builtin emulator (`node-version`, `cache: npm`, `registry-url`)
- native prefetch による `owner/repo[/path]@ref` GitHub repo action の remote fetch / cache fill
- cache 済み `owner/repo[/path]@ref` GitHub repo composite action の workspace-aware 展開
- cache 済み / prefetched `owner/repo[/path]@ref` GitHub repo `node*` action の最小実行
- cache 済み / prefetched `owner/repo[/path]@ref` GitHub repo `runs.using: docker` action の最小実行
- `uses: ./path` の local composite action 展開
- local composite action 内の nested `uses` 展開
- local composite action の `with` と `${{ inputs.* }}` の最小対応
- `CI`, `GITHUB_ACTIONS`, `GITHUB_WORKSPACE`, `GITHUB_WORKFLOW`, `GITHUB_JOB` の基本 env 注入
- `GITHUB_ACTION` の最小対応
- cached / prefetched GitHub action 向けの `GITHUB_ACTION_REPOSITORY`, `GITHUB_ACTION_REF` 注入
- local composite action inner step への `GITHUB_ACTION_PATH` 注入
- local composite action inner step 間に閉じた `GITHUB_STATE` の最小対応
- cache 済み / prefetched GitHub repo `node*` action の `pre` / `main` / `post` lifecycle と `GITHUB_STATE` 共有
- cache 済み / prefetched GitHub repo `runs.using: docker` action の `pre-entrypoint` / `entrypoint` / `post-entrypoint` lifecycle と `GITHUB_STATE` 共有
- `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY` の file command 対応
- native `run` step における `${{ env.* }}` の最小対応
- direct dependency に対する `${{ needs.<job>.outputs.<name> }}`, `${{ needs.<job>.result }}` の最小対応
- push workflow における `${{ github.ref }}`, `${{ github.ref_name }}`, `${{ github.sha }}` と `GITHUB_REF`, `GITHUB_REF_NAME`, `GITHUB_SHA` の最小対応
- push workflow における `${{ github.event_name }}` と `GITHUB_EVENT_NAME` の最小対応
- push workflow における `${{ github.repository }}` と `GITHUB_REPOSITORY` の最小対応
- push workflow における `${{ github.repository_owner }}` と `GITHUB_REPOSITORY_OWNER` の最小対応
- push workflow における `${{ github.actor }}` と `GITHUB_ACTOR` の最小対応
- native `run` step における `${{ github.workflow }}`, `${{ github.job }}`, `${{ github.workspace }}` の最小対応
- native `run` step における `${{ github.action }}` の最小対応
- cached / prefetched GitHub action 文脈での `${{ github.action_repository }}`, `${{ github.action_ref }}` の最小対応
- local composite action inner step における `${{ github.action_path }}` の最小対応
- native `run` step における `${{ runner.os }}`, `${{ runner.arch }}`, `${{ runner.temp }}`, `${{ runner.environment }}` の最小対応
- file-based な `bash` / `sh` / `pwsh` 実行と `{0}` 付き custom shell template の最小対応
- job 内の後続 step に対する `${{ steps.<id>.outputs.<name> }}` の最小対応
- `uses: docker://...` の native docker 実行
- MVP 非対応機能の reject
- `permissions` は parse して contract に保持するが、MVP では lowering で reject する

## まだないもの

- `${{ ... }}` の広い context (`github` / `runner` の残り, `vars`, `secrets` など)
- `pwsh` binary が存在しない環境での PowerShell workflow 実行
- Wasm backend

## Action Namespace

- GitHub 互換 action ref は `owner/repo@ref` として parse
- local path (`./action`), `docker://image`, custom registry (`bit://std/cache@v1`) も `ActionRef` として parse
- `./local-action` は workspace 上の `action.yml` / `action.yaml` を読んで composite step に展開し、`with` を `${{ inputs.* }}` に流し込む
- `owner/repo[/path]@ref` は native prefetch が repo を cache root に clone し、manifest が composite なら local action と同様に展開する
- 現在の resolver は `actions/checkout@*`, `actions/upload-artifact@*`, `actions/download-artifact@*`, `actions/cache@*`, `actions/cache/save@*`, `actions/cache/restore@*`, `actions/setup-node@*`, `builtin://checkout`, `docker://...` を action task に変換する
- native executor が実際に実行できるのは `builtin` backend、local / cached GitHub composite action 展開後の `run` task、`docker://...` action、cache 済み / prefetched GitHub repo `node*` action、cache 済み / prefetched GitHub repo `runs.using: docker` action です。GitHub repo `node*` action では `pre` / `main` / `post`、GitHub repo `runs.using: docker` action では `pre-entrypoint` / `entrypoint` / `post-entrypoint` が job の最後に post cleanup をぶら下げる形で走ります
- backend は namespace と分離していて、今の checkout は `builtin` backend の no-op step として扱う
- GitHub action cache root は既定で `_build/action_runner/github_actions`、`ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT` で上書きできる
- prefetch が使う `git` binary は `ACTION_RUNNER_GIT_BIN`、native executor が使う `node` / `docker` binary は `ACTION_RUNNER_NODE_BIN` / `ACTION_RUNNER_DOCKER_BIN`、`setup-node` builtin が使う binary は `ACTION_RUNNER_SETUP_NODE_BIN`、`${{ vars.* }}` は `ACTION_RUNNER_VAR_<NAME>`、`${{ secrets.* }}` は `ACTION_RUNNER_SECRET_<NAME>`、GitHub host は `ACTION_RUNNER_GITHUB_BASE_URL` で上書きできる

## Quick Commands

```bash
just           # check + test
just fmt       # format code
just test      # run tests
just e2e       # run black-box CLI scenarios
just gha-compat-dispatch compat-checkout-artifact.yml
just gha-compat-download 123456789
just gha-compat-compare compat-checkout-artifact.yml _build/gha-compat/123456789
just gha-compat-live compat-checkout-artifact.yml
just run path/to/workflow.yml
moon run src/main --target native -- .github/workflows/ci.yml --repo /path/to/repo --workspace /tmp/action-runner-work --before <old_sha>
moon run src/main --target native -- .github/workflows/ci.yml --repo /path/to/repo --repository owner/repo   # 明示 override
moon run src/main --target native -- .github/workflows/ci.yml --event /path/to/push-event.json
just info      # generate type definition files
```

`--event` を渡すと GitHub の push webhook payload JSON から `ref` / `before` / `after` / `repository` / `sender` / changed paths を読みます。CLI の `--ref` / `--before` / `--after` / `--changed` / `--repository` は event JSON より優先されます。`--repo` mode では `bit` runtime が `after_sha` の tree を workspace に materialize してから workflow を実行します。lowering 前には GitHub repo action の native prefetch も走ります。`--changed` を省略した場合は `bit` diff で changed paths を自動計算します。正確な push range を使いたい場合は `--before` を渡します。`${{ github.repository }}` / `GITHUB_REPOSITORY` は、`--repository` があればそれを使い、未指定なら repo root の `origin` remote URL から自動推測します。

`just e2e` は build 済み CLI 実行ファイルを直接叩いて、`testdata/e2e` の black-box scenario を順に流します。現時点では local push workflow、local composite action、trigger skip、file commands、artifact action roundtrip、artifact directory/wildcard + download-all、cache action roundtrip、cache auto-save roundtrip、cache `restore-keys`、cache `lookup-only`、cache `fail-on-cache-miss`、checkout `path + sparse-checkout`、checkout `fetch-depth`、checkout `ref`、checkout `clean`、checkout `submodules`、`setup-node` の `node-version + registry-url`、`setup-node cache: npm`、expression string functions、expression JSON functions、`hashFiles()`、`vars.*`、`secrets.*`、matrix include、matrix exclude、matrix mixed include、matrix max-parallel、matrix fail-fast、matrix needs/output aggregation、failure 後の downstream job skip、job-level `if: always()`、step-level `if: always()/failure()/cancelled()`、step-level `continue-on-error`、`${{ steps.<id>.outcome }}` / `${{ steps.<id>.conclusion }}`、invalid / unsupported matrix reject、`--event` に対する CLI override、`head_commit` fallback、direct `docker://...` action、remote composite prefetch、nested remote composite prefetch、nested remote composite cache hit、remote composite cache hit、remote `node` / `docker` lifecycle、remote `node` / `docker` failure cleanup、cache 済み remote `node` / `docker` failure cleanup、nested remote `node` / `docker` prefetch、nested remote `node` / `docker` cache hit、cache 済み remote `node` / `docker` action、`bit` repo materialization、repo mode の `needs.outputs`、repo mode の job-scoped file commands、repo mode の multi-job summary、repo mode の `needs.outputs + GITHUB_STEP_SUMMARY`、repo mode の remote `node` / `docker` failure cleanup、repo mode の cache 済み remote `node` / `docker` failure cleanup、`--repo + --event` の実行経路、repo mode の `head_commit` fallback、repo origin からの repository auto-detect、event payload に repository が無い場合の repo auto-detect、repo mode での `head_commit` fallback + repository auto-detect を確認します。

GitHub hosted runner との実値比較用に [compat-checkout-artifact.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-checkout-artifact.yml)、[compat-checkout-sparse.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-checkout-sparse.yml)、[compat-checkout-fetch-depth.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-checkout-fetch-depth.yml)、[compat-checkout-clean.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-checkout-clean.yml)、[compat-setup-node-basic.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-setup-node-basic.yml)、[compat-setup-node-cache-npm.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-setup-node-cache-npm.yml)、[compat-artifact-multi-job.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-artifact-multi-job.yml)、[compat-artifact-glob-directory.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-artifact-glob-directory.yml)、[compat-artifact-if-no-files-found.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-artifact-if-no-files-found.yml)、[compat-artifact-overwrite.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-artifact-overwrite.yml)、[compat-cache-roundtrip.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-cache-roundtrip.yml)、[compat-cache-auto-save.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-cache-auto-save.yml)、[compat-cache-restore-keys.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-cache-restore-keys.yml)、[compat-cache-lookup-only.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-cache-lookup-only.yml)、[compat-cache-fail-on-cache-miss.yml](/Users/mz/ghq/github.com/mizchi/action_runner/.github/workflows/compat-cache-fail-on-cache-miss.yml) を追加しています。どれも `workflow_dispatch` で起動でき、観測値を artifact に保存します。`just gha-compat-dispatch <workflow>` で起動して、run id が分かったら `just gha-compat-download <run_id>` で artifact を回収し、`just gha-compat-compare <workflow> <download-dir>` で local emulator と比較できます。repo を push 済みなら `just gha-compat-live <workflow>` で `dispatch -> wait -> download -> compare` をまとめて実行できます。

## 設計メモ

- `src/lib.mbt`: 契約型
- `src/parser.mbt`: workflow YAML parser
- `src/trigger.mbt`: `push` trigger matcher
- `src/lowering.mbt`: `bitflow` IR への変換と local composite action 展開
- `src/executor.mbt`: native host executor
- `src/runtime.mbt`: `bit` repo から workspace を materialize
- `src/main/main.mbt`: workflow を parse/lower/execute する最小 CLI
- `testdata/`: compat fixture の置き場

次段階ではより広い context、PowerShell 実行環境差分、Wasm backend を足していく想定です。
