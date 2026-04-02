///|
priv enum ConditionValue {
  JsonValue(Json)
}

///|
priv struct IfConditionContext {
  step_outputs : Map[String, Map[String, String]]
  step_outcomes : Map[String, String]
  step_conclusions : Map[String, String]
  workspace_root : String
  env_context : Map[String, String]
  job_context : Map[String, String]
  vars_context : Map[String, String]
  secrets_context : Map[String, String]
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
  workspace_root? : String = "",
  env_context? : Map[String, String] = {},
  job_context? : Map[String, String] = {},
  vars_context? : Map[String, String] = {},
  secrets_context? : Map[String, String] = {},
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
    workspace_root,
    env_context,
    job_context,
    vars_context,
    secrets_context,
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
    if ch == '\'' && !in_double {
      in_single = !in_single
      idx += 1
      continue
    }
    if ch == '"' && !in_single {
      in_double = !in_double
      idx += 1
      continue
    }
    if !in_single && !in_double {
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
    if ch == '\'' && !in_double {
      in_single = !in_single
      idx += 1
      continue
    }
    if ch == '"' && !in_single {
      in_double = !in_double
      idx += 1
      continue
    }
    if !in_single && !in_double {
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
fn if_vars_name(expression : String) -> String? {
  let trimmed = strip_if_outer_parens(expression)
  if trimmed.has_prefix("vars.") && trimmed.length() > 5 {
    Some(if_text_slice(trimmed, 5, trimmed.length()))
  } else {
    None
  }
}

///|
fn if_job_name(expression : String) -> String? {
  let trimmed = strip_if_outer_parens(expression)
  if trimmed.has_prefix("job.") && trimmed.length() > 4 {
    Some(if_text_slice(trimmed, 4, trimmed.length()))
  } else {
    None
  }
}

///|
fn if_secrets_name(expression : String) -> String? {
  let trimmed = strip_if_outer_parens(expression)
  if trimmed.has_prefix("secrets.") && trimmed.length() > 8 {
    Some(if_text_slice(trimmed, 8, trimmed.length()))
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
fn split_top_level_if_arguments(text : String) -> Array[String]? {
  let args : Array[String] = []
  let mut depth = 0
  let mut in_single = false
  let mut in_double = false
  let mut start = 0
  let mut idx = 0
  while idx < text.length() {
    let ch = text.unsafe_get(idx)
    if ch == '\'' && !in_double {
      in_single = !in_single
      idx += 1
      continue
    }
    if ch == '"' && !in_single {
      in_double = !in_double
      idx += 1
      continue
    }
    if !in_single && !in_double {
      if ch == '(' {
        depth += 1
      } else if ch == ')' {
        if depth == 0 {
          return None
        }
        depth -= 1
      } else if ch == ',' && depth == 0 {
        args.push(
          if_text_slice(text, start, idx).trim(chars=" \t\n\r").to_string(),
        )
        start = idx + 1
      }
    }
    idx += 1
  }
  if depth != 0 || in_single || in_double {
    return None
  }
  args.push(
    if_text_slice(text, start, text.length()).trim(chars=" \t\n\r").to_string(),
  )
  Some(args)
}

///|
fn if_function_arguments(
  expression : String,
  function_name : String,
  arity : Int,
) -> Array[String]? {
  let trimmed = strip_if_outer_parens(expression)
  let lower = trimmed.to_lower()
  let prefix = function_name.to_lower() + "("
  guard lower.has_prefix(prefix) && trimmed.has_suffix(")") else { return None }
  let inner = if_text_slice(trimmed, prefix.length(), trimmed.length() - 1)
  guard split_top_level_if_arguments(inner) is Some(args) else { return None }
  if args.length() != arity {
    None
  } else {
    Some(args)
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
fn if_expression_function_supported(text : String) -> Bool {
  match if_function_arguments(text, "contains", 2) {
    Some(args) =>
      return if_condition_supported(args[0]) && if_condition_supported(args[1])
    None => ()
  }
  match if_function_arguments(text, "startsWith", 2) {
    Some(args) =>
      return if_condition_supported(args[0]) && if_condition_supported(args[1])
    None => ()
  }
  match if_function_arguments(text, "endsWith", 2) {
    Some(args) =>
      return if_condition_supported(args[0]) && if_condition_supported(args[1])
    None => ()
  }
  match if_function_arguments(text, "fromJSON", 1) {
    Some(args) => return if_condition_supported(args[0])
    None => ()
  }
  match if_function_arguments(text, "toJSON", 1) {
    Some(args) => return if_condition_supported(args[0])
    None => ()
  }
  if if_hash_files_function_supported(text) {
    return true
  }
  match if_function_arguments_at_least(text, "format", 1) {
    Some(args) => {
      for arg in args {
        if !if_condition_supported(arg) {
          return false
        }
      }
      return true
    }
    None => ()
  }
  match if_function_arguments_at_least(text, "join", 1) {
    Some(args) => {
      for arg in args {
        if !if_condition_supported(arg) {
          return false
        }
      }
      return true
    }
    None => ()
  }
  match if_function_arguments_at_least(text, "case", 1) {
    Some(args) => {
      for arg in args {
        if !if_condition_supported(arg) {
          return false
        }
      }
      return true
    }
    None => ()
  }
  false
}

///|
fn if_number_literal(text : String) -> Bool {
  let trimmed = text.trim(chars=" \t\n\r").to_string()
  if trimmed.length() == 0 {
    return false
  }
  let mut i = 0
  if trimmed.unsafe_get(i).to_int() == '-'.to_int() ||
    trimmed.unsafe_get(i).to_int() == '+'.to_int() {
    i += 1
  }
  if i >= trimmed.length() {
    return false
  }
  let mut has_digit = false
  let mut has_dot = false
  while i < trimmed.length() {
    let ch = trimmed.unsafe_get(i).to_int()
    if ch >= '0'.to_int() && ch <= '9'.to_int() {
      has_digit = true
    } else if ch == '.'.to_int() && !has_dot {
      has_dot = true
    } else {
      return false
    }
    i += 1
  }
  has_digit
}

///|
fn if_condition_atom_supported(text : String) -> Bool {
  if if_bool_literal(text) is Some(_) {
    return true
  }
  if if_quoted_string(text) is Some(_) {
    return true
  }
  if if_number_literal(text) {
    return true
  }
  if if_expression_function_supported(text) {
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
  if if_job_name(trimmed) is Some(_) {
    return true
  }
  if if_vars_name(trimmed) is Some(_) {
    return true
  }
  if if_secrets_name(trimmed) is Some(_) {
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
  match find_top_level_if_operator(trimmed, ">=") {
    Some(idx) =>
      return if_condition_supported(if_text_slice(trimmed, 0, idx)) &&
        if_condition_supported(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
        )
    None => ()
  }
  match find_top_level_if_operator(trimmed, "<=") {
    Some(idx) =>
      return if_condition_supported(if_text_slice(trimmed, 0, idx)) &&
        if_condition_supported(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
        )
    None => ()
  }
  match find_top_level_if_operator(trimmed, ">") {
    Some(idx) =>
      return if_condition_supported(if_text_slice(trimmed, 0, idx)) &&
        if_condition_supported(
          if_text_slice(trimmed, idx + 1, trimmed.length()),
        )
    None => ()
  }
  match find_top_level_if_operator(trimmed, "<") {
    Some(idx) =>
      return if_condition_supported(if_text_slice(trimmed, 0, idx)) &&
        if_condition_supported(
          if_text_slice(trimmed, idx + 1, trimmed.length()),
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
    JsonValue(json) =>
      match json {
        False => false
        Null => false
        String(text) => text.length() > 0
        Number(value, repr=_) => value != 0.0
        _ => true
      }
  }
}

///|
fn if_condition_value_eq(left : ConditionValue, right : ConditionValue) -> Bool {
  match left {
    JsonValue(left_json) =>
      match right {
        JsonValue(right_json) => {
          if Json::equal(left_json, right_json) {
            return true
          }
          match left_json {
            Array(_) => false
            Object(_) => false
            _ =>
              match right_json {
                Array(_) => false
                Object(_) => false
                _ =>
                  if_condition_value_to_string(left) ==
                  if_condition_value_to_string(right)
              }
          }
        }
      }
  }
}

///|
fn if_condition_value_to_string(value : ConditionValue) -> String {
  match value {
    JsonValue(json) =>
      match json {
        True => "true"
        False => "false"
        Null => ""
        String(text) => text
        Number(value, repr~) =>
          match repr {
            Some(text) => text
            None => value.to_string()
          }
        Array(_) => Json::stringify(json)
        Object(_) => Json::stringify(json)
      }
  }
}

///|
fn if_condition_value_json(value : ConditionValue) -> Json {
  match value {
    JsonValue(json) => json
  }
}

///|
fn if_condition_value_from_json(json : Json) -> ConditionValue {
  JsonValue(json)
}

///|
fn if_expression_function_value(
  text : String,
  ctx : IfConditionContext,
) -> ConditionValue? {
  match if_function_arguments(text, "contains", 2) {
    Some(args) => {
      let haystack = if_condition_atom_value(args[0], ctx)
      let needle = if_condition_atom_value(args[1], ctx)
      let matched = match if_condition_value_json(haystack) {
        Array(items) => {
          let mut found = false
          for item in items {
            if if_condition_value_eq(if_condition_value_from_json(item), needle) {
              found = true
              break
            }
          }
          found
        }
        _ =>
          if_condition_value_to_string(haystack).contains(
            if_condition_value_to_string(needle),
          )
      }
      return Some(if_condition_value_from_json(Json::boolean(matched)))
    }
    None => ()
  }
  match if_function_arguments(text, "startsWith", 2) {
    Some(args) => {
      let text_value = if_condition_value_to_string(
        if_condition_atom_value(args[0], ctx),
      )
      let prefix = if_condition_value_to_string(
        if_condition_atom_value(args[1], ctx),
      )
      return Some(
        if_condition_value_from_json(
          Json::boolean(text_value.has_prefix(prefix)),
        ),
      )
    }
    None => ()
  }
  match if_function_arguments(text, "endsWith", 2) {
    Some(args) => {
      let text_value = if_condition_value_to_string(
        if_condition_atom_value(args[0], ctx),
      )
      let suffix = if_condition_value_to_string(
        if_condition_atom_value(args[1], ctx),
      )
      return Some(
        if_condition_value_from_json(
          Json::boolean(text_value.has_suffix(suffix)),
        ),
      )
    }
    None => ()
  }
  match if_function_arguments(text, "fromJSON", 1) {
    Some(args) => {
      let source = if_condition_value_to_string(
        if_condition_atom_value(args[0], ctx),
      )
      let json = @json.parse(source) catch { _ => Json::null() }
      return Some(if_condition_value_from_json(json))
    }
    None => ()
  }
  match if_function_arguments(text, "toJSON", 1) {
    Some(args) => {
      let value = if_condition_atom_value(args[0], ctx)
      let json_text = Json::stringify(if_condition_value_json(value), indent=2)
      return Some(if_condition_value_from_json(Json::string(json_text)))
    }
    None => ()
  }
  match if_hash_files_function_value(text, ctx) {
    Some(value) => return Some(value)
    None => ()
  }
  match if_function_arguments_at_least(text, "format", 1) {
    Some(args) => {
      let fmt_str = if_condition_value_to_string(
        if_condition_atom_value(args[0], ctx),
      )
      let mut result = fmt_str
      let mut i = 1
      while i < args.length() {
        let placeholder = "{" + (i - 1).to_string() + "}"
        let replacement = if_condition_value_to_string(
          if_condition_atom_value(args[i], ctx),
        )
        let mut new_result = ""
        let mut search_from = 0
        while true {
          match find_if_substring(result, placeholder, search_from) {
            Some(pos) => {
              new_result = new_result +
                if_text_slice(result, search_from, pos) +
                replacement
              search_from = pos + placeholder.length()
            }
            None => {
              new_result = new_result +
                if_text_slice(result, search_from, result.length())
              break
            }
          }
        }
        result = new_result
        i += 1
      }
      return Some(if_condition_value_from_json(Json::string(result)))
    }
    None => ()
  }
  match if_function_arguments_at_least(text, "join", 1) {
    Some(args) => {
      let value = if_condition_atom_value(args[0], ctx)
      let separator = if args.length() >= 2 {
        if_condition_value_to_string(if_condition_atom_value(args[1], ctx))
      } else {
        ","
      }
      match if_condition_value_json(value) {
        Array(items) => {
          let parts : Array[String] = []
          for item in items {
            parts.push(
              if_condition_value_to_string(if_condition_value_from_json(item)),
            )
          }
          return Some(
            if_condition_value_from_json(Json::string(parts.join(separator))),
          )
        }
        _ => {
          let str_val = if_condition_value_to_string(value)
          return Some(if_condition_value_from_json(Json::string(str_val)))
        }
      }
    }
    None => ()
  }
  match if_function_arguments_at_least(text, "case", 1) {
    Some(args) => {
      let has_default = args.length() % 2 == 1
      let pair_count = args.length() / 2
      let mut i = 0
      while i < pair_count {
        let pred = if_condition_atom_value(args[i * 2], ctx)
        if if_condition_value_truthy(pred) {
          return Some(if_condition_atom_value(args[i * 2 + 1], ctx))
        }
        i += 1
      }
      if has_default {
        return Some(if_condition_atom_value(args[args.length() - 1], ctx))
      }
      return Some(if_condition_value_from_json(Json::string("")))
    }
    None => ()
  }
  None
}

///|
fn if_condition_atom_value(
  text : String,
  ctx : IfConditionContext,
) -> ConditionValue {
  match if_bool_literal(text) {
    Some(value) => return if_condition_value_from_json(Json::boolean(value))
    None => ()
  }
  match if_quoted_string(text) {
    Some(value) => return if_condition_value_from_json(Json::string(value))
    None => ()
  }
  if if_number_literal(text) {
    let trimmed = text.trim(chars=" \t\n\r").to_string()
    return if_condition_value_from_json(Json::string(trimmed))
  }
  match if_expression_function_value(text, ctx) {
    Some(value) => return value
    None => ()
  }
  let trimmed = strip_if_outer_parens(text)
  if trimmed == "success()" {
    return if_condition_value_from_json(Json::boolean(ctx.success_value))
  }
  if trimmed == "always()" {
    return if_condition_value_from_json(Json::boolean(true))
  }
  if trimmed == "failure()" {
    return if_condition_value_from_json(Json::boolean(ctx.failure_value))
  }
  if trimmed == "cancelled()" {
    return if_condition_value_from_json(Json::boolean(ctx.cancelled_value))
  }
  match if_step_output_name(trimmed) {
    Some((step_id, output_name)) =>
      return if_condition_value_from_json(
        Json::string(
          resolve_if_step_output(ctx.step_outputs, step_id, output_name),
        ),
      )
    None => ()
  }
  match if_step_status_name(trimmed, ".outcome") {
    Some(step_id) =>
      return if_condition_value_from_json(
        Json::string(resolve_if_step_status(ctx.step_outcomes, step_id)),
      )
    None => ()
  }
  match if_step_status_name(trimmed, ".conclusion") {
    Some(step_id) =>
      return if_condition_value_from_json(
        Json::string(resolve_if_step_status(ctx.step_conclusions, step_id)),
      )
    None => ()
  }
  match if_needs_output_name(trimmed) {
    Some((job_id, output_name)) =>
      return if_condition_value_from_json(
        Json::string(
          resolve_if_needs_output(ctx.needs_outputs, job_id, output_name),
        ),
      )
    None => ()
  }
  match if_needs_result_name(trimmed) {
    Some(job_id) =>
      return if_condition_value_from_json(
        Json::string(resolve_if_needs_result(ctx.needs_results, job_id)),
      )
    None => ()
  }
  match if_env_name(trimmed) {
    Some(name) =>
      return if_condition_value_from_json(
        Json::string(
          if_map_get_case_insensitive(ctx.env_context, name).unwrap_or(""),
        ),
      )
    None => ()
  }
  match if_job_name(trimmed) {
    Some(name) =>
      return if_condition_value_from_json(
        Json::string(
          if_map_get_case_insensitive(ctx.job_context, name).unwrap_or(""),
        ),
      )
    None => ()
  }
  match if_vars_name(trimmed) {
    Some(name) =>
      return if_condition_value_from_json(
        Json::string(
          if_map_get_case_insensitive(ctx.vars_context, name).unwrap_or(""),
        ),
      )
    None => ()
  }
  match if_secrets_name(trimmed) {
    Some(name) =>
      return if_condition_value_from_json(
        Json::string(
          if_map_get_case_insensitive(ctx.secrets_context, name).unwrap_or(""),
        ),
      )
    None => ()
  }
  match if_github_name(trimmed) {
    Some(name) =>
      return if_condition_value_from_json(
        Json::string(
          if_map_get_case_insensitive(ctx.github_context, name).unwrap_or(""),
        ),
      )
    None => ()
  }
  match if_runner_name(trimmed) {
    Some(name) =>
      return if_condition_value_from_json(
        Json::string(
          if_map_get_case_insensitive(ctx.runner_context, name).unwrap_or(""),
        ),
      )
    None => ()
  }
  if_condition_value_from_json(Json::string(""))
}

///|
fn evaluate_string_function_expression(
  text : String,
  ctx : IfConditionContext,
) -> String? {
  match if_expression_function_value(text, ctx) {
    Some(value) => Some(if_condition_value_to_string(value))
    None => None
  }
}

///|
#warnings("-deprecated")
fn try_parse_int64(s : String) -> Int64? {
  let v = @strconv.parse_int64(s) catch { _ => return None }
  Some(v)
}

///|
#warnings("-deprecated")
fn try_parse_double(s : String) -> Double? {
  let v = @strconv.parse_double(s) catch { _ => return None }
  Some(v)
}

///|
fn compare_condition_values(
  left : ConditionValue,
  right : ConditionValue,
) -> Int {
  let left_str = if_condition_value_to_string(left)
  let right_str = if_condition_value_to_string(right)
  match (try_parse_int64(left_str), try_parse_int64(right_str)) {
    (Some(l), Some(r)) => if l < r { -1 } else if l > r { 1 } else { 0 }
    _ =>
      match (try_parse_double(left_str), try_parse_double(right_str)) {
        (Some(l), Some(r)) => if l < r { -1 } else if l > r { 1 } else { 0 }
        _ =>
          if left_str < right_str {
            -1
          } else if left_str > right_str {
            1
          } else {
            0
          }
      }
  }
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
      return !if_condition_value_eq(
        if_condition_atom_value(if_text_slice(trimmed, 0, idx), ctx),
        if_condition_atom_value(
          if_text_slice(trimmed, idx + 2, trimmed.length()),
          ctx,
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
  match find_top_level_if_operator(trimmed, ">=") {
    Some(idx) => {
      let left = if_condition_atom_value(if_text_slice(trimmed, 0, idx), ctx)
      let right = if_condition_atom_value(
        if_text_slice(trimmed, idx + 2, trimmed.length()),
        ctx,
      )
      return compare_condition_values(left, right) >= 0
    }
    None => ()
  }
  match find_top_level_if_operator(trimmed, "<=") {
    Some(idx) => {
      let left = if_condition_atom_value(if_text_slice(trimmed, 0, idx), ctx)
      let right = if_condition_atom_value(
        if_text_slice(trimmed, idx + 2, trimmed.length()),
        ctx,
      )
      return compare_condition_values(left, right) <= 0
    }
    None => ()
  }
  match find_top_level_if_operator(trimmed, ">") {
    Some(idx) => {
      let left = if_condition_atom_value(if_text_slice(trimmed, 0, idx), ctx)
      let right = if_condition_atom_value(
        if_text_slice(trimmed, idx + 1, trimmed.length()),
        ctx,
      )
      return compare_condition_values(left, right) > 0
    }
    None => ()
  }
  match find_top_level_if_operator(trimmed, "<") {
    Some(idx) => {
      let left = if_condition_atom_value(if_text_slice(trimmed, 0, idx), ctx)
      let right = if_condition_atom_value(
        if_text_slice(trimmed, idx + 1, trimmed.length()),
        ctx,
      )
      return compare_condition_values(left, right) < 0
    }
    None => ()
  }
  if trimmed.has_prefix("!") {
    return !eval_if_condition_bool(
      if_text_slice(trimmed, 1, trimmed.length()),
      ctx,
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
