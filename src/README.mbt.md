# action_runner

MVP の GitHub Actions 互換 push CI ランナー向けコア API。

この package は `push` workflow の subset を parse し、`bitflow` IR に lower し、native target では host shell 上で実行できます。

- `push` trigger のフィルタ判定
- workflow YAML subset parser
- workflow/job/step 契約型
- `ActionRef` / resolver
- `bitflow` IR への lowering
- `workflow list` の最小 read-only CLI
- `workflow run` の最小 subcommand
- `strategy.matrix` の最小対応 (`axes` / `include` / `exclude` / mixed `axes + include` / `fail-fast` / `max-parallel`)
- matrix job に対する `needs` fan-in と aggregated `${{ needs.<job>.result }}` / `${{ needs.<job>.outputs.* }}`
- minimal job-level `if:` (`success()` default, `always()` / `failure()` / `cancelled()`, simple `github.*` / `needs.*` comparison)
- minimal step-level `if:` (`success()` default, `always()` / `failure()` / `cancelled()`)
- minimal expression functions (`contains`, `startsWith`, `endsWith`, `fromJSON`, `toJSON`, `hashFiles`)
- `${{ vars.* }}` の最小対応 (`ACTION_RUNNER_VAR_<NAME>` から供給)
- `${{ secrets.* }}` の最小対応 (`ACTION_RUNNER_SECRET_<NAME>` から供給, `if:` 直接参照は未対応)
- `workflow_call` trigger と `inputs` / `outputs` / `secrets` の parse / contract 対応
- local / remote reusable workflow (`jobs.<job_id>.uses`) の最小実行 (`with`, `workflow_call.inputs` の `required` / implicit default / type validation, caller job の `strategy.matrix`, matrix caller 上の `workflow_call.outputs` 集約, `workflow_call.outputs`, `secrets` mapping, `secrets: inherit`, nested reusable workflow, remote reusable workflow 内 local action)
- job `container` の string / mapping form の parse / contract 対応と、`run` step / GitHub repo `node*` action を docker adapter で実行する最小対応
- job `container` 配下の GitHub repo / direct `runs.using: docker` action を sibling container として実行し、job container の volume mount を共有する最小対応
- job `container` 配下で `actions/checkout@*` が host 側に materialize した workspace を後続 container `run` step から見える形で扱う最小対応
- job `container` 配下で `actions/upload-artifact@*` / `actions/download-artifact@*` の roundtrip を後続 container `run` step から扱う最小対応
- job `services` の mapping form の parse / contract 対応、service container の最小 lifecycle 実行、`${{ job.services.<id>.ports[...] }}` context、health check wait、job `container` との docker network 共有の最小対応
- workflow/job `permissions` / `concurrency` の parse / contract 対応と lowering reject
- step-level `continue-on-error`
- `${{ steps.<id>.outcome }}` / `${{ steps.<id>.conclusion }}` の最小対応
- native host executor
- CLI run store の最小対応 (`--run-root`, `_build/action_runner/runs/<run-id>/run.json`, `jobs.json`, `artifacts.json`, `caches.json`, `tasks/*.stdout.log|stderr.log|summary.md`, jobs/artifacts/caches index, timestamps, `run list`, `run view`, `run watch`, `run logs`, `run download`, `artifact list`, `artifact download`, `cache list`, `cache prune`)
- local injection point の CLI flag 対応 (`--artifact-root`, `--cache-root`, `--github-action-cache-root`, `--registry-root`, `--wasm-action-root`)
- `bit` repo から push commit を materialize する runtime
- `uses: actions/checkout@*` と `uses: builtin://checkout` の最小 builtin 対応
- `actions/checkout` の `path` / `sparse-checkout` / `sparse-checkout-cone-mode` / `fetch-depth` / `ref` / `clean` / `submodules` の最小 builtin 対応
- `uses: actions/upload-artifact@*` / `uses: actions/download-artifact@*` の最小 builtin 対応 (`directory`, wildcard path, `if-no-files-found`, `overwrite`, download-all directory mode, `merge-multiple`)
- `uses: actions/setup-node@*` の最小 builtin 対応 (`node-version`, `cache: npm`, `registry-url`)
- job `container` 配下で `actions/setup-node@*` が PATH shim と output を後続 `run` step に伝播する最小対応
- `uses: actions/cache@*` / `actions/cache/restore@*` の `restore-keys`, `lookup-only`, `fail-on-cache-miss` 対応
- job `container` 配下で `actions/cache@*` の miss -> deferred save -> next job restore を後続 container `run` step から扱う最小対応
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

