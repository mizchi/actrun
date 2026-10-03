///|
fn act_nonempty_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for line_view in text.split("\n") {
    let line = compat_trim_cr(line_view.to_owned())
    if line.length() > 0 {
      lines.push(line)
    }
  }
  lines
}

///|
#cfg(target="native")
async test "compat act: set env uses a new env file per step" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "set-env-new-env-file-per-step",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let initial = compat_expect_task_report(report, "check/show_initial")
  let test2 = compat_expect_task_report(report, "check/show_test2")
  let returned = compat_expect_task_report(report, "check/show_returnedenv")
  let env_paths = act_nonempty_lines(
    @xfs.read_file_to_string(workspace + "/env_paths.txt"),
  )

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"act-set-env-new-env-file-per-step"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"supported"
    ),
  )
  @debug.debug_inspect(report.ok, content="true")
  @debug.debug_inspect(
    initial.stdout,
    content=(
      #|"<test>"
    ),
  )
  @debug.debug_inspect(
    test2.stdout,
    content=(
      #|"<test2>"
    ),
  )
  @debug.debug_inspect(
    returned.stdout,
    content=(
      #|"<returnedenv>"
    ),
  )
  @debug.debug_inspect(env_paths.length(), content="5")
  @debug.debug_inspect(env_paths[0] == env_paths[1], content="false")
  @debug.debug_inspect(env_paths[1] == env_paths[2], content="false")
  @debug.debug_inspect(env_paths[2] == env_paths[3], content="false")
  @debug.debug_inspect(env_paths[3] == env_paths[4], content="false")
}

///|
#cfg(target="native")
async test "compat act: step env override is visible inside local composite action" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "set-env-step-env-override",
    copy_fixture=true,
  )
  let lowered = @actrun.lower_push_workflow_in_workspace(workflow, workspace)
  let report = @actrun.execute_lowered_native(lowered, workspace_root=workspace)
  let before = compat_expect_task_report(report, "check/before")
  let after = compat_expect_task_report(report, "check/after")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"act-set-env-step-env-override"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"supported"
    ),
  )
  @debug.debug_inspect(lowered.errors, content="[]")
  @debug.debug_inspect(report.ok, content="true")
  @debug.debug_inspect(
    before.stdout,
    content=(
      #|"<test>"
    ),
  )
  @debug.debug_inspect(
    after.stdout,
    content=(
      #|"<returnedenv>"
    ),
  )
  @debug.debug_inspect(
    @xfs.read_file_to_string(workspace + "/inner.txt"),
    content=(
      #|"<val>"
    ),
  )
}

///|
#cfg(target="native")
async test "compat act: steps context outcome is supported" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "steps-context-outcome",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let second = compat_expect_task_report(report, "check/second")
  let third = compat_expect_task_report(report, "check/step_3")
  let fourth = compat_expect_task_report(report, "check/step_4")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"act-steps-context-outcome"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"supported"
    ),
  )
  @debug.debug_inspect(report.ok, content="true")
  @debug.debug_inspect(
    report.state,
    content=(
      #|"completed"
    ),
  )
  @debug.debug_inspect(
    second.status,
    content=(
      #|"failed"
    ),
  )
  @debug.debug_inspect(
    third.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(
    fourth.status,
    content=(
      #|"success"
    ),
  )
}

///|
#cfg(target="native")
async test "compat act: steps context conclusion is supported" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "steps-context-conclusion",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let second = compat_expect_task_report(report, "check/second")
  let third = compat_expect_task_report(report, "check/step_3")
  let fourth = compat_expect_task_report(report, "check/step_4")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"act-steps-context-conclusion"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"supported"
    ),
  )
  @debug.debug_inspect(report.ok, content="true")
  @debug.debug_inspect(
    report.state,
    content=(
      #|"completed"
    ),
  )
  @debug.debug_inspect(
    second.status,
    content=(
      #|"failed"
    ),
  )
  @debug.debug_inspect(
    third.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(
    fourth.status,
    content=(
      #|"success"
    ),
  )
}

///|
#cfg(target="native")
async test "compat act: step summary is collected from file command" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "stepsummary",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "create_summary/write_summary")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"act-stepsummary"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"supported"
    ),
  )
  @debug.debug_inspect(report.ok, content="true")
  @debug.debug_inspect(
    task.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(
    task.summary,
    content=(
      #|"summary\n"
    ),
  )
}

///|
#cfg(target="native")
async test "compat act: bash shell fixture works on host runner" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "shells-bash",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let explicit = compat_expect_task_report(report, "check/step_1")
  let defaulted = compat_expect_task_report(report, "check-job-default/step_1")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"act-shells-bash"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"supported"
    ),
  )
  @debug.debug_inspect(report.ok, content="true")
  @debug.debug_inspect(
    explicit.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(explicit.stdout.contains("I'm "), content="true")
  @debug.debug_inspect(
    defaulted.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(defaulted.stdout.contains("I'm "), content="true")
}

///|
#cfg(target="native")
async test "compat act: sh shell fixture works on host runner" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "shells-sh",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let explicit = compat_expect_task_report(report, "check/step_1")
  let defaulted = compat_expect_task_report(report, "check-job-default/step_1")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"act-shells-sh"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"supported"
    ),
  )
  @debug.debug_inspect(report.ok, content="true")
  @debug.debug_inspect(
    explicit.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(
    explicit.stdout,
    content=(
      #|"sh-ok\n"
    ),
  )
  @debug.debug_inspect(
    defaulted.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(
    defaulted.stdout,
    content=(
      #|"sh-ok\n"
    ),
  )
}

///|
#cfg(target="native")
async test "compat act: default runner shell is bash" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "shells-defaults",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "check/step_1")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"act-shells-defaults"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"supported"
    ),
  )
  @debug.debug_inspect(report.ok, content="true")
  @debug.debug_inspect(
    task.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(task.stdout.contains("I'm "), content="true")
}

///|
#cfg(target="native")
async test "compat act: custom templated shell is a known diff" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "shells-custom",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "check/step_1")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"act-shells-custom"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"known_diff"
    ),
  )
  // pwsh availability varies by environment; accept either outcome
  assert_true(task.status == "failed" || task.status == "success")
}
