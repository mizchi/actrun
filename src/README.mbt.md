# actrun

MVP の GitHub Actions 互換 push CI ランナー向けコア API。

The release-contract principle is: keep GitHub Actions-compatible surface area stable, and keep runner optimizations or protocol extensions internal / experimental.

この package は `push` workflow の subset を parse し、`bitflow` IR に lower し、native target では host shell 上で実行できます。

- `push` trigger のフィルタ判定
- workflow YAML subset parser
- workflow/job/step 契約型
- `ActionRef` / resolver
- `bitflow` IR への lowering
- `bitflow` task cache plan / writeback の CLI 連携 (`--flow-cache-store`, `--flow-signature`)
- `workflow list` の最小 read-only CLI
- `workflow run` の最小 subcommand
- `strategy.matrix` の最小対応 (`axes` / `include` / `exclude` / mixed `axes + include` / `fail-fast` / `max-parallel`)
- matrix job に対する `needs` fan-in と aggregated `${{ needs.<job>.result }}` / `${{ needs.<job>.outputs.* }}`
- minimal job-level `if:` (`success()` default, `always()` / `failure()` / `cancelled()`, simple `github.*` / `needs.*` comparison)
- minimal step-level `if:` (`success()` default, `always()` / `failure()` / `cancelled()`)
- minimal expression functions (`contains`, `startsWith`, `endsWith`, `fromJSON`, `toJSON`, `hashFiles`)
- `${{ vars.* }}` の最小対応 (`ACTRUN_VAR_<NAME>` から供給)
- `${{ secrets.* }}` の最小対応 (`ACTRUN_SECRET_<NAME>` から供給, `if:` 直接参照は未対応)
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
- CLI run store の最小対応 (`--run-root`, `_build/actrun/runs/<run-id>/run.json`, `jobs.json`, `artifacts.json`, `caches.json`, `tasks/*.stdout.log|stderr.log|summary.md`, jobs/artifacts/caches index, timestamps, `run list`, `run view`, `run watch`, `run logs`, `run download`, `artifact list`, `artifact download`, `cache list`, `cache prune`)
- local injection point の CLI flag 対応 (`--artifact-root`, `--cache-root`, `--github-action-cache-root`, `--registry-root`)
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

CLI では `actrun workflow list --repo /path/to/repo` で `.github/workflows/*.yml|*.yaml` を列挙できます。`name` が空なら file stem を fallback に使います。`actrun workflow run .github/workflows/ci.yml` は従来の `actrun .github/workflows/ci.yml` と同じ実行経路を subcommand で呼ぶ入口です。`actrun .github/workflows/ci.yml --repo /path/to/repo --workspace /tmp/work --before <sha>` の形で、repo 上の commit snapshot を materialize してから実行できます。`--event /path/to/push-event.json` を渡すと GitHub push webhook payload から `PushEvent` を組み立てます。`--changed` を省略した場合は changed paths を自動計算します。`${{ github.repository }}` / `GITHUB_REPOSITORY` は `--repository` で明示 override でき、未指定なら repo root の `origin` remote URL から自動推測します。`--run-root` を渡すと local run record の保存先を上書きでき、現時点では `<run-root>/run-<n>/run.json`, `jobs.json`, `artifacts.json`, `caches.json` と `tasks/*.stdout.log|stderr.log|summary.md` を保存し、`run.json` には `started_at_ms` / `finished_at_ms`, `exit_code`, job 状態、artifact/cache index も含みます。`--flow-cache-store <path>` を `--flow-signature <job-or-task>=<fingerprint>` と併用すると、dry-run 時は bitflow task cache の plan を計算し、`--json` 出力や `run.json` に `flow_cache.plan` を含めます。通常実行では successful な task を同じ store に writeback し、その結果を `flow_cache.writeback` として run record に残します。`actrun run list` は保存済み run を新しい順に列挙し、`actrun run view <run-id>` は run store を要約表示し、`--json` 付きなら `run.json` をそのまま返します。`actrun run watch <run-id>` は run store が終端状態になるまで poll し、完了時に `run view` と同じ要約、`--json` 付きなら `run.json` を返し、failed/cancelled 系 state では non-zero で終了します。`actrun run logs <run-id> --task <task-id>` は保存済み task log / summary を読み戻し、`--json` 付きなら task ごとの `stdout` / `stderr` / `summary` payload を返します。`actrun run download <run-id>` はその run の全 artifact を `<dir>/<artifact-name>/...` に展開し、`--json` 付きなら download 結果の summary を返します。`actrun artifact list <run-id>` はその run の artifact index を列挙し、`actrun artifact download <run-id> --name <artifact>` は保存済み artifact を指定 directory に展開し、`--json` 付きなら copied file の summary を返します。`actrun cache list` は cache root 配下の workspace ごとの cache key と file 一覧を列挙し、`actrun cache prune --key <cache-key>` は一致する cache entry を削除します。`--artifact-root` / `--cache-root` は builtin artifact/cache store の保存先を、`--github-action-cache-root` / `--registry-root` は remote action cache / custom registry root をそれぞれ上書きします。`--workspace-mode` は contract だけ先に入っていて、local workflow 実行では `worktree`、`--repo` 実行では `tmp` が default です。

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

`parse_action_ref` distinguishes GitHub repo refs, local paths, `docker://...`, and custom registry refs. A custom registry action (`bit://std/cache@v1`) resolves its manifest from `ACTRUN_ACTION_REGISTRY_ROOT/<scheme>/<name>/<version>`. On the release-contract surface, the stable WASM-related API is GitHub-compatible workflow / action metadata plus runner-local configuration (`ACTRUN_WASM_RUNNER`, `ACTRUN_WASM_BIN`). The native executor may prefer a sibling `*.wasm` next to a standard `node*` action `runs.main` as a self-hosted runner optimization. `ACTRUN_WASM_RUNNER` accepts `wasmtime`, `deno`, or `v8`, and the default binary becomes `wasmtime`, `deno`, or `ACTRUN_NODE_BIN` (`node`) respectively. `./local-action` reads `action.yml` / `action.yaml` from the workspace and expands to composite steps while wiring `with` into `${{ inputs.* }}`. `prefetch_workflow_github_actions_native` clones `owner/repo[/path]@ref` into `_build/actrun/github_actions` or `ACTRUN_GITHUB_ACTION_CACHE_ROOT`; composite manifests are expanded, `runs.using: node*` executes `runs.main` and `pre` / `post`, and `runs.using: docker` executes `runs.image` / `runs.args` / `runs.entrypoint` / `runs.pre-entrypoint` / `runs.post-entrypoint` from the native executor. The prefetch path uses `ACTRUN_GIT_BIN`; the native executor uses `ACTRUN_NODE_BIN` / `ACTRUN_DOCKER_BIN` / `ACTRUN_WASM_BIN`; `setup-node` uses `ACTRUN_SETUP_NODE_BIN`; `${{ vars.* }}` comes from `ACTRUN_VAR_<NAME>`; `${{ secrets.* }}` comes from `ACTRUN_SECRET_<NAME>`; and the GitHub host can be overridden by `ACTRUN_GITHUB_BASE_URL`. `wasm://...` and `runs-on: wasi` may still exist inside the repo but are not part of the release contract and are treated as internal / experimental. `ResolvedAction` separates the backend string from the capability model (`host` / `docker` / `wasm`).
