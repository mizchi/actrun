///|
fn ensure_dir(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
fn executor_test_absolute_path(path : String) -> String {
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
fn prepare_workspace(name : String) -> String raise {
  ensure_dir("_build")
  ensure_dir("_build/test-workspaces")
  let workspace = "_build/test-workspaces/" + name
  ensure_dir(workspace)
  executor_test_absolute_path(workspace)
}

///|
fn prepare_cached_github_action_root_for_executor(
  owner : String,
  repo : String,
  version : String,
  subpath? : String = "",
) -> String raise {
  ensure_dir("_build")
  ensure_dir("_build/action_runner")
  ensure_dir("_build/action_runner/github_actions")
  let root = "_build/action_runner/github_actions"
  let owner_dir = root + "/" + owner
  let repo_dir = owner_dir + "/" + repo
  let version_dir = repo_dir + "/" + version
  ensure_dir(owner_dir)
  ensure_dir(repo_dir)
  ensure_dir(version_dir)
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
    ensure_dir(current)
  }
  executor_test_absolute_path(action_root)
}

///|
fn expect_task_report(report : WorkflowRunReport, id : String) -> TaskRunReport {
  match find_task_run_report(report, id) {
    Some(item) => item
    None => abort("missing task report: " + id)
  }
}

///|
fn expect_step_report(
  report : WorkflowRunReport,
  id : String,
) -> WorkflowStepReport {
  match find_workflow_step_report(report, id) {
    Some(item) => item
    None => abort("missing step report: " + id)
  }
}

///|
#cfg(target="native")
async test "executor: run step in working directory with env" {
  let workspace = prepare_workspace("executor-success")
  ensure_dir(workspace + "/packages")
  ensure_dir(workspace + "/packages/app")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step("write", "printf '%s' \"$GREETING\" > result.txt", env={
          "GREETING": "hello",
        }),
      ],
      defaults=new_run_defaults(
        shell=Some("bash"),
        working_directory=Some("packages/app"),
      ),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  inspect(report.state, content="completed")

  let step = expect_step_report(report, "build/write")
  inspect(step.status, content="success")

  let task = expect_task_report(report, "build/write")
  inspect(task.status, content="success")
  assert_eq(task.cwd, workspace + "/packages/app")

  let result = @xfs.read_file_to_string(workspace + "/packages/app/result.txt")
  inspect(result, content="hello")
}

///|
#cfg(target="native")
async test "executor: default shell runs multiline script" {
  let workspace = prepare_workspace("executor-multiline")

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step(
        "multi", "printf 'a\\n' > lines.txt\nprintf 'b\\n' >> lines.txt\ncat lines.txt",
      ),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let task = expect_task_report(report, "build/multi")
  inspect(task.status, content="success")
  inspect(task.stdout, content="a\nb\n")
  inspect(@xfs.read_file_to_string(workspace + "/lines.txt"), content="a\nb\n")
}

///|
#cfg(target="native")
async test "executor: explicit sh shell runs script" {
  let workspace = prepare_workspace("executor-sh")

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step("sh", "printf '%s' \"$MESSAGE\"", shell=Some("sh"), env={
        "MESSAGE": "hello-sh",
      }),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let task = expect_task_report(report, "build/sh")
  inspect(task.status, content="success")
  inspect(task.stdout, content="hello-sh")
}

///|
#cfg(target="native")
async test "executor: custom shell template runs temp script file" {
  let workspace = prepare_workspace("executor-shell-template")

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step(
        "custom",
        "printf '%s' custom-shell-ok",
        shell=Some("sh {0}"),
      ),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let task = expect_task_report(report, "build/custom")
  inspect(task.status, content="success")
  inspect(task.stdout, content="custom-shell-ok")
}

///|
#cfg(target="native")
async test "executor: injects basic github runner env" {
  let workspace = prepare_workspace("executor-github-env")

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step(
        "env",
        "printf '%s|%s|%s|%s|%s' \"$GITHUB_WORKSPACE\" \"$GITHUB_WORKFLOW\" \"$GITHUB_JOB\" \"$CI\" \"$GITHUB_ACTIONS\"",
        shell=Some("bash"),
      ),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let task = expect_task_report(report, "build/env")
  inspect(task.status, content="success")
  inspect(task.stdout, content=workspace + "|ci|build|true|true")
}

