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
  assert_ne(
    validate_workspace_path("/home/user/workspace", "subdir/file.txt"),
    None,
  )
}
