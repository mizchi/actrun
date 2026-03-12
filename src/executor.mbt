///|
fn lowered_issues(lowered : LoweringResult) -> Array[String] {
  let issues : Array[String] = []
  for err in lowered.errors {
    issues.push(err)
  }
  for err in @wf.ir_issues(lowered.ir) {
    issues.push(err)
  }
  issues
}

///|
fn task_id_map(tasks : Array[@wf.FlowTask]) -> Map[String, @wf.FlowTask] {
  let result : Map[String, @wf.FlowTask] = {}
  for task in tasks {
    result[task.id] = task
  }
  result
}

///|
fn selected_task_set(ir : @wf.FlowIr) -> Map[String, Bool] {
  let selected : Map[String, Bool] = {}
  if ir.entry_targets.length() == 0 {
    for task in ir.tasks {
      selected[task.id] = true
    }
    return selected
  }
  let task_map = task_id_map(ir.tasks)
  let stack : Array[String] = []
  for target in ir.entry_targets {
    stack.push(target)
  }
  while stack.length() > 0 {
    let id = stack.pop().unwrap_or("")
    if id.length() == 0 || selected.get(id) is Some(_) {
      continue
    }
    selected[id] = true
    match task_map.get(id) {
      Some(task) =>
        for dep in task.needs {
          stack.push(dep)
        }
      None => ()
    }
  }
  selected
}

///|
priv struct JobRuntimeState {
  env_updates : Map[String, String]
  path_entries : Array[String]
  step_outputs : Map[String, Map[String, String]]
  step_outcomes : Map[String, String]
  step_conclusions : Map[String, String]
  action_states : Map[String, Map[String, String]]
  started_action_scopes : Map[String, Bool]
}

///|
priv struct StepFileCommands {
  env_path : String
  path_path : String
  output_path : String
  summary_path : String
  state_path : String
  script_path : String
}

///|
priv struct TaskExecutionResult {
  report : TaskRunReport
  env_updates : Map[String, String]
  path_entries : Array[String]
  output_values : Map[String, String]
  state_updates : Map[String, String]
}

///|
fn empty_job_runtime_state() -> JobRuntimeState {
  {
    env_updates: {},
    path_entries: [],
    step_outputs: {},
    step_outcomes: {},
    step_conclusions: {},
    action_states: {},
    started_action_scopes: {},
  }
}

///|
fn job_runtime_state(
  states : Map[String, JobRuntimeState],
  job_id : String,
) -> JobRuntimeState {
  states.get(job_id).unwrap_or(empty_job_runtime_state())
}

///|
fn resolve_task_cwd(workspace_root : String, relative_cwd : String) -> String {
  if relative_cwd.length() == 0 {
    return if workspace_root.length() == 0 { "." } else { workspace_root }
  }
  if relative_cwd.has_prefix("/") ||
    workspace_root.length() == 0 ||
    workspace_root == "." {
    return relative_cwd
  }
  if workspace_root.has_suffix("/") {
    workspace_root + relative_cwd
  } else {
    workspace_root + "/" + relative_cwd
  }
}