///|
#cfg(target="native")
async test "executor: env context is available in script expressions" {
  let workspace = prepare_workspace("executor-env-context-script")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "script_expr",
          "printf '%s|%s' \"${{ env.GREETING }}\" \"${{ env.STEP_ONLY }}\"",
          shell=Some("bash"),
          env={ "STEP_ONLY": "from-step" },
        ),
      ],
      env={ "GREETING": "from-job" },
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let task = expect_task_report(report, "build/script_expr")
  inspect(task.status, content="success")
  inspect(task.stdout, content="from-job|from-step")
}

///|
#cfg(target="native")
async test "executor: env context is available in env expressions" {
  let workspace = prepare_workspace("executor-env-context-env")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step("read", "printf '%s' \"$MESSAGE\"", shell=Some("bash"), env={
          "MESSAGE": "${{ env.GREETING }}",
        }),
      ],
      env={ "GREETING": "from-job-env" },
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let task = expect_task_report(report, "build/read")
  inspect(task.status, content="success")
  inspect(task.stdout, content="from-job-env")
}

///|
#cfg(target="native")
async test "executor: GITHUB_ENV updates later steps in job" {
  let workspace = prepare_workspace("executor-github-env-file")

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step(
        "export",
        "printf '%s=%s\\n' GREETING from-env-file >> \"$GITHUB_ENV\"",
        shell=Some("bash"),
      ),
      new_run_step("read", "printf '%s' \"$GREETING\"", shell=Some("bash")),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let read_task = expect_task_report(report, "build/read")
  inspect(read_task.status, content="success")
  inspect(read_task.stdout, content="from-env-file")
}

///|
#cfg(target="native")
async test "executor: env context sees GITHUB_ENV updates from prior steps" {
  let workspace = prepare_workspace("executor-env-context-github-env")

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step(
        "export",
        "printf '%s=%s\\n' GREETING from-github-env >> \"$GITHUB_ENV\"",
        shell=Some("bash"),
      ),
      new_run_step(
        "read",
        "printf '%s' \"${{ env.GREETING }}\"",
        shell=Some("bash"),
      ),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let task = expect_task_report(report, "build/read")
  inspect(task.status, content="success")
  inspect(task.stdout, content="from-github-env")
}

///|
#cfg(target="native")
async test "executor: GITHUB_ENV multiline updates later steps in job" {
  let workspace = prepare_workspace("executor-github-env-multiline")
  let export_script =
    #|cat <<'EOF' >> "$GITHUB_ENV"
    #|MULTI<<__ENV__
    #|line-1
    #|line-2
    #|__ENV__
    #|EOF

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step("export", export_script, shell=Some("bash")),
      new_run_step("read", "printf '%s' \"$MULTI\"", shell=Some("bash")),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let read_task = expect_task_report(report, "build/read")
  inspect(read_task.status, content="success")
  inspect(read_task.stdout, content="line-1\nline-2")
}

///|
#cfg(target="native")
async test "executor: GITHUB_PATH updates later steps in job" {
  let workspace = prepare_workspace("executor-github-path-file")
  let export_script =
    #|mkdir -p tools
    #|cat > tools/hello-tool <<'EOF'
    #|#!/bin/sh
    #|printf 'from-path-file'
    #|EOF
    #|chmod +x tools/hello-tool
    #|printf '%s\n' "$(pwd)/tools" >> "$GITHUB_PATH"

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step("export_path", export_script, shell=Some("bash")),
      new_run_step("read_path", "hello-tool", shell=Some("bash")),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let read_task = expect_task_report(report, "build/read_path")
  inspect(read_task.status, content="success")
  inspect(read_task.stdout, content="from-path-file")
}

///|
#cfg(target="native")
async test "executor: GITHUB_OUTPUT updates later steps in job" {
  let workspace = prepare_workspace("executor-github-output-file")

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step(
        "produce",
        "printf '%s=%s\\n' greeting from-output >> \"$GITHUB_OUTPUT\"",
        shell=Some("bash"),
      ),
      new_run_step(
        "consume",
        "printf '%s' \"${{ steps.produce.outputs.greeting }}\"",
        shell=Some("bash"),
      ),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let consume_task = expect_task_report(report, "build/consume")
  inspect(consume_task.status, content="success")
  inspect(consume_task.stdout, content="from-output")
}

