///|
fn ensure_runner_context_dir(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
fn runner_context_absolute_path(path : String) -> String {
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
fn prepare_runner_context_workspace(name : String) -> String raise {
  ensure_runner_context_dir("_build")
  ensure_runner_context_dir("_build/test-runner-context-workspaces")
  let workspace = "_build/test-runner-context-workspaces/" + name
  ensure_runner_context_dir(workspace)
  runner_context_absolute_path(workspace)
}

///|
#cfg(target="native")
async test "executor: injects runner env variables" {
  let workspace = prepare_runner_context_workspace("executor-runner-env")
  let script =
    #|if [ -n "$RUNNER_OS" ] &&
    #|   [ -n "$RUNNER_ARCH" ] &&
    #|   [ -n "$RUNNER_TEMP" ] &&
    #|   [ -d "$RUNNER_TEMP" ] &&
    #|   [ "$RUNNER_ENVIRONMENT" = "self-hosted" ]; then
    #|  printf '<ok>'
    #|else
    #|  printf '<%s|%s|%s|%s>' "$RUNNER_OS" "$RUNNER_ARCH" "$RUNNER_TEMP" "$RUNNER_ENVIRONMENT"
    #|  exit 1
    #|fi

  let workflow = new_workflow("ci", [
    new_job("build", [new_run_step("env", script, shell=Some("bash"))]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = find_task_run_report(report, "build/env").unwrap()

  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<ok>")
}
