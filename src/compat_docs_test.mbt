///|

///|
fn compat_docs_cache_store_root(workspace : String) -> String {
  let cwd = @xsys.get_env_var("PWD").unwrap_or(".")
  let absolute_workspace = if workspace.has_prefix("/") {
    workspace
  } else if cwd.has_suffix("/") {
    cwd + workspace
  } else {
    cwd + "/" + workspace
  }
  let workspace_key = absolute_workspace
    .replace_all(old="/", new="__")
    .replace_all(old=":", new="_")
  if cwd.has_suffix("/") {
    cwd + "_build/action_runner/cache/" + workspace_key
  } else {
    cwd + "/_build/action_runner/cache/" + workspace_key
  }
}

///|
fn compat_docs_set_env_var(key : String, value : String) -> String? {
  let previous = @xsys.get_env_var(key)
  @xsys.set_env_var(key, value)
  previous
}

///|
fn compat_docs_restore_env_var(key : String, previous : String?) -> Unit {
  match previous {
    Some(value) => @xsys.set_env_var(key, value)
    None => @xsys.unset_env_var(key)
  }
}

///|
test "compat docs: parse push scalar fixture" {
  let (fixture, workflow) = compat_expect_docs_fixture("push-scalar")

  inspect(fixture.id, content="docs-push-scalar")
  inspect(workflow.name, content="ci")
  inspect(workflow.jobs.length(), content="1")
  inspect(workflow.jobs[0].id, content="build")
  inspect(workflow.jobs[0].steps.length(), content="1")
}

///|
test "compat docs: parse push array fixture" {
  let (fixture, workflow) = compat_expect_docs_fixture("push-array")

  inspect(fixture.id, content="docs-push-array")
  inspect(workflow.name, content="ci-array")
  inspect(workflow.jobs.length(), content="1")
  inspect(workflow.jobs[0].steps[0].run.unwrap_or(""), content="echo array")
  inspect(workflow.trigger.branches, content="[]")
  inspect(workflow.trigger.paths, content="[]")
}

///|
test "compat docs: parse push object fixture" {
  let (fixture, workflow) = compat_expect_docs_fixture("push-object")

  inspect(fixture.id, content="docs-push-object")
  inspect(workflow.name, content="ci-object")
  inspect(workflow.trigger.branches, content="[\"main\", \"release/*\"]")
  inspect(workflow.trigger.paths, content="[\"src/**\", \"package.json\"]")
  inspect(workflow.jobs.length(), content="1")
  inspect(workflow.jobs[0].steps[0].id, content="test")
}

///|
test "compat docs: lower env precedence fixture" {
  let (fixture, _, lowered) = compat_expect_lowered_docs_fixture(
    "env-precedence",
  )
  let plan = compat_expect_task_plan(lowered.plan, "build/print")

  inspect(fixture.id, content="docs-env-precedence")
  inspect(lowered.errors, content="[]")
  inspect(plan.env.get("GLOBAL").unwrap_or(""), content="workflow")
  inspect(plan.env.get("SHARED").unwrap_or(""), content="step")
  inspect(plan.env.get("JOB_ONLY").unwrap_or(""), content="job")
  inspect(plan.env.get("STEP_ONLY").unwrap_or(""), content="step")
}

///|
test "compat docs: lower defaults.run fixture" {
  let (fixture, _, lowered) = compat_expect_lowered_docs_fixture("defaults-run")
  let default_task = compat_expect_task_plan(
    lowered.plan,
    "build/from_job_default",
  )
  let override_task = compat_expect_task_plan(
    lowered.plan,
    "build/from_step_override",
  )

  inspect(fixture.id, content="docs-defaults-run")
  inspect(lowered.errors, content="[]")
  inspect(default_task.shell, content="bash")
  inspect(default_task.working_directory, content="packages/app")
  inspect(override_task.shell, content="sh")
  inspect(override_task.working_directory, content="scripts")
}

///|
test "compat docs: lower jobs if fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "jobs-if-repository",
  )

  inspect(fixture.id, content="docs-jobs-if-repository")
  inspect(
    workflow.jobs[0].if_condition,
    content="github.repository == 'mizchi/action_runner'",
  )
  inspect(lowered.errors, content="[]")
  inspect(
    lowered.plan.job_if_conditions.get("build").unwrap_or(""),
    content="github.repository == 'mizchi/action_runner'",
  )
}

