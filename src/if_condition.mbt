///|
priv enum ConditionValue {
  Bool(Bool)
  String(String)
}

///|
priv struct IfConditionContext {
  step_outputs : Map[String, Map[String, String]]
  step_outcomes : Map[String, String]
  step_conclusions : Map[String, String]
  env_context : Map[String, String]
  github_context : Map[String, String]
  runner_context : Map[String, String]
  needs_outputs : Map[String, Map[String, String]]
  needs_results : Map[String, String]
  success_value : Bool
  failure_value : Bool
  cancelled_value : Bool
}

///|
fn new_if_condition_context(
  step_outputs? : Map[String, Map[String, String]] = {},
  step_outcomes? : Map[String, String] = {},
  step_conclusions? : Map[String, String] = {},
  env_context? : Map[String, String] = {},
  github_context? : Map[String, String] = {},
  runner_context? : Map[String, String] = {},
  needs_outputs? : Map[String, Map[String, String]] = {},
  needs_results? : Map[String, String] = {},
  success_value? : Bool = true,
  failure_value? : Bool = false,
  cancelled_value? : Bool = false,
) -> IfConditionContext {
  {
    step_outputs,
    step_outcomes,
    step_conclusions,
    env_context,
    github_context,
    runner_context,
    needs_outputs,
    needs_results,
    success_value,
    failure_value,
    cancelled_value,
  }
}

///|
fn if_text_slice(text : String, start : Int, end_ : Int) -> String {
  String::unsafe_substring(text, start~, end=end_)
}

