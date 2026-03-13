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
    let github_dir = e2e_join_path(src, ".github")
    let dst_github_dir = e2e_join_path(dst, ".github")
    if @xfs.path_exists(github_dir) && not(@xfs.path_exists(dst_github_dir)) {
      e2e_copy_tree(github_dir, dst_github_dir)
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
fn e2e_expect_not_contains(
  text : String,
  needle : String,
  context : String,
) -> Unit {
  if text.contains(needle) {
    abort(context + ": unexpected <" + needle + "> in\n" + text)
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
async fn e2e_run_env(
  cmd : String,
  args : Array[String],
  cwd : String,
  env? : Map[String, String] = {},
) -> E2eProcessResult {
  let command_args : Array[String] = []
  for key, value in env {
    command_args.push(key + "=" + value)
  }
  command_args.push(cmd)
  for arg in args {
    command_args.push(arg)
  }
  let (code, stdout, stderr) = @process.collect_output(
    "env",
    command_args,
    cwd~,
  )
  { code, stdout: stdout.text(), stderr: stderr.text() }
}

///|
#cfg(target="native")
async fn e2e_require_ok(
  label : String,
  cmd : String,
  args : Array[String],
  cwd : String,
  env? : Map[String, String] = {},
) -> Unit {
  let result = e2e_run_env(cmd, args, cwd, env~)
  if result.code != 0 {
    let message = if result.stderr.length() > 0 {
      result.stderr
    } else {
      result.stdout
    }
    abort(label + " failed: " + message)
  }
}

///|
#cfg(target="native")
async fn e2e_prepare_git_checkout_workspace(path : String) -> Unit {
  e2e_require_ok("git init", "git", ["init", "-q"], path)
  e2e_require_ok(
    "git config name",
    "git",
    ["config", "user.name", "Action Runner E2E"],
    path,
  )
  e2e_require_ok(
    "git config email",
    "git",
    ["config", "user.email", "action-runner-e2e@example.com"],
    path,
  )
  e2e_require_ok("git add first", "git", ["add", "."], path)
  e2e_require_ok(
    "git commit first",
    "git",
    ["commit", "-q", "-m", "first"],
    path,
  )
  @xfs.write_string_to_file(e2e_join_path(path, "tracked.txt"), "second\n")
  e2e_require_ok("git add second", "git", ["add", "tracked.txt"], path)
  e2e_require_ok(
    "git commit second",
    "git",
    ["commit", "-q", "-m", "second"],
    path,
  )
}

///|
#cfg(target="native")
async fn e2e_prepare_git_checkout_workspace_with_feature_branch(
  path : String,
) -> Unit {
  e2e_prepare_git_checkout_workspace(path)
  e2e_require_ok("git branch main", "git", ["branch", "-M", "main"], path)
  e2e_require_ok(
    "git checkout feature",
    "git",
    ["checkout", "-q", "-b", "feature"],
    path,
  )
  @xfs.write_string_to_file(e2e_join_path(path, "tracked.txt"), "feature\n")
  e2e_require_ok("git add feature", "git", ["add", "tracked.txt"], path)
  e2e_require_ok(
    "git commit feature",
    "git",
    ["commit", "-q", "-m", "feature"],
    path,
  )
  e2e_require_ok("git checkout main", "git", ["checkout", "-q", "main"], path)
}

///|
#cfg(target="native")
async fn e2e_prepare_git_repo_with_single_file(
  path : String,
  filename : String,
  content : String,
) -> Unit {
  e2e_remove_tree(path)
  e2e_ensure_dir(path)
  e2e_require_ok("git init", "git", ["init", "-q"], path)
  e2e_require_ok(
    "git config name",
    "git",
    ["config", "user.name", "Action Runner E2E"],
    path,
  )
  e2e_require_ok(
    "git config email",
    "git",
    ["config", "user.email", "action-runner-e2e@example.com"],
    path,
  )
  @xfs.write_string_to_file(e2e_join_path(path, filename), content)
  e2e_require_ok("git add file", "git", ["add", filename], path)
  e2e_require_ok("git commit file", "git", ["commit", "-q", "-m", "init"], path)
}

///|
#cfg(target="native")
async fn e2e_prepare_git_checkout_workspace_with_submodules(
  path : String,
  recursive? : Bool = false,
) -> Unit {
  e2e_prepare_git_checkout_workspace(path)
  let child_repo = e2e_join_path(e2e_parent_dir(path), "submodule-child")
  e2e_prepare_git_repo_with_single_file(child_repo, "child.txt", "child\n")
  if recursive {
    let grand_repo = e2e_join_path(e2e_parent_dir(path), "submodule-grand")
    e2e_prepare_git_repo_with_single_file(grand_repo, "grand.txt", "grand\n")
    e2e_require_ok(
      "child add grand submodule",
      "git",
      [
        "-c", "protocol.file.allow=always", "submodule", "add", grand_repo, "vendor/grand",
      ],
      child_repo,
    )
    e2e_require_ok(
      "child commit grand submodule",
      "git",
      ["commit", "-qam", "add grand"],
      child_repo,
    )
  }
  e2e_require_ok(
    "root add child submodule",
    "git",
    [
      "-c", "protocol.file.allow=always", "submodule", "add", child_repo, "deps/child",
    ],
    path,
  )
  e2e_require_ok(
    "root commit child submodule",
    "git",
    ["commit", "-qam", "add child"],
    path,
  )
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
async fn e2e_prepare_fake_version_node_bin(
  workspace : String,
  log_path : String,
  version : String,
) -> String {
  let bin_dir = e2e_join_path(workspace, "bin")
  e2e_ensure_dir(bin_dir)
  let node_path = e2e_join_path(bin_dir, "node")
  let absolute_log_path = e2e_absolute_path(log_path)
  @xfs.write_string_to_file(absolute_log_path, "")
  let normalized_version = if version.has_prefix("v") {
    version
  } else {
    "v" + version
  }
  let script = "#!/bin/sh\n" +
    "set -eu\n" +
    "printf '%s\\n' \"$@\" >> '" +
    absolute_log_path +
    "'\n" +
    "if [ \"${1:-}\" = \"--version\" ] || [ \"${1:-}\" = \"-v\" ]; then\n" +
    "  printf '%s\\n' '" +
    normalized_version +
    "'\n" +
    "  exit 0\n" +
    "fi\n" +
    "exit 0\n"
  @xfs.write_string_to_file(node_path, script)
  e2e_make_executable(node_path)
  e2e_absolute_path(node_path)
}

///|
#cfg(target="native")
async fn e2e_prepare_fake_wasm_bin(
  workspace : String,
  log_path : String,
) -> String {
  let bin_dir = e2e_join_path(workspace, "bin")
  e2e_ensure_dir(bin_dir)
  let wasm_path = e2e_join_path(bin_dir, "wasm-runner")
  let absolute_log_path = e2e_absolute_path(log_path)
  @xfs.write_string_to_file(absolute_log_path, "")
  let script = "#!/bin/sh\n" +
    "set -eu\n" +
    "printf '%s\\n' \"$@\" >> '" +
    absolute_log_path +
    "'\n" +
    "module=\"$1\"\n" +
    "shift || true\n" +
    "exec sh \"$module\" \"$@\"\n"
  @xfs.write_string_to_file(wasm_path, script)
  e2e_make_executable(wasm_path)
  e2e_absolute_path(wasm_path)
}

///|
#cfg(target="native")
async fn e2e_prepare_fake_docker_bin(
  workspace : String,
  log_path : String,
  inspect_sequence? : String = "healthy",
) -> String {
  let bin_dir = e2e_join_path(workspace, "bin")
  e2e_ensure_dir(bin_dir)
  let docker_path = e2e_join_path(bin_dir, "docker")
  let absolute_log_path = e2e_absolute_path(log_path)
  let inspect_count_path = e2e_absolute_path(log_path + ".inspect-count")
  @xfs.write_string_to_file(absolute_log_path, "")
  @xfs.write_string_to_file(inspect_count_path, "0")
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
    "if [ \"$cmd\" = login ] || [ \"$cmd\" = logout ] || [ \"$cmd\" = rm ]; then\n" +
    "  exit 0\n" +
    "fi\n" +
    "if [ \"$cmd\" = network ]; then\n" +
    "  exit 0\n" +
    "fi\n" +
    "if [ \"$cmd\" = inspect ]; then\n" +
    "  sequence=\"${ACTION_RUNNER_FAKE_DOCKER_INSPECT_SEQUENCE:-" +
    inspect_sequence +
    "}\"\n" +
    "  count=$(cat '" +
    inspect_count_path +
    "' 2>/dev/null || printf '0')\n" +
    "  count=$((count + 1))\n" +
    "  printf '%s' \"$count\" > '" +
    inspect_count_path +
    "'\n" +
    "  old_ifs=\"$IFS\"\n" +
    "  IFS=,\n" +
    "  set -- $sequence\n" +
    "  IFS=\"$old_ifs\"\n" +
    "  status=\"\"\n" +
    "  last=\"healthy\"\n" +
    "  idx=1\n" +
    "  for item in \"$@\"; do\n" +
    "    last=\"$item\"\n" +
    "    if [ \"$idx\" -eq \"$count\" ]; then\n" +
    "      status=\"$item\"\n" +
    "      break\n" +
    "    fi\n" +
    "    idx=$((idx + 1))\n" +
    "  done\n" +
    "  if [ -z \"$status\" ]; then\n" +
    "    status=\"$last\"\n" +
    "  fi\n" +
    "  printf '%s\\n' \"$status\"\n" +
    "  exit 0\n" +
    "fi\n" +
    "if [ \"$cmd\" = run ]; then\n" +
    "  workdir=\".\"\n" +
    "  entrypoint=\"\"\n" +
    "  while [ \"$#\" -gt 0 ]; do\n" +
    "    case \"$1\" in\n" +
    "      -e)\n" +
    "        name=\"${2%%=*}\"\n" +
    "        value=\"${2#*=}\"\n" +
    "        export \"$name=$value\"\n" +
    "        shift 2\n" +
    "        ;;\n" +
    "      -w)\n" +
    "        workdir=\"$2\"\n" +
    "        shift 2\n" +
    "        ;;\n" +
    "      -v|-p)\n" +
    "        shift 2\n" +
    "        ;;\n" +
    "      --entrypoint)\n" +
    "        entrypoint=\"$2\"\n" +
    "        shift 2\n" +
    "        ;;\n" +
    "      --rm)\n" +
    "        shift\n" +
    "        ;;\n" +
    "      --*)\n" +
    "        if [ \"$#\" -gt 1 ] && [ \"${2#-}\" = \"$2\" ]; then\n" +
    "          shift 2\n" +
    "        else\n" +
    "          shift\n" +
    "        fi\n" +
    "        ;;\n" +
    "      -*)\n" +
    "        shift\n" +
    "        ;;\n" +
    "      *)\n" +
    "        image=\"$1\"\n" +
    "        shift\n" +
    "        break\n" +
    "        ;;\n" +
    "    esac\n" +
    "  done\n" +
    "  if [ -n \"$entrypoint\" ]; then\n" +
    "    if [ \"$#\" -gt 0 ]; then\n" +
    "      set -- \"$entrypoint\" \"$@\"\n" +
    "    else\n" +
    "      set -- sh \"$entrypoint\"\n" +
    "    fi\n" +
    "  fi\n" +
    "  case \"$entrypoint\" in\n" +
    "    *pre.sh)\n" +
    "      if [ -n \"${GITHUB_STATE:-}\" ]; then\n" +
    "        printf 'phase=pre\\n' >> \"$GITHUB_STATE\"\n" +
    "      fi\n" +
    "      exit 0\n" +
    "      ;;\n" +
    "    *main.sh)\n" +
    "      if [ -n \"${GITHUB_WORKSPACE:-}\" ]; then\n" +
    "        printf '%s' \"${STATE_phase:-}\" > \"$GITHUB_WORKSPACE/main.txt\"\n" +
    "      fi\n" +
    "      if [ -n \"${GITHUB_STATE:-}\" ]; then\n" +
    "        printf 'phase=main\\n' >> \"$GITHUB_STATE\"\n" +
    "      fi\n" +
    "      exit 0\n" +
    "      ;;\n" +
    "    *fail.sh)\n" +
    "      if [ -n \"${GITHUB_WORKSPACE:-}\" ]; then\n" +
    "        printf '%s' \"${STATE_phase:-}\" > \"$GITHUB_WORKSPACE/main.txt\"\n" +
    "      fi\n" +
    "      if [ -n \"${GITHUB_STATE:-}\" ]; then\n" +
    "        printf 'phase=main\\n' >> \"$GITHUB_STATE\"\n" +
    "      fi\n" +
    "      exit 7\n" +
    "      ;;\n" +
    "    *post.sh)\n" +
    "      if [ -n \"${GITHUB_WORKSPACE:-}\" ]; then\n" +
    "        printf '%s|%s' \"${STATE_phase:-}\" \"$GITHUB_WORKSPACE\" > \"$GITHUB_WORKSPACE/post.txt\"\n" +
    "      fi\n" +
    "      exit 0\n" +
    "      ;;\n" +
    "  esac\n" +
    "  if [ \"$#\" -eq 0 ]; then\n" +
    "    exit 0\n" +
    "  fi\n" +
    "  cd \"$workdir\"\n" +
    "  exec \"$@\"\n" +
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
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_SECRET_CALL_TOKEN": "s3cr3t" },
  )
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
async fn run_store_basic() -> Unit {
  let scenario = "run-store-basic"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let run_root = e2e_join_path(workspace, "runs")
  let artifact_root = e2e_join_path(workspace, "custom-artifacts")
  let cache_root = e2e_join_path(workspace, "custom-cache")
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
    "--run-root",
    run_root,
    "--artifact-root",
    artifact_root,
    "--cache-root",
    cache_root,
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "run_id=run-1", scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-run-store", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  let run_json = e2e_read_text(e2e_join_path(run_root, "run-1/run.json"))
  e2e_expect_contains(run_json, "\"run_id\": \"run-1\"", scenario)
  e2e_expect_contains(
    run_json, "\"workflow_name\": \"e2e-run-store\"", scenario,
  )
  e2e_expect_contains(run_json, "\"workspace_mode\": \"local\"", scenario)
  e2e_expect_contains(run_json, "\"started_at_ms\": ", scenario)
  e2e_expect_contains(run_json, "\"finished_at_ms\": ", scenario)
  e2e_expect_contains(run_json, "\"steps\": [{", scenario)
  e2e_expect_contains(
    run_json, "\"stdout_path\": \"tasks/build__record.stdout.log\"", scenario,
  )
  e2e_expect_contains(
    run_json, "\"summary_path\": \"tasks/build__record.summary.md\"", scenario,
  )
  e2e_expect_contains(run_json, "\"jobs\": [{", scenario)
  e2e_expect_contains(run_json, "\"id\": \"build\"", scenario)
  e2e_expect_contains(run_json, "\"status\": \"success\"", scenario)
  e2e_expect_contains(run_json, "\"artifacts\": [{", scenario)
  e2e_expect_contains(run_json, "\"name\": \"report\"", scenario)
  e2e_expect_contains(run_json, "\"files\": [\"result.txt\"]", scenario)
  e2e_expect_contains(run_json, "\"caches\": [{", scenario)
  e2e_expect_contains(run_json, "\"key\": \"run-store-basic-key\"", scenario)
  e2e_expect_contains(
    run_json, "\"files\": [\"artifacts/result.txt\"]", scenario,
  )
  let jobs_json = e2e_read_text(e2e_join_path(run_root, "run-1/jobs.json"))
  e2e_expect_contains(jobs_json, "\"id\": \"build\"", scenario)
  e2e_expect_contains(jobs_json, "\"status\": \"success\"", scenario)
  let artifacts_json = e2e_read_text(
    e2e_join_path(run_root, "run-1/artifacts.json"),
  )
  e2e_expect_contains(artifacts_json, "\"name\": \"report\"", scenario)
  e2e_expect_contains(artifacts_json, "\"files\": [\"result.txt\"]", scenario)
  let caches_json = e2e_read_text(e2e_join_path(run_root, "run-1/caches.json"))
  e2e_expect_contains(caches_json, "\"key\": \"run-store-basic-key\"", scenario)
  e2e_expect_contains(
    caches_json, "\"files\": [\"artifacts/result.txt\"]", scenario,
  )
  e2e_expect_eq(
    e2e_read_text(
      e2e_join_path(run_root, "run-1/tasks/build__record.stdout.log"),
    ),
    "hello-run-store",
    scenario + " stdout",
  )
  e2e_expect_eq(
    e2e_read_text(
      e2e_join_path(run_root, "run-1/tasks/build__record.summary.md"),
    ),
    "summary-run-store",
    scenario + " summary",
  )
  let view_result = e2e_run_cli(["run", "view", "run-1", "--run-root", run_root])
  e2e_expect_ok(view_result, scenario + " view")
  e2e_expect_contains(view_result.stdout, "workflow=e2e-run-store", scenario)
  e2e_expect_contains(view_result.stdout, "state=completed", scenario)
  e2e_expect_contains(view_result.stdout, "job/build=success", scenario)
  e2e_expect_contains(
    view_result.stdout,
    "artifact/report=result.txt",
    scenario,
  )
  let view_json_result = e2e_run_cli([
    "run", "view", "run-1", "--run-root", run_root, "--json",
  ])
  e2e_expect_ok(view_json_result, scenario + " view json")
  e2e_expect_contains(
    view_json_result.stdout,
    "\"run_id\": \"run-1\"",
    scenario,
  )
  let watch_result = e2e_run_cli([
    "run", "watch", "run-1", "--run-root", run_root,
  ])
  e2e_expect_ok(watch_result, scenario + " watch")
  e2e_expect_contains(watch_result.stdout, "run_id=run-1", scenario)
  e2e_expect_contains(watch_result.stdout, "state=completed", scenario)
  let watch_json_result = e2e_run_cli([
    "run", "watch", "run-1", "--run-root", run_root, "--json",
  ])
  e2e_expect_ok(watch_json_result, scenario + " watch json")
  e2e_expect_contains(
    watch_json_result.stdout,
    "\"run_id\": \"run-1\"",
    scenario,
  )
  let logs_result = e2e_run_cli([
    "run", "logs", "run-1", "--run-root", run_root, "--task", "build/record",
  ])
  e2e_expect_ok(logs_result, scenario + " logs")
  e2e_expect_contains(logs_result.stdout, "==> build/record stdout", scenario)
  e2e_expect_contains(logs_result.stdout, "hello-run-store", scenario)
  e2e_expect_contains(logs_result.stdout, "==> build/record summary", scenario)
  e2e_expect_contains(logs_result.stdout, "summary-run-store", scenario)
  let logs_json_result = e2e_run_cli([
    "run", "logs", "run-1", "--run-root", run_root, "--task", "build/record", "--json",
  ])
  e2e_expect_ok(logs_json_result, scenario + " logs json")
  e2e_expect_contains(
    logs_json_result.stdout,
    "\"task_id\": \"build/record\"",
    scenario,
  )
  e2e_expect_contains(
    logs_json_result.stdout,
    "\"stdout\": \"hello-run-store\"",
    scenario,
  )
  let second_result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
    "--run-root",
    run_root,
    "--artifact-root",
    artifact_root,
    "--cache-root",
    cache_root,
  ])
  e2e_expect_ok(second_result, scenario + " second run")
  e2e_expect_contains(second_result.stdout, "run_id=run-2", scenario)
  let list_result = e2e_run_cli(["run", "list", "--run-root", run_root])
  e2e_expect_ok(list_result, scenario + " list")
  e2e_expect_contains(
    list_result.stdout,
    "run-2\tcompleted\te2e-run-store",
    scenario,
  )
  e2e_expect_contains(
    list_result.stdout,
    "run-1\tcompleted\te2e-run-store",
    scenario,
  )
  let list_json_result = e2e_run_cli([
    "run", "list", "--run-root", run_root, "--json",
  ])
  e2e_expect_ok(list_json_result, scenario + " list json")
  e2e_expect_contains(
    list_json_result.stdout,
    "\"run_id\": \"run-1\"",
    scenario,
  )
  e2e_expect_contains(
    list_json_result.stdout,
    "\"run_id\": \"run-2\"",
    scenario,
  )
  let artifact_list_result = e2e_run_cli([
    "artifact", "list", "run-1", "--run-root", run_root,
  ])
  e2e_expect_ok(artifact_list_result, scenario + " artifact list")
  e2e_expect_contains(
    artifact_list_result.stdout,
    "report\tresult.txt",
    scenario,
  )
  let artifact_list_json_result = e2e_run_cli([
    "artifact", "list", "run-1", "--run-root", run_root, "--json",
  ])
  e2e_expect_ok(artifact_list_json_result, scenario + " artifact list json")
  e2e_expect_contains(
    artifact_list_json_result.stdout,
    "\"name\": \"report\"",
    scenario,
  )
  let download_dir = e2e_join_path(workspace, "downloaded")
  let artifact_download_result = e2e_run_cli([
    "artifact", "download", "run-1", "--run-root", run_root, "--artifact-root", artifact_root,
    "--name", "report", "--dir", download_dir,
  ])
  e2e_expect_ok(artifact_download_result, scenario + " artifact download")
  e2e_expect_contains(
    artifact_download_result.stdout,
    "artifact=report",
    scenario,
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(download_dir, "result.txt")),
    "push|mizchi/action_runner",
    scenario + " artifact download file",
  )
  let artifact_download_json_result = e2e_run_cli([
    "artifact", "download", "run-1", "--run-root", run_root, "--artifact-root", artifact_root,
    "--name", "report", "--dir", download_dir, "--json",
  ])
  e2e_expect_ok(
    artifact_download_json_result,
    scenario + " artifact download json",
  )
  e2e_expect_contains(
    artifact_download_json_result.stdout,
    "\"artifact\": \"report\"",
    scenario,
  )
  e2e_expect_contains(
    artifact_download_json_result.stdout,
    "\"files\": [\"result.txt\"]",
    scenario,
  )
  let run_download_dir = e2e_join_path(workspace, "run-downloaded")
  let run_download_result = e2e_run_cli([
    "run", "download", "run-1", "--run-root", run_root, "--artifact-root", artifact_root,
    "--dir", run_download_dir,
  ])
  e2e_expect_ok(run_download_result, scenario + " run download")
  e2e_expect_contains(run_download_result.stdout, "run_id=run-1", scenario)
  e2e_expect_contains(run_download_result.stdout, "artifacts=report", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(run_download_dir, "report/result.txt")),
    "push|mizchi/action_runner",
    scenario + " run download file",
  )
  let run_download_json_result = e2e_run_cli([
    "run", "download", "run-1", "--run-root", run_root, "--artifact-root", artifact_root,
    "--dir", run_download_dir, "--json",
  ])
  e2e_expect_ok(run_download_json_result, scenario + " run download json")
  e2e_expect_contains(
    run_download_json_result.stdout,
    "\"run_id\": \"run-1\"",
    scenario,
  )
  e2e_expect_contains(
    run_download_json_result.stdout,
    "\"artifacts\": [\"report\"]",
    scenario,
  )
  let cache_list_result = e2e_run_cli([
    "cache", "list", "--cache-root", cache_root,
  ])
  e2e_expect_ok(cache_list_result, scenario + " cache list")
  e2e_expect_contains(
    cache_list_result.stdout,
    "run-store-basic-key\t",
    scenario,
  )
  e2e_expect_contains(
    cache_list_result.stdout,
    "artifacts/result.txt",
    scenario,
  )
  let cache_list_json_result = e2e_run_cli([
    "cache", "list", "--cache-root", cache_root, "--json",
  ])
  e2e_expect_ok(cache_list_json_result, scenario + " cache list json")
  e2e_expect_contains(
    cache_list_json_result.stdout,
    "\"key\": \"run-store-basic-key\"",
    scenario,
  )
  let workspace_key = e2e_absolute_path(workspace)
    .replace_all(old="/", new="__")
    .replace_all(old=":", new="_")
  e2e_expect_eq(
    e2e_read_text(
      e2e_join_path(artifact_root, workspace_key + "/report/result.txt"),
    ),
    "push|mizchi/action_runner",
    scenario + " artifact root override",
  )
  e2e_expect_eq(
    e2e_read_text(
      e2e_join_path(
        cache_root,
        workspace_key + "/run-store-basic-key/artifacts/result.txt",
      ),
    ),
    "push|mizchi/action_runner",
    scenario + " cache root override",
  )
  let cache_prune_result = e2e_run_cli([
    "cache", "prune", "--cache-root", cache_root, "--key", "run-store-basic-key",
  ])
  e2e_expect_ok(cache_prune_result, scenario + " cache prune")
  e2e_expect_contains(
    cache_prune_result.stdout,
    "run-store-basic-key\t",
    scenario,
  )
  let cache_list_after_prune = e2e_run_cli([
    "cache", "list", "--cache-root", cache_root,
  ])
  e2e_expect_ok(cache_list_after_prune, scenario + " cache list after prune")
  e2e_expect_eq(
    cache_list_after_prune.stdout,
    "",
    scenario + " cache list empty",
  )
}

