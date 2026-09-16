///|
fn expect_git_workspace(result : GitWorkspaceResult) -> GitWorkspace {
  match result.workspace {
    Some(workspace) => workspace
    None => abort(result.errors.join("\n"))
  }
}

///|
fn runtime_test_env(timestamp : Int64) -> Map[String, String] {
  let date = timestamp.to_string() + " +0000"
  {
    "GIT_AUTHOR_NAME": "Author",
    "GIT_AUTHOR_EMAIL": "a@b.com",
    "GIT_COMMITTER_NAME": "Author",
    "GIT_COMMITTER_EMAIL": "a@b.com",
    "GIT_AUTHOR_DATE": date,
    "GIT_COMMITTER_DATE": date,
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
  }
}

///|
async fn runtime_test_git(
  cwd : String,
  args : Array[String],
  timestamp : Int64,
) -> String {
  let (code, stdout, stderr) = @process.collect_output(
    "git",
    args,
    cwd~,
    extra_env=runtime_test_env(timestamp),
  )
  if code != 0 {
    abort("git " + args.join(" ") + " failed: " + stderr.text())
  }
  stdout.text().trim().to_owned()
}

///|
fn io_error_message(err : @xfs.IOError) -> String {
  let @xfs.IOError(message) = err
  message
}

///|
fn runtime_test_remove_all(path : String) -> Unit raise @xfs.IOError {
  if !@xfs.path_exists(path) {
    return
  }
  if @xfs.is_dir(path) {
    for entry in @xfs.read_dir(path) {
      runtime_test_remove_all(path + "/" + entry)
    }
    @xfs.remove_dir(path)
  } else {
    @xfs.remove_file(path)
  }
}

///|
fn runtime_test_reset_dir(path : String) -> Unit {
  runtime_test_remove_all(path) catch {
    err => abort("failed to reset " + path + ": " + io_error_message(err))
  }
  ensure_dir_for_runtime_test(path)
}

///|
fn ensure_dir_for_runtime_test(path : String) -> Unit {
  if @xfs.path_exists(path) {
    return
  }
  let parts = path.split("/").map(part => part.to_owned()).collect()
  let mut current = ""
  for part in parts {
    if part.length() == 0 {
      continue
    }
    current = if current.length() == 0 { part } else { current + "/" + part }
    if !@xfs.path_exists(current) {
      @xfs.create_dir(current) catch {
        err =>
          abort("failed to create " + current + ": " + io_error_message(err))
      }
    }
  }
}

///|
/// Initialize `root` as a repository on `main`, add `file` and commit it.
async fn setup_git_repo(
  root : String,
  file : String,
  content : String,
  message : String,
  timestamp : Int64,
) -> String {
  runtime_test_reset_dir(root)
  ignore(runtime_test_git(root, ["init", "--quiet"], timestamp))
  ignore(
    runtime_test_git(
      root,
      ["symbolic-ref", "HEAD", "refs/heads/main"],
      timestamp,
    ),
  )
  ignore(
    runtime_test_git(root, ["config", "commit.gpgsign", "false"], timestamp),
  )
  commit_repo_file(root, file, content, message, timestamp)
}

///|
async fn commit_repo_file(
  root : String,
  file : String,
  content : String,
  message : String,
  timestamp : Int64,
) -> String {
  @xfs.write_string_to_file(root + "/" + file, content) catch {
    err => abort("failed to write " + file + ": " + io_error_message(err))
  }
  ignore(runtime_test_git(root, ["add", "--", file], timestamp))
  ignore(
    runtime_test_git(root, ["commit", "--quiet", "-m", message], timestamp),
  )
  runtime_test_git(root, ["rev-parse", "HEAD"], timestamp)
}

///|
fn runtime_test_read(path : String) -> String {
  @xfs.read_file_to_string(path) catch {
    err => abort("failed to read " + path + ": " + io_error_message(err))
  }
}

///|
async test "runtime: materialize push workspace from git repo" {
  let repo_root = "_build/runtime-test/materialize/repo"
  let workspace_root = "_build/runtime-test/materialize/work"
  let commit_sha = setup_git_repo(
    repo_root, "hello.txt", "hello\n", "Initial commit", 1700000000L,
  )
  let event = new_push_event("main", ["hello.txt"], after_sha=commit_sha)
  let result = materialize_git_push_workspace(repo_root, event, workspace_root)
  @debug.debug_inspect(result.errors, content="[]")
  let workspace = expect_git_workspace(result)
  @debug.assert_eq(workspace.git_dir.has_suffix("/materialize/repo/.git"), true)
  @debug.assert_eq(workspace.commit_sha, commit_sha)
  @debug.debug_inspect(
    workspace.refname,
    content=(
      #|"main"
    ),
  )
  @debug.debug_inspect(
    runtime_test_read(workspace_root + "/hello.txt"),
    content=(
      #|"hello\n"
    ),
  )
  @debug.debug_inspect(
    runtime_test_read(workspace_root + "/.git/HEAD"),
    content=(
      #|"ref: refs/heads/main\n"
    ),
  )
  @debug.assert_eq(
    runtime_test_read(workspace_root + "/.git/config").contains(repo_root),
    true,
  )
}

