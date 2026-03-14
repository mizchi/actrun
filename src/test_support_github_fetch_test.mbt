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
async fn test_support_prepare_fake_git_bin_from_source(
  workspace : String,
  source_dir : String,
  log_path : String,
) -> String {
  let bin_dir = workspace + "/bin"
  test_support_ensure_dir(bin_dir)
  let git_path = bin_dir + "/git"
  let absolute_log_path = test_support_absolute_path(log_path)
  let absolute_source_dir = test_support_absolute_path(source_dir)
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
async fn test_support_prepare_fake_version_node_bin(
  workspace : String,
  log_path : String,
  version : String,
) -> String {
  let bin_dir = workspace + "/bin"
  test_support_ensure_dir(bin_dir)
  let node_path = bin_dir + "/node"
  let absolute_log_path = test_support_absolute_path(log_path)
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
  test_support_make_executable(node_path)
  test_support_absolute_path(node_path)
}

///|
#cfg(target="native")
async fn test_support_prepare_fake_wasm_bin(
  workspace : String,
  log_path : String,
) -> String {
  let bin_dir = workspace + "/bin"
  test_support_ensure_dir(bin_dir)
  let wasm_path = bin_dir + "/wasm-runner"
  let absolute_log_path = test_support_absolute_path(log_path)
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
  test_support_make_executable(wasm_path)
  test_support_absolute_path(wasm_path)
}

///|
#cfg(target="native")
async fn test_support_prepare_fake_docker_bin(
  workspace : String,
  log_path : String,
  inspect_sequence? : String = "healthy",
) -> String {
  let bin_dir = workspace + "/bin"
  test_support_ensure_dir(bin_dir)
  let docker_path = bin_dir + "/docker"
  let absolute_log_path = test_support_absolute_path(log_path)
  let inspect_count_path = test_support_absolute_path(
    log_path + ".inspect-count",
  )
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
    "  sequence=\"${ACTRUN_FAKE_DOCKER_INSPECT_SEQUENCE:-" +
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
  test_support_make_executable(docker_path)
  test_support_absolute_path(docker_path)
}