///|
test "compat docs: parse and reject permissions fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "permissions-parse",
  )

  inspect(fixture.id, content="docs-permissions-parse")
  inspect(
    workflow.permissions.unwrap().values.get("_").unwrap_or(""),
    content="read-all",
  )
  inspect(
    workflow.jobs[0].permissions.unwrap().values.get("contents").unwrap_or(""),
    content="read",
  )
  inspect(
    lowered.errors,
    content="[\"workflow permissions are not supported in MVP\", \"job 'build' permissions are not supported in MVP\"]",
  )
}

///|
test "compat docs: lower jobs needs fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "jobs-needs",
  )
  let deploy_task = flow_task_by_id(lowered.ir, "deploy/deploy")

  inspect(fixture.id, content="docs-jobs-needs")
  inspect(workflow.jobs[1].needs, content="[\"build\"]")
  inspect(lowered.errors, content="[]")
  inspect(deploy_task.needs, content="[\"build/__finish\"]")
}

///|
test "compat docs: parse steps id fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "steps-id",
  )
  let plan = compat_expect_task_plan(lowered.plan, "build/print_version")

  inspect(fixture.id, content="docs-steps-id")
  inspect(workflow.jobs[0].steps[0].id, content="print_version")
  inspect(lowered.errors, content="[]")
  inspect(plan.step_id, content="print_version")
}

///|
test "compat docs: lower steps run fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "steps-run",
  )
  let plan = compat_expect_task_plan(lowered.plan, "build/script")

  inspect(fixture.id, content="docs-steps-run")
  inspect(
    workflow.jobs[0].steps[0].run.unwrap_or(""),
    content="npm install\nnpm test\n",
  )
  inspect(lowered.errors, content="[]")
  inspect(plan.script, content="npm install\nnpm test\n")
}

///|
test "compat docs: lower steps uses fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "steps-uses",
  )
  let plan = compat_expect_task_plan(lowered.plan, "build/checkout")

  inspect(fixture.id, content="docs-steps-uses")
  inspect(
    workflow.jobs[0].steps[0].uses.unwrap_or(""),
    content="actions/checkout@v4",
  )
  inspect(lowered.errors, content="[]")
  inspect(plan.kind, content="action")
  inspect(plan.action.unwrap().uses, content="actions/checkout@v4")
}

///|
test "compat docs: lower steps shell fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "steps-shell",
  )
  let plan = compat_expect_task_plan(lowered.plan, "build/shell_step")

  inspect(fixture.id, content="docs-steps-shell")
  inspect(workflow.jobs[0].steps[0].shell.unwrap_or(""), content="sh")
  inspect(lowered.errors, content="[]")
  inspect(plan.shell, content="sh")
}

///|
#cfg(target="native")
async test "compat docs: custom shell template runs via script placeholder" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "steps-shell-template",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/template")

  inspect(fixture.id, content="docs-steps-shell-template")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<template-ok>")
}

///|
test "compat docs: lower steps working-directory fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "steps-working-directory",
  )
  let plan = compat_expect_task_plan(lowered.plan, "build/workdir")

  inspect(fixture.id, content="docs-steps-working-directory")
  inspect(
    workflow.jobs[0].steps[0].working_directory.unwrap_or(""),
    content="scripts",
  )
  inspect(lowered.errors, content="[]")
  inspect(plan.working_directory, content="scripts")
}

///|
test "compat docs: lower steps env fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "steps-env",
  )
  let plan = compat_expect_task_plan(lowered.plan, "build/env_step")

  inspect(fixture.id, content="docs-steps-env")
  inspect(
    workflow.jobs[0].steps[0].env.get("STEP_NAME").unwrap_or(""),
    content="Mona",
  )
  inspect(lowered.errors, content="[]")
  inspect(plan.env.get("DAY_OF_WEEK").unwrap_or(""), content="Monday")
  inspect(plan.env.get("GREETING").unwrap_or(""), content="Hello")
  inspect(plan.env.get("STEP_NAME").unwrap_or(""), content="Mona")
}

