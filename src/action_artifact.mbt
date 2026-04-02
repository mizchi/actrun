///|
fn artifact_parent_dir(path : String) -> String {
  let parts : Array[String] = []
  for part in path.split("/") {
    parts.push(part.to_string())
  }
  if parts.length() <= 1 {
    return "."
  }
  let dirs : Array[String] = []
  for idx in 0..<(parts.length() - 1) {
    let part = parts[idx]
    if part.length() > 0 {
      dirs.push(part)
    }
  }
  let joined = dirs.join("/")
  if joined.length() > 0 {
    if path.has_prefix("/") {
      "/" + joined
    } else {
      joined
    }
  } else if path.has_prefix("/") {
    "/"
  } else {
    "."
  }
}

///|
fn parse_artifact_if_no_files_found(value : String) -> String? {
  let normalized = value.trim(chars=" \t\r\n").to_lower()
  if normalized.length() == 0 || normalized == "warn" {
    Some("warn")
  } else if normalized == "ignore" {
    Some("ignore")
  } else if normalized == "error" {
    Some("error")
  } else {
    None
  }
}

///|
fn artifact_store_root(workspace_root : String) -> String {
  let configured = @xsys.get_env_var("ACTRUN_ARTIFACT_ROOT").unwrap_or(
    "_build/actrun/artifacts",
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
priv struct ArtifactUploadSelection {
  root_paths : Array[String]
  file_paths : Array[String]
}

///|
fn artifact_has_wildcard(pattern : String) -> Bool {
  pattern.contains("*") || pattern.contains("?")
}

///|
fn artifact_normalize_pattern(pattern : String) -> String {
  let trimmed = pattern.trim(chars=" \t\r\n").to_string()
  let without_prefix = if trimmed.has_prefix("./") {
    exec_text_slice(trimmed, 2, trimmed.length())
  } else if trimmed.has_prefix("/") {
    exec_text_slice(trimmed, 1, trimmed.length())
  } else {
    trimmed
  }
  if without_prefix.has_suffix("/") {
    exec_text_slice(without_prefix, 0, without_prefix.length() - 1)
  } else {
    without_prefix
  }
}

///|
fn artifact_path_join(base : String, child : String) -> String {
  if child.has_prefix("/") {
    return child
  }
  if base.length() == 0 || base == "." {
    child
  } else if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
fn artifact_canonical_path(path : String) -> String {
  let absolute = absolute_exec_path(path)
  if absolute.length() > 1 && absolute.has_suffix("/") {
    exec_text_slice(absolute, 0, absolute.length() - 1)
  } else {
    absolute
  }
}

///|
fn artifact_split_path(path : String) -> Array[String] {
  let out : Array[String] = []
  if path.length() == 0 {
    return out
  }
  for part_view in path.split("/") {
    let part = part_view.to_string()
    if part.length() > 0 {
      out.push(part)
    }
  }
  out
}

///|
fn artifact_match_segment(pattern : String, text : String) -> Bool {
  let mut pi = 0
  let mut si = 0
  let mut star = -1
  let mut mark = 0
  while si < text.length() {
    if pi < pattern.length() &&
      (
        pattern.unsafe_get(pi) == '?'.to_int().to_uint16() ||
        pattern.unsafe_get(pi) == text.unsafe_get(si)
      ) {
      pi += 1
      si += 1
    } else if pi < pattern.length() &&
      pattern.unsafe_get(pi) == '*'.to_int().to_uint16() {
      star = pi
      mark = si
      pi += 1
    } else if star != -1 {
      pi = star + 1
      mark += 1
      si = mark
    } else {
      return false
    }
  }
  while pi < pattern.length() &&
        pattern.unsafe_get(pi) == '*'.to_int().to_uint16() {
    pi += 1
  }
  pi == pattern.length()
}

///|
fn artifact_match_path_segments(
  patterns : Array[String],
  pattern_index : Int,
  segments : Array[String],
  segment_index : Int,
) -> Bool {
  if pattern_index >= patterns.length() {
    return segment_index >= segments.length()
  }
  let pattern = patterns[pattern_index]
  if pattern == "**" {
    let mut next_index = segment_index
    while true {
      if artifact_match_path_segments(
          patterns,
          pattern_index + 1,
          segments,
          next_index,
        ) {
        return true
      }
      if next_index >= segments.length() {
        break
      }
      next_index += 1
    }
    false
  } else {
    if segment_index >= segments.length() {
      return false
    }
    if artifact_match_segment(pattern, segments[segment_index]) {
      artifact_match_path_segments(
        patterns,
        pattern_index + 1,
        segments,
        segment_index + 1,
      )
    } else {
      false
    }
  }
}

///|
fn artifact_path_matches(pattern : String, relative_path : String) -> Bool {
  let normalized = artifact_normalize_pattern(pattern)
  if normalized.length() == 0 {
    return false
  }
  artifact_match_path_segments(
    artifact_split_path(normalized),
    0,
    artifact_split_path(relative_path),
    0,
  )
}

///|
fn artifact_collect_relative_files(
  current_abs : String,
  relative_prefix : String,
  files : Array[String],
  include_hidden? : Bool = false,
) -> Unit {
  let entries = try @xfs.read_dir(current_abs) catch {
    _ => []
  } noraise {
    value => value
  }
  entries.sort_by(String::lexical_compare)
  for entry in entries {
    if !include_hidden && entry.has_prefix(".") {
      continue
    }
    let next_abs = artifact_path_join(current_abs, entry)
    let next_relative = if relative_prefix.length() == 0 {
      entry
    } else {
      relative_prefix + "/" + entry
    }
    if exec_is_dir(next_abs) {
      artifact_collect_relative_files(
        next_abs,
        next_relative,
        files,
        include_hidden~,
      )
    } else {
      files.push(next_relative)
    }
  }
}

///|
fn artifact_collect_absolute_files(
  current_abs : String,
  files : Array[String],
) -> Unit {
  let entries = try @xfs.read_dir(current_abs) catch {
    _ => []
  } noraise {
    value => value
  }
  entries.sort_by(String::lexical_compare)
  for entry in entries {
    let next_abs = artifact_path_join(current_abs, entry)
    if exec_is_dir(next_abs) {
      artifact_collect_absolute_files(next_abs, files)
    } else {
      files.push(next_abs)
    }
  }
}

///|
fn artifact_workspace_relative_files(
  workspace_root : String,
  include_hidden? : Bool = false,
) -> Array[String] {
  let workspace_abs = absolute_exec_path(resolve_task_cwd(workspace_root, ""))
  let files : Array[String] = []
  if !@xfs.path_exists(workspace_abs) {
    return files
  }
  artifact_collect_relative_files(workspace_abs, "", files, include_hidden~)
  files
}

///|
fn artifact_glob_root(pattern : String) -> String {
  let stable_segments : Array[String] = []
  for segment in artifact_split_path(artifact_normalize_pattern(pattern)) {
    if artifact_has_wildcard(segment) {
      break
    }
    stable_segments.push(segment)
  }
  stable_segments.join("/")
}

///|
fn artifact_is_prefix_dir(path : String, prefix : String) -> Bool {
  if path == prefix {
    return true
  }
  if prefix == "/" {
    return path.has_prefix("/")
  }
  path.has_prefix(prefix + "/")
}

///|
fn artifact_common_ancestor(paths : Array[String]) -> String {
  if paths.length() == 0 {
    return absolute_exec_path(".")
  }
  let mut current = artifact_canonical_path(paths[0])
  let mut found = false
  while !found {
    let mut all_contained = true
    for path in paths {
      if !artifact_is_prefix_dir(artifact_canonical_path(path), current) {
        all_contained = false
        break
      }
    }
    if all_contained {
      found = true
    } else {
      let parent = artifact_parent_dir(current)
      if parent == current {
        found = true
      } else {
        current = artifact_canonical_path(parent)
      }
    }
  }
  current
}

///|
fn artifact_select_upload_files(
  workspace_root : String,
  upload_paths : Array[String],
  include_hidden? : Bool = false,
) -> ArtifactUploadSelection {
  let included_roots : Array[String] = []
  let included_files : Map[String, Bool] = {}
  let excluded_patterns : Array[String] = []
  let workspace_files = artifact_workspace_relative_files(
    workspace_root,
    include_hidden~,
  )
  for raw_path in upload_paths {
    let path = raw_path.trim(chars=" \t\r\n").to_string()
    if path.has_prefix("!") {
      excluded_patterns.push(exec_text_slice(path, 1, path.length()))
      continue
    }
    if artifact_has_wildcard(path) {
      let root_relative = artifact_glob_root(path)
      let root_abs = artifact_canonical_path(
        resolve_task_cwd(workspace_root, root_relative),
      )
      if @xfs.path_exists(root_abs) {
        included_roots.push(root_abs)
      }
      for relative_path in workspace_files {
        if artifact_path_matches(path, relative_path) {
          included_files[absolute_exec_path(
            resolve_task_cwd(workspace_root, relative_path),
          )] = true
        }
      }
      continue
    }
    // Reject paths that escape the workspace
    guard validate_workspace_path(workspace_root, path) is Some(_) else {
      continue
    }
    let resolved_path = resolve_task_cwd(workspace_root, path)
    if !@xfs.path_exists(resolved_path) {
      continue
    }
    let absolute_path = artifact_canonical_path(resolved_path)
    if exec_is_dir(absolute_path) {
      included_roots.push(absolute_path)
      let child_files : Array[String] = []
      artifact_collect_absolute_files(absolute_path, child_files)
      for child in child_files {
        included_files[child] = true
      }
    } else {
      let root = artifact_canonical_path(artifact_parent_dir(absolute_path))
      included_roots.push(root)
      included_files[absolute_path] = true
    }
  }
  let selected_files : Array[String] = []
  for absolute_path, _ in included_files {
    let mut excluded = false
    for pattern in excluded_patterns {
      guard workspace_relative_store_path(workspace_root, absolute_path)
        is Some(relative_path) else {
        continue
      }
      if artifact_path_matches(pattern, relative_path) {
        excluded = true
        break
      }
    }
    if !excluded {
      selected_files.push(absolute_path)
    }
  }
  selected_files.sort_by(String::lexical_compare)
  { root_paths: included_roots, file_paths: selected_files }
}

///|
fn execute_upload_artifact_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskRunReport {
  let name = resolved_plan_env.get("INPUT_NAME").unwrap_or("")
  let path_input = resolved_plan_env.get("INPUT_PATH").unwrap_or("")
  let overwrite = parse_bool_false_default(
    resolved_plan_env.get("INPUT_OVERWRITE").unwrap_or("false"),
  )
  if name.length() == 0 {
    return task_report_failure(
      plan, workspace_root, "upload-artifact requires with.name",
    )
  }
  let include_hidden = parse_bool_false_default(
    resolved_plan_env.get("INPUT_INCLUDE_HIDDEN_FILES").unwrap_or("false"),
  )
  let upload_paths = split_nonempty_lines(path_input)
  if upload_paths.length() == 0 {
    return task_report_failure(
      plan, workspace_root, "upload-artifact requires with.path",
    )
  }
  let artifact_root = artifact_store_root(workspace_root) +
    "/" +
    sanitize_task_id(name)
  let selection = artifact_select_upload_files(
    workspace_root,
    upload_paths,
    include_hidden~,
  )
  let if_no_files_found = match
    parse_artifact_if_no_files_found(
      resolved_plan_env.get("INPUT_IF_NO_FILES_FOUND").unwrap_or(""),
    ) {
    Some(value) => value
    None =>
      return task_report_failure(
        plan, workspace_root, "upload-artifact if-no-files-found must be one of warn, ignore, error",
      )
  }
  if selection.file_paths.length() == 0 {
    return if if_no_files_found == "error" {
      task_report_failure(
        plan,
        workspace_root,
        "upload-artifact found no files for '\{path_input}'",
      )
    } else {
      task_report_success(plan, workspace_root)
    }
  }
  if @xfs.path_exists(artifact_root) {
    if !overwrite {
      return task_report_failure(
        plan,
        workspace_root,
        "upload-artifact artifact '\{name}' already exists and overwrite is false",
      )
    }
    if !exec_remove_tree(artifact_root) {
      return task_report_failure(
        plan,
        workspace_root,
        "failed to clear artifact store for '\{name}'",
      )
    }
  }
  if !ensure_exec_dir_recursive(artifact_root) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to prepare artifact store for '\{name}'",
    )
  }
  let artifact_root_path = artifact_common_ancestor(selection.root_paths)
  for absolute_path in selection.file_paths {
    let relative_path = exec_relative_path(artifact_root_path, absolute_path)
    let target = if relative_path.length() > 0 {
      artifact_root + "/" + relative_path
    } else {
      artifact_root + "/" + exec_leaf_name(absolute_path)
    }
    if !exec_copy_tree(absolute_path, target) {
      return task_report_failure(
        plan,
        workspace_root,
        "failed to upload artifact path '\{absolute_path}'",
      )
    }
  }
  task_report_success(plan, workspace_root)
}

///|
fn execute_download_artifact_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskRunReport {
  let name = resolved_plan_env.get("INPUT_NAME").unwrap_or("")
  let pattern = resolved_plan_env.get("INPUT_PATTERN").unwrap_or("")
  let path_input = resolved_plan_env.get("INPUT_PATH").unwrap_or("")
  let merge_multiple = parse_bool_false_default(
    resolved_plan_env.get("INPUT_MERGE_MULTIPLE").unwrap_or("false"),
  )
  let destination = if path_input.length() > 0 {
    resolve_task_cwd(workspace_root, path_input)
  } else {
    resolve_task_cwd(workspace_root, "")
  }
  if !ensure_exec_dir_recursive(destination) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to prepare artifact download dir '\{destination}'",
    )
  }
  if name.length() == 0 {
    let store_root = artifact_store_root(workspace_root)
    let artifact_entries = try @xfs.read_dir(store_root) catch {
      _ => []
    } noraise {
      value => value
    }
    artifact_entries.sort_by(String::lexical_compare)
    let mut copied_any = false
    for entry in artifact_entries {
      let artifact_root = store_root + "/" + entry
      if !exec_is_dir(artifact_root) {
        continue
      }
      if pattern.length() > 0 && !artifact_path_matches(pattern, entry) {
        continue
      }
      let target = if merge_multiple {
        destination
      } else {
        destination + "/" + entry
      }
      if !exec_copy_tree(artifact_root, target) {
        return task_report_failure(
          plan,
          workspace_root,
          "failed to download artifact '\{entry}'",
        )
      }
      copied_any = true
    }
    if !copied_any {
      return task_report_failure(
        plan, workspace_root, "download-artifact could not find any artifacts",
      )
    }
    return task_report_success(plan, workspace_root)
  }
  let artifact_root = artifact_store_root(workspace_root) +
    "/" +
    sanitize_task_id(name)
  if !@xfs.path_exists(artifact_root) {
    return task_report_failure(
      plan,
      workspace_root,
      "download-artifact could not find artifact '\{name}'",
    )
  }
  let entries = try @xfs.read_dir(artifact_root) catch {
    _ => []
  } noraise {
    value => value
  }
  entries.sort_by(String::lexical_compare)
  for entry in entries {
    if !exec_copy_tree(artifact_root + "/" + entry, destination + "/" + entry) {
      return task_report_failure(
        plan,
        workspace_root,
        "failed to download artifact '\{name}'",
      )
    }
  }
  task_report_success(plan, workspace_root)
}