///|
#cfg(target="native")
async fn run_workflow_list_basic() -> Unit {
  let scenario = "workflow-list-basic"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli(["workflow", "list", "--repo", workspace])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "ci\t.github/workflows/ci.yml", scenario)
  e2e_expect_contains(
    result.stdout,
    "lint\t.github/workflows/lint.yaml",
    scenario,
  )
  let json_result = e2e_run_cli([
    "workflow", "list", "--repo", workspace, "--json",
  ])
  e2e_expect_ok(json_result, scenario + " json")
  e2e_expect_contains(json_result.stdout, "\"name\": \"ci\"", scenario)
  e2e_expect_contains(
    json_result.stdout,
    "\"path\": \".github/workflows/lint.yaml\"",
    scenario,
  )
}

///|
#cfg(target="native")
async fn run_workflow_run_basic() -> Unit {
  let scenario = "workflow-run-basic"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir("workflow-list-basic"),
  )
  let run_root = e2e_join_path(workspace, "runs")
  let result = e2e_run_cli([
    "workflow",
    "run",
    e2e_join_path(workspace, ".github/workflows/ci.yml"),
    "--run-root",
    run_root,
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "run_id=run-1", scenario)
  e2e_expect_contains(result.stdout, "workflow=ci", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  let run_json = e2e_read_text(e2e_join_path(run_root, "run-1/run.json"))
  e2e_expect_contains(run_json, "\"workflow_name\": \"ci\"", scenario)
  e2e_expect_contains(
    run_json,
    "\"workflow_path\": \"" +
    e2e_join_path(workspace, ".github/workflows/ci.yml") +
    "\"",
    scenario,
  )
}

///|
#cfg(target="native")
async fn run_watch_failure_exit_code() -> Unit {
  let scenario = "run-watch-failure-exit-code"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let run_root = e2e_join_path(workspace, "runs")
  let run_result = e2e_run_cli([
    "workflow",
    "run",
    e2e_join_path(workspace, "workflow.yml"),
    "--run-root",
    run_root,
  ])
  e2e_expect_fail(run_result, scenario + " run")
  e2e_expect_contains(run_result.stdout, "run_id=run-1", scenario)
  e2e_expect_contains(run_result.stdout, "state=partial_failed", scenario)
  let run_json = e2e_read_text(e2e_join_path(run_root, "run-1/run.json"))
  e2e_expect_contains(run_json, "\"exit_code\": 1", scenario)
  let watch_result = e2e_run_cli([
    "run", "watch", "run-1", "--run-root", run_root,
  ])
  e2e_expect_fail(watch_result, scenario + " watch")
  e2e_expect_contains(watch_result.stdout, "state=partial_failed", scenario)
  let watch_json_result = e2e_run_cli([
    "run", "watch", "run-1", "--run-root", run_root, "--json",
  ])
  e2e_expect_fail(watch_json_result, scenario + " watch json")
  e2e_expect_contains(watch_json_result.stdout, "\"exit_code\": 1", scenario)
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
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_SECRET_CALL_TOKEN": "s3cr3t" },
  )
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
async fn run_local_reusable_workflow() -> Unit {
  let scenario = "local-reusable-workflow"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_SECRET_CALL_TOKEN": "s3cr3t" },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-reusable", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "after/package: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "reusable|s3cr3t-done",
    scenario + " artifact",
  )
}