///|
test "compat docs: parse steps with fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "steps-with",
  )
  let plan = compat_expect_task_plan(lowered.plan, "build/checkout")

  inspect(fixture.id, content="docs-steps-with")
  inspect(
    workflow.jobs[0].steps[0].with_values.get("fetch-depth").unwrap_or(""),
    content="0",
  )
  inspect(lowered.errors, content="[]")
  inspect(plan.kind, content="action")
}

///|
#cfg(target="native")
async test "compat docs: checkout default fetch-depth keeps shallow history" {
  let (fixture, workflow) = compat_expect_docs_fixture("checkout-fetch-depth")
  let workspace = prepare_git_checkout_workspace(
    "compat-docs-checkout-fetch-depth",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-checkout-fetch-depth")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<1|yes>")
}

///|
#cfg(target="native")
async test "compat docs: checkout fetch-depth zero keeps full history" {
  let (fixture, workflow) = compat_expect_docs_fixture(
    "checkout-fetch-depth-zero",
  )
  let workspace = prepare_git_checkout_workspace(
    "compat-docs-checkout-fetch-depth-zero",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-checkout-fetch-depth-zero")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<2|no>")
}

///|
#cfg(target="native")
async test "compat docs: checkout ref selects the requested branch" {
  let (fixture, workflow) = compat_expect_docs_fixture("checkout-ref")
  let workspace = prepare_git_checkout_workspace_with_feature_branch(
    "compat-docs-checkout-ref",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-checkout-ref")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<feature|feature|1|yes>")
}

///|
#cfg(target="native")
async test "compat docs: checkout clean default removes untracked files" {
  let (fixture, workflow) = compat_expect_docs_fixture("checkout-clean-default")
  let workspace = prepare_git_checkout_workspace(
    "compat-docs-checkout-clean-default",
  )
  @xfs.write_string_to_file(workspace + "/scratch.txt", "keep?")
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-checkout-clean-default")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<no|yes>")
}

///|
#cfg(target="native")
async test "compat docs: checkout clean false preserves untracked files" {
  let (fixture, workflow) = compat_expect_docs_fixture("checkout-clean-false")
  let workspace = prepare_git_checkout_workspace(
    "compat-docs-checkout-clean-false",
  )
  @xfs.write_string_to_file(workspace + "/scratch.txt", "keep")
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-checkout-clean-false")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<second|yes|yes>")
}

///|
#cfg(target="native")
async test "compat docs: checkout submodules true initializes direct submodules" {
  let (fixture, workflow) = compat_expect_docs_fixture("checkout-submodules")
  let workspace = prepare_git_checkout_workspace_with_submodules(
    "compat-docs-checkout-submodules",
    recursive=true,
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-checkout-submodules")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<yes|no>")
}

///|
#cfg(target="native")
async test "compat docs: checkout submodules recursive initializes nested submodules" {
  let (fixture, workflow) = compat_expect_docs_fixture(
    "checkout-submodules-recursive",
  )
  let workspace = prepare_git_checkout_workspace_with_submodules(
    "compat-docs-checkout-submodules-recursive",
    recursive=true,
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-checkout-submodules-recursive")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<yes|yes>")
}

///|
#cfg(target="native")
async test "compat docs: setup-node configures node version and npm auth config" {
  let (fixture, workflow) = compat_expect_docs_fixture("setup-node-basic")
  let workspace = prepare_workspace("compat-docs-setup-node-basic")
  let node_log_path = workspace + "/setup-node.log"
  ignore(
    test_support_prepare_fake_version_node_bin(
      workspace, node_log_path, "24.9.0",
    ),
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-setup-node-basic")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(
    task.stdout,
    content="<v20.19.5|v20.19.5|XXXXX-XXXXX-XXXXX-XXXXX|yes|//registry.npmjs.org/:_authToken=${NODE_AUTH_TOKEN};registry=https://registry.npmjs.org/>",
  )
}

///|
#cfg(target="native")
async test "compat docs: setup-node cache npm restores after save job" {
  let (fixture, workflow) = compat_expect_docs_fixture("setup-node-cache-npm")
  let workspace = prepare_workspace("compat-docs-setup-node-cache-npm")
  let node_log_path = workspace + "/setup-node-cache.log"
  ignore(
    test_support_prepare_fake_version_node_bin(
      workspace, node_log_path, "24.9.0",
    ),
  )
  @xfs.write_string_to_file(workspace + "/package-lock.json", "{\"lock\":1}\n")
  test_support_remove_tree(compat_docs_cache_store_root(workspace))
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "restore/verify")

  inspect(fixture.id, content="docs-setup-node-cache-npm")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<true|ocean|false|v20.19.5>")
}

