///|
pub struct RunDefaults {
  shell : String?
  working_directory : String?
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
}

///|
pub fn new_push_trigger(
  branches? : Array[String] = [],
  branches_ignore? : Array[String] = [],
  paths? : Array[String] = [],
  paths_ignore? : Array[String] = [],
) -> PushTrigger {
  { branches, branches_ignore, paths, paths_ignore }
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
  }
}

///|
pub struct JobSpec {
  id : String
  name : String
  needs : Array[String]
  outputs : Map[String, String]
  runs_on : Array[String]
  env : Map[String, String]
  defaults : RunDefaults
  steps : Array[StepSpec]
  matrix : JobMatrixSpec?
  reusable_workflow : String?
  container_image : String?
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
  needs? : Array[String] = [],
  outputs? : Map[String, String] = {},
  runs_on? : Array[String] = ["ubuntu-latest"],
  env? : Map[String, String] = {},
  defaults? : RunDefaults = new_run_defaults(),
  matrix? : JobMatrixSpec? = None,
  reusable_workflow? : String? = None,
  container_image? : String? = None,
) -> JobSpec {
  {
    id,
    name,
    needs,
    outputs,
    runs_on,
    env,
    defaults,
    steps,
    matrix,
    reusable_workflow,
    container_image,
  }
}

///|
pub struct WorkflowSpec {
  name : String
  trigger : PushTrigger
  env : Map[String, String]
  defaults : RunDefaults
  jobs : Array[JobSpec]
}

///|
pub fn new_workflow(
  name : String,
  jobs : Array[JobSpec],
  trigger? : PushTrigger = new_push_trigger(),
  env? : Map[String, String] = {},
  defaults? : RunDefaults = new_run_defaults(),
) -> WorkflowSpec {
  { name, trigger, env, defaults, jobs }
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
  action : ResolvedAction?
  action_scope : String?
  requires_action_started : Bool
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
  action? : ResolvedAction? = None,
  action_scope? : String? = None,
  requires_action_started? : Bool = false,
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
    action,
    action_scope,
    requires_action_started,
  }
}

///|
pub struct ExecutionPlan {
  tasks : Array[TaskPlan]
  job_outputs : Map[String, Map[String, String]]
  job_needs : Map[String, Array[String]]
  job_need_targets : Map[String, Map[String, Array[String]]]
  job_matrix_groups : Map[String, String]
  job_matrix_fail_fast : Map[String, Bool]
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
  steps : Array[StepSpec]
}

///|
pub fn new_local_action(
  steps : Array[StepSpec],
  name? : String = "",
  inputs? : Map[String, String] = {},
) -> LocalActionSpec {
  { name, inputs, steps }
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
