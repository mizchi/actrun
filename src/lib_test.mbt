///|
fn flow_task_by_id(ir : @wf.FlowIr, id : String) -> @wf.FlowTask {
  for task in ir.tasks {
    if task.id == id {
      return task
    }
  }
  abort("missing task: " + id)
}

///|
fn expect_task_plan(plan : ExecutionPlan, id : String) -> TaskPlan {
  match find_task_plan(plan, id) {
    Some(task) => task
    None => abort("missing task plan: " + id)
  }
}

///|
fn expect_workflow(parsed : WorkflowParseResult) -> WorkflowSpec {
  match parsed.workflow {
    Some(workflow) => workflow
    None => abort(parsed.errors.join("\n"))
  }
}

///|
fn expect_local_action(parsed : LocalActionParseResult) -> LocalActionSpec {
  match parsed.action {
    Some(action) => action
    None => abort(parsed.errors.join("\n"))
  }
}

///|
fn test_ensure_dir(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
fn test_absolute_path(path : String) -> String {
  if path.has_prefix("/") {
    return path
  }
  let cwd = @xsys.get_env_var("PWD").unwrap_or(".")
  if cwd.has_suffix("/") {
    cwd + path
  } else {
    cwd + "/" + path
  }
}

///|
fn test_parent_dir(path : String) -> String {
  let mut idx = path.length()
  while idx > 0 {
    idx -= 1
    if path.unsafe_get(idx) == '/' {
      if idx == 0 {
        return "/"
      }
      return String::unsafe_substring(path, start=0, end=idx)
    }
  }
  "."
}

///|
fn test_ensure_dir_all(path : String) -> Unit raise {
  if path.length() == 0 || path == "." || path == "/" || @xfs.path_exists(path) {
    return
  }
  let parent = test_parent_dir(path)
  if parent != path {
    test_ensure_dir_all(parent)
  }
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
fn prepare_local_action_workspace(name : String) -> String raise {
  test_ensure_dir("_build")
  test_ensure_dir("_build/test-workspaces")
  let workspace = "_build/test-workspaces/" + name
  test_ensure_dir(workspace)
  test_absolute_path(workspace)
}

///|
fn prepare_cached_github_action_root(
  owner : String,
  repo : String,
  version : String,
  subpath? : String = "",
) -> String raise {
  test_ensure_dir("_build")
  test_ensure_dir("_build/actrun")
  test_ensure_dir("_build/actrun/github_actions")
  let root = "_build/actrun/github_actions"
  let owner_dir = root + "/" + owner
  let repo_dir = owner_dir + "/" + repo
  let version_dir = repo_dir + "/" + version
  test_ensure_dir(owner_dir)
  test_ensure_dir(repo_dir)
  test_ensure_dir(version_dir)
  let action_root = if subpath.length() > 0 {
    version_dir + "/" + subpath
  } else {
    version_dir
  }
  let segments : Array[String] = []
  for segment in action_root.split("/") {
    let text = segment.to_string()
    if text.length() > 0 {
      segments.push(text)
    }
  }
  let mut current = if action_root.has_prefix("/") { "/" } else { "" }
  for segment in segments {
    current = if current == "/" {
      "/" + segment
    } else if current.length() == 0 {
      segment
    } else {
      current + "/" + segment
    }
    test_ensure_dir(current)
  }
  test_absolute_path(action_root)
}

///|
fn lib_test_set_env_var(key : String, value : String) -> String? {
  let previous = @xsys.get_env_var(key)
  @xsys.set_env_var(key, value)
  previous
}

///|
fn lib_test_restore_env_var(key : String, previous : String?) -> Unit {
  match previous {
    Some(value) => @xsys.set_env_var(key, value)
    None => @xsys.unset_env_var(key)
  }
}

///|
fn prepare_custom_registry_action_root(
  root : String,
  scheme : String,
  name : String,
  version : String,
) -> String raise {
  let action_root = root + "/" + scheme + "/" + name + "/" + version
  test_ensure_dir_all(action_root)
  test_absolute_path(action_root)
}

///|
test "parser: parse simple push workflow" {
  let src =
    #|name: ci
    #|'on': push
    #|env:
    #|  NODE_ENV: test
    #|defaults:
    #|  run:
    #|    shell: bash
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: install
    #|        run: pnpm install
    #|      - name: Test
    #|        run: pnpm test
  let parsed = parse_workflow_yaml(src)
  let workflow = expect_workflow(parsed)

  inspect(workflow.name, content="ci")
  inspect(workflow.env.get("NODE_ENV").unwrap_or(""), content="test")
  inspect(workflow.defaults.shell.unwrap_or(""), content="bash")
  inspect(workflow.jobs.length(), content="1")
  inspect(workflow.jobs[0].id, content="build")
  inspect(workflow.jobs[0].runs_on, content="[\"ubuntu-latest\"]")
  inspect(workflow.jobs[0].steps.length(), content="2")
  inspect(workflow.jobs[0].steps[0].id, content="install")
  inspect(workflow.jobs[0].steps[1].name, content="Test")
}

///|
test "parser: parse push object form and multiline run" {
  let src =
    #|name: ci
    #|on:
    #|  push:
    #|    branches: [main, release/*]
    #|    paths:
    #|      - src/**
    #|      - package.json
    #|jobs:
    #|  build:
    #|    runs-on:
    #|      - ubuntu-latest
    #|    steps:
    #|      - run: echo build
    #|  lint:
    #|    needs: build
    #|    runs-on: ubuntu-latest
    #|    defaults:
    #|      run:
    #|        working-directory: packages/app
    #|    steps:
    #|      - id: lint
    #|        run: |
    #|          pnpm install
    #|          pnpm lint
  let parsed = parse_workflow_yaml(src)
  let workflow = expect_workflow(parsed)

  inspect(workflow.trigger.branches, content="[\"main\", \"release/*\"]")
  inspect(workflow.trigger.paths, content="[\"src/**\", \"package.json\"]")
  inspect(workflow.jobs[1].needs, content="[\"build\"]")
  inspect(
    workflow.jobs[1].defaults.working_directory.unwrap_or(""),
    content="packages/app",
  )
  inspect(
    workflow.jobs[1].steps[0].run.unwrap_or(""),
    content="pnpm install\npnpm lint",
  )
}

///|
test "parser: parse job level if condition" {
  let src =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    if: github.repository == 'mizchi/actrun'
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo ok
  let parsed = parse_workflow_yaml(src)
  let workflow = expect_workflow(parsed)

  inspect(
    workflow.jobs[0].if_condition,
    content="github.repository == 'mizchi/actrun'",
  )
}

///|
test "parser: parse step continue-on-error" {
  let src =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: fail_soft
    #|        continue-on-error: true
    #|        run: exit 1
  let parsed = parse_workflow_yaml(src)
  let workflow = expect_workflow(parsed)

  inspect(workflow.jobs[0].steps[0].continue_on_error, content="true")
}

///|
test "parser: parse checkout uses step" {
  let src =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - uses: actions/checkout@v4
    #|        with:
    #|          fetch-depth: 1
    #|      - run: cat package.json
  let parsed = parse_workflow_yaml(src)
  let workflow = expect_workflow(parsed)

  inspect(
    workflow.jobs[0].steps[0].uses.unwrap_or(""),
    content="actions/checkout@v4",
  )
  inspect(
    workflow.jobs[0].steps[0].with_values.get("fetch-depth").unwrap_or(""),
    content="1",
  )
  inspect(workflow.jobs[0].steps[0].run, content="None")
}

///|
test "parser: parse local composite action yaml" {
  let src =
    #|name: Setup
    #|inputs:
    #|  message:
    #|    default: hello
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - run: echo prepare
    #|      shell: bash
    #|    - id: finish
    #|      run: echo done
  let parsed = parse_local_action_yaml(src)
  let action = expect_local_action(parsed)

  inspect(action.name, content="Setup")
  inspect(action.inputs.get("message").unwrap_or(""), content="hello")
  inspect(action.steps.length(), content="2")
  inspect(action.steps[0].run.unwrap_or(""), content="echo prepare")
  inspect(action.steps[0].shell.unwrap_or(""), content="bash")
  inspect(action.steps[1].id, content="finish")
}

///|
test "parser: accept pull_request trigger" {
  let src =
    #|on: pull_request
    #|jobs:
    #|  test:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo ok
  let parsed = parse_workflow_yaml(src)
  inspect(parsed.errors, content="[]")
  guard parsed.workflow is Some(workflow) else { fail("expected workflow") }
  inspect(workflow.jobs.length(), content="1")
}

///|
test "parser: reject unsupported trigger" {
  let src =
    #|on: schedule
    #|jobs:
    #|  test:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo ok
  let parsed = parse_workflow_yaml(src)
  inspect(
    parsed.errors,
    content="[\"only push and workflow_call triggers are supported in MVP\"]",
  )
}

///|
test "parser: parse matrix exclude rows" {
  let src =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    strategy:
    #|      matrix:
    #|        os: [ubuntu-latest, macos-latest]
    #|        target: [native, js]
    #|        exclude:
    #|          - os: macos-latest
    #|            target: js
    #|    runs-on: ${{ matrix.os }}
    #|    steps:
    #|      - run: printf '%s' '${{ matrix.target }}'
  let parsed = parse_workflow_yaml(src)
  let workflow = expect_workflow(parsed)

  inspect(parsed.errors, content="[]")
  inspect(workflow.jobs[0].matrix.unwrap().rows.length(), content="3")
}

///|
test "parser: parse mixed matrix axes and include rows" {
  let src =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    strategy:
    #|      matrix:
    #|        os: [ubuntu-latest]
    #|        include:
    #|          - os: ubuntu-latest
    #|            target: native
    #|          - os: windows-latest
    #|            target: js
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: printf '%s' ok
  let parsed = parse_workflow_yaml(src)
  let workflow = expect_workflow(parsed)

  inspect(parsed.errors, content="[]")
  inspect(workflow.jobs[0].matrix.unwrap().rows.length(), content="2")
  inspect(
    workflow.jobs[0].matrix.unwrap().rows[0].get("target").unwrap_or(""),
    content="native",
  )
  inspect(
    workflow.jobs[0].matrix.unwrap().rows[1].get("os").unwrap_or(""),
    content="windows-latest",
  )
}

///|
test "parser: parse matrix max parallel" {
  let src =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    strategy:
    #|      max-parallel: 2
    #|      matrix:
    #|        os: [ubuntu-latest, macos-latest]
    #|        target: [native, js]
    #|    runs-on: ${{ matrix.os }}
    #|    steps:
    #|      - run: printf '%s|%s' '${{ matrix.os }}' '${{ matrix.target }}'
  let parsed = parse_workflow_yaml(src)
  let workflow = expect_workflow(parsed)

  inspect(parsed.errors, content="[]")
  inspect(workflow.jobs[0].matrix.unwrap().rows.length(), content="4")
  inspect(workflow.jobs[0].matrix.unwrap().max_parallel, content="Some(2)")
}

///|
test "parser: reject non-positive matrix max parallel" {
  let src =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    strategy:
    #|      max-parallel: 0
    #|      matrix:
    #|        os: [ubuntu-latest]
    #|    runs-on: ${{ matrix.os }}
    #|    steps:
    #|      - run: printf '%s' ok
  let parsed = parse_workflow_yaml(src)

  inspect(parsed.workflow is None, content="true")
  inspect(
    parsed.errors,
    content="[\"jobs.build.strategy.max-parallel must be positive\"]",
  )
}

///|
test "push trigger: branch and path filters" {
  let trigger = new_push_trigger(branches=["main"], paths=["src/*", "README.md"])
  let matched = new_push_event("main", ["src/lib.mbt"])
  let wrong_branch = new_push_event("feature/test", ["src/lib.mbt"])
  let wrong_path = new_push_event("main", ["docs/spec.md"])

  assert_eq(matches_push_trigger(trigger, matched), true)
  assert_eq(matches_push_trigger(trigger, wrong_branch), false)
  assert_eq(matches_push_trigger(trigger, wrong_path), false)
}

///|
test "push trigger: paths ignore skips fully ignored changes" {
  let trigger = new_push_trigger(paths_ignore=["docs/*", "*.md"])

  assert_eq(
    matches_push_trigger(trigger, new_push_event("main", ["docs/spec.md"])),
    false,
  )
  assert_eq(
    matches_push_trigger(
      trigger,
      new_push_event("main", ["docs/spec.md", "src/main.mbt"]),
    ),
    true,
  )
}

///|
test "lowering: jobs and steps become bitflow tasks" {
  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [
          new_run_step("install", "pnpm install"),
          new_run_step("test", "pnpm test", env={ "STEP_ONLY": "1" }),
        ],
        env={ "JOB_ONLY": "1", "LEVEL": "job" },
      ),
      new_job(
        "lint",
        [new_run_step("lint", "pnpm lint")],
        needs=["build"],
        defaults=new_run_defaults(working_directory=Some("packages/app")),
      ),
    ],
    env={ "GLOBAL": "1", "LEVEL": "workflow" },
    defaults=new_run_defaults(shell=Some("bash")),
  )

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  inspect(result.ir.nodes.length(), content="2")
  inspect(result.ir.tasks.length(), content="5")
  inspect(
    result.ir.entry_targets,
    content="[\"build/__finish\", \"lint/__finish\"]",
  )

  let build_test = flow_task_by_id(result.ir, "build/test")
  inspect(build_test.needs, content="[\"build/install\"]")

  let lint_step = flow_task_by_id(result.ir, "lint/lint")
  inspect(lint_step.needs, content="[\"build/__finish\"]")
  inspect(lint_step.cwd, content="packages/app")

  let build_test_plan = expect_task_plan(result.plan, "build/test")
  inspect(build_test_plan.shell, content="bash")
  inspect(build_test_plan.env.get("GLOBAL").unwrap_or(""), content="1")
  inspect(build_test_plan.env.get("JOB_ONLY").unwrap_or(""), content="1")
  inspect(build_test_plan.env.get("STEP_ONLY").unwrap_or(""), content="1")
  inspect(build_test_plan.env.get("LEVEL").unwrap_or(""), content="job")

  let build_finish_plan = expect_task_plan(result.plan, "build/__finish")
  inspect(build_finish_plan.kind, content="barrier")
}

