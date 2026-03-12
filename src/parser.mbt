///|
priv struct YamlLine {
  indent : Int
  text : String
  raw : String
}

///|
priv struct YamlField {
  key : String
  value : YamlValue
}

///|
priv enum YamlValue {
  Str(String)
  Seq(Array[YamlValue])
  Obj(Array[YamlField])
  Null
}

///|
priv struct WorkflowYamlParser {
  lines : Array[YamlLine]
  mut idx : Int
  errors : Array[String]
}

///|
fn count_indent(raw : String, line_no : Int, errors : Array[String]) -> Int {
  let mut indent = 0
  while indent < raw.length() {
    let ch = raw.unsafe_get(indent)
    if ch == ' ' {
      indent += 1
      continue
    }
    if ch == '\t' {
      errors.push("line \{line_no}: tabs are not supported in YAML indentation")
    }
    break
  }
  indent
}

///|
fn strip_yaml_comment(text : String) -> String {
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
    if ch == '#' && not(in_single) && not(in_double) {
      return String::unsafe_substring(text, start=0, end=idx)
        .trim_end(chars=" \t")
        .to_string()
    }
    idx += 1
  }
  text.trim_end(chars=" \t").to_string()
}

///|
fn collect_yaml_lines(text : String, errors : Array[String]) -> Array[YamlLine] {
  let lines : Array[YamlLine] = []
  let mut line_no = 1
  for line_view in text.split("\n") {
    let raw = line_view.to_string().trim_end(chars="\r").to_string()
    let indent = count_indent(raw, line_no, errors)
    let content = if indent >= raw.length() {
      ""
    } else {
      String::unsafe_substring(raw, start=indent, end=raw.length())
    }
    lines.push({ indent, text: strip_yaml_comment(content), raw })
    line_no += 1
  }
  lines
}

///|
fn yaml_parser_new(text : String) -> WorkflowYamlParser {
  let errors : Array[String] = []
  { lines: collect_yaml_lines(text, errors), idx: 0, errors }
}

///|
fn WorkflowYamlParser::skip_ignorable(self : WorkflowYamlParser) -> Unit {
  while self.idx < self.lines.length() {
    if self.lines[self.idx].text.trim(chars=" ").to_string().length() == 0 {
      self.idx += 1
    } else {
      return
    }
  }
}

///|
fn is_sequence_item(text : String) -> Bool {
  text == "-" || text.has_prefix("- ")
}

///|
fn after_sequence_dash(text : String) -> String {
  if text == "-" {
    ""
  } else {
    String::unsafe_substring(text, start=2, end=text.length())
    .trim_start(chars=" ")
    .to_string()
  }
}

///|
fn split_key_value(text : String) -> (String, String?)? {
  guard text.find(":") is Some(idx) else { return None }
  let key = String::unsafe_substring(text, start=0, end=idx)
    .trim(chars=" ")
    .to_string()
  let rest = String::unsafe_substring(text, start=idx + 1, end=text.length())
    .trim_start(chars=" ")
    .to_string()
  if rest.length() == 0 {
    Some((key, None))
  } else {
    Some((key, Some(rest)))
  }
}

///|
fn split_inline_items(text : String) -> Array[String] {
  let items : Array[String] = []
  let mut in_single = false
  let mut in_double = false
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut start = 0
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
      if ch == '[' {
        bracket_depth += 1
      } else if ch == ']' && bracket_depth > 0 {
        bracket_depth -= 1
      } else if ch == '{' {
        brace_depth += 1
      } else if ch == '}' && brace_depth > 0 {
        brace_depth -= 1
      } else if ch == ',' && bracket_depth == 0 && brace_depth == 0 {
        items.push(
          String::unsafe_substring(text, start~, end=idx)
          .trim(chars=" ")
          .to_string(),
        )
        start = idx + 1
        idx += 1
        continue
      }
    }
    idx += 1
  }
  let last = String::unsafe_substring(text, start~, end=text.length())
    .trim(chars=" ")
    .to_string()
  if last.length() > 0 {
    items.push(last)
  }
  items
}

