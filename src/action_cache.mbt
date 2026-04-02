///|
fn cache_store_root(workspace_root : String) -> String {
  let configured = @xsys.get_env_var("ACTRUN_CACHE_ROOT").unwrap_or(
    "_build/actrun/cache",
  )
  ignore(ensure_exec_dir_recursive(configured))
  let workspace_key = sanitize_task_id(
    absolute_exec_path(resolve_task_cwd(workspace_root, "")),
  )
  let root = absolute_exec_path(configured + "/" + workspace_key)
  ignore(ensure_exec_dir_recursive(root))
  root
}

///|
fn cache_sequence_path(workspace_root : String) -> String {
  cache_store_root(workspace_root) + "/__actrun_sequence.txt"
}

///|
fn cache_key_metadata_path(cache_root : String) -> String {
  cache_root + "/__actrun_cache_key.txt"
}

///|
fn cache_sequence_metadata_path(cache_root : String) -> String {
  cache_root + "/__actrun_cache_sequence.txt"
}

///|
fn cache_store_path(workspace_root : String, key : String) -> String {
  cache_store_root(workspace_root) + "/" + sanitize_task_id(key)
}

///|
#warnings("-deprecated")
fn action_cache_parse_int64(value : StringView) -> Int64 raise {
  @strconv.parse_int64(value)
}

///|
fn read_exec_int(path : String) -> Int? {
  guard read_exec_text(path) is Some(content) else { return None }
  let trimmed = content.trim(chars=" \t\r\n").to_string()
  if trimmed.length() == 0 {
    return None
  }
  let parsed = action_cache_parse_int64(trimmed) catch { _ => return None }
  Some(parsed.to_int())
}

///|
fn write_cache_metadata(
  workspace_root : String,
  key : String,
  cache_root : String,
) -> Bool {
  let next_sequence = read_exec_int(cache_sequence_path(workspace_root)).unwrap_or(
      0,
    ) +
    1
  if !write_exec_text(
      cache_sequence_path(workspace_root),
      next_sequence.to_string(),
    ) {
    return false
  }
  if !write_exec_text(cache_key_metadata_path(cache_root), key) {
    return false
  }
  write_exec_text(
    cache_sequence_metadata_path(cache_root),
    next_sequence.to_string(),
  )
}

///|
fn read_cache_entry_key(cache_root : String) -> String? {
  let key_path = cache_key_metadata_path(cache_root)
  if @xfs.path_exists(key_path) {
    return read_exec_text(key_path).map(text => {
      text.trim(chars=" \t\r\n").to_string()
    })
  }
  None
}

///|
fn read_cache_entry_sequence(cache_root : String) -> Int {
  read_exec_int(cache_sequence_metadata_path(cache_root)).unwrap_or(0)
}

///|
fn restore_key_candidates(
  key : String,
  restore_keys_input : String,
) -> Array[String] {
  let candidates : Array[String] = []
  candidates.push(key)
  for restore_key in split_nonempty_lines(restore_keys_input) {
    candidates.push(restore_key)
  }
  candidates
}

///|
priv enum CacheRestoreLookup {
  Exact(String)
  Partial(String)
  Miss
  Err(String)
}

///|
fn resolve_cache_restore_lookup(
  workspace_root : String,
  key : String,
  restore_keys_input : String,
) -> CacheRestoreLookup {
  let exact_root = cache_store_path(workspace_root, key)
  if @xfs.path_exists(exact_root) {
    return Exact(key)
  }
  let store_root = cache_store_root(workspace_root)
  let entries = try @xfs.read_dir(store_root) catch {
    _ => return Err("failed to inspect cache store")
  } noraise {
    value => value
  }
  let candidates = restore_key_candidates(key, restore_keys_input)
  for candidate in candidates {
    let mut selected_key = ""
    let mut selected_sequence = -1
    for entry in entries {
      if entry == "__actrun_sequence.txt" {
        continue
      }
      let entry_root = store_root + "/" + entry
      guard read_cache_entry_key(entry_root) is Some(entry_key) else {
        continue
      }
      let sequence = read_cache_entry_sequence(entry_root)
      if entry_key.has_prefix(candidate) && sequence >= selected_sequence {
        selected_key = entry_key
        selected_sequence = sequence
      }
    }
    if selected_key.length() > 0 {
      return Partial(selected_key)
    }
  }
  Miss
}

