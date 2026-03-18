///|
test "S001: duplicate step IDs in same job" {
  let job = @ar.new_job("build", [
    @ar.new_run_step("setup", "echo setup"),
    @ar.new_run_step("setup", "echo setup again"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s001 = diags.filter(fn(d) { d.code == "duplicate-step-id" })
  inspect(
    s001[0].format(),
    content="[build/step1] id: error[duplicate-step-id]: duplicate step id 'setup' (first defined at step 0)",
  )
}

///|
test "S001: no duplicate when step IDs are different" {
  let job = @ar.new_job("build", [
    @ar.new_run_step("s1", "echo one"),
    @ar.new_run_step("s2", "echo two"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s001 = diags.filter(fn(d) { d.code == "duplicate-step-id" })
  inspect(s001.length(), content="0")
}

///|
test "S001: empty IDs do not count as duplicates" {
  let job = @ar.new_job("build", [
    @ar.new_run_step("", "echo one"),
    @ar.new_run_step("", "echo two"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s001 = diags.filter(fn(d) { d.code == "duplicate-step-id" })
  inspect(s001.length(), content="0")
}

///|
test "S002: empty runs-on without reusable workflow" {
  let job = @ar.new_job("build", [@ar.new_run_step("s1", "echo hi")], runs_on=[])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s002 = diags.filter(fn(d) { d.code == "missing-runs-on" })
  inspect(
    s002[0].format(),
    content="[build/step-1] runs-on: error[missing-runs-on]: job 'build' has empty runs-on and is not a reusable workflow call",
  )
}

///|
test "S002: no error when reusable workflow" {
  let job = @ar.new_job(
    "call",
    [],
    runs_on=[],
    reusable_workflow=Some("org/repo/.github/workflows/ci.yml@main"),
  )
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s002 = diags.filter(fn(d) { d.code == "missing-runs-on" })
  inspect(s002.length(), content="0")
}

///|
test "S003: empty job without steps or reusable workflow" {
  let job = @ar.new_job("empty", [], runs_on=["ubuntu-latest"])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s003 = diags.filter(fn(d) { d.code == "empty-job" })
  inspect(
    s003[0].format(),
    content="[empty/step-1] steps: error[empty-job]: job 'empty' has no steps and is not a reusable workflow call",
  )
}

///|
test "S003: no error when reusable workflow with no steps" {
  let job = @ar.new_job(
    "call",
    [],
    runs_on=[],
    reusable_workflow=Some("org/repo/.github/workflows/ci.yml@main"),
  )
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s003 = diags.filter(fn(d) { d.code == "empty-job" })
  inspect(s003.length(), content="0")
}

///|
test "S004: step has both uses and run via YAML" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: bad
    #|        uses: actions/checkout@v4
    #|        run: echo hi
  let parsed = @ar.parse_workflow_yaml(yaml)
  match parsed.workflow {
    Option::Some(workflow) => {
      let diags = check_structure(workflow)
      let s004 = diags.filter(fn(d) { d.code == "uses-and-run" })
      inspect(
        s004[0].format(),
        content="[build/step0] uses/run: error[uses-and-run]: step has both 'uses' and 'run' defined",
      )
    }
    Option::None => inspect("parse failed", content="should not fail")
  }
}

///|
test "S004: no error for normal steps" {
  let job = @ar.new_job("build", [
    @ar.new_run_step("s1", "echo hi"),
    @ar.new_uses_step("s2", "actions/checkout@v4"),
  ])
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s004 = diags.filter(fn(d) { d.code == "uses-and-run" })
  inspect(s004.length(), content="0")
}

///|
test "S005: matrix with empty rows" {
  let job = @ar.new_job(
    "build",
    [@ar.new_run_step("s1", "echo hi")],
    matrix=Some(@ar.new_job_matrix([])),
  )
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s005 = diags.filter(fn(d) { d.code == "empty-matrix" })
  inspect(
    s005[0].format(),
    content="[build/step-1] matrix: warning[empty-matrix]: job 'build' has a matrix with no rows",
  )
}

///|
test "S005: no warning when matrix has rows" {
  let row : Map[String, String] = { "os": "ubuntu-latest" }
  let job = @ar.new_job(
    "build",
    [@ar.new_run_step("s1", "echo hi")],
    matrix=Some(@ar.new_job_matrix([row])),
  )
  let workflow = @ar.new_workflow("test", [job])
  let diags = check_structure(workflow)
  let s005 = diags.filter(fn(d) { d.code == "empty-matrix" })
  inspect(s005.length(), content="0")
}