///|
async test "runtime: materialize uses HEAD when after sha is missing" {
  let repo_root = "_build/runtime-test/head/repo"
  let workspace_root = "_build/runtime-test/head/work"
  let commit_sha = setup_git_repo(
    repo_root, "hello.txt", "head\n", "Head commit", 1700000001L,
  )
  let event = new_push_event("", ["hello.txt"])
  let result = materialize_git_push_workspace(
    repo_root,
    event,
    workspace_root,
    remote_url="https://example.com/org/repo.git",
  )
  @debug.debug_inspect(result.errors, content="[]")
  let workspace = expect_git_workspace(result)
  @debug.assert_eq(workspace.commit_sha, commit_sha)
  @debug.debug_inspect(
    workspace.refname,
    content=(
      #|"main"
    ),
  )
  @debug.assert_eq(
    runtime_test_read(workspace_root + "/.git/config").contains(
      "https://example.com/org/repo.git",
    ),
    true,
  )
}

///|
async test "runtime: compute changed paths from before and after" {
  let repo_root = "_build/runtime-test/changed/repo"
  let before_sha = setup_git_repo(
    repo_root, "a.txt", "one\n", "Initial commit", 1700000002L,
  )
  let after_sha = commit_repo_file(
    repo_root, "b.txt", "two\n", "Add b", 1700000003L,
  )
  let event = new_push_event("main", [], before_sha~, after_sha~)
  let result = compute_git_changed_paths(repo_root, event)
  @debug.debug_inspect(result.errors, content="[]")
  @debug.assert_eq(result.base_sha, before_sha)
  @debug.assert_eq(result.head_sha, after_sha)
  @debug.debug_inspect(result.paths, content="[\"b.txt\"]")
}

///|
async test "runtime: compute changed paths falls back to first parent" {
  let repo_root = "_build/runtime-test/parent/repo"
  let before_sha = setup_git_repo(
    repo_root, "a.txt", "one\n", "Initial commit", 1700000004L,
  )
  let after_sha = commit_repo_file(
    repo_root, "a.txt", "two\n", "Modify a", 1700000005L,
  )
  let event = new_push_event("main", [], after_sha~)
  let result = compute_git_changed_paths(repo_root, event)
  @debug.debug_inspect(result.errors, content="[]")
  @debug.assert_eq(result.base_sha, before_sha)
  @debug.assert_eq(result.head_sha, after_sha)
  @debug.debug_inspect(result.paths, content="[\"a.txt\"]")
}

///|
async test "runtime: compute changed paths for root commit lists all files" {
  let repo_root = "_build/runtime-test/root/repo"
  let head_sha = setup_git_repo(
    repo_root, "a.txt", "one\n", "Initial commit", 1700000006L,
  )
  let event = new_push_event("main", [], after_sha=head_sha)
  let result = compute_git_changed_paths(repo_root, event)
  @debug.debug_inspect(result.errors, content="[]")
  @debug.debug_inspect(
    result.base_sha,
    content=(
      #|""
    ),
  )
  @debug.debug_inspect(result.paths, content="[\"a.txt\"]")
}

///|
async test "runtime: materialize clears stale workspace files" {
  let repo_root = "_build/runtime-test/stale/repo"
  let workspace_root = "_build/runtime-test/stale/work"
  let commit_sha = setup_git_repo(
    repo_root, "hello.txt", "fresh\n", "Fresh commit", 1700000007L,
  )
  runtime_test_reset_dir(workspace_root)
  @xfs.write_string_to_file(workspace_root + "/stale.txt", "stale\n") catch {
    err => abort("failed to write stale file: " + io_error_message(err))
  }
  let event = new_push_event("main", ["hello.txt"], after_sha=commit_sha)
  let result = materialize_git_push_workspace(repo_root, event, workspace_root)
  @debug.debug_inspect(result.errors, content="[]")
  @debug.assert_eq(@xfs.path_exists(workspace_root + "/stale.txt"), false)
  @debug.debug_inspect(
    runtime_test_read(workspace_root + "/hello.txt"),
    content=(
      #|"fresh\n"
    ),
  )
}

///|
async test "runtime: materialize rejects overlapping repo and workspace" {
  let repo_root = "_build/runtime-test/overlap/repo"
  let commit_sha = setup_git_repo(
    repo_root, "hello.txt", "hello\n", "Initial commit", 1700000008L,
  )
  let event = new_push_event("main", ["hello.txt"], after_sha=commit_sha)
  let result = materialize_git_push_workspace(
    repo_root,
    event,
    repo_root + "/work",
  )
  @debug.debug_inspect(
    result.errors,
    content="[\"workspace root must not overlap repo root\"]",
  )
}

///|
async test "runtime: materialize reports missing repository" {
  let result = materialize_git_push_workspace(
    "_build/runtime-test/missing/repo",
    new_push_event("main", []),
    "_build/runtime-test/missing/work",
  )
  @debug.debug_inspect(
    result.errors,
    content="[\"git repository not found: _build/runtime-test/missing/repo\"]",
  )
}
