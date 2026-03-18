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
      out.push("export " + shell_quote_assign(key, value))
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
      out.push("export " + shell_quote_assign(key, value))
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
      out.push("export " + shell_quote_assign(key, value))
    }
    out.push("")
  }
  // Steps
  for i, step in job.steps {
    emit_step(step, i, job.id, out)
  }
}

///|
fn emit_step(
  step : @ar.StepSpec,
  index : Int,
  _job_id : String,
  out : Array[String],
) -> Unit {
  // Step header
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
      out.push("export " + shell_quote_assign(key, value))
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
        Option::Some(script) =>
          // Continue on error
          if step.continue_on_error == "true" {
            out.push(script.trim(chars=" \t\r\n").to_string() + " || true")
          } else {
            out.push(script.trim(chars=" \t\r\n").to_string())
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
    // Checkout into a subdirectory
    let depth = if fetch_depth.length() > 0 {
      " --depth " + fetch_depth
    } else {
      " --depth 1"
    }
    out.push(
      "git clone" +
      depth +
      " \"$\u007bGITHUB_SERVER_URL:-https://github.com}/$\u007bGITHUB_REPOSITORY}\" " +
      shell_quote(path),
    )
    if ref_val.length() > 0 {
      out.push(
        "(cd " +
        shell_quote(path) +
        " && git checkout " +
        shell_quote(ref_val) +
        ")",
      )
    }
    // In-place checkout (assume we're in the repo)
  } else if ref_val.length() > 0 {
    out.push("git checkout " + shell_quote(ref_val))
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
    out.push("# mise use node@$(cat " + shell_quote(version_file) + " | head -1 | tr -d 'v ')")
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
  out.push("# actions/setup-python — uncomment your preferred version manager:")
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
  let name = get_with(with_values, "name")
  let path = get_with(with_values, "path")
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
  let name = get_with(with_values, "name")
  let path = get_with(with_values, "path")
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
  "true # if: " + cond
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
  // If no special characters, return as-is
  let mut needs_quote = false
  for ch in s {
    if ch == ' ' ||
      ch == '\t' ||
      ch == '"' ||
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
fn shell_quote_assign(key : String, value : String) -> String {
  // For export KEY=VALUE, quote the value if it contains ${{ }}
  if value.contains("$\u007b\u007b") {
    // Preserve expression as-is (it's a GitHub Actions expression, user needs to adapt)
    key + "=" + shell_quote(value) + "  # TODO: resolve expression"
  } else {
    key + "=" + shell_quote(value)
  }
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