///|
#cfg(target="native")
async test "compat docs: cache restore-keys restores prefix hit and reports false" {
  let (fixture, workflow) = compat_expect_docs_fixture("cache-restore-keys")
  let workspace = prepare_workspace("compat-docs-cache-restore-keys")
  test_support_remove_tree(compat_docs_cache_store_root(workspace))
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  let task = compat_expect_task_report(report, "restore/verify")

  inspect(fixture.id, content="docs-cache-restore-keys")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<false|ocean>")
}

///|
test "compat docs: lower steps if status functions fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "steps-if-status-functions",
  )

  inspect(fixture.id, content="docs-steps-if-status-functions")
  inspect(workflow.jobs[0].steps[2].if_condition, content="failure()")
  inspect(lowered.errors, content="[]")
  inspect(
    compat_expect_task_plan(lowered.plan, "build/on_failure").if_condition,
    content="failure()",
  )
  inspect(
    compat_expect_task_plan(lowered.plan, "build/always_step").if_condition,
    content="always()",
  )
  inspect(
    compat_expect_task_plan(lowered.plan, "build/on_cancelled").if_condition,
    content="cancelled()",
  )
}

///|
test "compat docs: lower steps continue-on-error fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "steps-continue-on-error",
  )

  inspect(fixture.id, content="docs-steps-continue-on-error")
  inspect(workflow.jobs[0].steps[0].continue_on_error, content="true")
  inspect(lowered.errors, content="[]")
  inspect(
    compat_expect_task_plan(lowered.plan, "build/fail_soft").continue_on_error,
    content="true",
  )
}

///|
test "compat docs: lower matrix axes fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "strategy-matrix-axes",
  )
  let first = compat_expect_task_plan(lowered.plan, "build__matrix_1/show")
  let second = compat_expect_task_plan(lowered.plan, "build__matrix_2/show")

  inspect(fixture.id, content="docs-strategy-matrix-axes")
  inspect(workflow.jobs[0].matrix.unwrap().rows.length(), content="2")
  inspect(lowered.errors, content="[]")
  inspect(first.runs_on, content="[\"ubuntu-latest\"]")
  inspect(first.script, content="printf '%s' 'ubuntu-latest'")
  inspect(second.runs_on, content="[\"macos-latest\"]")
  inspect(second.script, content="printf '%s' 'macos-latest'")
}

///|
test "compat docs: lower matrix include fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "strategy-matrix-include",
  )
  let first = compat_expect_task_plan(lowered.plan, "build__matrix_1/show")
  let second = compat_expect_task_plan(lowered.plan, "build__matrix_2/show")

  inspect(fixture.id, content="docs-strategy-matrix-include")
  inspect(workflow.jobs[0].matrix.unwrap().fail_fast, content="false")
  inspect(workflow.jobs[0].matrix.unwrap().rows.length(), content="2")
  inspect(lowered.errors, content="[]")
  inspect(first.runs_on, content="[\"ubuntu-latest\"]")
  inspect(first.script, content="printf '%s' 'native'")
  inspect(second.script, content="printf '%s' 'js'")
}

///|
test "compat docs: lower matrix exclude fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "strategy-matrix-exclude",
  )
  let first = compat_expect_task_plan(lowered.plan, "build__matrix_1/show")
  let second = compat_expect_task_plan(lowered.plan, "build__matrix_2/show")
  let third = compat_expect_task_plan(lowered.plan, "build__matrix_3/show")

  inspect(fixture.id, content="docs-strategy-matrix-exclude")
  inspect(workflow.jobs[0].matrix.unwrap().rows.length(), content="3")
  inspect(lowered.errors, content="[]")
  inspect(first.script, content="printf '%s|%s' 'ubuntu-latest' 'native'")
  inspect(second.script, content="printf '%s|%s' 'ubuntu-latest' 'js'")
  inspect(third.script, content="printf '%s|%s' 'macos-latest' 'native'")
}

