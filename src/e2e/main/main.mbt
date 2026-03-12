///|
struct E2eProcessResult {
  code : Int
  stdout : String
  stderr : String
}

///|
struct E2eRepoFile {
  path : String
  content : String
}

///|
struct E2eFakeGitRoute {
  match_text : String
  source_dir : String
}

///|
fn e2e_parent_dir(path : String) -> String {
  let parts : Array[String] = []
  for part in path.split("/") {
    parts.push(part.to_string())
  }
  if parts.length() <= 1 {
    return "."
  }
  let dirs : Array[String] = []
  for i in 0..<(parts.length() - 1) {
    let part = parts[i]
    if part.length() > 0 {
      dirs.push(part)
    }
  }
  let joined = dirs.join("/")
  if joined.length() > 0 {
    if path.has_prefix("/") {
      "/" + joined
    } else {
      joined
    }
  } else if path.has_prefix("/") {
    "/"
  } else {
    "."
  }
}

///|
fn e2e_join_path(base : String, child : String) -> String {
  if child.has_prefix("/") {
    return child
  }
  if base.length() == 0 || base == "." {
    child
  } else if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
fn e2e_absolute_path(path : String) -> String {
  if path.has_prefix("/") {
    return path
  }
  let cwd = @xsys.get_env_var("PWD").unwrap_or(".")
  if cwd.has_suffix("/") {
    cwd + path
  } else {
    cwd + "/" + path
  }
}

///|
fn e2e_read_text(path : String) -> String {
  @xfs.read_file_to_string(path) catch {
    _ => abort("failed to read: " + path)
  }
}

///|
fn e2e_is_dir(path : String) -> Bool {
  try @xfs.is_dir(path) catch {
    _ => false
  } noraise {
    value => value
  }
}

///|
fn e2e_read_dir(path : String) -> Array[String] {
  @xfs.read_dir(path) catch {
    _ => abort("failed to read dir: " + path)
  }
}

///|
fn e2e_ensure_dir(path : String) -> Unit {
  if path == "." || path.length() == 0 {
    return
  }
  let parent = e2e_parent_dir(path)
  if parent != path && parent != "." && not(@xfs.path_exists(parent)) {
    e2e_ensure_dir(parent)
  }
  if not(@xfs.path_exists(path)) {
    let ok = try @xfs.create_dir(path) catch {
      _ => false
    } noraise {
      _ => true
    }
    if not(ok) {
      abort("failed to create dir: " + path)
    }
  }
}

///|
fn e2e_remove_tree(path : String) -> Unit {
  if not(@xfs.path_exists(path)) {
    return
  }
  if e2e_is_dir(path) {
    for entry in e2e_read_dir(path) {
      e2e_remove_tree(e2e_join_path(path, entry))
    }
    let ok = try @xfs.remove_dir(path) catch {
      _ => false
    } noraise {
      _ => true
    }
    if not(ok) {
      abort("failed to remove dir: " + path)
    }
  } else {
    let ok = try @xfs.remove_file(path) catch {
      _ => false
    } noraise {
      _ => true
    }
    if not(ok) {
      abort("failed to remove file: " + path)
    }
  }
}

///|
fn e2e_copy_tree(src : String, dst : String) -> Unit {
  if e2e_is_dir(src) {
    if not(@xfs.path_exists(dst)) {
      e2e_ensure_dir(dst)
    }
    for entry in e2e_read_dir(src) {
      e2e_copy_tree(e2e_join_path(src, entry), e2e_join_path(dst, entry))
    }
  } else {
    e2e_ensure_dir(e2e_parent_dir(dst))
    let ok = try
      @xfs.write_bytes_to_file(dst, @xfs.read_file_to_bytes(src))
    catch {
      _ => false
    } noraise {
      _ => true
    }
    if not(ok) {
      abort("failed to copy file to: " + dst)
    }
  }
}

///|
fn e2e_prepare_dir(root_dir : String, name : String) -> String {
  e2e_ensure_dir("_build")
  e2e_ensure_dir(root_dir)
  let path = e2e_join_path(root_dir, name)
  e2e_remove_tree(path)
  e2e_ensure_dir(path)
  e2e_absolute_path(path)
}

///|
fn e2e_prepare_copied_dir(
  root_dir : String,
  name : String,
  source_dir : String,
) -> String {
  let workspace = e2e_prepare_dir(root_dir, name)
  e2e_copy_tree(source_dir, workspace)
  workspace
}

///|
fn e2e_fixture_dir(name : String) -> String {
  e2e_join_path("testdata/e2e", name)
}

///|
fn e2e_cli_executable() -> String {
  e2e_absolute_path("_build/native/debug/build/main/main.exe")
}

///|
fn e2e_expect_contains(
  text : String,
  needle : String,
  context : String,
) -> Unit {
  if not(text.contains(needle)) {
    abort(context + ": missing <" + needle + "> in\n" + text)
  }
}

///|
fn e2e_expect_eq(actual : String, expected : String, context : String) -> Unit {
  if actual != expected {
    abort(context + ": expected <" + expected + "> but got <" + actual + ">")
  }
}

///|
fn e2e_expect_ok(result : E2eProcessResult, scenario : String) -> Unit {
  if result.code != 0 {
    abort(
      scenario +
      ": cli failed\nstdout:\n" +
      result.stdout +
      "\nstderr:\n" +
      result.stderr,
    )
  }
}

///|
fn e2e_expect_fail(result : E2eProcessResult, scenario : String) -> Unit {
  if result.code == 0 {
    abort(
      scenario +
      ": cli unexpectedly succeeded\nstdout:\n" +
      result.stdout +
      "\nstderr:\n" +
      result.stderr,
    )
  }
}

///|
fn e2e_expect_missing(path : String, context : String) -> Unit {
  if @xfs.path_exists(path) {
    abort(context + ": unexpected path exists: " + path)
  }
}

///|
#cfg(target="native")
async fn e2e_make_executable(path : String) -> Unit {
  let (code, _, stderr) = @process.collect_output(
    "chmod",
    ["+x", path],
    cwd=".",
  )
  if code != 0 {
    abort("chmod failed: " + stderr.text())
  }
}

///|
#cfg(target="native")
async fn e2e_prepare_fake_git_bin(
  workspace : String,
  action_src : String,
  log_path : String,
) -> String {
  let bin_dir = e2e_join_path(workspace, "bin")
  e2e_ensure_dir(bin_dir)
  let git_path = e2e_join_path(bin_dir, "git")
  let absolute_log_path = e2e_absolute_path(log_path)
  let script = "#!/bin/sh\n" +
    "set -eu\n" +
    "printf '%s\\n' \"$@\" >> '" +
    absolute_log_path +
    "'\n" +
    "dest=\"\"\n" +
    "for arg in \"$@\"; do\n" +
    "  dest=\"$arg\"\n" +
    "done\n" +
    "mkdir -p \"$dest/composite\"\n" +
    "cat > \"$dest/composite/action.yml\" <<'EOF'\n" +
    action_src +
    "\nEOF\n"
  @xfs.write_string_to_file(git_path, script)
  e2e_make_executable(git_path)
  e2e_absolute_path(git_path)
}

///|
#cfg(target="native")
async fn e2e_prepare_fake_git_bin_from_source(
  workspace : String,
  source_dir : String,
  log_path : String,
) -> String {
  let bin_dir = e2e_join_path(workspace, "bin")
  e2e_ensure_dir(bin_dir)
  let git_path = e2e_join_path(bin_dir, "git")
  let absolute_log_path = e2e_absolute_path(log_path)
  let absolute_source_dir = e2e_absolute_path(source_dir)
  let script = "#!/bin/sh\n" +
    "set -eu\n" +
    "printf '%s\\n' \"$@\" >> '" +
    absolute_log_path +
    "'\n" +
    "dest=\"\"\n" +
    "for arg in \"$@\"; do\n" +
    "  dest=\"$arg\"\n" +
    "done\n" +
    "mkdir -p \"$dest\"\n" +
    "cp -R '" +
    absolute_source_dir +
    "/.' \"$dest/\"\n"
  @xfs.write_string_to_file(git_path, script)
  e2e_make_executable(git_path)
  e2e_absolute_path(git_path)
}

///|
#cfg(target="native")
async fn e2e_prepare_fake_git_router_bin(
  workspace : String,
  routes : Array[E2eFakeGitRoute],
  log_path : String,
) -> String {
  let bin_dir = e2e_join_path(workspace, "bin")
  e2e_ensure_dir(bin_dir)
  let git_path = e2e_join_path(bin_dir, "git")
  let absolute_log_path = e2e_absolute_path(log_path)
  let mut route_script = ""
  for route in routes {
    let absolute_source_dir = e2e_absolute_path(route.source_dir)
    route_script += "  *'" +
      route.match_text +
      "') cp -R '" +
      absolute_source_dir +
      "/.' \"$dest\" ;;\n"
  }
  let script = "#!/bin/sh\n" +
    "set -eu\n" +
    "printf '%s\\n' \"$@\" >> '" +
    absolute_log_path +
    "'\n" +
    "cmd=\"$1\"\n" +
    "shift\n" +
    "if [ \"$cmd\" != clone ]; then\n" +
    "  echo \"unexpected git command: $cmd\" >&2\n" +
    "  exit 1\n" +
    "fi\n" +
    "while [ \"$#\" -gt 0 ]; do\n" +
    "  case \"$1\" in\n" +
    "    --depth|--branch)\n" +
    "      shift 2\n" +
    "      ;;\n" +
    "    *)\n" +
    "      break\n" +
    "      ;;\n" +
    "  esac\n" +
    "done\n" +
    "clone_url=\"$1\"\n" +
    "dest=\"$2\"\n" +
    "mkdir -p \"$dest\"\n" +
    "case \"$clone_url\" in\n" +
    route_script +
    "  *) echo \"unexpected clone url: $clone_url\" >&2 ; exit 1 ;;\n" +
    "esac\n"
  @xfs.write_string_to_file(git_path, script)
  e2e_make_executable(git_path)
  e2e_absolute_path(git_path)
}

///|
#cfg(target="native")
async fn e2e_prepare_fake_node_bin(
  workspace : String,
  log_path : String,
) -> String {
  let bin_dir = e2e_join_path(workspace, "bin")
  e2e_ensure_dir(bin_dir)
  let node_path = e2e_join_path(bin_dir, "node")
  let absolute_log_path = e2e_absolute_path(log_path)
  @xfs.write_string_to_file(absolute_log_path, "")
  let script = "#!/bin/sh\n" +
    "set -eu\n" +
    "printf '%s\\n' \"$@\" >> '" +
    absolute_log_path +
    "'\n" +
    "script=\"$1\"\n" +
    "shift || true\n" +
    "exec sh \"$script\" \"$@\"\n"
  @xfs.write_string_to_file(node_path, script)
  e2e_make_executable(node_path)
  e2e_absolute_path(node_path)
}

///|
#cfg(target="native")
async fn e2e_prepare_fake_docker_bin(
  workspace : String,
  log_path : String,
) -> String {
  let bin_dir = e2e_join_path(workspace, "bin")
  e2e_ensure_dir(bin_dir)
  let docker_path = e2e_join_path(bin_dir, "docker")
  let absolute_log_path = e2e_absolute_path(log_path)
  @xfs.write_string_to_file(absolute_log_path, "")
  let script = "#!/bin/sh\n" +
    "set -eu\n" +
    "printf '%s\\n' \"$@\" >> '" +
    absolute_log_path +
    "'\n" +
    "cmd=\"$1\"\n" +
    "shift\n" +
    "if [ \"$cmd\" = build ]; then\n" +
    "  exit 0\n" +
    "fi\n" +
    "if [ \"$cmd\" = run ]; then\n" +
    "  workspace=\"\"\n" +
    "  input_message=\"\"\n" +
    "  github_state=\"\"\n" +
    "  state_phase=\"\"\n" +
    "  entrypoint=\"\"\n" +
    "  while [ \"$#\" -gt 0 ]; do\n" +
    "    case \"$1\" in\n" +
    "      -e)\n" +
    "        case \"$2\" in\n" +
    "          GITHUB_WORKSPACE=*) workspace=\"${2#GITHUB_WORKSPACE=}\" ;;\n" +
    "          INPUT_MESSAGE=*) input_message=\"${2#INPUT_MESSAGE=}\" ;;\n" +
    "          GITHUB_STATE=*) github_state=\"${2#GITHUB_STATE=}\" ;;\n" +
    "          STATE_phase=*) state_phase=\"${2#STATE_phase=}\" ;;\n" +
    "        esac\n" +
    "        shift 2\n" +
    "        ;;\n" +
    "      -v|-w)\n" +
    "        shift 2\n" +
    "        ;;\n" +
    "      --entrypoint)\n" +
    "        entrypoint=\"$2\"\n" +
    "        shift 2\n" +
    "        ;;\n" +
    "      --rm)\n" +
    "        shift\n" +
    "        ;;\n" +
    "      *)\n" +
    "        break\n" +
    "        ;;\n" +
    "    esac\n" +
    "  done\n" +
    "  if [ -n \"$workspace\" ] && [ -n \"$input_message\" ]; then\n" +
    "    printf '%s' \"$input_message\" > \"$workspace/docker.txt\"\n" +
    "  fi\n" +
    "  case \"$entrypoint\" in\n" +
    "    *pre.sh)\n" +
    "      if [ -n \"$github_state\" ]; then\n" +
    "        printf 'phase=pre\\n' >> \"$github_state\"\n" +
    "      fi\n" +
    "      ;;\n" +
    "    *main.sh)\n" +
    "      if [ -n \"$workspace\" ]; then\n" +
    "        printf '%s' \"$state_phase\" > \"$workspace/main.txt\"\n" +
    "      fi\n" +
    "      if [ -n \"$github_state\" ]; then\n" +
    "        printf 'phase=main\\n' >> \"$github_state\"\n" +
    "      fi\n" +
    "      ;;\n" +
    "    *fail.sh)\n" +
    "      if [ -n \"$workspace\" ]; then\n" +
    "        printf '%s' \"$state_phase\" > \"$workspace/main.txt\"\n" +
    "      fi\n" +
    "      if [ -n \"$github_state\" ]; then\n" +
    "        printf 'phase=main\\n' >> \"$github_state\"\n" +
    "      fi\n" +
    "      exit 7\n" +
    "      ;;\n" +
    "    *post.sh)\n" +
    "      if [ -n \"$workspace\" ]; then\n" +
    "        printf '%s|%s' \"$state_phase\" \"$workspace\" > \"$workspace/post.txt\"\n" +
    "      fi\n" +
    "      ;;\n" +
    "  esac\n" +
    "  exit 0\n" +
    "fi\n" +
    "echo \"unexpected docker command: $cmd\" >&2\n" +
    "exit 1\n"
  @xfs.write_string_to_file(docker_path, script)
  e2e_make_executable(docker_path)
  e2e_absolute_path(docker_path)
}

///|
#cfg(target="native")
async fn e2e_run_cli(
  args : Array[String],
  env? : Map[String, String] = {},
) -> E2eProcessResult {
  let command_args : Array[String] = []
  for key, value in env {
    command_args.push(key + "=" + value)
  }
  command_args.push(e2e_cli_executable())
  for arg in args {
    command_args.push(arg)
  }
  let (code, stdout, stderr) = @process.collect_output(
    "env",
    command_args,
    cwd=".",
  )
  { code, stdout: stdout.text(), stderr: stderr.text() }
}

///|
fn e2e_write_repo_file(repo_root : String, file : E2eRepoFile) -> Unit {
  let path = e2e_join_path(repo_root, file.path)
  e2e_ensure_dir(e2e_parent_dir(path))
  let ok = try @xfs.write_string_to_file(path, file.content) catch {
    _ => false
  } noraise {
    _ => true
  }
  if not(ok) {
    abort("failed to write repo file: " + path)
  }
}

///|
fn e2e_commit_repo_files(
  repo_root : String,
  files : Array[E2eRepoFile],
  message : String,
  timestamp : Int64,
  init? : Bool = false,
) -> String {
  let fs = @bitosfs.OsFs::new()
  e2e_ensure_dir(repo_root)
  if init {
    ignore(try? @bitlib.init_repo(fs, repo_root))
  }
  let paths : Array[String] = []
  for file in files {
    e2e_write_repo_file(repo_root, file)
    paths.push(file.path)
  }
  let add_ok = try @bitlib.add_paths(fs, fs, repo_root, paths) catch {
    _ => false
  } noraise {
    _ => true
  }
  if not(add_ok) {
    abort("bit add failed for repo: " + repo_root)
  }
  let commit_id = @bitlib.commit(
    fs, fs, repo_root, message, "Author <a@b.com>", timestamp,
  ) catch {
    _ => abort("bit commit failed for repo: " + repo_root)
  }
  commit_id.to_hex()
}

///|
#cfg(target="native")
async fn run_local_push_basic() -> Unit {
  let scenario = "local-push-basic"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-basic", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "setup/pick: success", scenario)
  e2e_expect_contains(result.stdout, "setup/verify: success", scenario)
  e2e_expect_contains(result.stdout, "build/consume: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/setup.txt")),
    "push|blue|mizchi/action_runner",
    scenario + " setup artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/build.txt")),
    "blue|success|octocat",
    scenario + " build artifact",
  )
}