///|
#cfg(target="native")
async fn run_local_reusable_workflow_inherit() -> Unit {
  let scenario = "local-reusable-workflow-inherit"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_SECRET_TOKEN": "s3cr3t" },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-reusable-inherit", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "after/package: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "s3cr3t-done",
    scenario + " artifact",
  )
}

///|
#cfg(target="native")
async fn run_local_reusable_workflow_input_types() -> Unit {
  let scenario = "local-reusable-workflow-input-types"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=local-reusable-workflow-input-types",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "after/package: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "false|0|hello",
    scenario + " artifact",
  )
}

///|
#cfg(target="native")
async fn run_local_reusable_workflow_matrix() -> Unit {
  let scenario = "local-reusable-workflow-matrix"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=local-reusable-workflow-matrix",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "after/verify: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "done",
    scenario + " artifact",
  )
}

///|
#cfg(target="native")
async fn run_local_reusable_workflow_matrix_output() -> Unit {
  let scenario = "local-reusable-workflow-matrix-output"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=local-reusable-workflow-matrix-output",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "after/show: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "one",
    scenario + " artifact",
  )
}

///|
#cfg(target="native")
async fn run_remote_reusable_workflow() -> Unit {
  let scenario = "remote-reusable-workflow"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_repo"),
    log_path,
  )
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_SECRET_CALL_TOKEN": "s3cr3t",
  }
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
      "--github-action-cache-root",
      e2e_join_path(workspace, "github_actions_cache"),
    ],
    env~,
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-remote-reusable", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "after/package: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "remote-reusable|s3cr3t-done",
    scenario + " artifact",
  )
  let git_log = e2e_read_text(log_path)
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/tools.git",
    scenario + " git url",
  )
}

