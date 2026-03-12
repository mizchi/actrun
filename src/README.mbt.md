# action_runner

MVP の GitHub Actions 互換 push CI ランナー向けコア API。

この package は `push` workflow の subset を parse し、`bitflow` IR に lower し、native target では host shell 上で実行できます。

- `push` trigger のフィルタ判定
- workflow YAML subset parser
- workflow/job/step 契約型
- `ActionRef` / resolver
- `bitflow` IR への lowering
- `strategy.matrix` の最小対応 (`axes` / `include` / `exclude` / mixed `axes + include` / `fail-fast` / `max-parallel`)
- matrix job に対する `needs` fan-in と aggregated `${{ needs.<job>.result }}` / `${{ needs.<job>.outputs.* }}`
- minimal job-level `if:` (`success()` default, `always()` / `failure()` / `cancelled()`, simple `github.*` / `needs.*` comparison)
- minimal step-level `if:` (`success()` default, `always()` / `failure()` / `cancelled()`)
- native host executor
- `bit` repo から push commit を materialize する runtime
- `uses: actions/checkout@*` と `uses: builtin://checkout` の最小 no-op 対応
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
- MVP 範囲外機能の明示的 reject

CLI では `action_runner .github/workflows/ci.yml --repo /path/to/repo --workspace /tmp/work --before <sha>` の形で、repo 上の commit snapshot を materialize してから実行できます。`--event /path/to/push-event.json` を渡すと GitHub push webhook payload から `PushEvent` を組み立てます。`--changed` を省略した場合は changed paths を自動計算します。`${{ github.repository }}` / `GITHUB_REPOSITORY` は `--repository` で明示 override でき、未指定なら repo root の `origin` remote URL から自動推測します。

## 例

```mbt check
///|
test {
  let workflow = new_workflow(
    "ci",
    [
      new_job("build", [
        new_run_step("install", "pnpm install"),
        new_run_step("test", "pnpm test"),
      ]),
      new_job("lint", [new_run_step("lint", "pnpm lint")], needs=["build"]),
    ],
    trigger=new_push_trigger(branches=["main"], paths=["src/*"]),
    defaults=new_run_defaults(shell=Some("bash")),
  )

  let event = new_push_event("main", ["src/lib.mbt"])
  inspect(matches_push_trigger(workflow.trigger, event), content="true")

  let src =
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: pnpm test
  let parsed = parse_workflow_yaml(src)
  let lowered = lower_push_workflow(parsed.workflow.unwrap())
  inspect(lowered.errors, content="[]")
  inspect(lowered.ir.tasks.length(), content="2")
}
```

## MVP 非対応

- `${{ ... }}` の広い context (`github` / `runner` の残り, matrix advanced, `vars`, `secrets` など)
- `pwsh` binary が存在しない環境での PowerShell workflow 実行
- reusable workflow
- job container / services

`parse_action_ref` は GitHub repo ref、local path、`docker://...`、custom registry ref を区別します。`./local-action` は workspace 上の `action.yml` / `action.yaml` を読んで composite step に展開し、`with` を `${{ inputs.* }}` に流し込みます。`prefetch_workflow_github_actions_native` は `owner/repo[/path]@ref` を `_build/action_runner/github_actions` か `ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT` 配下へ clone し、manifest が composite なら同様に展開し、`runs.using: node*` なら `runs.main` と `pre` / `post` lifecycle、`runs.using: docker` なら `runs.image` / `runs.args` / `runs.entrypoint` / `runs.pre-entrypoint` / `runs.post-entrypoint` を native executor から実行できます。prefetch が使う `git` binary は `ACTION_RUNNER_GIT_BIN`、native executor が使う `node` / `docker` binary は `ACTION_RUNNER_NODE_BIN` / `ACTION_RUNNER_DOCKER_BIN`、GitHub host は `ACTION_RUNNER_GITHUB_BASE_URL` で上書きできます。現時点で resolver は `actions/checkout`、`builtin://checkout`、`docker://...` を action task に変換し、native executor が実行できるのは `builtin` backend、local / cached GitHub composite action 展開後の `run` task、`docker://...` action、cache 済み / prefetched GitHub repo `node*` action、cache 済み / prefetched GitHub repo `runs.using: docker` action です。