///|
#cfg(target="native")
async test "executor: GITHUB_OUTPUT multiline updates later steps in job" {
  let workspace = prepare_workspace("executor-github-output-multiline")
  let export_script =
    #|cat <<'EOF' >> "$GITHUB_OUTPUT"
    #|message<<__OUTPUT__
    #|line-1
    #|line-2
    #|__OUTPUT__
    #|EOF

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step("produce", export_script, shell=Some("bash")),
      new_run_step(
        "consume",
        "printf '%s' \"${{ steps.produce.outputs.message }}\"",
        shell=Some("bash"),
      ),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let consume_task = expect_task_report(report, "build/consume")
  inspect(consume_task.status, content="success")
  inspect(consume_task.stdout, content="line-1\nline-2")
}

///|
#cfg(target="native")
async test "executor: GITHUB_STEP_SUMMARY stores step summary content" {
  let workspace = prepare_workspace("executor-github-step-summary")

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step(
        "summary",
        "printf 'hello summary' >> \"$GITHUB_STEP_SUMMARY\"",
        shell=Some("bash"),
      ),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let task = expect_task_report(report, "build/summary")
  inspect(task.status, content="success")
  inspect(task.summary, content="hello summary")
}

///|
#cfg(target="native")
async test "executor: step outputs are available in env expressions" {
  let workspace = prepare_workspace("executor-github-output-env")

  let workflow = new_workflow("ci", [
    new_job("build", [
      new_run_step(
        "produce",
        "printf '%s=%s\\n' message env-output >> \"$GITHUB_OUTPUT\"",
        shell=Some("bash"),
      ),
      new_run_step("consume", "printf '%s' \"$MESSAGE\"", shell=Some("bash"), env={
        "MESSAGE": "${{ steps.produce.outputs.message }}",
      }),
    ]),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let consume_task = expect_task_report(report, "build/consume")
  inspect(consume_task.status, content="success")
  inspect(consume_task.stdout, content="env-output")
}

///|
#cfg(target="native")
async test "executor: checkout step is a no-op success" {
  let workspace = prepare_workspace("executor-checkout")
  @xfs.write_string_to_file(workspace + "/tracked.txt", "from workspace")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4"),
        new_run_step("verify", "cat tracked.txt"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  inspect(report.state, content="completed")

  let checkout = expect_task_report(report, "build/checkout")
  inspect(checkout.kind, content="action")
  inspect(checkout.status, content="success")
  inspect(checkout.code, content="0")

  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="from workspace",
  )
}

///|
#cfg(target="native")
async test "executor: checkout supports path and sparse-checkout" {
  let workspace = prepare_workspace("executor-checkout-sparse")
  ensure_dir(workspace + "/.github")
  ensure_dir(workspace + "/.github/workflows")
  @xfs.write_string_to_file(workspace + "/README.md", "readme")
  @xfs.write_string_to_file(workspace + "/LICENSE", "license")
  @xfs.write_string_to_file(workspace + "/.github/workflows/ci.yml", "name: ci")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4", with_values={
          "path": "repo",
          "sparse-checkout": "README.md\n.github",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s|%s' \"$(test -f repo/README.md && echo yes || echo no)\" \"$(test -f repo/.github/workflows/ci.yml && echo yes || echo no)\" \"$(test -f repo/LICENSE && echo yes || echo no)\"",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let checkout = expect_task_report(report, "build/checkout")
  inspect(checkout.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="yes|yes|yes",
  )
}

///|
#cfg(target="native")
async test "executor: checkout supports sparse-checkout cone mode false" {
  let workspace = prepare_workspace("executor-checkout-sparse-noncone")
  ensure_dir(workspace + "/.github")
  ensure_dir(workspace + "/.github/workflows")
  @xfs.write_string_to_file(workspace + "/README.md", "readme")
  @xfs.write_string_to_file(workspace + "/LICENSE", "license")
  @xfs.write_string_to_file(workspace + "/.github/workflows/ci.yml", "name: ci")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4", with_values={
          "path": "repo",
          "sparse-checkout": "README.md\n.github",
          "sparse-checkout-cone-mode": "false",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s|%s' \"$(test -f repo/README.md && echo yes || echo no)\" \"$(test -f repo/.github/workflows/ci.yml && echo yes || echo no)\" \"$(test -f repo/LICENSE && echo yes || echo no)\"",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let checkout = expect_task_report(report, "build/checkout")
  inspect(checkout.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="yes|yes|no")
}

///|
#cfg(target="native")
async test "executor: cached github repo composite action runs inner steps" {
  let workspace = prepare_workspace("executor-github-repo-action")
  let action_root = prepare_cached_github_action_root_for_executor(
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
    #|      run: printf '%s|%s|%s|%s|%s' "${{ github.action }}" "${{ github.action_repository }}" "${{ github.action_ref }}" "$GITHUB_ACTION" "$GITHUB_ACTION_PATH" > remote.txt
    #|      shell: bash
  @xfs.write_string_to_file(action_root + "/action.yml", action_src)

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("remote", "mizchi-test/demo-action/composite@v1"),
        new_run_step("verify", "cat remote.txt"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  let write = expect_task_report(report, "build/remote__write")
  inspect(write.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="write|mizchi-test/demo-action|v1|write|" + action_root,
  )
}

///|
#cfg(target="native")
async test "executor: cached github repo node action runs main entrypoint" {
  let workspace = prepare_workspace("executor-github-node-action")
  let action_root = prepare_cached_github_action_root_for_executor(
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
  let main_src =
    #|printf '%s|%s|%s|%s|%s' "$INPUT_MESSAGE" "$GITHUB_ACTION" "$GITHUB_ACTION_PATH" "$GITHUB_ACTION_REPOSITORY" "$GITHUB_ACTION_REF" > "$GITHUB_WORKSPACE/node.txt"
  @xfs.write_string_to_file(action_root + "/action.yml", action_src)
  @xfs.write_string_to_file(action_root + "/main.sh", main_src)
  let node_log_path = workspace + "/node.log"
  let node_bin = test_support_prepare_fake_node_bin(workspace, node_log_path)

  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [
          new_uses_step("remote", "mizchi-test/node-action/action@v1", with_values={
            "message": "from-input",
          }),
          new_run_step("verify", "cat node.txt"),
        ],
        defaults=new_run_defaults(shell=Some("bash")),
      ),
    ],
    env={ "ACTION_RUNNER_NODE_BIN": node_bin },
  )

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  let remote = expect_task_report(report, "build/remote")
  inspect(remote.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="from-input|mizchitestnodeactionaction|" +
      action_root +
      "|mizchi-test/node-action|v1",
  )
  let node_log = @xfs.read_file_to_string(node_log_path)
  assert_eq(node_log.contains(action_root + "/main.sh"), true)
}

///|
#cfg(target="native")
async test "executor: github repo action cache miss fetches and runs inner steps" {
  let workspace = prepare_workspace("executor-github-repo-remote-fetch")
  let action_uses = "mizchi-fetch-exec/demo-action-exec/composite@v1"
  let repo_cache_root = "_build/action_runner/github_actions/mizchi-fetch-exec/demo-action-exec/v1"
  let log_path = workspace + "/git.log"
  test_support_remove_tree(repo_cache_root)
  let action_src =
    #|name: Remote
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: write
    #|      run: printf '%s' fetched-runtime > remote.txt
    #|      shell: bash
  let git_path = test_support_prepare_fake_github_git_bin(
    workspace, action_src, log_path,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
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
  let lowered = lower_push_workflow_in_workspace(workflow, workspace)

  inspect(prefetch.errors, content="[]")
  inspect(prefetch.fetched.length(), content="1")
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  assert_eq(@xfs.path_exists(repo_cache_root + "/composite/action.yml"), true)
  let verify = expect_task_report(report, "build/verify")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="fetched-runtime",
  )
  let log = @xfs.read_file_to_string(log_path)
  assert_eq(
    log.contains("https://github.com/mizchi-fetch-exec/demo-action-exec.git"),
    true,
  )
}

///|
#cfg(target="native")
async test "executor: builtin checkout alias works" {
  let workspace = prepare_workspace("executor-builtin-checkout")
  @xfs.write_string_to_file(workspace + "/tracked.txt", "from builtin")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "builtin://checkout"),
        new_run_step("verify", "cat tracked.txt"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  let checkout = expect_task_report(report, "build/checkout")
  inspect(checkout.kind, content="action")
  inspect(checkout.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="from builtin",
  )
}

///|
#cfg(target="native")
async test "executor: builtin artifact actions upload and download files" {
  let workspace = prepare_workspace("executor-builtin-artifacts")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "write",
          "mkdir -p dist\nprintf '%s' alpha > dist/alpha.txt\nprintf '%s' beta > dist/beta.txt",
          shell=Some("bash"),
        ),
        new_uses_step("upload", "actions/upload-artifact@v4", with_values={
          "name": "bundle",
          "path": "dist/alpha.txt\ndist/beta.txt",
        }),
        new_run_step(
          "remove",
          "rm -f dist/alpha.txt dist/beta.txt",
          shell=Some("bash"),
        ),
        new_uses_step("download", "actions/download-artifact@v4", with_values={
          "name": "bundle",
          "path": "restored",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"$(cat restored/alpha.txt)\" \"$(cat restored/beta.txt)\"",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let upload = expect_task_report(report, "build/upload")
  inspect(upload.status, content="success")
  let download = expect_task_report(report, "build/download")
  inspect(download.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="alpha|beta")
}

///|
#cfg(target="native")
async test "executor: builtin cache save and restore roundtrip across jobs" {
  let workspace = prepare_workspace("executor-builtin-cache")
  test_support_remove_tree("_build/action_runner/cache")

  let workflow = new_workflow("ci", [
    new_job(
      "save",
      [
        new_run_step(
          "write",
          "mkdir -p cache-dir\nprintf '%s' ocean > cache-dir/value.txt",
          shell=Some("bash"),
        ),
        new_uses_step("save", "actions/cache/save@v4", with_values={
          "key": "compat-cache-v1",
          "path": "cache-dir",
        }),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "restore",
      [
        new_run_step("clear", "rm -rf cache-dir", shell=Some("bash")),
        new_uses_step("restore", "actions/cache/restore@v4", with_values={
          "key": "compat-cache-v1",
          "path": "cache-dir",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"${{ steps.restore.outputs.cache-hit }}\" \"$(cat cache-dir/value.txt)\"",
          shell=Some("bash"),
        ),
      ],
      needs=["save"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let save = expect_task_report(report, "save/save")
  inspect(save.status, content="success")
  let restore = expect_task_report(report, "restore/restore")
  inspect(restore.status, content="success")
  let verify = expect_task_report(report, "restore/verify")
  inspect(verify.status, content="success")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="true|ocean")
}

///|
#cfg(target="native")
async test "executor: builtin cache action auto-saves on miss and restores on next job" {
  let workspace = prepare_workspace("executor-builtin-cache-main")
  test_support_remove_tree("_build/action_runner/cache")

  let workflow = new_workflow("ci", [
    new_job(
      "save",
      [
        new_run_step(
          "write",
          "mkdir -p cache-dir\nprintf '%s' ocean > cache-dir/value.txt",
          shell=Some("bash"),
        ),
        new_uses_step("cache", "actions/cache@v4", with_values={
          "key": "compat-cache-main-v1",
          "path": "cache-dir",
        }),
        new_run_step(
          "check_miss",
          "if [ -n \"${{ steps.cache.outputs.cache-hit }}\" ]; then exit 1; fi",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "restore",
      [
        new_run_step("clear", "rm -rf cache-dir", shell=Some("bash")),
        new_uses_step("restore_cache", "actions/cache@v4", with_values={
          "key": "compat-cache-main-v1",
          "path": "cache-dir",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"${{ steps.restore_cache.outputs.cache-hit }}\" \"$(cat cache-dir/value.txt)\"",
          shell=Some("bash"),
        ),
      ],
      needs=["save"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let cache = expect_task_report(report, "save/cache")
  inspect(cache.status, content="success")
  let cache_post = expect_task_report(report, "save/cache__post")
  inspect(cache_post.status, content="success")
  let check_miss = expect_task_report(report, "save/check_miss")
  inspect(check_miss.status, content="success")
  let restore = expect_task_report(report, "restore/restore_cache")
  inspect(restore.status, content="success")
  let verify = expect_task_report(report, "restore/verify")
  inspect(verify.status, content="success")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="true|ocean")
}

///|
#cfg(target="native")
async test "executor: local composite action runs inner steps" {
  let workspace = prepare_workspace("executor-local-action")
  ensure_dir(workspace + "/.github")
  ensure_dir(workspace + "/.github/actions")
  ensure_dir(workspace + "/.github/actions/setup")
  let action_src =
    #|name: Setup
    #|inputs:
    #|  message:
    #|    default: default-message
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: prepare
    #|      run: printf '%s|%s' "$FROM_INNER" "$GITHUB_ACTION_PATH" > local.txt
    #|      shell: bash
    #|      env:
    #|        FROM_INNER: ${{ inputs.message }}
    #|    - id: show
    #|      run: cat local.txt
  @xfs.write_string_to_file(
    workspace + "/.github/actions/setup/action.yml",
    action_src,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("setup", "./.github/actions/setup", with_values={
          "message": "from-local-action",
        }),
        new_run_step("verify", "cat local.txt"),
      ],
      defaults=new_run_defaults(shell=Some("sh")),
    ),
  ])

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)

  inspect(report.ok, content="true")
  inspect(report.state, content="completed")

  let prepare = expect_task_report(report, "build/setup__prepare")
  inspect(prepare.status, content="success")
  let show = expect_task_report(report, "build/setup__show")
  inspect(
    show.stdout.trim(chars=" \n\r\t").to_string(),
    content="from-local-action|" + workspace + "/.github/actions/setup",
  )
  let verify = expect_task_report(report, "build/verify")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="from-local-action|" + workspace + "/.github/actions/setup",
  )
}

///|
#cfg(target="native")
async test "executor: local composite action supports nested uses" {
  let workspace = prepare_workspace("executor-local-action-nested-uses")
  ensure_dir(workspace + "/.github")
  ensure_dir(workspace + "/.github/actions")
  ensure_dir(workspace + "/.github/actions/setup")
  ensure_dir(workspace + "/.github/actions/setup/nested")
  @xfs.write_string_to_file(
    workspace + "/tracked.txt",
    "tracked-from-workspace",
  )
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
    #|    - id: checkout
    #|      uses: builtin://checkout
    #|    - id: child
    #|      uses: ./nested
    #|    - id: show
    #|      run: printf '%s|%s' "$(cat tracked.txt)" "$(cat nested.txt)"
    #|      shell: bash
  @xfs.write_string_to_file(
    workspace + "/.github/actions/setup/action.yml",
    action_src,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("setup", "./.github/actions/setup"),
        new_run_step("verify", "printf '%s' \"$(cat nested.txt)\""),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)

  inspect(report.ok, content="true")
  let checkout = expect_task_report(report, "build/setup__checkout")
  inspect(checkout.status, content="success")
  let write = expect_task_report(report, "build/setup__child__write")
  inspect(write.status, content="success")
  let show = expect_task_report(report, "build/setup__show")
  inspect(
    show.stdout.trim(chars=" \n\r\t").to_string(),
    content="tracked-from-workspace|nested-ok",
  )
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="nested-ok")
}

///|
#cfg(target="native")
async test "executor: github action_path context is available in local composite action" {
  let workspace = prepare_workspace("executor-local-action-github-action-path")
  ensure_dir(workspace + "/.github")
  ensure_dir(workspace + "/.github/actions")
  ensure_dir(workspace + "/.github/actions/setup")
  let action_src =
    #|name: Setup
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: prepare
    #|      run: printf '%s' "${{ github.action_path }}" > action-path.txt
    #|      shell: bash
  @xfs.write_string_to_file(
    workspace + "/.github/actions/setup/action.yml",
    action_src,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [new_uses_step("setup", "./.github/actions/setup")],
      defaults=new_run_defaults(shell=Some("sh")),
    ),
  ])

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)

  inspect(report.ok, content="true")
  let prepare = expect_task_report(report, "build/setup__prepare")
  inspect(prepare.status, content="success")
  inspect(
    @xfs.read_file_to_string(workspace + "/action-path.txt"),
    content=workspace + "/.github/actions/setup",
  )
}

///|
#cfg(target="native")
async test "executor: GITHUB_STATE is scoped to local composite action inner steps" {
  let workspace = prepare_workspace("executor-local-action-state")
  ensure_dir(workspace + "/.github")
  ensure_dir(workspace + "/.github/actions")
  ensure_dir(workspace + "/.github/actions/setup")
  let action_src =
    #|name: Setup
    #|runs:
    #|  using: composite
    #|  steps:
    #|    - id: store
    #|      run: |
    #|        printf '%s=%s\n' token from-state >> "$GITHUB_STATE"
    #|        printf '%s' "${STATE_token:-missing}" > before.txt
    #|      shell: bash
    #|    - id: read
    #|      run: printf '%s' "${STATE_token:-missing}" > inner.txt
    #|      shell: bash
  @xfs.write_string_to_file(
    workspace + "/.github/actions/setup/action.yml",
    action_src,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("setup", "./.github/actions/setup"),
        new_run_step(
          "verify",
          "printf '%s' \"${STATE_token:-outside}\" > outer.txt",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("sh")),
    ),
  ])

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)

  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(
    @xfs.read_file_to_string(workspace + "/before.txt"),
    content="missing",
  )
  inspect(
    @xfs.read_file_to_string(workspace + "/inner.txt"),
    content="from-state",
  )
  inspect(@xfs.read_file_to_string(workspace + "/outer.txt"), content="outside")
}

///|
#cfg(target="native")
async test "executor: failed dependency blocks downstream job" {
  let workspace = prepare_workspace("executor-blocked")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [new_run_step("fail", "echo boom 1>&2; exit 5")],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "lint",
      [new_run_step("lint", "echo lint")],
      needs=["build"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")

  let failed = expect_task_report(report, "build/fail")
  inspect(failed.code, content="5")
  inspect(failed.status, content="failed")

  let build_step = expect_step_report(report, "build/fail")
  inspect(build_step.status, content="failed")

  let lint_step = expect_step_report(report, "lint/lint")
  inspect(lint_step.status, content="blocked")
  assert_eq(lint_step.message.has_prefix("blocked by dependency"), true)

  match find_task_run_report(report, "lint/lint") {
    Some(_) => abort("lint/lint should not run")
    None => ()
  }
}

///|
#cfg(target="native")
async test "executor: matrix fail-fast cancels later siblings" {
  let workspace = prepare_workspace("executor-matrix-fail-fast")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "emit",
          "mkdir -p artifacts\n" +
          "printf '%s' '${{ matrix.variant }}' > artifacts/${{ matrix.variant }}.txt\n" +
          "if [ '${{ matrix.variant }}' = 'fail' ]; then\n" +
          "  echo boom 1>&2\n" +
          "  exit 7\n" +
          "fi",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
      matrix=Some(
        new_job_matrix(
          [{ "variant": "ok" }, { "variant": "fail" }, { "variant": "late" }],
          fail_fast=true,
        ),
      ),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  inspect(
    expect_task_report(report, "build__matrix_1/emit").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build__matrix_2/emit").status,
    content="failed",
  )
  inspect(
    expect_task_report(report, "build__matrix_3/emit").status,
    content="cancelled",
  )
  inspect(
    expect_step_report(report, "build__matrix_3/emit").status,
    content="cancelled",
  )
  inspect(
    @xfs.read_file_to_string(workspace + "/artifacts/ok.txt"),
    content="ok",
  )
  inspect(
    @xfs.read_file_to_string(workspace + "/artifacts/fail.txt"),
    content="fail",
  )
  inspect(@xfs.path_exists(workspace + "/artifacts/late.txt"), content="false")
}

///|
#cfg(target="native")
async test "executor: matrix fail-fast false keeps later siblings running" {
  let workspace = prepare_workspace("executor-matrix-no-fail-fast")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "emit",
          "mkdir -p artifacts\n" +
          "printf '%s' '${{ matrix.variant }}' > artifacts/${{ matrix.variant }}.txt\n" +
          "if [ '${{ matrix.variant }}' = 'fail' ]; then\n" +
          "  echo boom 1>&2\n" +
          "  exit 7\n" +
          "fi",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
      matrix=Some(
        new_job_matrix(
          [{ "variant": "ok" }, { "variant": "fail" }, { "variant": "late" }],
          fail_fast=false,
        ),
      ),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  inspect(
    expect_task_report(report, "build__matrix_1/emit").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build__matrix_2/emit").status,
    content="failed",
  )
  inspect(
    expect_task_report(report, "build__matrix_3/emit").status,
    content="success",
  )
  inspect(
    expect_step_report(report, "build__matrix_3/emit").status,
    content="success",
  )
  inspect(
    @xfs.read_file_to_string(workspace + "/artifacts/late.txt"),
    content="late",
  )
}

///|
#cfg(target="native")
async test "executor: matrix needs aggregate result and outputs for downstream job" {
  let workspace = prepare_workspace("executor-matrix-needs-output")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "produce",
          "printf '%s=%s\\n' '${{ matrix.target }}' '${{ matrix.target }}' >> \"$GITHUB_OUTPUT\"",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
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
          "read",
          "printf '%s|%s|%s' " +
          "\"${{ needs.build.result }}\" " +
          "\"${{ needs.build.outputs.native }}\" " +
          "\"${{ needs.build.outputs.js }}\"",
          shell=Some("bash"),
        ),
      ],
      needs=["build"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(expect_step_report(report, "consume/read").status, content="success")
  inspect(
    expect_task_report(report, "consume/read").stdout,
    content="success|native|js",
  )
}

///|
#cfg(target="native")
async test "executor: docker actions run via docker adapter" {
  let workspace = prepare_workspace("executor-docker-action")
  let log_path = workspace + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(workspace, log_path)

  let docker_image_workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [new_uses_step("image", "docker://alpine:3.21")],
        defaults=new_run_defaults(shell=Some("bash")),
      ),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
  )

  let docker_image_report = execute_lowered_native(
    lower_push_workflow(docker_image_workflow),
    workspace_root=workspace,
  )

  inspect(docker_image_report.ok, content="true")
  inspect(docker_image_report.state, content="completed")

  let image = expect_task_report(docker_image_report, "build/image")
  inspect(image.kind, content="action")
  inspect(image.status, content="success")
  inspect(image.script, content="")
  inspect(image.stderr, content="")
  let remote_workspace = prepare_workspace("executor-github-docker-action")
  let action_root = prepare_cached_github_action_root_for_executor(
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

  let remote_workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [
          new_uses_step("remote", "mizchi-test/docker-action/action@v1", with_values={
            "message": "from-input",
          }),
          new_run_step("verify", "cat docker.txt"),
        ],
        defaults=new_run_defaults(shell=Some("bash")),
      ),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
  )

  let lowered = lower_push_workflow_in_workspace(
    remote_workflow, remote_workspace,
  )
  inspect(lowered.errors, content="[]")

  let remote_report = execute_lowered_native(
    lowered,
    workspace_root=remote_workspace,
  )
  inspect(remote_report.ok, content="true")
  let remote = expect_task_report(remote_report, "build/remote")
  inspect(remote.status, content="success")
  let verify = expect_task_report(remote_report, "build/verify")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="from-input")
  let docker_log = @xfs.read_file_to_string(log_path)
  assert_eq(docker_log.contains("run\n--rm\n"), true)
  assert_eq(docker_log.contains("alpine:3.21"), true)
  assert_eq(
    docker_log.contains("build\n-f\n" + action_root + "/Dockerfile\n"),
    true,
  )
  assert_eq(docker_log.contains("run\n--rm\n"), true)
}

