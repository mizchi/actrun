///|
/// Check semantic validity of a workflow spec
pub fn check_semantics(workflow : @ar.WorkflowSpec) -> Array[LintDiagnostic] {
  let diagnostics : Array[LintDiagnostic] = []
  // S006: Invalid uses syntax
  for job in workflow.jobs {
    for i, step in job.steps {
      match step.uses {
        Option::Some(uses_str) =>
          if !is_valid_uses(uses_str) {
            diagnostics.push({
              severity: Error,
              code: "invalid-uses",
              message: "invalid 'uses' syntax: '\{uses_str}' (expected 'owner/repo@ref', './local/path', or 'docker://image')",
              job_id: job.id,
              step_index: i,
              field: "uses",
            })
          }
        Option::None => ()
      }
    }
  }
  // S009: Invalid glob patterns in branches/paths
  check_trigger_globs(workflow.trigger, "trigger", diagnostics)
  match workflow.pull_request_trigger {
    Option::Some(pr_trigger) =>
      check_trigger_globs(pr_trigger, "pull_request_trigger", diagnostics)
    Option::None => ()
  }
  // S010: Always-true/false compound conditions
  for job in workflow.jobs {
    for i, step in job.steps {
      if step.if_condition.length() > 0 && step.if_condition != "success()" {
        let expr_str = unwrap_expression(step.if_condition)
        let (expr, _errors) = parse_expression(expr_str)
        check_tautology(expr, job.id, i, diagnostics)
      }
    }
  }
  diagnostics
}

///|
fn is_valid_uses(uses : String) -> Bool {
  // Local path
  if uses.has_prefix("./") {
    return true
  }
  // Docker image
  if uses.has_prefix("docker://") {
    return true
  }
  // owner/repo@ref or owner/repo/path@ref
  if uses.contains("/") && uses.contains("@") {
    return true
  }
  false
}

///|
fn check_trigger_globs(
  trigger : @ar.PushTrigger,
  field_prefix : String,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  check_glob_array(trigger.branches, "\{field_prefix}.branches", diagnostics)
  check_glob_array(
    trigger.branches_ignore,
    "\{field_prefix}.branches_ignore",
    diagnostics,
  )
  check_glob_array(trigger.paths, "\{field_prefix}.paths", diagnostics)
  check_glob_array(
    trigger.paths_ignore,
    "\{field_prefix}.paths_ignore",
    diagnostics,
  )
  check_glob_array(trigger.tags, "\{field_prefix}.tags", diagnostics)
  check_glob_array(
    trigger.tags_ignore,
    "\{field_prefix}.tags_ignore",
    diagnostics,
  )
}

///|
fn check_glob_array(
  patterns : Array[String],
  field : String,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  for pattern in patterns {
    match validate_glob(pattern) {
      Option::Some(msg) =>
        diagnostics.push({
          severity: Warning,
          code: "invalid-glob",
          message: "invalid glob pattern '\{pattern}': \{msg}",
          job_id: "",
          step_index: -1,
          field,
        })
      Option::None => ()
    }
  }
}

///|
fn validate_glob(pattern : String) -> String? {
  if pattern.length() == 0 {
    return Option::Some("empty pattern")
  }
  // Check unbalanced brackets
  let mut bracket_depth = 0
  let mut brace_depth = 0
  for ch in pattern {
    if ch == '[' {
      bracket_depth += 1
    } else if ch == ']' {
      bracket_depth -= 1
    } else if ch == '{' {
      brace_depth += 1
    } else if ch == '}' {
      brace_depth -= 1
    }
  }
  if bracket_depth != 0 {
    return Option::Some("unbalanced brackets '['")
  }
  if brace_depth != 0 {
    return Option::Some("unclosed '{'")
  }
  Option::None
}

///|
fn check_tautology(
  expr : Expr,
  job_id : String,
  step_index : Int,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  // Direct literal true
  match expr {
    Literal(LitBool(true)) => {
      diagnostics.push({
        severity: Warning,
        code: "redundant-condition",
        message: "condition is always true (literal 'true')",
        job_id,
        step_index,
        field: "if",
      })
      return
    }
    _ => ()
  }
  // Check compound conditions
  match classify_condition(expr) {
    AlwaysTrue(reason) =>
      diagnostics.push({
        severity: Warning,
        code: "redundant-condition",
        message: "condition is always true: \{reason}",
        job_id,
        step_index,
        field: "if",
      })
    AlwaysFalse(reason) =>
      diagnostics.push({
        severity: Warning,
        code: "redundant-condition",
        message: "condition is always false: \{reason}",
        job_id,
        step_index,
        field: "if",
      })
    Normal => ()
  }
}

///|
priv enum ConditionResult {
  AlwaysTrue(String)
  AlwaysFalse(String)
  Normal
}

///|
fn classify_condition(expr : Expr) -> ConditionResult {
  match expr {
    // failure() && success() -> always false
    BinaryOp(OpAnd, FunctionCall("failure", _), FunctionCall("success", _)) =>
      AlwaysFalse("failure() && success() are mutually exclusive")
    BinaryOp(OpAnd, FunctionCall("success", _), FunctionCall("failure", _)) =>
      AlwaysFalse("success() && failure() are mutually exclusive")
    // always() && false -> always false
    BinaryOp(OpAnd, FunctionCall("always", _), Literal(LitBool(false))) =>
      AlwaysFalse("always() && false is always false")
    BinaryOp(OpAnd, Literal(LitBool(false)), FunctionCall("always", _)) =>
      AlwaysFalse("false && always() is always false")
    // true || <anything> -> always true (redundant)
    BinaryOp(OpOr, Literal(LitBool(true)), _) =>
      AlwaysTrue("true || ... is always true")
    BinaryOp(OpOr, _, Literal(LitBool(true))) =>
      AlwaysTrue("... || true is always true")
    _ => Normal
  }
}
