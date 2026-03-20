///|
fn checkout_wildcard_match(pattern : String, text : String) -> Bool {
  let mut p = 0
  let mut t = 0
  let mut star = -1
  let mut mark = 0
  while t < text.length() {
    if p < pattern.length() {
      let pc = pattern.unsafe_get(p)
      let tc = text.unsafe_get(t)
      if pc == '*' {
        star = p
        p += 1
        mark = t
        continue
      }
      if pc == tc {
        p += 1
        t += 1
        continue
      }
    }
    if star >= 0 {
      p = star + 1
      mark += 1
      t = mark
    } else {
      return false
    }
  }
  while p < pattern.length() && pattern.unsafe_get(p) == '*' {
    p += 1
  }
  p == pattern.length()
}

///|
fn normalize_checkout_pattern(pattern : String) -> String {
  let trimmed = pattern.trim(chars=" \t\r").to_string()
  let no_prefix = if trimmed.has_prefix("./") {
    exec_text_slice(trimmed, 2, trimmed.length())
  } else if trimmed.has_prefix("/") {
    exec_text_slice(trimmed, 1, trimmed.length())
  } else {
    trimmed
  }
  if no_prefix.has_suffix("/") {
    exec_text_slice(no_prefix, 0, no_prefix.length() - 1)
  } else {
    no_prefix
  }
}

///|
fn checkout_sparse_match(
  patterns : Array[String],
  relative_path : String,
  is_dir : Bool,
  cone_mode : Bool,
) -> Bool {
  if cone_mode && not(is_dir) && not(relative_path.contains("/")) {
    return true
  }
  for raw_pattern in patterns {
    let pattern = normalize_checkout_pattern(raw_pattern)
    if pattern.length() == 0 {
      continue
    }
    if pattern.contains("*") {
      if checkout_wildcard_match(pattern, relative_path) {
        return true
      }
    } else if relative_path == pattern ||
      relative_path.has_prefix(pattern + "/") {
      return true
    }
  }
  false
}

///|
fn exec_relative_path(root : String, path : String) -> String {
  let root_abs = absolute_exec_path(root)
  let path_abs = absolute_exec_path(path)
  if path_abs == root_abs {
    return ""
  }
  let prefix = root_abs + "/"
  if path_abs.has_prefix(prefix) {
    return exec_text_slice(path_abs, prefix.length(), path_abs.length())
  }
  path_abs
}

///|
fn exec_copy_workspace_snapshot(
  workspace_root : String,
  destination : String,
) -> Bool {
  guard workspace_relative_store_path(workspace_root, destination)
    is Some(relative_destination) else {
    return false
  }
  let top_level = match relative_destination.split("/").next() {
    Some(segment) => segment.to_string()
    None => relative_destination
  }
  if not(exec_remove_tree(destination)) {
    return false
  }
  if not(ensure_exec_dir_recursive(destination)) {
    return false
  }
  let entries = try @xfs.read_dir(workspace_root) catch {
    _ => []
  } noraise {
    value => value
  }
  for entry in entries {
    if entry == top_level {
      continue
    }
    if not(
        exec_copy_tree(workspace_root + "/" + entry, destination + "/" + entry),
      ) {
      return false
    }
  }
  true
}

///|
fn exec_prune_sparse_checkout(
  root : String,
  current : String,
  patterns : Array[String],
  cone_mode : Bool,
) -> Bool {
  if exec_is_dir(current) {
    let entries = try @xfs.read_dir(current) catch {
      _ => []
    } noraise {
      value => value
    }
    let kept_entries : Array[String] = []
    for entry in entries {
      let child = current + "/" + entry
      if exec_prune_sparse_checkout(root, child, patterns, cone_mode) {
        kept_entries.push(entry)
      } else if not(exec_remove_tree(child)) {
        return false
      }
    }
    let relative = exec_relative_path(root, current)
    if relative.length() == 0 {
      return true
    }
    kept_entries.length() > 0 ||
    checkout_sparse_match(patterns, relative, true, cone_mode)
  } else {
    let relative = exec_relative_path(root, current)
    checkout_sparse_match(patterns, relative, false, cone_mode)
  }
}

