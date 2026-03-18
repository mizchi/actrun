///|
test "snapshot: mermaid single job" {
  let workflow = @ar.new_workflow("test", [
    @ar.new_job("build", [
      @ar.new_run_step("compile", "make build"),
      @ar.new_run_step("test", "make test"),
    ]),
  ])
  inspect(
    workflow_to_mermaid(workflow),
    content=(
      #|graph TD
      #|  build["build (2 steps)"]
    ),
  )
}

///|
test "snapshot: mermaid diamond dependency" {
  let workflow = @ar.new_workflow("ci", [
    @ar.new_job("lint", [@ar.new_run_step("lint", "npm run lint")]),
    @ar.new_job("test", [@ar.new_run_step("test", "npm test")]),
    @ar.new_job("build", [@ar.new_run_step("build", "npm run build")], needs=[
      "lint", "test",
    ]),
    @ar.new_job("deploy", [@ar.new_run_step("deploy", "deploy.sh")], needs=[
      "build",
    ]),
  ])
  inspect(
    workflow_to_mermaid(workflow),
    content=(
      #|graph TD
      #|  lint["lint (1 steps)"]
      #|  test["test (1 steps)"]
      #|  build["build (1 steps)"]
      #|  deploy["deploy (1 steps)"]
      #|  lint --> build
      #|  test --> build
      #|  build --> deploy
    ),
  )
}

///|
test "snapshot: mermaid detail with subgraphs" {
  let workflow = @ar.new_workflow("ci", [
    @ar.new_job("build", [
      @ar.new_uses_step("checkout", "actions/checkout@v4"),
      @ar.new_run_step("compile", "cargo build"),
    ]),
    @ar.new_job("test", [@ar.new_run_step("test", "cargo test")], needs=[
      "build",
    ]),
  ])
  inspect(
    workflow_to_mermaid_detail(workflow),
    content=(
      #|graph TD
      #|  subgraph build ["build"]
      #|    build_s0(["checkout"])
      #|    build_s1(["compile"])
      #|    build_s0 --> build_s1
      #|  end
      #|  subgraph test ["test"]
      #|    test_s0(["test"])
      #|  end
      #|  build --> test
    ),
  )
}

///|
test "snapshot: ascii render simple pipeline" {
  let workflow = @ar.new_workflow("pipeline", [
    @ar.new_job("build", [@ar.new_run_step("build", "make")]),
    @ar.new_job("test", [@ar.new_run_step("test", "make test")], needs=["build"]),
    @ar.new_job("deploy", [@ar.new_run_step("deploy", "deploy.sh")], needs=[
      "test",
    ]),
  ])
  inspect(
    render_workflow_ascii(workflow),
    content=(
      #|┌───────┐
      #|│ build │
      #|└───────┘
      #|    └┐
      #|     │
      #| ┌──────┐
      #| │ test │
      #| └──────┘
      #|     │
      #|     │
      #|┌────────┐
      #|│ deploy │
      #|└────────┘
    ),
  )
}

///|
test "snapshot: ascii render parallel jobs" {
  let workflow = @ar.new_workflow("ci", [
    @ar.new_job("lint", [@ar.new_run_step("lint", "npm run lint")]),
    @ar.new_job("test", [@ar.new_run_step("test", "npm test")]),
    @ar.new_job("e2e", [@ar.new_run_step("e2e", "npx playwright test")]),
    @ar.new_job("merge", [@ar.new_run_step("merge", "echo done")], needs=[
      "lint", "test", "e2e",
    ]),
  ])
  inspect(
    render_workflow_ascii(workflow),
    content=(
      #|┌──────┐    ┌──────┐    ┌─────┐
      #|│ lint │    │ test │    │ e2e │
      #|└──────┘    └──────┘    └─────┘
      #|    └──────────┬┴──────────┘
      #|               │
      #|           ┌───────┐
      #|           │ merge │
      #|           └───────┘
    ),
  )
}

///|
test "snapshot: mermaid from yaml" {
  let yaml =
    #|name: CI
    #|'on': push
    #|jobs:
    #|  lint:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|      - run: npm run lint
    #|  test:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|      - run: npm test
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    needs: [lint, test]
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|      - run: npm run build
    #|  deploy:
    #|    runs-on: ubuntu-latest
    #|    needs: [build]
    #|    steps:
    #|      - run: echo "deploying..."
  let parsed = @ar.parse_workflow_yaml(yaml)
  match parsed.workflow {
    Option::Some(w) =>
      inspect(
        workflow_to_mermaid(w),
        content=(
          #|graph TD
          #|  lint["lint (2 steps)"]
          #|  test["test (2 steps)"]
          #|  build["build (2 steps)"]
          #|  deploy["deploy (1 steps)"]
          #|  lint --> build
          #|  test --> build
          #|  build --> deploy
        ),
      )
    Option::None => inspect("parse failed")
  }
}