///|
test "compat docs: lower mixed matrix include fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "strategy-matrix-mixed-include",
  )
  let first = compat_expect_task_plan(lowered.plan, "build__matrix_1/show")
  let second = compat_expect_task_plan(lowered.plan, "build__matrix_2/show")
  let third = compat_expect_task_plan(lowered.plan, "build__matrix_3/show")

  inspect(fixture.id, content="docs-strategy-matrix-mixed-include")
  inspect(workflow.jobs[0].matrix.unwrap().rows.length(), content="3")
  inspect(lowered.errors, content="[]")
  inspect(first.script, content="printf '%s|%s' 'ubuntu-latest' 'js'")
  inspect(second.script, content="printf '%s|%s' 'macos-latest' 'native'")
  inspect(third.script, content="printf '%s|%s' 'windows-latest' 'js'")
}

///|
test "compat docs: lower matrix max parallel fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "strategy-matrix-max-parallel",
  )
  let first = flow_task_by_id(lowered.ir, "build__matrix_1/show")
  let second = flow_task_by_id(lowered.ir, "build__matrix_2/show")
  let third = flow_task_by_id(lowered.ir, "build__matrix_3/show")
  let fourth = flow_task_by_id(lowered.ir, "build__matrix_4/show")

  inspect(fixture.id, content="docs-strategy-matrix-max-parallel")
  inspect(workflow.jobs[0].matrix.unwrap().rows.length(), content="4")
  inspect(workflow.jobs[0].matrix.unwrap().max_parallel, content="Some(2)")
  inspect(lowered.errors, content="[]")
  inspect(first.needs, content="[]")
  inspect(second.needs, content="[]")
  inspect(third.needs, content="[\"build__matrix_1/__finish\"]")
  inspect(fourth.needs, content="[\"build__matrix_2/__finish\"]")
}

///|
test "compat docs: lower matrix needs fixture" {
  let (fixture, workflow, lowered) = compat_expect_lowered_docs_fixture(
    "strategy-matrix-needs",
  )
  let consume = flow_task_by_id(lowered.ir, "consume/read")

  inspect(fixture.id, content="docs-strategy-matrix-needs")
  inspect(workflow.jobs[1].needs, content="[\"build\"]")
  inspect(lowered.errors, content="[]")
  inspect(
    consume.needs,
    content="[\"build__matrix_1/__finish\", \"build__matrix_2/__finish\"]",
  )
  inspect(
    lowered.plan.job_needs.get("consume").unwrap_or([]),
    content="[\"build\"]",
  )
}

///|
#cfg(target="native")
async test "compat docs: matrix fail-fast cancels later rows" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "strategy-matrix-fail-fast",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )

  inspect(fixture.id, content="docs-strategy-matrix-fail-fast")
  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  inspect(
    compat_expect_task_report(report, "build__matrix_1/emit").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build__matrix_2/emit").status,
    content="failed",
  )
  inspect(
    compat_expect_task_report(report, "build__matrix_3/emit").status,
    content="cancelled",
  )
  inspect(@xfs.path_exists(workspace + "/artifacts/late.txt"), content="false")
}

///|
#cfg(target="native")
async test "compat docs: matrix fail-fast false keeps later rows running" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "strategy-matrix-fail-fast-false",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )

  inspect(fixture.id, content="docs-strategy-matrix-fail-fast-false")
  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  inspect(
    compat_expect_task_report(report, "build__matrix_1/emit").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build__matrix_2/emit").status,
    content="failed",
  )
  inspect(
    compat_expect_task_report(report, "build__matrix_3/emit").status,
    content="success",
  )
  inspect(
    @xfs.read_file_to_string(workspace + "/artifacts/late.txt"),
    content="late",
  )
}

///|
#cfg(target="native")
async test "compat docs: missing env property evaluates to empty string" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-missing-env",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-missing-env")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<>")
}

///|
#cfg(target="native")
async test "compat docs: missing step output evaluates to empty string" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-missing-step-output",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/consume")

  inspect(fixture.id, content="docs-context-missing-step-output")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<>")
}

///|
#cfg(target="native")
async test "compat docs: env context is available in step script" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-env-script",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-env-script")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<from-job|from-step>")
}

///|
#cfg(target="native")
async test "compat docs: env context is available in step env" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-env-step-env",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/read")

  inspect(fixture.id, content="docs-context-env-step-env")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<from-job-env>")
}

///|
#cfg(target="native")
async test "compat docs: github context is available in step script" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-github-script",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-github-script")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<github-context|build|" + workspace + ">")
}