///|
fn workspace_relative_store_path(
  workspace_root : String,
  resolved_path : String,
) -> String? {
  let workspace_abs = absolute_exec_path(resolve_task_cwd(workspace_root, ""))
  let resolved_abs = absolute_exec_path(resolved_path)
  if resolved_abs == workspace_abs {
    return Some("__root__")
  }
  let prefix = workspace_abs + "/"
  if resolved_abs.has_prefix(prefix) {
    return Some(
      exec_text_slice(resolved_abs, prefix.length(), resolved_abs.length()),
    )
  }
  None
}

///|
fn normalize_cache_path(path : String) -> String {
  let trimmed = path.trim(chars=" \t\r\n").to_string()
  if trimmed.has_prefix("~/") {
    let home = @xsys.get_env_var("HOME").unwrap_or("")
    if home.length() > 0 {
      return home + exec_text_slice(trimmed, 1, trimmed.length())
    }
  }
  if trimmed == "~" {
    return @xsys.get_env_var("HOME").unwrap_or(trimmed)
  }
  trimmed
}

///|
fn normalize_cache_paths(paths : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for path in paths {
    result.push(normalize_cache_path(path))
  }
  result
}

///|
fn execute_save_cache_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskRunReport {
  let key = resolved_plan_env.get("INPUT_KEY").unwrap_or("")
  let path_input = resolved_plan_env.get("INPUT_PATH").unwrap_or("")
  if key.length() == 0 {
    return task_report_failure(
      plan, workspace_root, "cache-save requires with.key",
    )
  }
  let cache_paths = normalize_cache_paths(split_nonempty_lines(path_input))
  if cache_paths.length() == 0 {
    return task_report_failure(
      plan, workspace_root, "cache-save requires with.path",
    )
  }
  let cache_root = cache_store_path(workspace_root, key)
  if !exec_remove_tree(cache_root) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to clear cache store for '\{key}'",
    )
  }
  if !ensure_exec_dir_recursive(cache_root) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to prepare cache store for '\{key}'",
    )
  }
  let mut copied = false
  for input_path in cache_paths {
    let resolved_path = resolve_task_cwd(workspace_root, input_path)
    if !@xfs.path_exists(resolved_path) {
      continue
    }
    guard workspace_relative_store_path(workspace_root, resolved_path)
      is Some(relative_path) else {
      return task_report_failure(
        plan,
        workspace_root,
        "cache-save path '\{input_path}' must stay within the workspace",
      )
    }
    let target = cache_root + "/" + relative_path
    if !exec_copy_tree(resolved_path, target) {
      return task_report_failure(
        plan,
        workspace_root,
        "failed to save cache path '\{input_path}'",
      )
    }
    copied = true
  }
  if !copied {
    return task_report_failure(
      plan,
      workspace_root,
      "cache-save found no files for '\{path_input}'",
    )
  }
  if !write_cache_metadata(workspace_root, key, cache_root) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to write cache metadata for '\{key}'",
    )
  }
  task_report_success(plan, workspace_root)
}

///|
fn cache_input_result_failure(
  plan : TaskPlan,
  workspace_root : String,
  action_name : String,
  missing_key : Bool,
) -> TaskExecutionResult {
  let message = if missing_key {
    action_name + " requires with.key"
  } else {
    action_name + " requires with.path"
  }
  failure_execution_result(plan, workspace_root, message)
}

