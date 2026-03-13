///|
fn expect_cli_options(result : CliParseResult) -> CliOptions {
  match result.options {
    Some(options) => options
    None => abort(result.errors.join("\n"))
  }
}

///|
fn ensure_main_test_dir(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
fn remove_main_test_tree(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    return
  }
  if @xfs.is_dir(path) {
    for entry in @xfs.read_dir(path) {
      remove_main_test_tree(path + "/" + entry)
    }
    @xfs.remove_dir(path)
  } else {
    @xfs.remove_file(path)
  }
}

///|
fn main_test_set_env_var(key : String, value : String) -> String? {
  let previous = @xsys.get_env_var(key)
  @xsys.set_env_var(key, value)
  previous
}

///|
fn main_test_restore_env_var(key : String, previous : String?) -> Unit {
  match previous {
    Some(value) => @xsys.set_env_var(key, value)
    None => @xsys.unset_env_var(key)
  }
}

///|
fn main_test_absolute_path(path : String) -> String {
  if path.has_prefix("/") {
    return path
  }
  let cwd = @env.current_dir().unwrap_or(
    @xsys.get_env_var("PWD").unwrap_or("."),
  )
  if cwd.has_suffix("/") {
    cwd + path
  } else {
    cwd + "/" + path
  }
}

///|
test "cli: parse local workflow path" {
  let result = parse_cli_args(["action_runner", ".github/workflows/ci.yml"])
  inspect(result.errors, content="[]")

  let options = expect_cli_options(result)
  inspect(options.workflow_path, content=".github/workflows/ci.yml")
  inspect(options.changed_paths, content="[]")
  assert_eq(options.repo_root, None)
  assert_eq(options.workspace_root, None)
  inspect(local_workspace_root(options.workflow_path), content=".")
}

///|
test "cli: parse repo mode flags" {
  let result = parse_cli_args([
    "action_runner", ".github/workflows/ci.yml", "--repo", "/repo", "--workspace",
    "/tmp/work", "--run-root", "/tmp/runs", "--artifact-root", "/tmp/artifacts",
    "--cache-root", "/tmp/cache", "--github-action-cache-root", "/tmp/gha-cache",
    "--registry-root", "/tmp/registry", "--wasm-action-root", "/tmp/wasm", "--workspace-mode",
    "tmp", "--event", "push.json", "--ref", "feature/demo", "--before", "def456",
    "--after", "abc123", "--repository", "mizchi/action_runner", "--changed", "src/lib.mbt",
    "--changed", "README.md",
  ])
  inspect(result.errors, content="[]")

  let options = expect_cli_options(result)
  inspect(options.repo_root.unwrap_or(""), content="/repo")
  inspect(options.workspace_root.unwrap_or(""), content="/tmp/work")
  inspect(options.run_root.unwrap_or(""), content="/tmp/runs")
  inspect(options.artifact_root.unwrap_or(""), content="/tmp/artifacts")
  inspect(options.cache_root.unwrap_or(""), content="/tmp/cache")
  inspect(
    options.github_action_cache_root.unwrap_or(""),
    content="/tmp/gha-cache",
  )
  inspect(options.registry_root.unwrap_or(""), content="/tmp/registry")
  inspect(options.wasm_action_root.unwrap_or(""), content="/tmp/wasm")
  inspect(options.workspace_mode, content="tmp")
  inspect(options.event_path.unwrap_or(""), content="push.json")
  inspect(options.ref_name, content="feature/demo")
  inspect(options.before_sha, content="def456")
  inspect(options.after_sha, content="abc123")
  inspect(options.repository, content="mizchi/action_runner")
  inspect(options.changed_paths, content="[\"src/lib.mbt\", \"README.md\"]")
}

