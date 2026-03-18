///|
/// Tier 1 structure validation checks for workflow specs.
pub fn check_structure(
  workflow : @ar.WorkflowSpec,
  strict? : Bool = false,
) -> Array[LintDiagnostic] {
  let diagnostics : Array[LintDiagnostic] = []
  for job in workflow.jobs {
    check_duplicate_step_ids(job, diagnostics)
    check_empty_runs_on(job, diagnostics)
    check_empty_job(job, diagnostics)
    check_step_uses_and_run(job, diagnostics)
    check_empty_matrix(job, diagnostics)
    if strict {
      check_missing_timeout(job, diagnostics)
    }
  }
  diagnostics
}

///|
/// S001: Duplicate step IDs in same job
fn check_duplicate_step_ids(
  job : @ar.JobSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  let seen : Map[String, Int] = {}
  for i, step in job.steps {
    if step.id.length() > 0 {
      match seen.get(step.id) {
        Option::Some(prev_index) =>
          diagnostics.push({
            severity: Error,
            code: "duplicate-step-id",
            message: "duplicate step id '\{step.id}' (first defined at step \{prev_index})",
            job_id: job.id,
            step_index: i,
            field: "id",
          })
        Option::None => seen[step.id] = i
      }
    }
  }
}

///|
/// S002: Empty runs-on (required unless reusable workflow)
fn check_empty_runs_on(
  job : @ar.JobSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  match job.reusable_workflow {
    Option::Some(_) => ()
    Option::None =>
      if job.runs_on.length() == 0 {
        diagnostics.push({
          severity: Error,
          code: "missing-runs-on",
          message: "job '\{job.id}' has empty runs-on and is not a reusable workflow call",
          job_id: job.id,
          step_index: -1,
          field: "runs-on",
        })
      }
  }
}

///|
/// S003: Empty job (no steps, not reusable workflow)
fn check_empty_job(
  job : @ar.JobSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  match job.reusable_workflow {
    Option::Some(_) => ()
    Option::None =>
      if job.steps.length() == 0 {
        diagnostics.push({
          severity: Error,
          code: "empty-job",
          message: "job '\{job.id}' has no steps and is not a reusable workflow call",
          job_id: job.id,
          step_index: -1,
          field: "steps",
        })
      }
  }
}

///|
/// S004: Step has both uses and run
fn check_step_uses_and_run(
  job : @ar.JobSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  for i, step in job.steps {
    let has_uses = match step.uses {
      Option::Some(_) => true
      Option::None => false
    }
    let has_run = match step.run {
      Option::Some(_) => true
      Option::None => false
    }
    if has_uses && has_run {
      diagnostics.push({
        severity: Error,
        code: "uses-and-run",
        message: "step has both 'uses' and 'run' defined",
        job_id: job.id,
        step_index: i,
        field: "uses/run",
      })
    }
  }
}

///|
/// S005: Matrix with empty rows
fn check_empty_matrix(
  job : @ar.JobSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  match job.matrix {
    Option::Some(m) =>
      if m.rows.length() == 0 {
        diagnostics.push({
          severity: Warning,
          code: "empty-matrix",
          message: "job '\{job.id}' has a matrix with no rows",
          job_id: job.id,
          step_index: -1,
          field: "matrix",
        })
      }
    Option::None => ()
  }
}

///|
/// missing-timeout: Job without timeout-minutes (strict only)
fn check_missing_timeout(
  job : @ar.JobSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  // Skip reusable workflow calls
  if job.reusable_workflow is Option::Some(_) {
    return
  }
  if job.timeout_minutes == 0 {
    diagnostics.push({
      severity: Warning,
      code: "missing-timeout",
      message: "job '\{job.id}' has no timeout-minutes (default is 360 min). Consider setting an explicit timeout",
      job_id: job.id,
      step_index: -1,
      field: "timeout-minutes",
    })
  }
}