///|
#cfg(target="native")
async fn run_local_composite_nested() -> Unit {
  let scenario = "local-composite-nested"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-composite", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/verify: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "hello-nested|outer|hello-nested",
    scenario + " artifact",
  )
}

///|
#cfg(target="native")
async fn run_trigger_skipped() -> Unit {
  let scenario = "trigger-skipped"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-skipped", scenario)
  e2e_expect_contains(result.stdout, "state=skipped", scenario)
  e2e_expect_missing(
    e2e_join_path(workspace, "should-not-exist.txt"),
    scenario + " skipped artifact",
  )
}

///|
#cfg(target="native")
async fn run_file_commands() -> Unit {
  let scenario = "file-commands"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-file-commands", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/setup: success", scenario)
  e2e_expect_contains(result.stdout, "build/consume: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/summary.txt")),
    "summary-line",
    scenario + " summary artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/commands.txt")),
    "yellow|line-1\nline-2|green|painted:test",
    scenario + " commands artifact",
  )
}

///|
#cfg(target="native")
async fn run_artifact_actions_roundtrip() -> Unit {
  let scenario = "artifact-actions-roundtrip"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-artifact-actions", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/upload: success", scenario)
  e2e_expect_contains(result.stdout, "build/download: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "alpha|beta",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_job_failure_blocked() -> Unit {
  let scenario = "job-failure-blocked"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-failure", scenario)
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/fail: failed", scenario)
  e2e_expect_contains(result.stdout, "lint/wait: blocked", scenario)
}

