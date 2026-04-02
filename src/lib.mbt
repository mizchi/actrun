///|
pub struct RunDefaults {
  shell : String?
  working_directory : String?
}

///|
pub struct PermissionsSpec {
  values : Map[String, String]
}

///|
pub struct ConcurrencySpec {
  group : String
  cancel_in_progress : String?
}

///|
pub struct WorkflowCallInputSpec {
  description : String
  required : Bool
  default_value : String?
  input_type : String
}

///|
pub struct WorkflowCallOutputSpec {
  description : String
  value : String
}

///|
pub struct WorkflowCallSecretSpec {
  required : Bool
}

///|
pub struct JobContainerCredentialsSpec {
  username : String
  password : String
}

///|
pub struct JobContainerSpec {
  image : String
  credentials : JobContainerCredentialsSpec?
  env : Map[String, String]
  ports : Array[String]
  volumes : Array[String]
  options : String?
}

///|
pub struct WorkflowCallSpec {
  inputs : Map[String, WorkflowCallInputSpec]
  outputs : Map[String, WorkflowCallOutputSpec]
  secrets : Map[String, WorkflowCallSecretSpec]
}

///|
pub fn new_permissions_spec(
  values? : Map[String, String] = {},
) -> PermissionsSpec {
  { values, }
}

///|
pub fn new_concurrency_spec(
  group : String,
  cancel_in_progress? : String? = None,
) -> ConcurrencySpec {
  { group, cancel_in_progress }
}

///|
pub fn new_workflow_call_input_spec(
  description? : String = "",
  required? : Bool = false,
  default_value? : String? = None,
  input_type? : String = "",
) -> WorkflowCallInputSpec {
  { description, required, default_value, input_type }
}

///|
pub fn new_workflow_call_output_spec(
  description? : String = "",
  value? : String = "",
) -> WorkflowCallOutputSpec {
  { description, value }
}

///|
pub fn new_workflow_call_secret_spec(
  required? : Bool = false,
) -> WorkflowCallSecretSpec {
  { required, }
}

///|
pub fn new_job_container_credentials_spec(
  username : String,
  password : String,
) -> JobContainerCredentialsSpec {
  { username, password }
}

///|
pub fn new_job_container_spec(
  image : String,
  credentials? : JobContainerCredentialsSpec? = None,
  env? : Map[String, String] = {},
  ports? : Array[String] = [],
  volumes? : Array[String] = [],
  options? : String? = None,
) -> JobContainerSpec {
  { image, credentials, env, ports, volumes, options }
}

///|
pub fn new_workflow_call_spec(
  inputs? : Map[String, WorkflowCallInputSpec] = {},
  outputs? : Map[String, WorkflowCallOutputSpec] = {},
  secrets? : Map[String, WorkflowCallSecretSpec] = {},
) -> WorkflowCallSpec {
  { inputs, outputs, secrets }
}

///|
pub fn new_run_defaults(
  shell? : String? = None,
  working_directory? : String? = None,
) -> RunDefaults {
  { shell, working_directory }
}

///|
pub struct PushTrigger {
  branches : Array[String]
  branches_ignore : Array[String]
  paths : Array[String]
  paths_ignore : Array[String]
  tags : Array[String]
  tags_ignore : Array[String]
}

///|
pub fn new_push_trigger(
  branches? : Array[String] = [],
  branches_ignore? : Array[String] = [],
  paths? : Array[String] = [],
  paths_ignore? : Array[String] = [],
  tags? : Array[String] = [],
  tags_ignore? : Array[String] = [],
) -> PushTrigger {
  { branches, branches_ignore, paths, paths_ignore, tags, tags_ignore }
}

///|
pub struct PushEvent {
  ref_name : String
  before_sha : String
  after_sha : String
  changed_paths : Array[String]
  repository : String
  actor : String
}

///|
pub fn new_push_event(
  ref_name : String,
  changed_paths : Array[String],
  before_sha? : String = "",
  after_sha? : String = "",
  repository? : String = "",
  actor? : String = "",
) -> PushEvent {
  { ref_name, before_sha, after_sha, changed_paths, repository, actor }
}