///|
#cfg(target="native")
async test "compat docs: github context is available in step env" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-github-step-env",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/read")

  inspect(fixture.id, content="docs-context-github-step-env")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<github-context-env|build>")
}

///|
#cfg(target="native")
async test "compat docs: string functions are available in step script and env" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-string-functions",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-string-functions")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<true|true|true|true>")
}

///|
#cfg(target="native")
async test "compat docs: json functions are available in step script and env" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-json-functions",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-json-functions")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<true|true|true|\"mizchi/action_runner\">")
}

///|
#cfg(target="native")
async test "compat docs: hashFiles is available in step script and env" {
  let (fixture, workflow, workspace) = compat_prepare_suite_fixture_auto(
    compat_docs_suite(),
    "context-hash-files",
    copy_fixture=true,
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-hash-files")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<yes|yes|yes>")
}

///|
#cfg(target="native")
async test "compat docs: vars context is available in step script and env" {
  let previous_color = compat_docs_set_env_var(
    "ACTION_RUNNER_VAR_COLOR", "ocean",
  )
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-vars",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  compat_docs_restore_env_var("ACTION_RUNNER_VAR_COLOR", previous_color)
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-vars")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<ocean|ocean|yes|ocean>")
}

///|
#cfg(target="native")
async test "compat docs: secrets context is available in step script and env" {
  let previous_token = compat_docs_set_env_var(
    "ACTION_RUNNER_SECRET_TOKEN", "s3cr3t",
  )
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-secrets",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  compat_docs_restore_env_var("ACTION_RUNNER_SECRET_TOKEN", previous_token)
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-secrets")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<s3cr3t|s3cr3t|yes|s3cr3t>")
}

///|
#cfg(target="native")
async test "compat docs: github.action is available in step script and env" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-github-action",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-github-action")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<show|show>")
}

///|
#cfg(target="native")
async test "compat docs: github ref context is available in push workflow" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-github-ref",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-github-ref")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(
    task.stdout,
    content="<push|refs/heads/main|main|abc123def456|push|refs/heads/main|main|abc123def456>",
  )
}

///|
#cfg(target="native")
async test "compat docs: github repository context is available in push workflow" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-github-repository",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/print")

  inspect(fixture.id, content="docs-context-github-repository")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<mizchi/action_runner|mizchi/action_runner>")
}

///|
#cfg(target="native")
async test "compat docs: step if status functions work in push workflow" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "steps-if-status-functions",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )

  inspect(fixture.id, content="docs-steps-if-status-functions")
  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  inspect(
    compat_expect_task_report(report, "build/default_skip").status,
    content="skipped",
  )
  inspect(
    compat_expect_task_report(report, "build/on_failure").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/always_step").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/on_cancelled").status,
    content="skipped",
  )
  inspect(
    @xfs.read_file_to_string(workspace + "/artifacts/result.txt"),
    content="no|yes|no|mizchi/action_runner",
  )
}

///|
#cfg(target="native")
async test "compat docs: step if string functions work in push workflow" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "steps-if-string-functions",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let verify = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-steps-if-string-functions")
  inspect(report.ok, content="true")
  inspect(
    compat_expect_task_report(report, "build/on_contains").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/on_starts").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/on_ends").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/skip_release").status,
    content="skipped",
  )
  inspect(verify.stdout, content="<yes|yes|yes|no>")
}

///|
#cfg(target="native")
async test "compat docs: step if json functions work in push workflow" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "steps-if-json-functions",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let verify = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-steps-if-json-functions")
  inspect(report.ok, content="true")
  inspect(
    compat_expect_task_report(report, "build/on_enabled").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/on_event").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/skip_false").status,
    content="skipped",
  )
  inspect(verify.stdout, content="<yes|yes|no>")
}

