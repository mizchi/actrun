///|
fn bit_workspace_error(message : String) -> BitWorkspaceResult {
  { workspace: None, errors: [message] }
}

///|
fn bit_changed_paths_error(message : String) -> BitChangedPathsResult {
  { paths: [], base_sha: "", head_sha: "", errors: [message] }
}

///|
fn normalize_repo_path(path : String) -> String {
  if path.length() > 1 && path.has_suffix("/") {
    String::unsafe_substring(path, start=0, end=path.length() - 1)
  } else {
    path
  }
}

///|
fn paths_overlap(left : String, right : String) -> Bool {
  let a = normalize_repo_path(left)
  let b = normalize_repo_path(right)
  if a == b {
    return true
  }
  let a_prefix = a + "/"
  let b_prefix = b + "/"
  a.has_prefix(b_prefix) || b.has_prefix(a_prefix)
}

///|
fn clear_workspace_root(
  fs : &@bit.FileSystem,
  rfs : &@bit.RepoFileSystem,
  path : String,
) -> Unit raise @bit.GitError {
  if rfs.is_file(path) {
    fs.remove_file(path)
    return
  }
  if !rfs.is_dir(path) {
    return
  }
  for entry in rfs.readdir(path) {
    clear_workspace_root(fs, rfs, @bit.join_path(path, entry))
  }
  fs.remove_dir(path)
}

///|
fn strip_ref_prefix(ref_name : String) -> String {
  if ref_name.has_prefix("refs/heads/") {
    return String::unsafe_substring(ref_name, start=11, end=ref_name.length())
  }
  if ref_name.has_prefix("refs/tags/") {
    return String::unsafe_substring(ref_name, start=10, end=ref_name.length())
  }
  ref_name
}

///|
fn resolve_event_ref_name(
  rfs : &@bit.RepoFileSystem,
  git_dir : String,
  ref_name : String,
) -> String {
  if ref_name.length() > 0 {
    return strip_ref_prefix(ref_name)
  }
  let head_path = @bit.join_path(git_dir, "HEAD")
  let head_bytes = rfs.read_file(head_path) catch { _ => return "HEAD" }
  let head_text = @utf8.decode_lossy(head_bytes[:]).trim().to_string()
  if head_text.has_prefix("ref: refs/heads/") {
    return strip_ref_prefix(
      String::unsafe_substring(head_text, start=5, end=head_text.length()),
    )
  }
  "HEAD"
}

///|
fn git_refname_from_event_ref(ref_name : String) -> String {
  if ref_name == "HEAD" {
    "HEAD"
  } else if ref_name.has_prefix("refs/") {
    ref_name
  } else {
    "refs/heads/" + ref_name
  }
}

///|
fn is_zero_sha(sha : String) -> Bool {
  if sha.length() == 0 {
    return false
  }
  for c in sha {
    if c != '0' {
      return false
    }
  }
  true
}

///|
fn resolve_push_commit_id(
  rfs : &@bit.RepoFileSystem,
  git_dir : String,
  event : PushEvent,
) -> @bit.ObjectId raise @bit.GitError {
  if event.after_sha.length() > 0 {
    return @bit.ObjectId::from_hex(event.after_sha)
  }
  match @bitlib.resolve_head_commit(rfs, git_dir) {
    Some(commit_id) => commit_id
    None => raise @bit.GitError::InvalidObject("HEAD commit is missing")
  }
}

///|
fn resolve_push_base_commit_id(
  store : @bit.ObjectStore,
  event : PushEvent,
  head_commit_id : @bit.ObjectId,
) -> @bit.ObjectId? raise @bit.GitError {
  if event.before_sha.length() > 0 && !is_zero_sha(event.before_sha) {
    return Some(@bit.ObjectId::from_hex(event.before_sha))
  }
  let commit_obj = store.get(head_commit_id)
  guard commit_obj is Some(obj) else {
    raise @bit.GitError::InvalidObject("Missing commit object")
  }
  if obj.obj_type != @bit.ObjectType::Commit {
    raise @bit.GitError::InvalidObject("Object is not a commit")
  }
  let info = @bit.parse_commit(obj.data)
  if info.parents.length() == 0 {
    None
  } else {
    Some(info.parents[0])
  }
}

///|
fn commit_tree_id(
  store : @bit.ObjectStore,
  commit_id : @bit.ObjectId,
) -> @bit.ObjectId raise @bit.GitError {
  let commit_obj = store.get(commit_id)
  guard commit_obj is Some(obj) else {
    raise @bit.GitError::InvalidObject("Missing commit object")
  }
  if obj.obj_type != @bit.ObjectType::Commit {
    raise @bit.GitError::InvalidObject("Object is not a commit")
  }
  @bit.parse_commit(obj.data).tree
}

