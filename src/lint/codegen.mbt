///|
/// Convert a workflow to a shell script (experimental)
pub fn workflow_to_shell(workflow : @ar.WorkflowSpec) -> String {
  let out : Array[String] = []
  out.push("#!/usr/bin/env bash")
  out.push("set -euo pipefail")
  out.push("")
  out.push("# Generated from workflow: " + workflow.name)
  out.push("# This is an experimental approximation — review before running")
  out.push("")
  // Workflow-level env
  if workflow.env.length() > 0 {
    out.push("# Workflow environment")
    for key, value in workflow.env {
      out.push("export " + key + "=" + shell_quote(resolve_expressions(value)))
    }
    out.push("")
  }
  // Sort jobs by dependency order
  let ordered = topo_sort_jobs(workflow.jobs)
  for job in ordered {
    emit_job(job, workflow, out)
  }
  out.join("\n")
}

///|
/// Convert a single job to a shell script
pub fn job_to_shell(job : @ar.JobSpec, workflow : @ar.WorkflowSpec) -> String {
  let out : Array[String] = []
  out.push("#!/usr/bin/env bash")
  out.push("set -euo pipefail")
  out.push("")
  out.push("# Job: " + job.id)
  if workflow.env.length() > 0 {
    for key, value in workflow.env {
      out.push("export " + key + "=" + shell_quote(resolve_expressions(value)))
    }
    out.push("")
  }
  emit_job(job, workflow, out)
  out.join("\n")
}

///|
fn emit_job(
  job : @ar.JobSpec,
  _workflow : @ar.WorkflowSpec,
  out : Array[String],
) -> Unit {
  let header = "# " + "=".repeat(60)
  out.push(header)
  let label = if job.name.length() > 0 { job.name } else { job.id }
  out.push("# Job: " + label)
  out.push(header)
  out.push("")
  // Job-level if condition
  if job.if_condition.length() > 0 && job.if_condition != "success()" {
    out.push("# if: " + job.if_condition)
    out.push("")
  }
  // Needs as comment
  if job.needs.length() > 0 {
    out.push("# depends on: " + job.needs.join(", "))
    out.push("")
  }
  // Job-level env
  if job.env.length() > 0 {
    for key, value in job.env {
      out.push("export " + key + "=" + shell_quote(resolve_expressions(value)))
    }
    out.push("")
  }
  // Steps
  for i, step in job.steps {
    emit_step(step, i, job.id, out)
  }
  // Capture job outputs as shell variables for downstream needs
  if job.outputs.length() > 0 {
    out.push(
      "# Job outputs (available to downstream jobs as _NEEDS_<JOB>_<KEY>)",
    )
    for key, value in job.outputs {
      let var_name = "_NEEDS_" + to_shell_var(job.id) + "_" + to_shell_var(key)
      out.push(var_name + "=" + shell_quote(resolve_expressions(value)))
    }
    out.push("")
  }
}

///|
fn emit_step(
  step : @ar.StepSpec,
  index : Int,
  job_id : String,
  out : Array[String],
) -> Unit {
  let label = if step.name.length() > 0 {
    step.name
  } else if step.id.length() > 0 {
    step.id
  } else {
    "Step " + (index + 1).to_string()
  }
  out.push("# --- " + label + " ---")
  // If condition
  if step.if_condition.length() > 0 && step.if_condition != "success()" {
    let cond = translate_if_condition(step.if_condition)
    if cond.length() > 0 {
      out.push("if " + cond + "; then")
    }
  }
  // Step env
  if step.env.length() > 0 {
    for key, value in step.env {
      out.push("export " + key + "=" + shell_quote(resolve_expressions(value)))
    }
  }
  // Working directory
  match step.working_directory {
    Option::Some(dir) => out.push("pushd " + shell_quote(dir) + " > /dev/null")
    Option::None => ()
  }
  // Body
  match step.uses {
    Option::Some(uses) => emit_uses_step(uses, step.with_values, out)
    Option::None =>
      match step.run {
        Option::Some(script) => {
          let resolved = resolve_expressions(
            script.trim(chars=" \t\r\n").to_string(),
          )
          // Convert GITHUB_OUTPUT writes to shell variable captures
          let converted = convert_github_output(resolved, step.id, job_id)
          if step.continue_on_error == "true" {
            out.push(converted + " || true")
          } else {
            out.push(converted)
          }
        }
        Option::None => out.push("# (empty step)")
      }
  }
  // Pop working directory
  match step.working_directory {
    Option::Some(_) => out.push("popd > /dev/null")
    Option::None => ()
  }
  // Close if block
  if step.if_condition.length() > 0 && step.if_condition != "success()" {
    let cond = translate_if_condition(step.if_condition)
    if cond.length() > 0 {
      out.push("fi")
    }
  }
  out.push("")
}