///|
fn find_if_substring(text : String, pattern : String, start : Int) -> Int? {
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
fn unwrap_if_expression(text : String) -> String {
  let trimmed = text.trim(chars=" \t\n\r").to_string()
  if trimmed.has_prefix("${{") &&
    trimmed.has_suffix("}}") &&
    trimmed.length() >= 5 {
    if_text_slice(trimmed, 3, trimmed.length() - 2)
    .trim(chars=" \t\n\r")
    .to_string()
  } else {
    trimmed
  }
}

///|
fn if_expression_has_outer_parens(text : String) -> Bool {
  guard text.length() >= 2 &&
    text.unsafe_get(0) == '(' &&
    text.unsafe_get(text.length() - 1) == ')' else {
    return false
  }
  let mut depth = 0
  let mut in_single = false
  let mut in_double = false
  let mut idx = 0
  while idx < text.length() {
    let ch = text.unsafe_get(idx)
    if ch == '\'' && not(in_double) {
      in_single = not(in_single)
      idx += 1
      continue
    }
    if ch == '"' && not(in_single) {
      in_double = not(in_double)
      idx += 1
      continue
    }
    if not(in_single) && not(in_double) {
      if ch == '(' {
        depth += 1
      } else if ch == ')' {
        depth -= 1
        if depth == 0 && idx != text.length() - 1 {
          return false
        }
      }
    }
    idx += 1
  }
  depth == 0
}

///|
fn strip_if_outer_parens(text : String) -> String {
  let mut current = unwrap_if_expression(text)
  while if_expression_has_outer_parens(current) {
    current = if_text_slice(current, 1, current.length() - 1)
      .trim(chars=" \t\n\r")
      .to_string()
  }
  current
}

///|
fn find_top_level_if_operator(text : String, op : String) -> Int? {
  guard op.length() > 0 else { return None }
  let mut depth = 0
  let mut in_single = false
  let mut in_double = false
  let mut idx = 0
  while idx + op.length() <= text.length() {
    let ch = text.unsafe_get(idx)
    if ch == '\'' && not(in_double) {
      in_single = not(in_single)
      idx += 1
      continue
    }
    if ch == '"' && not(in_single) {
      in_double = not(in_double)
      idx += 1
      continue
    }
    if not(in_single) && not(in_double) {
      if ch == '(' {
        depth += 1
        idx += 1
        continue
      }
      if ch == ')' {
        depth -= 1
        idx += 1
        continue
      }
      if depth == 0 {
        let mut matched = true
        let mut offset = 0
        while offset < op.length() {
          if text.unsafe_get(idx + offset) != op.unsafe_get(offset) {
            matched = false
            break
          }
          offset += 1
        }
        if matched {
          return Some(idx)
        }
      }
    }
    idx += 1
  }
  None
}

///|
fn if_bool_literal(text : String) -> Bool? {
  let trimmed = strip_if_outer_parens(text)
  if trimmed == "true" {
    Some(true)
  } else if trimmed == "false" {
    Some(false)
  } else {
    None
  }
}

///|
fn if_quoted_string(text : String) -> String? {
  let trimmed = strip_if_outer_parens(text)
  if trimmed.length() >= 2 &&
    (
      (
        trimmed.unsafe_get(0) == '\'' &&
        trimmed.unsafe_get(trimmed.length() - 1) == '\''
      ) ||
      (
        trimmed.unsafe_get(0) == '"' &&
        trimmed.unsafe_get(trimmed.length() - 1) == '"'
      )
    ) {
    Some(if_text_slice(trimmed, 1, trimmed.length() - 1))
  } else {
    None
  }
}

///|
fn if_step_output_name(expression : String) -> (String, String)? {
  let trimmed = strip_if_outer_parens(expression)
  guard trimmed.has_prefix("steps.") && trimmed.length() > 6 else {
    return None
  }
  guard find_if_substring(trimmed, ".outputs.", 6) is Some(outputs_idx) else {
    return None
  }
  let step_id = if_text_slice(trimmed, 6, outputs_idx)
  let output_name = if_text_slice(trimmed, outputs_idx + 9, trimmed.length())
  if step_id.length() == 0 || output_name.length() == 0 {
    None
  } else {
    Some((step_id, output_name))
  }
}

///|
fn if_step_status_name(expression : String, suffix : String) -> String? {
  let trimmed = strip_if_outer_parens(expression)
  guard trimmed.has_prefix("steps.") && trimmed.has_suffix(suffix) else {
    return None
  }
  let step_id = if_text_slice(trimmed, 6, trimmed.length() - suffix.length())
  if step_id.length() == 0 {
    None
  } else {
    Some(step_id)
  }
}

///|
fn if_needs_output_name(expression : String) -> (String, String)? {
  let trimmed = strip_if_outer_parens(expression)
  guard trimmed.has_prefix("needs.") && trimmed.length() > 6 else {
    return None
  }
  guard find_if_substring(trimmed, ".outputs.", 6) is Some(outputs_idx) else {
    return None
  }
  let job_id = if_text_slice(trimmed, 6, outputs_idx)
  let output_name = if_text_slice(trimmed, outputs_idx + 9, trimmed.length())
  if job_id.length() == 0 || output_name.length() == 0 {
    None
  } else {
    Some((job_id, output_name))
  }
}

///|
fn if_needs_result_name(expression : String) -> String? {
  let trimmed = strip_if_outer_parens(expression)
  guard trimmed.has_prefix("needs.") && trimmed.has_suffix(".result") else {
    return None
  }
  let job_id = if_text_slice(trimmed, 6, trimmed.length() - 7)
  if job_id.length() == 0 {
    None
  } else {
    Some(job_id)
  }
}

///|
fn if_env_name(expression : String) -> String? {
  let trimmed = strip_if_outer_parens(expression)
  if trimmed.has_prefix("env.") && trimmed.length() > 4 {
    Some(if_text_slice(trimmed, 4, trimmed.length()))
  } else {
    None
  }
}

///|
fn if_github_name(expression : String) -> String? {
  let trimmed = strip_if_outer_parens(expression)
  if trimmed.has_prefix("github.") && trimmed.length() > 7 {
    Some(if_text_slice(trimmed, 7, trimmed.length()))
  } else {
    None
  }
}

///|
fn if_runner_name(expression : String) -> String? {
  let trimmed = strip_if_outer_parens(expression)
  if trimmed.has_prefix("runner.") && trimmed.length() > 7 {
    Some(if_text_slice(trimmed, 7, trimmed.length()))
  } else {
    None
  }
}

///|
fn[V] if_map_get_case_insensitive(values : Map[String, V], key : String) -> V? {
  match values.get(key) {
    Some(value) => Some(value)
    None => {
      let needle = key.to_lower()
      for existing_key, value in values {
        if existing_key.to_lower() == needle {
          return Some(value)
        }
      }
      None
    }
  }
}

///|
fn resolve_if_step_output(
  step_outputs : Map[String, Map[String, String]],
  step_id : String,
  output_name : String,
) -> String {
  match if_map_get_case_insensitive(step_outputs, step_id) {
    Some(outputs) =>
      if_map_get_case_insensitive(outputs, output_name).unwrap_or("")
    None => ""
  }
}

///|
fn resolve_if_step_status(
  values : Map[String, String],
  step_id : String,
) -> String {
  if_map_get_case_insensitive(values, step_id).unwrap_or("")
}

///|
fn resolve_if_needs_output(
  needs_outputs : Map[String, Map[String, String]],
  job_id : String,
  output_name : String,
) -> String {
  match if_map_get_case_insensitive(needs_outputs, job_id) {
    Some(outputs) =>
      if_map_get_case_insensitive(outputs, output_name).unwrap_or("")
    None => ""
  }
}

///|
fn resolve_if_needs_result(
  needs_results : Map[String, String],
  job_id : String,
) -> String {
  if_map_get_case_insensitive(needs_results, job_id).unwrap_or("")
}

///|
fn condition_expression_has_status_check(text : String) -> Bool {
  let trimmed = unwrap_if_expression(text)
  trimmed.contains("success()") ||
  trimmed.contains("always()") ||
  trimmed.contains("failure()") ||
  trimmed.contains("cancelled()")
}

///|
fn if_condition_atom_supported(text : String) -> Bool {
  if if_bool_literal(text) is Some(_) {
    return true
  }
  if if_quoted_string(text) is Some(_) {
    return true
  }
  let trimmed = strip_if_outer_parens(text)
  if trimmed == "success()" ||
    trimmed == "always()" ||
    trimmed == "failure()" ||
    trimmed == "cancelled()" {
    return true
  }
  if if_step_output_name(trimmed) is Some(_) {
    return true
  }
  if if_step_status_name(trimmed, ".outcome") is Some(_) {
    return true
  }
  if if_step_status_name(trimmed, ".conclusion") is Some(_) {
    return true
  }
  if if_needs_output_name(trimmed) is Some(_) {
    return true
  }
  if if_needs_result_name(trimmed) is Some(_) {
    return true
  }
  if if_env_name(trimmed) is Some(_) {
    return true
  }
  if if_github_name(trimmed) is Some(_) {
    return true
  }
  if if_runner_name(trimmed) is Some(_) {
    return true
  }
  false
}

///|
fn if_condition_supported(text : String) -> Bool {
  let trimmed = strip_if_outer_parens(text)
  if trimmed.length() == 0 {
    return true
  }
  match find_top_level_if_operator(trimmed, "||") {
    Some(idx) =>
      return if_condition_supported(if_text_slice(trimmed, 0, idx)) &&
        if_condition_supported(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
        )
    None => ()
  }
  match find_top_level_if_operator(trimmed, "&&") {
    Some(idx) =>
      return if_condition_supported(if_text_slice(trimmed, 0, idx)) &&
        if_condition_supported(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
        )
    None => ()
  }
  match find_top_level_if_operator(trimmed, "!=") {
    Some(idx) =>
      return if_condition_supported(if_text_slice(trimmed, 0, idx)) &&
        if_condition_supported(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
        )
    None => ()
  }
  match find_top_level_if_operator(trimmed, "==") {
    Some(idx) =>
      return if_condition_supported(if_text_slice(trimmed, 0, idx)) &&
        if_condition_supported(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
        )
    None => ()
  }
  if trimmed.has_prefix("!") {
    return if_condition_supported(if_text_slice(trimmed, 1, trimmed.length()))
  }
  if_condition_atom_supported(trimmed)
}

///|
fn if_condition_value_truthy(value : ConditionValue) -> Bool {
  match value {
    Bool(flag) => flag
    String(text) => text.length() > 0
  }
}

///|
fn if_condition_value_eq(left : ConditionValue, right : ConditionValue) -> Bool {
  match left {
    Bool(left_flag) => {
      let left_text = if left_flag { "true" } else { "false" }
      match right {
        Bool(right_flag) => left_flag == right_flag
        String(right_text) => left_text == right_text
      }
    }
    String(left_text) =>
      match right {
        Bool(right_flag) => {
          let right_text = if right_flag { "true" } else { "false" }
          left_text == right_text
        }
        String(right_text) => left_text == right_text
      }
  }
}

///|
fn if_condition_atom_value(
  text : String,
  ctx : IfConditionContext,
) -> ConditionValue {
  match if_bool_literal(text) {
    Some(value) => return Bool(value)
    None => ()
  }
  match if_quoted_string(text) {
    Some(value) => return String(value)
    None => ()
  }
  let trimmed = strip_if_outer_parens(text)
  if trimmed == "success()" {
    return Bool(ctx.success_value)
  }
  if trimmed == "always()" {
    return Bool(true)
  }
  if trimmed == "failure()" {
    return Bool(ctx.failure_value)
  }
  if trimmed == "cancelled()" {
    return Bool(ctx.cancelled_value)
  }
  match if_step_output_name(trimmed) {
    Some((step_id, output_name)) =>
      return String(
        resolve_if_step_output(ctx.step_outputs, step_id, output_name),
      )
    None => ()
  }
  match if_step_status_name(trimmed, ".outcome") {
    Some(step_id) =>
      return String(resolve_if_step_status(ctx.step_outcomes, step_id))
    None => ()
  }
  match if_step_status_name(trimmed, ".conclusion") {
    Some(step_id) =>
      return String(resolve_if_step_status(ctx.step_conclusions, step_id))
    None => ()
  }
  match if_needs_output_name(trimmed) {
    Some((job_id, output_name)) =>
      return String(
        resolve_if_needs_output(ctx.needs_outputs, job_id, output_name),
      )
    None => ()
  }
  match if_needs_result_name(trimmed) {
    Some(job_id) =>
      return String(resolve_if_needs_result(ctx.needs_results, job_id))
    None => ()
  }
  match if_env_name(trimmed) {
    Some(name) =>
      return String(
        if_map_get_case_insensitive(ctx.env_context, name).unwrap_or(""),
      )
    None => ()
  }
  match if_github_name(trimmed) {
    Some(name) =>
      return String(
        if_map_get_case_insensitive(ctx.github_context, name).unwrap_or(""),
      )
    None => ()
  }
  match if_runner_name(trimmed) {
    Some(name) =>
      return String(
        if_map_get_case_insensitive(ctx.runner_context, name).unwrap_or(""),
      )
    None => ()
  }
  String("")
}

///|
fn eval_if_condition_bool(text : String, ctx : IfConditionContext) -> Bool {
  let trimmed = strip_if_outer_parens(text)
  if trimmed.length() == 0 {
    return true
  }
  match find_top_level_if_operator(trimmed, "||") {
    Some(idx) =>
      return eval_if_condition_bool(if_text_slice(trimmed, 0, idx), ctx) ||
        eval_if_condition_bool(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
          ctx,
        )
    None => ()
  }
  match find_top_level_if_operator(trimmed, "&&") {
    Some(idx) =>
      return eval_if_condition_bool(if_text_slice(trimmed, 0, idx), ctx) &&
        eval_if_condition_bool(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
          ctx,
        )
    None => ()
  }
  match find_top_level_if_operator(trimmed, "!=") {
    Some(idx) =>
      return not(
        if_condition_value_eq(
          if_condition_atom_value(if_text_slice(trimmed, 0, idx), ctx),
          if_condition_atom_value(
            if_text_slice(trimmed, idx + 2, trimmed.length()),
            ctx,
          ),
        ),
      )
    None => ()
  }
  match find_top_level_if_operator(trimmed, "==") {
    Some(idx) =>
      return if_condition_value_eq(
        if_condition_atom_value(if_text_slice(trimmed, 0, idx), ctx),
        if_condition_atom_value(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
          ctx,
        ),
      )
    None => ()
  }
  if trimmed.has_prefix("!") {
    return not(
      eval_if_condition_bool(if_text_slice(trimmed, 1, trimmed.length()), ctx),
    )
  }
  if_condition_value_truthy(if_condition_atom_value(trimmed, ctx))
}

///|
fn evaluate_if_condition(text : String, ctx : IfConditionContext) -> Bool {
  let trimmed = unwrap_if_expression(text)
  if trimmed.length() == 0 {
    return ctx.success_value
  }
  if condition_expression_has_status_check(trimmed) {
    eval_if_condition_bool(trimmed, ctx)
  } else {
    ctx.success_value && eval_if_condition_bool(trimmed, ctx)
  }
}

///|
fn evaluate_boolean_condition(text : String, ctx : IfConditionContext) -> Bool {
  let trimmed = unwrap_if_expression(text)
  if trimmed.length() == 0 {
    return false
  }
  eval_if_condition_bool(trimmed, ctx)
}
