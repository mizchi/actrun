///|
fn expect_cli_options(result : CliParseResult) -> CliOptions {
  match result.options {
    Some(options) => options
    None => abort(result.errors.join("\n"))
  }
}

///|
fn ensure_main_test_dir(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
test "cli: parse local workflow path" {
  let result = parse_cli_args(["action_runner", ".github/workflows/ci.yml"])
  inspect(result.errors, content="[]")

  let options = expect_cli_options(result)
  inspect(options.workflow_path, content=".github/workflows/ci.yml")
  inspect(options.changed_paths, content="[]")
  assert_eq(options.repo_root, None)
  assert_eq(options.workspace_root, None)
  inspect(local_workspace_root(options.workflow_path), content=".")
}

///|
test "cli: parse repo mode flags" {
  let result = parse_cli_args([
    "action_runner", ".github/workflows/ci.yml", "--repo", "/repo", "--workspace",
    "/tmp/work", "--event", "push.json", "--ref", "feature/demo", "--before", "def456",
    "--after", "abc123", "--repository", "mizchi/action_runner", "--changed", "src/lib.mbt",
    "--changed", "README.md",
  ])
  inspect(result.errors, content="[]")

  let options = expect_cli_options(result)
  inspect(options.repo_root.unwrap_or(""), content="/repo")
  inspect(options.workspace_root.unwrap_or(""), content="/tmp/work")
  inspect(options.event_path.unwrap_or(""), content="push.json")
  inspect(options.ref_name, content="feature/demo")
  inspect(options.before_sha, content="def456")
  inspect(options.after_sha, content="abc123")
  inspect(options.repository, content="mizchi/action_runner")
  inspect(options.changed_paths, content="[\"src/lib.mbt\", \"README.md\"]")
}

///|
test "cli: reject missing option value" {
  let result = parse_cli_args([
    "action_runner", ".github/workflows/ci.yml", "--repo",
  ])

  inspect(result.errors, content="[\"missing value for --repo\"]")
}

///|
test "cli: parse GitHub repository from https remote url" {
  inspect(
    github_repository_from_remote_url(
      "https://github.com/mizchi/action_runner.git",
    ),
    content="mizchi/action_runner",
  )
}

///|
test "cli: parse GitHub repository from ssh remote url" {
  inspect(
    github_repository_from_remote_url("git@github.com:mizchi/action_runner.git"),
    content="mizchi/action_runner",
  )
}

///|
test "cli: extract origin remote url from git config text" {
  let config =
    #|[core]
    #|  repositoryformatversion = 0
    #|[remote "upstream"]
    #|  url = https://github.com/other/project.git
    #|[remote "origin"]
    #|  url = git@github.com:mizchi/action_runner.git
    #|  fetch = +refs/heads/*:refs/remotes/origin/*
  inspect(
    origin_remote_url_from_git_config(config).unwrap_or(""),
    content="git@github.com:mizchi/action_runner.git",
  )
  inspect(
    github_repository_from_git_config(config).unwrap_or(""),
    content="mizchi/action_runner",
  )
}

///|
#cfg(target="native")
test "cli: infer GitHub repository from repo root origin config" {
  ensure_main_test_dir("_build")
  ensure_main_test_dir("_build/test-main")
  let repo_root = "_build/test-main/repository-detect"
  let git_dir = repo_root + "/.git"
  let config =
    #|[remote "origin"]
    #|  url = https://github.com/mizchi/action_runner.git
    #|  fetch = +refs/heads/*:refs/remotes/origin/*
  ensure_main_test_dir(repo_root)
  ensure_main_test_dir(git_dir)
  @xfs.write_string_to_file(git_dir + "/config", config)

  inspect(
    origin_remote_url_from_repo_root(repo_root).unwrap_or(""),
    content="https://github.com/mizchi/action_runner.git",
  )
  inspect(
    github_repository_from_repo_root(repo_root).unwrap_or(""),
    content="mizchi/action_runner",
  )
}

///|
test "cli: explicit flags override values from event payload" {
  let base = @ar.new_push_event(
    "main",
    ["README.md"],
    before_sha="def456",
    after_sha="abc123",
    repository="from/event",
    actor="octocat",
  )
  let options = expect_cli_options(
    parse_cli_args([
      "action_runner", ".github/workflows/ci.yml", "--event", "push.json", "--repository",
      "from/cli", "--after", "fff999", "--changed", "src/lib.mbt",
    ]),
  )
  let merged = merge_cli_push_event(base, options)

  inspect(merged.ref_name, content="main")
  inspect(merged.before_sha, content="def456")
  inspect(merged.after_sha, content="fff999")
  inspect(merged.repository, content="from/cli")
  inspect(merged.actor, content="octocat")
  inspect(merged.changed_paths, content="[\"src/lib.mbt\"]")
}

///|
test "cli: event file enables trigger checks" {
  let options = expect_cli_options(
    parse_cli_args([
      "action_runner", ".github/workflows/ci.yml", "--event", "push.json",
    ]),
  )

  inspect(should_check_trigger(options), content="true")
}
