///|
pub struct LintContext {
  // Top-level context types available in expressions
  contexts : Map[String, ExprType]
}

///|
fn make_step_type() -> ExprType {
  let fields : Map[String, ExprType] = {}
  fields["outputs"] = TyObject(MapObj(TyString))
  fields["outcome"] = TyString
  fields["conclusion"] = TyString
  TyObject(Strict(fields))
}

///|
fn make_needs_job_type() -> ExprType {
  let fields : Map[String, ExprType] = {}
  fields["outputs"] = TyObject(MapObj(TyString))
  fields["result"] = TyString
  TyObject(Strict(fields))
}

///|
fn make_github_type() -> ExprType {
  let fields : Map[String, ExprType] = {}
  fields["event_name"] = TyString
  fields["ref"] = TyString
  fields["ref_name"] = TyString
  fields["sha"] = TyString
  fields["head_ref"] = TyString
  fields["base_ref"] = TyString
  fields["repository"] = TyString
  fields["repository_owner"] = TyString
  fields["actor"] = TyString
  fields["workflow"] = TyString
  fields["run_id"] = TyString
  fields["run_number"] = TyString
  fields["run_attempt"] = TyString
  fields["action"] = TyString
  fields["action_path"] = TyString
  fields["workspace"] = TyString
  fields["server_url"] = TyString
  fields["api_url"] = TyString
  fields["graphql_url"] = TyString
  fields["token"] = TyString
  fields["job"] = TyString
  fields["triggering_actor"] = TyString
  fields["event"] = TyObject(Loose({}, TyAny))
  fields["output"] = TyString
  TyObject(Strict(fields))
}

///|
fn make_runner_type() -> ExprType {
  let fields : Map[String, ExprType] = {}
  fields["os"] = TyString
  fields["arch"] = TyString
  fields["name"] = TyString
  fields["environment"] = TyString
  fields["temp"] = TyString
  fields["tool_cache"] = TyString
  TyObject(Strict(fields))
}

///|
fn make_job_type() -> ExprType {
  let fields : Map[String, ExprType] = {}
  fields["status"] = TyString
  fields["container"] = TyObject(Loose({}, TyString))
  fields["services"] = TyObject(MapObj(TyObject(Loose({}, TyString))))
  TyObject(Strict(fields))
}

///|
pub fn build_lint_context(
  job : @ar.JobSpec,
  step_index : Int,
  all_jobs : Array[@ar.JobSpec],
) -> LintContext {
  let contexts : Map[String, ExprType] = {}
  contexts["github"] = make_github_type()
  contexts["env"] = TyObject(MapObj(TyString))
  contexts["secrets"] = TyObject(MapObj(TyString))
  contexts["vars"] = TyObject(MapObj(TyString))
  contexts["matrix"] = TyObject(MapObj(TyString))
  contexts["runner"] = make_runner_type()
  contexts["job"] = make_job_type()
  contexts["inputs"] = TyObject(MapObj(TyString))
  // Build steps context: only steps before current step_index
  let step_fields : Map[String, ExprType] = {}
  let mut i = 0
  while i < step_index && i < job.steps.length() {
    let step = job.steps[i]
    let sid = if step.id.length() > 0 { step.id } else { "" }
    if sid.length() > 0 {
      step_fields[sid] = make_step_type()
    }
    i += 1
  }
  contexts["steps"] = TyObject(Strict(step_fields))
  // Build needs context from job.needs
  let needs_fields : Map[String, ExprType] = {}
  for need_id in job.needs {
    // Verify the needed job exists
    let mut found = false
    for j in all_jobs {
      if j.id == need_id {
        found = true
        break
      }
    }
    if found {
      needs_fields[need_id] = make_needs_job_type()
    }
  }
  contexts["needs"] = TyObject(Strict(needs_fields))
  { contexts, }
}

///|
pub fn build_job_lint_context(
  job : @ar.JobSpec,
  all_jobs : Array[@ar.JobSpec],
) -> LintContext {
  let contexts : Map[String, ExprType] = {}
  contexts["github"] = make_github_type()
  contexts["env"] = TyObject(MapObj(TyString))
  contexts["secrets"] = TyObject(MapObj(TyString))
  contexts["vars"] = TyObject(MapObj(TyString))
  contexts["matrix"] = TyObject(MapObj(TyString))
  contexts["runner"] = make_runner_type()
  contexts["job"] = make_job_type()
  contexts["inputs"] = TyObject(MapObj(TyString))
  contexts["steps"] = TyObject(Strict({}))
  let needs_fields : Map[String, ExprType] = {}
  for need_id in job.needs {
    let mut found = false
    for j in all_jobs {
      if j.id == need_id {
        found = true
        break
      }
    }
    if found {
      needs_fields[need_id] = make_needs_job_type()
    }
  }
  contexts["needs"] = TyObject(Strict(needs_fields))
  { contexts, }
}