///|
fn unquote_yaml_string(text : String) -> String {
  if text.length() >= 2 {
    let first = text.unsafe_get(0)
    let last = text.unsafe_get(text.length() - 1)
    if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
      return String::unsafe_substring(text, start=1, end=text.length() - 1)
    }
  }
  text
}

///|
fn parse_inline_map(text : String) -> YamlValue {
  let inner = String::unsafe_substring(text, start=1, end=text.length() - 1)
  let fields : Array[YamlField] = []
  for item in split_inline_items(inner) {
    match split_key_value(item) {
      Some((key, Some(value))) =>
        fields.push({
          key: unquote_yaml_string(key),
          value: YamlValue::Str(unquote_yaml_string(value)),
        })
      Some((key, None)) =>
        fields.push({ key: unquote_yaml_string(key), value: YamlValue::Null })
      None => ()
    }
  }
  YamlValue::Obj(fields)
}

///|
fn parse_inline_value(text : String) -> YamlValue {
  let trimmed = text.trim(chars=" ").to_string()
  if trimmed.length() == 0 || trimmed == "null" || trimmed == "~" {
    return YamlValue::Null
  }
  if trimmed.has_prefix("[") && trimmed.has_suffix("]") {
    let inner = String::unsafe_substring(
      trimmed,
      start=1,
      end=trimmed.length() - 1,
    )
    let values : Array[YamlValue] = []
    for item in split_inline_items(inner) {
      values.push(parse_inline_value(item))
    }
    return YamlValue::Seq(values)
  }
  if trimmed.has_prefix("{") && trimmed.has_suffix("}") {
    return parse_inline_map(trimmed)
  }
  YamlValue::Str(unquote_yaml_string(trimmed))
}

///|
fn WorkflowYamlParser::parse_block_scalar(
  self : WorkflowYamlParser,
  parent_indent : Int,
  folded : Bool,
) -> YamlValue {
  let scalar_lines : Array[String] = []
  let mut scalar_indent = -1
  while self.idx < self.lines.length() {
    let line = self.lines[self.idx]
    if line.text.length() == 0 {
      scalar_lines.push("")
      self.idx += 1
      continue
    }
    if line.indent <= parent_indent {
      break
    }
    if scalar_indent < 0 {
      scalar_indent = line.indent
    }
    if line.indent < scalar_indent {
      break
    }
    let content = if scalar_indent >= line.raw.length() {
      ""
    } else {
      String::unsafe_substring(
        line.raw,
        start=scalar_indent,
        end=line.raw.length(),
      )
    }
    scalar_lines.push(content)
    self.idx += 1
  }
  YamlValue::Str(
    if folded {
      scalar_lines.join(" ")
    } else {
      scalar_lines.join("\n")
    },
  )
}

///|
fn WorkflowYamlParser::parse_mapping_entry(
  self : WorkflowYamlParser,
  text : String,
  expected_indent : Int,
) -> (String, YamlValue)? {
  match split_key_value(text) {
    Some((raw_key, value_text)) => {
      let key = unquote_yaml_string(raw_key)
      match value_text {
        Some(value) =>
          if value == "|" {
            Some((key, self.parse_block_scalar(expected_indent, false)))
          } else if value == ">" {
            Some((key, self.parse_block_scalar(expected_indent, true)))
          } else {
            Some((key, parse_inline_value(value)))
          }
        None => {
          let saved = self.idx
          self.skip_ignorable()
          if self.idx < self.lines.length() &&
            self.lines[self.idx].indent > expected_indent {
            let child_indent = self.lines[self.idx].indent
            Some((key, self.parse_block(child_indent)))
          } else {
            self.idx = saved
            Some((key, YamlValue::Null))
          }
        }
      }
    }
    None => {
      self.errors.push("line must be key: value, got '\{text}'")
      None
    }
  }
}

///|
fn WorkflowYamlParser::parse_mapping(
  self : WorkflowYamlParser,
  indent : Int,
) -> YamlValue {
  let fields : Array[YamlField] = []
  while true {
    self.skip_ignorable()
    guard self.idx < self.lines.length() else { break }
    let line = self.lines[self.idx]
    if line.indent != indent || is_sequence_item(line.text) {
      break
    }
    self.idx += 1
    match self.parse_mapping_entry(line.text, indent) {
      Some((key, value)) => fields.push({ key, value })
      None => ()
    }
  }
  YamlValue::Obj(fields)
}

