///|
/// Extract expression references from ${{ ... }} patterns in a string
fn extract_expressions(text : String) -> Array[String] {
  let result : Array[String] = []
  let prefix = "$\u007b\u007b" // ${{
  let suffix = "}}"
  let mut idx = 0
  while idx < text.length() {
    // Find "$\x7b\x7b"
    let mut found_start = -1
    let mut i = idx
    while i + prefix.length() <= text.length() {
      if String::unsafe_substring(text, start=i, end=i + prefix.length()) ==
        prefix {
        found_start = i
        break
      }
      i += 1
    }
    if found_start < 0 {
      break
    }
    // Find "}}"
    let expr_start = found_start + prefix.length()
    let mut j = expr_start
    let mut found_end = -1
    while j + suffix.length() <= text.length() {
      if String::unsafe_substring(text, start=j, end=j + suffix.length()) ==
        suffix {
        found_end = j
        break
      }
      j += 1
    }
    if found_end < 0 {
      break
    }
    let expr = String::unsafe_substring(text, start=expr_start, end=found_end)
      .trim(chars=" \t\n\r")
      .to_string()
    if expr.length() > 0 {
      result.push(expr)
    }
    idx = found_end + suffix.length()
  }
  result
}

///|
/// Check for unreachable steps (if: false or literal false condition)
fn check_unreachable_steps(
  job : @ar.JobSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  for i, step in job.steps {
    let cond = step.if_condition
    if cond == "false" || cond == "false()" {
      diagnostics.push({
        severity: Warning,
        code: "unreachable-step",
        message: "step is unreachable: condition is always false",
        job_id: job.id,
        step_index: i,
        field: "if",
      })
    }
  }
}

///|
/// Check for future step references (steps.foo where foo is defined after current step)
fn check_future_step_refs(
  job : @ar.JobSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  // Build map of step id -> index
  let step_indices : Map[String, Int] = {}
  for i, step in job.steps {
    if step.id.length() > 0 {
      step_indices[step.id] = i
    }
  }
  // Check each step's expressions
  for i, step in job.steps {
    let exprs_to_check : Array[String] = []
    // Collect all expressions from step fields
    if step.if_condition.length() > 0 && step.if_condition != "success()" {
      exprs_to_check.push(step.if_condition)
    }
    match step.run {
      Option::Some(run) =>
        for expr in extract_expressions(run) {
          exprs_to_check.push(expr)
        }
      Option::None => ()
    }
    for _key, value in step.env {
      for expr in extract_expressions(value) {
        exprs_to_check.push(expr)
      }
    }
    for _key, value in step.with_values {
      for expr in extract_expressions(value) {
        exprs_to_check.push(expr)
      }
    }
    // Parse each expression and look for steps.X references
    for expr_str in exprs_to_check {
      let (expr, _errors) = parse_expression(expr_str)
      check_step_refs_in_expr(expr, i, step_indices, job.id, diagnostics)
    }
  }
}

///|
fn check_step_refs_in_expr(
  expr : Expr,
  current_index : Int,
  step_indices : Map[String, Int],
  job_id : String,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  match expr {
    PropertyAccess(Ident("steps"), step_name) =>
      check_step_name_ref(
        step_name, current_index, step_indices, job_id, diagnostics,
      )
    PropertyAccess(PropertyAccess(Ident("steps"), step_name), _) =>
      check_step_name_ref(
        step_name, current_index, step_indices, job_id, diagnostics,
      )
    PropertyAccess(
      PropertyAccess(PropertyAccess(Ident("steps"), step_name), _),
      _
    ) =>
      check_step_name_ref(
        step_name, current_index, step_indices, job_id, diagnostics,
      )
    PropertyAccess(obj, _) =>
      check_step_refs_in_expr(
        obj, current_index, step_indices, job_id, diagnostics,
      )
    IndexAccess(obj, idx) => {
      check_step_refs_in_expr(
        obj, current_index, step_indices, job_id, diagnostics,
      )
      check_step_refs_in_expr(
        idx, current_index, step_indices, job_id, diagnostics,
      )
    }
    UnaryOp(_, operand) =>
      check_step_refs_in_expr(
        operand, current_index, step_indices, job_id, diagnostics,
      )
    BinaryOp(_, left, right) => {
      check_step_refs_in_expr(
        left, current_index, step_indices, job_id, diagnostics,
      )
      check_step_refs_in_expr(
        right, current_index, step_indices, job_id, diagnostics,
      )
    }
    FunctionCall(_, args) =>
      for arg in args {
        check_step_refs_in_expr(
          arg, current_index, step_indices, job_id, diagnostics,
        )
      }
    _ => ()
  }
}