///|
fn emit_uses_step(
  uses : String,
  with_values : Map[String, String],
  out : Array[String],
) -> Unit {
  if uses.contains("actions/checkout") {
    emit_checkout(with_values, out)
  } else if uses.contains("actions/setup-node") {
    emit_setup_node(with_values, out)
  } else if uses.contains("actions/setup-python") {
    emit_setup_python(with_values, out)
  } else if uses.contains("actions/upload-artifact") {
    emit_upload_artifact(with_values, out)
  } else if uses.contains("actions/download-artifact") {
    emit_download_artifact(with_values, out)
  } else if uses.contains("actions/cache") {
    emit_cache(uses, with_values, out)
  } else if uses.contains("extractions/setup-just") {
    out.push("# " + uses)
    out.push("# command -v just > /dev/null || cargo install just")
    out.push("# mise use -g just  # alternative: mise")
  } else if uses.has_prefix("./") {
    out.push("# local action: " + uses)
    out.push(
      "# TODO: inline composite action steps from " + uses + "/action.yml",
    )
  } else if uses.has_prefix("docker://") {
    let image = String::unsafe_substring(uses, start=9, end=uses.length())
    out.push("docker run --rm " + shell_quote(image))
  } else {
    out.push("# TODO: " + uses)
    out.push("echo \"[skip] " + uses + " — no shell equivalent\"")
  }
}

///|
fn emit_checkout(
  with_values : Map[String, String],
  out : Array[String],
) -> Unit {
  let ref_val = get_with(with_values, "ref")
  let path = get_with(with_values, "path")
  let fetch_depth = get_with(with_values, "fetch-depth")
  let submodules = get_with(with_values, "submodules")
  if path.length() > 0 {
    let depth = if fetch_depth.length() > 0 {
      " --depth " + fetch_depth
    } else {
      " --depth 1"
    }
    out.push(
      "git clone" +
      depth +
      " \"$\u007bGITHUB_SERVER_URL:-https://github.com}/$\u007bGITHUB_REPOSITORY}\" " +
      shell_quote(resolve_expressions(path)),
    )
    if ref_val.length() > 0 {
      out.push(
        "(cd " +
        shell_quote(resolve_expressions(path)) +
        " && git checkout " +
        shell_quote(resolve_expressions(ref_val)) +
        ")",
      )
    }
  } else if ref_val.length() > 0 {
    out.push("git checkout " + shell_quote(resolve_expressions(ref_val)))
  } else {
    out.push("git fetch --depth 1 origin")
    if fetch_depth.length() > 0 && fetch_depth != "1" {
      out.push("git fetch --depth " + fetch_depth + " origin")
    }
  }
  if submodules == "true" || submodules == "recursive" {
    out.push("git submodule update --init --recursive")
  }
}