///|
#cfg(target="native")
async fn run_unsupported_uses() -> Unit {
  let scenario = "unsupported-uses"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([e2e_join_path(workspace, "workflow.yml")])
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "error: step 'build/setup' action 'bit://std/cache@v1' is not supported in MVP",
    scenario,
  )
}

///|
#cfg(target="native")
async fn run_unsupported_matrix() -> Unit {
  let scenario = "unsupported-matrix"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([e2e_join_path(workspace, "workflow.yml")])
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "error: job 'build' matrix is not supported in MVP",
    scenario,
  )
}

///|
#cfg(target="native")
async fn run_event_cli_overrides() -> Unit {
  let scenario = "event-cli-overrides"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
    "--ref",
    "main",
    "--repository",
    "mizchi/action_runner",
    "--after",
    "override-sha",
    "--changed",
    "src/runner.mbt",
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-event-override", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/write: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/context.txt")),
    "main|mizchi/action_runner|override-sha|event-octocat|push",
    scenario + " context artifact",
  )
}

///|
#cfg(target="native")
async fn run_docker_image_basic() -> Unit {
  let scenario = "docker-image-basic"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let env : Map[String, String] = { "ACTION_RUNNER_DOCKER_BIN": fake_docker }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-docker-image", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/image: success", scenario)
  e2e_expect_contains(result.stdout, "build/marker: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/marker.txt")),
    "after-docker",
    scenario + " marker artifact",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "alpine:3.21", scenario + " docker image")
}

///|
#cfg(target="native")
async fn run_event_head_commit_fallback() -> Unit {
  let scenario = "event-head-commit-fallback"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-head-commit", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/context.txt")),
    "head-octocat|mizchi/action_runner",
    scenario + " context artifact",
  )
}

///|
#cfg(target="native")
async fn run_remote_composite_fetch() -> Unit {
  let scenario = "remote-composite-fetch"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let action_src =
    #|name: remote composite
    #|inputs:
    #|  message:
    #|    default: remote-default
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - shell: bash
    #|      run: |
    #|        printf '%s|%s|%s' "${{ inputs.message }}" "${{ github.action_repository }}" "${{ github.action_ref }}" > remote.txt
  let fake_git = e2e_prepare_fake_git_bin(workspace, action_src, log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-remote", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/remote.txt")),
    "remote-hello|demo/tools|v1",
    scenario + " artifact",
  )
  let git_log = e2e_read_text(log_path)
  e2e_expect_contains(git_log, "clone", scenario + " git log")
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/tools",
    scenario + " git url",
  )
}

///|
#cfg(target="native")
async fn run_remote_composite_nested_prefetch() -> Unit {
  let scenario = "remote-composite-nested-prefetch"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let fake_git = e2e_prepare_fake_git_router_bin(
    workspace,
    [
      {
        match_text: "https://github.com/demo/tools.git",
        source_dir: e2e_join_path(workspace, "parent_repo"),
      },
      {
        match_text: "https://github.com/demo/child.git",
        source_dir: e2e_join_path(workspace, "child_repo"),
      },
    ],
    log_path,
  )
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-remote-nested", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/remote.txt")),
    "nested|demo/child|v2",
    scenario + " artifact",
  )
  let git_log = e2e_read_text(log_path)
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/tools",
    scenario + " parent git url",
  )
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/child",
    scenario + " child git url",
  )
}

///|
#cfg(target="native")
async fn run_remote_composite_nested_cache_hit() -> Unit {
  let scenario = "remote-composite-nested-cache-hit"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let cache_root = e2e_join_path(workspace, "github_actions_cache")
  let parent_root = e2e_join_path(cache_root, "demo/tools/v1/composite")
  let child_root = e2e_join_path(cache_root, "demo/child/v2/composite")
  e2e_copy_tree(e2e_join_path(workspace, "parent_repo/composite"), parent_root)
  e2e_copy_tree(e2e_join_path(workspace, "child_repo/composite"), child_root)
  let log_path = e2e_join_path(workspace, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_router_bin(
    workspace,
    [
      {
        match_text: "https://github.com/demo/tools.git",
        source_dir: e2e_join_path(workspace, "parent_repo"),
      },
      {
        match_text: "https://github.com/demo/child.git",
        source_dir: e2e_join_path(workspace, "child_repo"),
      },
    ],
    log_path,
  )
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-remote-nested-cache-hit",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/remote.txt")),
    "nested|demo/child|v2",
    scenario + " artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
}

