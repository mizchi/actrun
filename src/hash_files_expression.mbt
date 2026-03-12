///|
fn if_function_arguments_at_least(
  expression : String,
  function_name : String,
  min_arity : Int,
) -> Array[String]? {
  let trimmed = strip_if_outer_parens(expression)
  let lower = trimmed.to_lower()
  let prefix = function_name.to_lower() + "("
  guard lower.has_prefix(prefix) && trimmed.has_suffix(")") else { return None }
  let inner = if_text_slice(trimmed, prefix.length(), trimmed.length() - 1)
  guard split_top_level_if_arguments(inner) is Some(args) else { return None }
  if args.length() < min_arity {
    None
  } else {
    Some(args)
  }
}

///|
fn if_hash_files_function_supported(text : String) -> Bool {
  match if_function_arguments_at_least(text, "hashFiles", 1) {
    Some(args) => {
      for arg in args {
        if not(if_condition_supported(arg)) {
          return false
        }
      }
      true
    }
    None => false
  }
}

///|
fn if_hash_files_join(base : String, child : String) -> String {
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
fn if_hash_files_is_dir(path : String) -> Bool {
  try @xfs.is_dir(path) catch {
    _ => false
  } noraise {
    value => value
  }
}

///|
fn if_hash_files_normalize_pattern(pattern : String) -> String {
  let trimmed = pattern.trim(chars=" \t\r\n").to_string()
  let without_prefix = if trimmed.has_prefix("./") {
    if_text_slice(trimmed, 2, trimmed.length())
  } else if trimmed.has_prefix("/") {
    if_text_slice(trimmed, 1, trimmed.length())
  } else {
    trimmed
  }
  if without_prefix.has_suffix("/") {
    if_text_slice(without_prefix, 0, without_prefix.length() - 1)
  } else {
    without_prefix
  }
}

///|
fn if_hash_files_pattern_matches(
  pattern : String,
  relative_path : String,
) -> Bool {
  let normalized = if_hash_files_normalize_pattern(pattern)
  if normalized.length() == 0 {
    return false
  }
  if wildcard_match(normalized, relative_path) {
    return true
  }
  if normalized.has_prefix("**/") && normalized.length() > 3 {
    return if_hash_files_pattern_matches(
      if_text_slice(normalized, 3, normalized.length()),
      relative_path,
    )
  }
  false
}

///|
fn if_hash_files_collect_files(
  current_abs : String,
  relative_prefix : String,
  files : Array[String],
) -> Unit {
  let entries = @xfs.read_dir(current_abs) catch { _ => [] }
  entries.sort_by(String::lexical_compare)
  for entry in entries {
    let next_abs = if_hash_files_join(current_abs, entry)
    let next_relative = if relative_prefix.length() == 0 {
      entry
    } else {
      relative_prefix + "/" + entry
    }
    if if_hash_files_is_dir(next_abs) {
      if_hash_files_collect_files(next_abs, next_relative, files)
    } else {
      files.push(next_relative)
    }
  }
}

///|
fn if_hash_files_selected_paths(
  workspace_root : String,
  patterns : Array[String],
) -> Array[String] {
  if workspace_root.length() == 0 || not(@xfs.path_exists(workspace_root)) {
    return []
  }
  let workspace_abs = absolute_exec_path(workspace_root)
  let all_files : Array[String] = []
  if_hash_files_collect_files(workspace_abs, "", all_files)
  let selected : Map[String, Bool] = {}
  for raw_pattern in patterns {
    let trimmed = raw_pattern.trim(chars=" \t\r\n").to_string()
    if trimmed.length() == 0 {
      continue
    }
    let excluded = trimmed.has_prefix("!")
    let pattern = if excluded {
      if_text_slice(trimmed, 1, trimmed.length())
    } else {
      trimmed
    }
    for relative_path in all_files {
      if if_hash_files_pattern_matches(pattern, relative_path) {
        if excluded {
          selected.remove(relative_path)
        } else {
          selected[relative_path] = true
        }
      }
    }
  }
  let values : Array[String] = []
  for relative_path, _ in selected {
    values.push(relative_path)
  }
  values.sort_by(String::lexical_compare)
  values
}

///|
fn if_hash_files_digest(
  workspace_root : String,
  patterns : Array[String],
) -> String {
  let matched = if_hash_files_selected_paths(workspace_root, patterns)
  if matched.length() == 0 {
    return ""
  }
  let workspace_abs = absolute_exec_path(workspace_root)
  let final_hash = @crypto.SHA256::new()
  for relative_path in matched {
    let absolute_path = if_hash_files_join(workspace_abs, relative_path)
    let bytes = @xfs.read_file_to_bytes(absolute_path) catch { _ => continue }
    final_hash.update(@crypto.sha256(bytes))
  }
  @crypto.bytes_to_hex_string(final_hash.finalize())
}

///|
fn if_hash_files_function_value(
  text : String,
  ctx : IfConditionContext,
) -> ConditionValue? {
  match if_function_arguments_at_least(text, "hashFiles", 1) {
    Some(args) => {
      let patterns : Array[String] = []
      for arg in args {
        patterns.push(
          if_condition_value_to_string(if_condition_atom_value(arg, ctx)),
        )
      }
      let digest = if_hash_files_digest(ctx.workspace_root, patterns)
      Some(if_condition_value_from_json(Json::string(digest)))
    }
    None => None
  }
}