///|
fn emit_setup_node(
  with_values : Map[String, String],
  out : Array[String],
) -> Unit {
  let version = get_with(with_values, "node-version")
  let version_file = get_with(with_values, "node-version-file")
  let registry = get_with(with_values, "registry-url")
  out.push("# actions/setup-node — uncomment your preferred version manager:")
  if version.length() > 0 {
    out.push("# Node.js " + version)
    out.push("# mise use node@" + version)
    out.push("# fnm use " + version + " || fnm install " + version)
    out.push("# nvm use " + version + " || nvm install " + version)
  } else if version_file.length() > 0 {
    out.push("# Node version from " + version_file)
    out.push(
      "# mise use node@$(cat " +
      shell_quote(version_file) +
      " | head -1 | tr -d 'v ')",
    )
  } else {
    out.push("# Using system Node.js")
  }
  out.push("node --version")
  if registry.length() > 0 {
    out.push("npm config set registry " + shell_quote(registry))
  }
  let cache = get_with(with_values, "cache")
  if cache.length() > 0 {
    out.push("# cache: " + cache + " (handled by package manager)")
  }
}

///|
fn emit_setup_python(
  with_values : Map[String, String],
  out : Array[String],
) -> Unit {
  let version = get_with(with_values, "python-version")
  out.push(
    "# actions/setup-python — uncomment your preferred version manager:",
  )
  if version.length() > 0 {
    out.push("# Python " + version)
    out.push("# mise use python@" + version)
    out.push("# uv python install " + version)
    out.push("# pyenv install -s " + version + " && pyenv local " + version)
  } else {
    out.push("# Using system Python")
  }
  out.push("python3 --version")
}

///|
fn emit_upload_artifact(
  with_values : Map[String, String],
  out : Array[String],
) -> Unit {
  let name = resolve_expressions(get_with(with_values, "name"))
  let path = resolve_expressions(get_with(with_values, "path"))
  let artifact_name = if name.length() > 0 { name } else { "artifact" }
  if path.length() > 0 {
    out.push("# Upload artifact: " + artifact_name)
    out.push(
      "mkdir -p \"$\u007bACTRUN_ARTIFACT_DIR:-.artifacts}/" +
      artifact_name +
      "\"",
    )
    out.push(
      "cp -r " +
      shell_quote(path) +
      " \"$\u007bACTRUN_ARTIFACT_DIR:-.artifacts}/" +
      artifact_name +
      "/\"",
    )
  } else {
    out.push("# upload-artifact: no path specified")
  }
}

///|
fn emit_download_artifact(
  with_values : Map[String, String],
  out : Array[String],
) -> Unit {
  let name = resolve_expressions(get_with(with_values, "name"))
  let path = resolve_expressions(get_with(with_values, "path"))
  let dest = if path.length() > 0 { path } else { "." }
  if name.length() > 0 {
    out.push("# Download artifact: " + name)
    out.push(
      "cp -r \"$\u007bACTRUN_ARTIFACT_DIR:-.artifacts}/" +
      name +
      "/.\" " +
      shell_quote(dest),
    )
  } else {
    out.push("# download-artifact: no name specified")
  }
}

///|
fn emit_cache(
  uses : String,
  with_values : Map[String, String],
  out : Array[String],
) -> Unit {
  let key = get_with(with_values, "key")
  let path = get_with(with_values, "path")
  out.push("# " + uses)
  if key.length() > 0 {
    out.push("# cache key: " + key)
  }
  if path.length() > 0 {
    out.push("# cache path: " + path)
  }
  out.push("# (caching is a no-op in shell export)")
}

///|
/// Replace ${{ expr }} with shell variable references
fn resolve_expressions(text : String) -> String {
  let prefix = "$\u007b\u007b"
  let suffix = "}}"
  let mut result = text
  // Iteratively replace ${{ ... }} patterns
  let mut safety = 0
  while safety < 50 {
    safety += 1
    let start = find_substr(result, prefix, 0)
    if start < 0 {
      break
    }
    let end = find_substr(result, suffix, start + prefix.length())
    if end < 0 {
      break
    }
    let expr = String::unsafe_substring(
        result,
        start=start + prefix.length(),
        end~,
      )
      .trim(chars=" \t")
      .to_string()
    let replacement = expr_to_shell_var(expr)
    let before = String::unsafe_substring(result, start=0, end=start)
    let after = String::unsafe_substring(
      result,
      start=end + suffix.length(),
      end=result.length(),
    )
    result = before + replacement + after
  }
  result
}

