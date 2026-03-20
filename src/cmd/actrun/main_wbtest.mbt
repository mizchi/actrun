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
  let result = parse_cli_args(["actrun", ".github/workflows/ci.yml"])
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
    "actrun", ".github/workflows/ci.yml", "--repo", "/repo", "--workspace", "/tmp/work",
    "--run-root", "/tmp/runs", "--artifact-root", "/tmp/artifacts", "--cache-root",
    "/tmp/cache", "--github-action-cache-root", "/tmp/gha-cache", "--registry-root",
    "/tmp/registry", "--wasm-action-root", "/tmp/wasm", "--workspace-mode", "tmp",
    "--event", "push.json", "--ref", "feature/demo", "--before", "def456", "--after",
    "abc123", "--repository", "mizchi/actrun", "--changed", "src/lib.mbt", "--changed",
    "README.md",
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
  inspect(options.repository, content="mizchi/actrun")
  inspect(options.changed_paths, content="[\"src/lib.mbt\", \"README.md\"]")
}

///|
test "cli: parse run list flags" {
  let result = parse_run_read_args([
    "actrun", "run", "list", "--run-root", "/tmp/runs", "--json",
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
test "cli: parse workflow list flags" {
  let result = parse_workflow_read_args([
    "actrun", "workflow", "list", "--repo", "/repo", "--json",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("workflow list parse failed")
  }
  inspect(options.action, content="list")
  inspect(options.repo_root.unwrap_or(""), content="/repo")
  inspect(options.json_output, content="true")
}

///|
test "cli: parse workflow run flags" {
  let result = parse_workflow_run_args([
    "actrun", "workflow", "run", ".github/workflows/ci.yml", "--repo", "/repo", "--workspace",
    "/tmp/work", "--run-root", "/tmp/runs", "--workspace-mode", "tmp", "--event",
    "push.json", "--repository", "mizchi/actrun", "--ref", "main", "--before", "def456",
    "--after", "abc123", "--changed", "src/lib.mbt",
  ])
  inspect(result.errors, content="[]")
  let options = expect_cli_options(result)
  inspect(options.workflow_path, content=".github/workflows/ci.yml")
  inspect(options.repo_root.unwrap_or(""), content="/repo")
  inspect(options.workspace_root.unwrap_or(""), content="/tmp/work")
  inspect(options.run_root.unwrap_or(""), content="/tmp/runs")
  inspect(options.workspace_mode, content="tmp")
  inspect(options.event_path.unwrap_or(""), content="push.json")
  inspect(options.repository, content="mizchi/actrun")
  inspect(options.ref_name, content="main")
  inspect(options.before_sha, content="def456")
  inspect(options.after_sha, content="abc123")
  inspect(options.changed_paths, content="[\"src/lib.mbt\"]")
}

///|
test "cli: parse run view flags" {
  let result = parse_run_read_args([
    "actrun", "run", "view", "run-1", "--run-root", "/tmp/runs", "--json",
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
    "actrun", "run", "watch", "run-1", "--run-root", "/tmp/runs", "--json",
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
    "actrun", "run", "logs", "run-1", "--run-root", "/tmp/runs", "--task", "build/record",
    "--json",
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
  inspect(options.json_output, content="true")
}

///|
test "cli: parse run download flags" {
  let result = parse_run_read_args([
    "actrun", "run", "download", "run-1", "--run-root", "/tmp/runs", "--artifact-root",
    "/tmp/artifacts", "--dir", "/tmp/out", "--json",
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
  inspect(options.json_output, content="true")
}

///|
test "cli: parse artifact list flags" {
  let result = parse_artifact_read_args([
    "actrun", "artifact", "list", "run-1", "--run-root", "/tmp/runs", "--json",
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
    "actrun", "artifact", "download", "run-1", "--run-root", "/tmp/runs", "--artifact-root",
    "/tmp/artifacts", "--name", "report", "--dir", "/tmp/out", "--json",
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
  inspect(options.json_output, content="true")
}

///|
test "cli: parse cache list flags" {
  let result = parse_cache_read_args([
    "actrun", "cache", "list", "--cache-root", "/tmp/cache", "--json",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("cache list parse failed")
  }
  inspect(options.action, content="list")
  inspect(options.cache_root.unwrap_or(""), content="/tmp/cache")
  inspect(options.key_filter, content="")
  inspect(options.workspace_key_filter, content="")
  inspect(options.json_output, content="true")
}

///|
test "cli: parse cache prune flags" {
  let result = parse_cache_read_args([
    "actrun", "cache", "prune", "--cache-root", "/tmp/cache", "--key", "cache-key",
    "--workspace-key", "workspace-1", "--json",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("cache prune parse failed")
  }
  inspect(options.action, content="prune")
  inspect(options.cache_root.unwrap_or(""), content="/tmp/cache")
  inspect(options.key_filter, content="cache-key")
  inspect(options.workspace_key_filter, content="workspace-1")
  inspect(options.json_output, content="true")
}

///|
test "cli: run state exit code mapping" {
  inspect(run_state_exit_code("completed"), content="0")
  inspect(run_state_exit_code("success"), content="0")
  inspect(run_state_exit_code("skipped"), content="0")
  inspect(run_state_exit_code("partial_failed"), content="1")
  inspect(run_state_exit_code("cancelled"), content="1")
}

///|
test "cli: reject missing option value" {
  let result = parse_cli_args(["actrun", ".github/workflows/ci.yml", "--repo"])

  inspect(result.errors, content="[\"missing value for --repo\"]")
}

///|
test "cli: reject invalid workspace mode" {
  let result = parse_cli_args([
    "actrun", ".github/workflows/ci.yml", "--workspace-mode", "podman",
  ])

  inspect(
    result.errors,
    content="[\"workspace mode must be one of: local, worktree, tmp, docker\"]",
  )
}

///|
test "cli: default workspace mode depends on repo mode" {
  let local_options = expect_cli_options(
    parse_cli_args(["actrun", ".github/workflows/ci.yml"]),
  )
  let repo = expect_cli_options(
    parse_cli_args(["actrun", ".github/workflows/ci.yml", "--repo", "/repo"]),
  )

  inspect(resolved_workspace_mode(local_options), content="worktree")
  inspect(resolved_workspace_mode(repo), content="tmp")
}

///|
test "cli: root override flags are exported to runner env" {
  let options = expect_cli_options(
    parse_cli_args([
      "actrun", ".github/workflows/ci.yml", "--artifact-root", "/tmp/artifacts",
      "--cache-root", "/tmp/cache", "--github-action-cache-root", "/tmp/gha-cache",
      "--registry-root", "/tmp/registry", "--wasm-action-root", "/tmp/wasm",
    ]),
  )
  let prev_artifact = main_test_set_env_var(
    "ACTRUN_ARTIFACT_ROOT", "/previous/artifacts",
  )
  let prev_cache = main_test_set_env_var("ACTRUN_CACHE_ROOT", "/previous/cache")
  let prev_gha = main_test_set_env_var(
    "ACTRUN_GITHUB_ACTION_CACHE_ROOT", "/previous/gha",
  )
  let prev_registry = main_test_set_env_var(
    "ACTRUN_ACTION_REGISTRY_ROOT", "/previous/registry",
  )
  let prev_wasm = main_test_set_env_var(
    "ACTRUN_WASM_ACTION_ROOT", "/previous/wasm",
  )

  apply_cli_root_overrides(options)

  inspect(
    @xsys.get_env_var("ACTRUN_ARTIFACT_ROOT").unwrap_or(""),
    content="/tmp/artifacts",
  )
  inspect(
    @xsys.get_env_var("ACTRUN_CACHE_ROOT").unwrap_or(""),
    content="/tmp/cache",
  )
  inspect(
    @xsys.get_env_var("ACTRUN_GITHUB_ACTION_CACHE_ROOT").unwrap_or(""),
    content="/tmp/gha-cache",
  )
  inspect(
    @xsys.get_env_var("ACTRUN_ACTION_REGISTRY_ROOT").unwrap_or(""),
    content="/tmp/registry",
  )
  inspect(
    @xsys.get_env_var("ACTRUN_WASM_ACTION_ROOT").unwrap_or(""),
    content="/tmp/wasm",
  )

  main_test_restore_env_var("ACTRUN_ARTIFACT_ROOT", prev_artifact)
  main_test_restore_env_var("ACTRUN_CACHE_ROOT", prev_cache)
  main_test_restore_env_var("ACTRUN_GITHUB_ACTION_CACHE_ROOT", prev_gha)
  main_test_restore_env_var("ACTRUN_ACTION_REGISTRY_ROOT", prev_registry)
  main_test_restore_env_var("ACTRUN_WASM_ACTION_ROOT", prev_wasm)
}

///|
test "cli: parse GitHub repository from https remote url" {
  inspect(
    github_repository_from_remote_url("https://github.com/mizchi/actrun.git"),
    content="mizchi/actrun",
  )
}

///|
test "cli: parse GitHub repository from ssh remote url" {
  inspect(
    github_repository_from_remote_url("git@github.com:mizchi/actrun.git"),
    content="mizchi/actrun",
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
    #|  url = git@github.com:mizchi/actrun.git
    #|  fetch = +refs/heads/*:refs/remotes/origin/*
  inspect(
    origin_remote_url_from_git_config(config).unwrap_or(""),
    content="git@github.com:mizchi/actrun.git",
  )
  inspect(
    github_repository_from_git_config(config).unwrap_or(""),
    content="mizchi/actrun",
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
    #|  url = https://github.com/mizchi/actrun.git
    #|  fetch = +refs/heads/*:refs/remotes/origin/*
  ensure_main_test_dir(repo_root)
  ensure_main_test_dir(git_dir)
  @xfs.write_string_to_file(git_dir + "/config", config)

  inspect(
    origin_remote_url_from_repo_root(repo_root).unwrap_or(""),
    content="https://github.com/mizchi/actrun.git",
  )
  inspect(
    github_repository_from_repo_root(repo_root).unwrap_or(""),
    content="mizchi/actrun",
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
    event: "push",
    state: "completed",
    ok: true,
    exit_code: 0,
    repository: "mizchi/actrun",
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
  inspect(first_json.contains("\"exit_code\": 0"), content="true")
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
    "ACTRUN_CACHE_ROOT", cache_root_abs,
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
      @ar.new_push_event("main", ["README.md"], repository="mizchi/actrun"),
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
      event: "push",
      state: report.state,
      ok: report.ok,
      exit_code: 0,
      repository: "mizchi/actrun",
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
  inspect(run_json.contains("\"conclusion\": \"success\""), content="true")
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
  inspect(jobs_json.contains("\"conclusion\": \"success\""), content="true")
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
  inspect(view_text.contains("(run-1)"), content="true")
  inspect(view_text.contains("ci"), content="true")
  inspect(view_text.contains("success"), content="true")
  inspect(view_text.contains("X build (success)"), content="true")
  inspect(view_text.contains("report"), content="true")
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
  inspect(list_text.contains("beta"), content="true")
  inspect(list_text.contains("run-2"), content="true")
  inspect(list_text.contains("alpha"), content="true")
  inspect(list_text.contains("run-1"), content="true")
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
    json_fields: [],
    jq_expr: "",
    limit: 0,
    status_filter: "",
    exit_status: false,
    verbose: false,
    show_log: false,
    log_failed: false,
    job_id: "",
    workflow_filter: "",
    branch_filter: "",
    event_filter: "",
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
    json_fields: [],
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
    key_filter: "",
    workspace_key_filter: "",
    max_age_days: 0,
    prune_all: false,
    json_output: true,
    json_fields: [],
    limit: 0,
  })
  inspect(cache_list_exit, content="0")
  let cache_prune_exit = handle_cache_read_command({
    action: "prune",
    cache_root: Some(cache_root_abs),
    key_filter: "run-store-basic-key",
    workspace_key_filter: workspace_key,
    max_age_days: 0,
    prune_all: false,
    json_output: false,
    json_fields: [],
    limit: 0,
  })
  inspect(cache_prune_exit, content="0")
  let pruned_list_text = format_cache_list_text(
    collect_cache_list_records(cache_root_abs),
  )
  inspect(pruned_list_text, content="")
  main_test_restore_env_var("ACTRUN_CACHE_ROOT", previous_cache_root)
}

///|
test "cli: workflow list reads .github/workflows from repo root" {
  ensure_main_test_dir("_build")
  ensure_main_test_dir("_build/test-main")
  let repo_root = "_build/test-main/workflow-list"
  remove_main_test_tree(repo_root)
  ensure_main_test_dir(repo_root)
  ensure_main_test_dir(repo_root + "/.github")
  ensure_main_test_dir(repo_root + "/.github/workflows")
  @xfs.write_string_to_file(
    repo_root + "/.github/workflows/ci.yml",
    "name: ci\n'on':\n  push:\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ci\n",
  )
  @xfs.write_string_to_file(
    repo_root + "/.github/workflows/lint.yaml",
    "'on':\n  push:\njobs:\n  lint:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo lint\n",
  )
  let records = collect_workflow_list_records(
    main_test_absolute_path(repo_root),
  )
  let list_text = format_workflow_list_text(records)
  inspect(list_text.contains("ci\t.github/workflows/ci.yml"), content="true")
  inspect(
    list_text.contains("lint\t.github/workflows/lint.yaml"),
    content="true",
  )
  let list_json_text = workflow_list_json(records)
  inspect(list_json_text.contains("\"name\": \"ci\""), content="true")
  inspect(
    list_json_text.contains("\"path\": \".github/workflows/lint.yaml\""),
    content="true",
  )
  let exit_code = handle_workflow_read_command({
    action: "list",
    repo_root: Some(main_test_absolute_path(repo_root)),
    json_output: true,
    json_fields: [],
  })
  inspect(exit_code, content="0")
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
      "actrun", ".github/workflows/ci.yml", "--event", "push.json", "--repository",
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
      "actrun", ".github/workflows/ci.yml", "--event", "push.json",
    ]),
  )

  inspect(should_check_trigger(options), content="true")
}

///|
#cfg(target="native")
async fn setup_workspace_test_repo(name : String) -> String {
  ensure_main_test_dir("_build")
  ensure_main_test_dir("_build/test-main")
  let repo_root = "_build/test-main/" + name
  remove_main_test_tree(repo_root)
  ensure_main_test_dir(repo_root)
  let (code, _, _) = @process.collect_output(
    "git",
    ["init", "-q"],
    cwd=repo_root,
  )
  assert_eq(code, 0)
  let (code2, _, _) = @process.collect_output(
    "git",
    ["config", "user.name", "test"],
    cwd=repo_root,
  )
  assert_eq(code2, 0)
  let (code3, _, _) = @process.collect_output(
    "git",
    ["config", "user.email", "test@test.com"],
    cwd=repo_root,
  )
  assert_eq(code3, 0)
  @xfs.write_string_to_file(repo_root + "/hello.txt", "hello\n")
  let (code4, _, _) = @process.collect_output(
    "git",
    ["add", "."],
    cwd=repo_root,
  )
  assert_eq(code4, 0)
  let (code5, _, _) = @process.collect_output(
    "git",
    ["commit", "-q", "-m", "init"],
    cwd=repo_root,
  )
  assert_eq(code5, 0)
  main_test_absolute_path(repo_root)
}

///|
#cfg(target="native")
async test "workspace: worktree mode creates and cleans up git worktree" {
  let repo_root = setup_workspace_test_repo("ws-worktree")
  let workspace_base = "_build/test-main/ws-worktree-out"
  remove_main_test_tree(workspace_base)
  ensure_main_test_dir(workspace_base)
  let (ws, errors) = setup_local_workspace(
    "worktree", repo_root, workspace_base,
  )
  inspect(errors, content="[]")
  guard ws is Some(workspace) else { abort("workspace setup failed") }
  inspect(workspace.cleanup_mode, content="worktree")
  assert_true(@xfs.path_exists(workspace.execution_root))
  assert_true(@xfs.path_exists(workspace.execution_root + "/hello.txt"))
  inspect(
    @xfs.read_file_to_string(workspace.execution_root + "/hello.txt"),
    content="hello\n",
  )
  cleanup_local_workspace(workspace)
  assert_false(@xfs.path_exists(workspace.execution_root))
}

///|
#cfg(target="native")
async test "workspace: tmp mode creates and cleans up cloned directory" {
  let repo_root = setup_workspace_test_repo("ws-tmp")
  let workspace_base = "_build/test-main/ws-tmp-out"
  remove_main_test_tree(workspace_base)
  ensure_main_test_dir(workspace_base)
  let (ws, errors) = setup_local_workspace("tmp", repo_root, workspace_base)
  inspect(errors, content="[]")
  guard ws is Some(workspace) else { abort("workspace setup failed") }
  inspect(workspace.cleanup_mode, content="tmp")
  assert_true(@xfs.path_exists(workspace.execution_root))
  assert_true(@xfs.path_exists(workspace.execution_root + "/hello.txt"))
  inspect(
    @xfs.read_file_to_string(workspace.execution_root + "/hello.txt"),
    content="hello\n",
  )
  assert_true(@xfs.path_exists(workspace.execution_root + "/.git"))
  cleanup_local_workspace(workspace)
  assert_false(@xfs.path_exists(workspace.execution_root))
}

///|
#cfg(target="native")
async test "workspace: local mode uses source root directly" {
  let (ws, errors) = setup_local_workspace("local", "/some/path", "/unused")
  inspect(errors, content="[]")
  guard ws is Some(workspace) else { abort("workspace setup failed") }
  inspect(workspace.execution_root, content="/some/path")
  inspect(workspace.cleanup_mode, content="none")
}

///|
fn json_has_field(json_text : String, field : String) -> Bool {
  json_text.contains("\"" + field + "\":")
}

///|
test "cli: run.json schema has all required top-level fields" {
  let required_fields : Array[String] = [
    "run_id", "workflow_name", "workflow_path", "workspace_root", "workspace_mode",
    "started_at_ms", "finished_at_ms", "status", "conclusion", "state", "ok", "exit_code",
    "repository", "ref_name", "before_sha", "after_sha", "changed_paths", "order",
    "issues", "steps", "tasks", "jobs", "artifacts", "caches",
  ]
  let record : RunRecord = {
    run_id: "run-1",
    workflow_name: "ci",
    workflow_path: ".github/workflows/ci.yml",
    workspace_root: "/tmp",
    workspace_mode: "local",
    started_at_ms: 1000UL,
    finished_at_ms: 2000UL,
    event: "push",
    state: "completed",
    ok: true,
    exit_code: 0,
    repository: "owner/repo",
    ref_name: "main",
    before_sha: "aaa",
    after_sha: "bbb",
    changed_paths: [],
  }
  let json_text = run_record_json(record)
  for field in required_fields {
    assert_true(json_has_field(json_text, field))
  }
}

///|
test "cli: job JSON schema has required fields" {
  let job_json = run_job_json({
    id: "build",
    name: "build",
    status: "completed",
    conclusion: "success",
    needs: ["setup"],
    task_ids: ["build/test"],
    steps: [
      { name: "test", number: 1, status: "completed", conclusion: "success" },
    ],
  })
  for
    field in (
      ["id", "name", "status", "conclusion", "needs", "task_ids", "steps"] :
      Array[String]) {
    assert_true(json_has_field(job_json, field))
  }
}

///|
test "cli: artifact JSON schema has required fields" {
  let artifact_json = run_artifact_json({
    name: "report",
    files: ["result.txt"],
  })
  for field in (["name", "files"] : Array[String]) {
    assert_true(json_has_field(artifact_json, field))
  }
}

///|
test "cli: cache JSON schema has required fields" {
  let cache_json = run_cache_json({
    key: "cache-key",
    sequence: Some(1),
    files: ["data.txt"],
  })
  for field in (["key", "sequence", "files"] : Array[String]) {
    assert_true(json_has_field(cache_json, field))
  }
}

///|
test "cli: parse run view with --json fields" {
  let result = parse_run_read_args([
    "actrun", "run", "view", "run-1", "--json", "status,conclusion,jobs",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run view parse failed")
  }
  inspect(options.json_output, content="true")
  inspect(options.json_fields, content="[\"status\", \"conclusion\", \"jobs\"]")
}

///|
test "cli: parse run view with --json (no fields)" {
  let result = parse_run_read_args(["actrun", "run", "view", "run-1", "--json"])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run view parse failed")
  }
  inspect(options.json_output, content="true")
  inspect(options.json_fields, content="[]")
}

///|
test "cli: filter_json_fields returns selected fields only" {
  let json_text = "{\"status\": \"completed\", \"conclusion\": \"success\", \"jobs\": []}"
  let filtered = filter_json_fields(json_text, ["status", "conclusion"]).unwrap()
  inspect(filtered.contains("\"status\""), content="true")
  inspect(filtered.contains("\"conclusion\""), content="true")
  inspect(filtered.contains("\"jobs\""), content="false")
}

///|
test "cli: filter_json_fields with empty fields returns all" {
  let json_text = "{\"status\": \"completed\", \"conclusion\": \"success\"}"
  let filtered = filter_json_fields(json_text, []).unwrap()
  inspect(filtered.contains("\"status\""), content="true")
  inspect(filtered.contains("\"conclusion\""), content="true")
}

///|
test "cli: parse run list with --limit and --status" {
  let result = parse_run_read_args([
    "actrun", "run", "list", "--limit", "5", "--status", "failure", "--json", "status,conclusion",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run list parse failed")
  }
  inspect(options.limit, content="5")
  inspect(options.status_filter, content="failure")
  inspect(options.json_output, content="true")
  inspect(options.json_fields, content="[\"status\", \"conclusion\"]")
}

///|
test "cli: parse run list with -L and -s shorthand" {
  let result = parse_run_read_args([
    "actrun", "run", "list", "-L", "3", "-s", "success",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run list parse failed")
  }
  inspect(options.limit, content="3")
  inspect(options.status_filter, content="success")
}

///|
test "cli: parse run view with --exit-status" {
  let result = parse_run_read_args([
    "actrun", "run", "view", "run-1", "--exit-status",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run view parse failed")
  }
  inspect(options.exit_status, content="true")
}

///|
test "cli: run_view_exit_code returns 0 for success" {
  let json = "{\"conclusion\": \"success\", \"status\": \"completed\"}"
  inspect(run_view_exit_code(json), content="0")
}

///|
test "cli: run_view_exit_code returns 1 for failure" {
  let json = "{\"conclusion\": \"failure\", \"status\": \"completed\"}"
  inspect(run_view_exit_code(json), content="1")
}

///|
test "cli: run_json_matches_status filters by conclusion" {
  let json = "{\"status\": \"completed\", \"conclusion\": \"failure\", \"state\": \"completed\"}"
  inspect(run_json_matches_status(json, "failure"), content="true")
  inspect(run_json_matches_status(json, "success"), content="false")
  inspect(run_json_matches_status(json, "completed"), content="true")
  inspect(run_json_matches_status(json, ""), content="true")
}

///|
test "cli: parse run view with --verbose" {
  let result = parse_run_read_args(["actrun", "run", "view", "run-1", "-v"])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run view parse failed")
  }
  inspect(options.verbose, content="true")
}

///|
test "cli: parse run logs with --log-failed and --job" {
  let result = parse_run_read_args([
    "actrun", "run", "logs", "run-1", "--log-failed", "--job", "build",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run logs parse failed")
  }
  inspect(options.log_failed, content="true")
  inspect(options.job_id, content="build")
}

///|
test "cli: parse run logs with -j shorthand" {
  let result = parse_run_read_args([
    "actrun", "run", "logs", "run-1", "-j", "test",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run logs parse failed")
  }
  inspect(options.job_id, content="test")
}

///|
test "cli: format_run_view_text gh-style output" {
  let json = "{\"run_id\": \"run-1\", \"workflow_name\": \"ci\", \"status\": \"completed\", \"conclusion\": \"success\", \"state\": \"completed\", \"started_at_ms\": 1000, \"finished_at_ms\": 3000, \"jobs\": [{\"id\": \"build\", \"name\": \"build\", \"status\": \"completed\", \"conclusion\": \"success\", \"steps\": [{\"name\": \"Checkout\", \"number\": 1, \"status\": \"completed\", \"conclusion\": \"success\"}]}]}"
  let text = format_run_view_text(json).unwrap()
  // Header line
  inspect(text.contains("X ci (run-1) success in 2s"), content="true")
  // Job line
  inspect(text.contains("  X build (success)"), content="true")
  // Steps should NOT show without verbose
  inspect(text.contains("Checkout"), content="false")
}

///|
test "cli: format_run_view_text verbose shows steps" {
  let json = "{\"run_id\": \"run-1\", \"workflow_name\": \"ci\", \"status\": \"completed\", \"conclusion\": \"success\", \"state\": \"completed\", \"jobs\": [{\"id\": \"build\", \"name\": \"build\", \"status\": \"completed\", \"conclusion\": \"success\", \"steps\": [{\"name\": \"Checkout\", \"number\": 1, \"status\": \"completed\", \"conclusion\": \"success\"}, {\"name\": \"Test\", \"number\": 2, \"status\": \"completed\", \"conclusion\": \"failure\"}]}]}"
  let text = format_run_view_text(json, verbose=true).unwrap()
  inspect(text.contains("    X Checkout (success)"), content="true")
  inspect(text.contains("    ! Test (failure)"), content="true")
}

///|
test "cli: format_run_view_text job_id filters jobs" {
  let json = "{\"run_id\": \"run-1\", \"workflow_name\": \"ci\", \"status\": \"completed\", \"conclusion\": \"success\", \"state\": \"completed\", \"jobs\": [{\"id\": \"build\", \"name\": \"build\", \"status\": \"completed\", \"conclusion\": \"success\", \"steps\": []}, {\"id\": \"test\", \"name\": \"test\", \"status\": \"completed\", \"conclusion\": \"failure\", \"steps\": []}]}"
  let text = format_run_view_text(json, job_id="build").unwrap()
  inspect(text.contains("build"), content="true")
  inspect(text.contains("test"), content="false")
}

///|
test "cli: format_run_view_text failure mark" {
  let json = "{\"run_id\": \"run-1\", \"workflow_name\": \"ci\", \"status\": \"completed\", \"conclusion\": \"failure\", \"state\": \"completed\", \"jobs\": [{\"id\": \"build\", \"name\": \"build\", \"status\": \"completed\", \"conclusion\": \"failure\", \"steps\": []}]}"
  let text = format_run_view_text(json).unwrap()
  inspect(text.contains("! ci (run-1) failure"), content="true")
  inspect(text.contains("  ! build (failure)"), content="true")
}

///|
test "cli: task_matches_job filters by job prefix" {
  inspect(task_matches_job("build/step_1", "build"), content="true")
  inspect(task_matches_job("test/step_1", "build"), content="false")
  inspect(task_matches_job("build/step_1", ""), content="true")
}

///|
test "cli: parse run list with --workflow and --branch" {
  let result = parse_run_read_args([
    "actrun", "run", "list", "-w", "ci", "-b", "main", "-e", "push",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("parse failed")
  }
  inspect(options.workflow_filter, content="ci")
  inspect(options.branch_filter, content="main")
  inspect(options.event_filter, content="push")
}

///|
test "cli: parse run view with --log" {
  let result = parse_run_read_args(["actrun", "run", "view", "run-1", "--log"])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("parse failed")
  }
  inspect(options.show_log, content="true")
  inspect(options.log_failed, content="false")
}

///|
test "cli: parse run view with --log-failed" {
  let result = parse_run_read_args([
    "actrun", "run", "view", "run-1", "--log-failed",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("parse failed")
  }
  inspect(options.show_log, content="true")
  inspect(options.log_failed, content="true")
}

///|
test "cli: ms_to_iso8601 converts correctly" {
  // 2025-01-01T00:00:00Z = 1735689600000 ms
  inspect(ms_to_iso8601(1735689600000UL), content="2025-01-01T00:00:00Z")
  inspect(ms_to_iso8601(0UL), content="")
}

///|
test "cli: run_number_from_id extracts number" {
  inspect(run_number_from_id("run-42"), content="42")
  inspect(run_number_from_id("run-1"), content="1")
  inspect(run_number_from_id("invalid"), content="0")
}

///|
test "cli: run_record_json includes gh alias fields" {
  let record : RunRecord = {
    run_id: "run-3",
    workflow_name: "ci",
    workflow_path: ".github/workflows/ci.yml",
    workspace_root: "/tmp",
    workspace_mode: "local",
    started_at_ms: 1735689600000UL,
    finished_at_ms: 1735689660000UL,
    event: "push",
    state: "completed",
    ok: true,
    exit_code: 0,
    repository: "owner/repo",
    ref_name: "main",
    before_sha: "aaa",
    after_sha: "bbb",
    changed_paths: [],
  }
  let json_text = run_record_json(record)
  // gh alias fields
  inspect(json_text.contains("\"workflowName\": \"ci\""), content="true")
  inspect(json_text.contains("\"name\": \"ci\""), content="true")
  inspect(json_text.contains("\"displayTitle\": \"ci\""), content="true")
  inspect(json_text.contains("\"headBranch\": \"main\""), content="true")
  inspect(json_text.contains("\"headSha\": \"bbb\""), content="true")
  inspect(json_text.contains("\"event\": \"push\""), content="true")
  inspect(json_text.contains("\"number\": 3"), content="true")
  inspect(json_text.contains("\"attempt\": 1"), content="true")
  inspect(
    json_text.contains("\"startedAt\": \"2025-01-01T00:00:00Z\""),
    content="true",
  )
  inspect(
    json_text.contains("\"completedAt\": \"2025-01-01T00:01:00Z\""),
    content="true",
  )
}

///|
test "cli: run_json_matches_filters workflow filter" {
  let json = "{\"workflow_name\": \"ci\", \"status\": \"completed\", \"conclusion\": \"success\", \"state\": \"completed\", \"ref_name\": \"main\", \"event\": \"push\"}"
  inspect(run_json_matches_filters(json, "", "ci", "", ""), content="true")
  inspect(run_json_matches_filters(json, "", "deploy", "", ""), content="false")
  inspect(run_json_matches_filters(json, "", "", "main", ""), content="true")
  inspect(run_json_matches_filters(json, "", "", "dev", ""), content="false")
  inspect(run_json_matches_filters(json, "", "", "", "push"), content="true")
  inspect(
    run_json_matches_filters(json, "", "", "", "pull_request"),
    content="false",
  )
}

// --- gh-compat integration tests ---

///|
#cfg(target="native")
test "gh-compat: run_record_json includes status and conclusion for completed run" {
  let record : RunRecord = {
    run_id: "run-1",
    workflow_name: "ci",
    workflow_path: ".github/workflows/ci.yml",
    workspace_root: "/tmp",
    workspace_mode: "local",
    started_at_ms: 1000UL,
    finished_at_ms: 2000UL,
    event: "push",
    state: "completed",
    ok: true,
    exit_code: 0,
    repository: "",
    ref_name: "",
    before_sha: "",
    after_sha: "",
    changed_paths: [],
  }
  let json_text = run_record_json(record)
  inspect(json_text.contains("\"status\": \"completed\""), content="true")
  inspect(json_text.contains("\"conclusion\": \"success\""), content="true")
}

///|
#cfg(target="native")
test "gh-compat: run_record_json conclusion is failure when ok=false" {
  let record : RunRecord = {
    run_id: "run-1",
    workflow_name: "ci",
    workflow_path: ".github/workflows/ci.yml",
    workspace_root: "/tmp",
    workspace_mode: "local",
    started_at_ms: 1000UL,
    finished_at_ms: 2000UL,
    event: "push",
    state: "partial_failed",
    ok: false,
    exit_code: 1,
    repository: "",
    ref_name: "",
    before_sha: "",
    after_sha: "",
    changed_paths: [],
  }
  let json_text = run_record_json(record)
  inspect(json_text.contains("\"status\": \"completed\""), content="true")
  inspect(json_text.contains("\"conclusion\": \"failure\""), content="true")
}

///|
#cfg(target="native")
test "gh-compat: job record includes name, conclusion, and steps" {
  let job : RunJobRecord = {
    id: "build",
    name: "build",
    status: "completed",
    conclusion: "success",
    needs: [],
    task_ids: ["build/checkout", "build/test"],
    steps: [
      {
        name: "Checkout",
        number: 1,
        status: "completed",
        conclusion: "success",
      },
      { name: "Test", number: 2, status: "completed", conclusion: "failure" },
    ],
  }
  let json_text = run_job_json(job)
  inspect(json_text.contains("\"name\": \"build\""), content="true")
  inspect(json_text.contains("\"conclusion\": \"success\""), content="true")
  inspect(json_text.contains("\"steps\": ["), content="true")
  inspect(json_text.contains("\"name\": \"Checkout\""), content="true")
  inspect(json_text.contains("\"number\": 1"), content="true")
  inspect(json_text.contains("\"name\": \"Test\""), content="true")
  inspect(json_text.contains("\"number\": 2"), content="true")
}

///|
#cfg(target="native")
test "gh-compat: run list with --limit restricts results" {
  let run_root = "_build/test-main/gh-compat-limit"
  remove_main_test_tree(run_root)
  let run_root_abs = main_test_absolute_path(run_root)
  ensure_main_test_dir(run_root)
  for i in 1..<=5 {
    let run_id = "run-" + i.to_string()
    let run_dir = run_root + "/" + run_id
    ensure_main_test_dir(run_dir)
    let json = "{\"run_id\": \"" +
      run_id +
      "\", \"workflow_name\": \"ci\", \"state\": \"completed\", \"status\": \"completed\", \"conclusion\": \"success\"}"
    @xfs.write_string_to_file(run_dir + "/run.json", json)
  }
  let all = format_run_list_text(run_root_abs).unwrap_or("")
  let all_lines : Array[String] = []
  for line in all.trim_end(chars="\n").to_string().split("\n") {
    let s = line.to_string()
    if s.length() > 0 {
      all_lines.push(s)
    }
  }
  inspect(all_lines.length(), content="5")
  let limited = format_run_list_text(run_root_abs, limit=2).unwrap_or("")
  let limited_lines : Array[String] = []
  for line in limited.trim_end(chars="\n").to_string().split("\n") {
    let s = line.to_string()
    if s.length() > 0 {
      limited_lines.push(s)
    }
  }
  inspect(limited_lines.length(), content="2")
  // Most recent runs first (reverse order)
  inspect(limited_lines[0].contains("run-5"), content="true")
  inspect(limited_lines[1].contains("run-4"), content="true")
}

///|
#cfg(target="native")
test "gh-compat: run list with --status filters by conclusion" {
  let run_root = "_build/test-main/gh-compat-status"
  remove_main_test_tree(run_root)
  let run_root_abs = main_test_absolute_path(run_root)
  ensure_main_test_dir(run_root)
  ensure_main_test_dir(run_root + "/run-1")
  @xfs.write_string_to_file(
    run_root + "/run-1/run.json",
    "{\"run_id\": \"run-1\", \"workflow_name\": \"ci\", \"state\": \"completed\", \"status\": \"completed\", \"conclusion\": \"success\"}",
  )
  ensure_main_test_dir(run_root + "/run-2")
  @xfs.write_string_to_file(
    run_root + "/run-2/run.json",
    "{\"run_id\": \"run-2\", \"workflow_name\": \"ci\", \"state\": \"completed\", \"status\": \"completed\", \"conclusion\": \"failure\"}",
  )
  ensure_main_test_dir(run_root + "/run-3")
  @xfs.write_string_to_file(
    run_root + "/run-3/run.json",
    "{\"run_id\": \"run-3\", \"workflow_name\": \"ci\", \"state\": \"completed\", \"status\": \"completed\", \"conclusion\": \"success\"}",
  )
  let failure_text = format_run_list_text(run_root_abs, status_filter="failure").unwrap_or(
    "",
  )
  inspect(failure_text.contains("run-2"), content="true")
  inspect(failure_text.contains("run-1"), content="false")
  inspect(failure_text.contains("run-3"), content="false")
  let success_text = format_run_list_text(run_root_abs, status_filter="success").unwrap_or(
    "",
  )
  inspect(success_text.contains("run-1"), content="true")
  inspect(success_text.contains("run-3"), content="true")
  inspect(success_text.contains("run-2"), content="false")
}

///|
#cfg(target="native")
test "gh-compat: run list --json with field selection" {
  let run_root = "_build/test-main/gh-compat-list-fields"
  remove_main_test_tree(run_root)
  let run_root_abs = main_test_absolute_path(run_root)
  ensure_main_test_dir(run_root)
  ensure_main_test_dir(run_root + "/run-1")
  @xfs.write_string_to_file(
    run_root + "/run-1/run.json",
    "{\"run_id\": \"run-1\", \"workflow_name\": \"ci\", \"state\": \"completed\", \"status\": \"completed\", \"conclusion\": \"success\", \"ok\": true}",
  )
  let json = collect_run_list_json(run_root_abs, json_fields=[
    "status", "conclusion",
  ]).unwrap_or("")
  inspect(json.contains("\"status\""), content="true")
  inspect(json.contains("\"conclusion\""), content="true")
  // Fields not requested should be absent
  inspect(json.contains("\"run_id\""), content="false")
  inspect(json.contains("\"workflow_name\""), content="false")
  inspect(json.contains("\"ok\""), content="false")
}

///|
#cfg(target="native")
test "gh-compat: run list --status with --limit combined" {
  let run_root = "_build/test-main/gh-compat-status-limit"
  remove_main_test_tree(run_root)
  let run_root_abs = main_test_absolute_path(run_root)
  ensure_main_test_dir(run_root)
  for i in 1..<=4 {
    let run_id = "run-" + i.to_string()
    ensure_main_test_dir(run_root + "/" + run_id)
    let conclusion = if i % 2 == 0 { "failure" } else { "success" }
    @xfs.write_string_to_file(
      run_root + "/" + run_id + "/run.json",
      "{\"run_id\": \"" +
      run_id +
      "\", \"workflow_name\": \"ci\", \"state\": \"completed\", \"status\": \"completed\", \"conclusion\": \"" +
      conclusion +
      "\"}",
    )
  }
  // 4 runs: run-1=success, run-2=failure, run-3=success, run-4=failure
  // Reverse order: run-4, run-3, run-2, run-1
  // Filter failure + limit 1 → run-4 only
  let filtered = format_run_list_text(
    run_root_abs,
    status_filter="failure",
    limit=1,
  ).unwrap_or("")
  inspect(filtered.contains("run-4"), content="true")
  inspect(filtered.contains("run-2"), content="false")
}

///|
#cfg(target="native")
test "gh-compat: handle_run_read_command view --exit-status returns 1 for failure" {
  let run_root = "_build/test-main/gh-compat-exit-status"
  remove_main_test_tree(run_root)
  ensure_main_test_dir(run_root)
  ensure_main_test_dir(run_root + "/run-1")
  @xfs.write_string_to_file(
    run_root + "/run-1/run.json",
    "{\"run_id\": \"run-1\", \"workflow_name\": \"ci\", \"state\": \"completed\", \"status\": \"completed\", \"conclusion\": \"failure\", \"ok\": false, \"exit_code\": 1}",
  )
  ensure_main_test_dir(run_root + "/run-2")
  @xfs.write_string_to_file(
    run_root + "/run-2/run.json",
    "{\"run_id\": \"run-2\", \"workflow_name\": \"ci\", \"state\": \"completed\", \"status\": \"completed\", \"conclusion\": \"success\", \"ok\": true, \"exit_code\": 0}",
  )
  let exit_fail = handle_run_read_command({
    action: "view",
    run_id: "run-1",
    run_root: Some(run_root),
    task_id: None,
    artifact_root: None,
    download_dir: ".",
    json_output: false,
    json_fields: [],
    jq_expr: "",
    limit: 0,
    status_filter: "",
    exit_status: true,
    verbose: false,
    show_log: false,
    log_failed: false,
    job_id: "",
    workflow_filter: "",
    branch_filter: "",
    event_filter: "",
  })
  inspect(exit_fail, content="1")
  let exit_success = handle_run_read_command({
    action: "view",
    run_id: "run-2",
    run_root: Some(run_root),
    task_id: None,
    artifact_root: None,
    download_dir: ".",
    json_output: false,
    json_fields: [],
    jq_expr: "",
    limit: 0,
    status_filter: "",
    exit_status: true,
    verbose: false,
    show_log: false,
    log_failed: false,
    job_id: "",
    workflow_filter: "",
    branch_filter: "",
    event_filter: "",
  })
  inspect(exit_success, content="0")
  // Without --exit-status, always 0
  let exit_no_flag = handle_run_read_command({
    action: "view",
    run_id: "run-1",
    run_root: Some(run_root),
    task_id: None,
    artifact_root: None,
    download_dir: ".",
    json_output: false,
    json_fields: [],
    jq_expr: "",
    limit: 0,
    status_filter: "",
    exit_status: false,
    verbose: false,
    show_log: false,
    log_failed: false,
    job_id: "",
    workflow_filter: "",
    branch_filter: "",
    event_filter: "",
  })
  inspect(exit_no_flag, content="0")
}

///|
#cfg(target="native")
test "gh-compat: handle_run_read_command view --json fields filters output" {
  let run_root = "_build/test-main/gh-compat-view-fields"
  remove_main_test_tree(run_root)
  ensure_main_test_dir(run_root)
  ensure_main_test_dir(run_root + "/run-1")
  @xfs.write_string_to_file(
    run_root + "/run-1/run.json",
    "{\"run_id\": \"run-1\", \"workflow_name\": \"ci\", \"status\": \"completed\", \"conclusion\": \"success\", \"jobs\": []}",
  )
  // Call filter_json_fields directly to verify (handle_run_read_command prints to stdout)
  let run_json = @xfs.read_file_to_string(run_root + "/run-1/run.json")
  let filtered = filter_json_fields(run_json, ["status", "conclusion"]).unwrap()
  inspect(filtered.contains("\"status\""), content="true")
  inspect(filtered.contains("\"conclusion\""), content="true")
  inspect(filtered.contains("\"run_id\""), content="false")
  inspect(filtered.contains("\"workflow_name\""), content="false")
  inspect(filtered.contains("\"jobs\""), content="false")
}

///|
#cfg(target="native")
test "gh-compat: format_run_list_text shows conclusion instead of state" {
  let run_root = "_build/test-main/gh-compat-list-conclusion"
  remove_main_test_tree(run_root)
  let run_root_abs = main_test_absolute_path(run_root)
  ensure_main_test_dir(run_root)
  ensure_main_test_dir(run_root + "/run-1")
  @xfs.write_string_to_file(
    run_root + "/run-1/run.json",
    "{\"run_id\": \"run-1\", \"workflow_name\": \"ci\", \"state\": \"completed\", \"conclusion\": \"success\"}",
  )
  let text = format_run_list_text(run_root_abs).unwrap_or("")
  // Should display both status and conclusion, plus workflow name and run id
  inspect(text.contains("success"), content="true")
  inspect(text.contains("ci"), content="true")
  inspect(text.contains("run-1"), content="true")
}

///|
#cfg(target="native")
async test "gh-compat: end-to-end workflow produces gh-compatible JSON" {
  ensure_main_test_dir("_build")
  ensure_main_test_dir("_build/test-main")
  let workspace_rel = "_build/test-main/gh-compat-e2e-workspace"
  let workspace = main_test_absolute_path(workspace_rel)
  let run_root = "_build/test-main/gh-compat-e2e-runs"
  remove_main_test_tree(workspace_rel)
  remove_main_test_tree(run_root)
  ensure_main_test_dir(workspace_rel)
  let workflow_src =
    #|name: e2e-test
    #|'on':
    #|  push:
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: hello
    #|        name: Say Hello
    #|        run: echo hello
    #|      - id: world
    #|        name: Say World
    #|        run: echo world
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
      @ar.new_push_event("main", ["README.md"], repository="owner/repo"),
    ),
  )
  let run_id = persist_run_record(
    run_root,
    {
      run_id: "",
      workflow_name: "e2e-test",
      workflow_path: ".github/workflows/e2e.yml",
      workspace_root: workspace,
      workspace_mode: "local",
      started_at_ms: 1000UL,
      finished_at_ms: 2000UL,
      event: "push",
      state: report.state,
      ok: report.ok,
      exit_code: 0,
      repository: "owner/repo",
      ref_name: "main",
      before_sha: "",
      after_sha: "",
      changed_paths: [],
    },
    report=Some(report),
    plan=Some(lowered.plan),
  ).unwrap_or("")
  inspect(run_id, content="run-1")
  let run_json = @xfs.read_file_to_string(run_root + "/run-1/run.json")
  // Top-level gh-compat fields
  inspect(run_json.contains("\"status\": \"completed\""), content="true")
  inspect(run_json.contains("\"conclusion\": \"success\""), content="true")
  // Job has gh-compat fields
  inspect(run_json.contains("\"name\": \"build\""), content="true")
  let payload = @json.parse(run_json) catch { _ => abort("parse failed") }
  let jobs = run_json_array(payload, "jobs")
  inspect(jobs.length(), content="1")
  guard jobs[0]
    is {
      "id": String(job_id),
      "name": String(job_name),
      "status": String(job_status),
      "conclusion": String(job_conclusion),
      "steps": Array(steps),
      ..
    } else {
    abort("job structure mismatch")
  }
  inspect(job_id, content="build")
  inspect(job_name, content="build")
  inspect(job_status, content="completed")
  inspect(job_conclusion, content="success")
  // Steps include the named steps
  assert_true(steps.length() >= 2)
  let step_names : Array[String] = []
  for step in steps {
    if step is { "name": String(name), .. } {
      step_names.push(name)
    }
  }
  inspect(step_names.contains("Say Hello"), content="true")
  inspect(step_names.contains("Say World"), content="true")
  // Verify field filtering works on persisted JSON
  let filtered = filter_json_fields(run_json, ["status", "conclusion", "jobs"]).unwrap()
  inspect(filtered.contains("\"status\""), content="true")
  inspect(filtered.contains("\"conclusion\""), content="true")
  inspect(filtered.contains("\"jobs\""), content="true")
  inspect(filtered.contains("\"run_id\""), content="false")
  inspect(filtered.contains("\"tasks\""), content="false")
}

///|
#cfg(target="native")
async test "gh-compat: --log-failed and --job filter logs" {
  ensure_main_test_dir("_build")
  ensure_main_test_dir("_build/test-main")
  let workspace_rel = "_build/test-main/gh-compat-log-failed-workspace"
  let workspace = main_test_absolute_path(workspace_rel)
  let run_root = "_build/test-main/gh-compat-log-failed-runs"
  remove_main_test_tree(workspace_rel)
  remove_main_test_tree(run_root)
  ensure_main_test_dir(workspace_rel)
  let workflow_src =
    #|name: log-test
    #|'on':
    #|  push:
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: passing
    #|        name: Passing Step
    #|        run: echo pass
    #|      - id: failing
    #|        name: Failing Step
    #|        run: echo fail-output && exit 1
    #|        continue-on-error: true
    #|  test:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: check
    #|        name: Check
    #|        run: echo check-ok
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
      @ar.new_push_event("main", ["README.md"], repository="owner/repo"),
    ),
  )
  let run_id = persist_run_record(
    run_root,
    {
      run_id: "",
      workflow_name: "log-test",
      workflow_path: ".github/workflows/log-test.yml",
      workspace_root: workspace,
      workspace_mode: "local",
      started_at_ms: 1000UL,
      finished_at_ms: 2000UL,
      event: "push",
      state: report.state,
      ok: report.ok,
      exit_code: 0,
      repository: "",
      ref_name: "",
      before_sha: "",
      after_sha: "",
      changed_paths: [],
    },
    report=Some(report),
    plan=Some(lowered.plan),
  ).unwrap_or("")
  inspect(run_id, content="run-1")
  let run_dir = run_root + "/run-1"
  let run_json = @xfs.read_file_to_string(run_dir + "/run.json")
  // --job build: only build job logs
  let job_logs = format_run_logs_text(run_dir, run_json, job_filter="build").unwrap_or(
    "",
  )
  inspect(job_logs.contains("build/passing"), content="true")
  inspect(job_logs.contains("test/check"), content="false")
  // --job test: only test job logs
  let test_logs = format_run_logs_text(run_dir, run_json, job_filter="test").unwrap_or(
    "",
  )
  inspect(test_logs.contains("test/check"), content="true")
  inspect(test_logs.contains("build/passing"), content="false")
  // --log-failed: only failed tasks
  let failed_logs = format_run_logs_text(run_dir, run_json, log_failed=true).unwrap_or(
    "",
  )
  inspect(failed_logs.contains("build/failing"), content="true")
  inspect(failed_logs.contains("build/passing"), content="false")
  inspect(failed_logs.contains("test/check"), content="false")
  // --log-failed --job build: failed tasks in build job only
  let job_failed_logs = format_run_logs_text(
    run_dir,
    run_json,
    log_failed=true,
    job_filter="build",
  ).unwrap_or("")
  inspect(job_failed_logs.contains("build/failing"), content="true")
  inspect(job_failed_logs.contains("build/passing"), content="false")
}

///|
test "cli: parse run rerun gives helpful error" {
  let result = parse_run_read_args(["actrun", "run", "rerun", "run-1"])
  assert_true(result.errors.length() > 0)
  inspect(result.errors[0].contains("--retry"), content="true")
}

///|
test "cli: parse run delete" {
  let result = parse_run_read_args([
    "actrun", "run", "delete", "run-1", "--run-root", "/tmp/runs",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("run delete parse failed")
  }
  inspect(options.action, content="delete")
  inspect(options.run_id, content="run-1")
}

///|
#cfg(target="native")
test "gh-compat: run delete removes run directory" {
  let run_root = "_build/test-main/gh-compat-run-delete"
  remove_main_test_tree(run_root)
  ensure_main_test_dir(run_root)
  ensure_main_test_dir(run_root + "/run-1")
  @xfs.write_string_to_file(
    run_root + "/run-1/run.json",
    "{\"run_id\": \"run-1\"}",
  )
  inspect(@xfs.path_exists(run_root + "/run-1"), content="true")
  let exit_code = handle_run_read_command({
    action: "delete",
    run_id: "run-1",
    run_root: Some(run_root),
    task_id: None,
    artifact_root: None,
    download_dir: ".",
    json_output: false,
    json_fields: [],
    jq_expr: "",
    limit: 0,
    status_filter: "",
    exit_status: false,
    verbose: false,
    show_log: false,
    log_failed: false,
    job_id: "",
    workflow_filter: "",
    branch_filter: "",
    event_filter: "",
  })
  inspect(exit_code, content="0")
  inspect(@xfs.path_exists(run_root + "/run-1"), content="false")
}

///|
#cfg(target="native")
test "gh-compat: run delete returns 1 for missing run" {
  let run_root = "_build/test-main/gh-compat-run-delete-missing"
  remove_main_test_tree(run_root)
  ensure_main_test_dir(run_root)
  let exit_code = handle_run_read_command({
    action: "delete",
    run_id: "run-99",
    run_root: Some(run_root),
    task_id: None,
    artifact_root: None,
    download_dir: ".",
    json_output: false,
    json_fields: [],
    jq_expr: "",
    limit: 0,
    status_filter: "",
    exit_status: false,
    verbose: false,
    show_log: false,
    log_failed: false,
    job_id: "",
    workflow_filter: "",
    branch_filter: "",
    event_filter: "",
  })
  inspect(exit_code, content="1")
}

///|
test "cli: filter_json_array_fields filters each item" {
  let json = "[{\"name\": \"a\", \"key\": \"1\"}, {\"name\": \"b\", \"key\": \"2\"}]"
  let filtered = filter_json_array_fields(json, ["name"]).unwrap()
  inspect(filtered.contains("\"name\""), content="true")
  inspect(filtered.contains("\"key\""), content="false")
}

///|
test "cli: filter_json_array_fields with empty fields returns all" {
  let json = "[{\"name\": \"a\", \"key\": \"1\"}]"
  let filtered = filter_json_array_fields(json, []).unwrap()
  inspect(filtered.contains("\"name\""), content="true")
  inspect(filtered.contains("\"key\""), content="true")
}

///|
test "cli: format_elapsed computes duration" {
  let text = format_elapsed("1000", "3000")
  inspect(text, content="2s")
  let text2 = format_elapsed("1000", "121000")
  inspect(text2, content="2m0s")
}

///|
test "cli: parse cache list with --limit and --json fields" {
  let result = parse_cache_read_args([
    "actrun", "cache", "list", "--limit", "5", "--json", "key,files",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("cache list parse failed")
  }
  inspect(options.limit, content="5")
  inspect(options.json_fields, content="[\"key\", \"files\"]")
}

///|
test "cli: parse workflow list with --json fields" {
  let result = parse_workflow_read_args([
    "actrun", "workflow", "list", "--json", "name",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("workflow list parse failed")
  }
  inspect(options.json_fields, content="[\"name\"]")
}

///|
test "cli: parse run view with --jq" {
  let result = parse_run_read_args([
    "actrun", "run", "view", "run-1", "--json", "jobs", "--jq", ".jobs[] | .name",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("parse failed")
  }
  inspect(options.json_output, content="true")
  inspect(options.json_fields, content="[\"jobs\"]")
  inspect(options.jq_expr, content=".jobs[] | .name")
}

///|
test "cli: parse run view with -q shorthand" {
  let result = parse_run_read_args([
    "actrun", "run", "view", "run-1", "-q", ".status",
  ])
  inspect(result.errors, content="[]")
  let options = match result.options {
    Some(value) => value
    None => abort("parse failed")
  }
  inspect(options.json_output, content="true")
  inspect(options.jq_expr, content=".status")
}

///|
test "cli: apply_jq extracts field" {
  let json = "{\"status\": \"completed\", \"conclusion\": \"success\"}"
  let result = apply_jq(json, ".conclusion").unwrap()
  inspect(result, content="\"success\"")
}

///|
test "cli: apply_jq array iteration" {
  let json = "[{\"name\": \"a\"}, {\"name\": \"b\"}]"
  let result = apply_jq(json, ".[] | .name").unwrap()
  inspect(result, content="\"a\"\n\"b\"")
}

///|
test "cli: apply_jq object construction" {
  let json = "{\"id\": \"build\", \"status\": \"completed\", \"conclusion\": \"success\"}"
  let result = apply_jq(json, "{id: .id, conclusion: .conclusion}").unwrap()
  inspect(
    result.contains("\"id\"") && result.contains("\"conclusion\""),
    content="true",
  )
}

///|
test "cli: apply_jq empty expr returns input" {
  let json = "{\"x\": 1}"
  let result = apply_jq(json, "").unwrap()
  inspect(result, content="{\"x\": 1}")
}

///|
test "cli: apply_json_pipeline combines fields and jq" {
  let json = "{\"status\": \"completed\", \"conclusion\": \"success\", \"jobs\": []}"
  let result = apply_json_pipeline(
    json,
    ["status", "conclusion"],
    ".conclusion",
  )
  inspect(result, content="\"success\"")
}

// --- dotenv parser tests ---

///|
fn dotenv_get(content : String, key : String) -> String {
  parse_dotenv(content).entries.get(key).unwrap_or("")
}

///|
test "dotenv: basic key=value" {
  let r = parse_dotenv("FOO=bar")
  inspect(r.entries.get("FOO").unwrap_or(""), content="bar")
}

///|
test "dotenv: empty lines and comments" {
  let input =
    #|# this is a comment
    #|
    #|FOO=bar
    #|
    #|# another comment
    #|BAZ=qux
  let r = parse_dotenv(input)
  inspect(r.entries.get("FOO").unwrap_or(""), content="bar")
  inspect(r.entries.get("BAZ").unwrap_or(""), content="qux")
}

///|
test "dotenv: double-quoted value" {
  inspect(dotenv_get("FOO=\"hello world\"", "FOO"), content="hello world")
}

///|
test "dotenv: single-quoted value" {
  inspect(dotenv_get("FOO='hello world'", "FOO"), content="hello world")
}

///|
test "dotenv: export prefix" {
  inspect(dotenv_get("export FOO=bar", "FOO"), content="bar")
  inspect(dotenv_get("export FOO=\"bar\"", "FOO"), content="bar")
}

///|
test "dotenv: whitespace around key and value" {
  inspect(dotenv_get("  FOO  =  bar  ", "FOO"), content="bar")
}

///|
test "dotenv: inline comment (unquoted)" {
  inspect(dotenv_get("FOO=bar # this is a comment", "FOO"), content="bar")
}

///|
test "dotenv: inline comment not stripped in quoted" {
  inspect(
    dotenv_get("FOO=\"bar # not a comment\"", "FOO"),
    content="bar # not a comment",
  )
}

///|
test "dotenv: escape sequences in double quotes" {
  inspect(dotenv_get("FOO=\"line1\\nline2\"", "FOO"), content="line1\nline2")
  inspect(dotenv_get("FOO=\"tab\\there\"", "FOO"), content="tab\there")
  inspect(dotenv_get("FOO=\"back\\\\slash\"", "FOO"), content="back\\slash")
  inspect(
    dotenv_get("FOO=\"escaped\\\"quote\"", "FOO"),
    content="escaped\"quote",
  )
}

///|
test "dotenv: no escape in single quotes" {
  inspect(dotenv_get("FOO='hello\\nworld'", "FOO"), content="hello\\nworld")
}

///|
test "dotenv: multiline double-quoted value" {
  let content = "FOO=\"line1\nline2\nline3\""
  inspect(dotenv_get(content, "FOO"), content="line1\nline2\nline3")
}

///|
test "dotenv: multiline single-quoted value" {
  let content = "FOO='line1\nline2'"
  inspect(dotenv_get(content, "FOO"), content="line1\nline2")
}

///|
test "dotenv: variable expansion ${VAR}" {
  let r = parse_dotenv("BASE=/app\nPATH_FULL=${BASE}/bin")
  inspect(r.entries.get("PATH_FULL").unwrap_or(""), content="/app/bin")
}

///|
test "dotenv: variable expansion $VAR" {
  let r = parse_dotenv("NAME=world\nGREET=hello_$NAME")
  inspect(r.entries.get("GREET").unwrap_or(""), content="hello_world")
}

///|
test "dotenv: no expansion in single quotes" {
  let r = parse_dotenv("NAME=world\nGREET='hello $NAME'")
  inspect(r.entries.get("GREET").unwrap_or(""), content="hello $NAME")
}

///|
test "dotenv: expansion in double quotes" {
  let r = parse_dotenv("NAME=world\nGREET=\"hello ${NAME}\"")
  inspect(r.entries.get("GREET").unwrap_or(""), content="hello world")
}

///|
test "dotenv: empty value" {
  inspect(dotenv_get("FOO=", "FOO"), content="")
}

///|
test "dotenv: empty quoted value" {
  inspect(dotenv_get("FOO=\"\"", "FOO"), content="")
  inspect(dotenv_get("FOO=''", "FOO"), content="")
}

///|
test "dotenv: value with equals sign" {
  inspect(dotenv_get("FOO=a=b=c", "FOO"), content="a=b=c")
}

///|
test "dotenv: multiple entries" {
  let input =
    #|A=1
    #|B=2
    #|C=3
  let r = parse_dotenv(input)
  inspect(r.entries.get("A").unwrap_or(""), content="1")
  inspect(r.entries.get("B").unwrap_or(""), content="2")
  inspect(r.entries.get("C").unwrap_or(""), content="3")
}

///|
test "dotenv: later value overrides earlier" {
  let r = parse_dotenv("FOO=first\nFOO=second")
  inspect(r.entries.get("FOO").unwrap_or(""), content="second")
}

///|
test "dotenv: hash in unquoted value without space" {
  // # without preceding space is NOT a comment
  inspect(dotenv_get("COLOR=#ffffff", "COLOR"), content="#ffffff")
}

///|
test "dotenv: lines without = are ignored" {
  let r = parse_dotenv("not_a_pair\nFOO=bar")
  inspect(r.entries.get("FOO").unwrap_or(""), content="bar")
  assert_true(r.entries.get("not_a_pair") is None)
}

///|
test "dotenv: windows line endings" {
  let r = parse_dotenv("FOO=bar\r\nBAZ=qux\r\n")
  inspect(r.entries.get("FOO").unwrap_or(""), content="bar")
  inspect(r.entries.get("BAZ").unwrap_or(""), content="qux")
}

///|
test "dotenv: chained variable expansion" {
  let r = parse_dotenv("A=hello\nB=${A}_world\nC=${B}_!")
  inspect(r.entries.get("C").unwrap_or(""), content="hello_world_!")
}

///|
test "dotenv: undefined variable expands to empty" {
  let r = parse_dotenv("FOO=${UNDEFINED_VAR_12345}")
  inspect(r.entries.get("FOO").unwrap_or(""), content="")
}

///|
test "cli: parse --no-nix flag" {
  let result = parse_cli_args(["actrun", "ci.yml", "--no-nix"])
  inspect(result.errors, content="[]")
  let options = expect_cli_options(result)
  inspect(options.nix_mode, content="off")
  inspect(options.nix_packages, content="[]")
}

///|
test "cli: parse --nix flag" {
  let result = parse_cli_args(["actrun", "ci.yml", "--nix"])
  inspect(result.errors, content="[]")
  let options = expect_cli_options(result)
  inspect(options.nix_mode, content="auto")
}

///|
test "cli: parse --nix-packages flag" {
  let result = parse_cli_args([
    "actrun", "ci.yml", "--nix-packages", "python312 nodejs",
  ])
  inspect(result.errors, content="[]")
  let options = expect_cli_options(result)
  inspect(
    options.nix_packages,
    content=(
      #|["python312", "nodejs"]
    ),
  )
}

///|
test "toml: parse string values" {
  let root = @toml.parse(
    "workspace_mode = \"worktree\"\ntrust_actions = true\n",
  )
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  inspect(toml_get_string(table, "workspace_mode"), content="worktree")
  inspect(toml_get_bool(table, "trust_actions"), content="true")
}

///|
test "toml: parse array values" {
  let root = @toml.parse(
    "skip_actions = [\"actions/checkout\", \"actions/setup-node\"]\n",
  )
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  inspect(
    toml_get_string_array(table, "skip_actions"),
    content="[\"actions/checkout\", \"actions/setup-node\"]",
  )
}

///|
test "toml: skip comments and empty lines" {
  let root = @toml.parse("# comment\n\nworkspace_mode = \"local\"\n")
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  inspect(toml_get_string(table, "workspace_mode"), content="local")
}

///|
test "toml: section headers" {
  let root = @toml.parse("[section]\nkey = \"value\"\n")
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  let section = toml_get_table(table, "section")
  inspect(toml_get_string(section, "key"), content="value")
}

///|
test "toml: top-level keys and sections" {
  let root = @toml.parse("top = \"val\"\n[section]\nkey = \"value\"\n")
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  inspect(toml_get_string(table, "top"), content="val")
  let section = toml_get_table(table, "section")
  inspect(toml_get_string(section, "key"), content="value")
}

///|
test "config: merge cli overrides config" {
  let config : ActrunConfig = {
    workspace_mode: "worktree",
    local_skip_actions: ["actions/checkout"],
    trust_actions: true,
    nix_mode: "auto",
    nix_packages: ["python312"],
    container_runtime: "podman",
    local_override_actions: {},
    affected: {},
    includes: [],
    lint_ignore_rules: [],
    lint_preset: "default",
    include_dirty: false,
  }
  let cli = parse_cli_args(["actrun", "ci.yml", "--local", "--no-nix"])
  let options = expect_cli_options(cli)
  let merged = merge_config_into_options(options, config)
  // CLI --local overrides config worktree
  inspect(merged.workspace_mode, content="local")
  // CLI --no-nix overrides config auto
  inspect(merged.nix_mode, content="off")
  // Config values used when CLI has no override
  inspect(merged.trust_actions, content="true")
  inspect(
    merged.skip_actions,
    content=(
      #|["actions/checkout"]
    ),
  )
}

///|
test "config: cli skip_actions overrides local_skip_actions" {
  let config : ActrunConfig = {
    workspace_mode: "",
    local_skip_actions: ["actions/checkout"],
    trust_actions: false,
    nix_mode: "",
    nix_packages: [],
    container_runtime: "",
    local_override_actions: {},
    affected: {},
    includes: [],
    lint_ignore_rules: [],
    lint_preset: "default",
    include_dirty: false,
  }
  let cli = parse_cli_args([
    "actrun", "ci.yml", "--skip-action", "actions/setup-node",
  ])
  let options = expect_cli_options(cli)
  let merged = merge_config_into_options(options, config)
  inspect(
    merged.skip_actions,
    content=(
      #|["actions/setup-node"]
    ),
  )
}

///|
test "config: default when no actrun.toml" {
  let config = load_actrun_config("/nonexistent/path")
  inspect(config.workspace_mode, content="")
  inspect(config.trust_actions, content="false")
  inspect(config.local_skip_actions, content="[]")
}

///|
test "cli: parse --container-runtime flag" {
  let result = parse_cli_args([
    "actrun", "ci.yml", "--container-runtime", "podman",
  ])
  inspect(result.errors, content="[]")
  let options = expect_cli_options(result)
  inspect(options.container_runtime, content="podman")
}

///|
test "config: container_runtime from config" {
  let config : ActrunConfig = {
    workspace_mode: "",
    local_skip_actions: [],
    trust_actions: false,
    nix_mode: "",
    nix_packages: [],
    container_runtime: "podman",
    local_override_actions: {},
    affected: {},
    includes: [],
    lint_ignore_rules: [],
    lint_preset: "default",
    include_dirty: false,
  }
  let cli = parse_cli_args(["actrun", "ci.yml"])
  let options = expect_cli_options(cli)
  let merged = merge_config_into_options(options, config)
  inspect(merged.container_runtime, content="podman")
}

///|
test "config: cli container_runtime overrides config" {
  let config : ActrunConfig = {
    workspace_mode: "",
    local_skip_actions: [],
    trust_actions: false,
    nix_mode: "",
    nix_packages: [],
    container_runtime: "docker",
    local_override_actions: {},
    affected: {},
    includes: [],
    lint_ignore_rules: [],
    lint_preset: "default",
    include_dirty: false,
  }
  let cli = parse_cli_args(["actrun", "ci.yml", "--container-runtime", "lima"])
  let options = expect_cli_options(cli)
  let merged = merge_config_into_options(options, config)
  inspect(merged.container_runtime, content="lima")
}

///|
test "container runtime: resolve bin names" {
  inspect(resolve_container_runtime_bin("docker"), content="(\"docker\", [])")
  inspect(resolve_container_runtime_bin("podman"), content="(\"podman\", [])")
  inspect(
    resolve_container_runtime_bin("container"),
    content="(\"container\", [])",
  )
  inspect(resolve_container_runtime_bin("nerdctl"), content="(\"nerdctl\", [])")
  inspect(
    resolve_container_runtime_bin("lima"),
    content=(
      #|("lima", ["nerdctl"])
    ),
  )
  inspect(
    resolve_container_runtime_bin("/usr/bin/custom"),
    content="(\"/usr/bin/custom\", [])",
  )
}

///|
test "toml: all-comments config parses as empty" {
  let template = "# comment line\n# key = \"value\"\n\n# another\n"
  let root = @toml.parse(template)
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  inspect(table.length(), content="0")
}

///|
test "toml: affected section parsing" {
  let root = @toml.parse(
    "[affected.\"ci.yml\"]\npatterns = [\"src/**\", \"*.toml\"]\n",
  )
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  let affected = toml_get_table(table, "affected")
  let ci = toml_get_table(affected, "ci.yml")
  inspect(
    toml_get_string_array(ci, "patterns"),
    content="[\"src/**\", \"*.toml\"]",
  )
}

///|
test "config: affected patterns loaded" {
  let root = @toml.parse("[affected.\"ci.yml\"]\npatterns = [\"src/**\"]\n")
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  let affected = toml_get_table(table, "affected")
  let result : Map[String, Array[String]] = {}
  for wf_name, wf_value in affected {
    match wf_value {
      @toml.TomlTable(wf_tbl) => {
        let patterns = toml_get_string_array(wf_tbl, "patterns")
        if patterns.length() > 0 {
          result[wf_name] = patterns
        }
      }
      _ => ()
    }
  }
  inspect(result.get("ci.yml"), content="Some([\"src/**\"])")
}

///|
test "glob_match: basic patterns" {
  // Exact match
  inspect(glob_match("README.md", "README.md"), content="true")
  inspect(glob_match("README.md", "src/main.rs"), content="false")
  // Wildcard extension
  inspect(glob_match("*.rs", "main.rs"), content="true")
  inspect(glob_match("*.rs", "main.ts"), content="false")
  // Directory prefix
  inspect(glob_match("src/**", "src/main.rs"), content="true")
  inspect(glob_match("src/**", "test/main.rs"), content="false")
  // Double-star extension
  inspect(glob_match("**/*.rs", "src/main.rs"), content="true")
  inspect(glob_match("**/*.rs", "main.rs"), content="true")
  inspect(glob_match("**/*.rs", "main.ts"), content="false")
  // Directory wildcard
  inspect(glob_match("src/*", "src/main.rs"), content="true")
  inspect(glob_match("src/*", "src/sub/main.rs"), content="false")
}

///|
test "files_match_patterns: matches at least one" {
  inspect(
    files_match_patterns(["src/main.rs", "README.md"], ["src/**"]),
    content="true",
  )
  inspect(
    files_match_patterns(["README.md", "docs/guide.md"], ["src/**"]),
    content="false",
  )
}

///|
test "glob_match: dir/*.ext patterns" {
  inspect(
    glob_match(".github/workflows/*.yml", ".github/workflows/ci.yml"),
    content="true",
  )
  inspect(
    glob_match(".github/workflows/*.yml", ".github/workflows/lint.yaml"),
    content="false",
  )
  inspect(
    glob_match(".github/workflows/*.yml", ".github/workflows/sub/ci.yml"),
    content="false",
  )
  inspect(glob_match("ci/*.yaml", "ci/test.yaml"), content="true")
  inspect(glob_match("ci/*.yaml", "ci/test.yml"), content="false")
}

///|
test "cli: parse --affected flag" {
  let result = parse_cli_args(["actrun", "ci.yml", "--affected"])
  let options = expect_cli_options(result)
  inspect(options.affected, content="true")
  inspect(options.retry, content="false")
}

///|
test "cli: parse --retry flag" {
  let result = parse_cli_args(["actrun", "ci.yml", "--retry"])
  let options = expect_cli_options(result)
  inspect(options.retry, content="true")
  inspect(options.affected, content="false")
}

///|
test "cli: parse --job and --step flags" {
  let result = parse_cli_args([
    "actrun", "ci.yml", "--job", "build", "--step", "test",
  ])
  let options = expect_cli_options(result)
  inspect(options.job_filter, content="build")
  inspect(options.step_filter, content="test")
}

///|
test "cli: parse --trigger flag" {
  let result = parse_cli_args(["actrun", "ci.yml", "--trigger", "schedule"])
  let options = expect_cli_options(result)
  inspect(options.trigger, content="schedule")
}

///|
test "extract_cron_schedules: basic" {
  let yaml = "on:\n  schedule:\n    - cron: '0 2 * * *'\n    - cron: '30 5 * * 1'\njobs:\n"
  let schedules = extract_cron_schedules(yaml)
  inspect(
    schedules,
    content=(
      #|["0 2 * * *", "30 5 * * 1"]
    ),
  )
}

///|
test "extract_cron_schedules: no schedule" {
  let yaml = "on: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n"
  let schedules = extract_cron_schedules(yaml)
  inspect(schedules, content="[]")
}

// --- glob_match tests ---

///|
test "glob_match: exact match" {
  inspect(glob_match("README.md", "README.md"), content="true")
  inspect(glob_match("README.md", "readme.md"), content="false")
  inspect(glob_match("src/main.rs", "src/main.rs"), content="true")
}

///|
test "glob_match: wildcard all" {
  inspect(glob_match("*", "anything"), content="true")
  inspect(glob_match("**", "any/path"), content="true")
  inspect(glob_match("**/*", "any/path/file"), content="true")
}

///|
test "glob_match: directory recursive (**)" {
  inspect(glob_match("src/**", "src/main.rs"), content="true")
  inspect(glob_match("src/**", "src/sub/deep/file.rs"), content="true")
  inspect(glob_match("src/**", "src"), content="true")
  inspect(glob_match("src/**", "tests/main.rs"), content="false")
  inspect(glob_match("src/**", "src2/main.rs"), content="false")
}

///|
test "glob_match: extension wildcard (**/*.ext)" {
  inspect(glob_match("**/*.rs", "src/main.rs"), content="true")
  inspect(glob_match("**/*.rs", "main.rs"), content="true")
  inspect(glob_match("**/*.rs", "src/sub/lib.rs"), content="true")
  inspect(glob_match("**/*.rs", "src/main.ts"), content="false")
}

///|
test "glob_match: root extension wildcard (*.ext)" {
  inspect(glob_match("*.toml", "Cargo.toml"), content="true")
  inspect(glob_match("*.toml", "moon.mod.toml"), content="true")
  inspect(glob_match("*.toml", "src/config.toml"), content="true")
  inspect(glob_match("*.md", "README.md"), content="true")
  inspect(glob_match("*.md", "src/README.md"), content="true")
}

///|
test "glob_match: directory non-recursive (dir/*)" {
  inspect(glob_match("src/*", "src/main.rs"), content="true")
  inspect(glob_match("src/*", "src/lib.rs"), content="true")
  inspect(glob_match("src/*", "src/sub/deep.rs"), content="false")
  inspect(glob_match("src/*", "tests/main.rs"), content="false")
}

///|
test "glob_match: directory with extension (dir/*.ext)" {
  inspect(glob_match("src/*.rs", "src/main.rs"), content="true")
  inspect(glob_match("src/*.rs", "src/lib.rs"), content="true")
  inspect(glob_match("src/*.rs", "src/main.ts"), content="false")
  inspect(glob_match("src/*.rs", "src/sub/main.rs"), content="false")
}

///|
test "glob_match: prefix match (directory)" {
  inspect(glob_match("docs", "docs/intro.md"), content="true")
  inspect(glob_match("docs", "docs"), content="true")
  inspect(glob_match("docs", "docs2/intro.md"), content="false")
}

///|
test "glob_match: path suffix match (**/filename)" {
  inspect(glob_match("**/package.json", "package.json"), content="true")
  inspect(glob_match("**/package.json", "sub/package.json"), content="true")
  inspect(
    glob_match("**/package.json", "deep/sub/package.json"),
    content="true",
  )
  inspect(glob_match("**/package.json", "package.lock"), content="false")
}

// --- files_match_patterns tests ---

///|
test "files_match_patterns: basic matching" {
  inspect(
    files_match_patterns(["src/main.rs", "README.md"], ["src/**"]),
    content="true",
  )
  inspect(
    files_match_patterns(["README.md", "docs/intro.md"], ["src/**"]),
    content="false",
  )
}

///|
test "files_match_patterns: multiple patterns" {
  inspect(
    files_match_patterns(["docs/intro.md"], ["src/**", "docs/**", "*.toml"]),
    content="true",
  )
  inspect(
    files_match_patterns(["Cargo.toml"], ["src/**", "docs/**", "*.toml"]),
    content="true",
  )
  inspect(
    files_match_patterns(["README.md"], ["src/**", "docs/**", "*.toml"]),
    content="false",
  )
}

///|
test "files_match_patterns: empty inputs" {
  inspect(files_match_patterns([], ["src/**"]), content="false")
  inspect(files_match_patterns(["src/main.rs"], []), content="false")
  inspect(files_match_patterns([], []), content="false")
}

///|
test "files_match_patterns: exact file patterns" {
  inspect(
    files_match_patterns(["package.json", "src/index.ts"], [
      "package.json", "pnpm-lock.yaml",
    ]),
    content="true",
  )
  inspect(
    files_match_patterns(["src/index.ts"], ["package.json", "pnpm-lock.yaml"]),
    content="false",
  )
}

///|
test "files_match_patterns: realistic CI patterns" {
  // Typical patterns from actrun.toml or on:push:paths
  let patterns = ["src/**", "package.json", "pnpm-lock.yaml"]
  inspect(files_match_patterns(["src/lib/parser.ts"], patterns), content="true")
  inspect(files_match_patterns(["package.json"], patterns), content="true")
  inspect(files_match_patterns(["pnpm-lock.yaml"], patterns), content="true")
  inspect(files_match_patterns(["README.md"], patterns), content="false")
  inspect(
    files_match_patterns(
      ["docs/guide.md", ".github/workflows/ci.yml"],
      patterns,
    ),
    content="false",
  )
}

// --- affected config parsing tests ---

///|
test "toml: affected with quoted key" {
  let root = @toml.parse(
    "[affected.\"ci.yml\"]\npatterns = [\"src/**\", \"*.toml\"]\n",
  )
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  let affected = toml_get_table(table, "affected")
  let ci = toml_get_table(affected, "ci.yml")
  inspect(
    toml_get_string_array(ci, "patterns"),
    content="[\"src/**\", \"*.toml\"]",
  )
}

///|
test "toml: affected with path key" {
  let root = @toml.parse(
    "[affected.\".github/workflows/ci.yml\"]\npatterns = [\"src/**\"]\n",
  )
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  let affected = toml_get_table(table, "affected")
  let ci = toml_get_table(affected, ".github/workflows/ci.yml")
  inspect(toml_get_string_array(ci, "patterns"), content="[\"src/**\"]")
}

///|
test "toml: affected patterns extraction" {
  let root = @toml.parse(
    "[affected.\"ci.yml\"]\npatterns = [\"src/**\", \"*.toml\"]\n[affected.\"lint.yml\"]\npatterns = [\"src/**\"]\n",
  )
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  let affected = toml_get_table(table, "affected")
  let result : Map[String, Array[String]] = {}
  for wf_name, wf_value in affected {
    match wf_value {
      @toml.TomlTable(wf_tbl) => {
        let patterns = toml_get_string_array(wf_tbl, "patterns")
        if patterns.length() > 0 {
          result[wf_name] = patterns
        }
      }
      _ => ()
    }
  }
  inspect(result.get("ci.yml").unwrap(), content="[\"src/**\", \"*.toml\"]")
  inspect(result.get("lint.yml").unwrap(), content="[\"src/**\"]")
}

///|
test "toml: override script is isolated" {
  let root = @toml.parse(
    "[override.\"actions/setup-node\"]\nrun = \"echo 'safe'\"\n",
  )
  guard root is @toml.TomlTable(table) else { fail("expected table") }
  let override_tbl = toml_get_table(table, "override")
  let node = toml_get_table(override_tbl, "actions/setup-node")
  inspect(toml_get_string(node, "run"), content="echo 'safe'")
}

///|
test "security: glob_match rejects path traversal patterns" {
  // A traversal pattern matches traversal paths
  inspect(glob_match("../**", "../../etc/passwd"), content="true")
  // But a normal src pattern does not match traversal paths
  inspect(glob_match("src/**", "../etc/passwd"), content="false")
  // files_match_patterns with traversal paths should not match src patterns
  inspect(
    files_match_patterns(["../../../etc/passwd"], ["src/**"]),
    content="false",
  )
}