///|
#cfg(target="native")
async fn run_remote_reusable_local_action() -> Unit {
  let scenario = "remote-reusable-local-action"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let log_path = e2e_join_path(workspace, "git.log")
  let fake_git = e2e_prepare_fake_git_bin_from_source(
    workspace,
    e2e_join_path(workspace, "remote_repo"),
    log_path,
  )
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
    "ACTION_RUNNER_SECRET_CALL_TOKEN": "s3cr3t",
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
    "workflow=e2e-remote-reusable-local-action",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "after/package: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "remote-local|s3cr3t-done",
    scenario + " artifact",
  )
}

///|
#cfg(target="native")
async fn run_remote_nested_reusable_workflow() -> Unit {
  let scenario = "remote-nested-reusable-workflow"
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
        match_text: "https://github.com/demo/outer.git",
        source_dir: e2e_join_path(workspace, "outer_repo"),
      },
      {
        match_text: "https://github.com/demo/inner.git",
        source_dir: e2e_join_path(workspace, "inner_repo"),
      },
    ],
    log_path,
  )
  let env : Map[String, String] = {
    "ACTION_RUNNER_GIT_BIN": fake_git,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": e2e_join_path(
      workspace, "github_actions_cache",
    ),
    "ACTION_RUNNER_SECRET_CALL_TOKEN": "s3cr3t",
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
    "workflow=e2e-remote-nested-reusable",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "after/package: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "remote-nested|s3cr3t-done",
    scenario + " artifact",
  )
  let git_log = e2e_read_text(log_path)
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/outer.git",
    scenario + " outer git url",
  )
  e2e_expect_contains(
    git_log,
    "https://github.com/demo/inner.git",
    scenario + " inner git url",
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
async fn run_artifact_actions_roundtrip_container() -> Unit {
  let scenario = "artifact-actions-roundtrip-container"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": fake_docker },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-artifact-actions-container",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/upload: success", scenario)
  e2e_expect_contains(result.stdout, "build/download: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "alpha|beta",
    scenario + " result artifact",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "alpine:3.21", scenario + " docker image")
}

///|
#cfg(target="native")
async fn run_artifact_glob_directory() -> Unit {
  let scenario = "artifact-glob-directory"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-artifact-glob-directory",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/upload_dir: success", scenario)
  e2e_expect_contains(result.stdout, "build/upload_glob: success", scenario)
  e2e_expect_contains(result.stdout, "build/download_all: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "root|child|linux|macos|no|no",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_artifact_if_no_files_found() -> Unit {
  let scenario = "artifact-if-no-files-found"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-artifact-if-no-files-found",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/upload_warn: success", scenario)
  e2e_expect_contains(result.stdout, "build/upload_ignore: success", scenario)
  e2e_expect_contains(result.stdout, "build/upload_error: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "success|success|success|success|failure|success",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_artifact_overwrite() -> Unit {
  let scenario = "artifact-overwrite"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-artifact-overwrite",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/upload_first: success", scenario)
  e2e_expect_contains(result.stdout, "build/upload_again: success", scenario)
  e2e_expect_contains(
    result.stdout,
    "build/upload_overwrite: success",
    scenario,
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "failure|success|beta",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_artifact_merge_multiple() -> Unit {
  let scenario = "artifact-merge-multiple"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-artifact-merge-multiple",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/upload_dir: success", scenario)
  e2e_expect_contains(result.stdout, "build/upload_glob: success", scenario)
  e2e_expect_contains(result.stdout, "build/download_all: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "root|child|linux|macos|no|no",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_cache_actions_roundtrip() -> Unit {
  let scenario = "cache-actions-roundtrip"
  e2e_remove_tree("_build/action_runner/cache")
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
  e2e_expect_contains(result.stdout, "workflow=e2e-cache-actions", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "save/save: success", scenario)
  e2e_expect_contains(result.stdout, "restore/restore: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "true|ocean",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_cache_auto_save_roundtrip() -> Unit {
  let scenario = "cache-auto-save-roundtrip"
  e2e_remove_tree("_build/action_runner/cache")
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
  e2e_expect_contains(result.stdout, "workflow=e2e-cache-auto-save", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "save/cache: success", scenario)
  e2e_expect_contains(result.stdout, "save/cache__post: success", scenario)
  e2e_expect_contains(result.stdout, "restore/cache: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "true|ocean",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_cache_auto_save_container() -> Unit {
  let scenario = "cache-auto-save-container"
  e2e_remove_tree("_build/action_runner/cache")
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": fake_docker },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-cache-auto-save-container",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "save/cache: success", scenario)
  e2e_expect_contains(result.stdout, "save/cache__post: success", scenario)
  e2e_expect_contains(result.stdout, "restore/cache: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "true|ocean",
    scenario + " result artifact",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "alpine:3.21", scenario + " docker image")
}

///|
#cfg(target="native")
async fn run_cache_restore_keys() -> Unit {
  let scenario = "cache-restore-keys"
  e2e_remove_tree("_build/action_runner/cache")
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-cache-restore-keys",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "save/save: success", scenario)
  e2e_expect_contains(result.stdout, "restore/restore: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "false|ocean",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_cache_lookup_only() -> Unit {
  let scenario = "cache-lookup-only"
  e2e_remove_tree("_build/action_runner/cache")
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
  e2e_expect_contains(result.stdout, "workflow=e2e-cache-lookup-only", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "save/save: success", scenario)
  e2e_expect_contains(result.stdout, "restore/restore: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "true|no",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_cache_fail_on_cache_miss() -> Unit {
  let scenario = "cache-fail-on-cache-miss"
  e2e_remove_tree("_build/action_runner/cache")
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-cache-fail-on-cache-miss",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "failure|success|no",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_checkout_sparse_path() -> Unit {
  let scenario = "checkout-sparse-path"
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
  e2e_expect_contains(result.stdout, "workflow=e2e-checkout-sparse", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/checkout: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "yes|yes|yes",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_checkout_fetch_depth() -> Unit {
  let scenario = "checkout-fetch-depth"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  e2e_prepare_git_checkout_workspace(workspace)
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-checkout-fetch-depth",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/shallow: success", scenario)
  e2e_expect_contains(result.stdout, "build/full: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/shallow.txt")),
    "1|yes",
    scenario + " shallow artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/full.txt")),
    "2|no",
    scenario + " full artifact",
  )
}

///|
#cfg(target="native")
async fn run_checkout_ref() -> Unit {
  let scenario = "checkout-ref"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  e2e_prepare_git_checkout_workspace_with_feature_branch(workspace)
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-checkout-ref", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/checkout: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "feature|feature|1|yes",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_checkout_clean() -> Unit {
  let scenario = "checkout-clean"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  e2e_prepare_git_checkout_workspace(workspace)
  @xfs.write_string_to_file(
    e2e_join_path(workspace, "scratch-before.txt"),
    "keep me\n",
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-checkout-clean", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/keep_dirty: success", scenario)
  e2e_expect_contains(result.stdout, "build/clean_checkout: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/clean.txt")),
    "yes|no|no",
    scenario + " clean artifact",
  )
}

///|
#cfg(target="native")
async fn run_checkout_submodules() -> Unit {
  let scenario = "checkout-submodules"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  e2e_prepare_git_checkout_workspace_with_submodules(workspace, recursive=true)
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-checkout-submodules",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/direct: success", scenario)
  e2e_expect_contains(result.stdout, "build/recursive: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/direct.txt")),
    "yes|no",
    scenario + " direct artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/recursive.txt")),
    "yes|yes",
    scenario + " recursive artifact",
  )
}

