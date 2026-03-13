///|
priv struct GitHubActionEnsureResult {
  action_root : String?
  did_fetch : Bool
  errors : Array[String]
}

///|
priv struct GitHubRepoEnsureResult {
  repo_root : String?
  did_fetch : Bool
  errors : Array[String]
}

///|
fn prefetch_parent_dir(path : String) -> String {
  let parts : Array[String] = []
  for part in path.split("/") {
    parts.push(part.to_string())
  }
  if parts.length() <= 1 {
    return "."
  }
  let dirs : Array[String] = []
  for idx in 0..<(parts.length() - 1) {
    dirs.push(parts[idx])
  }
  let joined = dirs.join("/")
  if joined.length() > 0 {
    joined
  } else if path.has_prefix("/") {
    "/"
  } else {
    "."
  }
}

///|
fn prefetch_trim_output(text : String) -> String {
  text.trim(chars=" \t\n\r").to_string()
}

///|
fn github_action_git_bin(git_bin : String?) -> String {
  match git_bin {
    Some(value) => value
    None => @xsys.get_env_var("ACTION_RUNNER_GIT_BIN").unwrap_or("git")
  }
}

///|
fn github_action_base_url(github_base_url : String?) -> String {
  let base = match github_base_url {
    Some(value) => value
    None =>
      @xsys.get_env_var("ACTION_RUNNER_GITHUB_BASE_URL").unwrap_or(
        "https://github.com",
      )
  }
  let trimmed = base.trim(chars=" \t\n\r").to_string()
  if trimmed.has_suffix("/") {
    String::unsafe_substring(trimmed, start=0, end=trimmed.length() - 1)
  } else {
    trimmed
  }
}

///|
fn github_action_repo_url(
  owner : String,
  repo : String,
  github_base_url : String?,
) -> String {
  github_action_base_url(github_base_url) + "/" + owner + "/" + repo + ".git"
}

///|
fn prefetch_command_message(stdout : String, stderr : String) -> String {
  let stderr_text = prefetch_trim_output(stderr)
  if stderr_text.length() > 0 {
    return stderr_text
  }
  let stdout_text = prefetch_trim_output(stdout)
  if stdout_text.length() > 0 {
    stdout_text
  } else {
    "unknown error"
  }
}

///|
async fn prefetch_mkdir_p(path : String) -> Bool {
  if path.length() == 0 || path == "." {
    return true
  }
  let (code, _, _) = @process.collect_output("mkdir", ["-p", path], cwd=".")
  code == 0
}

///|
async fn prefetch_ensure_cached_github_repo_root(
  action_ref : ActionRef,
  git_bin : String?,
  github_base_url : String?,
) -> GitHubRepoEnsureResult {
  match github_action_cache_layout(action_ref) {
    None => { repo_root: None, did_fetch: false, errors: [] }
    Some(layout) =>
      if @xfs.path_exists(layout.repo_root) {
        { repo_root: Some(layout.repo_root), did_fetch: false, errors: [] }
      } else {
        let parent_dir = prefetch_parent_dir(layout.repo_root)
        guard prefetch_mkdir_p(parent_dir) else {
          return {
            repo_root: None,
            did_fetch: false,
            errors: [
              "action '\{layout.uses}' failed to create cache dir '\{parent_dir}'",
            ],
          }
        }
        let clone_url = github_action_repo_url(
          layout.owner,
          layout.repo,
          github_base_url,
        )
        let (code, stdout, stderr) = @process.collect_output(
          github_action_git_bin(git_bin),
          [
            "clone",
            "--depth",
            "1",
            "--branch",
            layout.version,
            clone_url,
            layout.repo_root,
          ],
          cwd=".",
        )
        if code != 0 {
          return {
            repo_root: None,
            did_fetch: false,
            errors: [
              "action '\{layout.uses}' git clone failed: " +
              prefetch_command_message(stdout.text(), stderr.text()),
            ],
          }
        }
        { repo_root: Some(layout.repo_root), did_fetch: true, errors: [] }
      }
  }
}

///|
async fn prefetch_ensure_cached_github_action_root(
  action_ref : ActionRef,
  git_bin : String?,
  github_base_url : String?,
) -> GitHubActionEnsureResult {
  let repo_result = prefetch_ensure_cached_github_repo_root(
    action_ref, git_bin, github_base_url,
  )
  match github_action_cache_layout(action_ref) {
    None => { action_root: None, did_fetch: false, errors: [] }
    Some(layout) =>
      if repo_result.errors.length() > 0 {
        {
          action_root: None,
          did_fetch: repo_result.did_fetch,
          errors: repo_result.errors,
        }
      } else if has_action_manifest(layout.action_root) {
        {
          action_root: Some(layout.action_root),
          did_fetch: repo_result.did_fetch,
          errors: [],
        }
      } else if @xfs.path_exists(layout.repo_root) {
        {
          action_root: None,
          did_fetch: repo_result.did_fetch,
          errors: [
            "action '\{layout.uses}' cache exists at '\{layout.repo_root}' but '\{layout.action_root}' is missing action.yml or action.yaml",
          ],
        }
      } else {
        {
          action_root: None,
          did_fetch: repo_result.did_fetch,
          errors: [
            "action '\{layout.uses}' fetched repo cache but '\{layout.action_root}' is missing action.yml or action.yaml",
          ],
        }
      }
  }
}

///|
fn prefetch_remote_reusable_workflow_ref(path : String) -> ActionRef? {
  let parsed = parse_action_ref(path)
  guard parsed.action is Some(action_ref) else { return None }
  match action_ref {
    GitHubRepo(_, _, version, Some(subpath)) =>
      if version.length() > 0 && subpath.length() > 0 {
        Some(action_ref)
      } else {
        None
      }
    _ => None
  }
}

