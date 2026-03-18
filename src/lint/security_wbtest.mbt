///|
test "SEC01: detect script injection with github.event.issue.title" {
  let step = @ar.new_run_step(
    "s1", "echo $\u007b\u007b github.event.issue.title }}",
  )
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec01 = diags.filter(fn(d) { d.code == "script-injection" })
  inspect(
    sec01,
    content=(
      #|[{severity: Warning, code: "script-injection", message: "potential script injection: untrusted input 'github.event.issue.title' used directly in run script", job_id: "test", step_index: 0, field: "run"}]
    ),
  )
}

///|
test "SEC01: detect script injection with github.event.pull_request.body" {
  let step = @ar.new_run_step(
    "s1", "echo $\u007b\u007b github.event.pull_request.body }}",
  )
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec01 = diags.filter(fn(d) { d.code == "script-injection" })
  inspect(
    sec01,
    content=(
      #|[{severity: Warning, code: "script-injection", message: "potential script injection: untrusted input 'github.event.pull_request.body' used directly in run script", job_id: "test", step_index: 0, field: "run"}]
    ),
  )
}

///|
test "SEC01: detect github.head_ref injection" {
  let step = @ar.new_run_step("s1", "echo $\u007b\u007b github.head_ref }}")
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec01 = diags.filter(fn(d) { d.code == "script-injection" })
  inspect(
    sec01,
    content=(
      #|[{severity: Warning, code: "script-injection", message: "potential script injection: untrusted input 'github.head_ref' used directly in run script", job_id: "test", step_index: 0, field: "run"}]
    ),
  )
}

///|
test "SEC01: no warning for safe expressions" {
  let step = @ar.new_run_step("s1", "echo $\u007b\u007b github.sha }}")
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec01 = diags.filter(fn(d) { d.code == "script-injection" })
  inspect(
    sec01,
    content=(
      #|[]
    ),
  )
}

///|
test "SEC01: multiple dangerous expressions in one script" {
  let step = @ar.new_run_step(
    "s1", "echo $\u007b\u007b github.event.issue.title }} $\u007b\u007b github.event.comment.body }}",
  )
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec01 = diags.filter(fn(d) { d.code == "script-injection" })
  inspect(
    sec01,
    content=(
      #|[{severity: Warning, code: "script-injection", message: "potential script injection: untrusted input 'github.event.issue.title' used directly in run script", job_id: "test", step_index: 0, field: "run"}, {severity: Warning, code: "script-injection", message: "potential script injection: untrusted input 'github.event.comment.body' used directly in run script", job_id: "test", step_index: 0, field: "run"}]
    ),
  )
}

///|
test "SEC02: detect write-all permissions" {
  let step = @ar.new_run_step("s1", "echo hello")
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow(
    "test",
    [job],
    permissions=Some(@ar.new_permissions_spec(values={ "_": "write-all" })),
  )
  let diags = check_security(workflow)
  let sec02 = diags.filter(fn(d) { d.code == "permissive-permissions" })
  inspect(
    sec02,
    content=(
      #|[{severity: Warning, code: "permissive-permissions", message: "overly permissive permissions: 'write-all' grants write access to all scopes", job_id: "", step_index: -1, field: "permissions"}]
    ),
  )
}

///|
test "SEC02: detect all write permissions (more than 3)" {
  let step = @ar.new_run_step("s1", "echo hello")
  let job = @ar.new_job("test", [step])
  let perms = @ar.new_permissions_spec(values={
    "contents": "write",
    "packages": "write",
    "issues": "write",
    "pull-requests": "write",
  })
  let workflow = @ar.new_workflow("test", [job], permissions=Some(perms))
  let diags = check_security(workflow)
  let sec02 = diags.filter(fn(d) { d.code == "permissive-permissions" })
  inspect(
    sec02,
    content=(
      #|[{severity: Warning, code: "permissive-permissions", message: "overly permissive permissions: all 4 permissions are set to 'write'", job_id: "", step_index: -1, field: "permissions"}]
    ),
  )
}

///|
test "SEC02: no warning for mixed permissions" {
  let step = @ar.new_run_step("s1", "echo hello")
  let job = @ar.new_job("test", [step])
  let perms = @ar.new_permissions_spec(values={
    "contents": "write",
    "packages": "read",
    "issues": "write",
    "pull-requests": "write",
  })
  let workflow = @ar.new_workflow("test", [job], permissions=Some(perms))
  let diags = check_security(workflow)
  let sec02 = diags.filter(fn(d) { d.code == "permissive-permissions" })
  inspect(
    sec02,
    content=(
      #|[]
    ),
  )
}