///|
#cfg(target="native")
async fn run_remote_composite_cache_hit() -> Unit {
  let scenario = "remote-composite-cache-hit"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let cache_root = e2e_join_path(workspace, "github_actions_cache")
  let cached_action_root = e2e_join_path(cache_root, "demo/tools/v1/composite")
  e2e_ensure_dir(cached_action_root)
  let action_src =
    #|name: cached composite
    #|inputs:
    #|  message:
    #|    default: cached-default
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - shell: bash
    #|      run: |
    #|        printf '%s|%s|%s' "${{ inputs.message }}" "${{ github.action_repository }}" "${{ github.action_ref }}" > remote.txt
  @xfs.write_string_to_file(cached_action_root + "/action.yml", action_src)
  let log_path = e2e_join_path(workspace, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_bin(workspace, action_src, log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-remote-cache-hit", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/remote.txt")),
    "cached-hello|demo/tools|v1",
    scenario + " artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
}

///|
#cfg(target="native")
async fn run_remote_node_lifecycle() -> Unit {
  let scenario = "remote-node-lifecycle"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_action"),
    log_path,
  )
  let node_log_path = e2e_join_path(workspace, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(workspace, node_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
    "ACTION_RUNNER_NODE_BIN": fake_node,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-node-lifecycle", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__pre: success", scenario)
  e2e_expect_contains(result.stdout, "build/remote: success", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/main.txt")),
    "pre",
    scenario + " main artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "main|" + workspace,
    scenario + " post artifact",
  )
  let node_log = e2e_read_text(node_log_path)
  e2e_expect_contains(node_log, "pre.sh", scenario + " node pre")
  e2e_expect_contains(node_log, "main.sh", scenario + " node main")
  e2e_expect_contains(node_log, "post.sh", scenario + " node post")
}

///|
#cfg(target="native")
async fn run_remote_node_failure_cleanup() -> Unit {
  let scenario = "remote-node-failure-cleanup"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_action"),
    log_path,
  )
  let node_log_path = e2e_join_path(workspace, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(workspace, node_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
    "ACTION_RUNNER_NODE_BIN": fake_node,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-node-failure-cleanup",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: blocked", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "started|" + workspace,
    scenario + " post artifact",
  )
  let node_log = e2e_read_text(node_log_path)
  e2e_expect_contains(node_log, "pre.sh", scenario + " node pre")
  e2e_expect_contains(node_log, "main.sh", scenario + " node main")
  e2e_expect_contains(node_log, "post.sh", scenario + " node post")
}

///|
#cfg(target="native")
async fn run_remote_node_failure_cache_hit() -> Unit {
  let scenario = "remote-node-failure-cache-hit"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let cache_root = e2e_join_path(workspace, "github_actions_cache")
  let cached_action_root = e2e_join_path(cache_root, "demo/tools/v1/action")
  e2e_copy_tree(
    e2e_join_path(workspace, "remote_action/action"),
    cached_action_root,
  )
  let log_path = e2e_join_path(workspace, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_action"),
    log_path,
  )
  let node_log_path = e2e_join_path(workspace, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(workspace, node_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
    "ACTION_RUNNER_NODE_BIN": fake_node,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-node-failure-cache-hit",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: blocked", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "started|" + workspace,
    scenario + " post artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
  let node_log = e2e_read_text(node_log_path)
  e2e_expect_contains(node_log, "pre.sh", scenario + " node pre")
  e2e_expect_contains(node_log, "main.sh", scenario + " node main")
  e2e_expect_contains(node_log, "post.sh", scenario + " node post")
}

///|
#cfg(target="native")
async fn run_remote_node_nested_prefetch() -> Unit {
  let scenario = "remote-node-nested-prefetch"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let fake_git = e2e_prepare_fake_git_router_bin(
    workspace,
    [
      {
        match_text: "https://github.com/demo/tools.git",
        source_dir: e2e_join_path(workspace, "parent_repo"),
      },
      {
        match_text: "https://github.com/demo/child.git",
        source_dir: e2e_join_path(workspace, "child_repo"),
      },
    ],
    log_path,
  )
  let node_log_path = e2e_join_path(workspace, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(workspace, node_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
    "ACTION_RUNNER_NODE_BIN": fake_node,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-remote-node-nested",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/node.txt")),
    "nested-node|demo/child|v2",
    scenario + " artifact",
  )
  let git_log = e2e_read_text(log_path)
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/tools",
    scenario + " parent git url",
  )
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/child",
    scenario + " child git url",
  )
  let node_log = e2e_read_text(node_log_path)
  e2e_expect_contains(node_log, "main.sh", scenario + " node main")
}

///|
#cfg(target="native")
async fn run_remote_node_nested_cache_hit() -> Unit {
  let scenario = "remote-node-nested-cache-hit"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let cache_root = e2e_join_path(workspace, "github_actions_cache")
  let parent_root = e2e_join_path(cache_root, "demo/tools/v1/composite")
  let child_root = e2e_join_path(cache_root, "demo/child/v2/action")
  e2e_copy_tree(e2e_join_path(workspace, "parent_repo/composite"), parent_root)
  e2e_copy_tree(e2e_join_path(workspace, "child_repo/action"), child_root)
  let log_path = e2e_join_path(workspace, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_router_bin(
    workspace,
    [
      {
        match_text: "https://github.com/demo/tools.git",
        source_dir: e2e_join_path(workspace, "parent_repo"),
      },
      {
        match_text: "https://github.com/demo/child.git",
        source_dir: e2e_join_path(workspace, "child_repo"),
      },
    ],
    log_path,
  )
  let node_log_path = e2e_join_path(workspace, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(workspace, node_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
    "ACTION_RUNNER_NODE_BIN": fake_node,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-remote-node-nested-cache-hit",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/node.txt")),
    "nested-node|demo/child|v2",
    scenario + " artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
  let node_log = e2e_read_text(node_log_path)
  e2e_expect_contains(node_log, "main.sh", scenario + " node main")
}

///|
#cfg(target="native")
async fn run_remote_node_cache_hit() -> Unit {
  let scenario = "remote-node-cache-hit"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let cache_root = e2e_join_path(workspace, "github_actions_cache")
  let cached_action_root = e2e_join_path(cache_root, "demo/tools/v1/action")
  e2e_copy_tree(
    e2e_join_path(workspace, "remote_action/action"),
    cached_action_root,
  )
  let log_path = e2e_join_path(workspace, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_action"),
    log_path,
  )
  let node_log_path = e2e_join_path(workspace, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(workspace, node_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
    "ACTION_RUNNER_NODE_BIN": fake_node,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-node-cache-hit", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/main.txt")),
    "pre",
    scenario + " main artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "main|" + workspace,
    scenario + " post artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
  let node_log = e2e_read_text(node_log_path)
  e2e_expect_contains(node_log, "pre.sh", scenario + " node pre")
  e2e_expect_contains(node_log, "main.sh", scenario + " node main")
  e2e_expect_contains(node_log, "post.sh", scenario + " node post")
}

///|
#cfg(target="native")
async fn run_remote_docker_lifecycle() -> Unit {
  let scenario = "remote-docker-lifecycle"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_action"),
    log_path,
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-docker-lifecycle", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__pre: success", scenario)
  e2e_expect_contains(result.stdout, "build/remote: success", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/main.txt")),
    "pre",
    scenario + " main artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "main|" + workspace,
    scenario + " post artifact",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "build", scenario + " docker build")
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
}