///|
#cfg(target="native")
async test "compat docs: step if hashFiles works in push workflow" {
  let (fixture, workflow, workspace) = compat_prepare_suite_fixture_auto(
    compat_docs_suite(),
    "steps-if-hash-files",
    copy_fixture=true,
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let verify = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-steps-if-hash-files")
  inspect(report.ok, content="true")
  inspect(
    compat_expect_task_report(report, "build/on_match").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/skip_missing").status,
    content="skipped",
  )
  inspect(verify.stdout, content="<yes|no>")
}

///|
#cfg(target="native")
async test "compat docs: step if vars works in push workflow" {
  let previous_enabled = compat_docs_set_env_var(
    "ACTION_RUNNER_VAR_FEATURE_ENABLED", "true",
  )
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "steps-if-vars",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  compat_docs_restore_env_var(
    "ACTION_RUNNER_VAR_FEATURE_ENABLED", previous_enabled,
  )
  let verify = compat_expect_task_report(report, "build/verify")

  inspect(fixture.id, content="docs-steps-if-vars")
  inspect(report.ok, content="true")
  inspect(
    compat_expect_task_report(report, "build/on_enabled").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/skip_missing").status,
    content="skipped",
  )
  inspect(verify.stdout, content="<yes|no>")
}

///|
#cfg(target="native")
async test "compat docs: continue-on-error lets later steps run" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "steps-continue-on-error",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )

  inspect(fixture.id, content="docs-steps-continue-on-error")
  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(
    compat_expect_task_report(report, "build/fail_soft").status,
    content="failed",
  )
  inspect(
    compat_expect_step_report(report, "build/fail_soft").status,
    content="success",
  )
  inspect(
    compat_expect_task_report(report, "build/after").status,
    content="success",
  )
  inspect(
    @xfs.read_file_to_string(workspace + "/artifacts/result.txt"),
    content="mizchi/action_runner|yes",
  )
}

///|
#cfg(target="native")
async test "compat docs: job if can use github repository context" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "jobs-if-repository",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/print")

  inspect(fixture.id, content="docs-jobs-if-repository")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<job-if-ok>")
}

///|
#cfg(target="native")
async test "compat docs: github actor context is available in push workflow" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-github-actor",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/print")

  inspect(fixture.id, content="docs-context-github-actor")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<octocat|octocat>")
}

///|
#cfg(target="native")
async test "compat docs: github repository owner context is available in push workflow" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-github-repository-owner",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/print")

  inspect(fixture.id, content="docs-context-github-repository-owner")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<mizchi|mizchi>")
}

///|
#cfg(target="native")
async test "compat docs: needs outputs are available in dependent job" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-needs-output",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "consume/read")

  inspect(fixture.id, content="docs-context-needs-output")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<build-42>")
}

///|
#cfg(target="native")
async test "compat docs: needs result is available in dependent job" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-needs-result",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "consume/read")

  inspect(fixture.id, content="docs-context-needs-result")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<success>")
}

///|
#cfg(target="native")
async test "compat docs: matrix needs aggregate result and outputs" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-needs-matrix-output",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "consume/read")

  inspect(fixture.id, content="docs-context-needs-matrix-output")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<success|native|js>")
}

///|
#cfg(target="native")
async test "compat docs: runner context is available in step script" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-runner-script",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-runner-script")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<ok>")
}

///|
#cfg(target="native")
async test "compat docs: runner context is available in step env" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-runner-step-env",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/read")

  inspect(fixture.id, content="docs-context-runner-step-env")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<ok>")
}

///|
#cfg(target="native")
async test "compat docs: step outputs are available to later steps" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-step-output",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/consume")

  inspect(fixture.id, content="docs-context-step-output")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<from-output>")
}

///|
#cfg(target="native")
async test "compat docs: step outcome and conclusion are available to later steps" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-step-status",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/consume")

  inspect(fixture.id, content="docs-context-step-status")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(
    task.stdout,
    content="<success|success|failure|success|failure|success>",
  )
}

///|
#cfg(target="native")
async test "compat docs: env precedence uses the most specific value" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "context-env-precedence",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/show")

  inspect(fixture.id, content="docs-context-env-precedence")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<step>")
}

///|
#cfg(target="native")
async test "compat docs: step summary is collected from file command" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "workflow-command-step-summary",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/summary")

  inspect(fixture.mode, content="supported")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.summary, content="summary")
}

///|
#cfg(target="native")
async test "compat docs: github state is currently unsupported" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "workflow-command-state",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/state")

  inspect(fixture.mode, content="unsupported")
  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  inspect(task.status, content="failed")
  inspect(
    task.stderr,
    content="workflow command 'GITHUB_STATE' is not supported in MVP",
  )
}