///|
fn WorkflowYamlParser::parse_sequence(
  self : WorkflowYamlParser,
  indent : Int,
) -> YamlValue {
  let values : Array[YamlValue] = []
  while true {
    self.skip_ignorable()
    guard self.idx < self.lines.length() else { break }
    let line = self.lines[self.idx]
    if line.indent != indent || not(is_sequence_item(line.text)) {
      break
    }
    let item_text = after_sequence_dash(line.text)
    self.idx += 1
    if item_text.length() == 0 {
      let saved = self.idx
      self.skip_ignorable()
      if self.idx < self.lines.length() && self.lines[self.idx].indent > indent {
        values.push(self.parse_block(self.lines[self.idx].indent))
      } else {
        self.idx = saved
        values.push(YamlValue::Null)
      }
      continue
    }
    if split_key_value(item_text) is Some(_) {
      let fields : Array[YamlField] = []
      match self.parse_mapping_entry(item_text, indent + 2) {
        Some((key, value)) => fields.push({ key, value })
        None => ()
      }
      while true {
        self.skip_ignorable()
        guard self.idx < self.lines.length() else { break }
        let next = self.lines[self.idx]
        if next.indent != indent + 2 || is_sequence_item(next.text) {
          break
        }
        self.idx += 1
        match self.parse_mapping_entry(next.text, indent + 2) {
          Some((key, value)) => fields.push({ key, value })
          None => ()
        }
      }
      values.push(YamlValue::Obj(fields))
      continue
    }
    values.push(parse_inline_value(item_text))
  }
  YamlValue::Seq(values)
}

///|
fn WorkflowYamlParser::parse_block(
  self : WorkflowYamlParser,
  indent : Int,
) -> YamlValue {
  self.skip_ignorable()
  if self.idx >= self.lines.length() {
    return YamlValue::Null
  }
  if is_sequence_item(self.lines[self.idx].text) {
    self.parse_sequence(indent)
  } else {
    self.parse_mapping(indent)
  }
}

///|
fn parse_yaml_document(text : String) -> (YamlValue, Array[String]) {
  let parser = yaml_parser_new(text)
  parser.skip_ignorable()
  if parser.idx >= parser.lines.length() {
    return (YamlValue::Obj([]), parser.errors)
  }
  let root = parser.parse_block(parser.lines[parser.idx].indent)
  (root, parser.errors)
}

///|
fn yaml_obj_get(fields : Array[YamlField], key : String) -> YamlValue? {
  let mut found : YamlValue? = None
  for field in fields {
    if field.key == key {
      found = Some(field.value)
    }
  }
  found
}

///|
fn yaml_as_obj(
  value : YamlValue,
  errors : Array[String],
  ctx : String,
) -> Array[YamlField] {
  match value {
    Obj(fields) => fields
    _ => {
      errors.push(ctx + " must be a mapping")
      []
    }
  }
}

