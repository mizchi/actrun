///|
test "plan_workflow: basic wasi workflow" {
  let yaml =
    #|name: wasi-ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: wasi
    #|    steps:
    #|      - uses: wasm://lint@v1
    #|      - uses: wasm://test@v1
  let result = @actrun.plan_workflow(yaml)
  @debug.debug_inspect(
    result.workflow_name,
    content=(
      #|"wasi-ci"
    ),
  )
  @debug.debug_inspect(result.errors, content="[]")
  @debug.debug_inspect(result.jobs.length(), content="1")
  @debug.debug_inspect(
    result.jobs[0].id,
    content=(
      #|"build"
    ),
  )
  @debug.debug_inspect(result.jobs[0].runs_on, content="[\"wasi\"]")
  @debug.debug_inspect(result.jobs[0].steps.length(), content="2")
  @debug.debug_inspect(
    result.jobs[0].steps[0].kind,
    content=(
      #|"action"
    ),
  )
  @debug.debug_inspect(
    result.jobs[0].steps[0].uses,
    content=(
      #|"wasm://lint@v1"
    ),
  )
  @debug.debug_inspect(
    result.jobs[0].steps[0].backend,
    content=(
      #|"wasm"
    ),
  )
  @debug.debug_inspect(
    result.jobs[0].steps[1].uses,
    content=(
      #|"wasm://test@v1"
    ),
  )
}

///|
test "plan_workflow: standard workflow with run steps" {
  let yaml =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo hello
    #|      - run: echo world
  let result = @actrun.plan_workflow(yaml)
  @debug.debug_inspect(
    result.workflow_name,
    content=(
      #|"ci"
    ),
  )
  @debug.debug_inspect(result.errors, content="[]")
  @debug.debug_inspect(result.jobs[0].steps.length(), content="2")
  @debug.debug_inspect(
    result.jobs[0].steps[0].kind,
    content=(
      #|"run"
    ),
  )
  @debug.debug_inspect(
    result.jobs[0].steps[0].script,
    content=(
      #|"echo hello"
    ),
  )
}

///|
test "plan_workflow: multi-job with needs" {
  let yaml =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: wasi
    #|    steps:
    #|      - uses: wasm://compile@v1
    #|  test:
    #|    needs: build
    #|    runs-on: wasi
    #|    steps:
    #|      - uses: wasm://test@v1
  let result = @actrun.plan_workflow(yaml)
  @debug.debug_inspect(result.errors, content="[]")
  @debug.debug_inspect(result.jobs.length(), content="2")
  @debug.debug_inspect(result.jobs[1].needs, content="[\"build\"]")
}

///|
test "plan_workflow: wasi rejects run steps" {
  let yaml =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: wasi
    #|    steps:
    #|      - run: echo "not allowed"
  let result = @actrun.plan_workflow(yaml)
  @debug.debug_inspect(result.errors.length() > 0, content="true")
}

///|
test "plan_result_to_json: produces valid json structure" {
  let yaml =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: wasi
    #|    steps:
    #|      - uses: wasm://lint@v1
  let result = @actrun.plan_workflow(yaml)
  let json = @actrun.plan_result_to_json(result)
  @debug.debug_inspect(json.contains("\"workflow\": \"ci\""), content="true")
  @debug.debug_inspect(json.contains("\"wasm://lint@v1\""), content="true")
  @debug.debug_inspect(json.contains("\"wasm\""), content="true")
}

///|
test "plan_workflow: preserves uses step with values" {
  let yaml =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|        with:
    #|          fetch-depth: 1
  let result = @actrun.plan_workflow(yaml)
  @debug.debug_inspect(
    result.jobs[0].steps[0].with_values.get("fetch-depth").unwrap_or(""),
    content=(
      #|"1"
    ),
  )
}

///|
test "plan_result_to_json: includes script env and with values" {
  let yaml =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - env:
    #|          FOO: bar
    #|        run: echo hello
    #|      - uses: actions/checkout@v4
    #|        with:
    #|          fetch-depth: 1
  let result = @actrun.plan_workflow(yaml)
  let json = @actrun.plan_result_to_json(result)
  @debug.debug_inspect(
    json.contains("\"script\": \"echo hello\""),
    content="true",
  )
  @debug.debug_inspect(
    json.contains("\"env\": { \"FOO\": \"bar\" }"),
    content="true",
  )
  @debug.debug_inspect(
    json.contains("\"with\": { \"fetch-depth\": \"1\" }"),
    content="true",
  )
}