///|
#cfg(target="native")
async fn run_checkout_container() -> Unit {
  let scenario = "checkout-container"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  e2e_prepare_git_checkout_workspace(workspace)
  let tools_root = e2e_join_path("_build/e2e/tools", scenario)
  e2e_remove_tree(tools_root)
  e2e_ensure_dir(tools_root)
  let docker_log_path = e2e_join_path(tools_root, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(tools_root, docker_log_path)
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": fake_docker },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-checkout-container",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/checkout: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "second|yes",
    scenario + " result artifact",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(
    docker_log,
    "node:20-bookworm",
    scenario + " container image",
  )
}

///|
#cfg(target="native")
async fn run_setup_node_basic() -> Unit {
  let scenario = "setup-node-basic"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let node_log_path = e2e_join_path(workspace, "setup-node.log")
  let fake_node = e2e_prepare_fake_version_node_bin(
    workspace, node_log_path, "24.9.0",
  )
  ignore(fake_node)
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-setup-node-basic", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/setup: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "v20.19.5|v20.19.5|XXXXX-XXXXX-XXXXX-XXXXX|yes|//registry.npmjs.org/:_authToken=${NODE_AUTH_TOKEN};registry=https://registry.npmjs.org/;",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_setup_node_cache_npm() -> Unit {
  let scenario = "setup-node-cache-npm"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let node_log_path = e2e_join_path(workspace, "setup-node-cache.log")
  ignore(e2e_prepare_fake_version_node_bin(workspace, node_log_path, "24.9.0"))
  @xfs.write_string_to_file(
    e2e_join_path(workspace, "package-lock.json"),
    "{\"lock\":1}\n",
  )
  let result = e2e_run_cli([
    e2e_join_path(workspace, "workflow.yml"),
    "--event",
    e2e_join_path(workspace, "event.json"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-setup-node-cache-npm",
    scenario,
  )
  e2e_expect_contains(result.stdout, "save/setup: success", scenario)
  e2e_expect_contains(result.stdout, "save/setup__post: success", scenario)
  e2e_expect_contains(result.stdout, "restore/setup: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "true|ocean|false|v20.19.5",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_setup_node_container() -> Unit {
  let scenario = "setup-node-container"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let node_log_path = e2e_join_path(workspace, "setup-node.log")
  ignore(e2e_prepare_fake_version_node_bin(workspace, node_log_path, "24.9.0"))
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": fake_docker },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-setup-node-container",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/setup: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "v20.0.0|v20.0.0",
    scenario + " result artifact",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(
    docker_log,
    "node:20-bookworm",
    scenario + " container image",
  )
}

///|
#cfg(target="native")
async fn run_expression_string_functions() -> Unit {
  let scenario = "expression-string-functions"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-expression-string-functions",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/show: success", scenario)
  e2e_expect_contains(result.stdout, "build/on_contains: success", scenario)
  e2e_expect_contains(result.stdout, "build/on_starts: success", scenario)
  e2e_expect_contains(result.stdout, "build/on_ends: success", scenario)
  e2e_expect_contains(result.stdout, "build/skip_release: skipped", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/script.txt")),
    "true|true|true|true",
    scenario + " script artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "yes|yes|yes|no",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_expression_json_functions() -> Unit {
  let scenario = "expression-json-functions"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-expression-json-functions",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/show: success", scenario)
  e2e_expect_contains(result.stdout, "build/on_enabled: success", scenario)
  e2e_expect_contains(result.stdout, "build/on_event: success", scenario)
  e2e_expect_contains(result.stdout, "build/skip_false: skipped", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/script.txt")),
    "true|true|true|\"mizchi/action_runner\"",
    scenario + " script artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "yes|yes|no",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_expression_hash_files() -> Unit {
  let scenario = "expression-hash-files"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-expression-hash-files",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/show: success", scenario)
  e2e_expect_contains(result.stdout, "build/on_match: success", scenario)
  e2e_expect_contains(result.stdout, "build/skip_missing: skipped", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/script.txt")),
    "yes|yes|yes",
    scenario + " script artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "yes|no",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_expression_vars() -> Unit {
  let scenario = "expression-vars"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={
      "ACTION_RUNNER_VAR_COLOR": "ocean",
      "ACTION_RUNNER_VAR_FEATURE_ENABLED": "true",
    },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-expression-vars", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/show: success", scenario)
  e2e_expect_contains(result.stdout, "build/on_enabled: success", scenario)
  e2e_expect_contains(result.stdout, "build/skip_missing: skipped", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/script.txt")),
    "ocean|ocean|yes|ocean",
    scenario + " script artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "yes|no",
    scenario + " result artifact",
  )
}

///|
#cfg(target="native")
async fn run_expression_secrets() -> Unit {
  let scenario = "expression-secrets"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_SECRET_TOKEN": "s3cr3t" },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-expression-secrets",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/show: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/script.txt")),
    "s3cr3t|s3cr3t|yes|s3cr3t",
    scenario + " script artifact",
  )
}

///|
#cfg(target="native")
async fn run_matrix_include_basic() -> Unit {
  let scenario = "matrix-include-basic"
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
  e2e_expect_contains(result.stdout, "workflow=e2e-matrix-include", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_1/emit: success", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_2/emit: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/native.txt")),
    "native",
    scenario + " native artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/js.txt")),
    "js",
    scenario + " js artifact",
  )
}

///|
#cfg(target="native")
async fn run_matrix_exclude_basic() -> Unit {
  let scenario = "matrix-exclude-basic"
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
  e2e_expect_contains(result.stdout, "workflow=e2e-matrix-exclude", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_1/emit: success", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_2/emit: success", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_3/emit: success", scenario)
  e2e_expect_eq(
    e2e_read_text(
      e2e_join_path(workspace, "artifacts/native-ubuntu-latest.txt"),
    ),
    "ubuntu-latest|native",
    scenario + " ubuntu native artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/js-ubuntu-latest.txt")),
    "ubuntu-latest|js",
    scenario + " ubuntu js artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/native-macos-latest.txt")),
    "macos-latest|native",
    scenario + " macos native artifact",
  )
}

///|
#cfg(target="native")
async fn run_matrix_mixed_include_basic() -> Unit {
  let scenario = "matrix-mixed-include-basic"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-matrix-mixed-include",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_1/emit: success", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_2/emit: success", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_3/emit: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/ubuntu-latest-js.txt")),
    "ubuntu-latest|js",
    scenario + " ubuntu js artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/macos-latest-native.txt")),
    "macos-latest|native",
    scenario + " macos native artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/windows-latest-js.txt")),
    "windows-latest|js",
    scenario + " windows js artifact",
  )
}

///|
#cfg(target="native")
async fn run_matrix_max_parallel_basic() -> Unit {
  let scenario = "matrix-max-parallel-basic"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-matrix-max-parallel",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_1/emit: success", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_2/emit: success", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_3/emit: success", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_4/emit: success", scenario)
  e2e_expect_eq(
    e2e_read_text(
      e2e_join_path(workspace, "artifacts/ubuntu-latest-native.txt"),
    ),
    "ubuntu-latest|native",
    scenario + " ubuntu native artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/ubuntu-latest-js.txt")),
    "ubuntu-latest|js",
    scenario + " ubuntu js artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/macos-latest-native.txt")),
    "macos-latest|native",
    scenario + " macos native artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/macos-latest-js.txt")),
    "macos-latest|js",
    scenario + " macos js artifact",
  )
}

///|
#cfg(target="native")
async fn run_matrix_fail_fast_basic() -> Unit {
  let scenario = "matrix-fail-fast-basic"
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
  e2e_expect_contains(result.stdout, "workflow=e2e-matrix-fail-fast", scenario)
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_1/emit: success", scenario)
  e2e_expect_contains(result.stdout, "build__matrix_2/emit: failed", scenario)
  e2e_expect_contains(
    result.stdout,
    "build__matrix_3/emit: cancelled",
    scenario,
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/ok.txt")),
    "ok",
    scenario + " ok artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/fail.txt")),
    "fail",
    scenario + " fail artifact",
  )
  e2e_expect_missing(
    e2e_join_path(workspace, "artifacts/late.txt"),
    scenario + " cancelled artifact",
  )
}

///|
#cfg(target="native")
async fn run_matrix_needs_output_basic() -> Unit {
  let scenario = "matrix-needs-output-basic"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-matrix-needs-output",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "consume/read: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "success|native|js",
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
  e2e_expect_contains(result.stdout, "lint/wait: skipped", scenario)
}

///|
#cfg(target="native")
async fn run_job_if_always() -> Unit {
  let scenario = "job-if-always"
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
  e2e_expect_contains(result.stdout, "workflow=e2e-job-if-always", scenario)
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/fail: failed", scenario)
  e2e_expect_contains(result.stdout, "cleanup/finalize: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/cleanup.txt")),
    "cleanup-ran",
    scenario + " cleanup artifact",
  )
}

///|
#cfg(target="native")
async fn run_step_if_status_functions() -> Unit {
  let scenario = "step-if-status-functions"
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
  e2e_expect_contains(result.stdout, "workflow=e2e-step-if-status", scenario)
  e2e_expect_contains(result.stdout, "state=partial_failed", scenario)
  e2e_expect_contains(result.stdout, "build/fail: failed", scenario)
  e2e_expect_contains(result.stdout, "build/default_skip: skipped", scenario)
  e2e_expect_contains(result.stdout, "build/on_failure: success", scenario)
  e2e_expect_contains(result.stdout, "build/always_step: success", scenario)
  e2e_expect_contains(result.stdout, "build/on_cancelled: skipped", scenario)
  e2e_expect_missing(
    e2e_join_path(workspace, "artifacts/default.txt"),
    scenario + " default skip artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/failure.txt")),
    "failure-ran",
    scenario + " failure artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/always.txt")),
    "always-ran",
    scenario + " always artifact",
  )
  e2e_expect_missing(
    e2e_join_path(workspace, "artifacts/cancelled.txt"),
    scenario + " cancelled artifact",
  )
}

///|
#cfg(target="native")
async fn run_step_continue_on_error_basic() -> Unit {
  let scenario = "step-continue-on-error-basic"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-step-continue-on-error",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/fail_soft: success", scenario)
  e2e_expect_contains(result.stdout, "build/after: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/after.txt")),
    "after-ran",
    scenario + " after artifact",
  )
}

