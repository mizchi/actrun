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
fn executor_test_set_env_var(key : String, value : String) -> String? {
  let previous = @xsys.get_env_var(key)
  @xsys.set_env_var(key, value)
  previous
}

///|
fn executor_test_restore_env_var(key : String, previous : String?) -> Unit {
  match previous {
    Some(value) => @xsys.set_env_var(key, value)
    None => @xsys.unset_env_var(key)
  }
}

///|
fn executor_test_parent_dir(path : String) -> String {
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
fn executor_test_ensure_dir_all(path : String) -> Unit raise {
  if path.length() == 0 || path == "." || path == "/" || @xfs.path_exists(path) {
    return
  }
  let parent = executor_test_parent_dir(path)
  if parent != path {
    executor_test_ensure_dir_all(parent)
  }
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
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
fn executor_test_cache_store_root(workspace : String) -> String {
  executor_test_absolute_path(
    "_build/action_runner/cache/" +
    workspace.replace_all(old="/", new="__").replace_all(old=":", new="_"),
  )
}

///|
#cfg(target="native")
async fn executor_test_run_env(
  cmd : String,
  args : Array[String],
  cwd : String,
  env? : Map[String, String] = {},
) -> (Int, String, String) {
  let command_args : Array[String] = []
  for key, value in env {
    command_args.push(key + "=" + value)
  }
  command_args.push(cmd)
  for arg in args {
    command_args.push(arg)
  }
  let (code, stdout, stderr) = @process.collect_output(
    "env",
    command_args,
    cwd~,
  )
  (code, stdout.text(), stderr.text())
}

///|
#cfg(target="native")
async fn executor_test_require_ok(
  label : String,
  cmd : String,
  args : Array[String],
  cwd : String,
  env? : Map[String, String] = {},
) -> Unit {
  let (code, stdout, stderr) = executor_test_run_env(cmd, args, cwd, env~)
  if code != 0 {
    let message = if stderr.length() > 0 { stderr } else { stdout }
    abort(label + " failed: " + message)
  }
}

///|
#cfg(target="native")
async fn prepare_git_checkout_workspace(name : String) -> String {
  let existing = executor_test_absolute_path("_build/test-workspaces/" + name)
  if @xfs.path_exists(existing) {
    executor_test_require_ok("rm workspace", "rm", ["-rf", existing], ".")
  }
  let workspace = prepare_workspace(name)
  executor_test_require_ok("git init", "git", ["init", "-q"], workspace)
  executor_test_require_ok(
    "git config name",
    "git",
    ["config", "user.name", "Action Runner Test"],
    workspace,
  )
  executor_test_require_ok(
    "git config email",
    "git",
    ["config", "user.email", "action-runner@example.com"],
    workspace,
  )
  @xfs.write_string_to_file(workspace + "/tracked.txt", "first")
  executor_test_require_ok(
    "git add first",
    "git",
    ["add", "tracked.txt"],
    workspace,
  )
  executor_test_require_ok(
    "git commit first",
    "git",
    ["commit", "-q", "-m", "first"],
    workspace,
  )
  @xfs.write_string_to_file(workspace + "/tracked.txt", "second")
  executor_test_require_ok(
    "git add second",
    "git",
    ["add", "tracked.txt"],
    workspace,
  )
  executor_test_require_ok(
    "git commit second",
    "git",
    ["commit", "-q", "-m", "second"],
    workspace,
  )
  workspace
}

///|
#cfg(target="native")
async fn prepare_git_checkout_workspace_with_feature_branch(
  name : String,
) -> String {
  let workspace = prepare_git_checkout_workspace(name)
  executor_test_require_ok(
    "git branch main",
    "git",
    ["branch", "-M", "main"],
    workspace,
  )
  executor_test_require_ok(
    "git checkout feature",
    "git",
    ["checkout", "-q", "-b", "feature"],
    workspace,
  )
  @xfs.write_string_to_file(workspace + "/tracked.txt", "feature")
  executor_test_require_ok(
    "git add feature",
    "git",
    ["add", "tracked.txt"],
    workspace,
  )
  executor_test_require_ok(
    "git commit feature",
    "git",
    ["commit", "-q", "-m", "feature"],
    workspace,
  )
  executor_test_require_ok(
    "git checkout main",
    "git",
    ["checkout", "-q", "main"],
    workspace,
  )
  workspace
}

///|
#cfg(target="native")
async fn prepare_git_repo_with_single_file(
  name : String,
  filename : String,
  content : String,
) -> String {
  let existing = executor_test_absolute_path("_build/test-workspaces/" + name)
  if @xfs.path_exists(existing) {
    executor_test_require_ok("rm repo", "rm", ["-rf", existing], ".")
  }
  let repo = prepare_workspace(name)
  executor_test_require_ok("git init", "git", ["init", "-q"], repo)
  executor_test_require_ok(
    "git config name",
    "git",
    ["config", "user.name", "Action Runner Test"],
    repo,
  )
  executor_test_require_ok(
    "git config email",
    "git",
    ["config", "user.email", "action-runner@example.com"],
    repo,
  )
  @xfs.write_string_to_file(repo + "/" + filename, content)
  executor_test_require_ok("git add file", "git", ["add", filename], repo)
  executor_test_require_ok(
    "git commit file",
    "git",
    ["commit", "-q", "-m", "init"],
    repo,
  )
  repo
}

///|
#cfg(target="native")
async fn prepare_git_checkout_workspace_with_submodules(
  name : String,
  recursive? : Bool = false,
) -> String {
  let workspace = prepare_git_checkout_workspace(name)
  let child_repo = prepare_git_repo_with_single_file(
    name + "-child",
    "child.txt",
    "child\n",
  )
  if recursive {
    let grand_repo = prepare_git_repo_with_single_file(
      name + "-grand",
      "grand.txt",
      "grand\n",
    )
    executor_test_require_ok(
      "child add grand submodule",
      "git",
      [
        "-c", "protocol.file.allow=always", "submodule", "add", grand_repo, "vendor/grand",
      ],
      child_repo,
    )
    executor_test_require_ok(
      "child commit grand submodule",
      "git",
      ["commit", "-qam", "add grand"],
      child_repo,
    )
  }
  executor_test_require_ok(
    "root add child submodule",
    "git",
    [
      "-c", "protocol.file.allow=always", "submodule", "add", child_repo, "deps/child",
    ],
    workspace,
  )
  executor_test_require_ok(
    "root commit child submodule",
    "git",
    ["commit", "-qam", "add child"],
    workspace,
  )
  workspace
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
fn prepare_custom_registry_action_root_for_executor(
  root : String,
  scheme : String,
  name : String,
  version : String,
) -> String raise {
  let action_root = root + "/" + scheme + "/" + name + "/" + version
  executor_test_ensure_dir_all(action_root)
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
async test "executor: checkout default fetch-depth clones shallow history" {
  let workspace = prepare_git_checkout_workspace(
    "executor-checkout-fetch-depth",
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4"),
        new_run_step(
          "verify",
          "printf '%s|%s' \"$(git rev-list --count HEAD)\" \"$(test -f .git/shallow && echo yes || echo no)\"",
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
  inspect(report.state, content="completed")
  inspect(
    expect_task_report(report, "build/checkout").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="1|yes",
  )
}

///|
#cfg(target="native")
async test "executor: checkout fetch-depth zero keeps full history" {
  let workspace = prepare_git_checkout_workspace(
    "executor-checkout-fetch-depth-zero",
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4", with_values={
          "fetch-depth": "0",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"$(git rev-list --count HEAD)\" \"$(test -f .git/shallow && echo yes || echo no)\"",
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
  inspect(report.state, content="completed")
  inspect(
    expect_task_report(report, "build/checkout").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="2|no",
  )
}

///|
#cfg(target="native")
async test "executor: checkout ref selects requested branch" {
  let workspace = prepare_git_checkout_workspace_with_feature_branch(
    "executor-checkout-ref",
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4", with_values={
          "path": "repo",
          "ref": "feature",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s|%s|%s' \"$(cat repo/tracked.txt)\" \"$(git -C repo branch --show-current)\" \"$(git -C repo rev-list --count HEAD)\" \"$(test -f repo/.git/shallow && echo yes || echo no)\"",
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
  inspect(report.state, content="completed")
  inspect(
    expect_task_report(report, "build/checkout").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="feature|feature|1|yes",
  )
}

///|
#cfg(target="native")
async test "executor: checkout clean default removes untracked files" {
  let workspace = prepare_git_checkout_workspace(
    "executor-checkout-clean-default",
  )
  @xfs.write_string_to_file(workspace + "/scratch.txt", "keep?")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4"),
        new_run_step(
          "verify",
          "printf '%s|%s' \"$(test -f scratch.txt && echo yes || echo no)\" \"$(test -f .git/shallow && echo yes || echo no)\"",
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
  inspect(report.state, content="completed")
  inspect(
    expect_task_report(report, "build/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="no|yes",
  )
}

///|
#cfg(target="native")
async test "executor: checkout clean false preserves untracked files" {
  let workspace = prepare_git_checkout_workspace(
    "executor-checkout-clean-false",
  )
  @xfs.write_string_to_file(workspace + "/scratch.txt", "keep")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4", with_values={
          "clean": "false",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s|%s' \"$(cat tracked.txt)\" \"$(test -f scratch.txt && echo yes || echo no)\" \"$(test -f .git/shallow && echo yes || echo no)\"",
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
  inspect(report.state, content="completed")
  inspect(
    expect_task_report(report, "build/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="second|yes|yes",
  )
}

///|
#cfg(target="native")
async test "executor: checkout materialized on host is visible to job container run step" {
  let workspace = prepare_git_checkout_workspace(
    "executor-checkout-job-container",
  )
  let tools_root = prepare_workspace("executor-checkout-job-container-tools")
  let docker_log_path = tools_root + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(
    tools_root, docker_log_path,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4"),
        new_run_step(
          "verify",
          "printf '%s|%s' \"$(cat tracked.txt)\" \"$(test -f .git/shallow && echo yes || echo no)\"",
          shell=Some("bash"),
        ),
      ],
      env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
      container=Some(new_job_container_spec("node:20-bookworm")),
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(
    expect_task_report(report, "build/checkout").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="second|yes",
  )
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(docker_log.contains("node:20-bookworm"), true)
}

///|
#cfg(target="native")
async test "executor: checkout submodules true initializes direct submodules" {
  let workspace = prepare_git_checkout_workspace_with_submodules(
    "executor-checkout-submodules",
    recursive=true,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4", with_values={
          "path": "repo",
          "submodules": "true",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"$(test -f repo/deps/child/child.txt && echo yes || echo no)\" \"$(test -f repo/deps/child/vendor/grand/grand.txt && echo yes || echo no)\"",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  inspect(report.ok, content="true")
  inspect(
    expect_task_report(report, "build/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="yes|no",
  )
}

///|
#cfg(target="native")
async test "executor: checkout submodules recursive initializes nested submodules" {
  let workspace = prepare_git_checkout_workspace_with_submodules(
    "executor-checkout-submodules-recursive",
    recursive=true,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("checkout", "actions/checkout@v4", with_values={
          "path": "repo",
          "submodules": "recursive",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"$(test -f repo/deps/child/child.txt && echo yes || echo no)\" \"$(test -f repo/deps/child/vendor/grand/grand.txt && echo yes || echo no)\"",
          shell=Some("bash"),
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )
  inspect(report.ok, content="true")
  inspect(
    expect_task_report(report, "build/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="yes|yes",
  )
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
async test "executor: job container runs github repo node action via docker adapter" {
  let workspace = prepare_workspace("executor-job-container-node-action")
  let action_root = prepare_cached_github_action_root_for_executor(
    "mizchi-test",
    "node-action-container",
    "v1",
    subpath="action",
  )
  let action_src =
    #|name: Remote Node In Container
    #|runs:
    #|  using: node20
    #|  main: main.sh
  let main_src =
    #|printf '%s|%s|%s' "$CONTAINER_FLAG" "$GITHUB_WORKSPACE" "$PWD" > "$GITHUB_WORKSPACE/node.txt"
  @xfs.write_string_to_file(action_root + "/action.yml", action_src)
  @xfs.write_string_to_file(action_root + "/main.sh", main_src)
  let node_log_path = workspace + "/node.log"
  let node_bin = test_support_prepare_fake_node_bin(workspace, node_log_path)
  let docker_log_path = workspace + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(
    workspace, docker_log_path,
  )

  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [new_uses_step("remote", "mizchi-test/node-action-container/action@v1")],
        defaults=new_run_defaults(shell=Some("bash")),
        container=Some(
          new_job_container_spec("alpine:3.21", env={
            "CONTAINER_FLAG": "from-container",
          }),
        ),
      ),
    ],
    env={
      "ACTION_RUNNER_DOCKER_BIN": docker_bin,
      "ACTION_RUNNER_NODE_BIN": node_bin,
    },
  )

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  let remote = expect_task_report(report, "build/remote")
  inspect(remote.status, content="success")
  inspect(
    @xfs.read_file_to_string(workspace + "/node.txt"),
    content="from-container|" + workspace + "|" + action_root,
  )
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(docker_log.contains("run\n--rm\n"), true)
  assert_eq(docker_log.contains("alpine:3.21"), true)
  assert_eq(docker_log.contains(node_bin), true)
  assert_eq(docker_log.contains(action_root + "/main.sh"), true)
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
async test "executor: builtin artifact actions roundtrip across job container run steps" {
  let workspace = prepare_workspace("executor-builtin-artifacts-container")
  let docker_log_path = workspace + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(
    workspace, docker_log_path,
  )

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
      env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
      container=Some(new_job_container_spec("node:20-bookworm")),
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  inspect(expect_task_report(report, "build/upload").status, content="success")
  inspect(
    expect_task_report(report, "build/download").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="alpha|beta",
  )
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(docker_log.contains("node:20-bookworm"), true)
}

///|
#cfg(target="native")
async test "executor: builtin artifact actions support directory, wildcard, and download-all" {
  let workspace = prepare_workspace("executor-builtin-artifacts-glob-dir")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "write",
          "mkdir -p pkg/nested logs/linux logs/macos\n" +
          "printf '%s' root > pkg/root.txt\n" +
          "printf '%s' child > pkg/nested/child.txt\n" +
          "printf '%s' linux > logs/linux/out.txt\n" +
          "printf '%s' macos > logs/macos/out.txt\n",
          shell=Some("bash"),
        ),
        new_uses_step("upload_dir", "actions/upload-artifact@v4", with_values={
          "name": "dir-bundle",
          "path": "pkg/",
        }),
        new_uses_step("upload_glob", "actions/upload-artifact@v4", with_values={
          "name": "log-bundle",
          "path": "logs/*/out.txt",
        }),
        new_run_step("remove", "rm -rf pkg logs", shell=Some("bash")),
        new_uses_step("download_all", "actions/download-artifact@v4", with_values={
          "path": "restored",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s|%s|%s|%s|%s' " +
          "\"$(cat restored/dir-bundle/root.txt)\" " +
          "\"$(cat restored/dir-bundle/nested/child.txt)\" " +
          "\"$(cat restored/log-bundle/linux/out.txt)\" " +
          "\"$(cat restored/log-bundle/macos/out.txt)\" " +
          "\"$(test -d restored/dir-bundle/pkg && echo yes || echo no)\" " +
          "\"$(test -f restored/log-bundle/out.txt && echo yes || echo no)\"",
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

  inspect(
    expect_task_report(report, "build/upload_dir").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/upload_glob").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/download_all").status,
    content="success",
  )
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="root|child|linux|macos|no|no",
  )
}

///|
#cfg(target="native")
async test "executor: upload-artifact if-no-files-found supports warn ignore and error" {
  let workspace = prepare_workspace("executor-builtin-artifacts-missing")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("upload_warn", "actions/upload-artifact@v4", with_values={
          "name": "warn-bundle",
          "path": "missing/*.txt",
        }),
        new_uses_step("upload_ignore", "actions/upload-artifact@v4", with_values={
          "name": "ignore-bundle",
          "path": "missing/*.txt",
          "if-no-files-found": "ignore",
        }),
        new_uses_step(
          "upload_error",
          "actions/upload-artifact@v4",
          with_values={
            "name": "error-bundle",
            "path": "missing/*.txt",
            "if-no-files-found": "error",
          },
          continue_on_error="true",
        ),
        new_run_step(
          "verify",
          "printf '%s|%s|%s|%s|%s|%s' " +
          "\"${{ steps.upload_warn.outcome }}\" " +
          "\"${{ steps.upload_warn.conclusion }}\" " +
          "\"${{ steps.upload_ignore.outcome }}\" " +
          "\"${{ steps.upload_ignore.conclusion }}\" " +
          "\"${{ steps.upload_error.outcome }}\" " +
          "\"${{ steps.upload_error.conclusion }}\"",
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

  let upload_warn = expect_task_report(report, "build/upload_warn")
  inspect(upload_warn.status, content="success")
  let upload_ignore = expect_task_report(report, "build/upload_ignore")
  inspect(upload_ignore.status, content="success")
  let upload_error = expect_task_report(report, "build/upload_error")
  inspect(upload_error.status, content="failed")
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="success|success|success|success|failure|success",
  )
}

///|
#cfg(target="native")
async test "executor: upload-artifact overwrite replaces existing artifact only when enabled" {
  let workspace = prepare_workspace("executor-builtin-artifacts-overwrite")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "write_first",
          "mkdir -p dist\nprintf '%s' alpha > dist/value.txt",
          shell=Some("bash"),
        ),
        new_uses_step("upload_first", "actions/upload-artifact@v4", with_values={
          "name": "bundle",
          "path": "dist/value.txt",
        }),
        new_run_step(
          "write_second",
          "printf '%s' beta > dist/value.txt",
          shell=Some("bash"),
        ),
        new_uses_step(
          "upload_again",
          "actions/upload-artifact@v4",
          with_values={ "name": "bundle", "path": "dist/value.txt" },
          continue_on_error="true",
        ),
        new_uses_step("upload_overwrite", "actions/upload-artifact@v4", with_values={
          "name": "bundle",
          "path": "dist/value.txt",
          "overwrite": "true",
        }),
        new_run_step("remove", "rm -f dist/value.txt", shell=Some("bash")),
        new_uses_step("download", "actions/download-artifact@v4", with_values={
          "name": "bundle",
          "path": "restored",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s|%s' " +
          "\"${{ steps.upload_again.outcome }}\" " +
          "\"${{ steps.upload_again.conclusion }}\" " +
          "\"$(cat restored/value.txt)\"",
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

  inspect(
    expect_task_report(report, "build/upload_first").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/upload_again").status,
    content="failed",
  )
  inspect(
    expect_task_report(report, "build/upload_overwrite").status,
    content="success",
  )
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="failure|success|beta",
  )
}

///|
#cfg(target="native")
async test "executor: download-artifact merge-multiple flattens download-all into one directory" {
  let workspace = prepare_workspace("executor-builtin-artifacts-merge-multiple")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "write",
          "mkdir -p pkg/nested logs/linux logs/macos\n" +
          "printf '%s' root > pkg/root.txt\n" +
          "printf '%s' child > pkg/nested/child.txt\n" +
          "printf '%s' linux > logs/linux/out.txt\n" +
          "printf '%s' macos > logs/macos/out.txt\n",
          shell=Some("bash"),
        ),
        new_uses_step("upload_dir", "actions/upload-artifact@v4", with_values={
          "name": "dir-bundle",
          "path": "pkg/",
        }),
        new_uses_step("upload_glob", "actions/upload-artifact@v4", with_values={
          "name": "log-bundle",
          "path": "logs/*/out.txt",
        }),
        new_run_step("remove", "rm -rf pkg logs", shell=Some("bash")),
        new_uses_step("download_all", "actions/download-artifact@v4", with_values={
          "path": "restored",
          "merge-multiple": "true",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s|%s|%s|%s|%s' " +
          "\"$(cat restored/root.txt)\" " +
          "\"$(cat restored/nested/child.txt)\" " +
          "\"$(cat restored/linux/out.txt)\" " +
          "\"$(cat restored/macos/out.txt)\" " +
          "\"$(test -d restored/dir-bundle && echo yes || echo no)\" " +
          "\"$(test -d restored/log-bundle && echo yes || echo no)\"",
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

  inspect(
    expect_task_report(report, "build/download_all").status,
    content="success",
  )
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="root|child|linux|macos|no|no",
  )
}

///|
#cfg(target="native")
async test "executor: builtin cache save and restore roundtrip across jobs" {
  let workspace = prepare_workspace("executor-builtin-cache")
  test_support_remove_tree(executor_test_cache_store_root(workspace))

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
  test_support_remove_tree(executor_test_cache_store_root(workspace))

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
async test "executor: builtin cache action auto-saves across job container jobs" {
  let workspace = prepare_workspace("executor-builtin-cache-container")
  test_support_remove_tree(executor_test_cache_store_root(workspace))
  let docker_log_path = workspace + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(
    workspace, docker_log_path,
  )

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
          "key": "compat-cache-container-v1",
          "path": "cache-dir",
        }),
        new_run_step(
          "check_miss",
          "if [ -n \"${{ steps.cache.outputs.cache-hit }}\" ]; then exit 1; fi",
          shell=Some("bash"),
        ),
      ],
      env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
      container=Some(new_job_container_spec("alpine:3.21")),
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "restore",
      [
        new_run_step("clear", "rm -rf cache-dir", shell=Some("bash")),
        new_uses_step("cache", "actions/cache@v4", with_values={
          "key": "compat-cache-container-v1",
          "path": "cache-dir",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"${{ steps.cache.outputs.cache-hit }}\" \"$(cat cache-dir/value.txt)\"",
          shell=Some("bash"),
        ),
      ],
      needs=["save"],
      env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
      container=Some(new_job_container_spec("alpine:3.21")),
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  inspect(expect_task_report(report, "save/cache").status, content="success")
  inspect(
    expect_task_report(report, "save/cache__post").status,
    content="success",
  )
  inspect(expect_task_report(report, "restore/cache").status, content="success")
  inspect(
    expect_task_report(report, "restore/verify").stdout
    .trim(chars=" \n\r\t")
    .to_string(),
    content="true|ocean",
  )
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(docker_log.contains("alpine:3.21"), true)
}

///|
#cfg(target="native")
async test "executor: builtin cache restore uses restore-keys fallback and reports partial hit" {
  let workspace = prepare_workspace("executor-builtin-cache-restore-keys")
  test_support_remove_tree(executor_test_cache_store_root(workspace))

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
          "key": "compat-cache-restore-v1",
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
          "key": "compat-cache-restore-v2",
          "restore-keys": "compat-cache-restore-\n",
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

  let restore = expect_task_report(report, "restore/restore")
  inspect(restore.status, content="success")
  let verify = expect_task_report(report, "restore/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="false|ocean",
  )
}

///|
#cfg(target="native")
async test "executor: builtin cache action saves new primary key after restore-keys fallback" {
  let workspace = prepare_workspace("executor-builtin-cache-restore-keys-main")
  test_support_remove_tree(executor_test_cache_store_root(workspace))

  let workflow = new_workflow("ci", [
    new_job(
      "seed",
      [
        new_run_step(
          "write",
          "mkdir -p cache-dir\nprintf '%s' ocean > cache-dir/value.txt",
          shell=Some("bash"),
        ),
        new_uses_step("save", "actions/cache/save@v4", with_values={
          "key": "compat-cache-main-restore-v1",
          "path": "cache-dir",
        }),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "restore",
      [
        new_run_step("clear", "rm -rf cache-dir", shell=Some("bash")),
        new_uses_step("cache", "actions/cache@v4", with_values={
          "key": "compat-cache-main-restore-v2",
          "restore-keys": "compat-cache-main-restore-\n",
          "path": "cache-dir",
        }),
        new_run_step(
          "mutate",
          "printf '%s' wave > cache-dir/value.txt",
          shell=Some("bash"),
        ),
      ],
      needs=["seed"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "verify",
      [
        new_run_step("clear", "rm -rf cache-dir", shell=Some("bash")),
        new_uses_step("cache", "actions/cache@v4", with_values={
          "key": "compat-cache-main-restore-v2",
          "path": "cache-dir",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"${{ steps.cache.outputs.cache-hit }}\" \"$(cat cache-dir/value.txt)\"",
          shell=Some("bash"),
        ),
      ],
      needs=["restore"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let cache = expect_task_report(report, "restore/cache")
  inspect(cache.status, content="success")
  let cache_post = expect_task_report(report, "restore/cache__post")
  inspect(cache_post.status, content="success")
  let verify = expect_task_report(report, "verify/verify")
  inspect(verify.status, content="success")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="true|wave")
}

///|
#cfg(target="native")
async test "executor: builtin cache restore-keys prefers the most recent prefix match" {
  let workspace = prepare_workspace("executor-builtin-cache-restore-latest")
  test_support_remove_tree(executor_test_cache_store_root(workspace))

  let workflow = new_workflow("ci", [
    new_job(
      "save_old",
      [
        new_run_step(
          "write",
          "mkdir -p cache-dir\nprintf '%s' ocean > cache-dir/value.txt",
          shell=Some("bash"),
        ),
        new_uses_step("save", "actions/cache/save@v4", with_values={
          "key": "compat-cache-restore-latest-v1",
          "path": "cache-dir",
        }),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "save_new",
      [
        new_run_step(
          "write",
          "mkdir -p cache-dir\nprintf '%s' wave > cache-dir/value.txt",
          shell=Some("bash"),
        ),
        new_uses_step("save", "actions/cache/save@v4", with_values={
          "key": "compat-cache-restore-latest-v2",
          "path": "cache-dir",
        }),
      ],
      needs=["save_old"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "restore",
      [
        new_run_step("clear", "rm -rf cache-dir", shell=Some("bash")),
        new_uses_step("restore", "actions/cache/restore@v4", with_values={
          "key": "compat-cache-restore-latest-v3",
          "restore-keys": "compat-cache-restore-latest-\n",
          "path": "cache-dir",
        }),
        new_run_step("verify", "cat cache-dir/value.txt", shell=Some("bash")),
      ],
      needs=["save_new"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let verify = expect_task_report(report, "restore/verify")
  inspect(verify.status, content="success")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="wave")
}

///|
#cfg(target="native")
async test "executor: builtin cache restore lookup-only reports exact hit without downloading files" {
  let workspace = prepare_workspace(
    "executor-builtin-cache-lookup-only-restore",
  )
  test_support_remove_tree(executor_test_cache_store_root(workspace))

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
          "key": "compat-cache-lookup-only-v1",
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
          "key": "compat-cache-lookup-only-v1",
          "path": "cache-dir",
          "lookup-only": "true",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"${{ steps.restore.outputs.cache-hit }}\" \"$(if [ -f cache-dir/value.txt ]; then printf yes; else printf no; fi)\"",
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

  let restore = expect_task_report(report, "restore/restore")
  inspect(restore.status, content="success")
  let verify = expect_task_report(report, "restore/verify")
  inspect(verify.status, content="success")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="true|no")
}

///|
#cfg(target="native")
async test "executor: builtin cache lookup-only skips restore but still saves primary key after partial hit" {
  let workspace = prepare_workspace("executor-builtin-cache-lookup-only-main")
  test_support_remove_tree(executor_test_cache_store_root(workspace))

  let workflow = new_workflow("ci", [
    new_job(
      "seed",
      [
        new_run_step(
          "write",
          "mkdir -p cache-dir\nprintf '%s' ocean > cache-dir/value.txt",
          shell=Some("bash"),
        ),
        new_uses_step("save", "actions/cache/save@v4", with_values={
          "key": "compat-cache-lookup-main-v1",
          "path": "cache-dir",
        }),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "promote",
      [
        new_run_step(
          "write",
          "mkdir -p cache-dir\nprintf '%s' wave > cache-dir/value.txt",
          shell=Some("bash"),
        ),
        new_uses_step("cache", "actions/cache@v4", with_values={
          "key": "compat-cache-lookup-main-v2",
          "restore-keys": "compat-cache-lookup-main-\n",
          "path": "cache-dir",
          "lookup-only": "true",
        }),
        new_run_step(
          "verify_lookup",
          "printf '%s|%s' \"${{ steps.cache.outputs.cache-hit }}\" \"$(cat cache-dir/value.txt)\"",
          shell=Some("bash"),
        ),
      ],
      needs=["seed"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "verify",
      [
        new_run_step("clear", "rm -rf cache-dir", shell=Some("bash")),
        new_uses_step("cache", "actions/cache@v4", with_values={
          "key": "compat-cache-lookup-main-v2",
          "path": "cache-dir",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"${{ steps.cache.outputs.cache-hit }}\" \"$(cat cache-dir/value.txt)\"",
          shell=Some("bash"),
        ),
      ],
      needs=["promote"],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let verify_lookup = expect_task_report(report, "promote/verify_lookup")
  inspect(verify_lookup.status, content="success")
  inspect(
    verify_lookup.stdout.trim(chars=" \n\r\t").to_string(),
    content="false|wave",
  )
  let cache_post = expect_task_report(report, "promote/cache__post")
  inspect(cache_post.status, content="success")
  let verify = expect_task_report(report, "verify/verify")
  inspect(verify.status, content="success")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="true|wave")
}

///|
#cfg(target="native")
async test "executor: builtin cache restore fail-on-cache-miss fails exact miss" {
  let workspace = prepare_workspace(
    "executor-builtin-cache-fail-on-miss-restore",
  )
  test_support_remove_tree(executor_test_cache_store_root(workspace))

  let workflow = new_workflow("ci", [
    new_job(
      "restore",
      [
        new_uses_step(
          "restore",
          "actions/cache/restore@v4",
          with_values={
            "key": "compat-cache-fail-on-miss-v1",
            "path": "cache-dir",
            "fail-on-cache-miss": "true",
          },
          continue_on_error="true",
        ),
        new_run_step(
          "verify",
          "printf '%s|%s|%s' \"${{ steps.restore.outcome }}\" \"${{ steps.restore.conclusion }}\" \"$(if [ -f cache-dir/value.txt ]; then printf yes; else printf no; fi)\"",
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

  let restore = expect_task_report(report, "restore/restore")
  inspect(restore.status, content="failed")
  let verify = expect_task_report(report, "restore/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="failure|success|no",
  )
}

///|
#cfg(target="native")
async test "executor: builtin cache action fail-on-cache-miss fails exact miss" {
  let workspace = prepare_workspace("executor-builtin-cache-fail-on-miss-main")
  test_support_remove_tree(executor_test_cache_store_root(workspace))

  let workflow = new_workflow("ci", [
    new_job(
      "restore",
      [
        new_uses_step(
          "cache",
          "actions/cache@v4",
          with_values={
            "key": "compat-cache-main-fail-on-miss-v1",
            "path": "cache-dir",
            "fail-on-cache-miss": "true",
          },
          continue_on_error="true",
        ),
        new_run_step(
          "verify",
          "printf '%s|%s' \"${{ steps.cache.outcome }}\" \"${{ steps.cache.conclusion }}\"",
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

  let cache = expect_task_report(report, "restore/cache")
  inspect(cache.status, content="failed")
  let verify = expect_task_report(report, "restore/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="failure|success",
  )
}

///|
#cfg(target="native")
async test "executor: builtin setup-node exposes requested node version output and PATH shim" {
  let workspace = prepare_workspace("executor-builtin-setup-node")
  let node_log_path = workspace + "/setup-node.log"
  let fake_node = test_support_prepare_fake_version_node_bin(
    workspace, node_log_path, "24.9.0",
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("setup", "actions/setup-node@v4", with_values={
          "node-version": "20",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"${{ steps.setup.outputs.node-version }}\" \"$(node --version)\"",
          shell=Some("bash"),
        ),
      ],
      env={ "ACTION_RUNNER_SETUP_NODE_BIN": fake_node },
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let setup = expect_task_report(report, "build/setup")
  inspect(setup.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="v20.0.0|v20.0.0",
  )
}

///|
#cfg(target="native")
async test "executor: builtin setup-node works in job container run step" {
  let workspace = prepare_workspace("executor-builtin-setup-node-container")
  let node_log_path = workspace + "/setup-node-container.log"
  let fake_node = test_support_prepare_fake_version_node_bin(
    workspace, node_log_path, "24.9.0",
  )
  let docker_log_path = workspace + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(
    workspace, docker_log_path,
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("setup", "actions/setup-node@v4", with_values={
          "node-version": "20",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' \"${{ steps.setup.outputs.node-version }}\" \"$(node --version)\"",
          shell=Some("bash"),
        ),
      ],
      env={
        "ACTION_RUNNER_SETUP_NODE_BIN": fake_node,
        "ACTION_RUNNER_DOCKER_BIN": docker_bin,
      },
      container=Some(new_job_container_spec("node:20-bookworm")),
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let setup = expect_task_report(report, "build/setup")
  inspect(setup.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="v20.0.0|v20.0.0",
  )
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(docker_log.contains("node:20-bookworm"), true)
  let node_log = @xfs.read_file_to_string(node_log_path)
  assert_eq(node_log.contains("--version"), true)
}

///|
#cfg(target="native")
async test "executor: builtin setup-node registry-url exports npm auth config" {
  let workspace = prepare_workspace("executor-builtin-setup-node-registry")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("setup", "actions/setup-node@v4", with_values={
          "registry-url": "https://registry.npmjs.org",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s|%s' \"$NODE_AUTH_TOKEN\" \"$(test -f \"$NPM_CONFIG_USERCONFIG\" && echo yes || echo no)\" \"$(tr '\\n' ';' < \"$NPM_CONFIG_USERCONFIG\")\"",
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

  let setup = expect_task_report(report, "build/setup")
  inspect(setup.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="XXXXX-XXXXX-XXXXX-XXXXX|yes|//registry.npmjs.org/:_authToken=${NODE_AUTH_TOKEN};registry=https://registry.npmjs.org/",
  )
}

///|
#cfg(target="native")
async test "executor: builtin setup-node cache npm restores after deferred post save" {
  let workspace = prepare_workspace("executor-builtin-setup-node-cache")
  let node_log_path = workspace + "/setup-node-cache.log"
  let fake_node = test_support_prepare_fake_version_node_bin(
    workspace, node_log_path, "24.9.0",
  )
  @xfs.write_string_to_file(workspace + "/package-lock.json", "{\"lock\":1}\n")
  test_support_remove_tree(executor_test_cache_store_root(workspace))

  let workflow = new_workflow("ci", [
    new_job(
      "save",
      [
        new_uses_step("setup", "actions/setup-node@v4", with_values={
          "node-version": "20",
          "cache": "npm",
        }),
        new_run_step(
          "fill_cache",
          "mkdir -p \"$NPM_CONFIG_CACHE\"\nprintf '%s' ocean > \"$NPM_CONFIG_CACHE/value.txt\"\nprintf '%s' \"${{ steps.setup.outputs.cache-hit }}\" > miss.txt",
          shell=Some("bash"),
        ),
      ],
      env={ "ACTION_RUNNER_SETUP_NODE_BIN": fake_node },
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "restore",
      [
        new_uses_step("setup", "actions/setup-node@v4", with_values={
          "node-version": "20",
          "cache": "npm",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s|%s|%s' \"${{ steps.setup.outputs.cache-hit }}\" \"$(cat \"$NPM_CONFIG_CACHE/value.txt\")\" \"$(cat miss.txt)\" \"$(node --version)\"",
          shell=Some("bash"),
        ),
      ],
      needs=["save"],
      env={ "ACTION_RUNNER_SETUP_NODE_BIN": fake_node },
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")

  let setup = expect_task_report(report, "save/setup")
  inspect(setup.status, content="success")
  let setup_post = expect_task_report(report, "save/setup__post")
  inspect(setup_post.status, content="success")
  let restore_setup = expect_task_report(report, "restore/setup")
  inspect(restore_setup.status, content="success")
  let verify = expect_task_report(report, "restore/verify")
  inspect(verify.status, content="success")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="true|ocean|false|v20.0.0",
  )
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
async test "executor: failed dependency skips downstream job by default" {
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
  inspect(lint_step.status, content="skipped")
  inspect(lint_step.message, content="job if condition evaluated to false")
  let lint_task = expect_task_report(report, "lint/lint")
  inspect(lint_task.status, content="skipped")
}

///|
#cfg(target="native")
async test "executor: job if false skips entire job" {
  let workspace = prepare_workspace("executor-job-if-false")

  let workflow = new_workflow("ci", [
    new_job(
      "skip",
      [new_run_step("nope", "printf '%s' should-not-run")],
      defaults=new_run_defaults(shell=Some("bash")),
      if_condition="false",
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  inspect(report.state, content="completed")

  let step = expect_step_report(report, "skip/nope")
  inspect(step.status, content="skipped")
  let task = expect_task_report(report, "skip/nope")
  inspect(task.status, content="skipped")
}

///|
#cfg(target="native")
async test "executor: job if always runs despite failed needs" {
  let workspace = prepare_workspace("executor-job-if-always")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [new_run_step("fail", "echo boom 1>&2; exit 7")],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
    new_job(
      "cleanup",
      [new_run_step("finalize", "printf '%s' cleanup-ran")],
      needs=["build"],
      defaults=new_run_defaults(shell=Some("bash")),
      if_condition="always()",
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")

  let build_task = expect_task_report(report, "build/fail")
  inspect(build_task.status, content="failed")
  let cleanup_task = expect_task_report(report, "cleanup/finalize")
  inspect(cleanup_task.status, content="success")
  inspect(cleanup_task.stdout, content="cleanup-ran")
}

///|
#cfg(target="native")
async test "executor: step if status functions respect prior step results" {
  let workspace = prepare_workspace("executor-step-if-status")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step("fail", "echo boom 1>&2; exit 9"),
        new_run_step("default_skip", "printf '%s' should-not-run"),
        new_run_step(
          "on_failure",
          "printf '%s' failure-ran",
          if_condition="failure()",
        ),
        new_run_step(
          "always_step",
          "printf '%s' always-ran",
          if_condition="always()",
        ),
        new_run_step(
          "on_cancelled",
          "printf '%s' cancelled-ran",
          if_condition="cancelled()",
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  inspect(expect_task_report(report, "build/fail").status, content="failed")
  inspect(
    expect_task_report(report, "build/default_skip").status,
    content="skipped",
  )
  inspect(
    expect_task_report(report, "build/on_failure").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/on_failure").stdout,
    content="failure-ran",
  )
  inspect(
    expect_task_report(report, "build/always_step").status,
    content="success",
  )
  inspect(
    expect_task_report(report, "build/always_step").stdout,
    content="always-ran",
  )
  inspect(
    expect_task_report(report, "build/on_cancelled").status,
    content="skipped",
  )
}

///|
#cfg(target="native")
async test "executor: continue-on-error keeps workflow green and runs later steps" {
  let workspace = prepare_workspace("executor-continue-on-error")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "fail_soft",
          "echo boom 1>&2; exit 4",
          continue_on_error="true",
        ),
        new_run_step("after", "printf '%s' after-ran"),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(
    expect_task_report(report, "build/fail_soft").status,
    content="failed",
  )
  inspect(
    expect_step_report(report, "build/fail_soft").status,
    content="success",
  )
  inspect(expect_task_report(report, "build/after").status, content="success")
  inspect(expect_task_report(report, "build/after").stdout, content="after-ran")
}

///|
#cfg(target="native")
async test "executor: fromJSON can drive continue-on-error expression" {
  let workspace = prepare_workspace("executor-continue-on-error-fromjson")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "fail_soft",
          "echo boom 1>&2; exit 4",
          continue_on_error="${{ fromJSON(env.SOFT_FAIL) }}",
        ),
        new_run_step("after", "printf '%s' after-ran"),
      ],
      env={ "SOFT_FAIL": "true" },
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(
    expect_task_report(report, "build/fail_soft").status,
    content="failed",
  )
  inspect(
    expect_step_report(report, "build/fail_soft").status,
    content="success",
  )
  inspect(expect_task_report(report, "build/after").status, content="success")
  inspect(expect_task_report(report, "build/after").stdout, content="after-ran")
}

///|
#cfg(target="native")
async test "executor: hashFiles returns a stable hex digest and empty string on no match" {
  let workspace = prepare_workspace("executor-hash-files")
  @xfs.write_string_to_file(workspace + "/package-lock.json", "{\"lock\":1}\n")
  @xfs.write_string_to_file(workspace + "/Gemfile.lock", "GEM\n")
  ensure_dir(workspace + "/vendor")
  @xfs.write_string_to_file(workspace + "/vendor/ignored.lock", "skip\n")
  let script =
    #|printf '%s|%s|%s' \
    #|  "$(test ${#LOCK_HASH} -eq 64 && echo yes || echo no)" \
    #|  "$(test "$LOCK_HASH" = "${{ hashFiles('**/*.lock', '!vendor/**') }}" && echo yes || echo no)" \
    #|  "$(test -z "$MISSING_HASH" && echo yes || echo no)"

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step("show", script, env={
          "LOCK_HASH": "${{ hashFiles('**/*.lock', '!vendor/**') }}",
          "MISSING_HASH": "${{ hashFiles('**/*.missing') }}",
        }),
        new_run_step(
          "gate",
          "printf '%s' hash-ran",
          if_condition="hashFiles('**/*.lock', '!vendor/**') != ''",
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  inspect(
    expect_task_report(report, "build/show").stdout,
    content="yes|yes|yes",
  )
  inspect(expect_task_report(report, "build/gate").status, content="success")
  inspect(expect_task_report(report, "build/gate").stdout, content="hash-ran")
}

///|
#cfg(target="native")
async test "executor: vars context resolves from ACTION_RUNNER_VAR prefix and missing vars are empty" {
  let workspace = prepare_workspace("executor-vars-context")
  let previous_color = executor_test_set_env_var(
    "ACTION_RUNNER_VAR_COLOR", "ocean",
  )
  let previous_enabled = executor_test_set_env_var(
    "ACTION_RUNNER_VAR_FEATURE_ENABLED", "true",
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "show",
          "printf '%s|%s|%s|%s' '${{ vars.COLOR }}' \"$COLOR_FROM_ENV\" \"$(test -z \"$MISSING_FROM_ENV\" && echo yes || echo no)\" '${{ vars.color }}'",
          env={
            "COLOR_FROM_ENV": "${{ vars.COLOR }}",
            "MISSING_FROM_ENV": "${{ vars.MISSING }}",
          },
        ),
        new_run_step(
          "gate",
          "printf '%s' vars-ran",
          if_condition="vars.FEATURE_ENABLED == 'true'",
        ),
        new_run_step(
          "skip_missing",
          "printf '%s' no",
          if_condition="vars.MISSING != ''",
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  executor_test_restore_env_var("ACTION_RUNNER_VAR_COLOR", previous_color)
  executor_test_restore_env_var(
    "ACTION_RUNNER_VAR_FEATURE_ENABLED", previous_enabled,
  )

  inspect(report.ok, content="true")
  inspect(
    expect_task_report(report, "build/show").stdout,
    content="ocean|ocean|yes|ocean",
  )
  inspect(expect_task_report(report, "build/gate").status, content="success")
  inspect(expect_task_report(report, "build/gate").stdout, content="vars-ran")
  inspect(
    expect_task_report(report, "build/skip_missing").status,
    content="skipped",
  )
}

///|
#cfg(target="native")
async test "executor: secrets context resolves from ACTION_RUNNER_SECRET prefix and missing secrets are empty" {
  let workspace = prepare_workspace("executor-secrets-context")
  let previous_token = executor_test_set_env_var(
    "ACTION_RUNNER_SECRET_TOKEN", "s3cr3t",
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step(
          "show",
          "printf '%s|%s|%s|%s' '${{ secrets.TOKEN }}' \"$TOKEN_FROM_ENV\" \"$(test -z \"$MISSING_FROM_ENV\" && echo yes || echo no)\" '${{ secrets.token }}'",
          env={
            "TOKEN_FROM_ENV": "${{ secrets.TOKEN }}",
            "MISSING_FROM_ENV": "${{ secrets.MISSING }}",
          },
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  executor_test_restore_env_var("ACTION_RUNNER_SECRET_TOKEN", previous_token)

  inspect(report.ok, content="true")
  inspect(
    expect_task_report(report, "build/show").stdout,
    content="s3cr3t|s3cr3t|yes|s3cr3t",
  )
}

///|
#cfg(target="native")
async test "executor: steps outcome and conclusion are available to later steps and if" {
  let workspace = prepare_workspace("executor-step-status-context")

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_run_step("first", "exit 0"),
        new_run_step("second", "exit 1", continue_on_error="true"),
        new_run_step(
          "show",
          "printf '%s|%s|%s|%s|%s|%s' '${{ steps.first.outcome }}' '${{ steps.first.conclusion }}' '${{ steps.second.outcome }}' '${{ steps.second.conclusion }}' \"$FIRST_OUTCOME\" \"$SECOND_CONCLUSION\"",
          env={
            "FIRST_OUTCOME": "${{ steps.first.outcome }}",
            "SECOND_CONCLUSION": "${{ steps.second.conclusion }}",
          },
        ),
        new_run_step(
          "gate",
          "printf '%s' gate-ran",
          if_condition="steps.second.outcome == 'failure' && steps.second.conclusion == 'success'",
        ),
      ],
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(
    expect_task_report(report, "build/show").stdout,
    content="success|success|failure|success|success|success",
  )
  inspect(expect_task_report(report, "build/gate").status, content="success")
  inspect(expect_task_report(report, "build/gate").stdout, content="gate-ran")
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
async test "executor: wasm actions run via configured wasm runner" {
  let workspace = prepare_workspace("executor-wasm-action")
  let tools_root = prepare_workspace("executor-wasm-action-tools")
  let wasm_log_path = tools_root + "/wasm.log"
  let wasm_bin = test_support_prepare_fake_wasm_bin(tools_root, wasm_log_path)
  let wasm_root = workspace + "/wasm-actions"
  ensure_dir(wasm_root)
  ensure_dir(wasm_root + "/std")
  ensure_dir(wasm_root + "/std/echo")
  ensure_dir(wasm_root + "/std/echo/v1")
  @xfs.write_string_to_file(
    wasm_root + "/std/echo/v1/main.wasm",
    "#!/bin/sh\n" +
    "set -eu\n" +
    "printf '%s|%s' \"${INPUT_MESSAGE:-}\" \"$GITHUB_WORKSPACE\"\n" +
    "printf 'result=from-wasm\\n' > \"$GITHUB_OUTPUT\"\n",
  )
  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("module", "wasm://std/echo@v1", with_values={
          "message": "hello",
        }),
        new_run_step(
          "verify",
          "printf '%s' '${{ steps.module.outputs.result }}'",
          shell=Some("bash"),
        ),
      ],
      env={
        "ACTION_RUNNER_WASM_BIN": wasm_bin,
        "ACTION_RUNNER_WASM_ACTION_ROOT": wasm_root,
      },
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  let module_report = expect_task_report(report, "build/module")
  inspect(module_report.kind, content="action")
  inspect(module_report.status, content="success")
  inspect(
    module_report.stdout.trim(chars=" \n\r\t").to_string(),
    content="hello|" + workspace,
  )
  let verify = expect_task_report(report, "build/verify")
  inspect(verify.stdout.trim(chars=" \n\r\t").to_string(), content="from-wasm")
  let wasm_log = @xfs.read_file_to_string(wasm_log_path)
  assert_eq(wasm_log.contains("main.wasm"), true)
}

///|
#cfg(target="native")
async test "executor: wasm actions fail when module is missing" {
  let workspace = prepare_workspace("executor-wasm-action-missing")
  let tools_root = prepare_workspace("executor-wasm-action-missing-tools")
  let wasm_log_path = tools_root + "/wasm.log"
  let wasm_bin = test_support_prepare_fake_wasm_bin(tools_root, wasm_log_path)
  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [new_uses_step("module", "wasm://std/echo@v1")],
      env={
        "ACTION_RUNNER_WASM_BIN": wasm_bin,
        "ACTION_RUNNER_WASM_ACTION_ROOT": workspace + "/missing-root",
      },
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow(workflow),
    workspace_root=workspace,
  )

  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  let module_report = expect_task_report(report, "build/module")
  inspect(module_report.kind, content="action")
  inspect(module_report.status, content="failed")
  inspect(
    module_report.stderr,
    content="wasm module for 'std/echo@v1' was not found",
  )
  let wasm_log = @xfs.read_file_to_string(wasm_log_path)
  inspect(wasm_log, content="")
}

///|
#cfg(target="native")
async test "executor: custom registry node action runs via configured registry root" {
  let workspace = prepare_workspace("executor-custom-registry-node")
  let tools_root = prepare_workspace("executor-custom-registry-node-tools")
  let registry_root = prepare_workspace(
    "executor-custom-registry-node-registry",
  )
  let node_log_path = tools_root + "/node.log"
  let node_bin = test_support_prepare_fake_node_bin(tools_root, node_log_path)
  let previous_registry_root = executor_test_set_env_var(
    "ACTION_RUNNER_ACTION_REGISTRY_ROOT", registry_root,
  )
  let action_root = prepare_custom_registry_action_root_for_executor(
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
  @xfs.write_string_to_file(
    action_root + "/index.sh",
    "#!/bin/sh\n" +
    "set -eu\n" +
    "printf '%s' \"${INPUT_MESSAGE:-}\" > \"$GITHUB_WORKSPACE/registry-node.txt\"\n" +
    "printf 'result=from-registry-node\\n' > \"$GITHUB_OUTPUT\"\n",
  )

  let workflow = new_workflow("ci", [
    new_job(
      "build",
      [
        new_uses_step("setup", "bit://std/cache@v1", with_values={
          "message": "from-registry",
        }),
        new_run_step(
          "verify",
          "printf '%s|%s' '${{ steps.setup.outputs.result }}' \"$(cat registry-node.txt)\"",
          shell=Some("bash"),
        ),
      ],
      env={ "ACTION_RUNNER_NODE_BIN": node_bin },
      defaults=new_run_defaults(shell=Some("bash")),
    ),
  ])

  let report = execute_lowered_native(
    lower_push_workflow_in_workspace(workflow, workspace),
    workspace_root=workspace,
  )
  executor_test_restore_env_var(
    "ACTION_RUNNER_ACTION_REGISTRY_ROOT", previous_registry_root,
  )

  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  let setup_report = expect_task_report(report, "build/setup")
  inspect(setup_report.status, content="success")
  let verify = expect_task_report(report, "build/verify")
  inspect(
    verify.stdout.trim(chars=" \n\r\t").to_string(),
    content="from-registry-node|from-registry",
  )
  let node_log = @xfs.read_file_to_string(node_log_path)
  assert_eq(node_log.contains(action_root + "/index.sh"), true)
}

///|
#cfg(target="native")
async test "executor: job container runs run steps via docker adapter" {
  let workspace = prepare_workspace("executor-job-container")
  ensure_dir(workspace + "/nested")
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
          new_run_step(
            "show",
            "printf '%s|%s|%s' \"$CONTAINER_FLAG\" \"$STEP_FLAG\" \"$PWD\"",
            env={ "STEP_FLAG": "from-step" },
          ),
        ],
        container=Some(
          new_job_container_spec("alpine:3.21", env={
            "CONTAINER_FLAG": "from-container",
          }),
        ),
        defaults=new_run_defaults(working_directory=Some("nested")),
      ),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
  )

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(expect_step_report(report, "build/show").status, content="success")
  inspect(
    expect_task_report(report, "build/show").stdout,
    content="from-container|from-step|" + workspace + "/nested",
  )
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(docker_log.contains("run\n--rm\n"), true)
  assert_eq(docker_log.contains("alpine:3.21"), true)
  assert_eq(docker_log.contains("-w\n" + workspace + "/nested\n"), true)
}

///|
#cfg(target="native")
async test "executor: job container shares docker network with job services" {
  let workspace = prepare_workspace("executor-job-container-services-network")
  let docker_log_path = workspace + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(
    workspace, docker_log_path,
  )

  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [new_run_step("show", "printf '%s' hi", shell=Some("bash"))],
        container=Some(new_job_container_spec("alpine:3.21")),
        services={
          "postgres": new_job_container_spec(
            "postgres:16",
            ports=["5432:5432"],
            options=Some("--health-cmd pg_isready"),
          ),
        },
        defaults=new_run_defaults(shell=Some("bash")),
      ),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
  )

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(expect_task_report(report, "build/show").status, content="success")
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(
    docker_log.contains("network\ncreate\naction-runner-job-build\n"),
    true,
  )
  assert_eq(docker_log.contains("--network\naction-runner-job-build\n"), true)
  assert_eq(docker_log.contains("--network-alias\npostgres\n"), true)
  assert_eq(docker_log.contains("network\nrm\naction-runner-job-build\n"), true)
}

///|
#cfg(target="native")
async test "executor: job services start before steps, expose ports context, and cleanup after job" {
  let workspace = prepare_workspace("executor-job-services")
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
          new_run_step(
            "show",
            "printf '%s|%s' \"${{ job.services.postgres.ports[5432] }}\" \"$PORT_FROM_ENV\" > out.txt",
            shell=Some("bash"),
            env={ "PORT_FROM_ENV": "${{ job.services.postgres.ports[5432] }}" },
          ),
          new_run_step(
            "verify",
            "printf '|%s' yes >> out.txt",
            shell=Some("bash"),
            if_condition="${{ job.services.postgres.ports[5432] == '5432' }}",
          ),
        ],
        services={
          "postgres": new_job_container_spec(
            "postgres:16",
            env={ "POSTGRES_DB": "app" },
            ports=["5432:5432"],
            volumes=["db:/var/lib/postgresql/data"],
            options=Some("--health-cmd pg_isready"),
          ),
        },
        defaults=new_run_defaults(shell=Some("bash")),
      ),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
  )

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  inspect(report.state, content="completed")
  inspect(expect_task_report(report, "build/show").status, content="success")
  inspect(expect_task_report(report, "build/verify").status, content="success")
  inspect(
    @xfs.read_file_to_string(workspace + "/out.txt"),
    content="5432|5432|yes",
  )
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(docker_log.contains("run\n-d\n--rm\n--name\n"), true)
  assert_eq(docker_log.contains("action-runner-service-build__postgres"), true)
  assert_eq(docker_log.contains("postgres:16"), true)
  assert_eq(docker_log.contains("-e\nPOSTGRES_DB=app\n"), true)
  assert_eq(docker_log.contains("-p\n5432:5432\n"), true)
  assert_eq(docker_log.contains("-v\ndb:/var/lib/postgresql/data\n"), true)
  assert_eq(docker_log.contains("--health-cmd\npg_isready\n"), true)
  assert_eq(docker_log.contains("inspect\n--format\n"), true)
  assert_eq(
    docker_log.contains("rm\n-f\naction-runner-service-build__postgres\n"),
    true,
  )
}

///|
#cfg(target="native")
async test "executor: job services fail when health check becomes unhealthy" {
  let workspace = prepare_workspace("executor-job-services-health-fail")
  let docker_log_path = workspace + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(
    workspace,
    docker_log_path,
    inspect_sequence="starting,unhealthy",
  )

  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [new_run_step("show", "printf '%s' never", shell=Some("bash"))],
        services={
          "postgres": new_job_container_spec(
            "postgres:16",
            ports=["5432:5432"],
            options=Some("--health-cmd pg_isready"),
          ),
        },
        defaults=new_run_defaults(shell=Some("bash")),
      ),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
  )

  let lowered = lower_push_workflow(workflow)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="false")
  inspect(report.state, content="partial_failed")
  inspect(expect_task_report(report, "build/show").status, content="failed")
  inspect(
    expect_task_report(report, "build/show").stderr.contains("became unhealthy"),
    content="true",
  )
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(docker_log.contains("inspect\n--format\n"), true)
  assert_eq(
    docker_log.contains("rm\n-f\naction-runner-service-build__postgres\n"),
    true,
  )
}

///|
#cfg(target="native")
async test "executor: job container runs docker action as sibling container" {
  let workspace = prepare_workspace("executor-job-container-docker-action")
  let docker_log_path = workspace + "/docker.log"
  let docker_bin = test_support_prepare_fake_docker_bin(
    workspace, docker_log_path,
  )
  let action_root = prepare_cached_github_action_root_for_executor(
    "mizchi-test",
    "docker-action-container",
    "v1",
    subpath="action",
  )
  let action_src =
    #|name: Remote Docker In Container
    #|runs:
    #|  using: docker
    #|  image: Dockerfile
    #|  entrypoint: /bin/sh
    #|  args:
    #|    - -c
    #|    - printf '%s' "${CONTAINER_FLAG:-}" > "$GITHUB_WORKSPACE/docker.txt"
  @xfs.write_string_to_file(action_root + "/action.yml", action_src)
  @xfs.write_string_to_file(action_root + "/Dockerfile", "FROM alpine:3.21\n")

  let workflow = new_workflow(
    "ci",
    [
      new_job(
        "build",
        [
          new_uses_step(
            "remote", "mizchi-test/docker-action-container/action@v1",
          ),
        ],
        container=Some(
          new_job_container_spec(
            "node:20-bookworm",
            env={ "CONTAINER_FLAG": "from-container" },
            volumes=["cache:/cache"],
          ),
        ),
      ),
    ],
    env={ "ACTION_RUNNER_DOCKER_BIN": docker_bin },
  )

  let lowered = lower_push_workflow_in_workspace(workflow, workspace)
  inspect(lowered.errors, content="[]")

  let report = execute_lowered_native(lowered, workspace_root=workspace)
  inspect(report.ok, content="true")
  let remote = expect_task_report(report, "build/remote")
  inspect(remote.status, content="success")
  inspect(@xfs.read_file_to_string(workspace + "/docker.txt"), content="")
  let docker_log = @xfs.read_file_to_string(docker_log_path)
  assert_eq(docker_log.contains("-v\ncache:/cache\n"), true)
  assert_eq(docker_log.contains("CONTAINER_FLAG=from-container"), false)
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