///|
test "lowering: checkout uses step becomes checkout task" {
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("checkout", "builtin://checkout"),
      new_run_step("verify", "cat package.json"),
    ]),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  inspect(result.ir.tasks.length(), content="3")

  let checkout_task = flow_task_by_id(result.ir, "test/checkout")
  inspect(checkout_task.needs, content="[]")

  let verify_task = flow_task_by_id(result.ir, "test/verify")
  inspect(verify_task.needs, content="[\"test/checkout\"]")

  let checkout_plan = expect_task_plan(result.plan, "test/checkout")
  inspect(checkout_plan.kind, content="action")
  inspect(checkout_plan.script, content="")
  inspect(checkout_plan.action.unwrap().backend, content="builtin")
  inspect(checkout_plan.action.unwrap().kind, content="checkout")
  inspect(checkout_plan.action.unwrap().uses, content="builtin://checkout")
}

///|
test "lowering: checkout with values become INPUT env" {
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("checkout", "actions/checkout@v4", with_values={
        "path": "repo",
        "sparse-checkout": "README.md\n.github",
      }),
    ]),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  let checkout_plan = expect_task_plan(result.plan, "test/checkout")
  inspect(checkout_plan.action.unwrap().kind, content="checkout")
  inspect(checkout_plan.env.get("INPUT_PATH").unwrap_or(""), content="repo")
  inspect(
    checkout_plan.env.get("INPUT_SPARSE_CHECKOUT").unwrap_or(""),
    content="README.md\n.github",
  )
}

///|
test "lowering: unsupported uses step is rejected" {
  let workflow = new_workflow("ci", [
    new_job("test", [new_uses_step("setup", "bit://std/cache@v1")]),
  ])

  let result = lower_push_workflow(workflow)

  inspect(
    result.errors,
    content="[\"step 'test/setup' action 'bit://std/cache@v1' is not supported in MVP\"]",
  )
}

///|
test "lowering: custom registry composite action expands from registry root" {
  let workspace = prepare_local_action_workspace("custom-registry-composite")
  let registry_root = prepare_local_action_workspace(
    "custom-registry-composite-root",
  )
  let previous_root = lib_test_set_env_var(
    "ACTRUN_ACTION_REGISTRY_ROOT", registry_root,
  )
  let action_root = prepare_custom_registry_action_root(
    registry_root, "bit", "std/cache", "v1",
  )
  let manifest =
    #|name: cache
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: write
    #|      run: printf '%s' '${{ inputs.message }}'
    #|      shell: bash
  @xfs.write_string_to_file(action_root + "/action.yml", manifest)
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("setup", "bit://std/cache@v1", with_values={
        "message": "from-registry",
      }),
    ]),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)
  lib_test_restore_env_var("ACTRUN_ACTION_REGISTRY_ROOT", previous_root)

  inspect(result.errors, content="[]")
  let write_plan = expect_task_plan(result.plan, "test/setup__write")
  inspect(write_plan.kind, content="run")
  inspect(write_plan.script, content="printf '%s' 'from-registry'")
}