///|
fn yaml_as_optional_string(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> String? {
  match value {
    Some(Str(text)) => Some(text)
    Some(Null) => None
    Some(_) => {
      errors.push(ctx + " must be a string")
      None
    }
    None => None
  }
}

///|
fn yaml_as_string_list(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> Array[String] {
  match value {
    Some(Str(text)) => [text]
    Some(Seq(items)) => {
      let result : Array[String] = []
      for item in items {
        match item {
          Str(text) => result.push(text)
          _ => errors.push(ctx + " items must be strings")
        }
      }
      result
    }
    Some(Null) => []
    Some(_) => {
      errors.push(ctx + " must be a string or list")
      []
    }
    None => []
  }
}

///|
fn yaml_to_string_map(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> Map[String, String] {
  let result : Map[String, String] = {}
  guard value is Some(actual) else { return result }
  match actual {
    Obj(fields) =>
      for field in fields {
        match field.value {
          Str(text) => result[field.key] = text
          Null => result[field.key] = ""
          _ => errors.push(ctx + "." + field.key + " must be a string")
        }
      }
    _ => errors.push(ctx + " must be a mapping")
  }
  result
}

///|
fn yaml_as_optional_bool(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> Bool? {
  match value {
    Some(Str(text)) => {
      let normalized = text.trim(chars=" \t\r\n").to_lower()
      if normalized == "true" {
        Some(true)
      } else if normalized == "false" {
        Some(false)
      } else {
        errors.push(ctx + " must be true or false")
        None
      }
    }
    Some(Null) => None
    Some(_) => {
      errors.push(ctx + " must be a boolean")
      None
    }
    None => None
  }
}

///|
fn yaml_as_optional_int(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> Int? {
  match value {
    Some(Str(text)) => {
      let trimmed = text.trim(chars=" \t\r\n").to_string()
      if trimmed.length() == 0 {
        return None
      }
      let parsed = @strconv.parse_int64(trimmed) catch {
        _ => {
          errors.push(ctx + " must be an integer")
          return None
        }
      }
      Some(parsed.to_int())
    }
    Some(Null) => None
    Some(_) => {
      errors.push(ctx + " must be an integer")
      None
    }
    None => None
  }
}

///|
fn yaml_as_string_map_list(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> Array[Map[String, String]] {
  let result : Array[Map[String, String]] = []
  guard value is Some(actual) else { return result }
  match actual {
    Seq(items) => {
      let mut idx = 0
      while idx < items.length() {
        result.push(
          yaml_to_string_map(
            Some(items[idx]),
            errors,
            ctx + "[" + idx.to_string() + "]",
          ),
        )
        idx += 1
      }
    }
    Null => ()
    _ => errors.push(ctx + " must be a list")
  }
  result
}

///|
fn matrix_product_rows(
  axes : Array[(String, Array[String])],
  idx : Int,
  current : Map[String, String],
  rows : Array[Map[String, String]],
) -> Unit {
  if idx >= axes.length() {
    let row : Map[String, String] = {}
    for key, value in current {
      row[key] = value
    }
    rows.push(row)
    return
  }
  let (key, values) = axes[idx]
  for value in values {
    let next : Map[String, String] = {}
    for existing_key, existing_value in current {
      next[existing_key] = existing_value
    }
    next[key] = value
    matrix_product_rows(axes, idx + 1, next, rows)
  }
}

///|
fn matrix_row_matches(
  row : Map[String, String],
  pattern : Map[String, String],
) -> Bool {
  for key, value in pattern {
    match row.get(key) {
      Some(actual) if actual == value => ()
      _ => return false
    }
  }
  true
}

///|
fn matrix_row_merge(
  base : Map[String, String],
  overlay : Map[String, String],
) -> Map[String, String] {
  let merged : Map[String, String] = {}
  for key, value in base {
    merged[key] = value
  }
  for key, value in overlay {
    merged[key] = value
  }
  merged
}

///|
fn matrix_include_matches_original(
  original_row : Map[String, String],
  include_row : Map[String, String],
) -> Bool {
  for key, value in include_row {
    match original_row.get(key) {
      Some(actual) if actual == value => ()
      Some(_) => return false
      None => ()
    }
  }
  true
}

///|
fn expand_matrix_includes(
  original_rows : Array[Map[String, String]],
  include_rows : Array[Map[String, String]],
) -> Array[Map[String, String]] {
  let expanded : Array[Map[String, String]] = []
  for row in original_rows {
    expanded.push(matrix_row_merge({}, row))
  }
  for include_row in include_rows {
    let mut matched = false
    let mut row_index = 0
    while row_index < original_rows.length() {
      if matrix_include_matches_original(original_rows[row_index], include_row) {
        expanded[row_index] = matrix_row_merge(expanded[row_index], include_row)
        matched = true
      }
      row_index += 1
    }
    if not(matched) {
      expanded.push(matrix_row_merge({}, include_row))
    }
  }
  expanded
}

///|
fn filter_matrix_excludes(
  rows : Array[Map[String, String]],
  excludes : Array[Map[String, String]],
) -> Array[Map[String, String]] {
  if excludes.length() == 0 {
    return rows
  }
  let filtered : Array[Map[String, String]] = []
  for row in rows {
    let mut excluded = false
    for pattern in excludes {
      if matrix_row_matches(row, pattern) {
        excluded = true
        break
      }
    }
    if not(excluded) {
      filtered.push(row)
    }
  }
  filtered
}

///|
fn parse_job_matrix(
  strategy_value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> JobMatrixSpec? {
  guard strategy_value is Some(actual_strategy) else { return None }
  let strategy_fields = yaml_as_obj(actual_strategy, errors, ctx)
  let matrix_value = yaml_obj_get(strategy_fields, "matrix")
  guard matrix_value is Some(actual_matrix) else { return None }
  let matrix_fields = yaml_as_obj(actual_matrix, errors, ctx + ".matrix")
  let axes : Array[(String, Array[String])] = []
  let mut include_rows : Array[Map[String, String]] = []
  let mut exclude_rows : Array[Map[String, String]] = []
  for field in matrix_fields {
    if field.key == "include" {
      include_rows = yaml_as_string_map_list(
        Some(field.value),
        errors,
        ctx + ".matrix.include",
      )
      continue
    }
    if field.key == "exclude" {
      exclude_rows = yaml_as_string_map_list(
        Some(field.value),
        errors,
        ctx + ".matrix.exclude",
      )
      continue
    }
    match field.value {
      Seq(_) | Str(_) | Null =>
        axes.push(
          (
            field.key,
            yaml_as_string_list(
              Some(field.value),
              errors,
              ctx + ".matrix." + field.key,
            ),
          ),
        )
      _ =>
        errors.push(ctx + ".matrix." + field.key + " must be a string or list")
    }
  }
  let mut rows : Array[Map[String, String]] = []
  if axes.length() > 0 {
    let current : Map[String, String] = {}
    matrix_product_rows(axes, 0, current, rows)
    rows = filter_matrix_excludes(rows, exclude_rows)
    rows = expand_matrix_includes(rows, include_rows)
  } else {
    rows = include_rows
    rows = filter_matrix_excludes(rows, exclude_rows)
  }
  if rows.length() == 0 {
    errors.push(ctx + ".matrix must define at least one row")
    return None
  }
  let fail_fast = yaml_as_optional_bool(
    yaml_obj_get(strategy_fields, "fail-fast"),
    errors,
    ctx + ".fail-fast",
  ).unwrap_or(true)
  let max_parallel = yaml_as_optional_int(
    yaml_obj_get(strategy_fields, "max-parallel"),
    errors,
    ctx + ".max-parallel",
  )
  if max_parallel is Some(value) && value <= 0 {
    errors.push(ctx + ".max-parallel must be positive")
    return None
  }
  Some(new_job_matrix(rows, fail_fast~, max_parallel~))
}

///|
fn parse_run_defaults(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> RunDefaults {
  guard value is Some(actual) else { return new_run_defaults() }
  let fields = yaml_as_obj(actual, errors, ctx)
  let run_fields = match yaml_obj_get(fields, "run") {
    Some(run_value) => yaml_as_obj(run_value, errors, ctx + ".run")
    None => []
  }
  new_run_defaults(
    shell=yaml_as_optional_string(
      yaml_obj_get(run_fields, "shell"),
      errors,
      ctx + ".run.shell",
    ),
    working_directory=yaml_as_optional_string(
      yaml_obj_get(run_fields, "working-directory"),
      errors,
      ctx + ".run.working-directory",
    ),
  )
}

///|
fn parse_permissions(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> PermissionsSpec? {
  match value {
    None => None
    Some(Str(text)) => Some(new_permissions_spec(values={ "_": text }))
    Some(Obj(fields)) =>
      Some(
        new_permissions_spec(
          values=yaml_to_string_map(Some(Obj(fields)), errors, ctx),
        ),
      )
    Some(Null) => None
    Some(_) => {
      errors.push(ctx + " must be a string or mapping")
      None
    }
  }
}

///|
fn parse_push_trigger_value(
  value : YamlValue,
  errors : Array[String],
) -> PushTrigger {
  match value {
    Null => new_push_trigger()
    Obj(fields) =>
      new_push_trigger(
        branches=yaml_as_string_list(
          yaml_obj_get(fields, "branches"),
          errors,
          "on.push.branches",
        ),
        branches_ignore=yaml_as_string_list(
          yaml_obj_get(fields, "branches-ignore"),
          errors,
          "on.push.branches-ignore",
        ),
        paths=yaml_as_string_list(
          yaml_obj_get(fields, "paths"),
          errors,
          "on.push.paths",
        ),
        paths_ignore=yaml_as_string_list(
          yaml_obj_get(fields, "paths-ignore"),
          errors,
          "on.push.paths-ignore",
        ),
      )
    _ => {
      errors.push("on.push must be a mapping")
      new_push_trigger()
    }
  }
}

///|
fn parse_trigger(value : YamlValue?, errors : Array[String]) -> PushTrigger {
  match value {
    Some(Str(event_name)) =>
      if event_name == "push" {
        new_push_trigger()
      } else {
        errors.push("only push trigger is supported in MVP")
        new_push_trigger()
      }
    Some(Seq(items)) => {
      for item in items {
        if item is Str("push") {
          return new_push_trigger()
        }
      }
      errors.push("only push trigger is supported in MVP")
      new_push_trigger()
    }
    Some(Obj(fields)) =>
      match yaml_obj_get(fields, "push") {
        Some(push_value) => parse_push_trigger_value(push_value, errors)
        None => {
          errors.push("only push trigger is supported in MVP")
          new_push_trigger()
        }
      }
    Some(Null) => {
      errors.push("on must define push")
      new_push_trigger()
    }
    None => {
      errors.push("on is required")
      new_push_trigger()
    }
  }
}

///|
fn parse_step(
  value : YamlValue,
  errors : Array[String],
  ctx : String,
) -> StepSpec {
  let fields = yaml_as_obj(value, errors, ctx)
  {
    id: yaml_as_optional_string(yaml_obj_get(fields, "id"), errors, ctx + ".id").unwrap_or(
      "",
    ),
    name: yaml_as_optional_string(
      yaml_obj_get(fields, "name"),
      errors,
      ctx + ".name",
    ).unwrap_or(""),
    run: yaml_as_optional_string(
      yaml_obj_get(fields, "run"),
      errors,
      ctx + ".run",
    ),
    uses: yaml_as_optional_string(
      yaml_obj_get(fields, "uses"),
      errors,
      ctx + ".uses",
    ),
    shell: yaml_as_optional_string(
      yaml_obj_get(fields, "shell"),
      errors,
      ctx + ".shell",
    ),
    working_directory: yaml_as_optional_string(
      yaml_obj_get(fields, "working-directory"),
      errors,
      ctx + ".working-directory",
    ),
    env: yaml_to_string_map(yaml_obj_get(fields, "env"), errors, ctx + ".env"),
    with_values: yaml_to_string_map(
      yaml_obj_get(fields, "with"),
      errors,
      ctx + ".with",
    ),
    if_condition: yaml_as_optional_string(
      yaml_obj_get(fields, "if"),
      errors,
      ctx + ".if",
    ).unwrap_or("success()"),
    continue_on_error: yaml_as_optional_string(
      yaml_obj_get(fields, "continue-on-error"),
      errors,
      ctx + ".continue-on-error",
    ).unwrap_or("false"),
  }
}

///|
fn parse_job_steps(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> Array[StepSpec] {
  let steps : Array[StepSpec] = []
  guard value is Some(actual) else {
    errors.push(ctx + " is required")
    return steps
  }
  match actual {
    Seq(items) => {
      let mut idx = 0
      while idx < items.length() {
        steps.push(
          parse_step(items[idx], errors, ctx + "[" + idx.to_string() + "]"),
        )
        idx += 1
      }
    }
    _ => errors.push(ctx + " must be a list")
  }
  steps
}

///|
fn parse_container_image(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> String? {
  match value {
    Some(Str(text)) => Some(text)
    Some(Obj(fields)) =>
      yaml_as_optional_string(
        yaml_obj_get(fields, "image"),
        errors,
        ctx + ".image",
      )
    Some(Null) => None
    Some(_) => {
      errors.push(ctx + " must be a string or mapping")
      None
    }
    None => None
  }
}

///|
fn parse_job(id : String, value : YamlValue, errors : Array[String]) -> JobSpec {
  let ctx = "jobs." + id
  let fields = yaml_as_obj(value, errors, ctx)
  let strategy_value = yaml_obj_get(fields, "strategy")
  new_job(
    id,
    parse_job_steps(yaml_obj_get(fields, "steps"), errors, ctx + ".steps"),
    name=yaml_as_optional_string(
      yaml_obj_get(fields, "name"),
      errors,
      ctx + ".name",
    ).unwrap_or(""),
    if_condition=yaml_as_optional_string(
      yaml_obj_get(fields, "if"),
      errors,
      ctx + ".if",
    ).unwrap_or("success()"),
    needs=yaml_as_string_list(
      yaml_obj_get(fields, "needs"),
      errors,
      ctx + ".needs",
    ),
    outputs=yaml_to_string_map(
      yaml_obj_get(fields, "outputs"),
      errors,
      ctx + ".outputs",
    ),
    permissions=parse_permissions(
      yaml_obj_get(fields, "permissions"),
      errors,
      ctx + ".permissions",
    ),
    runs_on=yaml_as_string_list(
      yaml_obj_get(fields, "runs-on"),
      errors,
      ctx + ".runs-on",
    ),
    env=yaml_to_string_map(yaml_obj_get(fields, "env"), errors, ctx + ".env"),
    defaults=parse_run_defaults(
      yaml_obj_get(fields, "defaults"),
      errors,
      ctx + ".defaults",
    ),
    matrix=parse_job_matrix(strategy_value, errors, ctx + ".strategy"),
    reusable_workflow=yaml_as_optional_string(
      yaml_obj_get(fields, "uses"),
      errors,
      ctx + ".uses",
    ),
    container_image=parse_container_image(
      yaml_obj_get(fields, "container"),
      errors,
      ctx + ".container",
    ),
  )
}

///|
fn parse_local_action_inputs(
  value : YamlValue?,
  errors : Array[String],
  ctx : String,
) -> Map[String, String] {
  let inputs : Map[String, String] = {}
  guard value is Some(actual) else { return inputs }
  match actual {
    Obj(fields) =>
      for field in fields {
        match field.value {
          Obj(input_fields) =>
            inputs[field.key] = yaml_as_optional_string(
              yaml_obj_get(input_fields, "default"),
              errors,
              ctx + "." + field.key + ".default",
            ).unwrap_or("")
          Str(text) => inputs[field.key] = text
          Null => inputs[field.key] = ""
          _ =>
            errors.push(ctx + "." + field.key + " must be a mapping or string")
        }
      }
    _ => errors.push(ctx + " must be a mapping")
  }
  inputs
}

///|
priv struct ActionManifestSpec {
  name : String
  inputs : Map[String, String]
  runtime : String
  steps : Array[StepSpec]
  main : String
  pre : String?
  post : String?
  pre_if : String
  post_if : String
  image : String
  args : Array[String]
  entrypoint : String?
  pre_entrypoint : String?
  post_entrypoint : String?
}

///|
priv struct ActionManifestParseResult {
  action : ActionManifestSpec?
  errors : Array[String]
}

///|
fn parse_action_manifest_yaml(text : String) -> ActionManifestParseResult {
  let (yaml, parser_errors) = parse_yaml_document(text)
  let errors : Array[String] = []
  for err in parser_errors {
    errors.push(err)
  }
  guard yaml is Obj(root_fields) else {
    errors.push("local action root must be a mapping")
    return { action: None, errors }
  }

  let name = yaml_as_optional_string(
    yaml_obj_get(root_fields, "name"),
    errors,
    "name",
  ).unwrap_or("")
  let inputs = parse_local_action_inputs(
    yaml_obj_get(root_fields, "inputs"),
    errors,
    "inputs",
  )
  let runs_fields = match yaml_obj_get(root_fields, "runs") {
    Some(runs_value) => yaml_as_obj(runs_value, errors, "runs")
    None => {
      errors.push("runs is required")
      []
    }
  }
  let action_using = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "using"),
    errors,
    "runs.using",
  ).unwrap_or("")
  if action_using.length() == 0 {
    errors.push("runs.using is required")
  }
  let main = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "main"),
    errors,
    "runs.main",
  ).unwrap_or("")
  let pre = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "pre"),
    errors,
    "runs.pre",
  )
  let post = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "post"),
    errors,
    "runs.post",
  )
  let pre_if = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "pre-if"),
    errors,
    "runs.pre-if",
  ).unwrap_or("always()")
  let post_if = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "post-if"),
    errors,
    "runs.post-if",
  ).unwrap_or("always()")
  let image = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "image"),
    errors,
    "runs.image",
  ).unwrap_or("")
  let args = yaml_as_string_list(
    yaml_obj_get(runs_fields, "args"),
    errors,
    "runs.args",
  )
  let entrypoint = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "entrypoint"),
    errors,
    "runs.entrypoint",
  )
  let pre_entrypoint = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "pre-entrypoint"),
    errors,
    "runs.pre-entrypoint",
  )
  let post_entrypoint = yaml_as_optional_string(
    yaml_obj_get(runs_fields, "post-entrypoint"),
    errors,
    "runs.post-entrypoint",
  )
  let steps = if action_using == "composite" {
    parse_job_steps(yaml_obj_get(runs_fields, "steps"), errors, "runs.steps")
  } else {
    []
  }
  if action_using == "composite" && steps.length() == 0 {
    errors.push("runs.steps must have at least one step")
  }
  if action_using.has_prefix("node") && main.length() == 0 {
    errors.push("runs.main is required")
  }
  if action_using == "docker" && image.length() == 0 {
    errors.push("runs.image is required")
  }
  if pre_if != "always()" && pre_if != "success()" {
    errors.push("runs.pre-if must be success() or always() in MVP")
  }
  if post_if != "always()" && post_if != "success()" {
    errors.push("runs.post-if must be success() or always() in MVP")
  }
  if errors.length() > 0 {
    { action: None, errors }
  } else {
    {
      action: Some({
        name,
        inputs,
        runtime: action_using,
        steps,
        main,
        pre,
        post,
        pre_if,
        post_if,
        image,
        args,
        entrypoint,
        pre_entrypoint,
        post_entrypoint,
      }),
      errors,
    }
  }
}