///|
pub struct StepSpec {
  id : String
  name : String
  run : String?
  uses : String?
  shell : String?
  working_directory : String?
  env : Map[String, String]
  with_values : Map[String, String]
  if_condition : String
  continue_on_error : String
  timeout_minutes : Int
}

///|
pub fn new_run_step(
  id : String,
  run : String,
  name? : String = "",
  shell? : String? = None,
  working_directory? : String? = None,
  env? : Map[String, String] = {},
  if_condition? : String = "success()",
  with_values? : Map[String, String] = {},
  continue_on_error? : String = "false",
  timeout_minutes? : Int = 0,
) -> StepSpec {
  {
    id,
    name,
    run: Some(run),
    uses: None,
    shell,
    working_directory,
    env,
    with_values,
    if_condition,
    continue_on_error,
    timeout_minutes,
  }
}

///|
pub fn new_uses_step(
  id : String,
  uses : String,
  name? : String = "",
  env? : Map[String, String] = {},
  if_condition? : String = "success()",
  with_values? : Map[String, String] = {},
  continue_on_error? : String = "false",
  timeout_minutes? : Int = 0,
) -> StepSpec {
  {
    id,
    name,
    run: None,
    uses: Some(uses),
    shell: None,
    working_directory: None,
    env,
    with_values,
    if_condition,
    continue_on_error,
    timeout_minutes,
  }
}

///|
pub struct JobSpec {
  id : String
  name : String
  if_condition : String
  needs : Array[String]
  outputs : Map[String, String]
  permissions : PermissionsSpec?
  concurrency : ConcurrencySpec?
  runs_on : Array[String]
  env : Map[String, String]
  defaults : RunDefaults
  steps : Array[StepSpec]
  matrix : JobMatrixSpec?
  reusable_workflow : String?
  reusable_workflow_with : Map[String, String]
  reusable_workflow_secrets : Map[String, String]
  reusable_workflow_inherit_secrets : Bool
  services : Map[String, JobContainerSpec]
  container : JobContainerSpec?
  container_image : String?
  timeout_minutes : Int
  environment : String
}

///|
pub struct JobMatrixSpec {
  rows : Array[Map[String, String]]
  fail_fast : Bool
  max_parallel : Int?
}

///|
pub fn new_job_matrix(
  rows : Array[Map[String, String]],
  fail_fast? : Bool = true,
  max_parallel? : Int? = None,
) -> JobMatrixSpec {
  { rows, fail_fast, max_parallel }
}

///|
pub fn new_job(
  id : String,
  steps : Array[StepSpec],
  name? : String = "",
  if_condition? : String = "success()",
  needs? : Array[String] = [],
  outputs? : Map[String, String] = {},
  permissions? : PermissionsSpec? = None,
  concurrency? : ConcurrencySpec? = None,
  runs_on? : Array[String] = ["ubuntu-latest"],
  env? : Map[String, String] = {},
  defaults? : RunDefaults = new_run_defaults(),
  matrix? : JobMatrixSpec? = None,
  reusable_workflow? : String? = None,
  reusable_workflow_with? : Map[String, String] = {},
  reusable_workflow_secrets? : Map[String, String] = {},
  reusable_workflow_inherit_secrets? : Bool = false,
  container? : JobContainerSpec? = None,
  container_image? : String? = None,
  services? : Map[String, JobContainerSpec] = {},
  timeout_minutes? : Int = 0,
  environment? : String = "",
) -> JobSpec {
  let actual_container = match container {
    Some(spec) => Some(spec)
    None =>
      match container_image {
        Some(image) => Some(new_job_container_spec(image))
        None => None
      }
  }
  let actual_container_image = match actual_container {
    Some(spec) => Some(spec.image)
    None => None
  }
  {
    id,
    name,
    if_condition,
    needs,
    outputs,
    permissions,
    concurrency,
    runs_on,
    env,
    defaults,
    steps,
    matrix,
    reusable_workflow,
    reusable_workflow_with,
    reusable_workflow_secrets,
    reusable_workflow_inherit_secrets,
    services,
    container: actual_container,
    container_image: actual_container_image,
    timeout_minutes,
    environment,
  }
}

///|
pub struct WorkflowSpec {
  name : String
  run_name : String
  trigger : PushTrigger
  pull_request_trigger : PushTrigger?
  workflow_call : Bool
  workflow_call_spec : WorkflowCallSpec?
  permissions : PermissionsSpec?
  concurrency : ConcurrencySpec?
  env : Map[String, String]
  defaults : RunDefaults
  jobs : Array[JobSpec]
}