///|
async fn prefetch_action_uses(
  uses : String,
  workspace_root : String,
  current_action_root : String?,
  git_bin : String?,
  github_base_url : String?,
  visited : Map[String, Bool],
  fetched : Array[String],
  errors : Array[String],
) -> Unit {
  let parsed = parse_action_ref(uses)
  guard parsed.action is Some(action_ref) else { return }
  match action_ref {
    LocalPath(path) => {
      let resolved_root = match current_action_root {
        Some(root) => normalize_local_action_path(join_path(root, path))
        None => path
      }
      let visit_key = "local:" + resolved_root
      if visited.get(visit_key) is Some(_) {
        return
      }
      visited[visit_key] = true
      guard find_local_action_manifest(workspace_root, resolved_root)
        is Some((_, manifest_text)) else {
        return
      }
      let parsed_action = parse_local_action_yaml(manifest_text)
      guard parsed_action.action is Some(action) else { return }
      for step in action.steps {
        if step.uses is Some(nested_uses) {
          prefetch_action_uses(
            nested_uses,
            workspace_root,
            Some(resolved_root),
            git_bin,
            github_base_url,
            visited,
            fetched,
            errors,
          )
        }
      }
    }
    GitHubRepo(_, _, _, _) => {
      if resolve_action_ref(action_ref).action is Some(_) {
        return
      }
      match github_action_cache_layout(action_ref) {
        Some(layout) => {
          let visit_key = "github:" + layout.action_root
          if visited.get(visit_key) is Some(_) {
            return
          }
          visited[visit_key] = true
          let ensured = prefetch_ensure_cached_github_action_root(
            action_ref, git_bin, github_base_url,
          )
          for err in ensured.errors {
            errors.push(err)
          }
          if ensured.did_fetch {
            fetched.push(layout.uses)
          }
          guard ensured.action_root is Some(action_root) else { return }
          guard find_local_action_manifest(workspace_root, action_root)
            is Some((_, manifest_text)) else {
            return
          }
          let parsed_action = parse_local_action_yaml(manifest_text)
          guard parsed_action.action is Some(action) else { return }
          for step in action.steps {
            if step.uses is Some(nested_uses) {
              prefetch_action_uses(
                nested_uses,
                workspace_root,
                Some(action_root),
                git_bin,
                github_base_url,
                visited,
                fetched,
                errors,
              )
            }
          }
        }
        None => ()
      }
    }
    _ => ()
  }
}

///|
async fn prefetch_workflow_dependencies(
  workflow : WorkflowSpec,
  workspace_root : String,
  git_bin : String?,
  github_base_url : String?,
  visited : Map[String, Bool],
  fetched : Array[String],
  errors : Array[String],
) -> Unit {
  for job in workflow.jobs {
    match job.reusable_workflow {
      Some(path) =>
        if path.has_prefix("./") {
          let workflow_path = join_path(
            workspace_root,
            normalize_local_action_path(path),
          )
          let visit_key = "workflow-local:" + workflow_path
          if visited.get(visit_key) is None {
            visited[visit_key] = true
            match read_text(workflow_path) {
              Some(text) => {
                let parsed = parse_workflow_yaml(text)
                for err in parsed.errors {
                  errors.push("reusable workflow '\{path}' parse error: " + err)
                }
                if parsed.workflow is Some(callee) {
                  prefetch_workflow_dependencies(
                    callee, workspace_root, git_bin, github_base_url, visited, fetched,
                    errors,
                  )
                }
              }
              None => ()
            }
          }
        } else {
          match prefetch_remote_reusable_workflow_ref(path) {
            Some(action_ref) =>
              match github_action_cache_layout(action_ref) {
                Some(layout) => {
                  let visit_key = "workflow-github:" + layout.action_root
                  if visited.get(visit_key) is None {
                    visited[visit_key] = true
                    let ensured = prefetch_ensure_cached_github_repo_root(
                      action_ref, git_bin, github_base_url,
                    )
                    for err in ensured.errors {
                      errors.push(err)
                    }
                    if ensured.did_fetch {
                      fetched.push(layout.uses)
                    }
                    guard ensured.repo_root is Some(repo_root) else { () }
                    match read_text(layout.action_root) {
                      Some(text) => {
                        let parsed = parse_workflow_yaml(text)
                        for err in parsed.errors {
                          errors.push(
                            "reusable workflow '\{path}' parse error: " + err,
                          )
                        }
                        if parsed.workflow is Some(callee) {
                          prefetch_workflow_dependencies(
                            callee, repo_root, git_bin, github_base_url, visited,
                            fetched, errors,
                          )
                        }
                      }
                      None =>
                        errors.push(
                          "reusable workflow '\{path}' fetched repo cache but '\{layout.action_root}' is missing",
                        )
                    }
                  }
                }
                None => ()
              }
            None => ()
          }
        }
      None => ()
    }
    for step in job.steps {
      if step.uses is Some(uses) {
        prefetch_action_uses(
          uses,
          workspace_root,
          None,
          git_bin,
          github_base_url,
          visited,
          fetched,
          errors,
        )
      }
    }
  }
}

///|
pub async fn prefetch_workflow_github_actions_native(
  workflow : WorkflowSpec,
  workspace_root : String,
  git_bin? : String? = None,
  github_base_url? : String? = None,
) -> GitHubActionPrefetchResult {
  let fetched : Array[String] = []
  let errors : Array[String] = []
  let visited : Map[String, Bool] = {}
  prefetch_workflow_dependencies(
    workflow, workspace_root, git_bin, github_base_url, visited, fetched, errors,
  )
  { fetched, errors }
}
