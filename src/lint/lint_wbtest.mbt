///|
test "lint clean workflow produces no errors" {
  let workflow = @ar.new_workflow("clean", [
    @ar.new_job("build", [
      @ar.new_run_step("compile", "make build"),
      @ar.new_run_step("test", "make test"),
    ]),
  ])
  let diags = lint_workflow(workflow)
  let errors = diags.filter(fn(d) { d.severity == Error })
  assert_eq(errors.length(), 0)
}

///|
test "lint detects undefined context in if condition" {
  let workflow = @ar.new_workflow("test", [
    @ar.new_job("build", [
      @ar.new_run_step(
        "s1",
        "echo test",
        if_condition="foobar.something == 'x'",
      ),
    ]),
  ])
  let diags = lint_workflow(workflow)
  let context_errors = diags.filter(fn(d) { d.code == "undefined-context" })
  assert_true(context_errors.length() > 0)
}

///|
test "lint detects unreachable step" {
  let workflow = @ar.new_workflow("test", [
    @ar.new_job("build", [
      @ar.new_run_step("s1", "echo ok"),
      @ar.new_run_step("s2", "echo skip", if_condition="false"),
    ]),
  ])
  let diags = lint_workflow(workflow)
  let dead = diags.filter(fn(d) { d.code == "unreachable-step" })
  assert_eq(dead.length(), 1)
}

///|
test "lint detects cycle" {
  let workflow = @ar.new_workflow("test", [
    @ar.new_job("a", [@ar.new_run_step("s1", "echo a")], needs=["b"]),
    @ar.new_job("b", [@ar.new_run_step("s1", "echo b")], needs=["a"]),
  ])
  let diags = lint_workflow(workflow)
  let cycles = diags.filter(fn(d) { d.code == "circular-needs" })
  assert_true(cycles.length() > 0)
}

///|
test "lint valid expression in run" {
  let workflow = @ar.new_workflow("test", [
    @ar.new_job("build", [
      @ar.new_run_step("s1", "echo $\u007b\u007b github.ref }}"),
    ]),
  ])
  let diags = lint_workflow(workflow)
  let errors = diags.filter(fn(d) { d.severity == Error })
  assert_eq(errors.length(), 0)
}

///|
test "lint unknown function in expression" {
  let workflow = @ar.new_workflow("test", [
    @ar.new_job("build", [
      @ar.new_run_step("s1", "echo $\u007b\u007b unknownFunc() }}"),
    ]),
  ])
  let diags = lint_workflow(workflow)
  let func_errors = diags.filter(fn(d) { d.code == "unknown-function" })
  assert_true(func_errors.length() > 0)
}

///|
test "has_errors returns true for errors" {
  let diags : Array[LintDiagnostic] = [
    {
      severity: Error,
      code: "undefined-context",
      message: "test",
      job_id: "j",
      step_index: 0,
      field: "if",
    },
  ]
  assert_true(has_errors(diags))
}

///|
test "has_errors returns false for warnings only" {
  let diags : Array[LintDiagnostic] = [
    {
      severity: Warning,
      code: "unknown-property",
      message: "test",
      job_id: "j",
      step_index: 0,
      field: "if",
    },
  ]
  assert_true(!has_errors(diags))
}
