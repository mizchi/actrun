///|
fn act_nonempty_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for line_view in text.split("\n") {
    let line = compat_trim_cr(line_view.to_string())
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
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let initial = compat_expect_task_report(report, "check/show_initial")
  let test2 = compat_expect_task_report(report, "check/show_test2")
  let returned = compat_expect_task_report(report, "check/show_returnedenv")
  let env_paths = act_nonempty_lines(
    @xfs.read_file_to_string(workspace + "/env_paths.txt"),
  )

  inspect(fixture.id, content="act-set-env-new-env-file-per-step")
  inspect(fixture.mode, content="supported")
  inspect(report.ok, content="true")
  inspect(initial.stdout, content="<test>")
  inspect(test2.stdout, content="<test2>")
  inspect(returned.stdout, content="<returnedenv>")
  inspect(env_paths.length(), content="5")
  inspect(env_paths[0] == env_paths[1], content="false")
  inspect(env_paths[1] == env_paths[2], content="false")
  inspect(env_paths[2] == env_paths[3], content="false")
  inspect(env_paths[3] == env_paths[4], content="false")
}

///|
#cfg(target="native")
async test "compat act: step env override is visible inside local composite action" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "set-env-step-env-override",
    copy_fixture=true,
  )
  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  let report = execute_lowered_native(lowered, workspace_root=workspace)
  let before = compat_expect_task_report(report, "check/before")
  let after = compat_expect_task_report(report, "check/after")

  inspect(fixture.id, content="act-set-env-step-env-override")
  inspect(fixture.mode, content="supported")
  inspect(lowered.errors, content="[]")
  inspect(report.ok, content="true")
  inspect(before.stdout, content="<test>")
  inspect(after.stdout, content="<returnedenv>")
  inspect(@xfs.read_file_to_string(workspace + "/inner.txt"), content="<val>")
}

///|
#cfg(target="native")
async test "compat act: steps context outcome is supported" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "steps-context-outcome",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let second = compat_expect_task_report(report, "check/second")
  let third = compat_expect_task_report(report, "check/step_3")
  let fourth = compat_expect_task_report(report, "check/step_4")

  inspect(fixture.id, content="act-steps-context-outcome")
  inspect(fixture.mode, content="supported")
  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(second.status, content="failed")
  inspect(third.status, content="success")
  inspect(fourth.status, content="success")
}

///|
#cfg(target="native")
async test "compat act: steps context conclusion is supported" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "steps-context-conclusion",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let second = compat_expect_task_report(report, "check/second")
  let third = compat_expect_task_report(report, "check/step_3")
  let fourth = compat_expect_task_report(report, "check/step_4")

  inspect(fixture.id, content="act-steps-context-conclusion")
  inspect(fixture.mode, content="supported")
  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(second.status, content="failed")
  inspect(third.status, content="success")
  inspect(fourth.status, content="success")
}

///|
#cfg(target="native")
async test "compat act: step summary is collected from file command" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "stepsummary",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "create_summary/write_summary")

  inspect(fixture.id, content="act-stepsummary")
  inspect(fixture.mode, content="supported")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.summary, content="summary\n")
}

///|
#cfg(target="native")
async test "compat act: bash shell fixture works on host runner" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "shells-bash",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let explicit = compat_expect_task_report(report, "check/step_1")
  let defaulted = compat_expect_task_report(report, "check-job-default/step_1")

  inspect(fixture.id, content="act-shells-bash")
  inspect(fixture.mode, content="supported")
  inspect(report.ok, content="true")
  inspect(explicit.status, content="success")
  inspect(explicit.stdout.contains("I'm "), content="true")
  inspect(defaulted.status, content="success")
  inspect(defaulted.stdout.contains("I'm "), content="true")
}

///|
#cfg(target="native")
async test "compat act: sh shell fixture works on host runner" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "shells-sh",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let explicit = compat_expect_task_report(report, "check/step_1")
  let defaulted = compat_expect_task_report(report, "check-job-default/step_1")

  inspect(fixture.id, content="act-shells-sh")
  inspect(fixture.mode, content="supported")
  inspect(report.ok, content="true")
  inspect(explicit.status, content="success")
  inspect(explicit.stdout, content="sh-ok\n")
  inspect(defaulted.status, content="success")
  inspect(defaulted.stdout, content="sh-ok\n")
}

///|
#cfg(target="native")
async test "compat act: default runner shell is bash" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "shells-defaults",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "check/step_1")

  inspect(fixture.id, content="act-shells-defaults")
  inspect(fixture.mode, content="supported")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout.contains("I'm "), content="true")
}

///|
#cfg(target="native")
async test "compat act: custom templated shell is a known diff" {
  let (fixture, workflow, workspace) = compat_prepare_act_fixture_auto(
    "shells-custom",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "check/step_1")

  inspect(fixture.id, content="act-shells-custom")
  inspect(fixture.mode, content="known_diff")
  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  inspect(task.status, content="failed")
}