///|
fn restore_cache_store_native(
  workspace_root : String,
  key : String,
  restore_keys_input : String,
  lookup_only : Bool,
) -> CacheRestoreLookup {
  let lookup = resolve_cache_restore_lookup(
    workspace_root, key, restore_keys_input,
  )
  let matched_key = match lookup {
    Exact(found_key) => found_key
    Partial(found_key) => found_key
    Miss => return Miss
    Err(message) => return Err(message)
  }
  if lookup_only {
    return match lookup {
      Exact(_) => Exact(matched_key)
      Partial(_) => Partial(matched_key)
      Miss => Miss
      Err(message) => Err(message)
    }
  }
  let cache_root = cache_store_path(workspace_root, matched_key)
  let entries = try @xfs.read_dir(cache_root) catch {
    _ => return Err("failed to inspect cache '\{matched_key}'")
  } noraise {
    value => value
  }
  for entry in entries {
    if entry == "__actrun_cache_key.txt" ||
      entry == "__actrun_cache_sequence.txt" {
      continue
    }
    let source = cache_root + "/" + entry
    if entry == "__root__" {
      let root_entries = try @xfs.read_dir(source) catch {
        _ => return Err("failed to inspect cache '\{matched_key}' root")
      } noraise {
        value => value
      }
      for root_entry in root_entries {
        // Reject entries that could escape the workspace via path traversal
        if root_entry.contains("..") {
          continue
        }
        if !exec_copy_tree(
            source + "/" + root_entry,
            workspace_root + "/" + root_entry,
          ) {
          return Err("failed to restore cache '\{matched_key}'")
        }
      }
    } else if entry.contains("..") {
      return Err("cache entry '\{entry}' contains invalid path component")
    } else if !exec_copy_tree(source, workspace_root + "/" + entry) {
      return Err("failed to restore cache '\{matched_key}'")
    }
  }
  match lookup {
    Exact(_) => Exact(matched_key)
    Partial(_) => Partial(matched_key)
    Miss => Miss
    Err(message) => Err(message)
  }
}

///|
fn execute_restore_cache_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskExecutionResult {
  let key = resolved_plan_env.get("INPUT_KEY").unwrap_or("")
  let restore_keys_input = resolved_plan_env
    .get("INPUT_RESTORE_KEYS")
    .unwrap_or("")
  let lookup_only = parse_bool_false_default(
    resolved_plan_env.get("INPUT_LOOKUP_ONLY").unwrap_or(""),
  )
  let fail_on_cache_miss = parse_bool_false_default(
    resolved_plan_env.get("INPUT_FAIL_ON_CACHE_MISS").unwrap_or(""),
  )
  let path_input = resolved_plan_env.get("INPUT_PATH").unwrap_or("")
  if key.length() == 0 {
    return cache_input_result_failure(
      plan, workspace_root, "cache-restore", true,
    )
  }
  if split_nonempty_lines(path_input).length() == 0 {
    return cache_input_result_failure(
      plan, workspace_root, "cache-restore", false,
    )
  }
  let cache_hit = match
    restore_cache_store_native(
      workspace_root, key, restore_keys_input, lookup_only,
    ) {
    Exact(_) => "true"
    Partial(_) => "false"
    Miss =>
      if fail_on_cache_miss {
        return failure_execution_result(
          plan,
          workspace_root,
          "cache miss for key '\{key}' and fail-on-cache-miss is true",
        )
      } else {
        "false"
      }
    Err(message) =>
      return failure_execution_result(plan, workspace_root, message)
  }
  {
    report: task_report_success(plan, workspace_root),
    env_updates: {},
    path_entries: [],
    output_values: { "cache-hit": cache_hit },
    state_updates: {},
  }
}

