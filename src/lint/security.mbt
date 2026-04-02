///|
/// Dangerous expression prefixes that indicate untrusted user input
let dangerous_prefixes : Array[String] = [
  "github.event.issue.title", "github.event.issue.body", "github.event.pull_request.title",
  "github.event.pull_request.body", "github.event.comment.body", "github.event.review.body",
  "github.event.discussion.title", "github.event.discussion.body", "github.event.pages.*.page_name",
  "github.event.commits.*.message", "github.event.head_commit.message", "github.event.head_commit.author.email",
  "github.event.head_commit.author.name", "github.head_ref", "github.event.workflow_run.head_branch",
  "github.event.workflow_run.head_commit.message",
]

///|
/// Deprecated workflow commands that should not be used in run scripts
let deprecated_commands : Array[(String, String)] = [
  ("::set-output name=", "deprecated, use GITHUB_OUTPUT"),
  ("::save-state name=", "deprecated, use GITHUB_STATE"),
  ("::set-env name=", "deprecated and DISABLED, use GITHUB_ENV"),
  ("::add-path::", "deprecated and DISABLED, use GITHUB_PATH"),
]

///|
/// Convert an Expr AST to a dot-path string for pattern matching
fn expr_to_dot_path(expr : Expr) -> String {
  match expr {
    Ident(name) => name
    PropertyAccess(obj, prop) => {
      let base = expr_to_dot_path(obj)
      if base.length() > 0 {
        "\{base}.\{prop}"
      } else {
        prop
      }
    }
    _ => ""
  }
}

///|
/// Check if an expression matches any dangerous pattern (untrusted input)
fn is_dangerous_expression(expr : Expr) -> Bool {
  let path = expr_to_dot_path(expr)
  if path.length() == 0 {
    return false
  }
  for prefix in dangerous_prefixes {
    // Handle wildcard patterns like github.event.pages.*.page_name
    if prefix.contains("*") {
      if matches_wildcard_pattern(path, prefix) {
        return true
      }
    } else if path == prefix || path.has_prefix(prefix + ".") {
      return true
    }
  }
  false
}

///|
/// Match a dot-path against a pattern with wildcards
fn matches_wildcard_pattern(path : String, pattern : String) -> Bool {
  let path_parts = split_dot_path(path)
  let pattern_parts = split_dot_path(pattern)
  if path_parts.length() < pattern_parts.length() {
    return false
  }
  for i, pp in pattern_parts {
    if i >= path_parts.length() {
      return false
    }
    if pp != "*" && pp != path_parts[i] {
      return false
    }
  }
  true
}