///|
test "lowering: custom registry node action resolves backend from manifest" {
  let workspace = prepare_local_action_workspace("custom-registry-node")
  let registry_root = prepare_local_action_workspace(
    "custom-registry-node-root",
  )
  let previous_root = lib_test_set_env_var(
    "ACTRUN_ACTION_REGISTRY_ROOT", registry_root,
  )
  let action_root = prepare_custom_registry_action_root(
    registry_root, "bit", "std/cache", "v1",
  )
  let manifest =
    #|name: cache
    #|inputs:
    #|  message:
    #|    default: hello
    #|runs:
    #|  using: node20
    #|  main: index.sh
  @xfs.write_string_to_file(action_root + "/action.yml", manifest)
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("setup", "bit://std/cache@v1", with_values={
        "message": "from-node",
      }),
    ]),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)
  lib_test_restore_env_var("ACTRUN_ACTION_REGISTRY_ROOT", previous_root)

  inspect(result.errors, content="[]")
  let setup_plan = expect_task_plan(result.plan, "test/setup")
  inspect(setup_plan.kind, content="action")
  inspect(setup_plan.action.unwrap().backend, content="node")
  inspect(
    setup_plan.action.unwrap().entrypoint.unwrap_or(""),
    content=action_root + "/index.sh",
  )
  inspect(
    setup_plan.env.get("INPUT_MESSAGE").unwrap_or(""),
    content="from-node",
  )
}

///|
test "lowering: custom registry docker action resolves backend from manifest" {
  let workspace = prepare_local_action_workspace("custom-registry-docker")
  let registry_root = prepare_local_action_workspace(
    "custom-registry-docker-root",
  )
  let previous_root = lib_test_set_env_var(
    "ACTRUN_ACTION_REGISTRY_ROOT", registry_root,
  )
  let action_root = prepare_custom_registry_action_root(
    registry_root, "bit", "std/docker-cache", "v1",
  )
  let manifest =
    #|name: cache
    #|inputs:
    #|  message:
    #|    default: hello
    #|runs:
    #|  using: docker
    #|  image: docker://alpine:3.21
    #|  entrypoint: echo
    #|  args:
    #|    - ${{ inputs.message }}
  @xfs.write_string_to_file(action_root + "/action.yml", manifest)
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("setup", "bit://std/docker-cache@v1", with_values={
        "message": "from-docker",
      }),
    ]),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)
  lib_test_restore_env_var("ACTRUN_ACTION_REGISTRY_ROOT", previous_root)

  inspect(result.errors, content="[]")
  let setup_plan = expect_task_plan(result.plan, "test/setup")
  inspect(setup_plan.kind, content="action")
  inspect(setup_plan.action.unwrap().backend, content="docker")
  inspect(setup_plan.action.unwrap().image.unwrap_or(""), content="alpine:3.21")
  inspect(setup_plan.action.unwrap().entrypoint.unwrap_or(""), content="echo")
  inspect(setup_plan.action.unwrap().args, content="[\"from-docker\"]")
}

///|
test "lowering: docker uses step becomes docker action task" {
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("image", "docker://alpine:3.21"),
      new_run_step("verify", "echo ok"),
    ]),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  let image_plan = expect_task_plan(result.plan, "test/image")
  inspect(image_plan.kind, content="action")
  inspect(image_plan.action.unwrap().backend, content="docker")
  inspect(image_plan.action.unwrap().kind, content="docker-image")
  inspect(image_plan.action.unwrap().uses, content="docker://alpine:3.21")

  let verify_task = flow_task_by_id(result.ir, "test/verify")
  inspect(verify_task.needs, content="[\"test/image\"]")
}

///|
test "lowering: wasm uses step becomes wasm action task" {
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("module", "wasm://std/echo@v1"),
      new_run_step("verify", "echo ok"),
    ]),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  let module_plan = expect_task_plan(result.plan, "test/module")
  inspect(module_plan.kind, content="action")
  inspect(module_plan.action.unwrap().backend, content="wasm")
  inspect(module_plan.action.unwrap().kind, content="wasm-module")
  inspect(module_plan.action.unwrap().capabilities.wasm, content="true")
  inspect(
    module_plan.action.unwrap().entrypoint.unwrap_or(""),
    content="std/echo@v1",
  )

  let verify_task = flow_task_by_id(result.ir, "test/verify")
  inspect(verify_task.needs, content="[\"test/module\"]")
}

///|
test "lowering: builtin artifact actions receive with values as INPUT env" {
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("upload", "actions/upload-artifact@v4", with_values={
        "name": "bundle",
        "path": "dist/result.txt",
      }),
      new_uses_step("download", "actions/download-artifact@v4", with_values={
        "name": "bundle",
        "path": "restored",
      }),
    ]),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  let upload_plan = expect_task_plan(result.plan, "test/upload")
  inspect(upload_plan.action.unwrap().backend, content="builtin")
  inspect(upload_plan.action.unwrap().kind, content="upload-artifact")
  inspect(upload_plan.env.get("INPUT_NAME").unwrap_or(""), content="bundle")
  inspect(
    upload_plan.env.get("INPUT_PATH").unwrap_or(""),
    content="dist/result.txt",
  )

  let download_plan = expect_task_plan(result.plan, "test/download")
  inspect(download_plan.action.unwrap().kind, content="download-artifact")
  inspect(download_plan.env.get("INPUT_NAME").unwrap_or(""), content="bundle")
  inspect(download_plan.env.get("INPUT_PATH").unwrap_or(""), content="restored")
}

///|
test "lowering: builtin cache actions receive with values as INPUT env" {
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("restore", "actions/cache/restore@v4", with_values={
        "key": "bundle-v1",
        "path": "cache-dir",
      }),
      new_uses_step("save", "actions/cache/save@v4", with_values={
        "key": "bundle-v1",
        "path": "cache-dir",
      }),
    ]),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  let restore_plan = expect_task_plan(result.plan, "test/restore")
  inspect(restore_plan.action.unwrap().backend, content="builtin")
  inspect(restore_plan.action.unwrap().kind, content="cache-restore")
  inspect(restore_plan.env.get("INPUT_KEY").unwrap_or(""), content="bundle-v1")
  inspect(restore_plan.env.get("INPUT_PATH").unwrap_or(""), content="cache-dir")

  let save_plan = expect_task_plan(result.plan, "test/save")
  inspect(save_plan.action.unwrap().kind, content="cache-save")
  inspect(save_plan.env.get("INPUT_KEY").unwrap_or(""), content="bundle-v1")
  inspect(save_plan.env.get("INPUT_PATH").unwrap_or(""), content="cache-dir")
}

