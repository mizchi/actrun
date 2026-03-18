///|
test "nix_wrap_command: NixNone passes through" {
  let (cmd, args) = nix_wrap_command(NixNone, "bash", ["--norc", "script.sh"])
  inspect(cmd, content="bash")
  inspect(
    args,
    content=(
      #|["--norc", "script.sh"]
    ),
  )
}

///|
test "nix_wrap_command: Flake wraps with nix develop" {
  let (cmd, args) = nix_wrap_command(Flake, "bash", ["--norc", "script.sh"])
  inspect(cmd, content="nix")
  inspect(
    args,
    content=(
      #|["develop", "--command", "bash", "--norc", "script.sh"]
    ),
  )
}

///|
test "nix_wrap_command: Shell wraps with nix-shell --run" {
  let (cmd, args) = nix_wrap_command(Shell, "bash", ["--norc", "script.sh"])
  inspect(cmd, content="nix-shell")
  inspect(args[0], content="--run")
}

///|
test "nix_wrap_command: Packages wraps with nix-shell -p" {
  let (cmd, args) = nix_wrap_command(
    Packages(["python312", "nodejs"]),
    "bash",
    ["script.sh"],
  )
  inspect(cmd, content="nix-shell")
  inspect(
    args,
    content=(
      #|["-p", "python312", "-p", "nodejs", "--run", "'bash' 'script.sh'"]
    ),
  )
}

///|
test "is_commit_sha: full 40-char SHA is recognized" {
  assert_eq(is_commit_sha("abc1234def5678abc1234def5678abc1234def56"), true)
}

///|
test "is_commit_sha: short 7-char SHA is recognized" {
  assert_eq(is_commit_sha("abc1234"), true)
}

///|
test "is_commit_sha: uppercase hex chars are valid" {
  assert_eq(is_commit_sha("ABC1234DEF5678ABC1234DEF5678ABC1234DEF56"), true)
}

///|
test "is_commit_sha: tag is not a SHA" {
  assert_eq(is_commit_sha("v1"), false)
  assert_eq(is_commit_sha("v1.2.3"), false)
}

///|
test "is_commit_sha: branch name is not a SHA" {
  assert_eq(is_commit_sha("main"), false)
}

///|
test "is_commit_sha: too short hex string is not a SHA" {
  assert_eq(is_commit_sha("abc123"), false)
}

///|
test "is_commit_sha: empty string is not a SHA" {
  assert_eq(is_commit_sha(""), false)
}

///|
test "canonicalize_abs_path: resolves parent segments" {
  inspect(canonicalize_abs_path("/a/b/../c"), content="/a/c")
  inspect(canonicalize_abs_path("/a/b/../../c"), content="/c")
  inspect(canonicalize_abs_path("/a/./b/./c"), content="/a/b/c")
  inspect(canonicalize_abs_path("/a/b/c/../../d"), content="/a/d")
}

///|
test "canonicalize_abs_path: stops at root" {
  inspect(canonicalize_abs_path("/a/../../../.."), content="/")
}

///|
test "validate_workspace_path: rejects traversal with leading dotdot" {
  assert_eq(validate_workspace_path("/home/user/workspace", "../../etc"), None)
}

///|
test "validate_workspace_path: rejects traversal with intermediate dotdot" {
  assert_eq(
    validate_workspace_path("/home/user/workspace", "sub/../../.."),
    None,
  )
}

///|
test "validate_workspace_path: accepts legitimate subpath" {
  assert_true(
    validate_workspace_path("/home/user/workspace", "subdir/file.txt") != None,
  )
}

///|
/// Helper: run a shell command and return (exit_code, stdout, stderr).
async fn wbtest_run(
  cmd : String,
  args : Array[String],
) -> (Int, String, String) {
  let (code, stdout, stderr) = @process.collect_output(cmd, args)
  (code, stdout.text(), stderr.text())
}

