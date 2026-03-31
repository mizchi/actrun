///|
/// Plan API: parse + lower a workflow YAML and return a structured plan.
/// This is the scheduler component for worker environments.

///|
pub struct PlanResult {
  workflow_name : String
  errors : Array[String]
  jobs : Array[PlanJob]
}

///|
pub struct PlanJob {
  id : String
  needs : Array[String]
  runs_on : Array[String]
  steps : Array[PlanStep]
}

///|
pub struct PlanStep {
  id : String
  kind : String
  name : String
  shell : String
  script : String
  uses : String
  backend : String
  if_condition : String
  env : Map[String, String]
  with_values : Map[String, String]
}

///|
pub fn plan_workflow(
  yaml_text : String,
  workspace_root? : String = "",
) -> PlanResult {
  let parsed = parse_workflow_yaml(yaml_text)
  guard parsed.workflow is Some(workflow) else {
    return { workflow_name: "", errors: parsed.errors, jobs: [] }
  }
  let lowered = lower_push_workflow_in_workspace(workflow, workspace_root)
  let job_steps : Map[String, Array[PlanStep]] = {}
  let job_order : Array[String] = []
  for task in lowered.plan.tasks {
    if task.kind == "barrier" {
      continue
    }
    if job_steps.get(task.job_id) is None {
      job_steps[task.job_id] = []
      job_order.push(task.job_id)
    }
    let step : PlanStep = {
      id: task.id,
      kind: task.kind,
      name: task.name,
      shell: task.shell,
      script: task.script,
      uses: match task.action {
        Some(action) => action.uses
        None => ""
      },
      backend: match task.action {
        Some(action) => action.backend
        None => ""
      },
      if_condition: task.if_condition,
      env: task.env,
      with_values: task.with_values,
    }
    job_steps.get(task.job_id).unwrap().push(step)
  }
  let jobs : Array[PlanJob] = []
  for job_id in job_order {
    let needs = lowered.plan.job_needs.get(job_id).unwrap_or([])
    let runs_on = lowered.plan.tasks
      .iter()
      .find_first(fn(t) { t.job_id == job_id })
      .map(fn(t) { t.runs_on })
      .unwrap_or([])
    jobs.push({
      id: job_id,
      needs,
      runs_on,
      steps: job_steps.get(job_id).unwrap_or([]),
    })
  }
  let errors = lowered.errors
  for err in parsed.errors {
    errors.push(err)
  }
  { workflow_name: workflow.name, errors, jobs }
}

///|
pub fn plan_result_to_json(result : PlanResult) -> String {
  let parts : Array[String] = []
  parts.push("\"workflow\": " + json_escape_string(result.workflow_name))
  if result.errors.length() > 0 {
    let err_items : Array[String] = []
    for err in result.errors {
      err_items.push(json_escape_string(err))
    }
    parts.push("\"errors\": [" + err_items.join(", ") + "]")
  }
  let job_items : Array[String] = []
  for job in result.jobs {
    let jparts : Array[String] = []
    jparts.push("\"id\": " + json_escape_string(job.id))
    if job.needs.length() > 0 {
      let ns : Array[String] = []
      for n in job.needs {
        ns.push(json_escape_string(n))
      }
      jparts.push("\"needs\": [" + ns.join(", ") + "]")
    }
    if job.runs_on.length() > 0 {
      let rs : Array[String] = []
      for r in job.runs_on {
        rs.push(json_escape_string(r))
      }
      jparts.push("\"runs_on\": [" + rs.join(", ") + "]")
    }
    let step_items : Array[String] = []
    for step in job.steps {
      let sparts : Array[String] = []
      sparts.push("\"id\": " + json_escape_string(step.id))
      sparts.push("\"kind\": " + json_escape_string(step.kind))
      if step.name.length() > 0 {
        sparts.push("\"name\": " + json_escape_string(step.name))
      }
      if step.uses.length() > 0 {
        sparts.push("\"uses\": " + json_escape_string(step.uses))
      }
      if step.backend.length() > 0 {
        sparts.push("\"backend\": " + json_escape_string(step.backend))
      }
      if step.shell.length() > 0 {
        sparts.push("\"shell\": " + json_escape_string(step.shell))
      }
      if step.script.length() > 0 {
        sparts.push("\"script\": " + json_escape_string(step.script))
      }
      if step.if_condition.length() > 0 && step.if_condition != "success()" {
        sparts.push("\"if\": " + json_escape_string(step.if_condition))
      }
      if step.env.length() > 0 {
        sparts.push("\"env\": " + plan_json_string_map(step.env))
      }
      if step.with_values.length() > 0 {
        sparts.push("\"with\": " + plan_json_string_map(step.with_values))
      }
      step_items.push("{ " + sparts.join(", ") + " }")
    }
    jparts.push("\"steps\": [" + step_items.join(", ") + "]")
    job_items.push("{ " + jparts.join(", ") + " }")
  }
  parts.push("\"jobs\": [" + job_items.join(", ") + "]")
  "{ " + parts.join(", ") + " }"
}

///|
fn json_escape_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for ch in s {
    if ch == '"' {
      buf.write_string("\\\"")
    } else if ch == '\\' {
      buf.write_string("\\\\")
    } else if ch == '\n' {
      buf.write_string("\\n")
    } else if ch == '\r' {
      buf.write_string("\\r")
    } else if ch == '\t' {
      buf.write_string("\\t")
    } else {
      buf.write_char(ch)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn plan_json_string_map(values : Map[String, String]) -> String {
  let items : Array[String] = []
  for key, value in values {
    items.push(json_escape_string(key) + ": " + json_escape_string(value))
  }
  "{ " + items.join(", ") + " }"
}
