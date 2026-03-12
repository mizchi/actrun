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
  test_ensure_dir("_build/action_runner")
  test_ensure_dir("_build/action_runner/github_actions")
  let root = "_build/action_runner/github_actions"
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
    segments.push(segment.to_string())
  }
  let mut current = ""
  for segment in segments {
    current = if current.length() == 0 {
      segment
    } else {
      current + "/" + segment
    }
    test_ensure_dir(current)
  }
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
test "parser: reject non-push trigger" {
  let src =
    #|on: pull_request
    #|jobs:
    #|  test:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo ok
  let parsed = parse_workflow_yaml(src)

  inspect(parsed.errors, content="[\"only push trigger is supported in MVP\"]")
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
test "parser: reject mixed matrix axes and include in P0" {
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
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: printf '%s' ok
  let parsed = parse_workflow_yaml(src)

  inspect(
    parsed.errors,
    content="[\"jobs.build.strategy.matrix include with axes is not supported in P0\"]",
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
#cfg(target="native")
async test "lowering: github repo action cache miss fetches and expands composite action" {
  let workspace = prepare_local_action_workspace(
    "lower-github-repo-remote-fetch",
  )
  let action_uses = "mizchi-fetch-lib/demo-action-lib/composite@v1"
  let repo_cache_root = "_build/action_runner/github_actions/mizchi-fetch-lib/demo-action-lib/v1"
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
test "lowering: matrix outputs are rejected in P0" {
  let workflow = new_workflow("ci", [
    new_job(
      "test",
      [new_run_step("always", "echo ok", if_condition="always()")],
      outputs={ "artifact": "${{ steps.always.outputs.name }}" },
      matrix=Some(new_job_matrix([{ "target": "native" }])),
    ),
  ])

  let result = lower_push_workflow(workflow)

  inspect(
    result.errors,
    content="[\"job 'test' matrix outputs are not supported in P0\"]",
  )
}