///|
#cfg(target="native")
async fn run_remote_docker_failure_cleanup() -> Unit {
  let scenario = "remote-docker-failure-cleanup"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_action"),
    log_path,
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-docker-failure-cleanup",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: blocked", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "main|" + workspace,
    scenario + " post artifact",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "build", scenario + " docker build")
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "fail.sh", scenario + " docker fail")
  e2e_expect_contains(docker_log, "post.sh", scenario + " docker post")
}

///|
#cfg(target="native")
async fn run_remote_docker_failure_cache_hit() -> Unit {
  let scenario = "remote-docker-failure-cache-hit"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let cache_root = e2e_join_path(workspace, "github_actions_cache")
  let cached_action_root = e2e_join_path(cache_root, "demo/tools/v1/action")
  e2e_copy_tree(
    e2e_join_path(workspace, "remote_action/action"),
    cached_action_root,
  )
  let log_path = e2e_join_path(workspace, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_action"),
    log_path,
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-docker-failure-cache-hit",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: blocked", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "main|" + workspace,
    scenario + " post artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "build", scenario + " docker build")
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "fail.sh", scenario + " docker fail")
  e2e_expect_contains(docker_log, "post.sh", scenario + " docker post")
}

///|
#cfg(target="native")
async fn run_remote_docker_nested_prefetch() -> Unit {
  let scenario = "remote-docker-nested-prefetch"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let fake_git = e2e_prepare_fake_git_router_bin(
    workspace,
    [
      {
        match_text: "https://github.com/demo/tools.git",
        source_dir: e2e_join_path(workspace, "parent_repo"),
      },
      {
        match_text: "https://github.com/demo/child.git",
        source_dir: e2e_join_path(workspace, "child_repo"),
      },
    ],
    log_path,
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-remote-docker-nested",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/main.txt")),
    "pre",
    scenario + " main artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "main|" + workspace,
    scenario + " post artifact",
  )
  let git_log = e2e_read_text(log_path)
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/tools",
    scenario + " parent git url",
  )
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/child",
    scenario + " child git url",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "build", scenario + " docker build")
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
}

///|
#cfg(target="native")
async fn run_remote_docker_nested_cache_hit() -> Unit {
  let scenario = "remote-docker-nested-cache-hit"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let cache_root = e2e_join_path(workspace, "github_actions_cache")
  let parent_root = e2e_join_path(cache_root, "demo/tools/v1/composite")
  let child_root = e2e_join_path(cache_root, "demo/child/v2/action")
  e2e_copy_tree(e2e_join_path(workspace, "parent_repo/composite"), parent_root)
  e2e_copy_tree(e2e_join_path(workspace, "child_repo/action"), child_root)
  let log_path = e2e_join_path(workspace, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_router_bin(
    workspace,
    [
      {
        match_text: "https://github.com/demo/tools.git",
        source_dir: e2e_join_path(workspace, "parent_repo"),
      },
      {
        match_text: "https://github.com/demo/child.git",
        source_dir: e2e_join_path(workspace, "child_repo"),
      },
    ],
    log_path,
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-remote-docker-nested-cache-hit",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/main.txt")),
    "pre",
    scenario + " main artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "main|" + workspace,
    scenario + " post artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "build", scenario + " docker build")
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
}

///|
#cfg(target="native")
async fn run_remote_docker_cache_hit() -> Unit {
  let scenario = "remote-docker-cache-hit"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let cache_root = e2e_join_path(workspace, "github_actions_cache")
  let cached_action_root = e2e_join_path(cache_root, "demo/tools/v1/action")
  e2e_copy_tree(
    e2e_join_path(workspace, "remote_action/action"),
    cached_action_root,
  )
  let log_path = e2e_join_path(workspace, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_action"),
    log_path,
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-docker-cache-hit", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/main.txt")),
    "pre",
    scenario + " main artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "post.txt")),
    "main|" + workspace,
    scenario + " post artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "build", scenario + " docker build")
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
}

///|
#cfg(target="native")
async fn run_repo_push_bit() -> Unit {
  let scenario = "repo-push-bit"
  let repo_root = e2e_prepare_dir("_build/e2e/repo-push-bit", "repo")
  let workspace_root = e2e_prepare_dir("_build/e2e/repo-push-bit", "workspace")
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before\n" },
    ],
    "Initial commit",
    1700000100L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after\n" }],
    "Update message",
    1700000101L,
  )
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--ref", "main", "--before", before_sha, "--after", after_sha,
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-repo", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/copy: success", scenario)
  e2e_expect_contains(result.stdout, "build/context: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/message.txt")),
    "after\n",
    scenario + " message artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/context.txt")),
    "push|main",
    scenario + " context artifact",
  )
}

///|
#cfg(target="native")
async fn run_repo_needs_output() -> Unit {
  let scenario = "repo-needs-output"
  let repo_root = e2e_prepare_dir("_build/e2e/repo-needs-output", "repo")
  let workspace_root = e2e_prepare_dir(
    "_build/e2e/repo-needs-output", "workspace",
  )
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-needs\n" },
    ],
    "Initial needs commit",
    1700000500L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-needs\n" }],
    "Update needs message",
    1700000501L,
  )
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--ref", "main", "--before", before_sha, "--after", after_sha, "--repository",
    "mizchi/action_runner",
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-repo-needs", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "setup/pick: success", scenario)
  e2e_expect_contains(result.stdout, "build/consume: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/result.txt")),
    "green|success|after-needs\n|mizchi/action_runner",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_repo_job_file_commands() -> Unit {
  let scenario = "repo-job-file-commands"
  let repo_root = e2e_prepare_dir("_build/e2e/repo-job-file-commands", "repo")
  let workspace_root = e2e_prepare_dir(
    "_build/e2e/repo-job-file-commands", "workspace",
  )
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-job-file\n" },
    ],
    "Initial job file commit",
    1700000800L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-job-file\n" }],
    "Update job file message",
    1700000801L,
  )
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--ref", "main", "--before", before_sha, "--after", after_sha, "--repository",
    "mizchi/action_runner",
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-repo-job-commands", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "setup/vars: success", scenario)
  e2e_expect_contains(result.stdout, "build/consume: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/result.txt")),
    "amber|missing|missing|after-job-file|mizchi/action_runner",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_repo_multi_job_summary() -> Unit {
  let scenario = "repo-multi-job-summary"
  let repo_root = e2e_prepare_dir("_build/e2e/repo-multi-job-summary", "repo")
  let workspace_root = e2e_prepare_dir(
    "_build/e2e/repo-multi-job-summary", "workspace",
  )
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-summary\n" },
    ],
    "Initial summary commit",
    1700000900L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-summary\n" }],
    "Update summary message",
    1700000901L,
  )
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--ref", "main", "--before", before_sha, "--after", after_sha, "--repository",
    "mizchi/action_runner",
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-repo-summary", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "setup/write: success", scenario)
  e2e_expect_contains(result.stdout, "build/write: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/setup-summary.txt")),
    "setup-summary",
    scenario + " setup summary artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/build-summary.txt")),
    "build-summary|after-summary",
    scenario + " build summary artifact",
  )
}