///|
pub fn parse_local_action_yaml(text : String) -> LocalActionParseResult {
  let parsed = parse_action_manifest_yaml(text)
  guard parsed.action is Some(action) else {
    return { action: None, errors: parsed.errors }
  }
  let errors : Array[String] = []
  for err in parsed.errors {
    errors.push(err)
  }
  if action.runtime != "composite" {
    errors.push("only composite local actions are supported in MVP")
  }
  if errors.length() > 0 {
    { action: None, errors }
  } else {
    {
      action: Some(
        new_local_action(action.steps, name=action.name, inputs=action.inputs),
      ),
      errors,
    }
  }
}

///|
pub fn parse_workflow_yaml(text : String) -> WorkflowParseResult {
  let (yaml, parser_errors) = parse_yaml_document(text)
  let errors : Array[String] = []
  for err in parser_errors {
    errors.push(err)
  }
  guard yaml is Obj(root_fields) else {
    errors.push("workflow root must be a mapping")
    return { workflow: None, errors }
  }

  let jobs_value = yaml_obj_get(root_fields, "jobs")
  let jobs : Array[JobSpec] = []
  match jobs_value {
    Some(Obj(job_fields)) =>
      for field in job_fields {
        jobs.push(parse_job(field.key, field.value, errors))
      }
    Some(_) => errors.push("jobs must be a mapping")
    None => errors.push("jobs is required")
  }

  let workflow = new_workflow(
    yaml_as_optional_string(yaml_obj_get(root_fields, "name"), errors, "name").unwrap_or(
      "",
    ),
    jobs,
    trigger=parse_trigger(yaml_obj_get(root_fields, "on"), errors),
    permissions=parse_permissions(
      yaml_obj_get(root_fields, "permissions"),
      errors,
      "permissions",
    ),
    env=yaml_to_string_map(yaml_obj_get(root_fields, "env"), errors, "env"),
    defaults=parse_run_defaults(
      yaml_obj_get(root_fields, "defaults"),
      errors,
      "defaults",
    ),
  )

  if errors.length() > 0 {
    { workflow: None, errors }
  } else {
    { workflow: Some(workflow), errors }
  }
}
