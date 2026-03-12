///|
fn expect_bit_workspace(result : BitWorkspaceResult) -> BitWorkspace {
  match result.workspace {
    Some(workspace) => workspace
    None => abort(result.errors.join("\n"))
  }
}

///|
fn setup_bit_repo(
  fs : &@bit.FileSystem,
  rfs : &@bit.RepoFileSystem,
  root : String,
  file : String,
  content : String,
  message : String,
  timestamp : Int64,
  allow_empty? : Bool = false,
) -> @bit.ObjectId raise @bit.GitError {
  ignore(try? @bitlib.init_repo(fs, root))
  fs.write_string(root + "/" + file, content)
  @bitlib.add_paths(fs, rfs, root, [file])
  @bitlib.commit(
    fs,
    rfs,
    root,
    message,
    "Author <a@b.com>",
    timestamp,
    allow_empty~,
  )
}

///|
fn commit_repo_file(
  fs : &@bit.FileSystem,
  rfs : &@bit.RepoFileSystem,
  root : String,
  file : String,
  content : String,
  message : String,
  timestamp : Int64,
) -> @bit.ObjectId raise @bit.GitError {
  fs.write_string(root + "/" + file, content)
  @bitlib.add_paths(fs, rfs, root, [file])
  @bitlib.commit(fs, rfs, root, message, "Author <a@b.com>", timestamp)
}

///|
test "runtime: materialize push workspace from bit repo" {
  let fs = @bit.TestFs::new()
  let commit_id = setup_bit_repo(
    fs, fs, "/repo", "hello.txt", "hello\n", "Initial commit", 1700000000L,
  )
  let event = new_push_event(
    "main",
    ["hello.txt"],
    after_sha=commit_id.to_hex(),
  )

  let result = materialize_bit_push_workspace(fs, fs, "/repo", event, "/work")
  inspect(result.errors, content="[]")

  let workspace = expect_bit_workspace(result)
  assert_eq(workspace.git_dir, "/repo/.git")
  assert_eq(workspace.commit_sha, commit_id.to_hex())
  inspect(fs.read_string("/work/hello.txt"), content="hello\n")
  inspect(fs.read_string("/work/.git/HEAD"), content="ref: refs/heads/main\n")
  assert_eq(fs.read_string("/work/.git/config").contains("/repo"), true)
}

///|
test "runtime: materialize uses HEAD when after sha is missing" {
  let fs = @bit.TestFs::new()
  let commit_id = setup_bit_repo(
    fs, fs, "/repo", "hello.txt", "head\n", "Head commit", 1700000001L,
  )
  let event = new_push_event("", ["hello.txt"])

  let result = materialize_bit_push_workspace(fs, fs, "/repo", event, "/head")
  inspect(result.errors, content="[]")
  let workspace = expect_bit_workspace(result)
  assert_eq(workspace.commit_sha, commit_id.to_hex())
  inspect(workspace.refname, content="main")
}

///|
test "runtime: compute changed paths from before and after" {
  let fs = @bit.TestFs::new()
  let before_id = setup_bit_repo(
    fs, fs, "/repo", "a.txt", "one\n", "Initial commit", 1700000002L,
  )
  let after_id = commit_repo_file(
    fs, fs, "/repo", "b.txt", "two\n", "Add b", 1700000003L,
  )
  let event = new_push_event(
    "main",
    [],
    before_sha=before_id.to_hex(),
    after_sha=after_id.to_hex(),
  )

  let result = compute_bit_changed_paths(fs, "/repo", event)
  inspect(result.errors, content="[]")
  inspect(result.base_sha, content=before_id.to_hex())
  inspect(result.head_sha, content=after_id.to_hex())
  inspect(result.paths, content="[\"b.txt\"]")
}

///|
test "runtime: compute changed paths falls back to first parent" {
  let fs = @bit.TestFs::new()
  let before_id = setup_bit_repo(
    fs, fs, "/repo", "a.txt", "one\n", "Initial commit", 1700000004L,
  )
  let after_id = commit_repo_file(
    fs, fs, "/repo", "a.txt", "two\n", "Modify a", 1700000005L,
  )
  let event = new_push_event("main", [], after_sha=after_id.to_hex())

  let result = compute_bit_changed_paths(fs, "/repo", event)
  inspect(result.errors, content="[]")
  inspect(result.base_sha, content=before_id.to_hex())
  inspect(result.head_sha, content=after_id.to_hex())
  inspect(result.paths, content="[\"a.txt\"]")
}

///|
test "runtime: materialize clears stale workspace files" {
  let fs = @bit.TestFs::new()
  let commit_id = setup_bit_repo(
    fs, fs, "/repo", "hello.txt", "fresh\n", "Fresh commit", 1700000002L,
  )
  fs.write_string("/work/stale.txt", "stale\n")
  let event = new_push_event(
    "main",
    ["hello.txt"],
    after_sha=commit_id.to_hex(),
  )

  let result = materialize_bit_push_workspace(fs, fs, "/repo", event, "/work")
  inspect(result.errors, content="[]")
  assert_eq(fs.exists("/work/stale.txt"), false)
  inspect(fs.read_string("/work/hello.txt"), content="fresh\n")
}

///|
test "runtime: materialize rejects overlapping repo and workspace" {
  let fs = @bit.TestFs::new()
  let commit_id = setup_bit_repo(
    fs, fs, "/repo", "hello.txt", "hello\n", "Initial commit", 1700000003L,
  )
  let event = new_push_event(
    "main",
    ["hello.txt"],
    after_sha=commit_id.to_hex(),
  )

  let result = materialize_bit_push_workspace(
    fs, fs, "/repo", event, "/repo/work",
  )
  inspect(
    result.errors,
    content="[\"workspace root must not overlap repo root\"]",
  )
}

///|
#cfg(target="native")
test "runtime: native wrapper materializes workspace on disk" {
  let fs = @bitosfs.OsFs::new()
  let repo_root = "_build/runtime-native-source"
  let workspace_root = "_build/runtime-native-work"
  let commit_id = setup_bit_repo(
    fs,
    fs,
    repo_root,
    "hello.txt",
    "native\n",
    "Native materialize",
    1700000004L,
    allow_empty=true,
  )
  let event = new_push_event(
    "main",
    ["hello.txt"],
    after_sha=commit_id.to_hex(),
  )

  let result = materialize_bit_push_workspace_native(
    repo_root, event, workspace_root,
  )
  inspect(result.errors, content="[]")
  assert_eq(expect_bit_workspace(result).commit_sha, commit_id.to_hex())
  inspect(
    @xfs.read_file_to_string(workspace_root + "/hello.txt"),
    content="native\n",
  )
  inspect(
    @xfs.read_file_to_string(workspace_root + "/.git/HEAD"),
    content="ref: refs/heads/main\n",
  )
}