///|
#cfg(target="native")
async test "executor: github repo node action lifecycle shares GITHUB_STATE across pre main post" {
  let workspace = prepare_workspace("executor-github-node-lifecycle")
  let action_root = prepare_cached_github_action_root_for_executor(
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
  @xfs.write_string_to_file(
    action_root + "/pre.sh",
    "printf 'phase=pre\\n' >> \"$GITHUB_STATE\"",
  )
  @xfs.write_string_to_file(
    action_root + "/main.sh",
    "printf '%s' \"$STATE_phase\" > \"$GITHUB_WORKSPACE/main.txt\" && printf 'phase=main\\n' >> \"$GITHUB_STATE\"",
  )
  @xfs.write_string_to_file(
    action_root + "/post.sh",
    "printf '%s|%s' \"$STATE_phase\" \"$GITHUB_WORKSPACE\" > \"$GITHUB_WORKSPACE/post.txt\"",
  )
  let node_log_path = workspace + "/node.log"
  let node_bin = test_support_prepare_fake_node_bin(workspace, node_log_path)

  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [
          new_uses_step("remote", "mizchi-test/node-lifecycle/action@v1"),
          new_run_step("verify", "cat main.txt"),
        ],
        defaults=new_run_defaults(shell=Some("bash")),
      ),
    ],
    env={ "ACTION_RUNNER_NODE_BIN": node_bin },
  )

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  inspect(
    expect_task_report(report, "build/remote__pre").status,
    content="success",
  )
  inspect(expect_task_report(report, "build/remote").status, content="success")
  inspect(
    expect_task_report(report, "build/remote__post").status,
    content="success",
  )
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="pre")
  inspect(
    @xfs.read_file_to_string(workspace + "/post.txt"),
    content="main|" + workspace,
  )
}

///|
#cfg(target="native")
async test "executor: github repo docker action lifecycle shares GITHUB_STATE across pre main post" {
  let workspace = prepare_workspace("executor-github-docker-lifecycle")
  let action_root = prepare_cached_github_action_root_for_executor(
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
  let docker_log_path = workspace + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(
    workspace, docker_log_path,
  )

  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [
          new_uses_step("remote", "mizchi-test/docker-lifecycle/action@v1"),
          new_run_step("verify", "cat main.txt"),
        ],
        defaults=new_run_defaults(shell=Some("bash")),
      ),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
  )

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  inspect(
    expect_task_report(report, "build/remote__pre").status,
    content="success",
  )
  inspect(expect_task_report(report, "build/remote").status, content="success")
  inspect(
    expect_task_report(report, "build/remote__post").status,
    content="success",
  )
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="pre")
  inspect(
    @xfs.read_file_to_string(workspace + "/post.txt"),
    content="main|" + workspace,
  )
}