///|
/// Convert a GitHub Actions expression to a shell variable reference
fn expr_to_shell_var(expr : String) -> String {
  // env.VAR → $VAR
  if expr.has_prefix("env.") {
    let var_name = String::unsafe_substring(expr, start=4, end=expr.length())
    return "$" + var_name
  }
  // secrets.VAR → $SECRET_VAR
  if expr.has_prefix("secrets.") {
    let var_name = String::unsafe_substring(expr, start=8, end=expr.length())
    return "$SECRET_" + to_shell_var(var_name)
  }
  // github.* → known mappings
  if expr.has_prefix("github.") {
    return resolve_github_context(expr)
  }
  // matrix.VAR → $MATRIX_VAR
  if expr.has_prefix("matrix.") {
    let var_name = String::unsafe_substring(expr, start=7, end=expr.length())
    return "$MATRIX_" + to_shell_var(var_name)
  }
  // runner.* → known mappings
  if expr.has_prefix("runner.") {
    let field = String::unsafe_substring(expr, start=7, end=expr.length())
    return "$RUNNER_" + to_shell_var(field)
  }
  // steps.ID.outputs.KEY → $_STEP_ID_KEY
  if expr.has_prefix("steps.") {
    return resolve_step_ref(expr)
  }
  // needs.JOB.outputs.KEY → $_NEEDS_JOB_KEY
  if expr.has_prefix("needs.") {
    return resolve_needs_ref(expr)
  }
  // Boolean/function expressions — pass through as comment
  if expr.contains("(") {
    return "# " + expr
  }
  // Fallback
  "$\u007b" + expr + "}"
}

///|
fn resolve_github_context(expr : String) -> String {
  let known : Map[String, String] = {}
  known["github.ref"] = "$GITHUB_REF"
  known["github.ref_name"] = "$GITHUB_REF_NAME"
  known["github.sha"] = "$GITHUB_SHA"
  known["github.repository"] = "$GITHUB_REPOSITORY"
  known["github.actor"] = "$GITHUB_ACTOR"
  known["github.workflow"] = "$GITHUB_WORKFLOW"
  known["github.run_id"] = "$GITHUB_RUN_ID"
  known["github.run_number"] = "$GITHUB_RUN_NUMBER"
  known["github.workspace"] = "$GITHUB_WORKSPACE"
  known["github.server_url"] = "$GITHUB_SERVER_URL"
  known["github.api_url"] = "$GITHUB_API_URL"
  known["github.token"] = "$GITHUB_TOKEN"
  known["github.event_name"] = "$GITHUB_EVENT_NAME"
  known["github.head_ref"] = "$GITHUB_HEAD_REF"
  known["github.base_ref"] = "$GITHUB_BASE_REF"
  known["github.job"] = "$GITHUB_JOB"
  known["github.action"] = "$GITHUB_ACTION"
  known["github.action_path"] = "$GITHUB_ACTION_PATH"
  known["github.triggering_actor"] = "$GITHUB_TRIGGERING_ACTOR"
  match known.get(expr) {
    Some(v) => v
    None =>
      // github.event.* → jq from event.json
      if expr.has_prefix("github.event.") {
        let jq_path = "." +
          String::unsafe_substring(expr, start=13, end=expr.length())
        "$(jq -r '" + jq_path + "' \"$GITHUB_EVENT_PATH\")"
      } else {
        "$\u007b" + to_shell_var(expr) + "}"
      }
  }
}

