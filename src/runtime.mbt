///|
/// Error raised when a `git` subcommand fails or cannot be spawned.
priv suberror GitCliError {
  GitCliError(String)
}

///|
fn GitCliError::message(self : GitCliError) -> String {
  let GitCliError(message) = self
  message
}

///|
fn git_workspace_error(message : String) -> GitWorkspaceResult {
  { workspace: None, errors: [message], }
}

///|
fn git_changed_paths_error(message : String) -> GitChangedPathsResult {
  { paths: [], base_sha: "", head_sha: "", errors: [message], }
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
/// Run `git` with the given arguments inside `cwd` and return
/// `(exit_code, stdout, stderr)`. Spawn failures are reported as exit code -1.
async fn git_exec(
  cwd : String,
  args : Array[String],
) -> (Int, String, String) noraise {
  run_command("git", args, cwd~) catch {
    _ => (-1, "", "failed to run git " + args.join(" "))
  }
}

///|
/// Run `git` and return trimmed stdout, raising when the command fails.
async fn git_stdout(
  cwd : String,
  args : Array[String],
) -> String raise GitCliError {
  let (code, stdout, stderr) = git_exec(cwd, args)
  if code != 0 {
    let detail = stderr.trim().to_owned()
    let message = "git " + args.join(" ") + " failed"
    raise GitCliError(
      if detail.length() > 0 {
        message + ": " + detail
      } else {
        message
      },
    )
  }
  stdout.trim().to_owned()
}

///|
/// Run `git` for its side effects, raising when the command fails.
async fn git_run(cwd : String, args : Array[String]) -> Unit raise GitCliError {
  ignore(git_stdout(cwd, args))
}

///|
/// Locate the git directory that backs `repo_root`.
/// Returns `(git_dir, is_bare)` or `None` when `repo_root` is not a repository.
async fn detect_git_dir(repo_root : String) -> (String, Bool)? noraise {
  let git_dir = git_stdout(repo_root, ["rev-parse", "--absolute-git-dir"]) catch {
    _ => return None
  }
  let bare = git_stdout(repo_root, ["rev-parse", "--is-bare-repository"]) catch {
    _ => "false"
  }
  Some((git_dir, bare == "true"))
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
async fn resolve_event_ref_name(
  repo_root : String,
  ref_name : String,
) -> String noraise {
  if ref_name.length() > 0 {
    return strip_ref_prefix(ref_name)
  }
  let symbolic = git_stdout(repo_root, ["symbolic-ref", "--quiet", "HEAD"]) catch {
    _ => return "HEAD"
  }
  if symbolic.has_prefix("refs/heads/") {
    strip_ref_prefix(symbolic)
  } else {
    "HEAD"
  }
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
/// Resolve `revision` to a full commit sha inside `repo_root`.
async fn resolve_commit_sha(
  repo_root : String,
  revision : String,
  missing_message : String,
) -> String raise GitCliError {
  let sha = git_stdout(repo_root, [
    "rev-parse",
    "--verify",
    "--quiet",
    revision + "^{commit}",
  ]) catch {
    _ => raise GitCliError(missing_message)
  }
  if sha.length() == 0 {
    raise GitCliError(missing_message)
  }
  sha
}

///|
async fn resolve_push_commit_sha(
  repo_root : String,
  event : PushEvent,
) -> String raise GitCliError {
  if event.after_sha.length() > 0 {
    return resolve_commit_sha(
      repo_root,
      event.after_sha,
      "Missing commit object: " + event.after_sha,
    )
  }
  resolve_commit_sha(repo_root, "HEAD", "HEAD commit is missing")
}

///|
async fn resolve_push_base_commit_sha(
  repo_root : String,
  event : PushEvent,
  head_sha : String,
) -> String? raise GitCliError {
  if event.before_sha.length() > 0 && !is_zero_sha(event.before_sha) {
    return Some(
      resolve_commit_sha(
        repo_root,
        event.before_sha,
        "Missing commit object: " + event.before_sha,
      ),
    )
  }
  // Fall back to the first parent; a root commit has no base.
  let parent = git_stdout(repo_root, [
    "rev-parse",
    "--verify",
    "--quiet",
    head_sha + "^1",
  ]) catch {
    _ => return None
  }
  if parent.length() == 0 {
    None
  } else {
    Some(parent)
  }
}

///|
fn sort_paths(paths : Array[String]) -> Array[String] {
  let result = paths.copy()
  result.sort_by(String::lexical_compare)
  result
}

///|
fn split_output_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for line in text.split("\n") {
    let trimmed = line.trim(chars="\r").to_owned()
    if trimmed.length() > 0 {
      lines.push(trimmed)
    }
  }
  lines
}

///|
/// Compute the paths touched between the push base and head commits of
/// the repository at `repo_root` using the `git` CLI.
pub async fn compute_git_changed_paths(
  repo_root : String,
  event : PushEvent,
) -> GitChangedPathsResult noraise {
  guard detect_git_dir(repo_root) is Some(_) else {
    return git_changed_paths_error("git repository not found: " + repo_root)
  }
  let head_sha = resolve_push_commit_sha(repo_root, event) catch {
    err => return git_changed_paths_error(err.message())
  }
  let base_sha = resolve_push_base_commit_sha(repo_root, event, head_sha) catch {
    err => return git_changed_paths_error(err.message())
  }
  let diff_args = [
    "-c", "core.quotePath=false", "diff-tree", "-r", "--no-commit-id", "--name-only",
    "--no-renames",
  ]
  match base_sha {
    Some(base) => {
      diff_args.push(base)
      diff_args.push(head_sha)
    }
    None => {
      diff_args.push("--root")
      diff_args.push(head_sha)
    }
  }
  let output = git_stdout(repo_root, diff_args) catch {
    err => return git_changed_paths_error(err.message())
  }
  {
    paths: sort_paths(split_output_lines(output)),
    base_sha: base_sha.unwrap_or(""),
    head_sha,
    errors: [],
  }
}

///|
fn remove_path_recursive(path : String) -> Unit raise {
  if !@xfs.path_exists(path) {
    return
  }
  if @xfs.is_dir(path) {
    for entry in @xfs.read_dir(path) {
      remove_path_recursive(path + "/" + entry)
    }
    @xfs.remove_dir(path)
  } else {
    @xfs.remove_file(path)
  }
}

///|
/// Materialize the push head commit of `repo_root` into `workspace_root`
/// as a fresh git checkout whose `origin` points at `remote_url`
/// (or `repo_root` when omitted).
pub async fn materialize_git_push_workspace(
  repo_root : String,
  event : PushEvent,
  workspace_root : String,
  remote_url? : String = "",
) -> GitWorkspaceResult noraise {
  guard detect_git_dir(repo_root) is Some((git_dir, _is_bare)) else {
    return git_workspace_error("git repository not found: " + repo_root)
  }
  if paths_overlap(repo_root, workspace_root) {
    return git_workspace_error("workspace root must not overlap repo root")
  }
  let commit_sha = resolve_push_commit_sha(repo_root, event) catch {
    err => return git_workspace_error(err.message())
  }
  let refname = resolve_event_ref_name(repo_root, event.ref_name)
  let git_refname = git_refname_from_event_ref(refname)
  let resolved_remote_url = if remote_url.length() > 0 {
    remote_url
  } else {
    repo_root
  }
  remove_path_recursive(workspace_root) catch {
    err =>
      return git_workspace_error(
        "failed to clear workspace root: " + err.to_string(),
      )
  }
  let materialize = async fn() -> Unit raise GitCliError {
    git_run(".", [
      "clone", "--quiet", "--no-checkout", repo_root, workspace_root,
    ])
    if git_refname == "HEAD" {
      git_run(workspace_root, [
        "-c", "advice.detachedHead=false", "checkout", "--quiet", "--detach", commit_sha,
      ])
    } else {
      git_run(workspace_root, ["update-ref", git_refname, commit_sha])
      git_run(workspace_root, ["symbolic-ref", "HEAD", git_refname])
      git_run(workspace_root, ["reset", "--quiet", "--hard", commit_sha])
    }
    git_run(workspace_root, ["remote", "set-url", "origin", resolved_remote_url])
  }
  materialize() catch {
    err => return git_workspace_error(err.message())
  }
  {
    workspace: Some({
      repo_root,
      git_dir,
      workspace_root,
      commit_sha,
      refname,
      remote_url: resolved_remote_url,
    }),
    errors: [],
  }
}