///|
fn check_step_name_ref(
  step_name : String,
  current_index : Int,
  step_indices : Map[String, Int],
  job_id : String,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  if step_name == "*" {
    return
  }
  let opt : Int? = step_indices.get(step_name)
  match opt {
    Option::Some(def_index) =>
      if def_index >= current_index {
        diagnostics.push({
          severity: Error,
          code: "future-step-ref",
          message: "reference to future step '\{step_name}' (defined at index \{def_index}, current index \{current_index})",
          job_id,
          step_index: current_index,
          field: "expression",
        })
      }
    Option::None =>
      diagnostics.push({
        severity: Error,
        code: "undefined-step-ref",
        message: "reference to undefined step '\{step_name}'",
        job_id,
        step_index: current_index,
        field: "expression",
      })
  }
}

///|
/// Check for undefined needs references
fn check_undefined_needs(
  job : @ar.JobSpec,
  all_job_ids : Array[String],
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  for need_id in job.needs {
    let mut found = false
    for jid in all_job_ids {
      if jid == need_id {
        found = true
        break
      }
    }
    if not(found) {
      diagnostics.push({
        severity: Error,
        code: "undefined-needs",
        message: "job '\{job.id}' depends on undefined job '\{need_id}'",
        job_id: job.id,
        step_index: -1,
        field: "needs",
      })
    }
  }
}

///|
/// Check for cycles in job dependencies
fn check_dependency_cycles(
  jobs : Array[@ar.JobSpec],
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  // Build adjacency list
  let needs_map : Map[String, Array[String]] = {}
  for job in jobs {
    needs_map[job.id] = job.needs
  }
  // DFS cycle detection
  let visited : Map[String, Bool] = {} // fully processed
  let in_stack : Map[String, Bool] = {} // currently on recursion stack
  for job in jobs {
    if visited.get(job.id).unwrap_or(false) {
      continue
    }
    let cycle = dfs_find_cycle(job.id, needs_map, visited, in_stack, [])
    match cycle {
      Option::Some(path) => {
        diagnostics.push({
          severity: Error,
          code: "circular-needs",
          message: "circular dependency detected: \{path}",
          job_id: job.id,
          step_index: -1,
          field: "needs",
        })
        break
      }
      Option::None => ()
    }
  }
}

///|
fn dfs_find_cycle(
  node : String,
  graph : Map[String, Array[String]],
  visited : Map[String, Bool],
  in_stack : Map[String, Bool],
  path : Array[String],
) -> String? {
  if in_stack.get(node).unwrap_or(false) {
    // Found a cycle
    let cycle_path = path.copy()
    cycle_path.push(node)
    return Option::Some(cycle_path.join(" -> "))
  }
  if visited.get(node).unwrap_or(false) {
    return Option::None
  }
  in_stack[node] = true
  path.push(node)
  let opt : Array[String]? = graph.get(node)
  match opt {
    Option::Some(deps) =>
      for dep in deps {
        let result = dfs_find_cycle(dep, graph, visited, in_stack, path)
        match result {
          Option::Some(_) => return result
          Option::None => ()
        }
      }
    Option::None => ()
  }
  let _ = path.pop()
  in_stack[node] = false
  visited[node] = true
  Option::None
}