///|
#cfg(target="native")
async fn run_step_status_context() -> Unit {
  let scenario = "step-status-context"
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
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-step-status-context",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/second: success", scenario)
  e2e_expect_contains(result.stdout, "build/gate: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "success|success|failure|success",
    scenario + " status artifact",
  )
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
    "error: jobs.build.strategy.max-parallel must be positive",
    scenario,
  )
}

///|
#cfg(target="native")
async fn run_unsupported_permissions() -> Unit {
  let scenario = "unsupported-permissions"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([e2e_join_path(workspace, "workflow.yml")])
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "error: workflow permissions are not supported in MVP",
    scenario,
  )
  e2e_expect_contains(
    result.stdout,
    "error: job 'build' permissions are not supported in MVP",
    scenario,
  )
}

///|
#cfg(target="native")
async fn run_unsupported_concurrency() -> Unit {
  let scenario = "unsupported-concurrency"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([e2e_join_path(workspace, "workflow.yml")])
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "error: workflow concurrency is not supported in MVP",
    scenario,
  )
  e2e_expect_contains(
    result.stdout,
    "error: job 'build' concurrency is not supported in MVP",
    scenario,
  )
}

///|
#cfg(target="native")
async fn run_unsupported_workflow_call() -> Unit {
  let scenario = "unsupported-workflow-call"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([e2e_join_path(workspace, "workflow.yml")])
  e2e_expect_fail(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "error: workflow_call is not supported in MVP",
    scenario,
  )
}

///|
#cfg(target="native")
async fn run_job_container_basic() -> Unit {
  let scenario = "job-container-basic"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let result = e2e_run_cli([e2e_join_path(workspace, "workflow.yml")], env={
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
  })
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=job-container-basic", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/show: success", scenario)
  e2e_expect_eq(
    @xfs.read_file_to_string(e2e_join_path(workspace, "out.txt")),
    "from-container|" + workspace + "/nested",
    scenario + " output",
  )
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "alpine:3.21", scenario + " docker image")
}

///|
#cfg(target="native")
async fn run_job_container_node_action() -> Unit {
  let scenario = "job-container-node-action"
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
  let node_log_path = e2e_join_path(workspace, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(workspace, node_log_path)
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let result = e2e_run_cli([e2e_join_path(workspace, "workflow.yml")], env={
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
    "ACTION_RUNNER_NODE_BIN": fake_node,
  })
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-job-container-node-action",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "node.txt")),
    "from-container|" + workspace + "|" + cached_action_root,
    scenario + " output",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "alpine:3.21", scenario + " docker image")
  e2e_expect_contains(docker_log, fake_node, scenario + " node bin")
  e2e_expect_contains(
    docker_log,
    cached_action_root + "/main.sh",
    scenario + " entrypoint",
  )
}

///|
#cfg(target="native")
async fn run_job_container_docker_action() -> Unit {
  let scenario = "job-container-docker-action"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let cache_root = e2e_join_path(workspace, "github_actions_cache")
  let cached_action_root = e2e_join_path(
    cache_root, "demo/docker-action/v1/action",
  )
  e2e_copy_tree(
    e2e_join_path(workspace, "remote_action/action"),
    cached_action_root,
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let result = e2e_run_cli([e2e_join_path(workspace, "workflow.yml")], env={
    "ACTION_RUNNER_DOCKER_BIN": fake_docker,
    "ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT": cache_root,
  })
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-job-container-docker-action",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/remote: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "docker.txt")),
    "",
    scenario + " output",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "-v", scenario + " volume flag")
  e2e_expect_contains(docker_log, "cache:/cache", scenario + " shared volume")
  e2e_expect_not_contains(
    docker_log,
    "CONTAINER_FLAG=from-container",
    scenario + " no container env",
  )
}

///|
#cfg(target="native")
async fn run_job_services_basic() -> Unit {
  let scenario = "job-services-basic"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": fake_docker },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=job-services-basic", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/show: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "5432|5432|yes",
    scenario + " result artifact",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(docker_log, "run", scenario + " docker run")
  e2e_expect_contains(docker_log, "-d", scenario + " detached service")
  e2e_expect_contains(
    docker_log,
    "action-runner-service-build__postgres",
    scenario + " service name",
  )
  e2e_expect_contains(docker_log, "postgres:16", scenario + " service image")
  e2e_expect_contains(docker_log, "inspect", scenario + " health inspect")
  e2e_expect_contains(docker_log, "rm", scenario + " cleanup command")
}

///|
#cfg(target="native")
async fn run_job_services_container_network() -> Unit {
  let scenario = "job-services-container-network"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let docker_log_path = e2e_join_path(workspace, "docker.log")
  let fake_docker = e2e_prepare_fake_docker_bin(workspace, docker_log_path)
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--event",
      e2e_join_path(workspace, "event.json"),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": fake_docker },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=job-services-container-network",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/show: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "artifacts/result.txt")),
    "hi",
    scenario + " result artifact",
  )
  let docker_log = e2e_read_text(docker_log_path)
  e2e_expect_contains(
    docker_log,
    "network\ncreate\naction-runner-job-build\n",
    scenario + " network create",
  )
  e2e_expect_contains(
    docker_log,
    "--network-alias\npostgres\n",
    scenario + " network alias",
  )
  e2e_expect_contains(
    docker_log,
    "network\nrm\naction-runner-job-build\n",
    scenario + " network cleanup",
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
async fn run_wasm_action_basic() -> Unit {
  let scenario = "wasm-action-basic"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let wasm_log_path = e2e_join_path(workspace, "wasm.log")
  let wasm_bin = e2e_prepare_fake_wasm_bin(workspace, wasm_log_path)
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--wasm-action-root",
      e2e_join_path(workspace, "wasm-actions"),
    ],
    env={ "ACTION_RUNNER_WASM_BIN": wasm_bin },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "workflow=e2e-wasm-action", scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/module: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "verify.txt")),
    "from-wasm",
    scenario + " verify artifact",
  )
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "wasm-artifact.txt")),
    "hello|" + workspace + "\n",
    scenario + " wasm artifact",
  )
  let wasm_log = e2e_read_text(wasm_log_path)
  e2e_expect_contains(wasm_log, "main.wasm", scenario + " wasm log")
}