///|
fn resolve_step_ref(expr : String) -> String {
  // steps.ID.outputs.KEY → $_STEP_ID_KEY
  // steps.ID.outcome → $_STEP_ID_OUTCOME
  let rest = String::unsafe_substring(expr, start=6, end=expr.length())
  let parts = split_by_dot(rest)
  if parts.length() >= 3 && parts[1] == "outputs" {
    let step_id = parts[0]
    let key = parts[2]
    "$_STEP_" + to_shell_var(step_id) + "_" + to_shell_var(key)
  } else if parts.length() >= 2 && parts[1] == "outcome" {
    "$_STEP_" + to_shell_var(parts[0]) + "_OUTCOME"
  } else if parts.length() >= 2 && parts[1] == "conclusion" {
    "$_STEP_" + to_shell_var(parts[0]) + "_CONCLUSION"
  } else {
    "$\u007bsteps." + rest + "}"
  }
}

///|
fn resolve_needs_ref(expr : String) -> String {
  // needs.JOB.outputs.KEY → $_NEEDS_JOB_KEY
  // needs.JOB.result → $_NEEDS_JOB_RESULT
  let rest = String::unsafe_substring(expr, start=6, end=expr.length())
  let parts = split_by_dot(rest)
  if parts.length() >= 3 && parts[1] == "outputs" {
    let job_id = parts[0]
    let key = parts[2]
    "$_NEEDS_" + to_shell_var(job_id) + "_" + to_shell_var(key)
  } else if parts.length() >= 2 && parts[1] == "result" {
    "$_NEEDS_" + to_shell_var(parts[0]) + "_RESULT"
  } else {
    "$\u007bneeds." + rest + "}"
  }
}

///|
/// Convert GITHUB_OUTPUT writes to shell variable assignments
/// `echo "key=value" >> "$GITHUB_OUTPUT"` → `_STEP_<ID>_<KEY>=value`
fn convert_github_output(
  script : String,
  step_id : String,
  _job_id : String,
) -> String {
  if not(script.contains("GITHUB_OUTPUT")) {
    return script
  }
  let lines : Array[String] = []
  for line_view in script.split("\n") {
    let line = line_view.to_string()
    let trimmed = line.trim(chars=" \t\r").to_string()
    // Match: echo "key=value" >> "$GITHUB_OUTPUT"
    if trimmed.contains(">>") && trimmed.contains("GITHUB_OUTPUT") {
      // Try to extract key=value pattern
      let kv = extract_output_kv(trimmed)
      match kv {
        Option::Some((key, value)) => {
          let var_name = if step_id.length() > 0 {
            "_STEP_" + to_shell_var(step_id) + "_" + to_shell_var(key)
          } else {
            "_OUTPUT_" + to_shell_var(key)
          }
          lines.push(var_name + "=" + shell_quote(value))
        }
        Option::None => lines.push(line)
      }
    } else if trimmed.contains(">>") && trimmed.contains("GITHUB_ENV") {
      // echo "KEY=value" >> "$GITHUB_ENV" → export KEY=value
      let kv = extract_output_kv(trimmed)
      match kv {
        Option::Some((key, value)) =>
          lines.push("export " + key + "=" + shell_quote(value))
        Option::None => lines.push(line)
      }
    } else {
      lines.push(line)
    }
  }
  lines.join("\n")
}

///|
/// Extract key=value from echo "key=value" >> ... patterns
fn extract_output_kv(line : String) -> (String, String)? {
  // Find the quoted content between echo " and " >>
  let echo_idx = find_substr(line, "echo ", 0)
  if echo_idx < 0 {
    return Option::None
  }
  let content_start = echo_idx + 5
  // Skip opening quote
  let mut start = content_start
  if start < line.length() && line.unsafe_get(start) == '"' {
    start += 1
  }
  // Find >>
  let redir = find_substr(line, ">>", start)
  if redir < 0 {
    return Option::None
  }
  let mut end = redir
  // Strip trailing quote and whitespace
  while end > start &&
        (line.unsafe_get(end - 1) == '"' || line.unsafe_get(end - 1) == ' ') {
    end -= 1
  }
  let content = String::unsafe_substring(line, start~, end~)
  // Find = in content
  let eq = find_substr(content, "=", 0)
  if eq < 0 {
    return Option::None
  }
  let key = String::unsafe_substring(content, start=0, end=eq)
  let value = String::unsafe_substring(
    content,
    start=eq + 1,
    end=content.length(),
  )
  Option::Some((key, value))
}