///|
pub fn strip_unsupported_workflow_fields(
  workflow : WorkflowSpec,
) -> WorkflowSpec {
  let stripped_jobs : Array[JobSpec] = []
  for job in workflow.jobs {
    stripped_jobs.push({ ..job, permissions: None, concurrency: None })
  }
  { ..workflow, permissions: None, concurrency: None, jobs: stripped_jobs }
}

///|
pub fn step_matches_skip_pattern(
  step : StepSpec,
  patterns : Array[String],
) -> Bool {
  match step.uses {
    Some(uses) => {
      let mut matched = false
      for pattern in patterns {
        if uses.contains(pattern) {
          matched = true
          break
        }
      }
      matched
    }
    None => false
  }
}

///|
pub fn filter_workflow_steps(
  workflow : WorkflowSpec,
  skip_patterns : Array[String],
) -> WorkflowSpec {
  if skip_patterns.length() == 0 {
    return workflow
  }
  let filtered_jobs : Array[JobSpec] = []
  for job in workflow.jobs {
    let filtered_steps : Array[StepSpec] = []
    for step in job.steps {
      if !step_matches_skip_pattern(step, skip_patterns) {
        filtered_steps.push(step)
      }
    }
    filtered_jobs.push({ ..job, steps: filtered_steps })
  }
  { ..workflow, jobs: filtered_jobs }
}

///|
pub fn override_workflow_steps(
  workflow : WorkflowSpec,
  overrides : Map[String, String],
) -> WorkflowSpec {
  if overrides.length() == 0 {
    return workflow
  }
  let result_jobs : Array[JobSpec] = []
  for job in workflow.jobs {
    let result_steps : Array[StepSpec] = []
    for step in job.steps {
      match step.uses {
        Some(uses) => {
          let mut matched_script : String? = None
          for pattern, script in overrides {
            if uses.contains(pattern) {
              matched_script = Some(script)
              break
            }
          }
          match matched_script {
            Some(script) =>
              result_steps.push({
                ..step,
                uses: None,
                run: Some(script),
                shell: Some("bash"),
              })
            None => result_steps.push(step)
          }
        }
        None => result_steps.push(step)
      }
    }
    result_jobs.push({ ..job, steps: result_steps })
  }
  { ..workflow, jobs: result_jobs }
}

///|
pub fn filter_workflow_jobs(
  workflow : WorkflowSpec,
  skip_job_ids : Array[String],
) -> WorkflowSpec {
  if skip_job_ids.length() == 0 {
    return workflow
  }
  let filtered_jobs : Array[JobSpec] = []
  for job in workflow.jobs {
    let mut should_skip = false
    for skip_id in skip_job_ids {
      if job.id == skip_id {
        should_skip = true
        break
      }
    }
    if !should_skip {
      filtered_jobs.push(job)
    }
  }
  { ..workflow, jobs: filtered_jobs }
}

///|
pub fn select_workflow_job(
  workflow : WorkflowSpec,
  job_id : String,
) -> WorkflowSpec {
  if job_id.length() == 0 {
    return workflow
  }
  let filtered_jobs : Array[JobSpec] = []
  for job in workflow.jobs {
    if job.id == job_id {
      filtered_jobs.push(job)
    }
  }
  { ..workflow, jobs: filtered_jobs }
}

///|
pub fn select_workflow_step(
  workflow : WorkflowSpec,
  job_id : String,
  step_id : String,
) -> WorkflowSpec {
  if step_id.length() == 0 {
    return workflow
  }
  let filtered_jobs : Array[JobSpec] = []
  for job in workflow.jobs {
    if job_id.length() > 0 && job.id != job_id {
      continue
    }
    let filtered_steps : Array[StepSpec] = []
    for step in job.steps {
      if step.id == step_id || step.name == step_id {
        filtered_steps.push(step)
      }
    }
    if filtered_steps.length() > 0 {
      filtered_jobs.push({ ..job, steps: filtered_steps })
    }
  }
  { ..workflow, jobs: filtered_jobs }
}