///|
#cfg(target="native")
async fn run_repo_needs_summary() -> Unit {
  let scenario = "repo-needs-summary"
  let repo_root = e2e_prepare_dir("_build/e2e/repo-needs-summary", "repo")
  let workspace_root = e2e_prepare_dir(
    "_build/e2e/repo-needs-summary", "workspace",
  )
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-needs-summary\n" },
    ],
    "Initial needs summary commit",
    1700000950L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-needs-summary\n" }],
    "Update needs summary message",
    1700000951L,
  )
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--ref", "main", "--before", before_sha, "--after", after_sha, "--repository",
    "mizchi/action_runner",
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-repo-needs-summary",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "setup/pick: success", scenario)
  e2e_expect_contains(result.stdout, "build/write: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/setup-summary.txt")),
    "setup-summary|violet",
    scenario + " setup summary artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/build-summary.txt")),
    "violet|success|after-needs-summary",
    scenario + " build summary artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/result.txt")),
    "violet|success|after-needs-summary|mizchi/action_runner",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_repo_remote_node_failure_cleanup() -> Unit {
  let scenario = "repo-remote-node-failure-cleanup"
  let root_dir = "_build/e2e/repo-remote-node-failure-cleanup"
  let repo_root = e2e_prepare_dir(root_dir, "repo")
  let workspace_root = e2e_prepare_dir(root_dir, "workspace")
  let tools_root = e2e_prepare_dir(root_dir, "tools")
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-repo-node-failure\n" },
    ],
    "Initial repo node failure commit",
    1700000960L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-repo-node-failure\n" }],
    "Update repo node failure message",
    1700000961L,
  )
  let log_path = e2e_join_path(tools_root, "git.log")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    tools_root,
    e2e_join_path(e2e_fixture_dir(scenario), "remote_action"),
    log_path,
  )
  let node_log_path = e2e_join_path(tools_root, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(tools_root, node_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      tools_root, "github_actions_cache",
    ),
    "ACTION_RUNNER_NODE_BIN": fake_node,
  }
  let result = e2e_run_cli(
    [
      ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
      "--ref", "main", "--before", before_sha, "--after", after_sha, "--repository",
      "mizchi/action_runner",
    ],
    env~,
  )
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-repo-remote-node-failure",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: blocked", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "post.txt")),
    "started|" + workspace_root,
    scenario + " post artifact",
  )
  let git_log = e2e_read_text(log_path)
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/tools",
    scenario + " git url",
  )
  let node_log = e2e_read_text(node_log_path)
  e2e_expect_contains(node_log, "pre.sh", scenario + " node pre")
  e2e_expect_contains(node_log, "main.sh", scenario + " node main")
  e2e_expect_contains(node_log, "post.sh", scenario + " node post")
}

///|
#cfg(target="native")
async fn run_repo_remote_node_failure_cache_hit() -> Unit {
  let scenario = "repo-remote-node-failure-cache-hit"
  let root_dir = "_build/e2e/repo-remote-node-failure-cache-hit"
  let repo_root = e2e_prepare_dir(root_dir, "repo")
  let workspace_root = e2e_prepare_dir(root_dir, "workspace")
  let tools_root = e2e_prepare_dir(root_dir, "tools")
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-repo-node-failure-cache\n" },
    ],
    "Initial repo node failure cache commit",
    1700000962L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-repo-node-failure-cache\n" }],
    "Update repo node failure cache message",
    1700000963L,
  )
  let cache_root = e2e_join_path(tools_root, "github_actions_cache")
  let cached_action_root = e2e_join_path(cache_root, "demo/tools/v1/action")
  e2e_copy_tree(
    e2e_join_path(e2e_fixture_dir(scenario), "remote_action/action"),
    cached_action_root,
  )
  let log_path = e2e_join_path(tools_root, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    tools_root,
    e2e_join_path(e2e_fixture_dir(scenario), "remote_action"),
    log_path,
  )
  let node_log_path = e2e_join_path(tools_root, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(tools_root, node_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
    "ACTION_RUNNER_NODE_BIN": fake_node,
  }
  let result = e2e_run_cli(
    [
      ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
      "--ref", "main", "--before", before_sha, "--after", after_sha, "--repository",
      "mizchi/action_runner",
    ],
    env~,
  )
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-repo-remote-node-failure-cache-hit",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: blocked", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "post.txt")),
    "started|" + workspace_root,
    scenario + " post artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
  let node_log = e2e_read_text(node_log_path)
  e2e_expect_contains(node_log, "pre.sh", scenario + " node pre")
  e2e_expect_contains(node_log, "main.sh", scenario + " node main")
  e2e_expect_contains(node_log, "post.sh", scenario + " node post")
}

///|
#cfg(target="native")
async fn run_repo_remote_docker_failure_cleanup() -> Unit {
  let scenario = "repo-remote-docker-failure-cleanup"
  let root_dir = "_build/e2e/repo-remote-docker-failure-cleanup"
  let repo_root = e2e_prepare_dir(root_dir, "repo")
  let workspace_root = e2e_prepare_dir(root_dir, "workspace")
  let tools_root = e2e_prepare_dir(root_dir, "tools")
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-repo-docker-failure\n" },
    ],
    "Initial repo docker failure commit",
    1700000970L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-repo-docker-failure\n" }],
    "Update repo docker failure message",
    1700000971L,
  )
  let log_path = e2e_join_path(tools_root, "git.log")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    tools_root,
    e2e_join_path(e2e_fixture_dir(scenario), "remote_action"),
    log_path,
  )
  let docker_log_path = e2e_join_path(tools_root, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(tools_root, docker_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      tools_root, "github_actions_cache",
    ),
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
  }
  let result = e2e_run_cli(
    [
      ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
      "--ref", "main", "--before", before_sha, "--after", after_sha, "--repository",
      "mizchi/action_runner",
    ],
    env~,
  )
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-repo-remote-docker-failure",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: blocked", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "post.txt")),
    "main|" + workspace_root,
    scenario + " post artifact",
  )
  let git_log = e2e_read_text(log_path)
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/tools",
    scenario + " git url",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "build", scenario + " docker build")
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "fail.sh", scenario + " docker fail")
  e2e_expect_contains(docker_log, "post.sh", scenario + " docker post")
}

///|
#cfg(target="native")
async fn run_repo_remote_docker_failure_cache_hit() -> Unit {
  let scenario = "repo-remote-docker-failure-cache-hit"
  let root_dir = "_build/e2e/repo-remote-docker-failure-cache-hit"
  let repo_root = e2e_prepare_dir(root_dir, "repo")
  let workspace_root = e2e_prepare_dir(root_dir, "workspace")
  let tools_root = e2e_prepare_dir(root_dir, "tools")
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-repo-docker-failure-cache\n" },
    ],
    "Initial repo docker failure cache commit",
    1700000972L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-repo-docker-failure-cache\n" }],
    "Update repo docker failure cache message",
    1700000973L,
  )
  let cache_root = e2e_join_path(tools_root, "github_actions_cache")
  let cached_action_root = e2e_join_path(cache_root, "demo/tools/v1/action")
  e2e_copy_tree(
    e2e_join_path(e2e_fixture_dir(scenario), "remote_action/action"),
    cached_action_root,
  )
  let log_path = e2e_join_path(tools_root, "git.log")
  @xfs.write_string_to_file(log_path, "")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    tools_root,
    e2e_join_path(e2e_fixture_dir(scenario), "remote_action"),
    log_path,
  )
  let docker_log_path = e2e_join_path(tools_root, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(tools_root, docker_log_path)
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
  }
  let result = e2e_run_cli(
    [
      ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
      "--ref", "main", "--before", before_sha, "--after", after_sha, "--repository",
      "mizchi/action_runner",
    ],
    env~,
  )
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-repo-remote-docker-failure-cache-hit",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: failed", scenario)
  e2e_expect_contains(result.stdout, "build/remote__post: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: blocked", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "post.txt")),
    "main|" + workspace_root,
    scenario + " post artifact",
  )
  e2e_expect_eq(e2e_read_text(log_path), "", scenario + " git log")
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "build", scenario + " docker build")
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "fail.sh", scenario + " docker fail")
  e2e_expect_contains(docker_log, "post.sh", scenario + " docker post")
}