///|
#cfg(target="native")
async test "compat docs: github env single-line applies to later steps" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "workflow-command-github-env-single",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/read")

  inspect(fixture.id, content="docs-workflow-command-github-env-single")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<yellow>")
}

///|
#cfg(target="native")
async test "compat docs: github env multiline applies to later steps" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "workflow-command-github-env-multiline",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/read")

  inspect(fixture.id, content="docs-workflow-command-github-env-multiline")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<line-1\nline-2>")
}

///|
#cfg(target="native")
async test "compat docs: github output single-line applies to later steps" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "workflow-command-github-output-single",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/get_color")

  inspect(fixture.id, content="docs-workflow-command-github-output-single")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<green>")
}

///|
#cfg(target="native")
async test "compat docs: github output multiline applies to later steps" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "workflow-command-github-output-multiline",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let task = compat_expect_task_report(report, "build/get_json")

  inspect(fixture.id, content="docs-workflow-command-github-output-multiline")
  inspect(report.ok, content="true")
  inspect(task.status, content="success")
  inspect(task.stdout, content="<line-1\nline-2>")
}

///|
#cfg(target="native")
async test "compat docs: github path only affects later steps" {
  let (fixture, workflow, workspace) = compat_prepare_docs_fixture_auto(
    "workflow-command-github-path",
  )
  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
    push_event=compat_push_event_fixture(fixture),
  )
  let export_task = compat_expect_task_report(report, "build/export_path")
  let read_task = compat_expect_task_report(report, "build/read_path")

  inspect(fixture.id, content="docs-workflow-command-github-path")
  inspect(report.ok, content="true")
  inspect(export_task.status, content="success")
  inspect(export_task.stdout, content="<missing>")
  inspect(read_task.status, content="success")
  inspect(read_task.stdout, content="<from-path>")
}

///|
test "compat docs: parse push branches fixture" {
  let (fixture, workflow) = compat_expect_docs_fixture("push-branches")

  inspect(fixture.id, content="docs-push-branches")
  inspect(workflow.trigger.branches, content="[\"main\", \"releases/*\"]")
  inspect(
    matches_push_trigger(
      workflow.trigger,
      new_push_event("main", ["src/lib.mbt"]),
    ),
    content="true",
  )
  inspect(
    matches_push_trigger(
      workflow.trigger,
      new_push_event("feature/example", ["src/lib.mbt"]),
    ),
    content="false",
  )
}

///|
test "compat docs: parse push branches-ignore fixture" {
  let (fixture, workflow) = compat_expect_docs_fixture("push-branches-ignore")

  inspect(fixture.id, content="docs-push-branches-ignore")
  inspect(
    workflow.trigger.branches_ignore,
    content="[\"mona/octocat\", \"releases/*-alpha\"]",
  )
  inspect(
    matches_push_trigger(
      workflow.trigger,
      new_push_event("releases/10-alpha", ["src/lib.mbt"]),
    ),
    content="false",
  )
  inspect(
    matches_push_trigger(
      workflow.trigger,
      new_push_event("releases/10", ["src/lib.mbt"]),
    ),
    content="true",
  )
}

///|
test "compat docs: parse push paths fixture" {
  let (fixture, workflow) = compat_expect_docs_fixture("push-paths")

  inspect(fixture.id, content="docs-push-paths")
  inspect(workflow.trigger.paths, content="[\"src/**\", \"package.json\"]")
  inspect(
    matches_push_trigger(
      workflow.trigger,
      new_push_event("main", ["src/app.mbt"]),
    ),
    content="true",
  )
  inspect(
    matches_push_trigger(
      workflow.trigger,
      new_push_event("main", ["docs/spec.md"]),
    ),
    content="false",
  )
}

///|
test "compat docs: parse push paths-ignore fixture" {
  let (fixture, workflow) = compat_expect_docs_fixture("push-paths-ignore")

  inspect(fixture.id, content="docs-push-paths-ignore")
  inspect(workflow.trigger.paths_ignore, content="[\"docs/**\", \"*.md\"]")
  inspect(
    matches_push_trigger(
      workflow.trigger,
      new_push_event("main", ["docs/spec.txt", "README.md"]),
    ),
    content="false",
  )
  inspect(
    matches_push_trigger(
      workflow.trigger,
      new_push_event("main", ["docs/spec.txt", "src/lib.mbt"]),
    ),
    content="true",
  )
}