///|
/// Check for unused job outputs (declared but never referenced downstream)
fn check_unused_job_outputs(
  workflow : @ar.WorkflowSpec,
  diagnostics : Array[LintDiagnostic],
) -> Unit {
  // Collect all output references from all expressions in all jobs
  let referenced_outputs : Map[String, Bool] = {} // "job_id.output_key"
  for job in workflow.jobs {
    for step in job.steps {
      let exprs : Array[String] = []
      if step.if_condition.length() > 0 && step.if_condition != "success()" {
        exprs.push(step.if_condition)
      }
      match step.run {
        Option::Some(run) =>
          for expr in extract_expressions(run) {
            exprs.push(expr)
          }
        Option::None => ()
      }
      for _key, value in step.env {
        for expr in extract_expressions(value) {
          exprs.push(expr)
        }
      }
      for _key, value in step.with_values {
        for expr in extract_expressions(value) {
          exprs.push(expr)
        }
      }
      for expr_str in exprs {
        let (expr, _) = parse_expression(expr_str)
        collect_needs_output_refs(expr, referenced_outputs)
      }
    }
    // Also check job output expressions
    for _key, value in job.outputs {
      for expr in extract_expressions(value) {
        let (parsed, _) = parse_expression(expr)
        collect_needs_output_refs(parsed, referenced_outputs)
      }
    }
  }
  // Now check each job's outputs
  for job in workflow.jobs {
    if job.outputs.length() == 0 {
      continue
    }
    // Check if any downstream job references this job's outputs
    let mut any_referenced = false
    for key, _ in job.outputs {
      let ref_key = "\{job.id}.\{key}"
      if referenced_outputs.get(ref_key).unwrap_or(false) {
        any_referenced = true
        break
      }
    }
    if not(any_referenced) {
      // Check if any job depends on this job at all
      let mut has_downstream = false
      for other_job in workflow.jobs {
        for need_id in other_job.needs {
          if need_id == job.id {
            has_downstream = true
            break
          }
        }
        if has_downstream {
          break
        }
      }
      if has_downstream {
        diagnostics.push({
          severity: Warning,
          code: "unused-outputs",
          message: "job '\{job.id}' declares outputs but they are not referenced by downstream jobs",
          job_id: job.id,
          step_index: -1,
          field: "outputs",
        })
      }
    }
  }
}

///|
fn collect_needs_output_refs(expr : Expr, refs : Map[String, Bool]) -> Unit {
  match expr {
    // needs.JOB.outputs.KEY
    PropertyAccess(
      PropertyAccess(PropertyAccess(Ident("needs"), job_id), "outputs"),
      key
    ) => refs["\{job_id}.\{key}"] = true
    PropertyAccess(obj, _) => collect_needs_output_refs(obj, refs)
    IndexAccess(obj, idx) => {
      collect_needs_output_refs(obj, refs)
      collect_needs_output_refs(idx, refs)
    }
    UnaryOp(_, operand) => collect_needs_output_refs(operand, refs)
    BinaryOp(_, left, right) => {
      collect_needs_output_refs(left, refs)
      collect_needs_output_refs(right, refs)
    }
    FunctionCall(_, args) =>
      for arg in args {
        collect_needs_output_refs(arg, refs)
      }
    _ => ()
  }
}

///|
/// Run all dead code checks on a workflow
pub fn check_dead_code(workflow : @ar.WorkflowSpec) -> Array[LintDiagnostic] {
  let diagnostics : Array[LintDiagnostic] = []
  let all_job_ids : Array[String] = []
  for job in workflow.jobs {
    all_job_ids.push(job.id)
  }
  for job in workflow.jobs {
    check_unreachable_steps(job, diagnostics)
    check_future_step_refs(job, diagnostics)
    check_undefined_needs(job, all_job_ids, diagnostics)
  }
  check_dependency_cycles(workflow.jobs, diagnostics)
  check_unused_job_outputs(workflow, diagnostics)
  diagnostics
}