///|
pub fn new_workflow(
  name : String,
  jobs : Array[JobSpec],
  run_name? : String = "",
  trigger? : PushTrigger = new_push_trigger(),
  pull_request_trigger? : PushTrigger? = None,
  workflow_call? : Bool = false,
  workflow_call_spec? : WorkflowCallSpec? = None,
  permissions? : PermissionsSpec? = None,
  concurrency? : ConcurrencySpec? = None,
  env? : Map[String, String] = {},
  defaults? : RunDefaults = new_run_defaults(),
) -> WorkflowSpec {
  {
    name,
    run_name,
    trigger,
    pull_request_trigger,
    workflow_call,
    workflow_call_spec,
    permissions,
    concurrency,
    env,
    defaults,
    jobs,
  }
}

///|
pub struct TaskPlan {
  id : String
  kind : String
  job_id : String
  step_id : String
  name : String
  script : String
  shell : String
  working_directory : String
  if_condition : String
  runs_on : Array[String]
  env : Map[String, String]
  with_values : Map[String, String]
  action : ResolvedAction?
  action_scope : String?
  requires_action_started : Bool
  continue_on_error : String
  // Parsed from step or job timeout-minutes. 0 means no timeout.
  // Currently parsed but not enforced at execution time.
  timeout_minutes : Int
}

///|
pub fn new_task_plan(
  id : String,
  kind : String,
  job_id : String,
  step_id : String,
  name : String,
  script : String,
  shell : String,
  working_directory : String,
  if_condition : String,
  runs_on : Array[String],
  env : Map[String, String],
  with_values? : Map[String, String] = {},
  action? : ResolvedAction? = None,
  action_scope? : String? = None,
  requires_action_started? : Bool = false,
  continue_on_error? : String = "false",
  timeout_minutes? : Int = 0,
) -> TaskPlan {
  {
    id,
    kind,
    job_id,
    step_id,
    name,
    script,
    shell,
    working_directory,
    if_condition,
    runs_on,
    env,
    with_values,
    action,
    action_scope,
    requires_action_started,
    continue_on_error,
    timeout_minutes,
  }
}

///|
pub struct ExecutionPlan {
  tasks : Array[TaskPlan]
  job_outputs : Map[String, Map[String, String]]
  job_if_conditions : Map[String, String]
  job_needs : Map[String, Array[String]]
  job_need_targets : Map[String, Map[String, Array[String]]]
  job_virtual_targets : Map[String, Array[String]]
  job_virtual_output_targets : Map[String, Map[String, Array[String]]]
  job_matrix_groups : Map[String, String]
  job_matrix_fail_fast : Map[String, Bool]
  job_containers : Map[String, JobContainerSpec]
  job_services : Map[String, Map[String, JobContainerSpec]]
  composite_output_mappings : Map[String, Map[String, String]]
}

///|
pub fn find_task_plan(plan : ExecutionPlan, id : String) -> TaskPlan? {
  for task in plan.tasks {
    if task.id == id {
      return Some(task)
    }
  }
  None
}

///|
pub struct LoweringResult {
  ir : @wf.FlowIr
  plan : ExecutionPlan
  errors : Array[String]
}

///|
pub struct WorkflowParseResult {
  workflow : WorkflowSpec?
  errors : Array[String]
}

///|
pub struct LocalActionSpec {
  name : String
  inputs : Map[String, String]
  outputs : Map[String, String]
  steps : Array[StepSpec]
}

///|
pub fn new_local_action(
  steps : Array[StepSpec],
  name? : String = "",
  inputs? : Map[String, String] = {},
  outputs? : Map[String, String] = {},
) -> LocalActionSpec {
  { name, inputs, outputs, steps }
}

///|
pub struct LocalActionParseResult {
  action : LocalActionSpec?
  errors : Array[String]
}

///|
pub struct BitWorkspace {
  repo_root : String
  git_dir : String
  workspace_root : String
  commit_sha : String
  refname : String
  remote_url : String
}

///|
pub struct BitWorkspaceResult {
  workspace : BitWorkspace?
  errors : Array[String]
}

///|
pub struct BitChangedPathsResult {
  paths : Array[String]
  base_sha : String
  head_sha : String
  errors : Array[String]
}

