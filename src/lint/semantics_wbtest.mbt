///|
test "S006: valid uses formats" {
  let job = @ar.new_job("build", [
    @ar.new_uses_step("s1", "actions/checkout@v4"),
    @ar.new_uses_step("s2", "actions/setup-node@v3"),
    @ar.new_uses_step("s3", "owner/repo/path@v1"),
    @ar.new_uses_step("s4", "./local/action"),
    @ar.new_uses_step("s5", "docker://alpine:3.18"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_semantics(workflow)
  let s006 = diags.filter(fn(d) { d.code == "invalid-uses" })
  inspect(s006, content="[]")
}

///|
test "S006: invalid uses format" {
  let job = @ar.new_job("build", [
    @ar.new_uses_step("s1", "just-a-string"),
    @ar.new_uses_step("s2", "no-at-sign/repo"),
    @ar.new_uses_step("s3", "nopath@v1"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_semantics(workflow)
  let s006 = diags.filter(fn(d) { d.code == "invalid-uses" })
  inspect(s006.length(), content="3")
  inspect(s006[0].severity, content="Error")
}

///|
test "S009: valid glob patterns" {
  let trigger = @ar.new_push_trigger(
    branches=["main", "release/*", "feature/**"],
    paths=["src/**/*.ts", "!docs/**"],
  )
  let workflow = @ar.new_workflow(
    "test",
    [@ar.new_job("build", [@ar.new_run_step("s1", "echo hi")])],
    trigger~,
  )
  let diags = check_semantics(workflow)
  let s009 = diags.filter(fn(d) { d.code == "invalid-glob" })
  inspect(s009, content="[]")
}

///|
test "S009: empty pattern" {
  let trigger = @ar.new_push_trigger(branches=["main", ""])
  let workflow = @ar.new_workflow(
    "test",
    [@ar.new_job("build", [@ar.new_run_step("s1", "echo hi")])],
    trigger~,
  )
  let diags = check_semantics(workflow)
  let s009 = diags.filter(fn(d) { d.code == "invalid-glob" })
  inspect(s009.length(), content="1")
  inspect(s009[0].message, content="invalid glob pattern '': empty pattern")
}

///|
test "S009: unbalanced brackets" {
  let trigger = @ar.new_push_trigger(branches=["feature/[broken"])
  let workflow = @ar.new_workflow(
    "test",
    [@ar.new_job("build", [@ar.new_run_step("s1", "echo hi")])],
    trigger~,
  )
  let diags = check_semantics(workflow)
  let s009 = diags.filter(fn(d) { d.code == "invalid-glob" })
  inspect(s009.length(), content="1")
  inspect(
    s009[0].message,
    content="invalid glob pattern 'feature/[broken': unbalanced brackets '['",
  )
}

///|
test "S009: unclosed brace" {
  let trigger = @ar.new_push_trigger(paths=["src/{foo,bar"])
  let workflow = @ar.new_workflow(
    "test",
    [@ar.new_job("build", [@ar.new_run_step("s1", "echo hi")])],
    trigger~,
  )
  let diags = check_semantics(workflow)
  let s009 = diags.filter(fn(d) { d.code == "invalid-glob" })
  inspect(s009.length(), content="1")
}

///|
test "S010: literal true condition" {
  let job = @ar.new_job("build", [
    @ar.new_run_step("s1", "echo hi", if_condition="true"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_semantics(workflow)
  let s010 = diags.filter(fn(d) { d.code == "redundant-condition" })
  inspect(s010.length(), content="1")
  inspect(s010[0].message, content="condition is always true (literal 'true')")
}

///|
test "S010: failure() && success() always false" {
  let job = @ar.new_job("build", [
    @ar.new_run_step("s1", "echo hi", if_condition="failure() && success()"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_semantics(workflow)
  let s010 = diags.filter(fn(d) { d.code == "redundant-condition" })
  inspect(s010.length(), content="1")
  inspect(
    s010[0].message,
    content="condition is always false: failure() && success() are mutually exclusive",
  )
}

///|
test "S010: true || anything always true" {
  let job = @ar.new_job("build", [
    @ar.new_run_step(
      "s1",
      "echo hi",
      if_condition="true || github.event_name == 'push'",
    ),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_semantics(workflow)
  let s010 = diags.filter(fn(d) { d.code == "redundant-condition" })
  inspect(s010.length(), content="1")
  inspect(
    s010[0].message,
    content="condition is always true: true || ... is always true",
  )
}

///|
test "S010: always() && false always false" {
  let job = @ar.new_job("build", [
    @ar.new_run_step("s1", "echo hi", if_condition="always() && false"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_semantics(workflow)
  let s010 = diags.filter(fn(d) { d.code == "redundant-condition" })
  inspect(s010.length(), content="1")
  inspect(
    s010[0].message,
    content="condition is always false: always() && false is always false",
  )
}

///|
test "S010: no false positive for normal conditions" {
  let job = @ar.new_job("build", [
    @ar.new_run_step(
      "s1",
      "echo hi",
      if_condition="github.event_name == 'push'",
    ),
    @ar.new_run_step("s2", "echo hi", if_condition="failure()"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_semantics(workflow)
  let s010 = diags.filter(fn(d) { d.code == "redundant-condition" })
  inspect(s010, content="[]")
}