///|
fn execute_cache_action_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskExecutionResult {
  let key = resolved_plan_env.get("INPUT_KEY").unwrap_or("")
  let restore_keys_input = resolved_plan_env
    .get("INPUT_RESTORE_KEYS")
    .unwrap_or("")
  let lookup_only = parse_bool_false_default(
    resolved_plan_env.get("INPUT_LOOKUP_ONLY").unwrap_or(""),
  )
  let fail_on_cache_miss = parse_bool_false_default(
    resolved_plan_env.get("INPUT_FAIL_ON_CACHE_MISS").unwrap_or(""),
  )
  let save_always = parse_bool_false_default(
    resolved_plan_env.get("INPUT_SAVE_ALWAYS").unwrap_or("false"),
  )
  let path_input = resolved_plan_env.get("INPUT_PATH").unwrap_or("")
  if key.length() == 0 {
    return cache_input_result_failure(plan, workspace_root, "cache", true)
  }
  if split_nonempty_lines(path_input).length() == 0 {
    return cache_input_result_failure(plan, workspace_root, "cache", false)
  }
  let cache_hit = match
    restore_cache_store_native(
      workspace_root, key, restore_keys_input, lookup_only,
    ) {
    Exact(_) => "true"
    Partial(_) => "false"
    Miss =>
      if fail_on_cache_miss {
        return {
          report: task_report_failure(
            plan,
            workspace_root,
            "cache miss for key '\{key}' and fail-on-cache-miss is true",
          ),
          env_updates: {},
          path_entries: [],
          output_values: {},
          state_updates: {
            "CACHE_KEY": key,
            "CACHE_PATH": path_input,
            "CACHE_HIT": "",
            "CACHE_SKIP_POST": "true",
          },
        }
      } else {
        ""
      }
    Err(message) =>
      return failure_execution_result(plan, workspace_root, message)
  }
  {
    report: task_report_success(plan, workspace_root),
    env_updates: {},
    path_entries: [],
    output_values: { "cache-hit": cache_hit },
    state_updates: {
      "CACHE_KEY": key,
      "CACHE_PATH": path_input,
      "CACHE_HIT": cache_hit,
      "CACHE_SAVE_ALWAYS": if save_always {
        "true"
      } else {
        ""
      },
    },
  }
}

///|
fn execute_cache_post_save_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
  state : JobRuntimeState,
) -> TaskRunReport {
  let saved_state = action_scope_state(state, plan.action_scope)
  let save_always = saved_state.get("CACHE_SAVE_ALWAYS").unwrap_or("") == "true"
  if !save_always {
    if saved_state.get("CACHE_SKIP_POST").unwrap_or("") == "true" {
      return task_report_success(plan, workspace_root)
    }
    if saved_state.get("CACHE_HIT").unwrap_or("") == "true" {
      return task_report_success(plan, workspace_root)
    }
  }
  let key = saved_state
    .get("CACHE_KEY")
    .unwrap_or(resolved_plan_env.get("INPUT_KEY").unwrap_or(""))
  let path_input = saved_state
    .get("CACHE_PATH")
    .unwrap_or(resolved_plan_env.get("INPUT_PATH").unwrap_or(""))
  return execute_save_cache_native(
    plan,
    workspace_root,
    merge_runner_env(resolved_plan_env, {
      "INPUT_KEY": key,
      "INPUT_PATH": path_input,
    }),
  )
}

///|
fn execute_cache_builtin_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
  state : JobRuntimeState,
  action_kind : String,
) -> TaskExecutionResult {
  if action_kind == "cache" {
    return execute_cache_action_native(plan, workspace_root, resolved_plan_env)
  }
  if action_kind == "cache-restore" {
    return execute_restore_cache_native(plan, workspace_root, resolved_plan_env)
  }
  if action_kind == "cache-save" {
    return builtin_task_result(
      execute_save_cache_native(plan, workspace_root, resolved_plan_env),
    )
  }
  if action_kind == "cache-save-post" {
    return builtin_task_result(
      execute_cache_post_save_native(
        plan, workspace_root, resolved_plan_env, state,
      ),
    )
  }
  cache_input_result_failure(plan, workspace_root, action_kind, true)
}
