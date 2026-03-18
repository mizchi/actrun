///|
pub struct LintOptions {
  strict : Bool // enables missing-timeout
  online : Bool // enables mutable-action-ref + existence check
  yaml_text : String // raw YAML for text-level checks
} derive(Show)

///|
pub fn default_lint_options() -> LintOptions {
  { strict: false, online: false, yaml_text: "" }
}

///|
pub fn new_lint_options(
  strict? : Bool = false,
  online? : Bool = false,
  yaml_text? : String = "",
) -> LintOptions {
  { strict, online, yaml_text }
}

///|
/// Apply preset to LintOptions. Returns (strict, online).
pub fn apply_preset(preset : String) -> (Bool, Bool) {
  match preset {
    "strict" => (true, false)
    "oss" => (true, true)
    _ => (false, false) // "default" or unknown
  }
}

///|
/// Lint a parsed workflow spec, returning all diagnostics
pub fn lint_workflow(
  workflow : @ar.WorkflowSpec,
  yaml_text? : String = "",
  options? : LintOptions = { strict: false, online: false, yaml_text: "" },
) -> Array[LintDiagnostic] {
  let effective_yaml = if yaml_text.length() > 0 {
    yaml_text
  } else {
    options.yaml_text
  }
  let diagnostics : Array[LintDiagnostic] = []
  // Phase 2: Type-check all expressions
  for job in workflow.jobs {
    // Check job-level if condition
    if job.if_condition.length() > 0 && job.if_condition != "success()" {
      let ctx = build_job_lint_context(job, workflow.jobs)
      let expr_str = unwrap_expression(job.if_condition)
      let diags = check_expression(expr_str, ctx, job.id, -1, "if")
      for d in diags {
        diagnostics.push(d)
      }
    }
    // Check step-level expressions
    for i, step in job.steps {
      let ctx = build_lint_context(job, i, workflow.jobs)
      // Check if condition
      if step.if_condition.length() > 0 && step.if_condition != "success()" {
        let expr_str = unwrap_expression(step.if_condition)
        let diags = check_expression(expr_str, ctx, job.id, i, "if")
        for d in diags {
          diagnostics.push(d)
        }
      }
      // Check expressions in run scripts
      match step.run {
        Option::Some(run) =>
          for expr in extract_expressions(run) {
            let diags = check_expression(expr, ctx, job.id, i, "run")
            for d in diags {
              diagnostics.push(d)
            }
          }
        Option::None => ()
      }
      // Check expressions in env values
      for _key, value in step.env {
        for expr in extract_expressions(value) {
          let diags = check_expression(expr, ctx, job.id, i, "env")
          for d in diags {
            diagnostics.push(d)
          }
        }
      }
      // Check expressions in with values
      for _key, value in step.with_values {
        for expr in extract_expressions(value) {
          let diags = check_expression(expr, ctx, job.id, i, "with")
          for d in diags {
            diagnostics.push(d)
          }
        }
      }
    }
    // Check job output expressions
    for _key, value in job.outputs {
      let ctx = build_lint_context(job, job.steps.length(), workflow.jobs)
      for expr in extract_expressions(value) {
        let diags = check_expression(expr, ctx, job.id, -1, "outputs")
        for d in diags {
          diagnostics.push(d)
        }
      }
    }
  }
  // Phase 1.5: Structure validation
  let structure_diags = check_structure(workflow, strict=options.strict)
  for d in structure_diags {
    diagnostics.push(d)
  }
  // Phase 3: Dead code detection
  let dead_code_diags = check_dead_code(workflow)
  for d in dead_code_diags {
    diagnostics.push(d)
  }
  // Phase 4: Security checks
  let security_diags = check_security(workflow, yaml_text=effective_yaml)
  for d in security_diags {
    diagnostics.push(d)
  }
  // Phase 5: Semantic checks
  let semantics_diags = check_semantics(workflow)
  for d in semantics_diags {
    diagnostics.push(d)
  }
  diagnostics
}

///|
/// Strip ${{ }} wrapper if present, like the existing unwrap_if_expression
fn unwrap_expression(text : String) -> String {
  let trimmed = text.trim(chars=" \t\n\r").to_string()
  let prefix = "$\u007b\u007b"
  let suffix = "}}"
  if trimmed.has_prefix(prefix) &&
    trimmed.has_suffix(suffix) &&
    trimmed.length() >= 5 {
    String::unsafe_substring(trimmed, start=3, end=trimmed.length() - 2)
    .trim(chars=" \t\n\r")
    .to_string()
  } else {
    trimmed
  }
}

///|
pub fn filter_diagnostics(
  diagnostics : Array[LintDiagnostic],
  ignore_rules : Array[String],
) -> Array[LintDiagnostic] {
  if ignore_rules.length() == 0 {
    return diagnostics
  }
  let result : Array[LintDiagnostic] = []
  for d in diagnostics {
    let mut ignored = false
    for rule in ignore_rules {
      if d.code == rule {
        ignored = true
        break
      }
    }
    if not(ignored) {
      result.push(d)
    }
  }
  result
}

///|
/// Default rules to ignore (noisy warnings that most users don't want)
pub let default_ignore_rules : Array[String] = []

///|
pub fn format_diagnostics(diagnostics : Array[LintDiagnostic]) -> String {
  let lines : Array[String] = []
  for d in diagnostics {
    lines.push(d.format())
  }
  lines.join("\n")
}

///|
pub fn has_errors(diagnostics : Array[LintDiagnostic]) -> Bool {
  for d in diagnostics {
    if d.severity == Error {
      return true
    }
  }
  false
}
