///|
fn make_test_context() -> LintContext {
  let job = @ar.new_job(
    "test",
    [
      @ar.new_run_step("step1", "echo hello"),
      @ar.new_run_step("step2", "echo world"),
    ],
    needs=["build"],
  )
  let build_job = @ar.new_job("build", [@ar.new_run_step("compile", "make")])
  build_lint_context(job, 2, [build_job, job])
}

///|
test "check valid github.ref" {
  let ctx = make_test_context()
  let diags = check_expression("github.ref", ctx, "test", 0, "if")
  assert_eq(diags.length(), 0)
}

///|
test "check valid github.event_name" {
  let ctx = make_test_context()
  let diags = check_expression(
    "github.event_name == 'push'", ctx, "test", 0, "if",
  )
  assert_eq(diags.length(), 0)
}

///|
test "check undefined context" {
  let ctx = make_test_context()
  let diags = check_expression("foobar.something", ctx, "test", 0, "if")
  assert_true(diags.length() > 0)
  assert_eq(diags[0].code, "undefined-context")
}

///|
test "check unknown github property" {
  let ctx = make_test_context()
  let diags = check_expression("github.nonexistent", ctx, "test", 0, "if")
  assert_true(diags.length() > 0)
  assert_eq(diags[0].code, "unknown-property")
}

///|
test "check env access is valid" {
  let ctx = make_test_context()
  let diags = check_expression("env.MY_VAR", ctx, "test", 0, "if")
  assert_eq(diags.length(), 0)
}

///|
test "check secrets access is valid" {
  let ctx = make_test_context()
  let diags = check_expression("secrets.GITHUB_TOKEN", ctx, "test", 0, "if")
  assert_eq(diags.length(), 0)
}

///|
test "check steps access" {
  let ctx = make_test_context()
  // step1 and step2 are visible (step_index=2 means both are before)
  let diags = check_expression(
    "steps.step1.outputs.result", ctx, "test", 2, "if",
  )
  assert_eq(diags.length(), 0)
}

///|
test "check unknown step reference" {
  let ctx = make_test_context()
  let diags = check_expression(
    "steps.nonexistent.outputs.foo", ctx, "test", 2, "if",
  )
  assert_true(diags.length() > 0)
  assert_eq(diags[0].code, "unknown-property")
}

///|
test "check needs access" {
  let ctx = make_test_context()
  let diags = check_expression(
    "needs.build.result == 'success'", ctx, "test", 0, "if",
  )
  assert_eq(diags.length(), 0)
}

///|
test "check unknown needs reference" {
  let ctx = make_test_context()
  let diags = check_expression("needs.unknown.result", ctx, "test", 0, "if")
  assert_true(diags.length() > 0)
}

///|
test "check function arity: contains with wrong args" {
  let ctx = make_test_context()
  let diags = check_expression("contains('hello')", ctx, "test", 0, "if")
  assert_true(diags.length() > 0)
  assert_eq(diags[0].code, "wrong-arity")
}

///|
test "check function arity: success with args" {
  let ctx = make_test_context()
  let diags = check_expression("success('x')", ctx, "test", 0, "if")
  assert_true(diags.length() > 0)
  assert_eq(diags[0].code, "wrong-arity")
}

///|
test "check unknown function" {
  let ctx = make_test_context()
  let diags = check_expression("fooFunc()", ctx, "test", 0, "if")
  assert_true(diags.length() > 0)
  assert_eq(diags[0].code, "unknown-function")
}

///|
test "check valid contains call" {
  let ctx = make_test_context()
  let diags = check_expression(
    "contains('hello world', 'world')", ctx, "test", 0, "if",
  )
  assert_eq(diags.length(), 0)
}

///|
test "check valid complex expression" {
  let ctx = make_test_context()
  let diags = check_expression(
    "github.event_name == 'push' && contains(github.ref, 'main')", ctx, "test", 0,
    "if",
  )
  assert_eq(diags.length(), 0)
}

///|
test "check hashFiles" {
  let ctx = make_test_context()
  let diags = check_expression(
    "hashFiles('**/package-lock.json')", ctx, "test", 0, "run",
  )
  assert_eq(diags.length(), 0)
}

///|
test "check toJSON" {
  let ctx = make_test_context()
  let diags = check_expression("toJSON(env)", ctx, "test", 0, "run")
  assert_eq(diags.length(), 0)
}

///|
test "check format_diagnostic" {
  let diag : LintDiagnostic = {
    severity: Error,
    code: "undefined-context",
    message: "test message",
    job_id: "build",
    step_index: 0,
    field: "if",
  }
  let formatted = diag.format()
  assert_true(formatted.contains("build"))
  assert_true(formatted.contains("undefined-context"))
  assert_true(formatted.contains("test message"))
}