///|
fn parse_checkout_fetch_depth(value : String) -> Int? {
  let trimmed = value.trim(chars=" \t\r\n").to_string()
  if trimmed.length() == 0 {
    return Some(1)
  }
  let parsed = @strconv.parse_int64(trimmed) catch { _ => return None }
  if parsed < 0 {
    None
  } else {
    Some(parsed.to_int())
  }
}

///|
fn parse_checkout_submodules(value : String) -> String {
  let normalized = value.trim(chars=" \t\r\n").to_lower()
  if normalized == "recursive" {
    "recursive"
  } else if normalized == "true" || normalized == "1" || normalized == "yes" {
    "true"
  } else {
    ""
  }
}

///|
fn parse_checkout_ref(value : String) -> String {
  value.trim(chars=" \t\r\n").to_string()
}

///|
fn checkout_temp_root(workspace_root : String, task_id : String) -> String {
  ignore(ensure_exec_dir_recursive("_build/actrun/checkouts"))
  let workspace_key = sanitize_task_id(
    absolute_exec_path(resolve_task_cwd(workspace_root, "")),
  )
  let root = absolute_exec_path(
    "_build/actrun/checkouts/" + workspace_key + "/" + sanitize_task_id(task_id),
  )
  ignore(exec_remove_tree(root))
  ignore(ensure_exec_dir_recursive(root))
  root
}

///|
fn exec_has_git_repo(path : String) -> Bool {
  @xfs.path_exists(path + "/.git")
}

///|
async fn exec_git_command_text(
  git_bin : String,
  args : Array[String],
  cwd : String,
) -> (Int, String, String) {
  run_command(git_bin, args, cwd~)
}

///|
fn exec_command_message(
  stdout : String,
  stderr : String,
  fallback : String,
) -> String {
  if stderr.length() > 0 {
    stderr
  } else if stdout.length() > 0 {
    stdout
  } else {
    fallback
  }
}

///|
async fn exec_git_clone_into(
  git_bin : String,
  source_root : String,
  temp_root : String,
  fetch_depth : Int,
  ref_name? : String = "",
  fetch_tags? : Bool = true,
  show_progress? : Bool = false,
  clone_url? : String = "",
  filter? : String = "",
) -> (Int, String, String) {
  let args : Array[String] = ["clone"]
  if not(show_progress) {
    args.push("--quiet")
  } else {
    args.push("--progress")
  }
  args.push("--no-local")
  if not(fetch_tags) {
    args.push("--no-tags")
  }
  if fetch_depth > 0 {
    args.push("--depth")
    args.push(fetch_depth.to_string())
  }
  if filter.length() > 0 {
    args.push("--filter")
    args.push(filter)
  }
  if ref_name.length() > 0 {
    args.push("--branch")
    args.push(ref_name)
  }
  let url = if clone_url.length() > 0 {
    clone_url
  } else {
    "file://" + absolute_exec_path(source_root)
  }
  args.push(url)
  args.push(temp_root)
  exec_git_command_text(git_bin, args, ".")
}

///|
async fn exec_git_update_submodules(
  git_bin : String,
  repo_root : String,
  submodules_mode : String,
) -> (Int, String, String) {
  if submodules_mode.length() == 0 {
    return (0, "", "")
  }
  let sync_args : Array[String] = [
    "-c", "protocol.file.allow=always", "submodule", "sync", "--recursive",
  ]
  let (sync_code, sync_stdout, sync_stderr) = exec_git_command_text(
    git_bin, sync_args, repo_root,
  )
  if sync_code != 0 {
    return (sync_code, sync_stdout, sync_stderr)
  }
  let update_args : Array[String] = [
    "-c", "protocol.file.allow=always", "submodule", "update", "--init",
  ]
  if submodules_mode == "recursive" {
    update_args.push("--recursive")
  }
  exec_git_command_text(git_bin, update_args, repo_root)
}

