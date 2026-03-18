///|
test "extract expressions from template" {
  let exprs = extract_expressions(
    "echo $\u007b\u007b github.ref }} and $\u007b\u007b env.FOO }}",
  )
  assert_eq(exprs.length(), 2)
  assert_eq(exprs[0], "github.ref")
  assert_eq(exprs[1], "env.FOO")
}

///|
test "extract expressions empty string" {
  let exprs = extract_expressions("no expressions here")
  assert_eq(exprs.length(), 0)
}

///|
test "detect unreachable step with if: false" {
  let job = @ar.new_job("test", [
    @ar.new_run_step("s1", "echo hello"),
    @ar.new_run_step("s2", "echo skip", if_condition="false"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_dead_code(workflow)
  let dead_steps = diags.filter(fn(d) { d.code == "unreachable-step" })
  assert_eq(dead_steps.length(), 1)
}

///|
test "detect undefined needs reference" {
  let job = @ar.new_job("deploy", [@ar.new_run_step("s1", "deploy")], needs=[
    "nonexistent",
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_dead_code(workflow)
  let undefined = diags.filter(fn(d) { d.code == "undefined-needs" })
  assert_eq(undefined.length(), 1)
}

///|
test "detect dependency cycle" {
  let job_a = @ar.new_job("a", [@ar.new_run_step("s1", "echo a")], needs=["b"])
  let job_b = @ar.new_job("b", [@ar.new_run_step("s1", "echo b")], needs=["a"])
  let workflow = @ar.new_workflow("test", [job_a, job_b])
  let diags = check_dead_code(workflow)
  let cycles = diags.filter(fn(d) { d.code == "circular-needs" })
  assert_true(cycles.length() > 0)
}

///|
test "no false positives for valid workflow" {
  let build_job = @ar.new_job("build", [@ar.new_run_step("compile", "make")])
  let test_job = @ar.new_job("test", [@ar.new_run_step("test", "make test")], needs=[
    "build",
  ])
  let workflow = @ar.new_workflow("test", [build_job, test_job])
  let diags = check_dead_code(workflow)
  let errors = diags.filter(fn(d) { d.severity == Error })
  assert_eq(errors.length(), 0)
}

///|
test "detect undefined step reference in expression" {
  let job = @ar.new_job("test", [
    @ar.new_run_step(
      "s1", "echo $\u007b\u007b steps.nonexistent.outputs.foo }}",
    ),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_dead_code(workflow)
  let step_refs = diags.filter(fn(d) { d.code == "undefined-step-ref" })
  assert_true(step_refs.length() > 0)
}

///|
test "valid step reference produces no error" {
  let job = @ar.new_job("test", [
    @ar.new_run_step("setup", "echo setup"),
    @ar.new_run_step("use", "echo $\u007b\u007b steps.setup.outputs.result }}"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_dead_code(workflow)
  let step_errors = diags.filter(fn(d) {
    d.code == "future-step-ref" || d.code == "undefined-step-ref"
  })
  assert_eq(step_errors.length(), 0)
}
