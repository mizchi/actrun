///|
fn test_support_ensure_dir(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
fn test_support_absolute_path(path : String) -> String {
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
#cfg(target="native")
async fn test_support_make_executable(path : String) -> Unit {
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
async fn test_support_remove_tree(path : String) -> Unit {
  if not(@xfs.path_exists(path)) {
    return
  }
  let (code, _, stderr) = @process.collect_output("rm", ["-rf", path], cwd=".")
  if code != 0 {
    abort("rm failed: " + stderr.text())
  }
}

///|
#cfg(target="native")
async fn test_support_prepare_fake_github_git_bin(
  workspace : String,
  action_src : String,
  log_path : String,
) -> String {
  let bin_dir = workspace + "/bin"
  test_support_ensure_dir(bin_dir)
  let git_path = bin_dir + "/git"
  let absolute_log_path = test_support_absolute_path(log_path)
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
  test_support_make_executable(git_path)
  test_support_absolute_path(git_path)
}

///|
#cfg(target="native")
async fn test_support_prepare_fake_node_bin(
  workspace : String,
  log_path : String,
) -> String {
  let bin_dir = workspace + "/bin"
  test_support_ensure_dir(bin_dir)
  let node_path = bin_dir + "/node"
  let absolute_log_path = test_support_absolute_path(log_path)
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
  test_support_make_executable(node_path)
  test_support_absolute_path(node_path)
}

///|
#cfg(target="native")
async fn test_support_prepare_fake_docker_bin(
  workspace : String,
  log_path : String,
) -> String {
  let bin_dir = workspace + "/bin"
  test_support_ensure_dir(bin_dir)
  let docker_path = bin_dir + "/docker"
  let absolute_log_path = test_support_absolute_path(log_path)
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
  test_support_make_executable(docker_path)
  test_support_absolute_path(docker_path)
}