///|
#cfg(target="native")
async fn run_repo_event_json() -> Unit {
  let scenario = "repo-event-json"
  let repo_root = e2e_prepare_dir("_build/e2e/repo-event-json", "repo")
  let workspace_root = e2e_prepare_dir(
    "_build/e2e/repo-event-json", "workspace",
  )
  let fixture_root = e2e_fixture_dir(scenario)
  e2e_copy_tree(e2e_join_path(fixture_root, "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-event\n" },
    ],
    "Initial event commit",
    1700000300L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-event\n" }],
    "Update event message",
    1700000301L,
  )
  let event_path = e2e_join_path(workspace_root, "event.json")
  let event_json = "{\n" +
    "  \"ref\": \"refs/heads/main\",\n" +
    "  \"before\": \"" +
    before_sha +
    "\",\n" +
    "  \"after\": \"" +
    after_sha +
    "\",\n" +
    "  \"repository\": {\n" +
    "    \"full_name\": \"mizchi/action_runner\"\n" +
    "  },\n" +
    "  \"sender\": {\n" +
    "    \"login\": \"event-cat\"\n" +
    "  },\n" +
    "  \"commits\": [\n" +
    "    {\n" +
    "      \"added\": [],\n" +
    "      \"modified\": [\"src/message.txt\"],\n" +
    "      \"removed\": []\n" +
    "    }\n" +
    "  ]\n" +
    "}\n"
  @xfs.write_string_to_file(event_path, event_json)
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--event", event_path,
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-repo-event", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/message.txt")),
    "after-event\n",
    scenario + " message artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/context.txt")),
    "push|main|mizchi/action_runner|event-cat|" + after_sha,
    scenario + " context artifact",
  )
}

///|
#cfg(target="native")
async fn run_repo_event_head_commit() -> Unit {
  let scenario = "repo-event-head-commit"
  let repo_root = e2e_prepare_dir("_build/e2e/repo-event-head-commit", "repo")
  let workspace_root = e2e_prepare_dir(
    "_build/e2e/repo-event-head-commit", "workspace",
  )
  let fixture_root = e2e_fixture_dir(scenario)
  e2e_copy_tree(e2e_join_path(fixture_root, "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-head-event\n" },
    ],
    "Initial head event commit",
    1700000600L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-head-event\n" }],
    "Update head event message",
    1700000601L,
  )
  let event_path = e2e_join_path(workspace_root, "event.json")
  let event_json = "{\n" +
    "  \"ref\": \"refs/heads/main\",\n" +
    "  \"before\": \"" +
    before_sha +
    "\",\n" +
    "  \"after\": \"" +
    after_sha +
    "\",\n" +
    "  \"repository\": {\n" +
    "    \"full_name\": \"mizchi/action_runner\"\n" +
    "  },\n" +
    "  \"sender\": {\n" +
    "    \"login\": \"head-event-cat\"\n" +
    "  },\n" +
    "  \"head_commit\": {\n" +
    "    \"added\": [],\n" +
    "    \"modified\": [\"src/message.txt\"],\n" +
    "    \"removed\": []\n" +
    "  }\n" +
    "}\n"
  @xfs.write_string_to_file(event_path, event_json)
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--event", event_path,
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-repo-head-event", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/message.txt")),
    "after-head-event\n",
    scenario + " message artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/context.txt")),
    "head-event-cat|mizchi/action_runner|" + after_sha,
    scenario + " context artifact",
  )
}

///|
#cfg(target="native")
async fn run_repo_auto_detect_repository() -> Unit {
  let scenario = "repo-auto-detect-repository"
  let repo_root = e2e_prepare_dir(
    "_build/e2e/repo-auto-detect-repository", "repo",
  )
  let workspace_root = e2e_prepare_dir(
    "_build/e2e/repo-auto-detect-repository", "workspace",
  )
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "detect\n" },
    ],
    "Initial detect commit",
    1700000200L,
    init=true,
  )
  let config_path = e2e_join_path(repo_root, ".git/config")
  let config_text = e2e_read_text(config_path) +
    "\n[remote \"origin\"]\n  url = https://github.com/mizchi/action_runner.git\n"
  @xfs.write_string_to_file(config_path, config_text)
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--ref", "main", "--after", after_sha,
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-repo-detect", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/repository.txt")),
    "mizchi/action_runner",
    scenario + " repository artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/owner.txt")),
    "mizchi",
    scenario + " owner artifact",
  )
}

///|
#cfg(target="native")
async fn run_repo_event_auto_detect_repository() -> Unit {
  let scenario = "repo-event-auto-detect-repository"
  let repo_root = e2e_prepare_dir(
    "_build/e2e/repo-event-auto-detect-repository", "repo",
  )
  let workspace_root = e2e_prepare_dir(
    "_build/e2e/repo-event-auto-detect-repository", "workspace",
  )
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-detect-event\n" },
    ],
    "Initial detect event commit",
    1700000400L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-detect-event\n" }],
    "Update detect event message",
    1700000401L,
  )
  let config_path = e2e_join_path(repo_root, ".git/config")
  let config_text = e2e_read_text(config_path) +
    "\n[remote \"origin\"]\n  url = git@github.com:mizchi/action_runner.git\n"
  @xfs.write_string_to_file(config_path, config_text)
  let event_path = e2e_join_path(workspace_root, "event.json")
  let event_json = "{\n" +
    "  \"ref\": \"refs/heads/main\",\n" +
    "  \"before\": \"" +
    before_sha +
    "\",\n" +
    "  \"after\": \"" +
    after_sha +
    "\",\n" +
    "  \"sender\": {\n" +
    "    \"login\": \"detect-cat\"\n" +
    "  },\n" +
    "  \"commits\": [\n" +
    "    {\n" +
    "      \"added\": [],\n" +
    "      \"modified\": [\"src/message.txt\"],\n" +
    "      \"removed\": []\n" +
    "    }\n" +
    "  ]\n" +
    "}\n"
  @xfs.write_string_to_file(event_path, event_json)
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--event", event_path,
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-repo-event-detect", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/message.txt")),
    "after-detect-event\n",
    scenario + " message artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/context.txt")),
    "mizchi/action_runner|mizchi|detect-cat|" + after_sha,
    scenario + " context artifact",
  )
}