///|
pub struct PushEventJsonParseResult {
  event : PushEvent?
  errors : Array[String]
}

///|
pub struct GitHubActionPrefetchResult {
  fetched : Array[String]
  errors : Array[String]
}

///|
pub struct TaskRunReport {
  id : String
  kind : String
  status : String
  code : Int
  duration_ms : UInt64
  shell : String
  script : String
  cwd : String
  stdout : String
  stderr : String
  summary : String
}

///|
pub struct WorkflowStepReport {
  id : String
  status : String
  required : Bool
  duration_ms : UInt64
  message : String
}

///|
pub struct WorkflowRunReport {
  ok : Bool
  state : String
  order : Array[String]
  steps : Array[WorkflowStepReport]
  issues : Array[String]
  task_reports : Array[TaskRunReport]
}

///|
fn strip_add_mask_lines(text : String) -> String {
  let lines : Array[String] = []
  for line_view in text.split("\n") {
    let trimmed = line_view.trim(chars=" \t\r")
    if trimmed.has_prefix("::add-mask::") {
      continue
    }
    if trimmed.has_prefix("::group::") {
      continue
    }
    if trimmed.has_prefix("::endgroup::") {
      continue
    }
    if trimmed.has_prefix("::debug::") {
      continue
    }
    lines.push(line_view.to_string())
  }
  lines.join("\n")
}

///|
pub fn extract_add_mask_values(report : WorkflowRunReport) -> Array[String] {
  let values : Array[String] = []
  let prefix = "::add-mask::"
  for task in report.task_reports {
    for line_view in task.stdout.split("\n") {
      let line = line_view.trim(chars=" \t\r").to_string()
      if line.has_prefix(prefix) && line.length() > prefix.length() {
        let value = String::unsafe_substring(
          line,
          start=prefix.length(),
          end=line.length(),
        )
        if value.length() > 0 {
          values.push(value)
        }
      }
    }
    for line_view in task.stderr.split("\n") {
      let line = line_view.trim(chars=" \t\r").to_string()
      if line.has_prefix(prefix) && line.length() > prefix.length() {
        let value = String::unsafe_substring(
          line,
          start=prefix.length(),
          end=line.length(),
        )
        if value.length() > 0 {
          values.push(value)
        }
      }
    }
  }
  values
}

///|
pub fn mask_report_secrets(
  report : WorkflowRunReport,
  secret_values : Array[String],
) -> WorkflowRunReport {
  // Also collect ::add-mask:: values from stdout/stderr
  let add_mask_values = extract_add_mask_values(report)
  let all_secrets : Array[String] = []
  for value in secret_values {
    all_secrets.push(value)
  }
  for value in add_mask_values {
    all_secrets.push(value)
  }
  if all_secrets.length() == 0 {
    // Still strip workflow command lines even without secrets
    let stripped_tasks : Array[TaskRunReport] = []
    for task in report.task_reports {
      stripped_tasks.push({
        ..task,
        stdout: strip_add_mask_lines(task.stdout),
        stderr: strip_add_mask_lines(task.stderr),
      })
    }
    return { ..report, task_reports: stripped_tasks }
  }
  let masked_tasks : Array[TaskRunReport] = []
  for task in report.task_reports {
    masked_tasks.push({
      ..task,
      script: mask_secrets(task.script, all_secrets),
      stdout: strip_add_mask_lines(mask_secrets(task.stdout, all_secrets)),
      stderr: strip_add_mask_lines(mask_secrets(task.stderr, all_secrets)),
      summary: mask_secrets(task.summary, all_secrets),
    })
  }
  let masked_steps : Array[WorkflowStepReport] = []
  for step in report.steps {
    masked_steps.push({
      ..step,
      message: mask_secrets(step.message, all_secrets),
    })
  }
  { ..report, task_reports: masked_tasks, steps: masked_steps }
}

///|
pub fn find_workflow_step_report(
  report : WorkflowRunReport,
  id : String,
) -> WorkflowStepReport? {
  for item in report.steps {
    if item.id == id {
      return Some(item)
    }
  }
  None
}

///|
pub fn find_task_run_report(
  report : WorkflowRunReport,
  id : String,
) -> TaskRunReport? {
  for item in report.task_reports {
    if item.id == id {
      return Some(item)
    }
  }
  None
}