CLI では `action_runner workflow list --repo /path/to/repo` で `.github/workflows/*.yml|*.yaml` を列挙できます。`name` が空なら file stem を fallback に使います。`action_runner workflow run .github/workflows/ci.yml` は従来の `action_runner .github/workflows/ci.yml` と同じ実行経路を subcommand で呼ぶ入口です。`action_runner .github/workflows/ci.yml --repo /path/to/repo --workspace /tmp/work --before <sha>` の形で、repo 上の commit snapshot を materialize してから実行できます。`--event /path/to/push-event.json` を渡すと GitHub push webhook payload から `PushEvent` を組み立てます。`--changed` を省略した場合は changed paths を自動計算します。`${{ github.repository }}` / `GITHUB_REPOSITORY` は `--repository` で明示 override でき、未指定なら repo root の `origin` remote URL から自動推測します。`--run-root` を渡すと local run record の保存先を上書きでき、現時点では `<run-root>/run-<n>/run.json`, `jobs.json`, `artifacts.json`, `caches.json` と `tasks/*.stdout.log|stderr.log|summary.md` を保存し、`run.json` には `started_at_ms` / `finished_at_ms` と job 状態、artifact/cache index も含みます。`action_runner run list` は保存済み run を新しい順に列挙し、`action_runner run view <run-id>` は run store を要約表示し、`--json` 付きなら `run.json` をそのまま返します。`action_runner run watch <run-id>` は run store が終端状態になるまで poll し、完了時に `run view` と同じ要約、`--json` 付きなら `run.json` を返します。`action_runner run logs <run-id> --task <task-id>` は保存済み task log / summary を読み戻します。`action_runner run download <run-id>` はその run の全 artifact を `<dir>/<artifact-name>/...` に展開します。`action_runner artifact list <run-id>` はその run の artifact index を列挙し、`action_runner artifact download <run-id> --name <artifact>` は保存済み artifact を指定 directory に展開します。`action_runner cache list` は cache root 配下の workspace ごとの cache key と file 一覧を列挙し、`action_runner cache prune --key <cache-key>` は一致する cache entry を削除します。`--artifact-root` / `--cache-root` は builtin artifact/cache store の保存先を、`--github-action-cache-root` / `--registry-root` / `--wasm-action-root` は remote action cache / custom registry / wasm module root をそれぞれ上書きします。`--workspace-mode` は contract だけ先に入っていて、local workflow 実行では `worktree`、`--repo` 実行では `tmp` が default です。

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

- `pwsh` binary が存在しない環境での PowerShell workflow 実行
- reusable workflow の広い互換対応
- custom registry action の remote fetch / registry protocol 解決

`parse_action_ref` は GitHub repo ref、local path、`docker://...`、custom registry ref を区別します。custom registry action (`bit://std/cache@v1`) は `ACTION_RUNNER_ACTION_REGISTRY_ROOT/<scheme>/<name>/<version>` 配下の `action.yml` / `action.yaml` から manifest を解決します。`wasm://name@version` は Wasm backend contract として parse / resolve され、native executor は `ACTION_RUNNER_WASM_BIN` と `ACTION_RUNNER_WASM_ACTION_ROOT` を使って file-based Wasm module を実行できます。`./local-action` は workspace 上の `action.yml` / `action.yaml` を読んで composite step に展開し、`with` を `${{ inputs.* }}` に流し込みます。`prefetch_workflow_github_actions_native` は `owner/repo[/path]@ref` を `_build/action_runner/github_actions` か `ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT` 配下へ clone し、manifest が composite なら同様に展開し、`runs.using: node*` なら `runs.main` と `pre` / `post` lifecycle、`runs.using: docker` なら `runs.image` / `runs.args` / `runs.entrypoint` / `runs.pre-entrypoint` / `runs.post-entrypoint` を native executor から実行できます。prefetch が使う `git` binary は `ACTION_RUNNER_GIT_BIN`、native executor が使う `node` / `docker` / `wasm` binary は `ACTION_RUNNER_NODE_BIN` / `ACTION_RUNNER_DOCKER_BIN` / `ACTION_RUNNER_WASM_BIN`、`setup-node` builtin が使う binary は `ACTION_RUNNER_SETUP_NODE_BIN`、`${{ vars.* }}` は `ACTION_RUNNER_VAR_<NAME>`、`${{ secrets.* }}` は `ACTION_RUNNER_SECRET_<NAME>`、GitHub host は `ACTION_RUNNER_GITHUB_BASE_URL` で上書きできます。現時点で resolver は `actions/checkout`、`actions/upload-artifact`、`actions/download-artifact`、`actions/cache*`、`actions/setup-node`、`builtin://checkout`、`docker://...`、`wasm://...` を action task に変換し、native executor が実行できるのは `builtin` backend、local / cached GitHub composite action 展開後の `run` task、manifest-backed custom registry composite / `node*` / `runs.using: docker` action、`docker://...` action、`wasm://...` action、cache 済み / prefetched GitHub repo `node*` action、cache 済み / prefetched GitHub repo `runs.using: docker` action です。`ResolvedAction` は backend 文字列とは別に capability model (`host` / `docker` / `wasm`) を持ち、resolver と executor の契約を分離します。