///|
#cfg(target="native")
async fn run_custom_registry_node_action() -> Unit {
  let scenario = "custom-registry-node-action"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let node_log_path = e2e_join_path(workspace, "node.log")
  let fake_node = e2e_prepare_fake_node_bin(workspace, node_log_path)
  let result = e2e_run_cli(
    [
      e2e_join_path(workspace, "workflow.yml"),
      "--registry-root",
      e2e_join_path(workspace, "registry-actions"),
    ],
    env={ "ACTION_RUNNER_NODE_BIN": fake_node },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(
    result.stdout,
    "workflow=e2e-custom-registry-node",
    scenario,
  )
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/setup: success", scenario)
  e2e_expect_contains(result.stdout, "build/verify: success", scenario)
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(workspace, "registry-node.txt")),
    "from-registry",
    scenario + " registry artifact",
  )
  let node_log = e2e_read_text(node_log_path)
  e2e_expect_contains(node_log, "index.sh", scenario + " node log")
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
  e2e_expect_contains(result.stdout, "build/verify: skipped", scenario)
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
  e2e_expect_contains(result.stdout, "build/verify: skipped", scenario)
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
  e2e_expect_contains(result.stdout, "build/verify: skipped", scenario)
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
  e2e_expect_contains(result.stdout, "build/verify: skipped", scenario)
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
  e2e_expect_contains(result.stdout, "build/verify: skipped", scenario)
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
  e2e_expect_contains(result.stdout, "build/verify: skipped", scenario)
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
  e2e_expect_contains(result.stdout, "build/verify: skipped", scenario)
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
  e2e_expect_contains(result.stdout, "build/verify: skipped", scenario)
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

  println("e2e: run-store-basic")
  run_store_basic()
  println("e2e: run-store-basic ok")

  println("e2e: workflow-list-basic")
  run_workflow_list_basic()
  println("e2e: workflow-list-basic ok")

  println("e2e: workflow-run-basic")
  run_workflow_run_basic()
  println("e2e: workflow-run-basic ok")

  println("e2e: run-watch-failure-exit-code")
  run_watch_failure_exit_code()
  println("e2e: run-watch-failure-exit-code ok")

  println("e2e: local-composite-nested")
  run_local_composite_nested()
  println("e2e: local-composite-nested ok")

  println("e2e: local-reusable-workflow")
  run_local_reusable_workflow()
  println("e2e: local-reusable-workflow ok")

  println("e2e: local-reusable-workflow-inherit")
  run_local_reusable_workflow_inherit()
  println("e2e: local-reusable-workflow-inherit ok")

  println("e2e: local-reusable-workflow-input-types")
  run_local_reusable_workflow_input_types()
  println("e2e: local-reusable-workflow-input-types ok")

  println("e2e: local-reusable-workflow-matrix")
  run_local_reusable_workflow_matrix()
  println("e2e: local-reusable-workflow-matrix ok")

  println("e2e: local-reusable-workflow-matrix-output")
  run_local_reusable_workflow_matrix_output()
  println("e2e: local-reusable-workflow-matrix-output ok")

  println("e2e: remote-reusable-workflow")
  run_remote_reusable_workflow()
  println("e2e: remote-reusable-workflow ok")

  println("e2e: remote-reusable-local-action")
  run_remote_reusable_local_action()
  println("e2e: remote-reusable-local-action ok")

  println("e2e: remote-nested-reusable-workflow")
  run_remote_nested_reusable_workflow()
  println("e2e: remote-nested-reusable-workflow ok")

  println("e2e: trigger-skipped")
  run_trigger_skipped()
  println("e2e: trigger-skipped ok")

  println("e2e: file-commands")
  run_file_commands()
  println("e2e: file-commands ok")

  println("e2e: artifact-actions-roundtrip")
  run_artifact_actions_roundtrip()
  println("e2e: artifact-actions-roundtrip ok")

  println("e2e: artifact-actions-roundtrip-container")
  run_artifact_actions_roundtrip_container()
  println("e2e: artifact-actions-roundtrip-container ok")

  println("e2e: artifact-glob-directory")
  run_artifact_glob_directory()
  println("e2e: artifact-glob-directory ok")

  println("e2e: artifact-if-no-files-found")
  run_artifact_if_no_files_found()
  println("e2e: artifact-if-no-files-found ok")

  println("e2e: artifact-overwrite")
  run_artifact_overwrite()
  println("e2e: artifact-overwrite ok")

  println("e2e: artifact-merge-multiple")
  run_artifact_merge_multiple()
  println("e2e: artifact-merge-multiple ok")

  println("e2e: cache-actions-roundtrip")
  run_cache_actions_roundtrip()
  println("e2e: cache-actions-roundtrip ok")

  println("e2e: cache-auto-save-roundtrip")
  run_cache_auto_save_roundtrip()
  println("e2e: cache-auto-save-roundtrip ok")

  println("e2e: cache-auto-save-container")
  run_cache_auto_save_container()
  println("e2e: cache-auto-save-container ok")

  println("e2e: cache-restore-keys")
  run_cache_restore_keys()
  println("e2e: cache-restore-keys ok")

  println("e2e: cache-lookup-only")
  run_cache_lookup_only()
  println("e2e: cache-lookup-only ok")

  println("e2e: cache-fail-on-cache-miss")
  run_cache_fail_on_cache_miss()
  println("e2e: cache-fail-on-cache-miss ok")

  println("e2e: checkout-sparse-path")
  run_checkout_sparse_path()
  println("e2e: checkout-sparse-path ok")

  println("e2e: checkout-fetch-depth")
  run_checkout_fetch_depth()
  println("e2e: checkout-fetch-depth ok")

  println("e2e: checkout-ref")
  run_checkout_ref()
  println("e2e: checkout-ref ok")

  println("e2e: checkout-clean")
  run_checkout_clean()
  println("e2e: checkout-clean ok")

  println("e2e: checkout-submodules")
  run_checkout_submodules()
  println("e2e: checkout-submodules ok")

  println("e2e: checkout-container")
  run_checkout_container()
  println("e2e: checkout-container ok")

  println("e2e: setup-node-basic")
  run_setup_node_basic()
  println("e2e: setup-node-basic ok")

  println("e2e: setup-node-cache-npm")
  run_setup_node_cache_npm()
  println("e2e: setup-node-cache-npm ok")

  println("e2e: setup-node-container")
  run_setup_node_container()
  println("e2e: setup-node-container ok")

  println("e2e: expression-string-functions")
  run_expression_string_functions()
  println("e2e: expression-string-functions ok")

  println("e2e: expression-json-functions")
  run_expression_json_functions()
  println("e2e: expression-json-functions ok")

  println("e2e: expression-hash-files")
  run_expression_hash_files()
  println("e2e: expression-hash-files ok")

  println("e2e: expression-vars")
  run_expression_vars()
  println("e2e: expression-vars ok")

  println("e2e: expression-secrets")
  run_expression_secrets()
  println("e2e: expression-secrets ok")

  println("e2e: matrix-include-basic")
  run_matrix_include_basic()
  println("e2e: matrix-include-basic ok")

  println("e2e: matrix-exclude-basic")
  run_matrix_exclude_basic()
  println("e2e: matrix-exclude-basic ok")

  println("e2e: matrix-mixed-include-basic")
  run_matrix_mixed_include_basic()
  println("e2e: matrix-mixed-include-basic ok")

  println("e2e: matrix-max-parallel-basic")
  run_matrix_max_parallel_basic()
  println("e2e: matrix-max-parallel-basic ok")

  println("e2e: matrix-fail-fast-basic")
  run_matrix_fail_fast_basic()
  println("e2e: matrix-fail-fast-basic ok")

  println("e2e: matrix-needs-output-basic")
  run_matrix_needs_output_basic()
  println("e2e: matrix-needs-output-basic ok")

  println("e2e: job-failure-blocked")
  run_job_failure_blocked()
  println("e2e: job-failure-blocked ok")

  println("e2e: job-if-always")
  run_job_if_always()
  println("e2e: job-if-always ok")

  println("e2e: step-if-status-functions")
  run_step_if_status_functions()
  println("e2e: step-if-status-functions ok")

  println("e2e: step-continue-on-error-basic")
  run_step_continue_on_error_basic()
  println("e2e: step-continue-on-error-basic ok")

  println("e2e: step-status-context")
  run_step_status_context()
  println("e2e: step-status-context ok")

  println("e2e: unsupported-uses")
  run_unsupported_uses()
  println("e2e: unsupported-uses ok")

  println("e2e: unsupported-matrix")
  run_unsupported_matrix()
  println("e2e: unsupported-matrix ok")

  println("e2e: unsupported-permissions")
  run_unsupported_permissions()
  println("e2e: unsupported-permissions ok")

  println("e2e: unsupported-concurrency")
  run_unsupported_concurrency()
  println("e2e: unsupported-concurrency ok")

  println("e2e: unsupported-workflow-call")
  run_unsupported_workflow_call()
  println("e2e: unsupported-workflow-call ok")

  println("e2e: job-container-basic")
  run_job_container_basic()
  println("e2e: job-container-basic ok")

  println("e2e: job-container-node-action")
  run_job_container_node_action()
  println("e2e: job-container-node-action ok")

  println("e2e: job-container-docker-action")
  run_job_container_docker_action()
  println("e2e: job-container-docker-action ok")

  println("e2e: job-services-basic")
  run_job_services_basic()
  println("e2e: job-services-basic ok")

  println("e2e: job-services-container-network")
  run_job_services_container_network()
  println("e2e: job-services-container-network ok")

  println("e2e: event-cli-overrides")
  run_event_cli_overrides()
  println("e2e: event-cli-overrides ok")

  println("e2e: docker-image-basic")
  run_docker_image_basic()
  println("e2e: docker-image-basic ok")

  println("e2e: wasm-action-basic")
  run_wasm_action_basic()
  println("e2e: wasm-action-basic ok")

  println("e2e: custom-registry-node-action")
  run_custom_registry_node_action()
  println("e2e: custom-registry-node-action ok")

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

  println("e2e: substrate-parity")
  run_substrate_parity()
  println("e2e: substrate-parity ok")

  println("e2e: substrate-parity-repo")
  run_substrate_parity_repo_mode()
  println("e2e: substrate-parity-repo ok")

  println("e2e: secret-mask")
  run_secret_mask()
  println("e2e: secret-mask ok")

  println("e2e: checkout-fetch-tags")
  run_checkout_fetch_tags()
  println("e2e: checkout-fetch-tags ok")

  println("e2e: checkout-persist-credentials")
  run_checkout_persist_credentials()
  println("e2e: checkout-persist-credentials ok")

  println("e2e: shell-templates")
  run_shell_templates()
  println("e2e: shell-templates ok")

  println("e2e: all scenarios passed")
}

///|
#cfg(target="native")
async fn run_substrate_parity() -> Unit {
  let scenario = "substrate-parity"
  let fixture = e2e_fixture_dir(scenario)
  let workflow_rel = "workflow.yml"

  // Prepare a git repo workspace with the fixture workflow
  let workspace = e2e_prepare_dir("_build/e2e/workspaces", scenario)
  e2e_copy_tree(fixture, workspace)
  e2e_prepare_git_checkout_workspace(workspace)

  let modes : Array[(String, String)] = [
    ("local", "local"),
    ("worktree", "worktree"),
    ("tmp", "tmp"),
  ]

  let run_roots : Map[String, String] = {}
  let results : Map[String, E2eProcessResult] = {}

  for item in modes {
    let (mode, _label) = item
    let run_root = e2e_prepare_dir(
      "_build/e2e/workspaces",
      scenario + "-runs-" + mode,
    )
    run_roots[mode] = run_root
    let result = e2e_run_cli([
      "workflow",
      "run",
      e2e_join_path(workspace, workflow_rel),
      "--workspace-mode",
      mode,
      "--run-root",
      run_root,
    ])
    e2e_expect_ok(result, scenario + " " + mode)
    e2e_expect_contains(
      result.stdout,
      "state=completed",
      scenario + " " + mode + " state",
    )
    results[mode] = result
  }

  // Step reports must match across all modes
  for item in modes {
    let (mode, _label) = item
    let result = results[mode]
    e2e_expect_contains(
      result.stdout,
      "build/write: success",
      scenario + " " + mode + " write",
    )
    e2e_expect_contains(
      result.stdout,
      "build/read: success",
      scenario + " " + mode + " read",
    )
    e2e_expect_contains(
      result.stdout,
      "build/upload: success",
      scenario + " " + mode + " upload",
    )
    e2e_expect_contains(
      result.stdout,
      "build/cache: success",
      scenario + " " + mode + " cache",
    )
  }

  // Verify run records, artifacts, caches, logs, summary for each mode
  for item in modes {
    let (mode, _label) = item
    let run_root = run_roots[mode]

    // run view --json includes correct workspace_mode
    let view = e2e_run_cli([
      "run", "view", "run-1", "--run-root", run_root, "--json",
    ])
    e2e_expect_ok(view, scenario + " " + mode + " view")
    e2e_expect_contains(
      view.stdout,
      "\"workspace_mode\": \"" + mode + "\"",
      scenario + " " + mode + " mode",
    )

    // artifacts recorded in run
    e2e_expect_contains(
      view.stdout,
      "\"name\": \"parity-report\"",
      scenario + " " + mode + " artifact name",
    )
    e2e_expect_contains(
      view.stdout,
      "\"files\": [\"result.txt\"]",
      scenario + " " + mode + " artifact files",
    )

    // caches recorded in run
    e2e_expect_contains(
      view.stdout,
      "\"key\": \"substrate-parity-key\"",
      scenario + " " + mode + " cache key",
    )

    // artifact list
    let artifact_list = e2e_run_cli([
      "artifact", "list", "run-1", "--run-root", run_root, "--json",
    ])
    e2e_expect_ok(artifact_list, scenario + " " + mode + " artifact list")
    e2e_expect_contains(
      artifact_list.stdout,
      "\"name\": \"parity-report\"",
      scenario + " " + mode + " artifact list name",
    )

    // run logs with summary
    let logs = e2e_run_cli([
      "run", "logs", "run-1", "--run-root", run_root, "--task", "build/read",
    ])
    e2e_expect_ok(logs, scenario + " " + mode + " logs")
    e2e_expect_contains(
      logs.stdout,
      "hello-from-step|from-env-file",
      scenario + " " + mode + " logs stdout",
    )
    e2e_expect_contains(
      logs.stdout,
      "substrate-summary",
      scenario + " " + mode + " logs summary",
    )
  }

  // Verify artifact download produces identical content across modes
  for item in modes {
    let (mode, _label) = item
    let run_root = run_roots[mode]
    let download_dir = e2e_prepare_dir(
      "_build/e2e/workspaces",
      scenario + "-dl-" + mode,
    )
    let dl = e2e_run_cli([
      "artifact", "download", "run-1", "--name", "parity-report", "--run-root", run_root,
      "--dir", download_dir,
    ])
    e2e_expect_ok(dl, scenario + " " + mode + " artifact download")
    e2e_expect_eq(
      e2e_read_text(e2e_join_path(download_dir, "result.txt")),
      "hello-from-step",
      scenario + " " + mode + " artifact content",
    )
  }
}