///|
test "SEC02: no warning for 3 or fewer all-write permissions" {
  let step = @ar.new_run_step("s1", "echo hello")
  let job = @ar.new_job("test", [step])
  let perms = @ar.new_permissions_spec(values={
    "contents": "write",
    "packages": "write",
    "issues": "write",
  })
  let workflow = @ar.new_workflow("test", [job], permissions=Some(perms))
  let diags = check_security(workflow)
  let sec02 = diags.filter(fn(d) { d.code == "permissive-permissions" })
  inspect(
    sec02,
    content=(
      #|[]
    ),
  )
}

///|
test "SEC02: job-level write-all" {
  let step = @ar.new_run_step("s1", "echo hello")
  let job = @ar.new_job(
    "deploy",
    [step],
    permissions=Some(@ar.new_permissions_spec(values={ "_": "write-all" })),
  )
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec02 = diags.filter(fn(d) { d.code == "permissive-permissions" })
  inspect(
    sec02,
    content=(
      #|[{severity: Warning, code: "permissive-permissions", message: "overly permissive permissions: 'write-all' grants write access to all scopes", job_id: "deploy", step_index: -1, field: "permissions"}]
    ),
  )
}

///|
test "SEC03: detect deprecated set-output command" {
  let step = @ar.new_run_step("s1", "echo ::set-output name=result::hello")
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec03 = diags.filter(fn(d) { d.code == "deprecated-command" })
  inspect(
    sec03,
    content=(
      #|[{severity: Warning, code: "deprecated-command", message: "deprecated workflow command '::set-output name=' (deprecated, use GITHUB_OUTPUT)", job_id: "test", step_index: 0, field: "run"}]
    ),
  )
}

///|
test "SEC03: detect deprecated set-env command" {
  let step = @ar.new_run_step("s1", "echo ::set-env name=MY_VAR::value")
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec03 = diags.filter(fn(d) { d.code == "deprecated-command" })
  inspect(
    sec03,
    content=(
      #|[{severity: Warning, code: "deprecated-command", message: "deprecated workflow command '::set-env name=' (deprecated and DISABLED, use GITHUB_ENV)", job_id: "test", step_index: 0, field: "run"}]
    ),
  )
}

///|
test "SEC03: detect deprecated add-path command" {
  let step = @ar.new_run_step("s1", "echo ::add-path::/usr/local/bin")
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec03 = diags.filter(fn(d) { d.code == "deprecated-command" })
  inspect(
    sec03,
    content=(
      #|[{severity: Warning, code: "deprecated-command", message: "deprecated workflow command '::add-path::' (deprecated and DISABLED, use GITHUB_PATH)", job_id: "test", step_index: 0, field: "run"}]
    ),
  )
}

///|
test "SEC03: no warning for modern commands" {
  let step = @ar.new_run_step("s1", "echo \"result=hello\" >> $GITHUB_OUTPUT")
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec03 = diags.filter(fn(d) { d.code == "deprecated-command" })
  inspect(
    sec03,
    content=(
      #|[]
    ),
  )
}

///|
test "SEC03: detect deprecated save-state command" {
  let step = @ar.new_run_step("s1", "echo ::save-state name=mystate::value")
  let job = @ar.new_job("test", [step])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let sec03 = diags.filter(fn(d) { d.code == "deprecated-command" })
  inspect(
    sec03,
    content=(
      #|[{severity: Warning, code: "deprecated-command", message: "deprecated workflow command '::save-state name=' (deprecated, use GITHUB_STATE)", job_id: "test", step_index: 0, field: "run"}]
    ),
  )
}

///|
test "snapshot: SEC04 pull_request_target without permissions" {
  let yaml =
    #|name: test
    #|'on': pull_request_target
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo test
  let parsed = @ar.parse_workflow_yaml(yaml)
  guard parsed.workflow is Option::Some(workflow) else { fail("parse failed") }
  let diags = check_security(workflow, yaml_text=yaml)
  let prt = diags.filter(fn(d) { d.code == "missing-prt-permissions" })
  inspect(prt.length(), content="1")
  inspect(
    prt[0].message,
    content="workflow uses 'pull_request_target' trigger without explicit 'permissions' — this runs with write access to the base repo and should have minimal permissions",
  )
}