///|
/// Split a string by dots
fn split_dot_path(s : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  for ch in s {
    if ch == '.' {
      parts.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  if buf.to_string().length() > 0 {
    parts.push(buf.to_string())
  }
  parts
}

///|
/// Walk an expression tree and collect all dangerous sub-expressions
fn collect_dangerous_exprs(expr : Expr, results : Array[String]) -> Unit {
  if is_dangerous_expression(expr) {
    let path = expr_to_dot_path(expr)
    results.push(path)
    return
  }
  match expr {
    PropertyAccess(obj, _) => collect_dangerous_exprs(obj, results)
    IndexAccess(obj, idx) => {
      collect_dangerous_exprs(obj, results)
      collect_dangerous_exprs(idx, results)
    }
    UnaryOp(_, operand) => collect_dangerous_exprs(operand, results)
    BinaryOp(_, left, right) => {
      collect_dangerous_exprs(left, results)
      collect_dangerous_exprs(right, results)
    }
    FunctionCall(_, args) =>
      for arg in args {
        collect_dangerous_exprs(arg, results)
      }
    _ => ()
  }
}

///|
/// SEC01: Check for script injection via untrusted input in run: scripts
fn check_script_injection(
  workflow : @ar.WorkflowSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  for job in workflow.jobs {
    for i, step in job.steps {
      match step.run {
        Option::Some(script) => {
          let exprs = extract_expressions(script)
          for expr_str in exprs {
            let (expr, _errors) = parse_expression(expr_str)
            let dangerous : Array[String] = []
            collect_dangerous_exprs(expr, dangerous)
            for path in dangerous {
              diagnostics.push({
                severity: Warning,
                code: "script-injection",
                message: "potential script injection: untrusted input '\{path}' used directly in run script",
                job_id: job.id,
                step_index: i,
                field: "run",
              })
            }
          }
        }
        Option::None => ()
      }
    }
  }
}

///|
/// SEC02: Check for overly permissive permissions
fn check_permissions(
  workflow : @ar.WorkflowSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  // Check workflow-level permissions
  match workflow.permissions {
    Option::Some(perms) => check_permissions_spec(perms, "", -1, diagnostics)
    Option::None => ()
  }
  // Check job-level permissions
  for job in workflow.jobs {
    match job.permissions {
      Option::Some(perms) =>
        check_permissions_spec(perms, job.id, -1, diagnostics)
      Option::None => ()
    }
  }
}

///|
fn check_permissions_spec(
  perms : @ar.PermissionsSpec,
  job_id : String,
  step_index : Int,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  // Check for write-all
  match perms.values.get("_") {
    Option::Some(val) =>
      if val == "write-all" {
        diagnostics.push({
          severity: Warning,
          code: "permissive-permissions",
          message: "overly permissive permissions: 'write-all' grants write access to all scopes",
          job_id,
          step_index,
          field: "permissions",
        })
        return
      }
    Option::None => ()
  }
  // Count write permissions
  let mut write_count = 0
  let mut total_count = 0
  for key, value in perms.values {
    if key == "_" {
      continue
    }
    total_count += 1
    if value == "write" {
      write_count += 1
    }
  }
  // All listed permissions are write and there are more than 3
  if write_count == total_count && total_count > 3 {
    diagnostics.push({
      severity: Warning,
      code: "permissive-permissions",
      message: "overly permissive permissions: all \{total_count} permissions are set to 'write'",
      job_id,
      step_index,
      field: "permissions",
    })
  }
}

///|
/// SEC03: Check for deprecated workflow commands in run scripts
fn check_deprecated_commands(
  workflow : @ar.WorkflowSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  for job in workflow.jobs {
    for i, step in job.steps {
      match step.run {
        Option::Some(script) =>
          for item in deprecated_commands {
            let (pattern, reason) = item
            if script.contains(pattern) {
              diagnostics.push({
                severity: Warning,
                code: "deprecated-command",
                message: "deprecated workflow command '\{pattern}' (\{reason})",
                job_id: job.id,
                step_index: i,
                field: "run",
              })
            }
          }
        Option::None => ()
      }
    }
  }
}

///|
/// SEC04: pull_request_target without explicit permissions
fn check_pull_request_target_permissions(
  workflow : @ar.WorkflowSpec,
  yaml_text : String,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  if yaml_text.length() == 0 {
    return
  }
  // Check if yaml contains pull_request_target trigger
  if !yaml_text.contains("pull_request_target") {
    return
  }
  // pull_request_target is present — check for permissions
  match workflow.permissions {
    Option::Some(_) => () // workflow-level permissions set, OK
    Option::None => {
      // Check if all jobs have permissions set
      let mut all_jobs_have_perms = true
      for job in workflow.jobs {
        if job.permissions is Option::None {
          all_jobs_have_perms = false
          break
        }
      }
      if !all_jobs_have_perms {
        diagnostics.push({
          severity: Warning,
          code: "missing-prt-permissions",
          message: "workflow uses 'pull_request_target' trigger without explicit 'permissions' — this runs with write access to the base repo and should have minimal permissions",
          job_id: "",
          step_index: -1,
          field: "on",
        })
      }
    }
  }
}

///|
/// if-always: warn on bare `always()` in if condition
fn check_if_always(
  workflow : @ar.WorkflowSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  for job in workflow.jobs {
    // Check job-level
    let job_cond = job.if_condition.trim(chars=" \t\n\r").to_string()
    if is_bare_always(job_cond) {
      diagnostics.push({
        severity: Warning,
        code: "if-always",
        message: "use 'if: success() || failure()' instead of 'if: always()' to skip cancelled runs",
        job_id: job.id,
        step_index: -1,
        field: "if",
      })
    }
    for i, step in job.steps {
      let cond = step.if_condition.trim(chars=" \t\n\r").to_string()
      if is_bare_always(cond) {
        diagnostics.push({
          severity: Warning,
          code: "if-always",
          message: "use 'if: success() || failure()' instead of 'if: always()' to skip cancelled runs",
          job_id: job.id,
          step_index: i,
          field: "if",
        })
      }
    }
  }
}

///|
fn is_bare_always(cond : String) -> Bool {
  let c = unwrap_expression_text(cond)
  c == "always()" || c == "always"
}

///|
fn unwrap_expression_text(text : String) -> String {
  let prefix = "$\u007b\u007b"
  let suffix = "}}"
  if text.has_prefix(prefix) && text.has_suffix(suffix) && text.length() >= 5 {
    String::unsafe_substring(text, start=3, end=text.length() - 2)
    .trim(chars=" \t\n\r")
    .to_string()
  } else {
    text
  }
}

///|
/// dangerous-checkout-in-prt: checkout with PR head ref in pull_request_target
fn check_dangerous_checkout_in_prt(
  workflow : @ar.WorkflowSpec,
  yaml_text : String,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  if yaml_text.length() == 0 || !yaml_text.contains("pull_request_target") {
    return
  }
  for job in workflow.jobs {
    for i, step in job.steps {
      match step.uses {
        Option::Some(uses) =>
          if uses.contains("actions/checkout") {
            // Check if with.ref references PR head
            for _key, value in step.with_values {
              if value.contains("github.event.pull_request.head") {
                diagnostics.push({
                  severity: Error,
                  code: "dangerous-checkout-in-prt",
                  message: "checking out PR head in pull_request_target is dangerous — attacker code runs with write access",
                  job_id: job.id,
                  step_index: i,
                  field: "with",
                })
              }
            }
          }
        Option::None => ()
      }
    }
  }
}

///|
/// secrets-to-env-in-third-party: passing secrets via env to untrusted actions
fn check_secrets_to_third_party(
  workflow : @ar.WorkflowSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  for job in workflow.jobs {
    for i, step in job.steps {
      match step.uses {
        Option::Some(uses) => {
          // Skip trusted actions: actions/*, github/*, local paths
          if uses.has_prefix("actions/") ||
            uses.has_prefix("github/") ||
            uses.has_prefix("./") ||
            uses.has_prefix("docker://") {
            continue
          }
          // Check env for secrets references
          for key, value in step.env {
            if value.contains("secrets.") {
              diagnostics.push({
                severity: Warning,
                code: "secrets-to-third-party",
                message: "secret passed via env '\{key}' to third-party action '\{uses}' — consider using inputs instead",
                job_id: job.id,
                step_index: i,
                field: "env",
              })
            }
          }
        }
        Option::None => ()
      }
    }
  }
}

///|
/// Run all security checks on a workflow
pub fn check_security(
  workflow : @ar.WorkflowSpec,
  yaml_text? : String = "",
) -> Array[LintDiagnostic] {
  let diagnostics : Array[LintDiagnostic] = []
  check_script_injection(workflow, diagnostics)
  check_permissions(workflow, diagnostics)
  check_deprecated_commands(workflow, diagnostics)
  check_pull_request_target_permissions(workflow, yaml_text, diagnostics)
  check_if_always(workflow, diagnostics)
  check_dangerous_checkout_in_prt(workflow, yaml_text, diagnostics)
  check_secrets_to_third_party(workflow, diagnostics)
  diagnostics
}