///|
#cfg(target="native")
async fn run_repo_event_head_commit_auto_detect_repository() -> Unit {
  let scenario = "repo-event-head-commit-auto-detect-repository"
  let repo_root = e2e_prepare_dir(
    "_build/e2e/repo-event-head-commit-auto-detect-repository", "repo",
  )
  let workspace_root = e2e_prepare_dir(
    "_build/e2e/repo-event-head-commit-auto-detect-repository", "workspace",
  )
  e2e_copy_tree(e2e_join_path(e2e_fixture_dir(scenario), "template"), repo_root)
  let workflow_path = e2e_join_path(repo_root, ".github/workflows/ci.yml")
  let workflow_text = e2e_read_text(workflow_path)
  let before_sha = e2e_commit_repo_files(
    repo_root,
    [
      { path: ".github/workflows/ci.yml", content: workflow_text },
      { path: "src/message.txt", content: "before-head-detect\n" },
    ],
    "Initial head detect commit",
    1700000700L,
    init=true,
  )
  let after_sha = e2e_commit_repo_files(
    repo_root,
    [{ path: "src/message.txt", content: "after-head-detect\n" }],
    "Update head detect message",
    1700000701L,
  )
  let config_path = e2e_join_path(repo_root, ".git/config")
  let config_text = e2e_read_text(config_path) +
    "\n[remote \"origin\"]\n  url = git@github.com:mizchi/action_runner.git\n"
  @xfs.write_string_to_file(config_path, config_text)
  let event_path = e2e_join_path(workspace_root, "event.json")
  let event_json = "{\n" +
    "  \"ref\": \"refs/heads/main\",\n" +
    "  \"before\": \"" +
    before_sha +
    "\",\n" +
    "  \"after\": \"" +
    after_sha +
    "\",\n" +
    "  \"sender\": {\n" +
    "    \"login\": \"detect-head-cat\"\n" +
    "  },\n" +
    "  \"head_commit\": {\n" +
    "    \"added\": [],\n" +
    "    \"modified\": [\"src/message.txt\"],\n" +
    "    \"removed\": []\n" +
    "  }\n" +
    "}\n"
  @xfs.write_string_to_file(event_path, event_json)
  let result = e2e_run_cli([
    ".github/workflows/ci.yml", "--repo", repo_root, "--workspace", workspace_root,
    "--event", event_path,
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-repo-head-detect", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/message.txt")),
    "after-head-detect\n",
    scenario + " message artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace_root, "artifacts/context.txt")),
    "detect-head-cat|mizchi/action_runner|mizchi|" + after_sha,
    scenario + " context artifact",
  )
}

///|
#cfg(target="native")
async fn main {
  println("e2e: local-push-basic")
  run_local_push_basic()
  println("e2e: local-push-basic ok")

  println("e2e: local-composite-nested")
  run_local_composite_nested()
  println("e2e: local-composite-nested ok")

  println("e2e: trigger-skipped")
  run_trigger_skipped()
  println("e2e: trigger-skipped ok")

  println("e2e: file-commands")
  run_file_commands()
  println("e2e: file-commands ok")

  println("e2e: artifact-actions-roundtrip")
  run_artifact_actions_roundtrip()
  println("e2e: artifact-actions-roundtrip ok")

  println("e2e: job-failure-blocked")
  run_job_failure_blocked()
  println("e2e: job-failure-blocked ok")

  println("e2e: unsupported-uses")
  run_unsupported_uses()
  println("e2e: unsupported-uses ok")

  println("e2e: unsupported-matrix")
  run_unsupported_matrix()
  println("e2e: unsupported-matrix ok")

  println("e2e: event-cli-overrides")
  run_event_cli_overrides()
  println("e2e: event-cli-overrides ok")

  println("e2e: docker-image-basic")
  run_docker_image_basic()
  println("e2e: docker-image-basic ok")

  println("e2e: event-head-commit-fallback")
  run_event_head_commit_fallback()
  println("e2e: event-head-commit-fallback ok")

  println("e2e: remote-composite-fetch")
  run_remote_composite_fetch()
  println("e2e: remote-composite-fetch ok")

  println("e2e: remote-composite-nested-prefetch")
  run_remote_composite_nested_prefetch()
  println("e2e: remote-composite-nested-prefetch ok")

  println("e2e: remote-composite-nested-cache-hit")
  run_remote_composite_nested_cache_hit()
  println("e2e: remote-composite-nested-cache-hit ok")

  println("e2e: remote-composite-cache-hit")
  run_remote_composite_cache_hit()
  println("e2e: remote-composite-cache-hit ok")

  println("e2e: remote-node-lifecycle")
  run_remote_node_lifecycle()
  println("e2e: remote-node-lifecycle ok")

  println("e2e: remote-node-failure-cleanup")
  run_remote_node_failure_cleanup()
  println("e2e: remote-node-failure-cleanup ok")

  println("e2e: remote-node-failure-cache-hit")
  run_remote_node_failure_cache_hit()
  println("e2e: remote-node-failure-cache-hit ok")

  println("e2e: remote-node-nested-prefetch")
  run_remote_node_nested_prefetch()
  println("e2e: remote-node-nested-prefetch ok")

  println("e2e: remote-node-nested-cache-hit")
  run_remote_node_nested_cache_hit()
  println("e2e: remote-node-nested-cache-hit ok")

  println("e2e: remote-node-cache-hit")
  run_remote_node_cache_hit()
  println("e2e: remote-node-cache-hit ok")

  println("e2e: remote-docker-lifecycle")
  run_remote_docker_lifecycle()
  println("e2e: remote-docker-lifecycle ok")

  println("e2e: remote-docker-failure-cleanup")
  run_remote_docker_failure_cleanup()
  println("e2e: remote-docker-failure-cleanup ok")

  println("e2e: remote-docker-failure-cache-hit")
  run_remote_docker_failure_cache_hit()
  println("e2e: remote-docker-failure-cache-hit ok")

  println("e2e: remote-docker-nested-prefetch")
  run_remote_docker_nested_prefetch()
  println("e2e: remote-docker-nested-prefetch ok")

  println("e2e: remote-docker-nested-cache-hit")
  run_remote_docker_nested_cache_hit()
  println("e2e: remote-docker-nested-cache-hit ok")

  println("e2e: remote-docker-cache-hit")
  run_remote_docker_cache_hit()
  println("e2e: remote-docker-cache-hit ok")

  println("e2e: repo-push-bit")
  run_repo_push_bit()
  println("e2e: repo-push-bit ok")

  println("e2e: repo-needs-output")
  run_repo_needs_output()
  println("e2e: repo-needs-output ok")

  println("e2e: repo-job-file-commands")
  run_repo_job_file_commands()
  println("e2e: repo-job-file-commands ok")

  println("e2e: repo-multi-job-summary")
  run_repo_multi_job_summary()
  println("e2e: repo-multi-job-summary ok")

  println("e2e: repo-needs-summary")
  run_repo_needs_summary()
  println("e2e: repo-needs-summary ok")

  println("e2e: repo-remote-node-failure-cleanup")
  run_repo_remote_node_failure_cleanup()
  println("e2e: repo-remote-node-failure-cleanup ok")

  println("e2e: repo-remote-node-failure-cache-hit")
  run_repo_remote_node_failure_cache_hit()
  println("e2e: repo-remote-node-failure-cache-hit ok")

  println("e2e: repo-remote-docker-failure-cleanup")
  run_repo_remote_docker_failure_cleanup()
  println("e2e: repo-remote-docker-failure-cleanup ok")

  println("e2e: repo-remote-docker-failure-cache-hit")
  run_repo_remote_docker_failure_cache_hit()
  println("e2e: repo-remote-docker-failure-cache-hit ok")

  println("e2e: repo-event-json")
  run_repo_event_json()
  println("e2e: repo-event-json ok")

  println("e2e: repo-event-head-commit")
  run_repo_event_head_commit()
  println("e2e: repo-event-head-commit ok")

  println("e2e: repo-auto-detect-repository")
  run_repo_auto_detect_repository()
  println("e2e: repo-auto-detect-repository ok")

  println("e2e: repo-event-auto-detect-repository")
  run_repo_event_auto_detect_repository()
  println("e2e: repo-event-auto-detect-repository ok")

  println("e2e: repo-event-head-commit-auto-detect-repository")
  run_repo_event_head_commit_auto_detect_repository()
  println("e2e: repo-event-head-commit-auto-detect-repository ok")

  println("e2e: all scenarios passed")
}

///|
#cfg(not(target="native"))
fn main {
  println("action_runner e2e harness is supported on native target only")
}