///|
test "snapshot: SEC04 pull_request_target with workflow permissions is ok" {
  let yaml =
    #|name: test
    #|'on': pull_request_target
    #|permissions:
    #|  contents: read
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo test
  let parsed = @ar.parse_workflow_yaml(yaml)
  guard parsed.workflow is Option::Some(workflow) else { fail("parse failed") }
  let diags = check_security(workflow, yaml_text=yaml)
  let prt = diags.filter(fn(d) { d.code == "missing-prt-permissions" })
  inspect(prt.length(), content="0")
}

///|
test "snapshot: SEC04 pull_request_target with job permissions is ok" {
  let yaml =
    #|name: test
    #|'on': pull_request_target
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    permissions:
    #|      contents: read
    #|    steps:
    #|      - run: echo test
  let parsed = @ar.parse_workflow_yaml(yaml)
  guard parsed.workflow is Option::Some(workflow) else { fail("parse failed") }
  let diags = check_security(workflow, yaml_text=yaml)
  let prt = diags.filter(fn(d) { d.code == "missing-prt-permissions" })
  inspect(prt.length(), content="0")
}

///|
test "snapshot: SEC04 normal pull_request does not trigger" {
  let yaml =
    #|name: test
    #|'on': pull_request
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo test
  let parsed = @ar.parse_workflow_yaml(yaml)
  guard parsed.workflow is Option::Some(workflow) else { fail("parse failed") }
  let diags = check_security(workflow, yaml_text=yaml)
  let prt = diags.filter(fn(d) { d.code == "missing-prt-permissions" })
  inspect(prt.length(), content="0")
}

///|
test "if-always: warns on bare always()" {
  let job = @ar.new_job("test", [
    @ar.new_run_step("s1", "echo ok", if_condition="always()"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let found = diags.filter(fn(d) { d.code == "if-always" })
  inspect(found.length(), content="1")
}

///|
test "if-always: no warn on always() && condition" {
  let job = @ar.new_job("test", [
    @ar.new_run_step(
      "s1",
      "echo ok",
      if_condition="always() && github.ref == 'refs/heads/main'",
    ),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_security(workflow)
  let found = diags.filter(fn(d) { d.code == "if-always" })
  inspect(found.length(), content="0")
}

///|
test "dangerous-checkout-in-prt: detects PR head checkout" {
  let yaml =
    #|name: test
    #|'on': pull_request_target
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|        with:
    #|          ref: ${{ github.event.pull_request.head.sha }}
  let parsed = @ar.parse_workflow_yaml(yaml)
  guard parsed.workflow is Option::Some(workflow) else { fail("parse failed") }
  let diags = check_security(workflow, yaml_text=yaml)
  let found = diags.filter(fn(d) { d.code == "dangerous-checkout-in-prt" })
  inspect(found.length(), content="1")
}

///|
test "dangerous-checkout-in-prt: normal checkout is ok" {
  let yaml =
    #|name: test
    #|'on': pull_request_target
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
  let parsed = @ar.parse_workflow_yaml(yaml)
  guard parsed.workflow is Option::Some(workflow) else { fail("parse failed") }
  let diags = check_security(workflow, yaml_text=yaml)
  let found = diags.filter(fn(d) { d.code == "dangerous-checkout-in-prt" })
  inspect(found.length(), content="0")
}

///|
test "secrets-to-third-party: detects secrets in env" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: third-party/action@v1
    #|        env:
    #|          TOKEN: ${{ secrets.GITHUB_TOKEN }}
  let parsed = @ar.parse_workflow_yaml(yaml)
  guard parsed.workflow is Option::Some(workflow) else { fail("parse failed") }
  let diags = check_security(workflow)
  let found = diags.filter(fn(d) { d.code == "secrets-to-third-party" })
  inspect(found.length(), content="1")
}

///|
test "secrets-to-third-party: actions/ org is trusted" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|        env:
    #|          TOKEN: ${{ secrets.GITHUB_TOKEN }}
  let parsed = @ar.parse_workflow_yaml(yaml)
  guard parsed.workflow is Option::Some(workflow) else { fail("parse failed") }
  let diags = check_security(workflow)
  let found = diags.filter(fn(d) { d.code == "secrets-to-third-party" })
  inspect(found.length(), content="0")
}

///|
test "missing-timeout: strict mode only" {
  let job = @ar.new_job("build", [@ar.new_run_step("s1", "make")])
  let workflow = @ar.new_workflow("test", [job])
  let diags1 = check_structure(workflow)
  let found1 = diags1.filter(fn(d) { d.code == "missing-timeout" })
  inspect(found1.length(), content="0")
  let diags2 = check_structure(workflow, strict=true)
  let found2 = diags2.filter(fn(d) { d.code == "missing-timeout" })
  inspect(found2.length(), content="1")
}
