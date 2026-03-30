///|
fn merge_env(
  base : Map[String, String],
  overlay : Map[String, String],
) -> Map[String, String] {
  let merged : Map[String, String] = {}
  for key, value in base {
    merged[key] = value
  }
  for key, value in overlay {
    merged[key] = value
  }
  merged
}

///|
fn resolve_string(
  workflow_value : String?,
  job_value : String?,
  step_value : String?,
  fallback : String,
) -> String {
  match step_value {
    Some(value) => value
    None =>
      match job_value {
        Some(value) => value
        None =>
          match workflow_value {
            Some(value) => value
            None => fallback
          }
      }
  }
}

///|
fn default_step_id(step : StepSpec, index : Int) -> String {
  if step.id.length() > 0 {
    step.id
  } else {
    "step_" + (index + 1).to_string()
  }
}

///|
fn step_task_id(job_id : String, step_id : String) -> String {
  job_id + "/" + step_id
}

///|
fn finish_task_id(job_id : String) -> String {
  job_id + "/__finish"
}

///|
fn composite_step_id(outer_step_id : String, inner_step_id : String) -> String {
  outer_step_id + "__" + inner_step_id
}

///|
fn lifecycle_step_id(step_id : String, phase : String) -> String {
  step_id + "__" + phase
}

///|
priv struct ExpandedJob {
  job : JobSpec
  visible_needs : Array[String]
  need_targets : Map[String, Array[String]]
  matrix_group : String?
  matrix_fail_fast : Bool
}

///|
fn job_id_set(jobs : Array[JobSpec]) -> Map[String, Bool] {
  let seen : Map[String, Bool] = {}
  for job in jobs {
    seen[job.id] = true
  }
  seen
}

///|
fn workflow_parallelism(job_count : Int) -> Int {
  if job_count == 0 {
    1
  } else {
    job_count
  }
}

///|
fn text_slice(text : String, start : Int, end_ : Int) -> String {
  String::unsafe_substring(text, start~, end=end_)
}

///|
fn normalize_local_action_path(path : String) -> String {
  let trimmed = path.trim(chars=" ").to_string()
  let is_absolute = trimmed.has_prefix("/")
  let parts : Array[String] = []
  for part_view in trimmed.split("/") {
    let part = part_view.to_string()
    if part.length() == 0 || part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 && parts[parts.length() - 1] != ".." {
        ignore(parts.pop())
      } else {
        parts.push(part)
      }
      continue
    }
    parts.push(part)
  }
  let normalized = parts.join("/")
  if normalized.length() == 0 {
    if is_absolute {
      "/"
    } else {
      "."
    }
  } else if is_absolute {
    "/" + normalized
  } else {
    normalized
  }
}

///|
fn join_path(base : String, child : String) -> String {
  if child.has_prefix("/") {
    return child
  }
  if base == "." || base.length() == 0 {
    return child
  }
  if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
fn absolute_lowering_path(path : String) -> String {
  if path.has_prefix("/") {
    return path
  }
  let cwd = @xsys.get_env_var("PWD").unwrap_or(".")
  if cwd.has_suffix("/") {
    cwd + path
  } else {
    cwd + "/" + path
  }
}

///|
fn lowering_path_segments(path : String) -> Array[String] {
  let segments : Array[String] = []
  let absolute = normalize_local_action_path(absolute_lowering_path(path))
  for part_view in absolute.split("/") {
    let part = part_view.to_string()
    if part.length() > 0 && part != "." {
      segments.push(part)
    }
  }
  segments
}

///|
fn relative_local_action_ref(
  base_root : String,
  target_path : String,
) -> String {
  let base_segments = lowering_path_segments(base_root)
  let target_segments = lowering_path_segments(target_path)
  let mut common = 0
  while common < base_segments.length() &&
        common < target_segments.length() &&
        base_segments[common] == target_segments[common] {
    common += 1
  }
  let relative_segments : Array[String] = []
  for _ in common..<base_segments.length() {
    relative_segments.push("..")
  }
  for idx in common..<target_segments.length() {
    relative_segments.push(target_segments[idx])
  }
  let relative = relative_segments.join("/")
  if relative.length() == 0 {
    "./"
  } else if relative.has_prefix("..") {
    relative
  } else {
    "./" + relative
  }
}

///|
fn rewrite_reusable_step_local_uses(
  step : StepSpec,
  source_root : String,
  execution_root : String,
) -> StepSpec {
  match step.uses {
    Some(uses) =>
      match parse_action_ref(uses).action {
        Some(LocalPath(local_path)) => {
          let resolved_path = normalize_local_action_path(
            join_path(source_root, local_path),
          )
          {
            id: step.id,
            name: step.name,
            run: step.run,
            uses: Some(relative_local_action_ref(execution_root, resolved_path)),
            shell: step.shell,
            working_directory: step.working_directory,
            env: step.env,
            with_values: step.with_values,
            if_condition: step.if_condition,
            continue_on_error: step.continue_on_error,
            timeout_minutes: step.timeout_minutes,
          }
        }
        _ => step
      }
    None => step
  }
}

///|
fn github_action_cache_root() -> String {
  absolute_lowering_path(
    @xsys.get_env_var("ACTRUN_GITHUB_ACTION_CACHE_ROOT").unwrap_or(
      "_build/actrun/github_actions",
    ),
  )
}

///|
fn action_registry_root() -> String {
  absolute_lowering_path(
    @xsys.get_env_var("ACTRUN_ACTION_REGISTRY_ROOT").unwrap_or(
      "_build/actrun/registry_actions",
    ),
  )
}

///|
priv struct GitHubActionCacheLayout {
  uses : String
  owner : String
  repo : String
  version : String
  repo_root : String
  action_root : String
}

///|
fn github_action_cache_layout(
  action_ref : ActionRef,
) -> GitHubActionCacheLayout? {
  match action_ref {
    GitHubRepo(owner, repo, version, subpath) =>
      if version.length() == 0 {
        None
      } else {
        let repo_root = join_path(
          join_path(join_path(github_action_cache_root(), owner), repo),
          version,
        )
        let action_root = match subpath {
          Some(path) if path.length() > 0 => join_path(repo_root, path)
          _ => repo_root
        }
        Some({
          uses: action_ref_text(action_ref),
          owner,
          repo,
          version,
          repo_root,
          action_root,
        })
      }
    _ => None
  }
}

///|
fn has_action_manifest(action_root : String) -> Bool {
  read_text(join_path(action_root, "action.yml")) is Some(_) ||
  read_text(join_path(action_root, "action.yaml")) is Some(_)
}

///|
fn cached_github_action_root(action_ref : ActionRef) -> String? {
  match github_action_cache_layout(action_ref) {
    Some(layout) =>
      if has_action_manifest(layout.action_root) {
        Some(layout.action_root)
      } else {
        None
      }
    None => None
  }
}

///|
fn cached_github_repo_path(action_ref : ActionRef) -> String? {
  match github_action_cache_layout(action_ref) {
    Some(layout) =>
      if @xfs.path_exists(layout.action_root) {
        Some(layout.action_root)
      } else {
        None
      }
    None => None
  }
}

///|
fn cached_github_repo_root(action_ref : ActionRef) -> String? {
  match github_action_cache_layout(action_ref) {
    Some(layout) =>
      if @xfs.path_exists(layout.repo_root) {
        Some(layout.repo_root)
      } else {
        None
      }
    None => None
  }
}

///|
fn custom_registry_action_root(action_ref : ActionRef) -> String? {
  match action_ref {
    Registry(scheme, name, version) =>
      if scheme == "builtin" || scheme == "wasm" || version.length() == 0 {
        None
      } else {
        let action_root = join_path(
          join_path(join_path(action_registry_root(), scheme), name),
          version,
        )
        if has_action_manifest(action_root) {
          Some(action_root)
        } else {
          None
        }
      }
    _ => None
  }
}

///|
fn manifest_backed_action_root(action_ref : ActionRef) -> String? {
  match cached_github_action_root(action_ref) {
    Some(root) => Some(root)
    None => custom_registry_action_root(action_ref)
  }
}

///|
fn find_substring(text : String, pattern : String, start : Int) -> Int? {
  if pattern.length() == 0 {
    return Some(start)
  }
  let mut idx = start
  while idx + pattern.length() <= text.length() {
    let mut matched = true
    let mut offset = 0
    while offset < pattern.length() {
      if text.unsafe_get(idx + offset) != pattern.unsafe_get(offset) {
        matched = false
        break
      }
      offset += 1
    }
    if matched {
      return Some(idx)
    }
    idx += 1
  }
  None
}

///|
fn input_expr_name(expression : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  if trimmed.has_prefix("inputs.") && trimmed.length() > 7 {
    Some(text_slice(trimmed, 7, trimmed.length()))
  } else {
    None
  }
}

///|
fn is_matrix_ident_code(c : UInt16) -> Bool {
  (c >= 'a'.to_int().to_uint16() && c <= 'z'.to_int().to_uint16()) ||
  (c >= 'A'.to_int().to_uint16() && c <= 'Z'.to_int().to_uint16()) ||
  (c >= '0'.to_int().to_uint16() && c <= '9'.to_int().to_uint16()) ||
  c == '_'.to_int().to_uint16() ||
  c == '-'.to_int().to_uint16()
}

///|
fn matrix_expr_name(expression : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  if trimmed.has_prefix("matrix.") && trimmed.length() > 7 {
    let key = text_slice(trimmed, 7, trimmed.length())
    let mut i = 0
    while i < key.length() {
      if not(is_matrix_ident_code(key.unsafe_get(i))) {
        return None
      }
      i += 1
    }
    Some(key)
  } else {
    None
  }
}

///|
fn substitute_matrix_refs_in_expr(
  expression : String,
  matrix_values : Map[String, String],
) -> String {
  let prefix = "matrix."
  let chunks : Array[String] = []
  let mut idx = 0
  while idx < expression.length() {
    match find_substring(expression, prefix, idx) {
      Some(pos) => {
        chunks.push(text_slice(expression, idx, pos))
        let key_start = pos + prefix.length()
        let mut key_end = key_start
        while key_end < expression.length() &&
              is_matrix_ident_code(expression.unsafe_get(key_end)) {
          key_end += 1
        }
        if key_end > key_start {
          let key = text_slice(expression, key_start, key_end)
          chunks.push(matrix_values.get(key).unwrap_or(""))
          idx = key_end
        } else {
          chunks.push(prefix)
          idx = key_start
        }
      }
      None => {
        chunks.push(text_slice(expression, idx, expression.length()))
        idx = expression.length()
      }
    }
  }
  chunks.join("")
}

///|
fn substitute_inputs_text(
  text : String,
  inputs : Map[String, String],
) -> String {
  let chunks : Array[String] = []
  let mut idx = 0
  while idx < text.length() {
    match find_substring(text, "${{", idx) {
      Some(open_idx) => {
        chunks.push(text_slice(text, idx, open_idx))
        match find_substring(text, "}}", open_idx + 3) {
          Some(close_idx) => {
            let expression = text_slice(text, open_idx + 3, close_idx)
            match input_expr_name(expression) {
              Some(name) => chunks.push(inputs.get(name).unwrap_or(""))
              None => chunks.push(text_slice(text, open_idx, close_idx + 2))
            }
            idx = close_idx + 2
          }
          None => {
            chunks.push(text_slice(text, open_idx, text.length()))
            idx = text.length()
          }
        }
      }
      None => {
        chunks.push(text_slice(text, idx, text.length()))
        idx = text.length()
      }
    }
  }
  chunks.join("")
}

///|
fn substitute_matrix_text(
  text : String,
  matrix_values : Map[String, String],
) -> String {
  let chunks : Array[String] = []
  let mut idx = 0
  while idx < text.length() {
    match find_substring(text, "${{", idx) {
      Some(open_idx) => {
        chunks.push(text_slice(text, idx, open_idx))
        match find_substring(text, "}}", open_idx + 3) {
          Some(close_idx) => {
            let expression = text_slice(text, open_idx + 3, close_idx)
            match matrix_expr_name(expression) {
              Some(name) =>
                // Entire expression is matrix.KEY — replace fully
                chunks.push(matrix_values.get(name).unwrap_or(""))
              None => {
                // Check if expression contains matrix.KEY references inline
                let substituted = substitute_matrix_refs_in_expr(
                  expression, matrix_values,
                )
                if substituted != expression {
                  let dollar = "$"
                  chunks.push(dollar + "{{" + substituted + "}}")
                } else {
                  chunks.push(text_slice(text, open_idx, close_idx + 2))
                }
              }
            }
            idx = close_idx + 2
          }
          None => {
            chunks.push(text_slice(text, open_idx, text.length()))
            idx = text.length()
          }
        }
      }
      None => {
        chunks.push(text_slice(text, idx, text.length()))
        idx = text.length()
      }
    }
  }
  chunks.join("")
}

///|
fn substitute_optional_inputs(
  value : String?,
  inputs : Map[String, String],
) -> String? {
  match value {
    Some(text) => Some(substitute_inputs_text(text, inputs))
    None => None
  }
}

///|
fn substitute_optional_matrix(
  value : String?,
  matrix_values : Map[String, String],
) -> String? {
  match value {
    Some(text) => Some(substitute_matrix_text(text, matrix_values))
    None => None
  }
}

///|
fn substitute_inputs_map(
  values : Map[String, String],
  inputs : Map[String, String],
) -> Map[String, String] {
  let result : Map[String, String] = {}
  for key, value in values {
    result[key] = substitute_inputs_text(value, inputs)
  }
  result
}

///|
fn substitute_matrix_map(
  values : Map[String, String],
  matrix_values : Map[String, String],
) -> Map[String, String] {
  let result : Map[String, String] = {}
  for key, value in values {
    result[key] = substitute_matrix_text(value, matrix_values)
  }
  result
}

///|
fn substitute_inputs_list(
  values : Array[String],
  inputs : Map[String, String],
) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    result.push(substitute_inputs_text(value, inputs))
  }
  result
}