///|
#cfg(target="native")
async fn run_substrate_parity_repo_mode() -> Unit {
  let scenario = "substrate-parity-repo"
  let fixture = e2e_fixture_dir("substrate-parity")

  // Prepare a git repo with the fixture content
  let repo_root = e2e_prepare_dir("_build/e2e/workspaces", scenario + "-repo")
  e2e_ensure_dir(e2e_join_path(repo_root, ".github"))
  e2e_ensure_dir(e2e_join_path(repo_root, ".github/workflows"))
  e2e_copy_tree(
    e2e_join_path(fixture, "workflow.yml"),
    e2e_join_path(repo_root, ".github/workflows/ci.yml"),
  )
  e2e_prepare_git_checkout_workspace(repo_root)

  let run_root = e2e_prepare_dir("_build/e2e/workspaces", scenario + "-runs")

  // Run in repo mode (default workspace-mode=tmp)
  let result = e2e_run_cli([
    "workflow", "run", ".github/workflows/ci.yml", "--repo", repo_root, "--run-root",
    run_root, "--repository", "test/substrate-parity",
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario + " state")
  e2e_expect_contains(
    result.stdout,
    "build/write: success",
    scenario + " write",
  )
  e2e_expect_contains(result.stdout, "build/read: success", scenario + " read")
  e2e_expect_contains(
    result.stdout,
    "build/upload: success",
    scenario + " upload",
  )

  // Verify run record
  let view = e2e_run_cli([
    "run", "view", "run-1", "--run-root", run_root, "--json",
  ])
  e2e_expect_ok(view, scenario + " view")
  e2e_expect_contains(
    view.stdout,
    "\"workspace_mode\": \"tmp\"",
    scenario + " mode",
  )
  e2e_expect_contains(
    view.stdout,
    "\"name\": \"parity-report\"",
    scenario + " artifact",
  )

  // Verify logs
  let logs = e2e_run_cli([
    "run", "logs", "run-1", "--run-root", run_root, "--task", "build/read",
  ])
  e2e_expect_ok(logs, scenario + " logs")
  e2e_expect_contains(
    logs.stdout,
    "hello-from-step|from-env-file",
    scenario + " logs stdout",
  )

  // Verify artifact download
  let download_dir = e2e_prepare_dir("_build/e2e/workspaces", scenario + "-dl")
  let dl = e2e_run_cli([
    "artifact", "download", "run-1", "--name", "parity-report", "--run-root", run_root,
    "--dir", download_dir,
  ])
  e2e_expect_ok(dl, scenario + " artifact download")
  e2e_expect_eq(
    e2e_read_text(e2e_join_path(download_dir, "result.txt")),
    "hello-from-step",
    scenario + " artifact content",
  )
}

///|
#cfg(target="native")
async fn run_shell_templates() -> Unit {
  let scenario = "shell-templates"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  let result = e2e_run_cli([
    "workflow",
    "run",
    e2e_join_path(workspace, "workflow.yml"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(
    result.stdout,
    "build/bash-default: success",
    scenario + " bash default",
  )
  e2e_expect_contains(
    result.stdout,
    "build/bash-explicit: success",
    scenario + " bash explicit",
  )
  e2e_expect_contains(result.stdout, "build/sh: success", scenario + " sh")
  e2e_expect_contains(
    result.stdout,
    "build/custom-template: success",
    scenario + " custom template",
  )
}

///|
#cfg(target="native")
async fn run_secret_mask() -> Unit {
  let scenario = "secret-mask"
  let fixture = e2e_fixture_dir(scenario)
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces", scenario, fixture,
  )
  let run_root = e2e_prepare_dir("_build/e2e/workspaces", scenario + "-runs")
  let secret_value = "super-secret-token-42"
  let result = e2e_run_cli(
    [
      "workflow",
      "run",
      e2e_join_path(workspace, "workflow.yml"),
      "--run-root",
      run_root,
    ],
    env={ "ACTION_RUNNER_SECRET_CALL_TOKEN": secret_value },
  )
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario + " state")

  // stdout must not contain the secret value
  e2e_expect_not_contains(
    result.stdout,
    secret_value,
    scenario + " stdout leak",
  )

  // run view --json must not contain the secret value
  let view = e2e_run_cli([
    "run", "view", "run-1", "--run-root", run_root, "--json",
  ])
  e2e_expect_ok(view, scenario + " view")
  e2e_expect_not_contains(view.stdout, secret_value, scenario + " view leak")

  // run logs must not contain the secret value
  let logs = e2e_run_cli([
    "run", "logs", "run-1", "--run-root", run_root, "--task", "build/leak",
  ])
  e2e_expect_ok(logs, scenario + " logs")
  e2e_expect_not_contains(logs.stdout, secret_value, scenario + " logs leak")
  // masked value should appear as ***
  e2e_expect_contains(logs.stdout, "***", scenario + " logs masked")

  // ::add-mask:: dynamic masking: "dynamic-secret-value" must be masked
  let add_mask_logs = e2e_run_cli([
    "run", "logs", "run-1", "--run-root", run_root, "--task", "build/add-mask",
  ])
  e2e_expect_ok(add_mask_logs, scenario + " add-mask logs")
  e2e_expect_not_contains(
    add_mask_logs.stdout,
    "dynamic-secret-value",
    scenario + " add-mask value leak",
  )
  // The ::add-mask:: line itself should be stripped
  e2e_expect_not_contains(
    add_mask_logs.stdout,
    "::add-mask::",
    scenario + " add-mask command leak",
  )
  // The masked output should contain ***
  e2e_expect_contains(
    add_mask_logs.stdout,
    "before-***-after",
    scenario + " add-mask replaced",
  )
}

///|
#cfg(target="native")
async fn run_checkout_fetch_tags() -> Unit {
  let scenario = "checkout-fetch-tags"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  e2e_prepare_git_checkout_workspace(workspace)
  // Create a tag in the repo
  e2e_require_ok("git tag", "git", ["tag", "v1.0.0"], workspace)
  let result = e2e_run_cli([
    "workflow",
    "run",
    e2e_join_path(workspace, "workflow.yml"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/verify: success", scenario)
  // with-tags should have at least 1 tag
  let with_tags = e2e_read_text(
    e2e_join_path(workspace, "artifacts/with-tags.txt"),
  )
  // without-tags should have 0 tags
  let without_tags = e2e_read_text(
    e2e_join_path(workspace, "artifacts/without-tags.txt"),
  )
  e2e_expect_eq(with_tags, "1", scenario + " with-tags count")
  e2e_expect_eq(without_tags, "0", scenario + " without-tags count")
}

///|
#cfg(target="native")
async fn run_checkout_persist_credentials() -> Unit {
  let scenario = "checkout-persist-credentials"
  let workspace = e2e_prepare_copied_dir(
    "_build/e2e/workspaces",
    scenario,
    e2e_fixture_dir(scenario),
  )
  e2e_prepare_git_checkout_workspace(workspace)
  let result = e2e_run_cli([
    "workflow",
    "run",
    e2e_join_path(workspace, "workflow.yml"),
  ])
  e2e_expect_ok(result, scenario)
  e2e_expect_contains(result.stdout, "state=completed", scenario)
  e2e_expect_contains(result.stdout, "build/verify: success", scenario)
  let cred = e2e_read_text(e2e_join_path(workspace, "artifacts/credential.txt"))
  e2e_expect_eq(cred, "none", scenario + " no credential helper")
}

///|
#cfg(not(target="native"))
fn main {
  println("action_runner e2e harness is supported on native target only")
}