///|
test "cli: parse run list flags" {
  let result = parse_run_read_args([
    "action_runner", "run", "list", "--run-root", "/tmp/runs", "--json",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run list parse failed")
  }
  inspect(options.action, content="list")
  inspect(options.run_id, content="")
  inspect(options.run_root.unwrap_or(""), content="/tmp/runs")
  inspect(options.json_output, content="true")
  assert_eq(options.task_id, None)
}

///|
test "cli: parse run view flags" {
  let result = parse_run_read_args([
    "action_runner", "run", "view", "run-1", "--run-root", "/tmp/runs", "--json",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run view parse failed")
  }
  inspect(options.action, content="view")
  inspect(options.run_id, content="run-1")
  inspect(options.run_root.unwrap_or(""), content="/tmp/runs")
  inspect(options.json_output, content="true")
  assert_eq(options.task_id, None)
}

///|
test "cli: parse run watch flags" {
  let result = parse_run_read_args([
    "action_runner", "run", "watch", "run-1", "--run-root", "/tmp/runs", "--json",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run watch parse failed")
  }
  inspect(options.action, content="watch")
  inspect(options.run_id, content="run-1")
  inspect(options.run_root.unwrap_or(""), content="/tmp/runs")
  inspect(options.json_output, content="true")
  assert_eq(options.task_id, None)
}

///|
test "cli: parse run logs flags" {
  let result = parse_run_read_args([
    "action_runner", "run", "logs", "run-1", "--run-root", "/tmp/runs", "--task",
    "build/record",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run logs parse failed")
  }
  inspect(options.action, content="logs")
  inspect(options.run_id, content="run-1")
  inspect(options.run_root.unwrap_or(""), content="/tmp/runs")
  inspect(options.task_id.unwrap_or(""), content="build/record")
  inspect(options.json_output, content="false")
}

///|
test "cli: parse run download flags" {
  let result = parse_run_read_args([
    "action_runner", "run", "download", "run-1", "--run-root", "/tmp/runs", "--artifact-root",
    "/tmp/artifacts", "--dir", "/tmp/out",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run download parse failed")
  }
  inspect(options.action, content="download")
  inspect(options.run_id, content="run-1")
  inspect(options.run_root.unwrap_or(""), content="/tmp/runs")
  inspect(options.artifact_root.unwrap_or(""), content="/tmp/artifacts")
  inspect(options.download_dir, content="/tmp/out")
  inspect(options.json_output, content="false")
}

///|
test "cli: parse artifact list flags" {
  let result = parse_artifact_read_args([
    "action_runner", "artifact", "list", "run-1", "--run-root", "/tmp/runs", "--json",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("artifact list parse failed")
  }
  inspect(options.action, content="list")
  inspect(options.run_id, content="run-1")
  inspect(options.run_root.unwrap_or(""), content="/tmp/runs")
  inspect(options.json_output, content="true")
  inspect(options.artifact_name, content="")
}

///|
test "cli: parse artifact download flags" {
  let result = parse_artifact_read_args([
    "action_runner", "artifact", "download", "run-1", "--run-root", "/tmp/runs",
    "--artifact-root", "/tmp/artifacts", "--name", "report", "--dir", "/tmp/out",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("artifact download parse failed")
  }
  inspect(options.action, content="download")
  inspect(options.run_id, content="run-1")
  inspect(options.run_root.unwrap_or(""), content="/tmp/runs")
  inspect(options.artifact_root.unwrap_or(""), content="/tmp/artifacts")
  inspect(options.artifact_name, content="report")
  inspect(options.download_dir, content="/tmp/out")
}

///|
test "cli: parse cache list flags" {
  let result = parse_cache_read_args([
    "action_runner", "cache", "list", "--cache-root", "/tmp/cache", "--json",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("cache list parse failed")
  }
  inspect(options.action, content="list")
  inspect(options.cache_root.unwrap_or(""), content="/tmp/cache")
  inspect(options.json_output, content="true")
}

///|
test "cli: reject missing option value" {
  let result = parse_cli_args([
    "action_runner", ".github/workflows/ci.yml", "--repo",
  ])

  inspect(result.errors, content="[\"missing value for --repo\"]")
}

///|
test "cli: reject invalid workspace mode" {
  let result = parse_cli_args([
    "action_runner", ".github/workflows/ci.yml", "--workspace-mode", "podman",
  ])

  inspect(
    result.errors,
    content="[\"workspace mode must be one of: worktree, tmp, docker\"]",
  )
}

///|
test "cli: default workspace mode depends on repo mode" {
  let local_options = expect_cli_options(
    parse_cli_args(["action_runner", ".github/workflows/ci.yml"]),
  )
  let repo = expect_cli_options(
    parse_cli_args([
      "action_runner", ".github/workflows/ci.yml", "--repo", "/repo",
    ]),
  )

  inspect(resolved_workspace_mode(local_options), content="worktree")
  inspect(resolved_workspace_mode(repo), content="tmp")
}

///|
test "cli: root override flags are exported to runner env" {
  let options = expect_cli_options(
    parse_cli_args([
      "action_runner", ".github/workflows/ci.yml", "--artifact-root", "/tmp/artifacts",
      "--cache-root", "/tmp/cache", "--github-action-cache-root", "/tmp/gha-cache",
      "--registry-root", "/tmp/registry", "--wasm-action-root", "/tmp/wasm",
    ]),
  )
  let prev_artifact = main_test_set_env_var(
    "ACTION_RUNNER_ARTIFACT_ROOT", "/previous/artifacts",
  )
  let prev_cache = main_test_set_env_var(
    "ACTION_RUNNER_CACHE_ROOT", "/previous/cache",
  )
  let prev_gha = main_test_set_env_var(
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT", "/previous/gha",
  )
  let prev_registry = main_test_set_env_var(
    "ACTION_RUNNER_ACTION_REGISTRY_ROOT", "/previous/registry",
  )
  let prev_wasm = main_test_set_env_var(
    "ACTION_RUNNER_WASM_ACTION_ROOT", "/previous/wasm",
  )

  apply_cli_root_overrides(options)

  inspect(
    @xsys.get_env_var("ACTION_RUNNER_ARTIFACT_ROOT").unwrap_or(""),
    content="/tmp/artifacts",
  )
  inspect(
    @xsys.get_env_var("ACTION_RUNNER_CACHE_ROOT").unwrap_or(""),
    content="/tmp/cache",
  )
  inspect(
    @xsys.get_env_var("ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT").unwrap_or(""),
    content="/tmp/gha-cache",
  )
  inspect(
    @xsys.get_env_var("ACTION_RUNNER_ACTION_REGISTRY_ROOT").unwrap_or(""),
    content="/tmp/registry",
  )
  inspect(
    @xsys.get_env_var("ACTION_RUNNER_WASM_ACTION_ROOT").unwrap_or(""),
    content="/tmp/wasm",
  )

  main_test_restore_env_var("ACTION_RUNNER_ARTIFACT_ROOT", prev_artifact)
  main_test_restore_env_var("ACTION_RUNNER_CACHE_ROOT", prev_cache)
  main_test_restore_env_var("ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT", prev_gha)
  main_test_restore_env_var("ACTION_RUNNER_ACTION_REGISTRY_ROOT", prev_registry)
  main_test_restore_env_var("ACTION_RUNNER_WASM_ACTION_ROOT", prev_wasm)
}

///|
test "cli: parse GitHub repository from https remote url" {
  inspect(
    github_repository_from_remote_url(
      "https://github.com/mizchi/action_runner.git",
    ),
    content="mizchi/action_runner",
  )
}

///|
test "cli: parse GitHub repository from ssh remote url" {
  inspect(
    github_repository_from_remote_url("git@github.com:mizchi/action_runner.git"),
    content="mizchi/action_runner",
  )
}

///|
test "cli: extract origin remote url from git config text" {
  let config =
    #|[core]
    #|  repositoryformatversion = 0
    #|[remote "upstream"]
    #|  url = https://github.com/other/project.git
    #|[remote "origin"]
    #|  url = git@github.com:mizchi/action_runner.git
    #|  fetch = +refs/heads/*:refs/remotes/origin/*
  inspect(
    origin_remote_url_from_git_config(config).unwrap_or(""),
    content="git@github.com:mizchi/action_runner.git",
  )
  inspect(
    github_repository_from_git_config(config).unwrap_or(""),
    content="mizchi/action_runner",
  )
}

///|
#cfg(target="native")
test "cli: infer GitHub repository from repo root origin config" {
  ensure_main_test_dir("_build")
  ensure_main_test_dir("_build/test-main")
  let repo_root = "_build/test-main/repository-detect"
  let git_dir = repo_root + "/.git"
  let config =
    #|[remote "origin"]
    #|  url = https://github.com/mizchi/action_runner.git
    #|  fetch = +refs/heads/*:refs/remotes/origin/*
  ensure_main_test_dir(repo_root)
  ensure_main_test_dir(git_dir)
  @xfs.write_string_to_file(git_dir + "/config", config)

  inspect(
    origin_remote_url_from_repo_root(repo_root).unwrap_or(""),
    content="https://github.com/mizchi/action_runner.git",
  )
  inspect(
    github_repository_from_repo_root(repo_root).unwrap_or(""),
    content="mizchi/action_runner",
  )
}

///|
#cfg(target="native")
test "cli: persist run record allocates sequential run ids" {
  ensure_main_test_dir("_build")
  ensure_main_test_dir("_build/test-main")
  let run_root = "_build/test-main/run-store"
  remove_main_test_tree(run_root)
  let record : RunRecord = {
    run_id: "",
    workflow_name: "ci",
    workflow_path: ".github/workflows/ci.yml",
    workspace_root: "/tmp/workspace",
    workspace_mode: "worktree",
    started_at_ms: 1000UL,
    finished_at_ms: 2000UL,
    state: "completed",
    ok: true,
    repository: "mizchi/action_runner",
    ref_name: "main",
    before_sha: "def456",
    after_sha: "abc123",
    changed_paths: ["README.md"],
  }

  let first = persist_run_record(run_root, record).unwrap_or("")
  let second = persist_run_record(run_root, record).unwrap_or("")

  inspect(first, content="run-1")
  inspect(second, content="run-2")
  let first_json = @xfs.read_file_to_string(run_root + "/run-1/run.json")
  inspect(first_json.contains("\"run_id\": \"run-1\""), content="true")
  inspect(
    first_json.contains("\"workspace_mode\": \"worktree\""),
    content="true",
  )
  inspect(
    first_json.contains("\"changed_paths\": [\"README.md\"]"),
    content="true",
  )
  inspect(first_json.contains("\"started_at_ms\": 1000"), content="true")
  inspect(first_json.contains("\"finished_at_ms\": 2000"), content="true")
  inspect(
    @xfs.read_file_to_string(run_root + "/run-1/jobs.json"),
    content="[]\n",
  )
  inspect(
    @xfs.read_file_to_string(run_root + "/run-1/artifacts.json"),
    content="[]\n",
  )
  inspect(
    @xfs.read_file_to_string(run_root + "/run-1/caches.json"),
    content="[]\n",
  )
}

///|
#cfg(target="native")
async test "cli: persist run record stores task logs and summaries" {
  ensure_main_test_dir("_build")
  ensure_main_test_dir("_build/test-main")
  let workspace_rel = "_build/test-main/run-store-report-workspace"
  let workspace = main_test_absolute_path(workspace_rel)
  let run_root = "_build/test-main/run-store-report"
  let cache_root = "_build/test-main/run-store-cache-list"
  let cache_root_abs = main_test_absolute_path(cache_root)
  remove_main_test_tree(workspace_rel)
  remove_main_test_tree(run_root)
  remove_main_test_tree(cache_root)
  ensure_main_test_dir(workspace_rel)
  let previous_cache_root = main_test_set_env_var(
    "ACTION_RUNNER_CACHE_ROOT", cache_root_abs,
  )
  let workflow_src =
    #|name: ci
    #|'on':
    #|  push:
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: record
    #|        run: |
    #|          printf '%s' hello-run-store
    #|          printf '%s' summary-run-store >> "$GITHUB_STEP_SUMMARY"
    #|          mkdir -p artifacts
    #|          printf '%s' cached-run-store > artifacts/result.txt
    #|      - id: upload
    #|        uses: actions/upload-artifact@v4
    #|        with:
    #|          name: report
    #|          path: artifacts/result.txt
    #|      - id: cache
    #|        uses: actions/cache/save@v4
    #|        with:
    #|          key: run-store-basic-key
    #|          path: artifacts/result.txt
  let parsed = @ar.parse_workflow_yaml(workflow_src)
  let workflow = match parsed.workflow {
    Some(spec) => spec
    None => abort(parsed.errors.join("\n"))
  }
  let lowered = @ar.lower_push_workflow_in_workspace(workflow, workspace)
  if lowered.errors.length() > 0 {
    abort(lowered.errors.join("\n"))
  }
  let report = @ar.execute_lowered_native(
    lowered,
    workspace_root=workspace,
    push_event=Some(
      @ar.new_push_event(
        "main",
        ["README.md"],
        repository="mizchi/action_runner",
      ),
    ),
  )
  let run_id = persist_run_record(
    run_root,
    {
      run_id: "",
      workflow_name: "ci",
      workflow_path: ".github/workflows/ci.yml",
      workspace_root: workspace,
      workspace_mode: "worktree",
      started_at_ms: 1000UL,
      finished_at_ms: 2000UL,
      state: report.state,
      ok: report.ok,
      repository: "mizchi/action_runner",
      ref_name: "main",
      before_sha: "",
      after_sha: "",
      changed_paths: ["README.md"],
    },
    report=Some(report),
    plan=Some(lowered.plan),
  ).unwrap_or("")

  inspect(run_id, content="run-1")
  let run_json = @xfs.read_file_to_string(run_root + "/run-1/run.json")
  inspect(run_json.contains("\"steps\": [{"), content="true")
  inspect(run_json.contains("\"started_at_ms\": 1000"), content="true")
  inspect(run_json.contains("\"finished_at_ms\": 2000"), content="true")
  inspect(
    run_json.contains("\"stdout_path\": \"tasks/build__record.stdout.log\""),
    content="true",
  )
  inspect(
    run_json.contains("\"summary_path\": \"tasks/build__record.summary.md\""),
    content="true",
  )
  inspect(run_json.contains("\"jobs\": [{"), content="true")
  inspect(run_json.contains("\"id\": \"build\""), content="true")
  inspect(run_json.contains("\"status\": \"success\""), content="true")
  inspect(run_json.contains("\"artifacts\": [{"), content="true")
  inspect(run_json.contains("\"name\": \"report\""), content="true")
  inspect(run_json.contains("\"files\": [\"result.txt\"]"), content="true")
  inspect(run_json.contains("\"caches\": [{"), content="true")
  inspect(run_json.contains("\"key\": \"run-store-basic-key\""), content="true")
  inspect(
    run_json.contains("\"files\": [\"artifacts/result.txt\"]"),
    content="true",
  )
  let jobs_json = @xfs.read_file_to_string(run_root + "/run-1/jobs.json")
  inspect(jobs_json.contains("\"id\": \"build\""), content="true")
  inspect(jobs_json.contains("\"status\": \"success\""), content="true")
  let artifacts_json = @xfs.read_file_to_string(
    run_root + "/run-1/artifacts.json",
  )
  inspect(artifacts_json.contains("\"name\": \"report\""), content="true")
  inspect(
    artifacts_json.contains("\"files\": [\"result.txt\"]"),
    content="true",
  )
  let caches_json = @xfs.read_file_to_string(run_root + "/run-1/caches.json")
  inspect(
    caches_json.contains("\"key\": \"run-store-basic-key\""),
    content="true",
  )
  inspect(
    caches_json.contains("\"files\": [\"artifacts/result.txt\"]"),
    content="true",
  )
  inspect(
    @xfs.read_file_to_string(run_root + "/run-1/tasks/build__record.stdout.log"),
    content="hello-run-store",
  )
  inspect(
    @xfs.read_file_to_string(run_root + "/run-1/tasks/build__record.summary.md"),
    content="summary-run-store",
  )
  let view_text = format_run_view_text(run_json).unwrap_or("")
  inspect(view_text.contains("run_id=run-1"), content="true")
  inspect(view_text.contains("workflow=ci"), content="true")
  inspect(view_text.contains("state=completed"), content="true")
  inspect(view_text.contains("job/build=success"), content="true")
  inspect(view_text.contains("artifact/report=result.txt"), content="true")
  inspect(
    view_text.contains("cache/run-store-basic-key=artifacts/result.txt"),
    content="true",
  )
  let logs_text = format_run_logs_text(
    run_root + "/run-1",
    run_json,
    task_id=Some("build/record"),
  ).unwrap_or("")
  inspect(logs_text.contains("==> build/record stdout"), content="true")
  inspect(logs_text.contains("hello-run-store"), content="true")
  inspect(logs_text.contains("==> build/record summary"), content="true")
  inspect(logs_text.contains("summary-run-store"), content="true")

  let run_root_list = "_build/test-main/run-store-list"
  remove_main_test_tree(run_root_list)
  let run_root_list_abs = main_test_absolute_path(run_root_list)
  let run_json_one =
    #|{
    #|  "run_id": "run-1",
    #|  "workflow_name": "alpha",
    #|  "state": "completed"
    #|}
  let run_json_two =
    #|{
    #|  "run_id": "run-2",
    #|  "workflow_name": "beta",
    #|  "state": "failed"
    #|}
  ensure_main_test_dir(run_root_list)
  ensure_main_test_dir(run_root_list + "/run-1")
  ensure_main_test_dir(run_root_list + "/run-2")
  @xfs.write_string_to_file(run_root_list + "/run-1/run.json", run_json_one)
  @xfs.write_string_to_file(run_root_list + "/run-2/run.json", run_json_two)
  let list_text = format_run_list_text(run_root_list_abs).unwrap_or("")
  inspect(list_text.contains("run-2\tfailed\tbeta"), content="true")
  inspect(list_text.contains("run-1\tcompleted\talpha"), content="true")
  let list_json = collect_run_list_json(run_root_list_abs).unwrap_or("")
  inspect(list_json.contains("\"run_id\": \"run-1\""), content="true")
  inspect(list_json.contains("\"run_id\": \"run-2\""), content="true")
  let artifact_list_text = format_artifact_list_text(artifacts_json).unwrap_or(
    "",
  )
  inspect(artifact_list_text.contains("report\tresult.txt"), content="true")
  let run_download_dir = "_build/test-main/run-download-all"
  remove_main_test_tree(run_download_dir)
  let run_download_exit = handle_run_read_command({
    action: "download",
    run_id: "run-1",
    run_root: Some(run_root),
    task_id: None,
    artifact_root: None,
    download_dir: run_download_dir,
    json_output: false,
  })
  inspect(run_download_exit, content="0")
  inspect(
    @xfs.read_file_to_string(run_download_dir + "/report/result.txt"),
    content="cached-run-store",
  )
  let download_dir = "_build/test-main/run-store-download"
  remove_main_test_tree(download_dir)
  let download_exit = handle_artifact_read_command({
    action: "download",
    run_id: "run-1",
    run_root: Some(run_root),
    artifact_root: None,
    artifact_name: "report",
    download_dir,
    json_output: false,
  })
  inspect(download_exit, content="0")
  inspect(
    @xfs.read_file_to_string(download_dir + "/result.txt"),
    content="cached-run-store",
  )
  let workspace_key = run_store_sanitize_id(workspace)
  let cache_list_text = format_cache_list_text(
    collect_cache_list_records(cache_root_abs),
  )
  inspect(
    cache_list_text.contains(
      workspace_key + "\t" + "run-store-basic-key\t1\tartifacts/result.txt",
    ),
    content="true",
  )
  let cache_list_json_text = cache_list_json(
    collect_cache_list_records(cache_root_abs),
  )
  inspect(cache_list_json_text.contains("\"workspace_key\": "), content="true")
  inspect(
    cache_list_json_text.contains("\"key\": \"run-store-basic-key\""),
    content="true",
  )
  let cache_list_exit = handle_cache_read_command({
    action: "list",
    cache_root: Some(cache_root_abs),
    json_output: true,
  })
  inspect(cache_list_exit, content="0")
  main_test_restore_env_var("ACTION_RUNNER_CACHE_ROOT", previous_cache_root)
}

///|
test "cli: explicit flags override values from event payload" {
  let base = @ar.new_push_event(
    "main",
    ["README.md"],
    before_sha="def456",
    after_sha="abc123",
    repository="from/event",
    actor="octocat",
  )
  let options = expect_cli_options(
    parse_cli_args([
      "action_runner", ".github/workflows/ci.yml", "--event", "push.json", "--repository",
      "from/cli", "--after", "fff999", "--changed", "src/lib.mbt",
    ]),
  )
  let merged = merge_cli_push_event(base, options)

  inspect(merged.ref_name, content="main")
  inspect(merged.before_sha, content="def456")
  inspect(merged.after_sha, content="fff999")
  inspect(merged.repository, content="from/cli")
  inspect(merged.actor, content="octocat")
  inspect(merged.changed_paths, content="[\"src/lib.mbt\"]")
}

///|
test "cli: event file enables trigger checks" {
  let options = expect_cli_options(
    parse_cli_args([
      "action_runner", ".github/workflows/ci.yml", "--event", "push.json",
    ]),
  )

  inspect(should_check_trigger(options), content="true")
}