///|
fn merge_runner_env(
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
fn exec_text_slice(text : String, start : Int, end_ : Int) -> String {
  String::unsafe_substring(text, start~, end=end_)
}

///|
fn append_paths(newer : Array[String], older : Array[String]) -> Array[String] {
  let combined : Array[String] = []
  for path in newer {
    combined.push(path)
  }
  for path in older {
    combined.push(path)
  }
  combined
}

///|
fn apply_job_runtime_updates(
  state : JobRuntimeState,
  step_id : String,
  step_outcome : String?,
  step_conclusion : String?,
  action_scope : String?,
  env_updates : Map[String, String],
  path_entries : Array[String],
  output_values : Map[String, String],
  state_updates : Map[String, String],
) -> JobRuntimeState {
  let updated_paths = append_paths(path_entries, state.path_entries)
  let merged_env = merge_runner_env(state.env_updates, env_updates)
  let updated_outputs : Map[String, Map[String, String]] = {}
  for key, value in state.step_outputs {
    updated_outputs[key] = value
  }
  let updated_outcomes : Map[String, String] = {}
  for key, value in state.step_outcomes {
    updated_outcomes[key] = value
  }
  let updated_conclusions : Map[String, String] = {}
  for key, value in state.step_conclusions {
    updated_conclusions[key] = value
  }
  if step_id.length() > 0 && output_values.length() > 0 {
    updated_outputs[step_id] = output_values
  }
  match step_outcome {
    Some(value) if step_id.length() > 0 => updated_outcomes[step_id] = value
    _ => ()
  }
  match step_conclusion {
    Some(value) if step_id.length() > 0 => updated_conclusions[step_id] = value
    _ => ()
  }
  let updated_env = if updated_paths.length() > 0 {
    let base_path = merged_env
      .get("PATH")
      .unwrap_or(@xsys.get_env_var("PATH").unwrap_or(""))
    let prefix = updated_paths.join(":")
    merge_runner_env(merged_env, {
      "PATH": if base_path.length() == 0 {
        prefix
      } else {
        prefix + ":" + base_path
      },
    })
  } else {
    merged_env
  }
  let updated_action_states : Map[String, Map[String, String]] = {}
  for key, value in state.action_states {
    updated_action_states[key] = value
  }
  let updated_started_action_scopes : Map[String, Bool] = {}
  for key, value in state.started_action_scopes {
    updated_started_action_scopes[key] = value
  }
  match action_scope {
    Some(scope) => {
      updated_started_action_scopes[scope] = true
      if state_updates.length() > 0 {
        updated_action_states[scope] = merge_runner_env(
          updated_action_states.get(scope).unwrap_or({}),
          state_updates,
        )
      }
    }
    None => ()
  }
  {
    env_updates: updated_env,
    path_entries: updated_paths,
    step_outputs: updated_outputs,
    step_outcomes: updated_outcomes,
    step_conclusions: updated_conclusions,
    action_states: updated_action_states,
    started_action_scopes: updated_started_action_scopes,
  }
}

///|
fn ensure_exec_dir_impl(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
fn ensure_exec_dir(path : String) -> Bool {
  try ensure_exec_dir_impl(path) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
fn write_exec_text(path : String, text : String) -> Bool {
  try @xfs.write_string_to_file(path, text) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
fn read_exec_text(path : String) -> String? {
  try @xfs.read_file_to_string(path) catch {
    _ => None
  } noraise {
    content => Some(content)
  }
}

///|
fn sanitize_task_id(task_id : String) -> String {
  task_id.replace_all(old="/", new="__").replace_all(old=":", new="_")
}

///|
fn absolute_exec_path(path : String) -> String {
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
fn trim_exec_output(text : String) -> String {
  text.trim(chars=" \t\n\r").to_string()
}

///|
async fn exec_capture_stdout(cmd : String, args : Array[String]) -> String? {
  let (code, stdout, _) = @process.collect_output(cmd, args, cwd=".")
  if code == 0 {
    let value = trim_exec_output(stdout.text())
    if value.length() > 0 {
      Some(value)
    } else {
      None
    }
  } else {
    None
  }
}

///|
async fn runner_os_name() -> String {
  match @xsys.get_env_var("RUNNER_OS") {
    Some(value) => value
    None =>
      match @xsys.get_env_var("OS") {
        Some(value) =>
          if value == "Windows_NT" {
            "Windows"
          } else {
            match exec_capture_stdout("uname", ["-s"]) {
              Some(name) =>
                if name == "Darwin" {
                  "macOS"
                } else if name == "Linux" {
                  "Linux"
                } else if name.has_prefix("MINGW") ||
                  name.has_prefix("MSYS") ||
                  name.has_prefix("CYGWIN") {
                  "Windows"
                } else {
                  name
                }
              None => "Linux"
            }
          }
        None =>
          match exec_capture_stdout("uname", ["-s"]) {
            Some(name) =>
              if name == "Darwin" {
                "macOS"
              } else if name == "Linux" {
                "Linux"
              } else if name.has_prefix("MINGW") ||
                name.has_prefix("MSYS") ||
                name.has_prefix("CYGWIN") {
                "Windows"
              } else {
                name
              }
            None => "Linux"
          }
      }
  }
}

///|
async fn runner_arch_name() -> String {
  match @xsys.get_env_var("RUNNER_ARCH") {
    Some(value) => value
    None =>
      match exec_capture_stdout("uname", ["-m"]) {
        Some(value) => {
          let normalized = value.to_lower()
          if normalized == "x86_64" || normalized == "amd64" {
            "X64"
          } else if normalized == "x86" ||
            normalized == "i386" ||
            normalized == "i686" {
            "X86"
          } else if normalized == "arm64" || normalized == "aarch64" {
            "ARM64"
          } else if normalized == "arm" ||
            normalized == "armv7l" ||
            normalized == "armv6l" {
            "ARM"
          } else {
            value
          }
        }
        None => "X64"
      }
  }
}

///|
fn runner_environment_name() -> String {
  @xsys.get_env_var("RUNNER_ENVIRONMENT").unwrap_or("self-hosted")
}

///|
fn prepare_runner_temp_dir(job_id : String, workspace_root : String) -> String {
  ignore(ensure_exec_dir("_build"))
  ignore(ensure_exec_dir("_build/action_runner"))
  ignore(ensure_exec_dir("_build/action_runner/runner_temp"))
  let workspace_key = sanitize_task_id(
    absolute_exec_path(resolve_task_cwd(workspace_root, "")),
  )
  let dir = absolute_exec_path(
    "_build/action_runner/runner_temp/" +
    workspace_key +
    "__" +
    sanitize_task_id(job_id),
  )
  ignore(ensure_exec_dir(dir))
  dir
}

///|
fn find_exec_substring(text : String, pattern : String, start : Int) -> Int? {
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
fn prepare_step_file_commands(
  task_id : String,
  workspace_root : String,
) -> StepFileCommands? {
  guard ensure_exec_dir("_build") else { return None }
  guard ensure_exec_dir("_build/action_runner") else { return None }
  guard ensure_exec_dir("_build/action_runner/file_commands") else {
    return None
  }
  let workspace_key = sanitize_task_id(
    absolute_exec_path(resolve_task_cwd(workspace_root, "")),
  )
  let prefix = absolute_exec_path(
    "_build/action_runner/file_commands/" +
    workspace_key +
    "__" +
    sanitize_task_id(task_id),
  )
  let env_path = prefix + ".env"
  let path_path = prefix + ".path"
  let output_path = prefix + ".output"
  let summary_path = prefix + ".summary"
  let state_path = prefix + ".state"
  let script_path = prefix + ".script"
  guard write_exec_text(env_path, "") else { return None }
  guard write_exec_text(path_path, "") else { return None }
  guard write_exec_text(output_path, "") else { return None }
  guard write_exec_text(summary_path, "") else { return None }
  guard write_exec_text(state_path, "") else { return None }
  guard write_exec_text(script_path, "") else { return None }
  Some({
    env_path,
    path_path,
    output_path,
    summary_path,
    state_path,
    script_path,
  })
}

///|
fn trim_cr(text : String) -> String {
  text.trim_end(chars="\r").to_string()
}

///|
fn parse_env_updates(path : String) -> Map[String, String] {
  let updates : Map[String, String] = {}
  guard read_exec_text(path) is Some(content) else { return updates }
  let lines = content.split("\n").collect()
  let mut idx = 0
  while idx < lines.length() {
    let line = trim_cr(lines[idx].to_string())
    if line.length() == 0 {
      idx += 1
      continue
    }
    match line.find("<<") {
      Some(split_idx) => {
        let key = exec_text_slice(line, 0, split_idx)
        let delimiter = exec_text_slice(line, split_idx + 2, line.length())
        if key.length() > 0 && delimiter.length() > 0 {
          let value_lines : Array[String] = []
          let mut cursor = idx + 1
          let mut closed = false
          while cursor < lines.length() {
            let value_line = trim_cr(lines[cursor].to_string())
            if value_line == delimiter {
              closed = true
              break
            }
            value_lines.push(value_line)
            cursor += 1
          }
          if closed {
            updates[key] = value_lines.join("\n")
            idx = cursor + 1
            continue
          }
        }
        idx += 1
      }
      None =>
        match line.find("=") {
          Some(eq_idx) => {
            let key = exec_text_slice(line, 0, eq_idx)
            if key.length() > 0 {
              updates[key] = exec_text_slice(line, eq_idx + 1, line.length())
            }
            idx += 1
          }
          None => idx += 1
        }
    }
  }
  updates
}

///|
fn parse_path_updates(path : String) -> Array[String] {
  let updates : Array[String] = []
  guard read_exec_text(path) is Some(content) else { return updates }
  for line_view in content.split("\n") {
    let line = trim_cr(line_view.to_string())
    if line.length() == 0 {
      continue
    }
    updates.push(line)
  }
  updates
}

///|
fn parse_output_values(path : String) -> Map[String, String] {
  parse_env_updates(path)
}

///|
fn parse_state_values(path : String) -> Map[String, String] {
  parse_env_updates(path)
}

///|
fn parse_summary_text(path : String) -> String {
  read_exec_text(path).unwrap_or("")
}

///|
fn step_output_expr_name(expression : String) -> (String, String)? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  guard trimmed.has_prefix("steps.") && trimmed.length() > 6 else {
    return None
  }
  guard find_exec_substring(trimmed, ".outputs.", 6) is Some(outputs_idx) else {
    return None
  }
  let step_id = exec_text_slice(trimmed, 6, outputs_idx)
  let output_name = exec_text_slice(trimmed, outputs_idx + 9, trimmed.length())
  if step_id.length() == 0 || output_name.length() == 0 {
    None
  } else {
    Some((step_id, output_name))
  }
}

///|
fn step_status_expr_name(expression : String, suffix : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  guard trimmed.has_prefix("steps.") && trimmed.has_suffix(suffix) else {
    return None
  }
  let step_id = exec_text_slice(trimmed, 6, trimmed.length() - suffix.length())
  if step_id.length() == 0 {
    None
  } else {
    Some(step_id)
  }
}

///|
fn needs_output_expr_name(expression : String) -> (String, String)? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  guard trimmed.has_prefix("needs.") && trimmed.length() > 6 else {
    return None
  }
  guard find_exec_substring(trimmed, ".outputs.", 6) is Some(outputs_idx) else {
    return None
  }
  let job_id = exec_text_slice(trimmed, 6, outputs_idx)
  let output_name = exec_text_slice(trimmed, outputs_idx + 9, trimmed.length())
  if job_id.length() == 0 || output_name.length() == 0 {
    None
  } else {
    Some((job_id, output_name))
  }
}

///|
fn needs_result_expr_name(expression : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  guard trimmed.has_prefix("needs.") && trimmed.has_suffix(".result") else {
    return None
  }
  let job_id = exec_text_slice(trimmed, 6, trimmed.length() - 7)
  if job_id.length() == 0 {
    None
  } else {
    Some(job_id)
  }
}

///|
fn env_expr_name(expression : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  if trimmed.has_prefix("env.") && trimmed.length() > 4 {
    Some(exec_text_slice(trimmed, 4, trimmed.length()))
  } else {
    None
  }
}

///|
fn github_expr_name(expression : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  if trimmed.has_prefix("github.") && trimmed.length() > 7 {
    Some(exec_text_slice(trimmed, 7, trimmed.length()))
  } else {
    None
  }
}

///|
fn runner_expr_name(expression : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  if trimmed.has_prefix("runner.") && trimmed.length() > 7 {
    Some(exec_text_slice(trimmed, 7, trimmed.length()))
  } else {
    None
  }
}

///|
fn vars_expr_name(expression : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  if trimmed.has_prefix("vars.") && trimmed.length() > 5 {
    Some(exec_text_slice(trimmed, 5, trimmed.length()))
  } else {
    None
  }
}

///|
fn resolve_step_output(
  state : JobRuntimeState,
  step_id : String,
  output_name : String,
) -> String {
  match map_get_case_insensitive(state.step_outputs, step_id) {
    Some(outputs) =>
      map_get_case_insensitive(outputs, output_name).unwrap_or("")
    None => ""
  }
}

///|
fn resolve_step_outcome(state : JobRuntimeState, step_id : String) -> String {
  map_get_case_insensitive(state.step_outcomes, step_id).unwrap_or("")
}

///|
fn resolve_step_conclusion(state : JobRuntimeState, step_id : String) -> String {
  map_get_case_insensitive(state.step_conclusions, step_id).unwrap_or("")
}

///|
fn resolve_needs_output(
  needs_outputs : Map[String, Map[String, String]],
  job_id : String,
  output_name : String,
) -> String {
  match map_get_case_insensitive(needs_outputs, job_id) {
    Some(outputs) =>
      map_get_case_insensitive(outputs, output_name).unwrap_or("")
    None => ""
  }
}

///|
fn resolve_needs_result(
  needs_results : Map[String, String],
  job_id : String,
) -> String {
  map_get_case_insensitive(needs_results, job_id).unwrap_or("")
}

///|
fn[V] map_get_case_insensitive(values : Map[String, V], key : String) -> V? {
  match values.get(key) {
    Some(value) => Some(value)
    None => {
      let needle = key.to_lower()
      for existing_key, value in values {
        if existing_key.to_lower() == needle {
          return Some(value)
        }
      }
      None
    }
  }
}

///|
fn action_scope_state(
  state : JobRuntimeState,
  action_scope : String?,
) -> Map[String, String] {
  match action_scope {
    Some(scope) => state.action_states.get(scope).unwrap_or({})
    None => {}
  }
}

///|
fn action_scope_started(
  state : JobRuntimeState,
  action_scope : String?,
) -> Bool {
  match action_scope {
    Some(scope) => state.started_action_scopes.get(scope).unwrap_or(false)
    None => false
  }
}

///|
fn action_scope_env(
  state : JobRuntimeState,
  action_scope : String?,
) -> Map[String, String] {
  let env : Map[String, String] = {}
  for key, value in action_scope_state(state, action_scope) {
    env["STATE_" + key] = value
  }
  env
}

///|
fn github_action_repository(plan : TaskPlan) -> String {
  match plan.env.get("GITHUB_ACTION_REPOSITORY") {
    Some(value) if value.length() > 0 => value
    _ =>
      match plan.action {
        Some(action) =>
          match action.action_ref {
            GitHubRepo(owner, repo, _, _) => owner + "/" + repo
            _ => ""
          }
        None => ""
      }
  }
}

///|
fn github_action_ref_value(plan : TaskPlan) -> String {
  match plan.env.get("GITHUB_ACTION_REF") {
    Some(value) if value.length() > 0 => value
    _ =>
      match plan.action {
        Some(action) =>
          match action.action_ref {
            GitHubRepo(_, _, version, _) => version
            _ => ""
          }
        None => ""
      }
  }
}

///|
fn leaf_step_id(step_id : String) -> String {
  let mut idx = step_id.length()
  while idx >= 2 {
    idx -= 1
    if step_id.unsafe_get(idx - 1) == '_' && step_id.unsafe_get(idx) == '_' {
      return exec_text_slice(step_id, idx + 1, step_id.length())
    }
  }
  step_id
}

///|
fn is_action_name_char(code : UInt16) -> Bool {
  (code >= 97 && code <= 122) ||
  (code >= 65 && code <= 90) ||
  (code >= 48 && code <= 57) ||
  code == 95
}

///|
fn sanitize_action_name(text : String) -> String {
  let chars : Array[String] = []
  let mut idx = 0
  while idx < text.length() {
    let code = text.unsafe_get(idx)
    if is_action_name_char(code) {
      chars.push(exec_text_slice(text, idx, idx + 1))
    }
    idx += 1
  }
  chars.join("")
}

///|
fn github_action_name_from_ref(action_ref : ActionRef) -> String {
  match action_ref {
    GitHubRepo(owner, repo, _, subpath) => {
      let subpath_text = match subpath {
        Some(path) => if path.length() > 0 { "/" + path } else { "" }
        None => ""
      }
      sanitize_action_name(owner + "/" + repo + subpath_text)
    }
    _ => sanitize_action_name(action_ref_text(action_ref))
  }
}

///|
fn github_action_value(plan : TaskPlan) -> String {
  match plan.env.get("GITHUB_ACTION") {
    Some(value) if value.length() > 0 => value
    _ =>
      if plan.kind == "action" {
        match plan.action {
          Some(action) => github_action_name_from_ref(action.action_ref)
          None => sanitize_action_name(leaf_step_id(plan.step_id))
        }
      } else {
        leaf_step_id(plan.step_id)
      }
  }
}

///|
fn github_action_path_value(plan : TaskPlan) -> String {
  match plan.env.get("GITHUB_ACTION_PATH") {
    Some(value) if value.length() > 0 => value
    _ =>
      match plan.action {
        Some(action) => action.action_path.unwrap_or("")
        None => ""
      }
  }
}

///|
fn push_event_ref(push_event : PushEvent?) -> String {
  match push_event {
    Some(event) =>
      if event.ref_name.length() == 0 {
        ""
      } else if event.ref_name.has_prefix("refs/") {
        event.ref_name
      } else {
        "refs/heads/" + event.ref_name
      }
    None => ""
  }
}

///|
fn push_event_name(push_event : PushEvent?) -> String {
  match push_event {
    Some(_) => "push"
    None => "push"
  }
}

///|
fn github_repository_owner(push_event : PushEvent?) -> String {
  match push_event {
    Some(event) => {
      let repository = event.repository.trim(chars=" /").to_string()
      match repository.find("/") {
        Some(idx) =>
          if idx > 0 {
            String::unsafe_substring(repository, start=0, end=idx)
          } else {
            ""
          }
        None => ""
      }
    }
    None => ""
  }
}

///|
fn github_context(
  workflow_name : String,
  plan : TaskPlan,
  workspace_root : String,
  push_event : PushEvent?,
) -> Map[String, String] {
  {
    "action": github_action_value(plan),
    "actor": match push_event {
      Some(event) => event.actor
      None => ""
    },
    "event_name": push_event_name(push_event),
    "workflow": workflow_name,
    "job": plan.job_id,
    "workspace": absolute_exec_path(resolve_task_cwd(workspace_root, "")),
    "ref": push_event_ref(push_event),
    "ref_name": match push_event {
      Some(event) => event.ref_name
      None => ""
    },
    "repository": match push_event {
      Some(event) => event.repository
      None => ""
    },
    "repository_owner": github_repository_owner(push_event),
    "sha": match push_event {
      Some(event) => event.after_sha
      None => ""
    },
    "action_path": github_action_path_value(plan),
    "action_repository": github_action_repository(plan),
    "action_ref": github_action_ref_value(plan),
  }
}

///|
async fn runner_context(
  plan : TaskPlan,
  workspace_root : String,
) -> Map[String, String] {
  {
    "os": runner_os_name(),
    "arch": runner_arch_name(),
    "environment": runner_environment_name(),
    "temp": prepare_runner_temp_dir(plan.job_id, workspace_root),
  }
}

///|
fn runner_vars_context() -> Map[String, String] {
  let values : Map[String, String] = {}
  let prefix = "ACTION_RUNNER_VAR_"
  for key, value in @xsys.get_env_vars() {
    if key.has_prefix(prefix) && key.length() > prefix.length() {
      values[exec_text_slice(key, prefix.length(), key.length())] = value
    }
  }
  values
}

///|
fn substitute_runtime_text(
  text : String,
  state : JobRuntimeState,
  workspace_root : String,
  env_context : Map[String, String],
  github_context : Map[String, String],
  runner_context : Map[String, String],
  needs_outputs : Map[String, Map[String, String]],
  needs_results : Map[String, String],
) -> String {
  let vars_context = runner_vars_context()
  let chunks : Array[String] = []
  let mut idx = 0
  while idx < text.length() {
    match find_exec_substring(text, "${{", idx) {
      Some(open_idx) => {
        chunks.push(exec_text_slice(text, idx, open_idx))
        match find_exec_substring(text, "}}", open_idx + 3) {
          Some(close_idx) => {
            let expression = exec_text_slice(text, open_idx + 3, close_idx)
            match step_output_expr_name(expression) {
              Some((step_id, output_name)) =>
                chunks.push(resolve_step_output(state, step_id, output_name))
              None =>
                match step_status_expr_name(expression, ".outcome") {
                  Some(step_id) =>
                    chunks.push(resolve_step_outcome(state, step_id))
                  None =>
                    match step_status_expr_name(expression, ".conclusion") {
                      Some(step_id) =>
                        chunks.push(resolve_step_conclusion(state, step_id))
                      None =>
                        match needs_output_expr_name(expression) {
                          Some((job_id, output_name)) =>
                            chunks.push(
                              resolve_needs_output(
                                needs_outputs, job_id, output_name,
                              ),
                            )
                          None =>
                            match needs_result_expr_name(expression) {
                              Some(job_id) =>
                                chunks.push(
                                  resolve_needs_result(needs_results, job_id),
                                )
                              None =>
                                match env_expr_name(expression) {
                                  Some(name) =>
                                    chunks.push(
                                      map_get_case_insensitive(
                                        env_context, name,
                                      ).unwrap_or(""),
                                    )
                                  None =>
                                    match vars_expr_name(expression) {
                                      Some(name) =>
                                        chunks.push(
                                          map_get_case_insensitive(
                                            vars_context, name,
                                          ).unwrap_or(""),
                                        )
                                      None =>
                                        match github_expr_name(expression) {
                                          Some(name) =>
                                            chunks.push(
                                              map_get_case_insensitive(
                                                github_context, name,
                                              ).unwrap_or(""),
                                            )
                                          None =>
                                            match runner_expr_name(expression) {
                                              Some(name) =>
                                                chunks.push(
                                                  map_get_case_insensitive(
                                                    runner_context, name,
                                                  ).unwrap_or(""),
                                                )
                                              None =>
                                                match
                                                  evaluate_string_function_expression(
                                                    expression,
                                                    new_if_condition_context(
                                                      step_outputs=state.step_outputs,
                                                      step_outcomes=state.step_outcomes,
                                                      step_conclusions=state.step_conclusions,
                                                      workspace_root~,
                                                      env_context~,
                                                      vars_context~,
                                                      github_context~,
                                                      runner_context~,
                                                      needs_outputs~,
                                                      needs_results~,
                                                    ),
                                                  ) {
                                                  Some(value) =>
                                                    chunks.push(value)
                                                  None =>
                                                    chunks.push(
                                                      exec_text_slice(
                                                        text,
                                                        open_idx,
                                                        close_idx + 2,
                                                      ),
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            idx = close_idx + 2
          }
          None => {
            chunks.push(exec_text_slice(text, open_idx, text.length()))
            idx = text.length()
          }
        }
      }
      None => {
        chunks.push(exec_text_slice(text, idx, text.length()))
        idx = text.length()
      }
    }
  }
  chunks.join("")
}

///|
fn substitute_runtime_optional(
  value : String?,
  state : JobRuntimeState,
  workspace_root : String,
  env_context : Map[String, String],
  github_context : Map[String, String],
  runner_context : Map[String, String],
  needs_outputs : Map[String, Map[String, String]],
  needs_results : Map[String, String],
) -> String? {
  match value {
    Some(text) =>
      Some(
        substitute_runtime_text(
          text, state, workspace_root, env_context, github_context, runner_context,
          needs_outputs, needs_results,
        ),
      )
    None => None
  }
}

///|
fn resolve_plan_env(
  plan : TaskPlan,
  state : JobRuntimeState,
  workspace_root : String,
  github_context : Map[String, String],
  runner_context : Map[String, String],
  needs_outputs : Map[String, Map[String, String]],
  needs_results : Map[String, String],
) -> Map[String, String] {
  let action_env = action_scope_env(state, plan.action_scope)
  let mut context = merge_runner_env(plan.env, state.env_updates)
  context = merge_runner_env(context, action_env)
  let mut pass = 0
  while pass < 8 {
    let next : Map[String, String] = {}
    for key, value in plan.env {
      next[key] = substitute_runtime_text(
        value, state, workspace_root, context, github_context, runner_context, needs_outputs,
        needs_results,
      )
    }
    for key, value in state.env_updates {
      next[key] = value
    }
    for key, value in action_env {
      next[key] = value
    }
    context = next
    pass += 1
  }
  context
}

///|
fn shell_escape_arg(value : String) -> String {
  "'" + value.replace_all(old="'", new="'\"'\"'") + "'"
}

///|
fn shell_command(
  shell : String,
  script_path : String,
) -> (String, Array[String]) {
  let trimmed = shell.trim(chars=" ").to_string()
  if trimmed.contains("{0}") {
    let expanded = trimmed.replace_all(
      old="{0}",
      new=shell_escape_arg(script_path),
    )
    return ("sh", ["-c", expanded])
  }
  if trimmed == "pwsh" || trimmed == "powershell" {
    return (trimmed, ["-Command", ". " + shell_escape_arg(script_path)])
  }
  if trimmed == "bash" || trimmed.length() == 0 {
    return ("bash", ["--noprofile", "--norc", "-eo", "pipefail", script_path])
  }
  if trimmed == "sh" {
    return ("sh", ["-e", script_path])
  }
  (trimmed, [script_path])
}

///|
fn env_command_args(
  cmd : String,
  args : Array[String],
  env : Map[String, String],
) -> Array[String] {
  let env_args : Array[String] = []
  for key, value in env {
    env_args.push(key + "=" + value)
  }
  env_args.push(cmd)
  for arg in args {
    env_args.push(arg)
  }
  env_args
}

///|
fn unsupported_workflow_command(plan : TaskPlan, script : String) -> String? {
  if script.contains("GITHUB_STATE") && plan.action_scope is None {
    Some("GITHUB_STATE")
  } else {
    None
  }
}

///|
fn job_needs_outputs(
  plan : ExecutionPlan,
  job_id : String,
  outputs : Map[String, Map[String, String]],
) -> Map[String, Map[String, String]] {
  let values : Map[String, Map[String, String]] = {}
  let targets = plan.job_need_targets.get(job_id).unwrap_or({})
  for need in plan.job_needs.get(job_id).unwrap_or([]) {
    let merged : Map[String, String] = {}
    for target in targets.get(need).unwrap_or([need]) {
      for key, value in outputs.get(target).unwrap_or({}) {
        if value.length() > 0 {
          merged[key] = value
        }
      }
    }
    values[need] = merged
  }
  values
}

///|
fn job_needs_results(
  plan : ExecutionPlan,
  job_id : String,
  results : Map[String, String],
) -> Map[String, String] {
  let values : Map[String, String] = {}
  let targets = plan.job_need_targets.get(job_id).unwrap_or({})
  for need in plan.job_needs.get(job_id).unwrap_or([]) {
    let mut has_failure = false
    let mut has_cancelled = false
    let mut has_skipped = false
    let mut has_success = false
    for target in targets.get(need).unwrap_or([need]) {
      match results.get(target).unwrap_or("") {
        "failure" => has_failure = true
        "cancelled" => has_cancelled = true
        "skipped" => has_skipped = true
        "success" => has_success = true
        _ => ()
      }
    }
    values[need] = if has_failure {
      "failure"
    } else if has_cancelled {
      "cancelled"
    } else if has_skipped {
      "skipped"
    } else if has_success {
      "success"
    } else {
      ""
    }
  }
  values
}

///|
fn job_if_success_value(needs_results : Map[String, String]) -> Bool {
  for _, value in needs_results {
    if value != "success" {
      return false
    }
  }
  true
}

///|
fn job_if_failure_value(needs_results : Map[String, String]) -> Bool {
  for _, value in needs_results {
    if value == "failure" {
      return true
    }
  }
  false
}

///|
fn job_if_cancelled_value(needs_results : Map[String, String]) -> Bool {
  for _, value in needs_results {
    if value == "cancelled" {
      return true
    }
  }
  false
}

///|
fn step_if_success_value(state : JobRuntimeState) -> Bool {
  for _, value in state.step_conclusions {
    if value == "failure" || value == "cancelled" {
      return false
    }
  }
  true
}

///|
fn step_if_failure_value(state : JobRuntimeState) -> Bool {
  for _, value in state.step_conclusions {
    if value == "failure" {
      return true
    }
  }
  false
}

///|
fn step_if_cancelled_value(state : JobRuntimeState) -> Bool {
  for _, value in state.step_conclusions {
    if value == "cancelled" {
      return true
    }
  }
  false
}

///|
fn task_outcome(report : TaskRunReport) -> String {
  if report.status == "skipped" || report.status == "cancelled" {
    return report.status
  }
  if report.code == 0 {
    "success"
  } else {
    "failure"
  }
}

///|
fn task_conclusion(outcome : String, continue_on_error : Bool) -> String {
  if outcome == "failure" && continue_on_error {
    "success"
  } else {
    outcome
  }
}

///|
fn task_conclusion_allows_dependents(conclusion : String) -> Bool {
  conclusion == "success" || conclusion == "skipped"
}

///|
fn matrix_group_members(plan : ExecutionPlan) -> Map[String, Array[String]] {
  let groups : Map[String, Array[String]] = {}
  for job_id, group in plan.job_matrix_groups {
    let jobs = groups.get(group).unwrap_or([])
    jobs.push(job_id)
    groups[group] = jobs
  }
  groups
}

///|
fn evaluate_job_outputs(
  output_defs : Map[String, String],
  state : JobRuntimeState,
  workspace_root : String,
) -> Map[String, String] {
  let values : Map[String, String] = {}
  let empty_github : Map[String, String] = {}
  let empty_runner : Map[String, String] = {}
  let empty_needs_outputs : Map[String, Map[String, String]] = {}
  let empty_needs_results : Map[String, String] = {}
  for key, value in output_defs {
    values[key] = substitute_runtime_text(
      value,
      state,
      workspace_root,
      state.env_updates,
      empty_github,
      empty_runner,
      empty_needs_outputs,
      empty_needs_results,
    )
  }
  values
}

///|
fn make_invalid_report(issues : Array[String]) -> WorkflowRunReport {
  {
    ok: false,
    state: "invalid",
    order: [],
    steps: [],
    issues,
    task_reports: [],
  }
}

///|
fn task_report_success(
  plan : TaskPlan,
  workspace_root : String,
) -> TaskRunReport {
  {
    id: plan.id,
    kind: plan.kind,
    status: "success",
    code: 0,
    shell: plan.shell,
    script: plan.script,
    cwd: resolve_task_cwd(workspace_root, plan.working_directory),
    stdout: "",
    stderr: "",
    summary: "",
  }
}

///|
fn task_report_failure(
  plan : TaskPlan,
  workspace_root : String,
  message : String,
) -> TaskRunReport {
  {
    id: plan.id,
    kind: plan.kind,
    status: "failed",
    code: 1,
    shell: plan.shell,
    script: plan.script,
    cwd: resolve_task_cwd(workspace_root, plan.working_directory),
    stdout: "",
    stderr: message,
    summary: "",
  }
}

///|
fn task_report_skipped(
  plan : TaskPlan,
  workspace_root : String,
  message : String,
) -> TaskRunReport {
  {
    id: plan.id,
    kind: plan.kind,
    status: "skipped",
    code: 0,
    shell: plan.shell,
    script: plan.script,
    cwd: resolve_task_cwd(workspace_root, plan.working_directory),
    stdout: "",
    stderr: message,
    summary: "",
  }
}

///|
fn task_report_cancelled(
  plan : TaskPlan,
  workspace_root : String,
  message : String,
) -> TaskRunReport {
  {
    id: plan.id,
    kind: plan.kind,
    status: "cancelled",
    code: 1,
    shell: plan.shell,
    script: plan.script,
    cwd: resolve_task_cwd(workspace_root, plan.working_directory),
    stdout: "",
    stderr: message,
    summary: "",
  }
}

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
fn ensure_exec_dir_recursive(path : String) -> Bool {
  if path == "." || path.length() == 0 || @xfs.path_exists(path) {
    return true
  }
  let parent = artifact_parent_dir(path)
  if parent != path && not(ensure_exec_dir_recursive(parent)) {
    return false
  }
  ensure_exec_dir(path)
}

///|
fn exec_is_dir(path : String) -> Bool {
  try @xfs.is_dir(path) catch {
    _ => false
  } noraise {
    value => value
  }
}

///|
fn exec_remove_tree(path : String) -> Bool {
  if not(@xfs.path_exists(path)) {
    return true
  }
  if exec_is_dir(path) {
    let entries = try @xfs.read_dir(path) catch {
      _ => []
    } noraise {
      value => value
    }
    for entry in entries {
      if not(exec_remove_tree(path + "/" + entry)) {
        return false
      }
    }
    try @xfs.remove_dir(path) catch {
      _ => false
    } noraise {
      _ => true
    }
  } else {
    try @xfs.remove_file(path) catch {
      _ => false
    } noraise {
      _ => true
    }
  }
}

///|
fn exec_leaf_name(path : String) -> String {
  let parts : Array[String] = []
  for part in path.split("/") {
    let text = part.to_string()
    if text.length() > 0 {
      parts.push(text)
    }
  }
  if parts.length() == 0 {
    ""
  } else {
    parts[parts.length() - 1]
  }
}

///|
fn exec_copy_tree(src : String, dst : String) -> Bool {
  if exec_is_dir(src) {
    if not(ensure_exec_dir_recursive(dst)) {
      return false
    }
    let entries = try @xfs.read_dir(src) catch {
      _ => []
    } noraise {
      value => value
    }
    for entry in entries {
      if not(exec_copy_tree(src + "/" + entry, dst + "/" + entry)) {
        return false
      }
    }
    true
  } else {
    if not(ensure_exec_dir_recursive(artifact_parent_dir(dst))) {
      return false
    }
    try @xfs.write_bytes_to_file(dst, @xfs.read_file_to_bytes(src)) catch {
      _ => false
    } noraise {
      _ => true
    }
  }
}

///|
fn exec_clear_dir_contents(path : String) -> Bool {
  if not(ensure_exec_dir_recursive(path)) {
    return false
  }
  let entries = try @xfs.read_dir(path) catch {
    _ => []
  } noraise {
    value => value
  }
  for entry in entries {
    if not(exec_remove_tree(path + "/" + entry)) {
      return false
    }
  }
  true
}

///|
fn exec_copy_dir_contents(src : String, dst : String) -> Bool {
  if not(exec_clear_dir_contents(dst)) {
    return false
  }
  let entries = try @xfs.read_dir(src) catch {
    _ => []
  } noraise {
    value => value
  }
  for entry in entries {
    if not(exec_copy_tree(src + "/" + entry, dst + "/" + entry)) {
      return false
    }
  }
  true
}

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
fn parse_checkout_cone_mode(value : String) -> Bool {
  let normalized = value.trim(chars=" \t\r\n").to_lower()
  normalized != "false" && normalized != "0" && normalized != "no"
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
fn parse_checkout_clean(value : String) -> Bool {
  let normalized = value.trim(chars=" \t\r\n").to_lower()
  normalized != "false" && normalized != "0" && normalized != "no"
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
fn normalize_setup_node_registry_url(value : String) -> String {
  let trimmed = value.trim(chars=" \t\r\n").to_string()
  if trimmed.length() == 0 {
    ""
  } else if trimmed.has_suffix("/") {
    trimmed
  } else {
    trimmed + "/"
  }
}

///|
fn normalize_setup_node_version(
  value : String,
  current_version : String,
) -> String {
  let trimmed = value.trim(chars=" \t\r\n").to_string()
  if trimmed.length() == 0 {
    return current_version
  }
  let bare = if trimmed.has_prefix("v") {
    exec_text_slice(trimmed, 1, trimmed.length())
  } else {
    trimmed
  }
  let first = bare.split(".").next().unwrap_or("").to_string()
  let mut digits = ""
  for c in first {
    if c >= '0' && c <= '9' {
      digits += c.to_string()
    } else {
      break
    }
  }
  if digits.length() == 0 {
    return current_version
  }
  let parts : Array[String] = []
  for part_view in bare.split(".") {
    let part = part_view.to_string()
    if part.length() == 0 {
      continue
    }
    if part == "x" || part == "*" {
      break
    }
    let mut numeric = ""
    for c in part {
      if c >= '0' && c <= '9' {
        numeric += c.to_string()
      } else {
        break
      }
    }
    if numeric.length() == 0 {
      break
    }
    parts.push(numeric)
  }
  let major = parts.get(0).unwrap_or(digits)
  let minor = parts.get(1).unwrap_or("0")
  let patch = parts.get(2).unwrap_or("0")
  "v" + major + "." + minor + "." + patch
}

///|
fn checkout_temp_root(workspace_root : String, task_id : String) -> String {
  ignore(ensure_exec_dir_recursive("_build/action_runner/checkouts"))
  let workspace_key = sanitize_task_id(
    absolute_exec_path(resolve_task_cwd(workspace_root, "")),
  )
  let root = absolute_exec_path(
    "_build/action_runner/checkouts/" +
    workspace_key +
    "/" +
    sanitize_task_id(task_id),
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
  let (code, stdout, stderr) = @process.collect_output(git_bin, args, cwd~)
  (code, stdout.text(), stderr.text())
}

///|
async fn exec_git_list_files(git_bin : String, cwd : String) -> String? {
  let (code, stdout, _) = exec_git_command_text(git_bin, ["ls-files"], cwd)
  if code == 0 {
    Some(stdout)
  } else {
    None
  }
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
) -> (Int, String, String) {
  let args : Array[String] = ["clone", "--quiet", "--no-local"]
  if fetch_depth > 0 {
    args.push("--depth")
    args.push(fetch_depth.to_string())
  }
  if ref_name.length() > 0 {
    args.push("--branch")
    args.push(ref_name)
  }
  args.push("file://" + absolute_exec_path(source_root))
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
fn exec_remove_missing_tracked_files(
  destination : String,
  current_tracked : String,
  next_tracked : String,
) -> Bool {
  let next_map : Map[String, Bool] = {}
  for relative in split_nonempty_lines(next_tracked) {
    next_map[relative] = true
  }
  for relative in split_nonempty_lines(current_tracked) {
    if next_map.get(relative).unwrap_or(false) {
      continue
    }
    if not(exec_remove_tree(destination + "/" + relative)) {
      return false
    }
  }
  true
}

///|
fn exec_copy_dir_contents_preserving_untracked(
  src : String,
  dst : String,
  current_tracked : String,
  next_tracked : String,
) -> Bool {
  if not(ensure_exec_dir_recursive(dst)) {
    return false
  }
  if not(exec_remove_tree(dst + "/.git")) {
    return false
  }
  if not(exec_copy_tree(src + "/.git", dst + "/.git")) {
    return false
  }
  if not(exec_remove_missing_tracked_files(dst, current_tracked, next_tracked)) {
    return false
  }
  let entries = try @xfs.read_dir(src) catch {
    _ => []
  } noraise {
    value => value
  }
  for entry in entries {
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
async fn exec_git_clone_checkout(
  plan : TaskPlan,
  workspace_root : String,
  source_root : String,
  checkout_root : String,
  fetch_depth : Int,
  clean : Bool,
  resolved_plan_env : Map[String, String],
) -> TaskRunReport? {
  let temp_root = checkout_temp_root(workspace_root, plan.id)
  let git_bin = configured_exec_bin(
    "ACTION_RUNNER_GIT_BIN", resolved_plan_env, "git",
  )
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
          git_bin, source_root, temp_root, 0,
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
      git_bin, source_root, temp_root, fetch_depth,
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
            git_bin, source_root, temp_root, 0,
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
  if not(clean) && checkout_root == source_root {
    guard exec_git_list_files(git_bin, source_root) is Some(current_tracked) else {
      return Some(
        task_report_failure(
          plan, workspace_root, "failed to inspect tracked files before checkout",
        ),
      )
    }
    guard exec_git_list_files(git_bin, temp_root) is Some(next_tracked) else {
      return Some(
        task_report_failure(
          plan, workspace_root, "failed to inspect tracked files after checkout clone",
        ),
      )
    }
    if not(
        exec_copy_dir_contents_preserving_untracked(
          temp_root, checkout_root, current_tracked, next_tracked,
        ),
      ) {
      return Some(
        task_report_failure(
          plan, workspace_root, "failed to materialize checkout contents",
        ),
      )
    }
    return None
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
fn artifact_store_root(workspace_root : String) -> String {
  ignore(ensure_exec_dir_recursive("_build/action_runner/artifacts"))
  let workspace_key = sanitize_task_id(
    absolute_exec_path(resolve_task_cwd(workspace_root, "")),
  )
  let root = absolute_exec_path(
    "_build/action_runner/artifacts/" + workspace_key,
  )
  ignore(ensure_exec_dir_recursive(root))
  root
}

///|
fn cache_store_root(workspace_root : String) -> String {
  ignore(ensure_exec_dir_recursive("_build/action_runner/cache"))
  let workspace_key = sanitize_task_id(
    absolute_exec_path(resolve_task_cwd(workspace_root, "")),
  )
  let root = absolute_exec_path("_build/action_runner/cache/" + workspace_key)
  ignore(ensure_exec_dir_recursive(root))
  root
}

///|
fn setup_node_store_root(workspace_root : String) -> String {
  ignore(ensure_exec_dir_recursive("_build/action_runner/setup_node"))
  let workspace_key = sanitize_task_id(
    absolute_exec_path(resolve_task_cwd(workspace_root, "")),
  )
  let root = absolute_exec_path(
    "_build/action_runner/setup_node/" + workspace_key,
  )
  ignore(ensure_exec_dir_recursive(root))
  root
}

///|
async fn exec_make_executable(path : String) -> Bool {
  let (code, _, _) = @process.collect_output("chmod", ["+x", path], cwd=".")
  code == 0
}

///|
async fn write_setup_node_shim(
  workspace_root : String,
  task_id : String,
  node_bin : String,
  node_version : String,
) -> String? {
  let shim_root = setup_node_store_root(workspace_root) +
    "/" +
    sanitize_task_id(task_id)
  let shim_dir = shim_root + "/bin"
  if not(ensure_exec_dir_recursive(shim_dir)) {
    return None
  }
  let shim_path = shim_dir + "/node"
  let script = "#!/bin/sh\n" +
    "set -eu\n" +
    "if [ \"${1:-}\" = \"--version\" ] || [ \"${1:-}\" = \"-v\" ]; then\n" +
    "  printf '%s\\n' '" +
    node_version +
    "'\n" +
    "  exit 0\n" +
    "fi\n" +
    "exec '" +
    node_bin.replace_all(old="'", new="'\"'\"'") +
    "' \"$@\"\n"
  if not(write_exec_text(shim_path, script)) {
    return None
  }
  if not(exec_make_executable(shim_path)) {
    return None
  }
  Some(shim_dir)
}

///|
fn write_setup_node_npmrc(path : String, registry_url : String) -> Bool {
  let stripped = if registry_url.has_prefix("https://") {
    "//" + exec_text_slice(registry_url, 8, registry_url.length())
  } else if registry_url.has_prefix("http://") {
    "//" + exec_text_slice(registry_url, 7, registry_url.length())
  } else {
    registry_url
  }
  write_exec_text(
    path,
    stripped + ":_authToken=${NODE_AUTH_TOKEN}\n" + "registry=" + registry_url,
  )
}

///|
fn setup_node_cache_relative_path(cache_name : String) -> String {
  ".setup-node/" + cache_name + "-cache"
}

///|
fn setup_node_default_dependency_paths(cache_name : String) -> Array[String] {
  if cache_name == "npm" {
    ["package-lock.json", "npm-shrinkwrap.json"]
  } else {
    []
  }
}

///|
priv enum SetupNodeDependencyResolution {
  Ok(Array[String])
  Err(String)
}

///|
fn resolve_setup_node_dependency_paths(
  workspace_root : String,
  cache_name : String,
  dependency_input : String,
) -> SetupNodeDependencyResolution {
  let candidates = if dependency_input.trim(chars=" \t\r\n").length() > 0 {
    split_nonempty_lines(dependency_input)
  } else {
    setup_node_default_dependency_paths(cache_name)
  }
  if candidates.length() == 0 {
    return Err(
      "setup-node cache '\{cache_name}' requires cache-dependency-path or a default lockfile",
    )
  }
  let resolved : Array[String] = []
  let explicit = dependency_input.trim(chars=" \t\r\n").length() > 0
  for candidate in candidates {
    let resolved_path = resolve_task_cwd(workspace_root, candidate)
    if explicit && not(@xfs.path_exists(resolved_path)) {
      return Err(
        "setup-node cache dependency path '\{candidate}' does not exist",
      )
    }
    if not(@xfs.path_exists(resolved_path)) {
      continue
    }
    guard workspace_relative_store_path(workspace_root, resolved_path)
      is Some(relative_path) else {
      return Err(
        "setup-node cache dependency path '\{candidate}' must stay within the workspace",
      )
    }
    resolved.push(relative_path)
  }
  if resolved.length() == 0 {
    Err("setup-node cache '\{cache_name}' found no dependency files")
  } else {
    Ok(resolved)
  }
}

///|
fn setup_node_cache_key_text(
  workspace_root : String,
  cache_name : String,
  dependency_paths : Array[String],
) -> String? {
  let parts : Array[String] = []
  parts.push("cache=" + cache_name)
  for relative_path in dependency_paths {
    let resolved_path = resolve_task_cwd(workspace_root, relative_path)
    guard read_exec_text(resolved_path) is Some(content) else { return None }
    parts.push("--")
    parts.push(relative_path)
    parts.push(content)
  }
  Some(parts.join("\n"))
}

///|
fn stable_setup_node_hash(text : String) -> String {
  let mut hash = 7
  let mut idx = 0
  while idx < text.length() {
    hash = (hash * 131 + text.unsafe_get(idx).to_int()) % 2147483647
    idx += 1
  }
  hash.to_string()
}

///|
fn compute_setup_node_cache_key(
  workspace_root : String,
  cache_name : String,
  dependency_paths : Array[String],
) -> String? {
  guard setup_node_cache_key_text(workspace_root, cache_name, dependency_paths)
    is Some(key_text) else {
    return None
  }
  Some("setup-node-" + cache_name + "-" + stable_setup_node_hash(key_text))
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
fn split_nonempty_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for line_view in text.split("\n") {
    let line = line_view.trim(chars=" \t\r").to_string()
    if line.length() > 0 {
      lines.push(line)
    }
  }
  lines
}

///|
fn builtin_task_result(report : TaskRunReport) -> TaskExecutionResult {
  {
    report,
    env_updates: {},
    path_entries: [],
    output_values: {},
    state_updates: {},
  }
}

///|
#cfg(target="native")
async fn execute_builtin_checkout_native(
  action : ResolvedAction,
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
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
  let clean = parse_checkout_clean(
    resolved_plan_env.get("INPUT_CLEAN").unwrap_or("true"),
  )
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
  let cone_mode = parse_checkout_cone_mode(
    resolved_plan_env.get("INPUT_SPARSE_CHECKOUT_CONE_MODE").unwrap_or("true"),
  )
  let source_root = resolve_task_cwd(workspace_root, "")
  let checkout_root = if path_input.length() > 0 {
    resolve_task_cwd(workspace_root, path_input)
  } else {
    source_root
  }
  if exec_has_git_repo(source_root) {
    match
      exec_git_clone_checkout(
        plan, workspace_root, source_root, checkout_root, fetch_depth, clean, resolved_plan_env,
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

///|
#cfg(target="native")
async fn execute_setup_node_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskExecutionResult {
  let cache_input = resolved_plan_env.get("INPUT_CACHE").unwrap_or("")
  let normalized_cache_input = cache_input.trim(chars=" \t\r\n").to_string()
  let requested_node_file = resolved_plan_env
    .get("INPUT_NODE_VERSION_FILE")
    .unwrap_or("")
  if requested_node_file.trim(chars=" \t\r\n").length() > 0 {
    return {
      report: task_report_failure(
        plan, workspace_root, "setup-node node-version-file is not supported yet",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  let configured_node_fallback = resolved_plan_env
    .get("ACTION_RUNNER_NODE_BIN")
    .unwrap_or(@xsys.get_env_var("ACTION_RUNNER_NODE_BIN").unwrap_or("node"))
  let fallback_node_bin = resolve_exec_bin_for_workspace(
    configured_node_fallback, workspace_root,
  )
  let configured_setup_node_bin = resolved_plan_env
    .get("ACTION_RUNNER_SETUP_NODE_BIN")
    .unwrap_or(
      @xsys.get_env_var("ACTION_RUNNER_SETUP_NODE_BIN").unwrap_or(
        fallback_node_bin,
      ),
    )
  let node_bin = resolve_exec_bin_for_workspace(
    configured_setup_node_bin, workspace_root,
  )
  let (version_code, version_stdout, version_stderr) = @process.collect_output(
    node_bin,
    ["--version"],
    cwd=resolve_task_cwd(workspace_root, ""),
  )
  if version_code != 0 {
    return {
      report: task_report_failure(
        plan,
        workspace_root,
        exec_command_message(
          version_stdout.text(),
          version_stderr.text(),
          "failed to inspect node version",
        ),
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  let actual_version = version_stdout.text().trim(chars=" \t\r\n").to_string()
  let node_version = normalize_setup_node_version(
    resolved_plan_env.get("INPUT_NODE_VERSION").unwrap_or(""),
    actual_version,
  )
  guard write_setup_node_shim(workspace_root, plan.id, node_bin, node_version)
    is Some(shim_dir) else {
    return {
      report: task_report_failure(
        plan, workspace_root, "failed to prepare setup-node shim",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  let env_updates : Map[String, String] = {}
  let output_values : Map[String, String] = { "node-version": node_version }
  let state_updates : Map[String, String] = {}
  if normalized_cache_input.length() > 0 {
    if normalized_cache_input != "npm" {
      return {
        report: task_report_failure(
          plan,
          workspace_root,
          "setup-node cache '\{normalized_cache_input}' is not supported yet",
        ),
        env_updates: {},
        path_entries: [],
        output_values: {},
        state_updates: {},
      }
    }
    let dependency_input = resolved_plan_env
      .get("INPUT_CACHE_DEPENDENCY_PATH")
      .unwrap_or("")
    let dependency_paths = match
      resolve_setup_node_dependency_paths(
        workspace_root, normalized_cache_input, dependency_input,
      ) {
      Ok(paths) => paths
      Err(message) =>
        return {
          report: task_report_failure(plan, workspace_root, message),
          env_updates: {},
          path_entries: [],
          output_values: {},
          state_updates: {},
        }
    }
    guard compute_setup_node_cache_key(
        workspace_root, normalized_cache_input, dependency_paths,
      )
      is Some(cache_key) else {
      return {
        report: task_report_failure(
          plan, workspace_root, "failed to compute setup-node cache key",
        ),
        env_updates: {},
        path_entries: [],
        output_values: {},
        state_updates: {},
      }
    }
    let cache_relative_path = setup_node_cache_relative_path(
      normalized_cache_input,
    )
    let cache_abs_path = resolve_task_cwd(workspace_root, cache_relative_path)
    if not(ensure_exec_dir_recursive(cache_abs_path)) {
      return {
        report: task_report_failure(
          plan, workspace_root, "failed to prepare setup-node cache directory",
        ),
        env_updates: {},
        path_entries: [],
        output_values: {},
        state_updates: {},
      }
    }
    let cache_result = execute_restore_cache_native(plan, workspace_root, {
      "INPUT_KEY": cache_key,
      "INPUT_PATH": cache_relative_path,
    })
    if cache_result.report.status != "success" {
      return cache_result
    }
    let cache_hit = cache_result.output_values
      .get("cache-hit")
      .unwrap_or("false")
    env_updates["NPM_CONFIG_CACHE"] = cache_abs_path
    env_updates["npm_config_cache"] = cache_abs_path
    output_values["cache-hit"] = cache_hit
    state_updates["SETUP_NODE_CACHE_NAME"] = normalized_cache_input
    state_updates["SETUP_NODE_CACHE_KEY"] = cache_key
    state_updates["SETUP_NODE_CACHE_PATH"] = cache_relative_path
    state_updates["SETUP_NODE_CACHE_HIT"] = cache_hit
  }
  let registry_url = normalize_setup_node_registry_url(
    resolved_plan_env.get("INPUT_REGISTRY_URL").unwrap_or(""),
  )
  if registry_url.length() > 0 {
    let npmrc_path = prepare_runner_temp_dir(plan.job_id, workspace_root) +
      "/.npmrc"
    if not(write_setup_node_npmrc(npmrc_path, registry_url)) {
      return {
        report: task_report_failure(
          plan, workspace_root, "failed to write setup-node npm auth config",
        ),
        env_updates: {},
        path_entries: [],
        output_values: {},
        state_updates: {},
      }
    }
    let node_auth_token = resolved_plan_env
      .get("NODE_AUTH_TOKEN")
      .unwrap_or(
        @xsys.get_env_var("NODE_AUTH_TOKEN").unwrap_or(
          "XXXXX-XXXXX-XXXXX-XXXXX",
        ),
      )
    env_updates["NPM_CONFIG_USERCONFIG"] = npmrc_path
    env_updates["NODE_AUTH_TOKEN"] = node_auth_token
  }
  {
    report: task_report_success(plan, workspace_root),
    env_updates,
    path_entries: [shim_dir],
    output_values,
    state_updates,
  }
}

///|
#cfg(target="native")
fn execute_setup_node_cache_post_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
  state : JobRuntimeState,
) -> TaskRunReport {
  let saved_state = action_scope_state(state, plan.action_scope)
  if saved_state.length() == 0 {
    return task_report_success(plan, workspace_root)
  }
  if saved_state.get("SETUP_NODE_CACHE_HIT").unwrap_or("") == "true" {
    return task_report_success(plan, workspace_root)
  }
  let cache_name = saved_state
    .get("SETUP_NODE_CACHE_NAME")
    .unwrap_or(resolved_plan_env.get("INPUT_CACHE").unwrap_or(""))
  let path_input = saved_state
    .get("SETUP_NODE_CACHE_PATH")
    .unwrap_or(
      setup_node_cache_relative_path(
        cache_name.trim(chars=" \t\r\n").to_string(),
      ),
    )
  let key = saved_state.get("SETUP_NODE_CACHE_KEY").unwrap_or("")
  if key.length() == 0 {
    return task_report_success(plan, workspace_root)
  }
  let resolved_path = resolve_task_cwd(workspace_root, path_input)
  if not(@xfs.path_exists(resolved_path)) {
    return task_report_success(plan, workspace_root)
  }
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
#cfg(target="native")
fn execute_upload_artifact_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskRunReport {
  let name = resolved_plan_env.get("INPUT_NAME").unwrap_or("")
  let path_input = resolved_plan_env.get("INPUT_PATH").unwrap_or("")
  if name.length() == 0 {
    return task_report_failure(
      plan, workspace_root, "upload-artifact requires with.name",
    )
  }
  let upload_paths = split_nonempty_lines(path_input)
  if upload_paths.length() == 0 {
    return task_report_failure(
      plan, workspace_root, "upload-artifact requires with.path",
    )
  }
  let artifact_root = artifact_store_root(workspace_root) +
    "/" +
    sanitize_task_id(name)
  if not(exec_remove_tree(artifact_root)) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to clear artifact store for '\{name}'",
    )
  }
  if not(ensure_exec_dir_recursive(artifact_root)) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to prepare artifact store for '\{name}'",
    )
  }
  let mut copied = false
  for input_path in upload_paths {
    let resolved_path = resolve_task_cwd(workspace_root, input_path)
    if not(@xfs.path_exists(resolved_path)) {
      continue
    }
    let leaf = exec_leaf_name(resolved_path)
    let target = if leaf.length() > 0 {
      artifact_root + "/" + leaf
    } else {
      artifact_root
    }
    if not(exec_copy_tree(resolved_path, target)) {
      return task_report_failure(
        plan,
        workspace_root,
        "failed to upload artifact path '\{input_path}'",
      )
    }
    copied = true
  }
  if not(copied) {
    return task_report_failure(
      plan,
      workspace_root,
      "upload-artifact found no files for '\{path_input}'",
    )
  }
  task_report_success(plan, workspace_root)
}

///|
#cfg(target="native")
fn execute_download_artifact_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskRunReport {
  let name = resolved_plan_env.get("INPUT_NAME").unwrap_or("")
  let path_input = resolved_plan_env.get("INPUT_PATH").unwrap_or("")
  if name.length() == 0 {
    return task_report_failure(
      plan, workspace_root, "download-artifact requires with.name",
    )
  }
  let artifact_root = artifact_store_root(workspace_root) +
    "/" +
    sanitize_task_id(name)
  if not(@xfs.path_exists(artifact_root)) {
    return task_report_failure(
      plan,
      workspace_root,
      "download-artifact could not find artifact '\{name}'",
    )
  }
  let destination = if path_input.length() > 0 {
    resolve_task_cwd(workspace_root, path_input)
  } else {
    resolve_task_cwd(workspace_root, "")
  }
  if not(ensure_exec_dir_recursive(destination)) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to prepare artifact download dir '\{destination}'",
    )
  }
  let entries = try @xfs.read_dir(artifact_root) catch {
    _ => []
  } noraise {
    value => value
  }
  for entry in entries {
    if not(
        exec_copy_tree(artifact_root + "/" + entry, destination + "/" + entry),
      ) {
      return task_report_failure(
        plan,
        workspace_root,
        "failed to download artifact '\{name}'",
      )
    }
  }
  task_report_success(plan, workspace_root)
}

///|
#cfg(target="native")
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
  let cache_paths = split_nonempty_lines(path_input)
  if cache_paths.length() == 0 {
    return task_report_failure(
      plan, workspace_root, "cache-save requires with.path",
    )
  }
  let cache_root = cache_store_root(workspace_root) +
    "/" +
    sanitize_task_id(key)
  if not(exec_remove_tree(cache_root)) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to clear cache store for '\{key}'",
    )
  }
  if not(ensure_exec_dir_recursive(cache_root)) {
    return task_report_failure(
      plan,
      workspace_root,
      "failed to prepare cache store for '\{key}'",
    )
  }
  let mut copied = false
  for input_path in cache_paths {
    let resolved_path = resolve_task_cwd(workspace_root, input_path)
    if not(@xfs.path_exists(resolved_path)) {
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
    if not(exec_copy_tree(resolved_path, target)) {
      return task_report_failure(
        plan,
        workspace_root,
        "failed to save cache path '\{input_path}'",
      )
    }
    copied = true
  }
  if not(copied) {
    return task_report_failure(
      plan,
      workspace_root,
      "cache-save found no files for '\{path_input}'",
    )
  }
  task_report_success(plan, workspace_root)
}

///|
#cfg(target="native")
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
  {
    report: task_report_failure(plan, workspace_root, message),
    env_updates: {},
    path_entries: [],
    output_values: {},
    state_updates: {},
  }
}

///|
#cfg(target="native")
fn restore_cache_store_native(workspace_root : String, key : String) -> Bool? {
  let cache_root = cache_store_root(workspace_root) +
    "/" +
    sanitize_task_id(key)
  if not(@xfs.path_exists(cache_root)) {
    return Some(false)
  }
  let entries = try @xfs.read_dir(cache_root) catch {
    _ => []
  } noraise {
    value => value
  }
  for entry in entries {
    let source = cache_root + "/" + entry
    if entry == "__root__" {
      let root_entries = try @xfs.read_dir(source) catch {
        _ => []
      } noraise {
        value => value
      }
      for root_entry in root_entries {
        if not(
            exec_copy_tree(
              source + "/" + root_entry,
              workspace_root + "/" + root_entry,
            ),
          ) {
          return None
        }
      }
    } else if not(exec_copy_tree(source, workspace_root + "/" + entry)) {
      return None
    }
  }
  Some(true)
}

///|
#cfg(target="native")
fn execute_restore_cache_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskExecutionResult {
  let key = resolved_plan_env.get("INPUT_KEY").unwrap_or("")
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
  let cache_hit = match restore_cache_store_native(workspace_root, key) {
    Some(value) => value
    None =>
      return {
        report: task_report_failure(
          plan,
          workspace_root,
          "failed to restore cache '\{key}'",
        ),
        env_updates: {},
        path_entries: [],
        output_values: {},
        state_updates: {},
      }
  }
  {
    report: task_report_success(plan, workspace_root),
    env_updates: {},
    path_entries: [],
    output_values: { "cache-hit": if cache_hit { "true" } else { "false" } },
    state_updates: {},
  }
}

///|
#cfg(target="native")
fn execute_cache_action_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskExecutionResult {
  let key = resolved_plan_env.get("INPUT_KEY").unwrap_or("")
  let path_input = resolved_plan_env.get("INPUT_PATH").unwrap_or("")
  if key.length() == 0 {
    return cache_input_result_failure(plan, workspace_root, "cache", true)
  }
  if split_nonempty_lines(path_input).length() == 0 {
    return cache_input_result_failure(plan, workspace_root, "cache", false)
  }
  let cache_hit = match restore_cache_store_native(workspace_root, key) {
    Some(value) => value
    None =>
      return {
        report: task_report_failure(
          plan,
          workspace_root,
          "failed to restore cache '\{key}'",
        ),
        env_updates: {},
        path_entries: [],
        output_values: {},
        state_updates: {},
      }
  }
  {
    report: task_report_success(plan, workspace_root),
    env_updates: {},
    path_entries: [],
    output_values: { "cache-hit": if cache_hit { "true" } else { "" } },
    state_updates: {
      "CACHE_KEY": key,
      "CACHE_PATH": path_input,
      "CACHE_HIT": if cache_hit {
        "true"
      } else {
        ""
      },
    },
  }
}

///|
#cfg(target="native")
fn execute_cache_post_save_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
  state : JobRuntimeState,
) -> TaskRunReport {
  let saved_state = action_scope_state(state, plan.action_scope)
  if saved_state.get("CACHE_HIT").unwrap_or("") == "true" {
    return task_report_success(plan, workspace_root)
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
#cfg(target="native")
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

///|
#cfg(target="native")
fn configured_exec_bin(
  env_name : String,
  resolved_plan_env : Map[String, String],
  fallback : String,
) -> String {
  let configured = resolved_plan_env
    .get(env_name)
    .unwrap_or(@xsys.get_env_var(env_name).unwrap_or(fallback))
  if configured.contains("/") {
    absolute_exec_path(configured)
  } else {
    configured
  }
}

///|
#cfg(target="native")
fn resolve_exec_bin_for_workspace(
  configured : String,
  workspace_root : String,
) -> String {
  if configured.contains("/") {
    if configured.has_prefix("/") {
      configured
    } else {
      resolve_task_cwd(workspace_root, configured)
    }
  } else {
    configured
  }
}

///|
#cfg(target="native")
async fn execute_node_action_native(
  workflow_name : String,
  plan : TaskPlan,
  action : ResolvedAction,
  workspace_root : String,
  state : JobRuntimeState,
  needs_outputs : Map[String, Map[String, String]],
  needs_results : Map[String, String],
  push_event : PushEvent?,
) -> TaskExecutionResult {
  guard action.entrypoint is Some(entrypoint) else {
    return {
      report: task_report_failure(
        plan, workspace_root, "node action is missing an entrypoint",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  guard prepare_step_file_commands(plan.id, workspace_root)
    is Some(file_commands) else {
    return {
      report: task_report_failure(
        plan, workspace_root, "failed to prepare step file commands",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  let github_ctx = github_context(
    workflow_name, plan, workspace_root, push_event,
  )
  let runner_ctx = runner_context(plan, workspace_root)
  let resolved_plan_env = resolve_plan_env(
    plan, state, workspace_root, github_ctx, runner_ctx, needs_outputs, needs_results,
  )
  let env = default_runner_env(
    workflow_name, plan, workspace_root, github_ctx, resolved_plan_env, file_commands,
    runner_ctx,
  )
  let cmd = configured_exec_bin(
    "ACTION_RUNNER_NODE_BIN", resolved_plan_env, "node",
  )
  let cwd = action.action_path.unwrap_or(resolve_task_cwd(workspace_root, ""))
  let env_args = env_command_args(cmd, [entrypoint], env)
  let (code, stdout, stderr) = @process.collect_output("env", env_args, cwd~)
  {
    report: {
      id: plan.id,
      kind: plan.kind,
      status: if code == 0 {
        "success"
      } else {
        "failed"
      },
      code,
      shell: plan.shell,
      script: plan.script,
      cwd,
      stdout: stdout.text(),
      stderr: stderr.text(),
      summary: parse_summary_text(file_commands.summary_path),
    },
    env_updates: parse_env_updates(file_commands.env_path),
    path_entries: parse_path_updates(file_commands.path_path),
    output_values: parse_output_values(file_commands.output_path),
    state_updates: parse_state_values(file_commands.state_path),
  }
}

///|
#cfg(target="native")
async fn execute_docker_action_native(
  workflow_name : String,
  plan : TaskPlan,
  action : ResolvedAction,
  workspace_root : String,
  state : JobRuntimeState,
  needs_outputs : Map[String, Map[String, String]],
  needs_results : Map[String, String],
  push_event : PushEvent?,
) -> TaskExecutionResult {
  guard action.image is Some(image_source) else {
    return {
      report: task_report_failure(
        plan, workspace_root, "docker action is missing an image",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  guard prepare_step_file_commands(plan.id, workspace_root)
    is Some(file_commands) else {
    return {
      report: task_report_failure(
        plan, workspace_root, "failed to prepare step file commands",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  let github_ctx = github_context(
    workflow_name, plan, workspace_root, push_event,
  )
  let runner_ctx = runner_context(plan, workspace_root)
  let resolved_plan_env = resolve_plan_env(
    plan, state, workspace_root, github_ctx, runner_ctx, needs_outputs, needs_results,
  )
  let env = default_runner_env(
    workflow_name, plan, workspace_root, github_ctx, resolved_plan_env, file_commands,
    runner_ctx,
  )
  let docker_bin = configured_exec_bin(
    "ACTION_RUNNER_DOCKER_BIN", resolved_plan_env, "docker",
  )
  let workspace_abs = absolute_exec_path(resolve_task_cwd(workspace_root, ""))
  let container_cwd = absolute_exec_path(
    resolve_task_cwd(workspace_root, plan.working_directory),
  )
  let image_to_run = if @xfs.path_exists(image_source) {
    let action_root = action.action_path.unwrap_or(workspace_abs)
    let built_tag = "action-runner-" + sanitize_task_id(plan.id).to_lower()
    let build_args = ["build", "-f", image_source, "-t", built_tag, action_root]
    let (build_code, build_stdout, build_stderr) = @process.collect_output(
      docker_bin,
      build_args,
      cwd=action_root,
    )
    if build_code != 0 {
      return {
        report: {
          id: plan.id,
          kind: plan.kind,
          status: "failed",
          code: build_code,
          shell: plan.shell,
          script: plan.script,
          cwd: action_root,
          stdout: build_stdout.text(),
          stderr: build_stderr.text(),
          summary: "",
        },
        env_updates: {},
        path_entries: [],
        output_values: {},
        state_updates: {},
      }
    }
    built_tag
  } else {
    image_source
  }
  let run_args : Array[String] = [
    "run",
    "--rm",
    "-v",
    workspace_abs + ":" + workspace_abs,
    "-v",
    absolute_exec_path("_build/action_runner") +
    ":" +
    absolute_exec_path("_build/action_runner"),
    "-w",
    container_cwd,
  ]
  for key, value in env {
    run_args.push("-e")
    run_args.push(key + "=" + value)
  }
  match action.entrypoint {
    Some(entrypoint) if entrypoint.length() > 0 => {
      run_args.push("--entrypoint")
      run_args.push(entrypoint)
    }
    _ => ()
  }
  run_args.push(image_to_run)
  for arg in action.args {
    run_args.push(arg)
  }
  let (code, stdout, stderr) = @process.collect_output(
    docker_bin,
    run_args,
    cwd=workspace_abs,
  )
  {
    report: {
      id: plan.id,
      kind: plan.kind,
      status: if code == 0 {
        "success"
      } else {
        "failed"
      },
      code,
      shell: plan.shell,
      script: plan.script,
      cwd: container_cwd,
      stdout: stdout.text(),
      stderr: stderr.text(),
      summary: parse_summary_text(file_commands.summary_path),
    },
    env_updates: parse_env_updates(file_commands.env_path),
    path_entries: parse_path_updates(file_commands.path_path),
    output_values: parse_output_values(file_commands.output_path),
    state_updates: parse_state_values(file_commands.state_path),
  }
}

///|
#cfg(target="native")
async fn execute_action_plan_native(
  workflow_name : String,
  plan : TaskPlan,
  workspace_root : String,
  state : JobRuntimeState,
  needs_outputs : Map[String, Map[String, String]],
  needs_results : Map[String, String],
  push_event : PushEvent?,
) -> TaskExecutionResult {
  guard plan.action is Some(action) else {
    return {
      report: task_report_failure(
        plan, workspace_root, "missing action metadata",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  if action.backend == "builtin" {
    let github_ctx = github_context(
      workflow_name, plan, workspace_root, push_event,
    )
    let runner_ctx = runner_context(plan, workspace_root)
    let resolved_plan_env = resolve_plan_env(
      plan, state, workspace_root, github_ctx, runner_ctx, needs_outputs, needs_results,
    )
    if action.kind == "checkout" {
      return builtin_task_result(
        execute_builtin_checkout_native(
          action, plan, workspace_root, resolved_plan_env,
        ),
      )
    }
    if action.kind == "setup-node" {
      return execute_setup_node_native(plan, workspace_root, resolved_plan_env)
    }
    if action.kind == "setup-node-cache-post" {
      return builtin_task_result(
        execute_setup_node_cache_post_native(
          plan, workspace_root, resolved_plan_env, state,
        ),
      )
    }
    if action.kind == "upload-artifact" {
      return builtin_task_result(
        execute_upload_artifact_native(plan, workspace_root, resolved_plan_env),
      )
    }
    if action.kind == "download-artifact" {
      return builtin_task_result(
        execute_download_artifact_native(
          plan, workspace_root, resolved_plan_env,
        ),
      )
    }
    if action.kind == "cache" ||
      action.kind == "cache-save" ||
      action.kind == "cache-restore" ||
      action.kind == "cache-save-post" {
      return execute_cache_builtin_native(
        plan,
        workspace_root,
        resolved_plan_env,
        state,
        action.kind,
      )
    }
    return builtin_task_result(
      task_report_failure(
        plan,
        workspace_root,
        "builtin action kind '\{action.kind}' is not supported",
      ),
    )
  }
  if action.backend == "node" {
    return execute_node_action_native(
      workflow_name, plan, action, workspace_root, state, needs_outputs, needs_results,
      push_event,
    )
  }
  if action.backend == "docker" {
    return execute_docker_action_native(
      workflow_name, plan, action, workspace_root, state, needs_outputs, needs_results,
      push_event,
    )
  }
  {
    report: task_report_failure(
      plan,
      workspace_root,
      "action backend '\{action.backend}' is not supported",
    ),
    env_updates: {},
    path_entries: [],
    output_values: {},
    state_updates: {},
  }
}

///|
#cfg(target="native")
fn default_runner_env(
  workflow_name : String,
  plan : TaskPlan,
  workspace_root : String,
  github_context : Map[String, String],
  resolved_plan_env : Map[String, String],
  file_commands : StepFileCommands,
  runner_context : Map[String, String],
) -> Map[String, String] {
  let runner_env : Map[String, String] = {
    "CI": "true",
    "GITHUB_ACTION": github_context.get("action").unwrap_or(""),
    "GITHUB_ACTIONS": "true",
    "GITHUB_ACTOR": github_context.get("actor").unwrap_or(""),
    "GITHUB_ENV": file_commands.env_path,
    "GITHUB_EVENT_NAME": github_context.get("event_name").unwrap_or(""),
    "GITHUB_JOB": plan.job_id,
    "GITHUB_OUTPUT": file_commands.output_path,
    "GITHUB_PATH": file_commands.path_path,
    "GITHUB_REF": github_context.get("ref").unwrap_or(""),
    "GITHUB_REF_NAME": github_context.get("ref_name").unwrap_or(""),
    "GITHUB_REPOSITORY": github_context.get("repository").unwrap_or(""),
    "GITHUB_REPOSITORY_OWNER": github_context
    .get("repository_owner")
    .unwrap_or(""),
    "GITHUB_SHA": github_context.get("sha").unwrap_or(""),
    "GITHUB_STEP_SUMMARY": file_commands.summary_path,
    "GITHUB_WORKFLOW": workflow_name,
    "GITHUB_WORKSPACE": absolute_exec_path(resolve_task_cwd(workspace_root, "")),
    "RUNNER_ARCH": runner_context.get("arch").unwrap_or(""),
    "RUNNER_ENVIRONMENT": runner_context.get("environment").unwrap_or(""),
    "RUNNER_OS": runner_context.get("os").unwrap_or(""),
    "RUNNER_TEMP": runner_context.get("temp").unwrap_or(""),
  }
  match github_context.get("action_path") {
    Some(value) if value.length() > 0 =>
      runner_env["GITHUB_ACTION_PATH"] = value
    _ => ()
  }
  match github_context.get("action_repository") {
    Some(value) if value.length() > 0 =>
      runner_env["GITHUB_ACTION_REPOSITORY"] = value
    _ => ()
  }
  match github_context.get("action_ref") {
    Some(value) if value.length() > 0 => runner_env["GITHUB_ACTION_REF"] = value
    _ => ()
  }
  match plan.action_scope {
    Some(_) => runner_env["GITHUB_STATE"] = file_commands.state_path
    None => ()
  }
  merge_runner_env(resolved_plan_env, runner_env)
}

///|
#cfg(target="native")
async fn execute_task_plan_native(
  workflow_name : String,
  plan : TaskPlan,
  workspace_root : String,
  state : JobRuntimeState,
  needs_outputs : Map[String, Map[String, String]],
  needs_results : Map[String, String],
  push_event : PushEvent?,
) -> TaskExecutionResult {
  if plan.kind == "barrier" {
    return {
      report: task_report_success(plan, workspace_root),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  if plan.kind == "action" {
    return execute_action_plan_native(
      workflow_name, plan, workspace_root, state, needs_outputs, needs_results, push_event,
    )
  }
  guard prepare_step_file_commands(plan.id, workspace_root)
    is Some(file_commands) else {
    return {
      report: task_report_failure(
        plan, workspace_root, "failed to prepare step file commands",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  let github_ctx = github_context(
    workflow_name, plan, workspace_root, push_event,
  )
  let runner_ctx = runner_context(plan, workspace_root)
  let resolved_plan_env = resolve_plan_env(
    plan, state, workspace_root, github_ctx, runner_ctx, needs_outputs, needs_results,
  )
  let resolved_script = substitute_runtime_text(
    plan.script,
    state,
    workspace_root,
    resolved_plan_env,
    github_ctx,
    runner_ctx,
    needs_outputs,
    needs_results,
  )
  let resolved_shell = substitute_runtime_optional(
    Some(plan.shell),
    state,
    workspace_root,
    resolved_plan_env,
    github_ctx,
    runner_ctx,
    needs_outputs,
    needs_results,
  ).unwrap_or(plan.shell)
  let resolved_working_directory = substitute_runtime_optional(
    Some(plan.working_directory),
    state,
    workspace_root,
    resolved_plan_env,
    github_ctx,
    runner_ctx,
    needs_outputs,
    needs_results,
  ).unwrap_or(plan.working_directory)
  let unsupported_command = unsupported_workflow_command(plan, resolved_script)
  guard unsupported_command is None else {
    let command_name = unsupported_command.unwrap_or("")
    return {
      report: task_report_failure(
        plan,
        workspace_root,
        "workflow command '\{command_name}' is not supported in MVP",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  let cwd = resolve_task_cwd(workspace_root, resolved_working_directory)
  guard write_exec_text(file_commands.script_path, resolved_script) else {
    return {
      report: task_report_failure(
        plan, workspace_root, "failed to prepare step script file",
      ),
      env_updates: {},
      path_entries: [],
      output_values: {},
      state_updates: {},
    }
  }
  let (cmd, args) = shell_command(resolved_shell, file_commands.script_path)
  let env = default_runner_env(
    workflow_name, plan, workspace_root, github_ctx, resolved_plan_env, file_commands,
    runner_ctx,
  )
  let env_args = env_command_args(cmd, args, env)
  let (code, stdout, stderr) = @process.collect_output("env", env_args, cwd~)
  {
    report: {
      id: plan.id,
      kind: plan.kind,
      status: if code == 0 {
        "success"
      } else {
        "failed"
      },
      code,
      shell: cmd,
      script: resolved_script,
      cwd,
      stdout: stdout.text(),
      stderr: stderr.text(),
      summary: parse_summary_text(file_commands.summary_path),
    },
    env_updates: parse_env_updates(file_commands.env_path),
    path_entries: parse_path_updates(file_commands.path_path),
    output_values: parse_output_values(file_commands.output_path),
    state_updates: parse_state_values(file_commands.state_path),
  }
}

///|
#cfg(target="native")
pub async fn execute_lowered_native(
  lowered : LoweringResult,
  workspace_root? : String = ".",
  push_event? : PushEvent? = None,
) -> WorkflowRunReport {
  let issues = lowered_issues(lowered)
  if issues.length() > 0 {
    return make_invalid_report(issues)
  }

  let ir = lowered.ir
  let selected = selected_task_set(ir)
  let task_map = task_id_map(ir.tasks)
  let selected_tasks : Array[@wf.FlowTask] = []
  for task in ir.tasks {
    if selected.get(task.id) is Some(_) {
      selected_tasks.push(task)
    }
  }

  let remaining_deps : Map[String, Int] = {}
  let dependents : Map[String, Array[String]] = {}
  for task in selected_tasks {
    remaining_deps[task.id] = 0
    dependents[task.id] = []
  }
  for task in selected_tasks {
    let mut dep_count = 0
    for dep in task.needs {
      if selected.get(dep) is Some(_) {
        dep_count += 1
        let next = dependents.get(dep).unwrap_or([])
        next.push(task.id)
        dependents[dep] = next
      }
    }
    remaining_deps[task.id] = dep_count
  }

  let ready_queue : Array[String] = []
  for task in selected_tasks {
    if remaining_deps.get(task.id).unwrap_or(0) == 0 {
      ready_queue.push(task.id)
    }
  }

  let mut ready_idx = 0
  let steps : Array[WorkflowStepReport] = []
  let order : Array[String] = []
  let success : Map[String, Bool] = {}
  let reports : Array[TaskRunReport] = []
  let job_states : Map[String, JobRuntimeState] = {}
  let completed_job_outputs : Map[String, Map[String, String]] = {}
  let completed_job_results : Map[String, String] = {}
  let matrix_groups = matrix_group_members(lowered.plan)
  let cancelled_matrix_jobs : Map[String, Bool] = {}
  let evaluated_job_conditions : Map[String, Bool] = {}
  let started_job_tasks : Map[String, Bool] = {}
  let started_jobs : Map[String, Bool] = {}
  let mut required_failed = false

  while ready_idx < ready_queue.length() {
    let batch_ids : Array[String] = []
    let mut slots = 0
    while ready_idx < ready_queue.length() && slots < ir.max_parallel {
      batch_ids.push(ready_queue[ready_idx])
      ready_idx += 1
      slots += 1
    }

    for id in batch_ids {
      order.push(id)
      guard task_map.get(id) is Some(task) else { continue }
      let plan_opt = find_task_plan(lowered.plan, task.id)
      match plan_opt {
        Some(plan) => started_jobs[plan.job_id] = true
        None => ()
      }
      let current_state = match plan_opt {
        Some(plan) => job_runtime_state(job_states, plan.job_id)
        None => empty_job_runtime_state()
      }
      let needs_outputs = match plan_opt {
        Some(plan) =>
          job_needs_outputs(lowered.plan, plan.job_id, completed_job_outputs)
        None => {}
      }
      let needs_results = match plan_opt {
        Some(plan) =>
          job_needs_results(lowered.plan, plan.job_id, completed_job_results)
        None => {}
      }
      let job_should_run = match plan_opt {
        Some(plan) =>
          match evaluated_job_conditions.get(plan.job_id) {
            Some(value) => value
            None => {
              let github_ctx = github_context(
                ir.name,
                plan,
                workspace_root,
                push_event,
              )
              let vars_ctx = runner_vars_context()
              let runner_ctx = runner_context(plan, workspace_root)
              let value = evaluate_if_condition(
                lowered.plan.job_if_conditions
                .get(plan.job_id)
                .unwrap_or("success()"),
                new_if_condition_context(
                  step_outputs=current_state.step_outputs,
                  step_outcomes=current_state.step_outcomes,
                  step_conclusions=current_state.step_conclusions,
                  workspace_root~,
                  vars_context=vars_ctx,
                  github_context=github_ctx,
                  runner_context=runner_ctx,
                  needs_outputs~,
                  needs_results~,
                  success_value=job_if_success_value(needs_results),
                  failure_value=job_if_failure_value(needs_results),
                  cancelled_value=job_if_cancelled_value(needs_results),
                ),
              )
              evaluated_job_conditions[plan.job_id] = value
              value
            }
          }
        None => true
      }
      let cancelled_by_matrix = match plan_opt {
        Some(plan) => cancelled_matrix_jobs.get(plan.job_id).unwrap_or(false)
        None => false
      }
      if cancelled_by_matrix {
        match plan_opt {
          Some(plan) => {
            let message = "cancelled by matrix fail-fast"
            reports.push(task_report_cancelled(plan, workspace_root, message))
            steps.push({
              id: task.id,
              status: "cancelled",
              required: task.required,
              message,
            })
            if plan.kind == "barrier" {
              completed_job_results[plan.job_id] = "cancelled"
            }
          }
          None =>
            steps.push({
              id: task.id,
              status: "cancelled",
              required: task.required,
              message: "cancelled by matrix fail-fast",
            })
        }
        success[task.id] = false
      } else if not(job_should_run) {
        match plan_opt {
          Some(plan) => {
            let message = "job if condition evaluated to false"
            reports.push(task_report_skipped(plan, workspace_root, message))
            steps.push({
              id: task.id,
              status: "skipped",
              required: task.required,
              message,
            })
            if plan.kind == "barrier" {
              completed_job_results[plan.job_id] = "skipped"
            }
          }
          None =>
            steps.push({
              id: task.id,
              status: "skipped",
              required: task.required,
              message: "job if condition evaluated to false",
            })
        }
        success[task.id] = true
      } else {
        let blocked_deps : Array[String] = []
        for dep in task.needs {
          if selected.get(dep) is None {
            continue
          }
          if not(success.get(dep).unwrap_or(false)) {
            blocked_deps.push(dep)
          }
        }
        let is_barrier = match plan_opt {
          Some(plan) => plan.kind == "barrier"
          None => false
        }
        let step_should_run = match plan_opt {
          Some(plan) if not(is_barrier) => {
            let github_ctx = github_context(
              ir.name,
              plan,
              workspace_root,
              push_event,
            )
            let vars_ctx = runner_vars_context()
            let runner_ctx = runner_context(plan, workspace_root)
            evaluate_if_condition(
              plan.if_condition,
              new_if_condition_context(
                step_outputs=current_state.step_outputs,
                step_outcomes=current_state.step_outcomes,
                step_conclusions=current_state.step_conclusions,
                workspace_root~,
                env_context=merge_runner_env(
                  plan.env,
                  current_state.env_updates,
                ),
                vars_context=vars_ctx,
                github_context=github_ctx,
                runner_context=runner_ctx,
                needs_outputs~,
                needs_results~,
                success_value=step_if_success_value(current_state),
                failure_value=step_if_failure_value(current_state),
                cancelled_value=step_if_cancelled_value(current_state),
              ),
            )
          }
          _ => true
        }
        if not(is_barrier) && not(step_should_run) {
          match plan_opt {
            Some(plan) => {
              let message = "step if condition evaluated to false"
              reports.push(task_report_skipped(plan, workspace_root, message))
              job_states[plan.job_id] = apply_job_runtime_updates(
                current_state,
                plan.step_id,
                Some("skipped"),
                Some("skipped"),
                None,
                {},
                [],
                {},
                {},
              )
              steps.push({
                id: task.id,
                status: "skipped",
                required: task.required,
                message,
              })
            }
            None =>
              steps.push({
                id: task.id,
                status: "skipped",
                required: task.required,
                message: "step if condition evaluated to false",
              })
          }
          success[task.id] = true
        } else if blocked_deps.length() > 0 && is_barrier {
          steps.push({
            id: task.id,
            status: "blocked",
            required: task.required,
            message: "blocked by dependency: " + blocked_deps.join(", "),
          })
          match plan_opt {
            Some(plan) if plan.kind == "barrier" =>
              completed_job_results[plan.job_id] = "failure"
            _ => ()
          }
          success[task.id] = false
          if task.required {
            required_failed = true
          }
        } else {
          match plan_opt {
            Some(plan) => {
              if plan.requires_action_started &&
                not(action_scope_started(current_state, plan.action_scope)) {
                reports.push(
                  task_report_skipped(
                    plan, workspace_root, "action lifecycle was not started",
                  ),
                )
                job_states[plan.job_id] = apply_job_runtime_updates(
                  current_state,
                  plan.step_id,
                  Some("skipped"),
                  Some("skipped"),
                  None,
                  {},
                  [],
                  {},
                  {},
                )
                steps.push({
                  id: task.id,
                  status: "skipped",
                  required: task.required,
                  message: "action lifecycle was not started",
                })
                success[task.id] = true
                continue
              }
              if plan.kind != "barrier" {
                started_job_tasks[plan.job_id] = true
              }
              let result = execute_task_plan_native(
                ir.name,
                plan,
                workspace_root,
                current_state,
                needs_outputs,
                needs_results,
                push_event,
              )
              let report = result.report
              reports.push(report)
              let github_ctx = github_context(
                ir.name,
                plan,
                workspace_root,
                push_event,
              )
              let vars_ctx = runner_vars_context()
              let runner_ctx = runner_context(plan, workspace_root)
              let continue_on_error = if plan.kind == "barrier" {
                false
              } else {
                evaluate_boolean_condition(
                  plan.continue_on_error,
                  new_if_condition_context(
                    step_outputs=current_state.step_outputs,
                    step_outcomes=current_state.step_outcomes,
                    step_conclusions=current_state.step_conclusions,
                    workspace_root~,
                    env_context=merge_runner_env(
                      plan.env,
                      current_state.env_updates,
                    ),
                    vars_context=vars_ctx,
                    github_context=github_ctx,
                    runner_context=runner_ctx,
                    needs_outputs~,
                    needs_results~,
                    success_value=step_if_success_value(current_state),
                    failure_value=step_if_failure_value(current_state),
                    cancelled_value=step_if_cancelled_value(current_state),
                  ),
                )
              }
              let outcome = task_outcome(report)
              let conclusion = task_conclusion(outcome, continue_on_error)
              let next_state = apply_job_runtime_updates(
                current_state,
                plan.step_id,
                Some(outcome),
                Some(conclusion),
                plan.action_scope,
                result.env_updates,
                result.path_entries,
                result.output_values,
                result.state_updates,
              )
              job_states[plan.job_id] = next_state
              if conclusion == "success" {
                if plan.kind == "barrier" {
                  completed_job_outputs[plan.job_id] = evaluate_job_outputs(
                    lowered.plan.job_outputs.get(plan.job_id).unwrap_or({}),
                    next_state,
                    workspace_root,
                  )
                  completed_job_results[plan.job_id] = "success"
                }
                steps.push({
                  id: task.id,
                  status: "success",
                  required: task.required,
                  message: report.stdout,
                })
                success[task.id] = true
              } else if conclusion == "skipped" {
                if plan.kind == "barrier" {
                  completed_job_results[plan.job_id] = "skipped"
                }
                let message = if report.stderr.length() > 0 {
                  report.stderr
                } else if report.stdout.length() > 0 {
                  report.stdout
                } else {
                  "task skipped"
                }
                steps.push({
                  id: task.id,
                  status: "skipped",
                  required: task.required,
                  message,
                })
                success[task.id] = true
              } else if conclusion == "cancelled" {
                if plan.kind == "barrier" {
                  completed_job_results[plan.job_id] = "cancelled"
                }
                let message = if report.stderr.length() > 0 {
                  report.stderr
                } else if report.stdout.length() > 0 {
                  report.stdout
                } else {
                  "task cancelled"
                }
                steps.push({
                  id: task.id,
                  status: "cancelled",
                  required: task.required,
                  message,
                })
                success[task.id] = false
                if task.required {
                  required_failed = true
                }
              } else {
                if plan.kind == "barrier" {
                  completed_job_results[plan.job_id] = "failure"
                }
                let message = if report.stderr.length() > 0 {
                  report.stderr
                } else if report.stdout.length() > 0 {
                  report.stdout
                } else {
                  "task failed"
                }
                steps.push({
                  id: task.id,
                  status: "failed",
                  required: task.required,
                  message,
                })
                success[task.id] = task_conclusion_allows_dependents(conclusion)
                if task.required {
                  required_failed = true
                  let group = lowered.plan.job_matrix_groups
                    .get(plan.job_id)
                    .unwrap_or("")
                  if group.length() > 0 &&
                    lowered.plan.job_matrix_fail_fast
                    .get(plan.job_id)
                    .unwrap_or(false) {
                    for job_member in matrix_groups.get(group).unwrap_or([]) {
                      if job_member != plan.job_id &&
                        not(started_jobs.get(job_member).unwrap_or(false)) {
                        cancelled_matrix_jobs[job_member] = true
                      }
                    }
                  }
                }
              }
            }
            None => {
              steps.push({
                id: task.id,
                status: "failed",
                required: task.required,
                message: "missing task plan",
              })
              success[task.id] = false
              if task.required {
                required_failed = true
              }
            }
          }
        }
      }

      for dependent_id in dependents.get(id).unwrap_or([]) {
        let next = remaining_deps.get(dependent_id).unwrap_or(0) - 1
        remaining_deps[dependent_id] = next
        if next == 0 {
          ready_queue.push(dependent_id)
        }
      }
    }
  }

  {
    ok: not(required_failed),
    state: if required_failed {
      "partial_failed"
    } else {
      "completed"
    },
    order,
    steps,
    issues: [],
    task_reports: reports,
  }
}

///|
#cfg(not(target="native"))
pub async fn execute_lowered_native(
  lowered : LoweringResult,
  workspace_root? : String = ".",
  push_event? : PushEvent? = None,
) -> WorkflowRunReport {
  ignore(lowered)
  ignore(workspace_root)
  ignore(push_event)
  make_invalid_report(["native executor is only available on native target"])
}