///|
test "lowering: builtin cache action schedules deferred post save" {
  let workflow = new_workflow("ci", [
    new_job("test", [
      new_uses_step("cache", "actions/cache@v4", with_values={
        "key": "bundle-v1",
        "path": "cache-dir",
      }),
      new_run_step("verify", "echo ok"),
    ]),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")

  let cache_plan = expect_task_plan(result.plan, "test/cache")
  inspect(cache_plan.action.unwrap().kind, content="cache")
  inspect(cache_plan.action_scope, content="Some(\"test/cache\")")
  inspect(cache_plan.env.get("INPUT_KEY").unwrap_or(""), content="bundle-v1")

  let post_plan = expect_task_plan(result.plan, "test/cache__post")
  inspect(post_plan.action.unwrap().kind, content="cache-save-post")
  inspect(post_plan.action_scope, content="Some(\"test/cache\")")
  inspect(post_plan.requires_action_started, content="true")
  inspect(post_plan.if_condition, content="success()")

  let verify_task = flow_task_by_id(result.ir, "test/verify")
  inspect(verify_task.needs, content="[\"test/cache\"]")
  let post_task = flow_task_by_id(result.ir, "test/cache__post")
  inspect(post_task.needs, content="[\"test/verify\"]")
}

///|
test "lowering: local composite action expands inner steps" {
  let workspace = prepare_local_action_workspace("lower-local-action")
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/actions")
  test_ensure_dir(workspace + "/.github/actions/setup")
  let action_src =
    #|name: Setup
    #|inputs:
    #|  message:
    #|    default: default-message
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: prepare
    #|      run: printf '%s' "$FROM_INNER" > local.txt
    #|      shell: bash
    #|      env:
    #|        FROM_INNER: ${{ inputs.message }}
    #|    - run: cat local.txt
  @xfs.write_string_to_file(
    workspace + "/.github/actions/setup/action.yml",
    action_src,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "test",
      [
        new_uses_step("setup", "./.github/actions/setup", with_values={
          "message": "from-input",
        }),
        new_run_step("verify", "cat local.txt"),
      ],
      defaults=new_run_defaults(shell=Some("sh")),
    ),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  inspect(result.ir.tasks.length(), content="4")

  let first = flow_task_by_id(result.ir, "test/setup__prepare")
  inspect(first.needs, content="[]")
  inspect(first.cmd, content="printf '%s' \"$FROM_INNER\" > local.txt")

  let second = flow_task_by_id(result.ir, "test/setup__step_2")
  inspect(second.needs, content="[\"test/setup__prepare\"]")

  let verify = flow_task_by_id(result.ir, "test/verify")
  inspect(verify.needs, content="[\"test/setup__step_2\"]")

  let first_plan = expect_task_plan(result.plan, "test/setup__prepare")
  inspect(first_plan.kind, content="run")
  inspect(first_plan.shell, content="bash")
  inspect(first_plan.env.get("FROM_INNER").unwrap_or(""), content="from-input")
  inspect(first_plan.action_scope.unwrap_or(""), content="test/setup")

  let verify_plan = expect_task_plan(result.plan, "test/verify")
  inspect(verify_plan.action_scope.unwrap_or(""), content="")
}

///|
test "lowering: local composite action expands nested local action" {
  let workspace = prepare_local_action_workspace("lower-local-action-nested")
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/actions")
  test_ensure_dir(workspace + "/.github/actions/setup")
  test_ensure_dir(workspace + "/.github/actions/setup/nested")
  let nested_src =
    #|name: Nested
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: write
    #|      run: printf '%s' nested-ok > nested.txt
    #|      shell: bash
  @xfs.write_string_to_file(
    workspace + "/.github/actions/setup/nested/action.yml",
    nested_src,
  )
  let action_src =
    #|name: Setup
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: child
    #|      uses: ./nested
    #|    - id: show
    #|      run: cat nested.txt
  @xfs.write_string_to_file(
    workspace + "/.github/actions/setup/action.yml",
    action_src,
  )

  let workflow = new_workflow("ci", [
    new_job("test", [new_uses_step("setup", "./.github/actions/setup")]),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let write = flow_task_by_id(result.ir, "test/setup__child__write")
  inspect(write.needs, content="[]")

  let show = flow_task_by_id(result.ir, "test/setup__show")
  inspect(show.needs, content="[\"test/setup__child__write\"]")

  let write_plan = expect_task_plan(result.plan, "test/setup__child__write")
  inspect(write_plan.action_scope.unwrap_or(""), content="test/setup__child")
  let show_plan = expect_task_plan(result.plan, "test/setup__show")
  inspect(show_plan.action_scope.unwrap_or(""), content="test/setup")
}

///|
test "lowering: local composite action nested builtin uses becomes action task" {
  let workspace = prepare_local_action_workspace(
    "lower-local-action-nested-builtin",
  )
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/actions")
  test_ensure_dir(workspace + "/.github/actions/setup")
  let action_src =
    #|name: Setup
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: checkout
    #|      uses: builtin://checkout
    #|    - id: show
    #|      run: cat tracked.txt
  @xfs.write_string_to_file(
    workspace + "/.github/actions/setup/action.yml",
    action_src,
  )

  let workflow = new_workflow("ci", [
    new_job("test", [new_uses_step("setup", "./.github/actions/setup")]),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let checkout_plan = expect_task_plan(result.plan, "test/setup__checkout")
  inspect(checkout_plan.kind, content="action")
  inspect(checkout_plan.action.unwrap().uses, content="builtin://checkout")
  let show = flow_task_by_id(result.ir, "test/setup__show")
  inspect(show.needs, content="[\"test/setup__checkout\"]")
}

///|
test "lowering: cached github repo composite action with subpath expands inner steps" {
  let workspace = prepare_local_action_workspace("lower-github-repo-action")
  let action_root = prepare_cached_github_action_root(
    "mizchi-test",
    "demo-action",
    "v1",
    subpath="composite",
  )
  let action_src =
    #|name: Remote
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: write
    #|      run: printf '%s' remote-ok > remote.txt
    #|      shell: bash
  @xfs.write_string_to_file(action_root + "/action.yml", action_src)

  let workflow = new_workflow("ci", [
    new_job(
      "test",
      [
        new_uses_step("remote", "mizchi-test/demo-action/composite@v1"),
        new_run_step("verify", "cat remote.txt"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let write = flow_task_by_id(result.ir, "test/remote__write")
  inspect(write.needs, content="[]")
  let write_plan = expect_task_plan(result.plan, "test/remote__write")
  inspect(
    write_plan.env.get("GITHUB_ACTION_REPOSITORY").unwrap_or(""),
    content="mizchi-test/demo-action",
  )
  inspect(write_plan.env.get("GITHUB_ACTION_REF").unwrap_or(""), content="v1")
  let verify = flow_task_by_id(result.ir, "test/verify")
  inspect(verify.needs, content="[\"test/remote__write\"]")
}

///|
test "lowering: cached github repo node action becomes node task" {
  let workspace = prepare_local_action_workspace("lower-github-node-action")
  let action_root = prepare_cached_github_action_root(
    "mizchi-test",
    "node-action",
    "v1",
    subpath="action",
  )
  let action_src =
    #|name: Remote Node
    #|inputs:
    #|  message:
    #|    default: default-message
    #|runs:
    #|  using: node20
    #|  main: main.sh
  @xfs.write_string_to_file(action_root + "/action.yml", action_src)

  let workflow = new_workflow("ci", [
    new_job(
      "test",
      [
        new_uses_step("remote", "mizchi-test/node-action/action@v1", with_values={
          "message": "from-input",
        }),
        new_run_step("verify", "echo ok"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let remote_plan = expect_task_plan(result.plan, "test/remote")
  inspect(remote_plan.kind, content="action")
  inspect(remote_plan.action.unwrap().backend, content="node")
  inspect(remote_plan.action.unwrap().capabilities.host, content="true")
  inspect(remote_plan.action.unwrap().capabilities.docker, content="false")
  inspect(remote_plan.action.unwrap().kind, content="node-script")
  inspect(
    remote_plan.action.unwrap().uses,
    content="mizchi-test/node-action/action@v1",
  )
  inspect(
    remote_plan.action.unwrap().entrypoint.unwrap_or(""),
    content=action_root + "/main.sh",
  )
  inspect(
    remote_plan.action.unwrap().action_path.unwrap_or(""),
    content=action_root,
  )
  inspect(
    remote_plan.env.get("INPUT_MESSAGE").unwrap_or(""),
    content="from-input",
  )
  inspect(
    remote_plan.env.get("GITHUB_ACTION_REPOSITORY").unwrap_or(""),
    content="mizchi-test/node-action",
  )
  inspect(remote_plan.env.get("GITHUB_ACTION_REF").unwrap_or(""), content="v1")
  inspect(
    remote_plan.env.get("GITHUB_ACTION_PATH").unwrap_or(""),
    content=action_root,
  )
}

///|
test "lowering: job outputs are carried into execution plan" {
  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "produce", "printf 'artifact_id=build-42\\n' >> \"$GITHUB_OUTPUT\"",
        ),
      ],
      outputs={ "artifact_id": "${{ steps.produce.outputs.artifact_id }}" },
    ),
    new_job(
      "consume",
      [
        new_run_step(
          "read", "printf '%s' \"${{ needs.build.outputs.artifact_id }}\"",
        ),
      ],
      needs=["build"],
    ),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_outputs
    .get("build")
    .unwrap_or({})
    .get("artifact_id")
    .unwrap_or(""),
    content="${{ steps.produce.outputs.artifact_id }}",
  )
  inspect(
    result.plan.job_needs.get("consume").unwrap_or([]),
    content="[\"build\"]",
  )
}

///|
test "lowering: cached github repo docker action becomes docker task" {
  let workspace = prepare_local_action_workspace("lower-github-docker-action")
  let action_root = prepare_cached_github_action_root(
    "mizchi-test",
    "docker-action",
    "v1",
    subpath="action",
  )
  let action_src =
    #|name: Remote Docker
    #|inputs:
    #|  message:
    #|    default: default-message
    #|runs:
    #|  using: docker
    #|  image: Dockerfile
    #|  entrypoint: /bin/sh
    #|  args:
    #|    - -c
    #|    - printf '%s' "$INPUT_MESSAGE" > "$GITHUB_WORKSPACE/docker.txt"
  @xfs.write_string_to_file(action_root + "/action.yml", action_src)
  @xfs.write_string_to_file(action_root + "/Dockerfile", "FROM alpine:3.21\n")

  let workflow = new_workflow("ci", [
    new_job(
      "test",
      [
        new_uses_step("remote", "mizchi-test/docker-action/action@v1", with_values={
          "message": "from-input",
        }),
        new_run_step("verify", "echo ok"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let remote_plan = expect_task_plan(result.plan, "test/remote")
  inspect(remote_plan.kind, content="action")
  inspect(remote_plan.action.unwrap().backend, content="docker")
  inspect(remote_plan.action.unwrap().capabilities.host, content="false")
  inspect(remote_plan.action.unwrap().capabilities.docker, content="true")
  inspect(remote_plan.action.unwrap().kind, content="docker-action")
  inspect(
    remote_plan.action.unwrap().image.unwrap_or(""),
    content=action_root + "/Dockerfile",
  )
  inspect(
    remote_plan.action.unwrap().entrypoint.unwrap_or(""),
    content="/bin/sh",
  )
  inspect(
    remote_plan.action.unwrap().args,
    content="[\"-c\", \"printf '%s' \\\"$INPUT_MESSAGE\\\" > \\\"$GITHUB_WORKSPACE/docker.txt\\\"\"]",
  )
  inspect(
    remote_plan.env.get("INPUT_MESSAGE").unwrap_or(""),
    content="from-input",
  )
}

///|
test "lowering: cached github repo docker action schedules post lifecycle at job end" {
  let workspace = prepare_local_action_workspace(
    "lower-github-docker-lifecycle",
  )
  let action_root = prepare_cached_github_action_root(
    "mizchi-test",
    "docker-lifecycle",
    "v1",
    subpath="action",
  )
  let action_src =
    #|name: Remote Docker Lifecycle
    #|runs:
    #|  using: docker
    #|  image: Dockerfile
    #|  pre-entrypoint: pre.sh
    #|  entrypoint: main.sh
    #|  post-entrypoint: post.sh
  @xfs.write_string_to_file(action_root + "/action.yml", action_src)
  @xfs.write_string_to_file(action_root + "/Dockerfile", "FROM alpine:3.21\n")

  let workflow = new_workflow("ci", [
    new_job(
      "test",
      [
        new_uses_step("remote", "mizchi-test/docker-lifecycle/action@v1"),
        new_run_step("verify", "echo ok"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let pre = flow_task_by_id(result.ir, "test/remote__pre")
  inspect(pre.needs, content="[]")
  let main = flow_task_by_id(result.ir, "test/remote")
  inspect(main.needs, content="[\"test/remote__pre\"]")
  let verify = flow_task_by_id(result.ir, "test/verify")
  inspect(verify.needs, content="[\"test/remote\"]")
  let post = flow_task_by_id(result.ir, "test/remote__post")
  inspect(post.needs, content="[\"test/verify\"]")
  let post_plan = expect_task_plan(result.plan, "test/remote__post")
  inspect(post_plan.if_condition, content="always()")
  inspect(post_plan.action_scope.unwrap_or(""), content="test/remote")
}

///|
test "lowering: cached github repo node action schedules post lifecycle at job end" {
  let workspace = prepare_local_action_workspace("lower-github-node-lifecycle")
  let action_root = prepare_cached_github_action_root(
    "mizchi-test",
    "node-lifecycle",
    "v1",
    subpath="action",
  )
  let action_src =
    #|name: Remote Node Lifecycle
    #|runs:
    #|  using: node20
    #|  pre: pre.sh
    #|  main: main.sh
    #|  post: post.sh
  @xfs.write_string_to_file(action_root + "/action.yml", action_src)

  let workflow = new_workflow("ci", [
    new_job(
      "test",
      [
        new_uses_step("remote", "mizchi-test/node-lifecycle/action@v1"),
        new_run_step("verify", "echo ok"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let pre = flow_task_by_id(result.ir, "test/remote__pre")
  inspect(pre.needs, content="[]")
  let main = flow_task_by_id(result.ir, "test/remote")
  inspect(main.needs, content="[\"test/remote__pre\"]")
  let verify = flow_task_by_id(result.ir, "test/verify")
  inspect(verify.needs, content="[\"test/remote\"]")
  let post = flow_task_by_id(result.ir, "test/remote__post")
  inspect(post.needs, content="[\"test/verify\"]")
  let post_plan = expect_task_plan(result.plan, "test/remote__post")
  inspect(post_plan.if_condition, content="always()")
  inspect(post_plan.action_scope.unwrap_or(""), content="test/remote")
}

///|
test "lowering: step if status functions are accepted" {
  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step("fail", "exit 1"),
        new_run_step("always_step", "echo always", if_condition="always()"),
        new_run_step("failure_step", "echo failure", if_condition="failure()"),
        new_run_step(
          "cancelled_step",
          "echo cancelled",
          if_condition="cancelled()",
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)

  inspect(lowered.errors, content="[]")
  inspect(
    expect_task_plan(lowered.plan, "build/always_step").if_condition,
    content="always()",
  )
  inspect(
    expect_task_plan(lowered.plan, "build/failure_step").if_condition,
    content="failure()",
  )
  inspect(
    expect_task_plan(lowered.plan, "build/cancelled_step").if_condition,
    content="cancelled()",
  )
}

///|
test "lowering: step continue-on-error is accepted" {
  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step("fail_soft", "exit 1", continue_on_error="true"),
        new_run_step("after", "echo after"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)

  inspect(lowered.errors, content="[]")
  inspect(
    expect_task_plan(lowered.plan, "build/fail_soft").continue_on_error,
    content="true",
  )
}

///|
#cfg(target="native")
async test "lowering: github repo action cache miss fetches and expands composite action" {
  let workspace = prepare_local_action_workspace(
    "lower-github-repo-remote-fetch",
  )
  let action_uses = "mizchi-fetch-lib/demo-action-lib/composite@v1"
  let repo_cache_root = "_build/actrun/github_actions/mizchi-fetch-lib/demo-action-lib/v1"
  let log_path = workspace + "/git.log"
  test_support_remove_tree(repo_cache_root)
  let action_src =
    #|name: Remote
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: write
    #|      run: printf '%s' fetched-remote > remote.txt
    #|      shell: bash
  let git_path = test_support_prepare_fake_github_git_bin(
    workspace, action_src, log_path,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "test",
      [
        new_uses_step("remote", action_uses),
        new_run_step("verify", "cat remote.txt"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let prefetch = prefetch_workflow_github_actions_native(
    workflow,
    workspace,
    git_bin=Some(git_path),
  )
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(prefetch.errors, content="[]")
  inspect(prefetch.fetched.length(), content="1")
  inspect(result.errors, content="[]")
  let write = flow_task_by_id(result.ir, "test/remote__write")
  inspect(write.needs, content="[]")
  assert_eq(@xfs.path_exists(repo_cache_root + "/composite/action.yml"), true)
  let log = @xfs.read_file_to_string(log_path)
  assert_eq(log.contains("clone\n--depth\n1\n--branch\nv1\n"), true)
  assert_eq(
    log.contains("https://github.com/mizchi-fetch-lib/demo-action-lib.git"),
    true,
  )
}

///|
test "lowering: local composite action rejects unsupported nested uses" {
  let workspace = prepare_local_action_workspace(
    "lower-local-action-nested-unsupported",
  )
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/actions")
  test_ensure_dir(workspace + "/.github/actions/setup")
  let action_src =
    #|name: Setup
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: node
    #|      uses: bit://std/cache@v1
  @xfs.write_string_to_file(
    workspace + "/.github/actions/setup/action.yml",
    action_src,
  )

  let workflow = new_workflow("ci", [
    new_job("test", [new_uses_step("setup", "./.github/actions/setup")]),
  ])

  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(
    result.errors,
    content="[\"step 'test/setup__node' action 'bit://std/cache@v1' is not supported in MVP\"]",
  )
}

///|
test "lowering: matrix job fan-in expands downstream needs" {
  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [new_run_step("emit", "printf '%s' '${{ matrix.target }}'")],
      matrix=Some(new_job_matrix([{ "target": "native" }, { "target": "js" }])),
    ),
    new_job("consume", [new_run_step("read", "printf '%s' ok")], needs=["build"]),
  ])

  let result = lower_push_workflow(workflow)
  let consume = flow_task_by_id(result.ir, "consume/read")

  inspect(result.errors, content="[]")
  inspect(
    consume.needs,
    content="[\"build__matrix_1/__finish\", \"build__matrix_2/__finish\"]",
  )
  inspect(
    result.plan.job_needs.get("consume").unwrap_or([]),
    content="[\"build\"]",
  )
  inspect(
    result.plan.job_need_targets
    .get("consume")
    .unwrap_or({})
    .get("build")
    .unwrap_or([]),
    content="[\"build__matrix_1\", \"build__matrix_2\"]",
  )
}

///|
test "lowering: matrix outputs are carried into execution plan" {
  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "produce", "printf '%s=%s\\n' '${{ matrix.target }}' '${{ matrix.target }}' >> \"$GITHUB_OUTPUT\"",
        ),
      ],
      outputs={
        "native": "${{ steps.produce.outputs.native }}",
        "js": "${{ steps.produce.outputs.js }}",
      },
      matrix=Some(new_job_matrix([{ "target": "native" }, { "target": "js" }])),
    ),
    new_job(
      "consume",
      [
        new_run_step(
          "read", "printf '%s' \"${{ needs.build.outputs.native }}\"",
        ),
      ],
      needs=["build"],
    ),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_outputs
    .get("build__matrix_1")
    .unwrap_or({})
    .get("native")
    .unwrap_or(""),
    content="${{ steps.produce.outputs.native }}",
  )
  inspect(
    result.plan.job_outputs
    .get("build__matrix_2")
    .unwrap_or({})
    .get("js")
    .unwrap_or(""),
    content="${{ steps.produce.outputs.js }}",
  )
}

///|
test "lowering: matrix jobs retain fail-fast metadata" {
  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [new_run_step("emit", "printf '%s' '${{ matrix.variant }}'")],
      matrix=Some(
        new_job_matrix(
          [{ "variant": "ok" }, { "variant": "fail" }, { "variant": "late" }],
          fail_fast=true,
        ),
      ),
    ),
  ])

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_matrix_groups.get("build__matrix_1").unwrap_or(""),
    content="build",
  )
  inspect(
    result.plan.job_matrix_groups.get("build__matrix_3").unwrap_or(""),
    content="build",
  )
  inspect(
    result.plan.job_matrix_fail_fast.get("build__matrix_1").unwrap_or(false),
    content="true",
  )
  inspect(
    result.plan.job_matrix_fail_fast.get("build__matrix_3").unwrap_or(false),
    content="true",
  )
}

///|
test "parser/lowering: workflow and job permissions are silently ignored" {
  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [new_run_step("show", "printf '%s' hi")],
        permissions=Some(
          new_permissions_spec(values={ "contents": "read", "issues": "write" }),
        ),
      ),
    ],
    permissions=Some(new_permissions_spec(values={ "_": "read-all" })),
  )

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
}

///|
test "security: permissions do not leak into task plan env" {
  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [new_run_step("check", "echo test")],
        permissions=Some(
          new_permissions_spec(values={
            "contents": "write",
            "packages": "write",
          }),
        ),
      ),
    ],
    permissions=Some(new_permissions_spec(values={ "_": "write-all" })),
  )

  let result = lower_push_workflow(workflow)
  inspect(result.errors, content="[]")
  // Permissions should not appear in task plan env
  for task in result.plan.tasks {
    inspect(task.env.get("PERMISSIONS_CONTENTS"), content="None")
    inspect(task.env.get("GITHUB_TOKEN_PERMISSIONS"), content="None")
  }
}

///|
test "security: permissions do not affect execution plan structure" {
  // Same workflow with and without permissions should produce identical plans
  let with_perms = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [new_run_step("step1", "echo one"), new_run_step("step2", "echo two")],
        permissions=Some(new_permissions_spec(values={ "contents": "write" })),
      ),
    ],
    permissions=Some(new_permissions_spec(values={ "_": "read-all" })),
  )
  let without_perms = new_workflow("ci", [
    new_job("build", [
      new_run_step("step1", "echo one"),
      new_run_step("step2", "echo two"),
    ]),
  ])

  let result_with = lower_push_workflow(with_perms)
  let result_without = lower_push_workflow(without_perms)

  inspect(result_with.errors, content="[]")
  inspect(result_without.errors, content="[]")
  // Same number of tasks
  inspect(
    result_with.plan.tasks.length() == result_without.plan.tasks.length(),
    content="true",
  )
  // Same task IDs
  for i in 0..<result_with.plan.tasks.length() {
    inspect(
      result_with.plan.tasks[i].id == result_without.plan.tasks[i].id,
      content="true",
    )
  }
}

///|
test "parser/lowering: workflow and job concurrency are silently ignored" {
  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [new_run_step("show", "printf '%s' hi")],
        concurrency=Some(
          new_concurrency_spec("job-group", cancel_in_progress=Some("true")),
        ),
      ),
    ],
    concurrency=Some(
      new_concurrency_spec(
        "workflow-group",
        cancel_in_progress=Some("${{ github.ref_name == 'main' }}"),
      ),
    ),
  )

  let result = lower_push_workflow(workflow)

  inspect(result.errors, content="[]")
}

///|
test "parser/lowering: workflow_call is parsed and rejected in MVP" {
  let src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      target:
    #|        description: target environment
    #|        required: true
    #|        type: string
    #|    outputs:
    #|      build_id:
    #|        description: build identifier
    #|        value: ${{ jobs.build.outputs.build_id }}
    #|    secrets:
    #|      token:
    #|        required: true
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' hi
  let parsed = parse_workflow_yaml(src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  inspect(workflow.workflow_call, content="true")
  let workflow_call = workflow.workflow_call_spec.unwrap()
  inspect(
    workflow_call.inputs.get("target").unwrap().description,
    content="target environment",
  )
  inspect(workflow_call.inputs.get("target").unwrap().required, content="true")
  inspect(
    workflow_call.inputs.get("target").unwrap().input_type,
    content="string",
  )
  inspect(
    workflow_call.outputs.get("build_id").unwrap().value,
    content="${{ jobs.build.outputs.build_id }}",
  )
  inspect(workflow_call.secrets.get("token").unwrap().required, content="true")

  let result = lower_push_workflow(workflow)
  inspect(result.errors, content="[\"workflow_call is not supported in MVP\"]")
}

///|
test "lowering: local reusable workflow jobs are expanded in workspace-aware mode" {
  let workspace = prepare_local_action_workspace("reusable-workflow-local")
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/workflows")
  let reusable_src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: write
    #|        run: printf '%s' inner > inner.txt
    #|  test:
    #|    needs: [build]
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: verify
    #|        run: test -f inner.txt
  @xfs.write_string_to_file(
    workspace + "/.github/workflows/reusable.yml",
    reusable_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    uses: ./.github/workflows/reusable.yml
    #|  after:
    #|    needs: [call]
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' done > result.txt
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let build_write = flow_task_by_id(result.ir, "call__build/write")
  inspect(build_write.needs, content="[]")
  let verify = flow_task_by_id(result.ir, "call__test/verify")
  inspect(verify.needs, content="[\"call__build/__finish\"]")
  let show = flow_task_by_id(result.ir, "after/show")
  inspect(show.needs, content="[\"call__test/__finish\"]")
  inspect(
    result.plan.job_need_targets.get("after").unwrap().get("call").unwrap(),
    content="[\"call__test\"]",
  )
}

///|
test "lowering: reusable workflow with and outputs are rewired to caller context" {
  let workspace = prepare_local_action_workspace("reusable-workflow-io")
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/workflows")
  let reusable_src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      message:
    #|        required: true
    #|        type: string
    #|    outputs:
    #|      result:
    #|        value: ${{ jobs.test.outputs.result }}
    #|    secrets:
    #|      token:
    #|        required: true
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: write
    #|        run: printf '%s|%s' '${{ inputs.message }}' '${{ secrets.token }}' > inner.txt
    #|  test:
    #|    needs: [build]
    #|    runs-on: ubuntu-latest
    #|    outputs:
    #|      result: ${{ steps.capture.outputs.result }}
    #|    steps:
    #|      - id: capture
    #|        run: printf 'result=%s' \"$(cat inner.txt)\" >> \"$GITHUB_OUTPUT\"
  @xfs.write_string_to_file(
    workspace + "/.github/workflows/reusable.yml",
    reusable_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    uses: ./.github/workflows/reusable.yml
    #|    with:
    #|      message: hello
    #|    secrets:
    #|      token: ${{ secrets.CALL_TOKEN }}
    #|  after:
    #|    needs: [call]
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' "${{ needs.call.outputs.result }}" > result.txt
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  inspect(
    workflow.jobs[0].reusable_workflow_with.get("message").unwrap_or(""),
    content="hello",
  )
  inspect(
    workflow.jobs[0].reusable_workflow_secrets.get("token").unwrap_or(""),
    content="${{ secrets.CALL_TOKEN }}",
  )
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_virtual_targets.get("call").unwrap(),
    content="[\"call__test\"]",
  )
  inspect(
    result.plan.job_outputs.get("call").unwrap().get("result").unwrap_or(""),
    content="${{ needs.call__test.outputs.result }}",
  )
  let build_write = expect_task_plan(result.plan, "call__build/write")
  inspect(
    build_write.script,
    content="printf '%s|%s' 'hello' '${{ secrets.CALL_TOKEN }}' > inner.txt",
  )
}

///|
test "lowering: reusable workflow secrets inherit is rewired to caller secrets context" {
  let workspace = prepare_local_action_workspace(
    "reusable-workflow-secrets-inherit",
  )
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/workflows")
  let reusable_src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|    outputs:
    #|      result:
    #|        value: ${{ jobs.test.outputs.result }}
    #|    secrets:
    #|      token:
    #|        required: true
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: write
    #|        run: printf '%s' '${{ secrets.token }}' > inner.txt
    #|  test:
    #|    needs: [build]
    #|    runs-on: ubuntu-latest
    #|    outputs:
    #|      result: ${{ steps.capture.outputs.result }}
    #|    steps:
    #|      - id: capture
    #|        run: printf 'result=%s' "$(cat inner.txt)" >> "$GITHUB_OUTPUT"
  @xfs.write_string_to_file(
    workspace + "/.github/workflows/reusable.yml",
    reusable_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    uses: ./.github/workflows/reusable.yml
    #|    secrets: inherit
    #|  after:
    #|    needs: [call]
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' "${{ needs.call.outputs.result }}" > result.txt
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  inspect(workflow.jobs[0].reusable_workflow_inherit_secrets, content="true")
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let build_write = expect_task_plan(result.plan, "call__build/write")
  inspect(
    build_write.script,
    content="printf '%s' '${{ secrets.token }}' > inner.txt",
  )
}

///|
test "lowering: reusable workflow fills implicit defaults for typed inputs" {
  let workspace = prepare_local_action_workspace(
    "reusable-workflow-input-types",
  )
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/workflows")
  let reusable_src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      enabled:
    #|        type: boolean
    #|      retries:
    #|        type: number
    #|      message:
    #|        type: string
    #|        default: hello
    #|    outputs:
    #|      result:
    #|        value: ${{ jobs.build.outputs.result }}
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    outputs:
    #|      result: ${{ steps.capture.outputs.result }}
    #|    steps:
    #|      - id: capture
    #|        run: |
    #|          printf '%s|%s|%s' '${{ inputs.enabled }}' '${{ inputs.retries }}' '${{ inputs.message }}' > inner.txt
    #|          printf 'result=%s' "$(cat inner.txt)" >> "$GITHUB_OUTPUT"
  @xfs.write_string_to_file(
    workspace + "/.github/workflows/reusable.yml",
    reusable_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    uses: ./.github/workflows/reusable.yml
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  let capture = expect_task_plan(result.plan, "call__build/capture")
  inspect(
    capture.script,
    content="printf '%s|%s|%s' 'false' '0' 'hello' > inner.txt\nprintf 'result=%s' \"$(cat inner.txt)\" >> \"$GITHUB_OUTPUT\"",
  )
}

///|
test "lowering: reusable workflow rejects invalid typed inputs" {
  let workspace = prepare_local_action_workspace(
    "reusable-workflow-invalid-inputs",
  )
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/workflows")
  let reusable_src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      enabled:
    #|        type: boolean
    #|      retries:
    #|        type: number
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: show
    #|        run: printf '%s|%s' '${{ inputs.enabled }}' '${{ inputs.retries }}'
  @xfs.write_string_to_file(
    workspace + "/.github/workflows/reusable.yml",
    reusable_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    uses: ./.github/workflows/reusable.yml
    #|    with:
    #|      enabled: maybe
    #|      retries: nope
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(
    result.errors,
    content="[\"job 'call' reusable workflow input 'enabled' expects boolean but got 'maybe': ./.github/workflows/reusable.yml\", \"job 'call' reusable workflow input 'retries' expects number but got 'nope': ./.github/workflows/reusable.yml\"]",
  )
}

///|
test "lowering: reusable workflow caller matrix fans out to row aliases" {
  let workspace = prepare_local_action_workspace("reusable-workflow-matrix")
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/workflows")
  let reusable_src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      message:
    #|        required: true
    #|        type: string
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: write
    #|        run: printf '%s' '${{ inputs.message }}' > '${{ inputs.message }}.txt'
  @xfs.write_string_to_file(
    workspace + "/.github/workflows/reusable.yml",
    reusable_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    strategy:
    #|      matrix:
    #|        message: [one, two]
    #|    uses: ./.github/workflows/reusable.yml
    #|    with:
    #|      message: ${{ matrix.message }}
    #|  after:
    #|    needs: [call]
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: verify
    #|        run: test -f one.txt && test -f two.txt
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_virtual_targets.get("call").unwrap(),
    content="[\"call__matrix_1\", \"call__matrix_2\"]",
  )
  inspect(
    result.plan.job_need_targets.get("after").unwrap().get("call").unwrap(),
    content="[\"call__matrix_1__build\", \"call__matrix_2__build\"]",
  )
}

///|
test "lowering: reusable workflow caller matrix aggregates workflow outputs" {
  let workspace = prepare_local_action_workspace(
    "reusable-workflow-matrix-output",
  )
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/workflows")
  let reusable_src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      message:
    #|        required: true
    #|        type: string
    #|    outputs:
    #|      result:
    #|        value: ${{ jobs.build.outputs.result }}
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    outputs:
    #|      result: ${{ steps.capture.outputs.result }}
    #|    steps:
    #|      - id: capture
    #|        run: |
    #|          if [ '${{ inputs.message }}' = 'two' ]; then
    #|            printf 'result=%s' '' >> \"$GITHUB_OUTPUT\"
    #|          else
    #|            printf 'result=%s' '${{ inputs.message }}' >> \"$GITHUB_OUTPUT\"
    #|          fi
  @xfs.write_string_to_file(
    workspace + "/.github/workflows/reusable.yml",
    reusable_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    strategy:
    #|      matrix:
    #|        message: [one, two]
    #|    uses: ./.github/workflows/reusable.yml
    #|    with:
    #|      message: ${{ matrix.message }}
    #|  after:
    #|    needs: [call]
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' "${{ needs.call.outputs.result }}" > result.txt
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_virtual_output_targets
    .get("call")
    .unwrap()
    .get("result")
    .unwrap(),
    content="[\"call__matrix_1\", \"call__matrix_2\"]",
  )
  inspect(
    result.plan.job_need_targets.get("after").unwrap().get("call").unwrap(),
    content="[\"call__matrix_1__build\", \"call__matrix_2__build\"]",
  )
}

///|
#cfg(target="native")
async test "lowering: remote reusable workflow cache miss fetches and expands workflow" {
  let workspace = prepare_local_action_workspace("reusable-workflow-remote")
  let remote_repo = workspace + "/remote_repo"
  test_ensure_dir(remote_repo)
  test_ensure_dir(remote_repo + "/.github")
  test_ensure_dir(remote_repo + "/.github/workflows")
  let reusable_src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      message:
    #|        required: true
    #|        type: string
    #|    outputs:
    #|      result:
    #|        value: ${{ jobs.verify.outputs.result }}
    #|    secrets:
    #|      token:
    #|        required: true
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: write
    #|        run: printf '%s|%s' '${{ inputs.message }}' '${{ secrets.token }}' > inner.txt
    #|  verify:
    #|    needs: [build]
    #|    runs-on: ubuntu-latest
    #|    outputs:
    #|      result: ${{ steps.capture.outputs.result }}
    #|    steps:
    #|      - id: capture
    #|        run: printf 'result=%s' \"$(cat inner.txt)\" >> \"$GITHUB_OUTPUT\"
  @xfs.write_string_to_file(
    remote_repo + "/.github/workflows/reusable.yml",
    reusable_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    uses: demo/tools/.github/workflows/reusable.yml@v1
    #|    with:
    #|      message: hello
    #|    secrets:
    #|      token: ${{ secrets.CALL_TOKEN }}
    #|  after:
    #|    needs: [call]
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' "${{ needs.call.outputs.result }}" > result.txt
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let log_path = workspace + "/git.log"
  let cache_root = "_build/actrun/github_actions/demo/tools/v1"
  test_support_remove_tree(cache_root)
  let git_path = test_support_prepare_fake_git_bin_from_source(
    workspace, remote_repo, log_path,
  )
  let prefetch = prefetch_workflow_github_actions_native(
    workflow,
    workspace,
    git_bin=Some(git_path),
  )
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(prefetch.errors, content="[]")
  inspect(
    prefetch.fetched,
    content="[\"demo/tools/.github/workflows/reusable.yml@v1\"]",
  )
  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_virtual_targets.get("call").unwrap(),
    content="[\"call__verify\"]",
  )
  inspect(
    result.plan.job_outputs.get("call").unwrap().get("result").unwrap_or(""),
    content="${{ needs.call__verify.outputs.result }}",
  )
  let write = expect_task_plan(result.plan, "call__build/write")
  inspect(
    write.script,
    content="printf '%s|%s' 'hello' '${{ secrets.CALL_TOKEN }}' > inner.txt",
  )
  let log = @xfs.read_file_to_string(log_path)
  assert_eq(log.contains("https://github.com/demo/tools.git"), true)
}

///|
#cfg(target="native")
async test "lowering: remote reusable workflow local action is resolved from cached repo" {
  let workspace = prepare_local_action_workspace(
    "reusable-workflow-remote-local-action",
  )
  let remote_repo = workspace + "/remote_repo"
  test_ensure_dir(remote_repo)
  test_ensure_dir(remote_repo + "/.github")
  test_ensure_dir(remote_repo + "/.github/workflows")
  test_ensure_dir(remote_repo + "/.github/actions")
  test_ensure_dir(remote_repo + "/.github/actions/emit")
  let reusable_src =
    #|name: reusable
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      message:
    #|        required: true
    #|        type: string
    #|    outputs:
    #|      result:
    #|        value: ${{ jobs.verify.outputs.result }}
    #|    secrets:
    #|      token:
    #|        required: true
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: local
    #|        uses: ./.github/actions/emit
    #|        with:
    #|          message: ${{ inputs.message }}
    #|          token: ${{ secrets.token }}
    #|  verify:
    #|    needs: [build]
    #|    runs-on: ubuntu-latest
    #|    outputs:
    #|      result: ${{ steps.capture.outputs.result }}
    #|    steps:
    #|      - id: capture
    #|        run: printf 'result=%s' \"$(cat inner.txt)\" >> \"$GITHUB_OUTPUT\"
  let action_src =
    #|name: emit
    #|inputs:
    #|  message:
    #|    required: true
    #|  token:
    #|    required: true
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: write
    #|      run: printf '%s|%s' '${{ inputs.message }}' '${{ inputs.token }}' > inner.txt
  @xfs.write_string_to_file(
    remote_repo + "/.github/workflows/reusable.yml",
    reusable_src,
  )
  @xfs.write_string_to_file(
    remote_repo + "/.github/actions/emit/action.yml",
    action_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    uses: demo/local-tools/.github/workflows/reusable.yml@v1
    #|    with:
    #|      message: hello
    #|    secrets:
    #|      token: ${{ secrets.CALL_TOKEN }}
    #|  after:
    #|    needs: [call]
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' "${{ needs.call.outputs.result }}" > result.txt
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let log_path = workspace + "/git.log"
  let cache_root = "_build/actrun/github_actions/demo/local-tools/v1"
  test_support_remove_tree(cache_root)
  let git_path = test_support_prepare_fake_git_bin_from_source(
    workspace, remote_repo, log_path,
  )
  let prefetch = prefetch_workflow_github_actions_native(
    workflow,
    workspace,
    git_bin=Some(git_path),
  )
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(prefetch.errors, content="[]")
  inspect(result.errors, content="[]")
  let write = expect_task_plan(result.plan, "call__build/local__write")
  inspect(
    write.script,
    content="printf '%s|%s' 'hello' '${{ secrets.CALL_TOKEN }}' > inner.txt",
  )
}

///|
test "lowering: nested local reusable workflow is expanded recursively" {
  let workspace = prepare_local_action_workspace(
    "reusable-workflow-nested-local",
  )
  test_ensure_dir(workspace + "/.github")
  test_ensure_dir(workspace + "/.github/workflows")
  let outer_src =
    #|name: outer
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      message:
    #|        required: true
    #|        type: string
    #|    outputs:
    #|      result:
    #|        value: ${{ jobs.wrap.outputs.result }}
    #|    secrets:
    #|      token:
    #|        required: true
    #|jobs:
    #|  inner:
    #|    uses: ./.github/workflows/inner.yml
    #|    with:
    #|      message: ${{ inputs.message }}
    #|    secrets:
    #|      token: ${{ secrets.token }}
    #|  wrap:
    #|    needs: [inner]
    #|    runs-on: ubuntu-latest
    #|    outputs:
    #|      result: ${{ steps.capture.outputs.result }}
    #|    steps:
    #|      - id: capture
    #|        run: printf 'result=%s' "${{ needs.inner.outputs.result }}" >> "$GITHUB_OUTPUT"
  let inner_src =
    #|name: inner
    #|on:
    #|  workflow_call:
    #|    inputs:
    #|      message:
    #|        required: true
    #|        type: string
    #|    outputs:
    #|      result:
    #|        value: ${{ jobs.build.outputs.result }}
    #|    secrets:
    #|      token:
    #|        required: true
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    outputs:
    #|      result: ${{ steps.capture.outputs.result }}
    #|    steps:
    #|      - id: write
    #|        run: printf '%s|%s' '${{ inputs.message }}' '${{ secrets.token }}' > inner.txt
    #|      - id: capture
    #|        run: printf 'result=%s' "$(cat inner.txt)" >> "$GITHUB_OUTPUT"
  @xfs.write_string_to_file(
    workspace + "/.github/workflows/outer.yml",
    outer_src,
  )
  @xfs.write_string_to_file(
    workspace + "/.github/workflows/inner.yml",
    inner_src,
  )
  let caller_src =
    #|name: caller
    #|on: push
    #|jobs:
    #|  call:
    #|    uses: ./.github/workflows/outer.yml
    #|    with:
    #|      message: nested
    #|    secrets:
    #|      token: ${{ secrets.CALL_TOKEN }}
    #|  after:
    #|    needs: [call]
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' "${{ needs.call.outputs.result }}" > result.txt
  let parsed = parse_workflow_yaml(caller_src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let result = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_virtual_targets.get("call__inner").unwrap(),
    content="[\"call__inner__build\"]",
  )
  inspect(
    result.plan.job_virtual_targets.get("call").unwrap(),
    content="[\"call__wrap\"]",
  )
  inspect(
    result.plan.job_outputs.get("call").unwrap().get("result").unwrap_or(""),
    content="${{ needs.call__wrap.outputs.result }}",
  )
  let build_write = expect_task_plan(result.plan, "call__inner__build/write")
  inspect(
    build_write.script,
    content="printf '%s|%s' 'nested' '${{ secrets.CALL_TOKEN }}' > inner.txt",
  )
}

///|
test "parser/lowering: job container mapping is parsed and lowered" {
  let src =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    container:
    #|      image: node:20-bookworm
    #|      credentials:
    #|        username: octocat
    #|        password: ${{ secrets.REGISTRY_TOKEN }}
    #|      env:
    #|        NODE_ENV: test
    #|      ports:
    #|        - "80"
    #|        - "5432"
    #|      volumes:
    #|        - "cache:/cache"
    #|      options: --cpus 1
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' hi
  let parsed = parse_workflow_yaml(src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let container = workflow.jobs[0].container.unwrap()
  inspect(container.image, content="node:20-bookworm")
  inspect(container.credentials.unwrap().username, content="octocat")
  inspect(
    container.credentials.unwrap().password,
    content="${{ secrets.REGISTRY_TOKEN }}",
  )
  inspect(container.env.get("NODE_ENV").unwrap_or(""), content="test")
  inspect(container.ports, content="[\"80\", \"5432\"]")
  inspect(container.volumes, content="[\"cache:/cache\"]")
  inspect(container.options.unwrap_or(""), content="--cpus 1")

  let result = lower_push_workflow(workflow)
  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_containers.get("build").unwrap().image,
    content="node:20-bookworm",
  )
}

///|
test "parser/lowering: job services mapping is parsed and lowered into execution plan" {
  let src =
    #|name: ci
    #|on: push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    services:
    #|      postgres:
    #|        image: postgres:16
    #|        credentials:
    #|          username: octocat
    #|          password: ${{ secrets.REGISTRY_TOKEN }}
    #|        env:
    #|          POSTGRES_DB: app
    #|        ports:
    #|          - "5432"
    #|        volumes:
    #|          - "db:/var/lib/postgresql/data"
    #|        options: --health-cmd pg_isready
    #|    steps:
    #|      - id: show
    #|        run: printf '%s' hi
  let parsed = parse_workflow_yaml(src)

  inspect(parsed.errors, content="[]")
  let workflow = parsed.workflow.unwrap()
  let service = workflow.jobs[0].services.get("postgres").unwrap()
  inspect(service.image, content="postgres:16")
  inspect(service.credentials.unwrap().username, content="octocat")
  inspect(
    service.credentials.unwrap().password,
    content="${{ secrets.REGISTRY_TOKEN }}",
  )
  inspect(service.env.get("POSTGRES_DB").unwrap_or(""), content="app")
  inspect(service.ports, content="[\"5432\"]")
  inspect(service.volumes, content="[\"db:/var/lib/postgresql/data\"]")
  inspect(service.options.unwrap_or(""), content="--health-cmd pg_isready")

  let result = lower_push_workflow(workflow)
  inspect(result.errors, content="[]")
  inspect(
    result.plan.job_services.get("build").unwrap().get("postgres").unwrap().image,
    content="postgres:16",
  )
}