///|
fn substitute_matrix_list(
  values : Array[String],
  matrix_values : Map[String, String],
) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    result.push(substitute_matrix_text(value, matrix_values))
  }
  result
}

///|
fn merge_run_defaults(base : RunDefaults, overlay : RunDefaults) -> RunDefaults {
  new_run_defaults(
    shell=match overlay.shell {
      Some(_) => overlay.shell
      None => base.shell
    },
    working_directory=match overlay.working_directory {
      Some(_) => overlay.working_directory
      None => base.working_directory
    },
  )
}

///|
fn reusable_job_id(caller_job_id : String, callee_job_id : String) -> String {
  caller_job_id + "__" + callee_job_id
}

///|
fn terminal_job_ids(jobs : Array[JobSpec]) -> Array[String] {
  let depended : Map[String, Bool] = {}
  for job in jobs {
    for need in job.needs {
      depended[need] = true
    }
  }
  let terminals : Array[String] = []
  for job in jobs {
    if depended.get(job.id) is None {
      terminals.push(job.id)
    }
  }
  terminals
}

///|
fn combine_if_conditions(outer : String, inner : String) -> String {
  if outer == "success()" {
    inner
  } else if inner == "success()" {
    outer
  } else {
    "(" + outer + ") && (" + inner + ")"
  }
}

///|
fn is_reusable_needs_ident_char(ch : UInt16) -> Bool {
  (ch >= 'a'.to_int().to_uint16() && ch <= 'z'.to_int().to_uint16()) ||
  (ch >= 'A'.to_int().to_uint16() && ch <= 'Z'.to_int().to_uint16()) ||
  (ch >= '0'.to_int().to_uint16() && ch <= '9'.to_int().to_uint16()) ||
  ch == '_'.to_int().to_uint16() ||
  ch == '-'.to_int().to_uint16()
}

///|
fn substitute_reusable_needs_text(
  text : String,
  replacements : Map[String, String],
) -> String {
  let chunks : Array[String] = []
  let mut idx = 0
  while idx < text.length() {
    match find_substring(text, "needs.", idx) {
      Some(need_idx) => {
        let start = need_idx + "needs.".length()
        let mut end = start
        while end < text.length() &&
              is_reusable_needs_ident_char(text.unsafe_get(end)) {
          end += 1
        }
        if end == start {
          chunks.push(text_slice(text, idx, need_idx + 1))
          idx = need_idx + 1
          continue
        }
        let name = text_slice(text, start, end)
        match replacements.get(name) {
          Some(replacement) => {
            chunks.push(text_slice(text, idx, need_idx))
            chunks.push("needs." + replacement)
            idx = end
          }
          None => {
            chunks.push(text_slice(text, idx, end))
            idx = end
          }
        }
      }
      None => {
        chunks.push(text_slice(text, idx, text.length()))
        idx = text.length()
      }
    }
  }
  chunks.join("")
}

///|
fn substitute_reusable_needs_optional(
  value : String?,
  replacements : Map[String, String],
) -> String? {
  match value {
    Some(text) => Some(substitute_reusable_needs_text(text, replacements))
    None => None
  }
}

///|
fn substitute_reusable_needs_map(
  values : Map[String, String],
  replacements : Map[String, String],
) -> Map[String, String] {
  let result : Map[String, String] = {}
  for key, value in values {
    result[key] = substitute_reusable_needs_text(value, replacements)
  }
  result
}

///|
fn substitute_reusable_needs_list(
  values : Array[String],
  replacements : Map[String, String],
) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    result.push(substitute_reusable_needs_text(value, replacements))
  }
  result
}

///|
fn secret_expr_name(expression : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  if trimmed.has_prefix("secrets.") && trimmed.length() > 8 {
    Some(text_slice(trimmed, 8, trimmed.length()))
  } else {
    None
  }
}

///|
fn substitute_secrets_text(
  text : String,
  secrets : Map[String, String],
) -> String {
  let chunks : Array[String] = []
  let mut idx = 0
  while idx < text.length() {
    match find_substring(text, "${{", idx) {
      Some(open_idx) => {
        chunks.push(text_slice(text, idx, open_idx))
        match find_substring(text, "}}", open_idx + 3) {
          Some(close_idx) => {
            let expression = text_slice(text, open_idx + 3, close_idx)
            match secret_expr_name(expression) {
              Some(name) => chunks.push(secrets.get(name).unwrap_or(""))
              None => chunks.push(text_slice(text, open_idx, close_idx + 2))
            }
            idx = close_idx + 2
          }
          None => {
            chunks.push(text_slice(text, open_idx, text.length()))
            idx = text.length()
          }
        }
      }
      None => {
        chunks.push(text_slice(text, idx, text.length()))
        idx = text.length()
      }
    }
  }
  chunks.join("")
}

///|
fn substitute_reusable_bindings_text(
  text : String,
  inputs : Map[String, String],
  secrets : Map[String, String],
) -> String {
  substitute_secrets_text(substitute_inputs_text(text, inputs), secrets)
}

///|
fn substitute_reusable_bindings_optional(
  value : String?,
  inputs : Map[String, String],
  secrets : Map[String, String],
) -> String? {
  match value {
    Some(text) => Some(substitute_reusable_bindings_text(text, inputs, secrets))
    None => None
  }
}

///|
fn substitute_reusable_bindings_map(
  values : Map[String, String],
  inputs : Map[String, String],
  secrets : Map[String, String],
) -> Map[String, String] {
  let result : Map[String, String] = {}
  for key, value in values {
    result[key] = substitute_reusable_bindings_text(value, inputs, secrets)
  }
  result
}

///|
fn substitute_reusable_bindings_list(
  values : Array[String],
  inputs : Map[String, String],
  secrets : Map[String, String],
) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    result.push(substitute_reusable_bindings_text(value, inputs, secrets))
  }
  result
}

///|
fn substitute_reusable_bindings_step(
  step : StepSpec,
  inputs : Map[String, String],
  secrets : Map[String, String],
) -> StepSpec {
  {
    id: step.id,
    name: substitute_reusable_bindings_text(step.name, inputs, secrets),
    run: substitute_reusable_bindings_optional(step.run, inputs, secrets),
    uses: substitute_reusable_bindings_optional(step.uses, inputs, secrets),
    shell: substitute_reusable_bindings_optional(step.shell, inputs, secrets),
    working_directory: substitute_reusable_bindings_optional(
      step.working_directory,
      inputs,
      secrets,
    ),
    env: substitute_reusable_bindings_map(step.env, inputs, secrets),
    with_values: substitute_reusable_bindings_map(
      step.with_values,
      inputs,
      secrets,
    ),
    if_condition: substitute_reusable_bindings_text(
      step.if_condition,
      inputs,
      secrets,
    ),
    continue_on_error: substitute_reusable_bindings_text(
      step.continue_on_error,
      inputs,
      secrets,
    ),
    timeout_minutes: step.timeout_minutes,
  }
}