///|
fn sort_paths(paths : Array[String]) -> Array[String] {
  let result = paths.copy()
  result.sort_by(String::lexical_compare)
  result
}

///|
pub fn compute_bit_changed_paths(
  rfs : &@bit.RepoFileSystem,
  repo_root : String,
  event : PushEvent,
) -> BitChangedPathsResult {
  let detected = @bitlib.detect_git_dir(rfs, repo_root)
  guard detected is Some((git_dir, _is_bare)) else {
    return bit_changed_paths_error("bit repository not found: " + repo_root)
  }

  let head_commit_id = resolve_push_commit_id(rfs, git_dir, event) catch {
    err => return bit_changed_paths_error(err.to_string())
  }
  let store = @bitlib.load_object_store_from_fs(rfs, git_dir) catch {
    err => return bit_changed_paths_error(err.to_string())
  }
  let base_commit_id = resolve_push_base_commit_id(store, event, head_commit_id) catch {
    err => return bit_changed_paths_error(err.to_string())
  }
  let new_tree = commit_tree_id(store, head_commit_id) catch {
    err => return bit_changed_paths_error(err.to_string())
  }
  let old_tree = match base_commit_id {
    Some(id) => {
      let old_tree_result = try? commit_tree_id(store, id)
      match old_tree_result {
        Ok(tree_id) => Some(tree_id)
        Err(err) => return bit_changed_paths_error(err.to_string())
      }
    }
    None => None
  }
  let diff_files = @bitdiff.diff_trees(rfs, git_dir, old_tree, new_tree) catch {
    err => return bit_changed_paths_error(err.to_string())
  }
  let paths : Array[String] = []
  for diff in diff_files {
    paths.push(diff.path)
  }
  {
    paths: sort_paths(paths),
    base_sha: base_commit_id.map(id => id.to_hex()).unwrap_or(""),
    head_sha: head_commit_id.to_hex(),
    errors: [],
  }
}

///|
pub fn compute_bit_changed_paths_native(
  repo_root : String,
  event : PushEvent,
) -> BitChangedPathsResult {
  let fs = @bitosfs.OsFs::new()
  compute_bit_changed_paths(fs, repo_root, event)
}

///|
pub fn materialize_bit_push_workspace(
  fs : &@bit.FileSystem,
  rfs : &@bit.RepoFileSystem,
  repo_root : String,
  event : PushEvent,
  workspace_root : String,
  remote_url? : String = "",
) -> BitWorkspaceResult {
  let detected = @bitlib.detect_git_dir(rfs, repo_root)
  guard detected is Some((git_dir, _is_bare)) else {
    return bit_workspace_error("bit repository not found: " + repo_root)
  }
  if paths_overlap(repo_root, workspace_root) {
    return bit_workspace_error("workspace root must not overlap repo root")
  }

  let commit_id = resolve_push_commit_id(rfs, git_dir, event) catch {
    err => return bit_workspace_error(err.to_string())
  }
  let store = @bitlib.load_object_store_from_fs(rfs, git_dir) catch {
    err => return bit_workspace_error(err.to_string())
  }
  let refname = resolve_event_ref_name(rfs, git_dir, event.ref_name)
  let git_refname = git_refname_from_event_ref(refname)
  let resolved_remote_url = if remote_url.length() > 0 {
    remote_url
  } else {
    repo_root
  }

  clear_workspace_root(fs, rfs, workspace_root) catch {
    err => return bit_workspace_error(err.to_string())
  }
  @bit.materialize_clone_to_fs(
    store, commit_id, git_refname, resolved_remote_url, fs, workspace_root,
  ) catch {
    err => return bit_workspace_error(err.to_string())
  }

  {
    workspace: Some({
      repo_root,
      git_dir,
      workspace_root,
      commit_sha: commit_id.to_hex(),
      refname,
      remote_url: resolved_remote_url,
    }),
    errors: [],
  }
}

///|
pub fn materialize_bit_push_workspace_native(
  repo_root : String,
  event : PushEvent,
  workspace_root : String,
  remote_url? : String = "",
) -> BitWorkspaceResult {
  let fs = @bitosfs.OsFs::new()
  materialize_bit_push_workspace(
    fs,
    fs,
    repo_root,
    event,
    workspace_root,
    remote_url~,
  )
}
