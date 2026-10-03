///|
test "compat languageservices: parse events-single fixture" {
  let (fixture, workflow) = compat_expect_languageservices_fixture(
    "events-single",
  )

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-events-single"
    ),
  )
  @debug.debug_inspect(workflow.jobs.length(), content="1")
  @debug.debug_inspect(
    workflow.jobs[0].id,
    content=(
      #|"build"
    ),
  )
  @debug.debug_inspect(
    workflow.jobs[0].steps[0].uses.unwrap_or(""),
    content=(
      #|"actions/checkout@v3"
    ),
  )
  @debug.debug_inspect(
    workflow.jobs[0].steps[1].run.unwrap_or(""),
    content=(
      #|"echo hi"
    ),
  )
}

///|
test "compat languageservices: parse workflow env fixture" {
  let (fixture, workflow) = compat_expect_languageservices_fixture(
    "workflow-env",
  )

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-workflow-env"
    ),
  )
  @debug.debug_inspect(
    workflow.env.get("root-env").unwrap_or(""),
    content=(
      #|"root env value"
    ),
  )
  @debug.debug_inspect(
    workflow.jobs[0].env.get("job-env").unwrap_or(""),
    content=(
      #|"job env value"
    ),
  )
  @debug.debug_inspect(
    workflow.jobs[0].steps[0].env.get("step-env").unwrap_or(""),
    content=(
      #|"step env value"
    ),
  )
}

///|
test "compat languageservices: lower workflow defaults fixture" {
  let (fixture, _, lowered) = compat_expect_lowered_languageservices_fixture(
    "workflow-defaults",
  )
  let plan = compat_expect_task_plan(lowered.plan, "one/step_1")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-workflow-defaults"
    ),
  )
  @debug.debug_inspect(lowered.errors, content="[]")
  @debug.debug_inspect(
    plan.shell,
    content=(
      #|"cmd"
    ),
  )
  @debug.debug_inspect(
    plan.working_directory,
    content=(
      #|"foo"
    ),
  )
}

///|
test "compat languageservices: lower job needs fixture" {
  let (fixture, _, lowered) = compat_expect_lowered_languageservices_fixture(
    "job-needs",
  )
  let task = flow_task_by_id(lowered.ir, "deploy/step_1")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-job-needs"
    ),
  )
  @debug.debug_inspect(lowered.errors, content="[]")
  @debug.debug_inspect(
    task.needs,
    content="[\"test-level-0/__finish\", \"test-level-1/__finish\"]",
  )
}

///|
test "compat languageservices: parse step id fixture" {
  let (fixture, workflow) = compat_expect_languageservices_fixture("step-id")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-step-id"
    ),
  )
  @debug.debug_inspect(
    workflow.jobs[0].steps[0].id,
    content=(
      #|"action-step-id"
    ),
  )
  @debug.debug_inspect(
    workflow.jobs[0].steps[1].id,
    content=(
      #|"run-step-id"
    ),
  )
}

///|
test "compat languageservices: lower step run missing fixture" {
  let (fixture, _, lowered) = compat_expect_lowered_languageservices_fixture(
    "errors-step-run-missing",
  )

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-errors-step-run-missing"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"supported"
    ),
  )
  @debug.debug_inspect(
    lowered.errors,
    content="[\"step 'build/step_1' must define run\"]",
  )
}

///|
test "compat languageservices: step uses missing is a known diff" {
  let (fixture, _, lowered) = compat_expect_lowered_languageservices_fixture(
    "errors-step-uses-missing",
  )

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-errors-step-uses-missing"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"known_diff"
    ),
  )
  @debug.debug_inspect(
    lowered.errors,
    content="[\"step 'build/step_1' must define run\"]",
  )
}

///|
test "compat languageservices: step uses syntax is a known diff" {
  let (fixture, _, lowered) = compat_expect_lowered_languageservices_fixture(
    "errors-step-uses-syntax",
  )

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-errors-step-uses-syntax"
    ),
  )
  @debug.debug_inspect(
    fixture.mode,
    content=(
      #|"known_diff"
    ),
  )
  @debug.debug_inspect(
    lowered.errors,
    content=(
      #|[
      #|  "step 'build/step_2' action 'actions/aws/ec2@main' is not supported in MVP",
      #|  "step 'build/step_3' local action './.github/actions/my-action' requires workspace-aware lowering",
      #|  "step 'build/step_4' action '$$docker://alpine:3.8' is not supported in MVP",
      #|  "step 'build/step_5' action '...docker://alpine:3.8' is not supported in MVP",
      #|  "step 'build/step_6' action ref 'badrepo@invalid' must be owner/repo@ref, docker://image, ./path, or scheme://name@version",
      #|  "step 'build/step_7' action ref 'docker://' must include an image name",
      #|]
    ),
  )
}

///|
#cfg(target="native")
async test "compat languageservices: expression env exact property fixture" {
  let (fixture, workflow, workspace) = compat_prepare_languageservices_fixture_auto(
    "expr-env-basic",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/show")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-expr-env-basic"
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
    task.stdout,
    content=(
      #|"<baz>"
    ),
  )
}

///|
#cfg(target="native")
async test "compat languageservices: expression env property is case-insensitive" {
  let (fixture, workflow, workspace) = compat_prepare_languageservices_fixture_auto(
    "expr-env-case-insensitive",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/show")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-expr-env-case-insensitive"
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
    task.stdout,
    content=(
      #|"<baz>"
    ),
  )
}

///|
#cfg(target="native")
async test "compat languageservices: expression step output exact property fixture" {
  let (fixture, workflow, workspace) = compat_prepare_languageservices_fixture_auto(
    "expr-step-output-basic",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/consume")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-expr-step-output-basic"
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
    task.stdout,
    content=(
      #|"<baz>"
    ),
  )
}

///|
#cfg(target="native")
async test "compat languageservices: expression step output property is case-insensitive" {
  let (fixture, workflow, workspace) = compat_prepare_languageservices_fixture_auto(
    "expr-step-output-case-insensitive",
  )
  let report = @actrun.execute_lowered_native(
    @actrun.lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/consume")

  @debug.debug_inspect(
    fixture.id,
    content=(
      #|"languageservices-expr-step-output-case-insensitive"
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
    task.stdout,
    content=(
      #|"<baz>"
    ),
  )
}