///|
fn workflow_call_input_implicit_default(input_type : String) -> String {
  match input_type {
    "boolean" => "false"
    "number" => "0"
    _ => ""
  }
}

///|
fn workflow_call_input_is_dynamic(value : String) -> Bool {
  value.contains("${{")
}

///|
fn workflow_call_number_literal_is_valid(value : String) -> Bool {
  if value.length() == 0 {
    return false
  }
  let mut idx = 0
  let mut has_digit = false
  let mut has_dot = false
  if value.unsafe_get(0) == '-'.to_int().to_uint16() ||
    value.unsafe_get(0) == '+'.to_int().to_uint16() {
    idx = 1
  }
  if idx >= value.length() {
    return false
  }
  while idx < value.length() {
    let ch = value.unsafe_get(idx)
    if ch >= '0'.to_int().to_uint16() && ch <= '9'.to_int().to_uint16() {
      has_digit = true
      idx += 1
      continue
    }
    if ch == '.'.to_int().to_uint16() && not(has_dot) {
      has_dot = true
      idx += 1
      continue
    }
    return false
  }
  has_digit
}

///|
fn workflow_call_input_value_matches_type(
  value : String,
  input_type : String,
) -> Bool {
  if workflow_call_input_is_dynamic(value) {
    return true
  }
  let trimmed = value.trim(chars=" \t\r\n").to_string()
  match input_type {
    "boolean" => {
      let normalized = trimmed.to_lower()
      normalized == "true" || normalized == "false"
    }
    "number" => workflow_call_number_literal_is_valid(trimmed)
    _ => true
  }
}

///|
fn workflow_job_output_reference(
  text : String,
  replacements : Map[String, String],
) -> String {
  let chunks : Array[String] = []
  let mut idx = 0
  while idx < text.length() {
    match find_substring(text, "jobs.", idx) {
      Some(jobs_idx) => {
        let prefix = "jobs."
        let start = jobs_idx + prefix.length()
        let mut job_end = start
        while job_end < text.length() &&
              is_reusable_needs_ident_char(text.unsafe_get(job_end)) {
          job_end += 1
        }
        if job_end == start {
          chunks.push(text_slice(text, idx, jobs_idx + 1))
          idx = jobs_idx + 1
          continue
        }
        let job_id = text_slice(text, start, job_end)
        let suffix = ".outputs."
        if job_end + suffix.length() > text.length() ||
          text_slice(text, job_end, job_end + suffix.length()) != suffix {
          chunks.push(text_slice(text, idx, job_end))
          idx = job_end
          continue
        }
        let output_start = job_end + suffix.length()
        let mut output_end = output_start
        while output_end < text.length() &&
              is_reusable_needs_ident_char(text.unsafe_get(output_end)) {
          output_end += 1
        }
        if output_end == output_start {
          chunks.push(text_slice(text, idx, output_start))
          idx = output_start
          continue
        }
        chunks.push(text_slice(text, idx, jobs_idx))
        let actual_job = replacements.get(job_id).unwrap_or(job_id)
        chunks.push(
          "needs." +
          actual_job +
          ".outputs." +
          text_slice(text, output_start, output_end),
        )
        idx = output_end
      }
      None => {
        chunks.push(text_slice(text, idx, text.length()))
        idx = text.length()
      }
    }
  }
  chunks.join("")
}

///|
fn substitute_reusable_needs_step(
  step : StepSpec,
  replacements : Map[String, String],
) -> StepSpec {
  {
    id: step.id,
    name: substitute_reusable_needs_text(step.name, replacements),
    run: substitute_reusable_needs_optional(step.run, replacements),
    uses: substitute_reusable_needs_optional(step.uses, replacements),
    shell: substitute_reusable_needs_optional(step.shell, replacements),
    working_directory: substitute_reusable_needs_optional(
      step.working_directory,
      replacements,
    ),
    env: substitute_reusable_needs_map(step.env, replacements),
    with_values: substitute_reusable_needs_map(step.with_values, replacements),
    if_condition: substitute_reusable_needs_text(
      step.if_condition,
      replacements,
    ),
    continue_on_error: substitute_reusable_needs_text(
      step.continue_on_error,
      replacements,
    ),
    timeout_minutes: step.timeout_minutes,
  }
}

///|
fn substitute_matrix_step(
  step : StepSpec,
  matrix_values : Map[String, String],
) -> StepSpec {
  {
    id: step.id,
    name: substitute_matrix_text(step.name, matrix_values),
    run: substitute_optional_matrix(step.run, matrix_values),
    uses: substitute_optional_matrix(step.uses, matrix_values),
    shell: substitute_optional_matrix(step.shell, matrix_values),
    working_directory: substitute_optional_matrix(
      step.working_directory,
      matrix_values,
    ),
    env: substitute_matrix_map(step.env, matrix_values),
    with_values: substitute_matrix_map(step.with_values, matrix_values),
    if_condition: substitute_matrix_text(step.if_condition, matrix_values),
    continue_on_error: substitute_matrix_text(
      step.continue_on_error,
      matrix_values,
    ),
    timeout_minutes: step.timeout_minutes,
  }
}

///|
fn substitute_matrix_job(
  job : JobSpec,
  actual_id : String,
  actual_needs : Array[String],
  matrix_values : Map[String, String],
) -> JobSpec {
  let steps : Array[StepSpec] = []
  for step in job.steps {
    steps.push(substitute_matrix_step(step, matrix_values))
  }
  new_job(
    actual_id,
    steps,
    name=substitute_matrix_text(job.name, matrix_values),
    if_condition=substitute_matrix_text(job.if_condition, matrix_values),
    needs=actual_needs,
    outputs=substitute_matrix_map(job.outputs, matrix_values),
    permissions=job.permissions,
    concurrency=job.concurrency,
    runs_on=substitute_matrix_list(job.runs_on, matrix_values),
    env=substitute_matrix_map(job.env, matrix_values),
    defaults=new_run_defaults(
      shell=substitute_optional_matrix(job.defaults.shell, matrix_values),
      working_directory=substitute_optional_matrix(
        job.defaults.working_directory,
        matrix_values,
      ),
    ),
    matrix=None,
    reusable_workflow=substitute_optional_matrix(
      job.reusable_workflow,
      matrix_values,
    ),
    reusable_workflow_with=substitute_matrix_map(
      job.reusable_workflow_with,
      matrix_values,
    ),
    reusable_workflow_secrets=substitute_matrix_map(
      job.reusable_workflow_secrets,
      matrix_values,
    ),
    reusable_workflow_inherit_secrets=job.reusable_workflow_inherit_secrets,
    services=job.services,
    container=job.container,
    timeout_minutes=job.timeout_minutes,
  )
}

///|
fn matrix_job_id(logical_id : String, index : Int) -> String {
  logical_id + "__matrix_" + (index + 1).to_string()
}

///|
fn expanded_job_ids(jobs : Array[JobSpec]) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = {}
  for job in jobs {
    match job.matrix {
      Some(matrix) => {
        let ids : Array[String] = []
        let mut row_index = 0
        while row_index < matrix.rows.length() {
          ids.push(matrix_job_id(job.id, row_index))
          row_index += 1
        }
        result[job.id] = ids
      }
      None => result[job.id] = [job.id]
    }
  }
  result
}

///|
fn resolve_job_targets(
  job_ids : Map[String, Array[String]],
  id : String,
) -> Array[String] {
  match job_ids.get(id) {
    Some(targets) =>
      if targets.length() == 1 && targets[0] == id {
        [id]
      } else {
        let resolved : Array[String] = []
        let seen : Map[String, Bool] = {}
        for target in targets {
          for actual in resolve_job_targets(job_ids, target) {
            if seen.get(actual) is None {
              seen[actual] = true
              resolved.push(actual)
            }
          }
        }
        resolved
      }
    None => [id]
  }
}

///|
fn expand_matrix_jobs(
  jobs : Array[JobSpec],
  aliases? : Map[String, Array[String]] = {},
) -> Array[ExpandedJob] {
  let expanded : Array[ExpandedJob] = []
  let job_ids = expanded_job_ids(jobs)
  for logical_id, targets in aliases {
    job_ids[logical_id] = targets
  }
  for job in jobs {
    match job.matrix {
      Some(matrix) => {
        let limit = matrix.max_parallel.unwrap_or(matrix.rows.length())
        let mut row_index = 0
        for row in matrix.rows {
          let actual_needs : Array[String] = []
          let need_targets : Map[String, Array[String]] = {}
          for need in job.needs {
            let targets = resolve_job_targets(job_ids, need)
            let target_ids : Array[String] = []
            for target in targets {
              actual_needs.push(target)
              target_ids.push(target)
            }
            need_targets[need] = target_ids
          }
          if row_index >= limit {
            actual_needs.push(matrix_job_id(job.id, row_index - limit))
          }
          expanded.push({
            job: substitute_matrix_job(
              job,
              matrix_job_id(job.id, row_index),
              actual_needs,
              row,
            ),
            visible_needs: job.needs,
            need_targets,
            matrix_group: Some(job.id),
            matrix_fail_fast: matrix.fail_fast,
          })
          row_index += 1
        }
      }
      None => {
        let actual_needs : Array[String] = []
        let need_targets : Map[String, Array[String]] = {}
        for need in job.needs {
          let targets = resolve_job_targets(job_ids, need)
          let target_ids : Array[String] = []
          for target in targets {
            actual_needs.push(target)
            target_ids.push(target)
          }
          need_targets[need] = target_ids
        }
        expanded.push({
          job: new_job(
            job.id,
            job.steps,
            name=job.name,
            if_condition=job.if_condition,
            needs=actual_needs,
            outputs=job.outputs,
            permissions=job.permissions,
            concurrency=job.concurrency,
            runs_on=job.runs_on,
            env=job.env,
            defaults=job.defaults,
            matrix=None,
            reusable_workflow=job.reusable_workflow,
            reusable_workflow_with=job.reusable_workflow_with,
            reusable_workflow_secrets=job.reusable_workflow_secrets,
            reusable_workflow_inherit_secrets=job.reusable_workflow_inherit_secrets,
            services=job.services,
            container=job.container,
          ),
          visible_needs: job.needs,
          need_targets,
          matrix_group: None,
          matrix_fail_fast: false,
        })
      }
    }
  }
  expanded
}