///|
/// Overwrite tracked files from clone into dst without deleting anything.
/// Preserves all existing files including .git, untracked files, and
/// tracked files that are not in the clone.
fn exec_overwrite_from_clone(src : String, dst : String) -> Bool {
  if not(ensure_exec_dir_recursive(dst)) {
    return false
  }
  let entries = try @xfs.read_dir(src) catch {
    _ => []
  } noraise {
    value => value
  }
  for entry in entries {
    // Never touch .git — keep the user's original .git intact
    if entry == ".git" {
      continue
    }
    if not(exec_copy_tree(src + "/" + entry, dst + "/" + entry)) {
      return false
    }
  }
  true
}

///|
fn exec_remove_checkout_contents_preserving_git(root : String) -> Bool {
  if not(ensure_exec_dir_recursive(root)) {
    return false
  }
  let entries = try @xfs.read_dir(root) catch {
    _ => []
  } noraise {
    value => value
  }
  for entry in entries {
    if entry == ".git" {
      continue
    }
    if not(exec_remove_tree(root + "/" + entry)) {
      return false
    }
  }
  true
}

///|
async fn exec_git_clone_checkout(
  plan : TaskPlan,
  workspace_root : String,
  source_root : String,
  checkout_root : String,
  fetch_depth : Int,
  resolved_plan_env : Map[String, String],
  clean? : Bool = true,
  allow_destructive_clean? : Bool = false,
  fetch_tags? : Bool = true,
  show_progress? : Bool = false,
  persist_credentials? : Bool = true,
  set_safe_directory? : Bool = true,
  lfs? : Bool = false,
  clone_url? : String = "",
  filter? : String = "",
) -> TaskRunReport? {
  let temp_root = checkout_temp_root(workspace_root, plan.id)
  let git_bin = configured_exec_bin("ACTRUN_GIT_BIN", resolved_plan_env, "git")
  let checkout_ref = parse_checkout_ref(
    resolved_plan_env.get("INPUT_REF").unwrap_or(""),
  )
  let submodules_mode = parse_checkout_submodules(
    resolved_plan_env.get("INPUT_SUBMODULES").unwrap_or(""),
  )
  let mut clone_ready = false
  if checkout_ref.length() > 0 {
    let (branch_code, branch_stdout, branch_stderr) = exec_git_clone_into(
      git_bin,
      source_root,
      temp_root,
      fetch_depth,
      ref_name=checkout_ref,
      fetch_tags~,
      show_progress~,
      clone_url~,
      filter~,
    )
    if branch_code == 0 {
      clone_ready = true
    } else {
      ignore(exec_remove_tree(temp_root))
      let branch_message = exec_command_message(
        branch_stdout, branch_stderr, "git clone failed",
      )
      if fetch_depth == 0 {
        let (fallback_code, fallback_stdout, fallback_stderr) = exec_git_clone_into(
          git_bin,
          source_root,
          temp_root,
          0,
          fetch_tags~,
          show_progress~,
          clone_url~,
          filter~,
        )
        if fallback_code != 0 {
          return Some(
            task_report_failure(
              plan,
              workspace_root,
              exec_command_message(
                fallback_stdout, fallback_stderr, branch_message,
              ),
            ),
          )
        }
        let (checkout_code, checkout_stdout, checkout_stderr) = exec_git_command_text(
          git_bin,
          ["checkout", "--quiet", checkout_ref],
          temp_root,
        )
        if checkout_code != 0 {
          return Some(
            task_report_failure(
              plan,
              workspace_root,
              exec_command_message(
                checkout_stdout, checkout_stderr, branch_message,
              ),
            ),
          )
        }
        clone_ready = true
      }
    }
  }
  if not(clone_ready) {
    let (clone_code, clone_stdout, clone_stderr) = exec_git_clone_into(
      git_bin,
      source_root,
      temp_root,
      fetch_depth,
      fetch_tags~,
      show_progress~,
      clone_url~,
      filter~,
    )
    if clone_code != 0 {
      return Some(
        task_report_failure(
          plan,
          workspace_root,
          exec_command_message(clone_stdout, clone_stderr, "git clone failed"),
        ),
      )
    }
    if checkout_ref.length() > 0 {
      let (checkout_code, checkout_stdout, checkout_stderr) = exec_git_command_text(
        git_bin,
        ["checkout", "--quiet", checkout_ref],
        temp_root,
      )
      if checkout_code != 0 {
        if fetch_depth > 0 {
          ignore(exec_remove_tree(temp_root))
          let (full_clone_code, full_clone_stdout, full_clone_stderr) = exec_git_clone_into(
            git_bin,
            source_root,
            temp_root,
            0,
            fetch_tags~,
            show_progress~,
            clone_url~,
            filter~,
          )
          if full_clone_code != 0 {
            return Some(
              task_report_failure(
                plan,
                workspace_root,
                exec_command_message(
                  full_clone_stdout, full_clone_stderr, "git clone failed",
                ),
              ),
            )
          }
          let (full_checkout_code, full_checkout_stdout, full_checkout_stderr) = exec_git_command_text(
            git_bin,
            ["checkout", "--quiet", checkout_ref],
            temp_root,
          )
          if full_checkout_code != 0 {
            return Some(
              task_report_failure(
                plan,
                workspace_root,
                exec_command_message(
                  full_checkout_stdout, full_checkout_stderr, "git checkout failed",
                ),
              ),
            )
          }
        } else {
          return Some(
            task_report_failure(
              plan,
              workspace_root,
              exec_command_message(
                checkout_stdout, checkout_stderr, "git checkout failed",
              ),
            ),
          )
        }
      }
    }
  }
  if submodules_mode.length() > 0 {
    let (submodule_code, submodule_stdout, submodule_stderr) = exec_git_update_submodules(
      git_bin, temp_root, submodules_mode,
    )
    if submodule_code != 0 {
      return Some(
        task_report_failure(
          plan,
          workspace_root,
          exec_command_message(
            submodule_stdout, submodule_stderr, "git submodule update failed",
          ),
        ),
      )
    }
  }
  // set-safe-directory
  if set_safe_directory {
    let abs_checkout = absolute_exec_path(checkout_root)
    ignore(
      exec_git_command_text(
        git_bin,
        ["config", "--global", "--add", "safe.directory", abs_checkout],
        temp_root,
      ),
    )
  }
  // persist-credentials: false removes the credential helper
  if not(persist_credentials) {
    ignore(
      exec_git_command_text(
        git_bin,
        ["config", "--local", "--unset-all", "credential.helper"],
        temp_root,
      ),
    )
  }
  // lfs
  if lfs {
    let (lfs_code, lfs_stdout, lfs_stderr) = exec_git_command_text(
      git_bin,
      ["lfs", "pull"],
      temp_root,
    )
    if lfs_code != 0 {
      return Some(
        task_report_failure(
          plan,
          workspace_root,
          exec_command_message(lfs_stdout, lfs_stderr, "git lfs pull failed"),
        ),
      )
    }
  }
  let preserve_local_files = checkout_root == source_root &&
    not(allow_destructive_clean)
  if preserve_local_files {
    // Local mode: never delete any files — only overwrite with new content.
    // This prevents accidental data loss when running in the user's working directory.
    if not(exec_overwrite_from_clone(temp_root, checkout_root)) {
      return Some(
        task_report_failure(
          plan, workspace_root, "failed to materialize checkout contents",
        ),
      )
    }
    return None
  }
  if checkout_root == source_root {
    if clean && not(exec_remove_checkout_contents_preserving_git(checkout_root)) {
      return Some(
        task_report_failure(
          plan, workspace_root, "failed to clean checkout contents",
        ),
      )
    }
    if not(exec_overwrite_from_clone(temp_root, checkout_root)) {
      return Some(
        task_report_failure(
          plan, workspace_root, "failed to materialize checkout contents",
        ),
      )
    }
    return None
  }
  if clean && not(exec_remove_tree(checkout_root)) {
    return Some(
      task_report_failure(
        plan, workspace_root, "failed to clean checkout contents",
      ),
    )
  }
  if not(exec_copy_dir_contents(temp_root, checkout_root)) {
    return Some(
      task_report_failure(
        plan, workspace_root, "failed to materialize checkout contents",
      ),
    )
  }
  None
}