///|
/// Helper to create a temporary directory for symlink tests.
async fn wbtest_setup_tmpdir() -> String {
  let (code, stdout, _) = wbtest_run("mktemp", ["-d"])
  assert_eq(code, 0)
  trim_exec_output(stdout)
}

///|
/// Helper to clean up test directory.
async fn wbtest_cleanup(path : String) -> Unit {
  let _ = wbtest_run("rm", ["-rf", path])
}

///|
async test "validate_workspace_path_real: rejects symlink pointing outside workspace" {
  let tmpdir = wbtest_setup_tmpdir()
  let workspace = tmpdir + "/workspace"
  let outside = tmpdir + "/outside"
  let _ = wbtest_run("mkdir", ["-p", workspace + "/subdir"])
  let _ = wbtest_run("mkdir", ["-p", outside])
  let _ = wbtest_run("sh", ["-c", "echo secret > " + outside + "/secret.txt"])
  // Create a symlink inside workspace pointing outside
  let _ = wbtest_run("ln", ["-s", outside, workspace + "/evil-link"])
  // String-based validation passes (doesn't know about symlinks)
  assert_true(
    validate_workspace_path(workspace, "evil-link/secret.txt") != None,
  )
  // Real path validation rejects (symlink resolves outside workspace)
  assert_eq(
    validate_workspace_path_real(workspace, "evil-link/secret.txt"),
    None,
  )
  wbtest_cleanup(tmpdir)
}

///|
async test "validate_workspace_path_real: accepts symlink within workspace" {
  let tmpdir = wbtest_setup_tmpdir()
  let workspace = tmpdir + "/workspace"
  let _ = wbtest_run("mkdir", ["-p", workspace + "/actual"])
  let _ = wbtest_run("sh", ["-c", "echo ok > " + workspace + "/actual/file.txt"])
  // Symlink within workspace pointing to another dir in workspace
  let _ = wbtest_run("ln", ["-s", workspace + "/actual", workspace + "/link"])
  // Both validations should pass
  assert_true(validate_workspace_path(workspace, "link/file.txt") != None)
  assert_true(validate_workspace_path_real(workspace, "link/file.txt") != None)
  wbtest_cleanup(tmpdir)
}

///|
async test "validate_workspace_path_real: rejects nested symlink chain escaping workspace" {
  let tmpdir = wbtest_setup_tmpdir()
  let workspace = tmpdir + "/workspace"
  let outside = tmpdir + "/outside"
  let _ = wbtest_run("mkdir", ["-p", workspace + "/a/b"])
  let _ = wbtest_run("mkdir", ["-p", outside])
  let _ = wbtest_run("sh", ["-c", "echo data > " + outside + "/data.txt"])
  // workspace/a/b/link -> outside
  let _ = wbtest_run("ln", ["-s", outside, workspace + "/a/b/link"])
  // String-based passes
  assert_true(validate_workspace_path(workspace, "a/b/link/data.txt") != None)
  // Real path rejects
  assert_eq(validate_workspace_path_real(workspace, "a/b/link/data.txt"), None)
  wbtest_cleanup(tmpdir)
}

///|
async test "resolve_real_path: resolves symlink to real target" {
  let tmpdir = wbtest_setup_tmpdir()
  let _ = wbtest_run("mkdir", ["-p", tmpdir + "/real"])
  let _ = wbtest_run("ln", ["-s", tmpdir + "/real", tmpdir + "/link"])
  let resolved = resolve_real_path(tmpdir + "/link")
  // Resolve tmpdir itself to handle macOS /var -> /private/var
  let real_tmpdir = resolve_real_path(tmpdir)
  inspect(resolved, content=real_tmpdir + "/real")
  wbtest_cleanup(tmpdir)
}

///|
async test "resolve_real_path: returns path for non-existent path" {
  let path = "/nonexistent/path/that/does/not/exist"
  let resolved = resolve_real_path(path)
  // realpath -m resolves even non-existent paths
  inspect(resolved, content=path)
}