///|
fn read_text(path : String) -> String? {
  try @xfs.read_file_to_string(path) catch {
    _ => None
  } noraise {
    content => Some(content)
  }
}

///|
priv struct ReusableWorkflowExpansion {
  jobs : Array[JobSpec]
  aliases : Map[String, Array[String]]
  alias_outputs : Map[String, Map[String, String]]
  alias_output_targets : Map[String, Map[String, Array[String]]]
}

///|
priv struct ReusableWorkflowSource {
  workflow_path : String
  source_root : String
}

///|
fn remote_reusable_workflow_ref(path : String) -> ActionRef? {
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
fn lowering_leaf_name(path : String) -> String {
  let mut last_slash = -1
  let mut idx = 0
  while idx < path.length() {
    if path.unsafe_get(idx) == '/' {
      last_slash = idx
    }
    idx += 1
  }
  if last_slash < 0 {
    path
  } else {
    exec_text_slice(path, last_slash + 1, path.length())
  }
}

///|
fn reusable_workflow_source(
  path : String,
  workspace_root : String,
) -> ReusableWorkflowSource? {
  if path.has_prefix("./") {
    let normalized = normalize_local_action_path(path)
    let resolved_path = join_path(workspace_root, normalized)
    // Primary: workspace_root + path (GitHub Actions spec)
    if @xfs.path_exists(resolved_path) {
      return Some({ workflow_path: resolved_path, source_root: workspace_root })
    }
    // Fallback: try just the filename in workspace_root
    // Handles cases where workflow is outside .github/workflows/
    // (e.g. examples/ directory with co-located callee)
    let fallback_path = join_path(
      workspace_root,
      lowering_leaf_name(normalized),
    )
    if @xfs.path_exists(fallback_path) {
      return Some({ workflow_path: fallback_path, source_root: workspace_root })
    }
    // Return primary path (will fail at read_text with clear error)
    return Some({ workflow_path: resolved_path, source_root: workspace_root })
  }
  guard remote_reusable_workflow_ref(path) is Some(action_ref) else {
    return None
  }
  guard cached_github_repo_path(action_ref) is Some(workflow_path) else {
    return None
  }
  Some({
    workflow_path,
    source_root: cached_github_repo_root(action_ref).unwrap_or(workspace_root),
  })
}

///|
fn expanded_row_jobs_for_reusable_caller(job : JobSpec) -> Array[JobSpec] {
  let rows : Array[JobSpec] = []
  for expanded in expand_matrix_jobs([job]) {
    rows.push(expanded.job)
  }
  rows
}

///|
fn expand_reusable_workflows_in_workspace(
  jobs : Array[JobSpec],
  workspace_root : String,
  execution_root : String,
  errors : Array[String],
) -> ReusableWorkflowExpansion {
  let expanded : Array[JobSpec] = []
  let aliases : Map[String, Array[String]] = {}
  let alias_outputs : Map[String, Map[String, String]] = {}
  let alias_output_targets : Map[String, Map[String, Array[String]]] = {}
  for job in jobs {
    match job.reusable_workflow {
      Some(path) => {
        let before_errors = errors.length()
        if workspace_root.length() == 0 {
          errors.push(
            "job '\{job.id}' reusable workflow '\{path}' requires workspace-aware lowering",
          )
          continue
        }
        if job.steps.length() > 0 {
          errors.push(
            "job '\{job.id}' reusable workflow caller steps are not supported in MVP",
          )
        }
        if job.outputs.length() > 0 {
          errors.push(
            "job '\{job.id}' reusable workflow caller outputs are not supported in MVP",
          )
        }
        // permissions and concurrency silently ignored for local execution
        ignore(job.permissions)
        ignore(job.concurrency)
        if job.container_image is Some(image) {
          errors.push(
            "job '\{job.id}' reusable workflow container is not supported in MVP: \{image}",
          )
        }
        if errors.length() > before_errors {
          continue
        }
        match reusable_workflow_source(path, workspace_root) {
          Some(source) =>
            match read_text(source.workflow_path) {
              Some(text) => {
                let parsed = parse_workflow_yaml(text)
                for err in parsed.errors {
                  errors.push(
                    "job '\{job.id}' reusable workflow '\{path}' parse error: " +
                    err,
                  )
                }
                guard parsed.workflow is Some(callee) else { continue }
                if not(callee.workflow_call) {
                  errors.push(
                    "job '\{job.id}' reusable workflow '\{path}' must use on: workflow_call",
                  )
                  continue
                }
                let workflow_call = callee.workflow_call_spec.unwrap_or(
                  new_workflow_call_spec(),
                )
                let bound_inputs : Map[String, String] = {}
                for input_name, input_spec in workflow_call.inputs {
                  let bound_value = match
                    job.reusable_workflow_with.get(input_name) {
                    Some(value) => Some(value)
                    None =>
                      match input_spec.default_value {
                        Some(value) => Some(value)
                        None =>
                          if input_spec.required {
                            errors.push(
                              "job '\{job.id}' reusable workflow missing required input '\{input_name}': \{path}",
                            )
                            None
                          } else {
                            Some(
                              workflow_call_input_implicit_default(
                                input_spec.input_type,
                              ),
                            )
                          }
                      }
                  }
                  match bound_value {
                    Some(value) =>
                      if workflow_call_input_value_matches_type(
                          value,
                          input_spec.input_type,
                        ) {
                        bound_inputs[input_name] = value
                      } else {
                        errors.push(
                          "job '\{job.id}' reusable workflow input '\{input_name}' expects \{input_spec.input_type} but got '\{value}': \{path}",
                        )
                      }
                    None => ()
                  }
                }
                for input_name, _ in job.reusable_workflow_with {
                  if workflow_call.inputs.get(input_name) is None {
                    errors.push(
                      "job '\{job.id}' reusable workflow unknown input '\{input_name}': \{path}",
                    )
                  }
                }
                let bound_secrets : Map[String, String] = {}
                for secret_name, secret_spec in workflow_call.secrets {
                  if job.reusable_workflow_inherit_secrets {
                    let dollar = "$"
                    bound_secrets[secret_name] = dollar +
                      "{{ secrets." +
                      secret_name +
                      " }}"
                  }
                  match job.reusable_workflow_secrets.get(secret_name) {
                    Some(value) => bound_secrets[secret_name] = value
                    None =>
                      if secret_spec.required &&
                        bound_secrets.get(secret_name) is None {
                        errors.push(
                          "job '\{job.id}' reusable workflow missing required secret '\{secret_name}': \{path}",
                        )
                      }
                  }
                }
                for secret_name, _ in job.reusable_workflow_secrets {
                  if workflow_call.secrets.get(secret_name) is None {
                    errors.push(
                      "job '\{job.id}' reusable workflow unknown secret '\{secret_name}': \{path}",
                    )
                  }
                }
                // permissions and concurrency silently ignored
                ignore(callee.permissions)
                ignore(callee.concurrency)
                let callee_ids : Map[String, String] = {}
                for callee_job in callee.jobs {
                  callee_ids[callee_job.id] = reusable_job_id(
                    job.id,
                    callee_job.id,
                  )
                }
                if errors.length() > before_errors {
                  continue
                }
                match job.matrix {
                  Some(_) => {
                    let row_ids : Array[String] = []
                    for row_job in expanded_row_jobs_for_reusable_caller(job) {
                      row_ids.push(row_job.id)
                      let nested = expand_reusable_workflows_in_workspace(
                        [row_job],
                        workspace_root,
                        execution_root,
                        errors,
                      )
                      if errors.length() > before_errors {
                        break
                      }
                      for nested_job in nested.jobs {
                        expanded.push(nested_job)
                      }
                      for alias_id, targets in nested.aliases {
                        aliases[alias_id] = targets
                      }
                      for alias_id, outputs in nested.alias_outputs {
                        alias_outputs[alias_id] = outputs
                      }
                      for alias_id, targets in nested.alias_output_targets {
                        alias_output_targets[alias_id] = targets
                      }
                    }
                    if errors.length() > before_errors {
                      continue
                    }
                    aliases[job.id] = row_ids
                    if workflow_call.outputs.length() > 0 {
                      let workflow_output_targets : Map[String, Array[String]] = {}
                      for output_name, _ in workflow_call.outputs {
                        workflow_output_targets[output_name] = row_ids
                      }
                      alias_output_targets[job.id] = workflow_output_targets
                    }
                    continue
                  }
                  None => ()
                }
                let transformed_jobs : Array[JobSpec] = []
                for callee_job in callee.jobs {
                  let steps : Array[StepSpec] = []
                  for step in callee_job.steps {
                    let substituted_step = rewrite_reusable_step_local_uses(
                      substitute_reusable_needs_step(
                        substitute_reusable_bindings_step(
                          step, bound_inputs, bound_secrets,
                        ),
                        callee_ids,
                      ),
                      source.source_root,
                      execution_root,
                    )
                    steps.push(substituted_step)
                  }
                  let actual_needs : Array[String] = []
                  if callee_job.needs.length() == 0 {
                    for need in job.needs {
                      actual_needs.push(need)
                    }
                  } else {
                    for need in callee_job.needs {
                      actual_needs.push(callee_ids.get(need).unwrap_or(need))
                    }
                  }
                  transformed_jobs.push(
                    new_job(
                      callee_ids.get(callee_job.id).unwrap_or(callee_job.id),
                      steps,
                      name=substitute_reusable_bindings_text(
                        callee_job.name,
                        bound_inputs,
                        bound_secrets,
                      ),
                      if_condition=combine_if_conditions(
                        job.if_condition,
                        substitute_reusable_needs_text(
                          substitute_reusable_bindings_text(
                            callee_job.if_condition,
                            bound_inputs,
                            bound_secrets,
                          ),
                          callee_ids,
                        ),
                      ),
                      needs=actual_needs,
                      outputs=substitute_reusable_needs_map(
                        substitute_reusable_bindings_map(
                          callee_job.outputs,
                          bound_inputs,
                          bound_secrets,
                        ),
                        callee_ids,
                      ),
                      permissions=callee_job.permissions,
                      concurrency=callee_job.concurrency,
                      runs_on=substitute_reusable_needs_list(
                        substitute_reusable_bindings_list(
                          callee_job.runs_on,
                          bound_inputs,
                          bound_secrets,
                        ),
                        callee_ids,
                      ),
                      env=substitute_reusable_needs_map(
                        substitute_reusable_bindings_map(
                          merge_env(callee.env, callee_job.env),
                          bound_inputs,
                          bound_secrets,
                        ),
                        callee_ids,
                      ),
                      defaults=merge_run_defaults(
                        new_run_defaults(
                          shell=substitute_reusable_bindings_optional(
                            callee.defaults.shell,
                            bound_inputs,
                            bound_secrets,
                          ),
                          working_directory=substitute_reusable_bindings_optional(
                            callee.defaults.working_directory,
                            bound_inputs,
                            bound_secrets,
                          ),
                        ),
                        new_run_defaults(
                          shell=substitute_reusable_needs_optional(
                            substitute_reusable_bindings_optional(
                              callee_job.defaults.shell,
                              bound_inputs,
                              bound_secrets,
                            ),
                            callee_ids,
                          ),
                          working_directory=substitute_reusable_needs_optional(
                            substitute_reusable_bindings_optional(
                              callee_job.defaults.working_directory,
                              bound_inputs,
                              bound_secrets,
                            ),
                            callee_ids,
                          ),
                        ),
                      ),
                      matrix=callee_job.matrix,
                      reusable_workflow=substitute_reusable_bindings_optional(
                        callee_job.reusable_workflow,
                        bound_inputs,
                        bound_secrets,
                      ),
                      reusable_workflow_with=substitute_reusable_bindings_map(
                        callee_job.reusable_workflow_with,
                        bound_inputs,
                        bound_secrets,
                      ),
                      reusable_workflow_secrets=substitute_reusable_bindings_map(
                        callee_job.reusable_workflow_secrets,
                        bound_inputs,
                        bound_secrets,
                      ),
                      reusable_workflow_inherit_secrets=callee_job.reusable_workflow_inherit_secrets,
                      services=callee_job.services,
                      container=callee_job.container,
                    ),
                  )
                }
                if errors.length() > before_errors {
                  continue
                }
                let nested = expand_reusable_workflows_in_workspace(
                  transformed_jobs,
                  source.source_root,
                  execution_root,
                  errors,
                )
                if errors.length() > before_errors {
                  continue
                }
                for nested_job in nested.jobs {
                  expanded.push(nested_job)
                }
                for alias_id, targets in nested.aliases {
                  aliases[alias_id] = targets
                }
                for alias_id, outputs in nested.alias_outputs {
                  alias_outputs[alias_id] = outputs
                }
                for alias_id, targets in nested.alias_output_targets {
                  alias_output_targets[alias_id] = targets
                }
                let terminals : Array[String] = []
                let seen_terminals : Map[String, Bool] = {}
                for terminal_id in terminal_job_ids(callee.jobs) {
                  let namespaced = callee_ids
                    .get(terminal_id)
                    .unwrap_or(terminal_id)
                  let targets = nested.aliases
                    .get(namespaced)
                    .unwrap_or([namespaced])
                  for target in targets {
                    if seen_terminals.get(target) is None {
                      seen_terminals[target] = true
                      terminals.push(target)
                    }
                  }
                }
                aliases[job.id] = terminals
                let workflow_outputs : Map[String, String] = {}
                for output_name, output_spec in workflow_call.outputs {
                  workflow_outputs[output_name] = workflow_job_output_reference(
                    substitute_reusable_bindings_text(
                      output_spec.value,
                      bound_inputs,
                      bound_secrets,
                    ),
                    callee_ids,
                  )
                }
                alias_outputs[job.id] = workflow_outputs
              }
              None =>
                errors.push(
                  "job '\{job.id}' reusable workflow '\{path}' is missing or not cached",
                )
            }
          None =>
            errors.push(
              "job '\{job.id}' reusable workflow is not supported in MVP: \{path}",
            )
        }
      }
      None => expanded.push(job)
    }
  }
  { jobs: expanded, aliases, alias_outputs, alias_output_targets }
}

///|
fn task_needs(job : JobSpec, previous_task_id : String) -> Array[String] {
  let needs : Array[String] = []
  if previous_task_id.length() > 0 {
    needs.push(previous_task_id)
  } else {
    for need in job.needs {
      needs.push(finish_task_id(need))
    }
  }
  needs
}

///|
fn step_name(step : StepSpec, resolved_step_id : String) -> String {
  if step.name.length() > 0 {
    step.name
  } else {
    resolved_step_id
  }
}

///|
fn validate_step_if(
  job_id : String,
  step_id : String,
  if_condition : String,
  errors : Array[String],
) -> Unit {
  if not(if_condition_supported(if_condition)) {
    errors.push(
      "step '\{job_id}/\{step_id}' if='\{if_condition}' is not supported in MVP",
    )
  }
}

///|
fn validate_job_if(
  job_id : String,
  if_condition : String,
  errors : Array[String],
) -> Unit {
  if not(if_condition_supported(if_condition)) {
    errors.push("job '\{job_id}' if='\{if_condition}' is not supported in MVP")
  }
}

///|
fn validate_continue_on_error(
  job_id : String,
  step_id : String,
  continue_on_error : String,
  errors : Array[String],
) -> Unit {
  if not(if_condition_supported(continue_on_error)) {
    errors.push(
      "step '\{job_id}/\{step_id}' continue-on-error='\{continue_on_error}' is not supported in MVP",
    )
  }
}

///|
fn append_run_task(
  tasks : Array[@wf.FlowTask],
  task_plans : Array[TaskPlan],
  job : JobSpec,
  task_id : String,
  step_id : String,
  name : String,
  script : String,
  needs : Array[String],
  shell : String,
  working_directory : String,
  if_condition : String,
  continue_on_error : String,
  env : Map[String, String],
  action_scope? : String? = None,
  timeout_minutes? : Int = 0,
) -> Unit {
  tasks.push(
    @wf.new_task(task_id, job.id, script, needs, env~, cwd=working_directory),
  )
  task_plans.push(
    new_task_plan(
      task_id,
      "run",
      job.id,
      step_id,
      name,
      script,
      shell,
      working_directory,
      if_condition,
      job.runs_on,
      env,
      continue_on_error~,
      action_scope~,
      timeout_minutes~,
    ),
  )
}

///|
fn append_action_task(
  tasks : Array[@wf.FlowTask],
  task_plans : Array[TaskPlan],
  job : JobSpec,
  task_id : String,
  step_id : String,
  name : String,
  needs : Array[String],
  shell : String,
  working_directory : String,
  if_condition : String,
  continue_on_error : String,
  env : Map[String, String],
  action : ResolvedAction,
  action_scope? : String? = None,
  requires_action_started? : Bool = false,
  timeout_minutes? : Int = 0,
) -> Unit {
  tasks.push(
    @wf.new_task(task_id, job.id, "__actrun_" + action.kind + "__", needs, env~),
  )
  task_plans.push(
    new_task_plan(
      task_id,
      "action",
      job.id,
      step_id,
      name,
      "",
      shell,
      working_directory,
      if_condition,
      job.runs_on,
      env,
      continue_on_error~,
      action=Some(action),
      action_scope~,
      requires_action_started~,
      timeout_minutes~,
    ),
  )
}

///|
priv struct DeferredActionTask {
  task_id : String
  step_id : String
  name : String
  shell : String
  working_directory : String
  if_condition : String
  continue_on_error : String
  env : Map[String, String]
  action : ResolvedAction
  action_scope : String?
  requires_action_started : Bool
}

///|
fn append_deferred_action_tasks(
  tasks : Array[@wf.FlowTask],
  task_plans : Array[TaskPlan],
  job : JobSpec,
  deferred_tasks : Array[DeferredActionTask],
  previous_task_id : String,
) -> String {
  let mut next_previous_task_id = previous_task_id
  let mut idx = deferred_tasks.length()
  while idx > 0 {
    idx -= 1
    let deferred = deferred_tasks[idx]
    append_action_task(
      tasks,
      task_plans,
      job,
      deferred.task_id,
      deferred.step_id,
      deferred.name,
      task_needs(job, next_previous_task_id),
      deferred.shell,
      deferred.working_directory,
      deferred.if_condition,
      deferred.continue_on_error,
      deferred.env,
      deferred.action,
      action_scope=deferred.action_scope,
      requires_action_started=deferred.requires_action_started,
    )
    next_previous_task_id = deferred.task_id
  }
  next_previous_task_id
}

///|
fn action_input_env_name(name : String) -> String {
  // @actions/core getInput replaces spaces with _ but keeps hyphens
  "INPUT_" + name.replace_all(old=" ", new="_").to_upper()
}

///|
fn action_input_env_name_underscore(name : String) -> String {
  // Actrun builtin actions use underscore form (INPUT_FETCH_DEPTH)
  "INPUT_" +
  name.replace_all(old="-", new="_").replace_all(old=" ", new="_").to_upper()
}

///|
fn action_input_env(
  defaults : Map[String, String],
  overrides : Map[String, String],
) -> Map[String, String] {
  let env : Map[String, String] = {}
  for key, value in merge_env(defaults, overrides) {
    // Resolve unresolved ${{ }} expressions in action.yml defaults
    // github.token is resolved later in executor; keep it as-is
    // Boolean-like expressions (== comparisons) default to "false"
    // Other unresolved expressions default to empty string
    let resolved_value = if value.contains("${{") {
      if value.contains("github.token") {
        value
      } else if value.contains("==") {
        "false"
      } else {
        ""
      }
    } else {
      value
    }
    let hyphen_name = action_input_env_name(key)
    env[hyphen_name] = resolved_value
    // Also set underscore form for builtin action compatibility
    let underscore_name = action_input_env_name_underscore(key)
    if hyphen_name != underscore_name {
      env[underscore_name] = resolved_value
    }
  }
  env
}

///|
fn github_action_context_env(action_ref : ActionRef) -> Map[String, String] {
  let env : Map[String, String] = {}
  match action_ref {
    GitHubRepo(owner, repo, version, _) => {
      env["GITHUB_ACTION_REPOSITORY"] = owner + "/" + repo
      if version.length() > 0 {
        env["GITHUB_ACTION_REF"] = version
      }
    }
    _ => ()
  }
  env
}

///|
fn lower_builtin_action(
  job : JobSpec,
  step : StepSpec,
  resolved_step_id : String,
  previous_task_id : String,
  shell : String,
  working_directory : String,
  env : Map[String, String],
  action_ref : ActionRef,
  action : ResolvedAction,
  tasks : Array[@wf.FlowTask],
  task_plans : Array[TaskPlan],
  deferred_post_tasks : Array[DeferredActionTask],
) -> String {
  let task_id = step_task_id(job.id, resolved_step_id)
  let needs = task_needs(job, previous_task_id)
  let setup_node_cache = step.with_values
    .get("cache")
    .unwrap_or("")
    .trim(chars=" \t\r\n")
    .length() >
    0
  if action.kind == "cache" || (action.kind == "setup-node" && setup_node_cache) {
    let action_scope = task_id
    append_action_task(
      tasks,
      task_plans,
      job,
      task_id,
      resolved_step_id,
      step_name(step, resolved_step_id),
      needs,
      shell,
      working_directory,
      step.if_condition,
      step.continue_on_error,
      env,
      action,
      action_scope=Some(action_scope),
    )
    deferred_post_tasks.push({
      task_id: step_task_id(job.id, lifecycle_step_id(resolved_step_id, "post")),
      step_id: lifecycle_step_id(resolved_step_id, "post"),
      name: step_name(step, resolved_step_id) + " / post",
      shell,
      working_directory,
      if_condition: "success()",
      continue_on_error: "false",
      env,
      action: {
        uses: action.uses,
        action_ref,
        kind: if action.kind == "setup-node" {
          "setup-node-cache-post"
        } else {
          "cache-save-post"
        },
        backend: "builtin",
        capabilities: backend_capabilities_for("builtin"),
        action_path: None,
        entrypoint: None,
        image: None,
        args: [],
      },
      action_scope: Some(action_scope),
      requires_action_started: true,
    })
    return task_id
  }
  append_action_task(
    tasks,
    task_plans,
    job,
    task_id,
    resolved_step_id,
    step_name(step, resolved_step_id),
    needs,
    shell,
    working_directory,
    step.if_condition,
    step.continue_on_error,
    env,
    action,
  )
  task_id
}

///|
fn lower_manifest_backed_action(
  workflow : WorkflowSpec,
  job : JobSpec,
  base_env : Map[String, String],
  step : StepSpec,
  resolved_step_id : String,
  previous_task_id : String,
  action_ref : ActionRef,
  cached_root : String,
  workspace_root : String,
  tasks : Array[@wf.FlowTask],
  task_plans : Array[TaskPlan],
  deferred_post_tasks : Array[DeferredActionTask],
  errors : Array[String],
  composite_output_mappings? : Map[String, Map[String, String]] = {},
) -> String {
  guard find_local_action_manifest(workspace_root, cached_root)
    is Some((_, manifest_text)) else {
    errors.push(
      "step '\{job.id}/\{resolved_step_id}' action '\{action_ref_text(action_ref)}' is missing action.yml or action.yaml",
    )
    return previous_task_id
  }
  let parsed_manifest = parse_action_manifest_yaml(manifest_text)
  guard parsed_manifest.action is Some(action_manifest) else {
    for err in parsed_manifest.errors {
      errors.push(
        "step '\{job.id}/\{resolved_step_id}' action '\{action_ref_text(action_ref)}' " +
        err,
      )
    }
    return previous_task_id
  }
  let action_context_env = github_action_context_env(action_ref)
  if action_manifest.runtime == "composite" {
    return lower_local_action(
      workflow,
      job,
      base_env,
      step,
      resolved_step_id,
      previous_task_id,
      cached_root,
      workspace_root,
      tasks,
      task_plans,
      deferred_post_tasks,
      errors,
      action_context_env~,
      composite_output_mappings~,
    )
  }
  if action_manifest.runtime.has_prefix("node") {
    let action_scope = step_task_id(job.id, resolved_step_id)
    let task_id = step_task_id(job.id, resolved_step_id)
    let shell = resolve_string(
      workflow.defaults.shell,
      job.defaults.shell,
      step.shell,
      "bash",
    )
    let working_directory = resolve_string(
      workflow.defaults.working_directory,
      job.defaults.working_directory,
      step.working_directory,
      "",
    )
    let step_env = merge_env(base_env, step.env)
    let node_env = merge_env(
      merge_env(
        step_env,
        action_input_env(action_manifest.inputs, step.with_values),
      ),
      merge_env(action_context_env, { "GITHUB_ACTION_PATH": cached_root }),
    )
    let action_name = step_name(step, resolved_step_id)
    let pre_if_condition = if action_manifest.pre_if == "always()" {
      step.if_condition
    } else {
      "success()"
    }
    let mut local_previous_task_id = previous_task_id
    match action_manifest.pre {
      Some(pre) if pre.length() > 0 => {
        let pre_step_id = lifecycle_step_id(resolved_step_id, "pre")
        let pre_task_id = step_task_id(job.id, pre_step_id)
        append_action_task(
          tasks,
          task_plans,
          job,
          pre_task_id,
          pre_step_id,
          action_name + " / pre",
          task_needs(job, local_previous_task_id),
          shell,
          working_directory,
          pre_if_condition,
          "false",
          node_env,
          {
            uses: action_ref_text(action_ref),
            action_ref,
            kind: "node-script",
            backend: "node",
            capabilities: backend_capabilities_for("node"),
            action_path: Some(cached_root),
            entrypoint: Some(join_path(cached_root, pre)),
            image: None,
            args: [],
          },
          action_scope=Some(action_scope),
        )
        local_previous_task_id = pre_task_id
      }
      _ => ()
    }
    append_action_task(
      tasks,
      task_plans,
      job,
      task_id,
      resolved_step_id,
      step_name(step, resolved_step_id),
      task_needs(job, local_previous_task_id),
      shell,
      working_directory,
      step.if_condition,
      step.continue_on_error,
      node_env,
      {
        uses: action_ref_text(action_ref),
        action_ref,
        kind: "node-script",
        backend: "node",
        capabilities: backend_capabilities_for("node"),
        action_path: Some(cached_root),
        entrypoint: Some(join_path(cached_root, action_manifest.main)),
        image: None,
        args: [],
      },
      action_scope=Some(action_scope),
    )
    match action_manifest.post {
      Some(post) if post.length() > 0 =>
        deferred_post_tasks.push({
          task_id: step_task_id(
            job.id,
            lifecycle_step_id(resolved_step_id, "post"),
          ),
          step_id: lifecycle_step_id(resolved_step_id, "post"),
          name: action_name + " / post",
          shell,
          working_directory,
          if_condition: action_manifest.post_if,
          continue_on_error: "false",
          env: node_env,
          action: {
            uses: action_ref_text(action_ref),
            action_ref,
            kind: "node-script",
            backend: "node",
            capabilities: backend_capabilities_for("node"),
            action_path: Some(cached_root),
            entrypoint: Some(join_path(cached_root, post)),
            image: None,
            args: [],
          },
          action_scope: Some(action_scope),
          requires_action_started: true,
        })
      _ => ()
    }
    return task_id
  }
  if action_manifest.runtime == "docker" {
    let action_scope = step_task_id(job.id, resolved_step_id)
    let task_id = step_task_id(job.id, resolved_step_id)
    let shell = resolve_string(
      workflow.defaults.shell,
      job.defaults.shell,
      step.shell,
      "bash",
    )
    let working_directory = resolve_string(
      workflow.defaults.working_directory,
      job.defaults.working_directory,
      step.working_directory,
      "",
    )
    let resolved_inputs = merge_env(action_manifest.inputs, step.with_values)
    let step_env = merge_env(base_env, step.env)
    let docker_env = merge_env(
      step_env,
      merge_env(
        action_input_env(action_manifest.inputs, step.with_values),
        action_context_env,
      ),
    )
    let args = substitute_inputs_list(action_manifest.args, resolved_inputs)
    let resolved_image = substitute_inputs_text(
      action_manifest.image,
      resolved_inputs,
    )
    let image = if resolved_image.has_prefix("docker://") {
      text_slice(resolved_image, 9, resolved_image.length())
    } else {
      join_path(cached_root, resolved_image)
    }
    let action_name = step_name(step, resolved_step_id)
    let pre_if_condition = if action_manifest.pre_if == "always()" {
      step.if_condition
    } else {
      "success()"
    }
    let mut local_previous_task_id = previous_task_id
    match
      substitute_optional_inputs(
        action_manifest.pre_entrypoint,
        resolved_inputs,
      ) {
      Some(pre_entrypoint) if pre_entrypoint.length() > 0 => {
        let pre_step_id = lifecycle_step_id(resolved_step_id, "pre")
        let pre_task_id = step_task_id(job.id, pre_step_id)
        append_action_task(
          tasks,
          task_plans,
          job,
          pre_task_id,
          pre_step_id,
          action_name + " / pre",
          task_needs(job, local_previous_task_id),
          shell,
          working_directory,
          pre_if_condition,
          "false",
          docker_env,
          {
            uses: action_ref_text(action_ref),
            action_ref,
            kind: "docker-action",
            backend: "docker",
            capabilities: backend_capabilities_for("docker"),
            action_path: Some(cached_root),
            entrypoint: Some(pre_entrypoint),
            image: Some(image),
            args,
          },
          action_scope=Some(action_scope),
        )
        local_previous_task_id = pre_task_id
      }
      _ => ()
    }
    append_action_task(
      tasks,
      task_plans,
      job,
      task_id,
      resolved_step_id,
      step_name(step, resolved_step_id),
      task_needs(job, local_previous_task_id),
      shell,
      working_directory,
      step.if_condition,
      step.continue_on_error,
      docker_env,
      {
        uses: action_ref_text(action_ref),
        action_ref,
        kind: "docker-action",
        backend: "docker",
        capabilities: backend_capabilities_for("docker"),
        action_path: Some(cached_root),
        entrypoint: substitute_optional_inputs(
          action_manifest.entrypoint,
          resolved_inputs,
        ),
        image: Some(image),
        args,
      },
      action_scope=Some(action_scope),
    )
    match
      substitute_optional_inputs(
        action_manifest.post_entrypoint,
        resolved_inputs,
      ) {
      Some(post_entrypoint) if post_entrypoint.length() > 0 =>
        deferred_post_tasks.push({
          task_id: step_task_id(
            job.id,
            lifecycle_step_id(resolved_step_id, "post"),
          ),
          step_id: lifecycle_step_id(resolved_step_id, "post"),
          name: action_name + " / post",
          shell,
          working_directory,
          if_condition: action_manifest.post_if,
          continue_on_error: "false",
          env: docker_env,
          action: {
            uses: action_ref_text(action_ref),
            action_ref,
            kind: "docker-action",
            backend: "docker",
            capabilities: backend_capabilities_for("docker"),
            action_path: Some(cached_root),
            entrypoint: Some(post_entrypoint),
            image: Some(image),
            args,
          },
          action_scope: Some(action_scope),
          requires_action_started: true,
        })
      _ => ()
    }
    return task_id
  }
  errors.push(
    "step '\{job.id}/\{resolved_step_id}' action '\{action_ref_text(action_ref)}' using='\{action_manifest.runtime}' is not supported in MVP",
  )
  previous_task_id
}

///|
fn find_local_action_manifest(
  workspace_root : String,
  action_path : String,
) -> (String, String)? {
  let action_root = join_path(
    workspace_root,
    normalize_local_action_path(action_path),
  )
  let yml_path = join_path(action_root, "action.yml")
  match read_text(yml_path) {
    Some(text) => Some((yml_path, text))
    None => {
      let yaml_path = join_path(action_root, "action.yaml")
      match read_text(yaml_path) {
        Some(text) => Some((yaml_path, text))
        None => None
      }
    }
  }
}

///|
fn lower_local_action(
  workflow : WorkflowSpec,
  job : JobSpec,
  job_env : Map[String, String],
  outer_step : StepSpec,
  outer_step_id : String,
  previous_task_id : String,
  action_path : String,
  workspace_root : String,
  tasks : Array[@wf.FlowTask],
  task_plans : Array[TaskPlan],
  deferred_post_tasks : Array[DeferredActionTask],
  errors : Array[String],
  action_context_env? : Map[String, String] = {},
  composite_output_mappings? : Map[String, Map[String, String]] = {},
) -> String {
  if workspace_root.length() == 0 {
    errors.push(
      "step '\{job.id}/\{outer_step_id}' local action '\{action_path}' requires workspace-aware lowering",
    )
    return previous_task_id
  }
  guard find_local_action_manifest(workspace_root, action_path)
    is Some((manifest_path, manifest_text)) else {
    errors.push(
      "step '\{job.id}/\{outer_step_id}' local action '\{action_path}' is missing action.yml or action.yaml",
    )
    return previous_task_id
  }
  // Parse as full manifest to support composite, node, and docker local actions
  let parsed_manifest = parse_action_manifest_yaml(manifest_text)
  guard parsed_manifest.action is Some(action_manifest) else {
    for err in parsed_manifest.errors {
      errors.push(
        "step '\{job.id}/\{outer_step_id}' local action '\{manifest_path}' " +
        err,
      )
    }
    return previous_task_id
  }
  // For node/docker local actions, delegate to manifest-backed lowering
  if action_manifest.runtime != "composite" {
    let local_action_ref = LocalPath(action_path)
    let action_path_root = normalize_local_action_path(action_path)
    let abs_action_root = absolute_exec_path(
      join_path(workspace_root, action_path_root),
    )
    return lower_manifest_backed_action(
      workflow,
      job,
      job_env,
      outer_step,
      outer_step_id,
      previous_task_id,
      local_action_ref,
      abs_action_root,
      workspace_root,
      tasks,
      task_plans,
      deferred_post_tasks,
      errors,
      composite_output_mappings~,
    )
  }
  let action = new_local_action(
    action_manifest.steps,
    name=action_manifest.name,
    inputs=action_manifest.inputs,
    outputs=action_manifest.outputs,
  )

  let mut local_previous_task_id = previous_task_id
  let resolved_inputs = merge_env(action.inputs, outer_step.with_values)
  let action_path_root = normalize_local_action_path(action_path)
  let action_root = join_path(workspace_root, action_path_root)
  let action_scope = step_task_id(job.id, outer_step_id)
  let outer_env = merge_env(job_env, outer_step.env)
  let outer_name = step_name(outer_step, outer_step_id)
  let mut inner_index = 0
  while inner_index < action.steps.length() {
    let inner_step = action.steps[inner_index]
    let inner_step_id = default_step_id(inner_step, inner_index)
    let resolved_step_id = composite_step_id(outer_step_id, inner_step_id)
    validate_step_if(job.id, resolved_step_id, inner_step.if_condition, errors)
    validate_continue_on_error(
      job.id,
      resolved_step_id,
      inner_step.continue_on_error,
      errors,
    )
    let resolved_name = if inner_step.name.length() > 0 {
      outer_name +
      " / " +
      substitute_inputs_text(inner_step.name, resolved_inputs)
    } else {
      outer_name + " / " + inner_step_id
    }
    if inner_step.uses is Some(uses) {
      let parsed_uses = parse_action_ref(uses)
      guard parsed_uses.action is Some(action_ref) else {
        for err in parsed_uses.errors {
          errors.push("step '\{job.id}/\{resolved_step_id}' " + err)
        }
        inner_index += 1
        continue
      }
      let nested_env = substitute_inputs_map(inner_step.env, resolved_inputs)
      let nested_with_values = substitute_inputs_map(
        inner_step.with_values,
        resolved_inputs,
      )
      let nested_outer_step : StepSpec = {
        id: inner_step.id,
        name: substitute_inputs_text(inner_step.name, resolved_inputs),
        run: None,
        uses: inner_step.uses,
        shell: None,
        working_directory: None,
        env: nested_env,
        with_values: nested_with_values,
        if_condition: inner_step.if_condition,
        continue_on_error: inner_step.continue_on_error,
        timeout_minutes: inner_step.timeout_minutes,
      }
      match action_ref {
        LocalPath(path) => {
          let nested_action_path = normalize_local_action_path(
            join_path(action_path_root, path),
          )
          local_previous_task_id = lower_local_action(
            workflow,
            job,
            outer_env,
            nested_outer_step,
            resolved_step_id,
            local_previous_task_id,
            nested_action_path,
            workspace_root,
            tasks,
            task_plans,
            deferred_post_tasks,
            errors,
            action_context_env~,
            composite_output_mappings~,
          )
          inner_index += 1
          continue
        }
        _ => ()
      }
      let resolved_action = resolve_action_ref(action_ref)
      if resolved_action.action is Some(action) {
        let task_id = step_task_id(job.id, resolved_step_id)
        let needs = task_needs(job, local_previous_task_id)
        append_action_task(
          tasks,
          task_plans,
          job,
          task_id,
          resolved_step_id,
          resolved_name,
          needs,
          resolve_string(
            workflow.defaults.shell,
            job.defaults.shell,
            None,
            "bash",
          ),
          resolve_string(
            workflow.defaults.working_directory,
            job.defaults.working_directory,
            None,
            "",
          ),
          inner_step.if_condition,
          inner_step.continue_on_error,
          merge_env(merge_env(outer_env, nested_env), action_context_env),
          action,
        )
        local_previous_task_id = task_id
        inner_index += 1
        continue
      }
      if manifest_backed_action_root(action_ref) is Some(cached_root) {
        local_previous_task_id = lower_manifest_backed_action(
          workflow,
          job,
          outer_env,
          nested_outer_step,
          resolved_step_id,
          local_previous_task_id,
          action_ref,
          cached_root,
          workspace_root,
          tasks,
          task_plans,
          deferred_post_tasks,
          errors,
          composite_output_mappings~,
        )
        inner_index += 1
        continue
      }
      guard resolved_action.action is Some(_) else {
        for err in resolved_action.errors {
          errors.push("step '\{job.id}/\{resolved_step_id}' " + err)
        }
        inner_index += 1
        continue
      }
    }
    guard inner_step.run is Some(script) else {
      errors.push("step '\{job.id}/\{resolved_step_id}' must define run")
      inner_index += 1
      continue
    }
    let task_id = step_task_id(job.id, resolved_step_id)
    let substituted_shell = substitute_optional_inputs(
      inner_step.shell,
      resolved_inputs,
    )
    let shell = resolve_string(
      workflow.defaults.shell,
      job.defaults.shell,
      substituted_shell,
      "bash",
    )
    let substituted_working_directory = substitute_optional_inputs(
      inner_step.working_directory,
      resolved_inputs,
    )
    let working_directory = resolve_string(
      workflow.defaults.working_directory,
      job.defaults.working_directory,
      substituted_working_directory,
      "",
    )
    let env = merge_env(
      substitute_inputs_map(
        merge_env(outer_env, inner_step.env),
        resolved_inputs,
      ),
      merge_env(action_context_env, { "GITHUB_ACTION_PATH": action_root }),
    )
    let substituted_script = substitute_inputs_text(script, resolved_inputs)
    let needs = task_needs(job, local_previous_task_id)
    append_run_task(
      tasks,
      task_plans,
      job,
      task_id,
      resolved_step_id,
      resolved_name,
      substituted_script,
      needs,
      shell,
      working_directory,
      inner_step.if_condition,
      inner_step.continue_on_error,
      env,
      action_scope=Some(action_scope),
    )
    local_previous_task_id = task_id
    inner_index += 1
  }
  // Register composite action output mappings
  // outputs map: output_name → expression (e.g., "${{ steps.write.outputs.value }}")
  // We resolve inner step references relative to the outer step scope
  if action.outputs.length() > 0 {
    let resolved_outputs : Map[String, String] = {}
    for output_name, expression in action.outputs {
      // Rewrite inner step references to composite step IDs
      // e.g., "steps.write.outputs.value" → look up "outer__write" in step_outputs
      resolved_outputs[output_name] = resolve_composite_output_expression(
        expression, outer_step_id,
      )
    }
    composite_output_mappings[outer_step_id] = resolved_outputs
  }
  local_previous_task_id
}

///|
fn resolve_composite_output_expression(
  expression : String,
  outer_step_id : String,
) -> String {
  // Parse "${{ steps.<inner_id>.outputs.<key> }}" and return "outer__inner:key"
  // as a compact representation the executor can resolve
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  let prefix = "${{"
  let suffix = "}}"
  guard trimmed.has_prefix(prefix) && trimmed.has_suffix(suffix) else {
    return expression
  }
  let inner = text_slice(
      trimmed,
      prefix.length(),
      trimmed.length() - suffix.length(),
    )
    .trim(chars=" \t\n\r")
    .to_string()
  let steps_prefix = "steps."
  guard inner.has_prefix(steps_prefix) else { return expression }
  let rest = text_slice(inner, steps_prefix.length(), inner.length())
  let outputs_marker = ".outputs."
  guard find_substring(rest, outputs_marker, 0) is Some(dot_idx) else {
    return expression
  }
  let inner_step_id = text_slice(rest, 0, dot_idx)
  let output_key = text_slice(
    rest,
    dot_idx + outputs_marker.length(),
    rest.length(),
  )
  let composite_id = composite_step_id(outer_step_id, inner_step_id)
  composite_id + ":" + output_key
}

///|
pub fn lower_push_workflow_in_workspace(
  workflow : WorkflowSpec,
  workspace_root : String,
) -> LoweringResult {
  let errors : Array[String] = []
  let nodes : Array[@wf.FlowNode] = []
  let tasks : Array[@wf.FlowTask] = []
  let task_plans : Array[TaskPlan] = []
  let job_outputs : Map[String, Map[String, String]] = {}
  let job_if_conditions : Map[String, String] = {}
  let job_needs : Map[String, Array[String]] = {}
  let job_need_targets : Map[String, Map[String, Array[String]]] = {}
  let job_virtual_targets : Map[String, Array[String]] = {}
  let job_virtual_output_targets : Map[String, Map[String, Array[String]]] = {}
  let job_matrix_groups : Map[String, String] = {}
  let job_matrix_fail_fast : Map[String, Bool] = {}
  let job_containers : Map[String, JobContainerSpec] = {}
  let job_services : Map[String, Map[String, JobContainerSpec]] = {}
  let composite_output_mappings : Map[String, Map[String, String]] = {}
  let entry_targets : Array[String] = []
  let seen_jobs : Map[String, Bool] = {}
  if workflow.workflow_call {
    errors.push("workflow_call is not supported in MVP")
  }
  let reusable_expansion = expand_reusable_workflows_in_workspace(
    workflow.jobs,
    workspace_root,
    workspace_root,
    errors,
  )
  let expanded_jobs = expand_matrix_jobs(
    reusable_expansion.jobs,
    aliases=reusable_expansion.aliases,
  )
  for job_id, targets in reusable_expansion.aliases {
    job_virtual_targets[job_id] = targets
  }
  for job_id, outputs in reusable_expansion.alias_outputs {
    job_outputs[job_id] = outputs
  }
  for job_id, output_targets in reusable_expansion.alias_output_targets {
    job_virtual_output_targets[job_id] = output_targets
  }
  // permissions and concurrency are silently ignored for local execution
  ignore(workflow.permissions)
  ignore(workflow.concurrency)
  let expanded_specs : Array[JobSpec] = []
  for expanded in expanded_jobs {
    expanded_specs.push(expanded.job)
  }
  let known_jobs = job_id_set(expanded_specs)

  for expanded in expanded_jobs {
    let job = expanded.job
    if job.id.length() == 0 {
      errors.push("job id is empty")
      continue
    }
    if seen_jobs.get(job.id) is Some(_) {
      errors.push("duplicate job id '\{job.id}'")
      continue
    }
    seen_jobs[job.id] = true
    nodes.push(@wf.new_node(job.id, job.needs))
  }

  for expanded in expanded_jobs {
    let job = expanded.job
    job_outputs[job.id] = job.outputs
    job_if_conditions[job.id] = job.if_condition
    job_needs[job.id] = expanded.visible_needs
    job_need_targets[job.id] = expanded.need_targets
    match expanded.matrix_group {
      Some(group) => {
        job_matrix_groups[job.id] = group
        job_matrix_fail_fast[job.id] = expanded.matrix_fail_fast
      }
      None => ()
    }
    match job.container {
      Some(container) => job_containers[job.id] = container
      None => ()
    }
    if job.services.length() > 0 {
      job_services[job.id] = job.services
    }
    if job.reusable_workflow is Some(path) {
      errors.push(
        "job '\{job.id}' reusable workflow is not supported in MVP: \{path}",
      )
    }
    // permissions and concurrency are silently ignored for local execution
    ignore(job.permissions)
    ignore(job.concurrency)
    validate_job_if(job.id, job.if_condition, errors)
    for need in job.needs {
      if known_jobs.get(need) is None {
        errors.push("job '\{job.id}' needs unknown job '\{need}'")
      }
    }
    if job.steps.length() == 0 {
      errors.push("job '\{job.id}' must have at least one step")
    }

    let mut previous_task_id = ""
    let deferred_post_tasks : Array[DeferredActionTask] = []
    let job_env = merge_env(workflow.env, job.env)
    let mut step_index = 0
    while step_index < job.steps.length() {
      let step = job.steps[step_index]
      let resolved_step_id = default_step_id(step, step_index)
      validate_step_if(job.id, resolved_step_id, step.if_condition, errors)
      validate_continue_on_error(
        job.id,
        resolved_step_id,
        step.continue_on_error,
        errors,
      )
      let shell = resolve_string(
        workflow.defaults.shell,
        job.defaults.shell,
        step.shell,
        "bash",
      )
      let working_directory = resolve_string(
        workflow.defaults.working_directory,
        job.defaults.working_directory,
        step.working_directory,
        "",
      )
      let step_env = merge_env(job_env, step.env)

      if step.uses is Some(uses) {
        let parsed = parse_action_ref(uses)
        guard parsed.action is Some(action_ref) else {
          for err in parsed.errors {
            errors.push("step '\{job.id}/\{resolved_step_id}' " + err)
          }
          step_index += 1
          continue
        }
        match action_ref {
          LocalPath(path) => {
            previous_task_id = lower_local_action(
              workflow,
              job,
              job_env,
              step,
              resolved_step_id,
              previous_task_id,
              path,
              workspace_root,
              tasks,
              task_plans,
              deferred_post_tasks,
              errors,
              composite_output_mappings~,
            )
            step_index += 1
            continue
          }
          _ => ()
        }
        let resolved = resolve_action_ref(action_ref)
        if resolved.action is Some(action) {
          previous_task_id = lower_builtin_action(
            job,
            step,
            resolved_step_id,
            previous_task_id,
            shell,
            working_directory,
            merge_env(
              merge_env(step_env, action_input_env({}, step.with_values)),
              github_action_context_env(action_ref),
            ),
            action_ref,
            action,
            tasks,
            task_plans,
            deferred_post_tasks,
          )
          step_index += 1
          continue
        }
        if workspace_root.length() > 0 &&
          manifest_backed_action_root(action_ref) is Some(cached_root) {
          previous_task_id = lower_manifest_backed_action(
            workflow,
            job,
            job_env,
            step,
            resolved_step_id,
            previous_task_id,
            action_ref,
            cached_root,
            workspace_root,
            tasks,
            task_plans,
            deferred_post_tasks,
            errors,
            composite_output_mappings~,
          )
          step_index += 1
          continue
        }
        guard resolved.action is Some(_) else {
          for err in resolved.errors {
            errors.push("step '\{job.id}/\{resolved_step_id}' " + err)
          }
          step_index += 1
          continue
        }
      }
      guard step.run is Some(script) else {
        errors.push("step '\{job.id}/\{resolved_step_id}' must define run")
        step_index += 1
        continue
      }
      let task_id = step_task_id(job.id, resolved_step_id)
      let needs = task_needs(job, previous_task_id)
      let effective_timeout = if step.timeout_minutes > 0 {
        step.timeout_minutes
      } else {
        job.timeout_minutes
      }
      append_run_task(
        tasks,
        task_plans,
        job,
        task_id,
        resolved_step_id,
        step_name(step, resolved_step_id),
        script,
        needs,
        shell,
        working_directory,
        step.if_condition,
        step.continue_on_error,
        step_env,
        timeout_minutes=effective_timeout,
      )
      previous_task_id = task_id
      step_index += 1
    }

    previous_task_id = append_deferred_action_tasks(
      tasks, task_plans, job, deferred_post_tasks, previous_task_id,
    )

    let barrier_id = finish_task_id(job.id)
    let barrier_needs = task_needs(job, previous_task_id)
    tasks.push(
      @wf.new_task(barrier_id, job.id, "__actrun_barrier__", barrier_needs),
    )
    task_plans.push(
      new_task_plan(
        barrier_id,
        "barrier",
        job.id,
        "__finish",
        "job finish",
        "",
        "",
        "",
        "success()",
        job.runs_on,
        {},
      ),
    )
    entry_targets.push(barrier_id)
  }

  let ir = @wf.new_ir(
    workflow.name,
    nodes,
    tasks,
    entry_targets~,
    max_parallel=workflow_parallelism(expanded_jobs.length()),
  )
  for issue in @wf.ir_issues(ir) {
    errors.push(issue)
  }
  {
    ir,
    plan: {
      tasks: task_plans,
      job_outputs,
      job_if_conditions,
      job_needs,
      job_need_targets,
      job_virtual_targets,
      job_virtual_output_targets,
      job_matrix_groups,
      job_matrix_fail_fast,
      job_containers,
      job_services,
      composite_output_mappings,
    },
    errors,
  }
}

///|
pub fn lower_push_workflow(workflow : WorkflowSpec) -> LoweringResult {
  lower_push_workflow_in_workspace(workflow, "")
}
