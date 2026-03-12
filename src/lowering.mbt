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
fn github_action_cache_root() -> String {
  absolute_lowering_path(
    @xsys.get_env_var("ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT").unwrap_or(
      "_build/action_runner/github_actions",
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
fn matrix_expr_name(expression : String) -> String? {
  let trimmed = expression.trim(chars=" \t\n\r").to_string()
  if trimmed.has_prefix("matrix.") && trimmed.length() > 7 {
    Some(text_slice(trimmed, 7, trimmed.length()))
  } else {
    None
  }
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
              Some(name) => chunks.push(matrix_values.get(name).unwrap_or(""))
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
    if_condition=job.if_condition,
    needs=actual_needs,
    outputs=substitute_matrix_map(job.outputs, matrix_values),
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
    container_image=substitute_optional_matrix(
      job.container_image,
      matrix_values,
    ),
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
fn expand_matrix_jobs(jobs : Array[JobSpec]) -> Array[ExpandedJob] {
  let expanded : Array[ExpandedJob] = []
  let job_ids = expanded_job_ids(jobs)
  for job in jobs {
    match job.matrix {
      Some(matrix) => {
        let limit = matrix.max_parallel.unwrap_or(matrix.rows.length())
        let mut row_index = 0
        for row in matrix.rows {
          let actual_needs : Array[String] = []
          let need_targets : Map[String, Array[String]] = {}
          for need in job.needs {
            let targets = job_ids.get(need).unwrap_or([need])
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
          let targets = job_ids.get(need).unwrap_or([need])
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
            runs_on=job.runs_on,
            env=job.env,
            defaults=job.defaults,
            matrix=None,
            reusable_workflow=job.reusable_workflow,
            container_image=job.container_image,
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
) -> Unit {
  tasks.push(
    @wf.new_task(
      task_id,
      job.id,
      "__action_runner_" + action.kind + "__",
      needs,
      env~,
    ),
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
    env[action_input_env_name(key)] = value
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
fn lower_cached_github_action(
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
  let parsed = parse_local_action_yaml(manifest_text)
  guard parsed.action is Some(action) else {
    for err in parsed.errors {
      errors.push(
        "step '\{job.id}/\{outer_step_id}' local action '\{manifest_path}' " +
        err,
      )
    }
    return previous_task_id
  }

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
      if cached_github_action_root(action_ref) is Some(cached_root) {
        local_previous_task_id = lower_cached_github_action(
          workflow, job, outer_env, nested_outer_step, resolved_step_id, local_previous_task_id,
          action_ref, cached_root, workspace_root, tasks, task_plans, deferred_post_tasks,
          errors,
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
  local_previous_task_id
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
  let job_matrix_groups : Map[String, String] = {}
  let job_matrix_fail_fast : Map[String, Bool] = {}
  let entry_targets : Array[String] = []
  let seen_jobs : Map[String, Bool] = {}
  let expanded_jobs = expand_matrix_jobs(workflow.jobs)
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
    if job.reusable_workflow is Some(path) {
      errors.push(
        "job '\{job.id}' reusable workflow is not supported in MVP: \{path}",
      )
    }
    if job.container_image is Some(image) {
      errors.push("job '\{job.id}' container is not supported in MVP: \{image}")
    }
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
              workflow, job, job_env, step, resolved_step_id, previous_task_id, path,
              workspace_root, tasks, task_plans, deferred_post_tasks, errors,
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
          cached_github_action_root(action_ref) is Some(cached_root) {
          previous_task_id = lower_cached_github_action(
            workflow, job, job_env, step, resolved_step_id, previous_task_id, action_ref,
            cached_root, workspace_root, tasks, task_plans, deferred_post_tasks,
            errors,
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
      @wf.new_task(
        barrier_id,
        job.id,
        "__action_runner_barrier__",
        barrier_needs,
      ),
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
      job_matrix_groups,
      job_matrix_fail_fast,
    },
    errors,
  }
}

///|
pub fn lower_push_workflow(workflow : WorkflowSpec) -> LoweringResult {
  lower_push_workflow_in_workspace(workflow, "")
}