///|
/// Convert string to valid shell variable name (uppercase, replace non-alnum with _)
fn to_shell_var(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') {
      buf.write_char(
        if ch >= 'a' && ch <= 'z' {
          Int::unsafe_to_char(ch.to_int() - 32)
        } else {
          ch
        },
      )
    } else {
      buf.write_char('_')
    }
  }
  buf.to_string()
}

///|
fn split_by_dot(s : String) -> Array[String] {
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
  let last = buf.to_string()
  if last.length() > 0 {
    parts.push(last)
  }
  parts
}

///|
fn find_substr(text : String, pattern : String, from : Int) -> Int {
  if pattern.length() == 0 {
    return from
  }
  let mut idx = from
  while idx + pattern.length() <= text.length() {
    let seg = String::unsafe_substring(
      text,
      start=idx,
      end=idx + pattern.length(),
    )
    if seg == pattern {
      return idx
    }
    idx += 1
  }
  -1
}

///|
fn translate_if_condition(cond : String) -> String {
  let expr = unwrap_expression_for_codegen(cond)
  if expr == "always()" || expr == "always" {
    return "true"
  }
  if expr == "failure()" || expr == "failure" {
    return "[ \"$_STEP_FAILED\" = \"1\" ]"
  }
  if expr == "cancelled()" || expr == "cancelled" {
    return "false"
  }
  if expr == "success()" || expr == "success" {
    return ""
  }
  // Try to resolve expression to shell
  let resolved = resolve_expressions(cond)
  if resolved != cond {
    "true # " + resolved
  } else {
    "true # if: " + cond
  }
}

///|
fn unwrap_expression_for_codegen(text : String) -> String {
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
fn get_with(values : Map[String, String], key : String) -> String {
  values.get(key).unwrap_or("")
}

///|
fn shell_quote(s : String) -> String {
  if s.length() == 0 {
    return "\"\""
  }
  let mut needs_quote = false
  for ch in s {
    if ch == ' ' ||
      ch == '\t' ||
      ch == '\'' ||
      ch == '\\' ||
      ch == '(' ||
      ch == ')' ||
      ch == '&' ||
      ch == '|' ||
      ch == ';' ||
      ch == '<' ||
      ch == '>' ||
      ch == '*' ||
      ch == '?' ||
      ch == '!' ||
      ch == '{' ||
      ch == '}' ||
      ch == '[' ||
      ch == ']' {
      needs_quote = true
      break
    }
  }
  if not(needs_quote) {
    return s
  }
  "\"" + s + "\""
}

///|
fn topo_sort_jobs(jobs : Array[@ar.JobSpec]) -> Array[@ar.JobSpec] {
  let id_map : Map[String, @ar.JobSpec] = {}
  for job in jobs {
    id_map[job.id] = job
  }
  let visited : Map[String, Bool] = {}
  let result : Array[@ar.JobSpec] = []
  for job in jobs {
    topo_visit(job.id, id_map, visited, result)
  }
  result
}

///|
fn topo_visit(
  id : String,
  id_map : Map[String, @ar.JobSpec],
  visited : Map[String, Bool],
  result : Array[@ar.JobSpec],
) -> Unit {
  if visited.get(id).unwrap_or(false) {
    return
  }
  visited[id] = true
  match id_map.get(id) {
    Some(job) => {
      for need_id in job.needs {
        topo_visit(need_id, id_map, visited, result)
      }
      result.push(job)
    }
    None => ()
  }
}