///|
async fn execute_builtin_checkout_native(
  action : ResolvedAction,
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
  allow_destructive_clean? : Bool = false,
) -> TaskRunReport {
  if action.kind != "checkout" {
    return task_report_failure(
      plan,
      workspace_root,
      "builtin action kind '\{action.kind}' is not supported",
    )
  }
  let path_input = resolved_plan_env.get("INPUT_PATH").unwrap_or("")
  let sparse_input = resolved_plan_env
    .get("INPUT_SPARSE_CHECKOUT")
    .unwrap_or("")
  let fetch_depth = match
    parse_checkout_fetch_depth(
      resolved_plan_env.get("INPUT_FETCH_DEPTH").unwrap_or(""),
    ) {
    Some(value) => value
    None =>
      return task_report_failure(
        plan, workspace_root, "checkout fetch-depth must be a non-negative integer",
      )
  }
  let cone_mode = parse_bool_true_default(
    resolved_plan_env.get("INPUT_SPARSE_CHECKOUT_CONE_MODE").unwrap_or("true"),
  )
  let fetch_tags = parse_bool_true_default(
    resolved_plan_env.get("INPUT_FETCH_TAGS").unwrap_or("false"),
  )
  let clean = parse_bool_true_default(
    resolved_plan_env.get("INPUT_CLEAN").unwrap_or("true"),
  )
  let show_progress = parse_bool_true_default(
    resolved_plan_env.get("INPUT_SHOW_PROGRESS").unwrap_or("true"),
  )
  let persist_credentials = parse_bool_true_default(
    resolved_plan_env.get("INPUT_PERSIST_CREDENTIALS").unwrap_or("true"),
  )
  let set_safe_directory = parse_bool_true_default(
    resolved_plan_env.get("INPUT_SET_SAFE_DIRECTORY").unwrap_or("true"),
  )
  let lfs = parse_bool_false_default(
    resolved_plan_env.get("INPUT_LFS").unwrap_or("false"),
  )
  let repository_input = resolved_plan_env
    .get("INPUT_REPOSITORY")
    .unwrap_or("")
    .trim(chars=" \t\r\n")
    .to_string()
  let filter_input = resolved_plan_env
    .get("INPUT_FILTER")
    .unwrap_or("")
    .trim(chars=" \t\r\n")
    .to_string()
  let clone_url = if repository_input.length() > 0 {
    "https://github.com/" + repository_input + ".git"
  } else {
    ""
  }
  let source_root = resolve_task_cwd(workspace_root, "")
  let checkout_root = if path_input.length() > 0 {
    match validate_workspace_path_real(workspace_root, path_input) {
      Some(validated) => validated
      None =>
        return task_report_failure(
          plan,
          workspace_root,
          "checkout path '\{path_input}' escapes the workspace",
        )
    }
  } else {
    source_root
  }
  if exec_has_git_repo(source_root) || clone_url.length() > 0 {
    match
      exec_git_clone_checkout(
        plan,
        workspace_root,
        source_root,
        checkout_root,
        fetch_depth,
        resolved_plan_env,
        clean~,
        allow_destructive_clean~,
        fetch_tags~,
        show_progress~,
        persist_credentials~,
        set_safe_directory~,
        lfs~,
        clone_url~,
        filter=filter_input,
      ) {
      Some(report) => return report
      None => ()
    }
  } else if path_input.length() > 0 &&
    not(exec_copy_workspace_snapshot(workspace_root, checkout_root)) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to prepare checkout path '\{path_input}'",
    )
  }
  let sparse_patterns = split_nonempty_lines(sparse_input)
  if sparse_patterns.length() > 0 &&
    not(
      exec_prune_sparse_checkout(
        checkout_root, checkout_root, sparse_patterns, cone_mode,
      ),
    ) {
    return task_report_failure(
      plan, workspace_root, "failed to apply sparse-checkout",
    )
  }
  task_report_success(plan, workspace_root)
}
