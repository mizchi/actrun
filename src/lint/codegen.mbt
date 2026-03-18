///|
/// Convert a workflow to a shell script (experimental)
pub fn workflow_to_shell(
  workflow : @ar.WorkflowSpec,
  reusable_workflows? : Map[String, @ar.WorkflowSpec] = {},
  parallel? : Bool = false,
) -> String {
  let out : Array[String] = []
  out.push("#!/usr/bin/env bash")
  out.push("set -eo pipefail")
  out.push("")
  out.push("# Generated from workflow: " + workflow.name)
  out.push("# This is an experimental approximation — review before running")
  out.push("# Requires: bash, jq")
  out.push("")
  if parallel {
    out.push("_TMPDIR=$(mktemp -d)")
    out.push("trap 'rm -rf \"$_TMPDIR\"' EXIT")
    out.push("")
  }
  emit_helpers(out)
  out.push("")
  // Workflow-level env
  if workflow.env.length() > 0 {
    out.push("# Workflow environment")
    for key, value in workflow.env {
      out.push("export " + key + "=" + shell_quote(resolve_expr(value)))
    }
    out.push("")
  }
  // Emit job functions — in parallel mode, outputs go to temp files
  let ordered = topo_sort_jobs(workflow.jobs)
  for job in ordered {
    match job.reusable_workflow {
      Option::Some(callee_path) =>
        emit_reusable_job(job, callee_path, reusable_workflows, out)
      Option::None =>
        if parallel {
          emit_job_function_parallel(job, out)
        } else {
          emit_job_function(job, out)
        }
    }
  }
  // Run section
  out.push("# " + "=".repeat(60))
  out.push("# Run jobs")
  out.push("# " + "=".repeat(60))
  out.push("")
  if parallel {
    emit_parallel_run(workflow.jobs, out)
  } else {
    emit_sequential_run(ordered, out)
  }
  out.join("\n")
}

///|
fn emit_sequential_run(
  ordered : Array[@ar.JobSpec],
  out : Array[String],
) -> Unit {
  for job in ordered {
    let fn_name = "job_" + to_shell_var(job.id)
    if job.if_condition.length() > 0 && job.if_condition != "success()" {
      out.push("# if: " + job.if_condition)
    }
    out.push(fn_name + " && _rc=0 || _rc=$?")
    let jvar = to_shell_var(job.id)
    out.push(
      "if [ \"$_rc\" -eq 0 ]; then _NEEDS_" +
      jvar +
      "_RESULT=success; else _NEEDS_" +
      jvar +
      "_RESULT=failure; fi",
    )
    out.push("")
  }
}

///|
fn emit_parallel_run(jobs : Array[@ar.JobSpec], out : Array[String]) -> Unit {
  // Compute layers: each layer is a set of jobs whose deps are all in previous layers
  let layers = compute_layers(jobs)
  for layer_idx, layer in layers {
    if layer.length() == 0 {
      continue
    }
    out.push("# --- Layer " + layer_idx.to_string() + " ---")
    if layer.length() == 1 {
      // Single job — run directly
      let job = layer[0]
      let fn_name = "job_" + to_shell_var(job.id)
      let jvar = to_shell_var(job.id)
      out.push(fn_name + " && _rc=0 || _rc=$?")
      out.push(
        "if [ \"$_rc\" -eq 0 ]; then _NEEDS_" +
        jvar +
        "_RESULT=success; else _NEEDS_" +
        jvar +
        "_RESULT=failure; fi",
      )
      // Load outputs from temp file
      out.push(
        "[ -f \"$_TMPDIR/" +
        job.id +
        ".env\" ] && source \"$_TMPDIR/" +
        job.id +
        ".env\" || true",
      )
    } else {
      // Multiple jobs — run in parallel with &
      for job in layer {
        let fn_name = "job_" + to_shell_var(job.id)
        out.push(
          "( " +
          fn_name +
          " && echo success > \"$_TMPDIR/" +
          job.id +
          ".result\"" +
          " || echo failure > \"$_TMPDIR/" +
          job.id +
          ".result\" ) &",
        )
      }
      out.push("wait")
      out.push("")
      // Collect results
      for job in layer {
        let jvar = to_shell_var(job.id)
        out.push(
          "_NEEDS_" + jvar + "_RESULT=$(cat \"$_TMPDIR/" + job.id + ".result\")",
        )
        out.push(
          "[ -f \"$_TMPDIR/" +
          job.id +
          ".env\" ] && source \"$_TMPDIR/" +
          job.id +
          ".env\"",
        )
      }
    }
    out.push("")
  }
}

///|
/// Job function variant for parallel mode: write outputs to temp file
fn emit_job_function_parallel(job : @ar.JobSpec, out : Array[String]) -> Unit {
  let fn_name = "job_" + to_shell_var(job.id)
  let label = if job.name.length() > 0 { job.name } else { job.id }
  out.push("# " + "=".repeat(60))
  out.push("# Job: " + label)
  out.push("# " + "=".repeat(60))
  out.push(fn_name + "() {")
  if job.needs.length() > 0 {
    out.push("  # depends on: " + job.needs.join(", "))
  }
  match job.matrix {
    Option::Some(m) =>
      if m.rows.length() > 0 {
        out.push("  # matrix — defaulting to first combination:")
        let first_row = m.rows[0]
        for key, value in first_row {
          out.push(
            "  : \"$\u007bMATRIX_" + to_shell_var(key) + ":=" + value + "}\"",
          )
        }
      }
    Option::None => ()
  }
  out.push("")
  if job.env.length() > 0 {
    for key, value in job.env {
      let resolved = resolve_expr(value)
      if resolved != value {
        out.push(
          "  export " +
          key +
          "=" +
          shell_quote(resolved) +
          comment_origin(value),
        )
      } else {
        out.push("  export " + key + "=" + shell_quote(value))
      }
    }
    out.push("")
  }
  for i, step in job.steps {
    emit_step(step, i, job.id, out, indent="  ")
  }
  // Write outputs to temp file so parent can source them
  if job.outputs.length() > 0 {
    out.push("  # Export outputs to temp file for cross-job access")
    out.push("  {")
    for key, value in job.outputs {
      let var_name = "_NEEDS_" +
        to_shell_var(job.id) +
        "_OUT_" +
        to_shell_var(key)
      let resolved = resolve_expr(value)
      out.push(
        "    echo " +
        var_name +
        "=" +
        shell_quote(resolved) +
        comment_origin(value),
      )
    }
    out.push("  } > \"$_TMPDIR/" + job.id + ".env\"")
    out.push("")
  }
  out.push("}")
  out.push("")
}

///|
fn compute_layers(jobs : Array[@ar.JobSpec]) -> Array[Array[@ar.JobSpec]] {
  let job_map : Map[String, @ar.JobSpec] = {}
  for job in jobs {
    job_map[job.id] = job
  }
  let assigned : Map[String, Int] = {} // job_id → layer
  let layers : Array[Array[@ar.JobSpec]] = []
  // Assign layers iteratively
  let mut changed = true
  while changed {
    changed = false
    for job in jobs {
      if assigned.get(job.id) is Some(_) {
        continue
      }
      if job.needs.length() == 0 {
        assigned[job.id] = 0
        changed = true
      } else {
        // Check if all deps are assigned
        let mut all_assigned = true
        let mut max_dep_layer = 0
        for need_id in job.needs {
          match assigned.get(need_id) {
            Some(layer) => if layer > max_dep_layer { max_dep_layer = layer }
            None => {
              all_assigned = false
              break
            }
          }
        }
        if all_assigned {
          assigned[job.id] = max_dep_layer + 1
          changed = true
        }
      }
    }
  }
  // Build layer arrays
  let mut max_layer = 0
  for _id, layer in assigned {
    if layer > max_layer {
      max_layer = layer
    }
  }
  let mut i = 0
  while i <= max_layer {
    layers.push([])
    i += 1
  }
  for job in jobs {
    match assigned.get(job.id) {
      Some(layer) => layers[layer].push(job)
      None => () // Unassigned (cycle?) — skip
    }
  }
  layers
}

///|
/// Convert a single job to a shell script
pub fn job_to_shell(job : @ar.JobSpec, workflow : @ar.WorkflowSpec) -> String {
  let out : Array[String] = []
  out.push("#!/usr/bin/env bash")
  out.push("set -eo pipefail")
  out.push("")
  out.push("# Job: " + job.id)
  if workflow.env.length() > 0 {
    for key, value in workflow.env {
      out.push("export " + key + "=" + shell_quote(resolve_expr(value)))
    }
    out.push("")
  }
  emit_job_body(job, out)
  out.join("\n")
}

///|
fn emit_helpers(out : Array[String]) -> Unit {
  out.push("# --- GitHub Actions expression helpers ---")
  out.push("gha_contains() { [[ \"$1\" == *\"$2\"* ]]; }")
  out.push("gha_startsWith() { [[ \"$1\" == \"$2\"* ]]; }")
  out.push("gha_endsWith() { [[ \"$1\" == *\"$2\" ]]; }")
  out.push("gha_format() { local fmt=\"$1\"; shift; printf \"$fmt\" \"$@\"; }")
  out.push("gha_join() { local IFS=\"$\u007b2:-,}\"; echo \"$\u007b1[*]}\"; }")
  out.push(
    "gha_toJSON() { jq -n --argjson v \"$(printenv | jq -Rs 'split(\"\\n\") | map(select(length > 0) | split(\"=\") | {(.[0]): (.[1:] | join(\"=\"))}) | add // {}')\" '$v'; }",
  )
  out.push("gha_fromJSON() { echo \"$1\" | jq -r '.'; }")
  out.push(
    "gha_hashFiles() { cat \"$@\" 2>/dev/null | sha256sum | cut -d' ' -f1; }",
  )
  out.push(
    "gha_success() { [ \"$\u007b_NEEDS_LAST_RESULT:-success}\" = \"success\" ]; }",
  )
  out.push(
    "gha_failure() { [ \"$\u007b_NEEDS_LAST_RESULT:-success}\" = \"failure\" ]; }",
  )
  out.push("gha_always() { true; }")
  out.push("gha_cancelled() { false; }")
}

///|
fn emit_job_function(job : @ar.JobSpec, out : Array[String]) -> Unit {
  let fn_name = "job_" + to_shell_var(job.id)
  let label = if job.name.length() > 0 { job.name } else { job.id }
  out.push("# " + "=".repeat(60))
  out.push("# Job: " + label)
  out.push("# " + "=".repeat(60))
  out.push(fn_name + "() {")
  // Needs as comment
  if job.needs.length() > 0 {
    out.push("  # depends on: " + job.needs.join(", "))
  }
  // Matrix variables: set defaults from first row
  match job.matrix {
    Option::Some(m) =>
      if m.rows.length() > 0 {
        out.push("  # matrix — defaulting to first combination:")
        let first_row = m.rows[0]
        for key, value in first_row {
          out.push(
            "  : \"$\u007bMATRIX_" + to_shell_var(key) + ":=" + value + "}\"",
          )
        }
      }
    Option::None => ()
  }
  out.push("")
  // Job-level env
  if job.env.length() > 0 {
    for key, value in job.env {
      let resolved = resolve_expr(value)
      if resolved != value {
        out.push(
          "  export " +
          key +
          "=" +
          shell_quote(resolved) +
          comment_origin(value),
        )
      } else {
        out.push("  export " + key + "=" + shell_quote(value))
      }
    }
    out.push("")
  }
  // Steps
  for i, step in job.steps {
    emit_step(step, i, job.id, out, indent="  ")
  }
  // Capture job outputs
  if job.outputs.length() > 0 {
    out.push("  # Job outputs")
    for key, value in job.outputs {
      let var_name = "_NEEDS_" +
        to_shell_var(job.id) +
        "_OUT_" +
        to_shell_var(key)
      let resolved = resolve_expr(value)
      out.push(
        "  " + var_name + "=" + shell_quote(resolved) + comment_origin(value),
      )
    }
    out.push("")
  }
  out.push("}")
  out.push("")
}

///|
fn emit_reusable_job(
  job : @ar.JobSpec,
  callee_path : String,
  reusable_workflows : Map[String, @ar.WorkflowSpec],
  out : Array[String],
) -> Unit {
  let fn_name = "job_" + to_shell_var(job.id)
  let label = if job.name.length() > 0 { job.name } else { job.id }
  out.push("# " + "=".repeat(60))
  out.push("# Job: " + label + " (reusable: " + callee_path + ")")
  out.push("# " + "=".repeat(60))
  out.push(fn_name + "() {")
  if job.needs.length() > 0 {
    out.push("  # depends on: " + job.needs.join(", "))
  }
  out.push("")
  // Set inputs from reusable_workflow_with as variables
  if job.reusable_workflow_with.length() > 0 {
    out.push("  # inputs from caller")
    for key, value in job.reusable_workflow_with {
      let resolved = resolve_expr(value)
      out.push(
        "  local INPUT_" +
        to_shell_var(key) +
        "=" +
        shell_quote(resolved) +
        comment_origin(value),
      )
    }
    out.push("")
  }
  // Try to resolve callee and inline its jobs
  let callee_opt : @ar.WorkflowSpec? = reusable_workflows.get(callee_path)
  match callee_opt {
    Option::Some(callee) =>
      // Inline callee jobs' steps
      for callee_job in callee.jobs {
        out.push("  # --- callee job: " + callee_job.id + " ---")
        // Callee env
        if callee_job.env.length() > 0 {
          for key, value in callee_job.env {
            out.push("  export " + key + "=" + shell_quote(resolve_expr(value)))
          }
        }
        for i, step in callee_job.steps {
          emit_step(step, i, callee_job.id, out, indent="  ")
        }
      }
    Option::None => {
      out.push("  # callee not resolved: " + callee_path)
      out.push("  echo \"[skip] reusable workflow: " + callee_path + "\"")
    }
  }
  out.push("}")
  out.push("")
}

///|
fn emit_job_body(job : @ar.JobSpec, out : Array[String]) -> Unit {
  if job.needs.length() > 0 {
    out.push("# depends on: " + job.needs.join(", "))
    out.push("")
  }
  if job.env.length() > 0 {
    for key, value in job.env {
      let resolved = resolve_expr(value)
      if resolved != value {
        out.push(
          "export " + key + "=" + shell_quote(resolved) + comment_origin(value),
        )
      } else {
        out.push("export " + key + "=" + shell_quote(value))
      }
    }
    out.push("")
  }
  for i, step in job.steps {
    emit_step(step, i, job.id, out, indent="")
  }
  if job.outputs.length() > 0 {
    out.push("# Job outputs")
    for key, value in job.outputs {
      let var_name = "_NEEDS_" +
        to_shell_var(job.id) +
        "_OUT_" +
        to_shell_var(key)
      let resolved = resolve_expr(value)
      out.push(var_name + "=" + shell_quote(resolved) + comment_origin(value))
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
  indent~ : String,
) -> Unit {
  let label = if step.name.length() > 0 {
    step.name
  } else if step.id.length() > 0 {
    step.id
  } else {
    "Step " + (index + 1).to_string()
  }
  out.push(indent + "# --- " + label + " ---")
  // If condition
  let mut in_if = false
  if step.if_condition.length() > 0 && step.if_condition != "success()" {
    let cond = translate_if_condition(step.if_condition)
    if cond.length() > 0 {
      out.push(indent + "# if: " + step.if_condition)
      out.push(indent + "if " + cond + "; then")
      in_if = true
    }
  }
  let body_indent = if in_if { indent + "  " } else { indent }
  // Step env
  if step.env.length() > 0 {
    for key, value in step.env {
      let resolved = resolve_expr(value)
      if resolved != value {
        out.push(
          body_indent +
          "export " +
          key +
          "=" +
          shell_quote(resolved) +
          comment_origin(value),
        )
      } else {
        out.push(body_indent + "export " + key + "=" + shell_quote(value))
      }
    }
  }
  // Working directory
  match step.working_directory {
    Option::Some(dir) =>
      out.push(body_indent + "pushd " + shell_quote(dir) + " > /dev/null")
    Option::None => ()
  }
  // Body
  match step.uses {
    Option::Some(uses) =>
      emit_uses_step(uses, step.with_values, out, body_indent)
    Option::None =>
      match step.run {
        Option::Some(script) => {
          let resolved = resolve_expr(script.trim(chars=" \t\r\n").to_string())
          let converted = convert_github_output(resolved, step.id, job_id)
          // Add origin comments for lines that changed
          let final_script = add_origin_comments(
            script.trim(chars=" \t\r\n").to_string(),
            converted,
          )
          if step.continue_on_error == "true" {
            for line_view in final_script.split("\n") {
              let line = line_view.to_string()
              out.push(body_indent + line)
            }
            // Only last command gets || true
          } else {
            for line_view in final_script.split("\n") {
              out.push(body_indent + line_view.to_string())
            }
          }
        }
        Option::None => out.push(body_indent + "# (empty step)")
      }
  }
  // Pop working directory
  match step.working_directory {
    Option::Some(_) => out.push(body_indent + "popd > /dev/null")
    Option::None => ()
  }
  // Close if block
  if in_if {
    out.push(indent + "fi")
  }
  out.push("")
}

///|
fn emit_uses_step(
  uses : String,
  with_values : Map[String, String],
  out : Array[String],
  indent : String,
) -> Unit {
  if uses.contains("actions/checkout") {
    emit_checkout(with_values, out, indent)
  } else if uses.contains("actions/setup-node") {
    emit_setup_node(with_values, out, indent)
  } else if uses.contains("actions/setup-python") {
    emit_setup_python(with_values, out, indent)
  } else if uses.contains("actions/upload-artifact") {
    emit_upload_artifact(with_values, out, indent)
  } else if uses.contains("actions/download-artifact") {
    emit_download_artifact(with_values, out, indent)
  } else if uses.contains("actions/cache") {
    emit_cache(uses, with_values, out, indent)
  } else if uses.contains("extractions/setup-just") {
    out.push(indent + "# " + uses)
    out.push(indent + "# command -v just > /dev/null || cargo install just")
    out.push(indent + "# mise use -g just  # alternative: mise")
  } else if uses.has_prefix("./") {
    out.push(indent + "# local action: " + uses)
    out.push(
      indent +
      "# TODO: inline composite action steps from " +
      uses +
      "/action.yml",
    )
  } else if uses.has_prefix("docker://") {
    let image = String::unsafe_substring(uses, start=9, end=uses.length())
    out.push(indent + "docker run --rm " + shell_quote(image))
  } else {
    out.push(indent + "# TODO: " + uses)
    out.push(indent + "echo \"[skip] " + uses + " — no shell equivalent\"")
  }
}

///|
fn emit_checkout(
  with_values : Map[String, String],
  out : Array[String],
  indent : String,
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
    let resolved_path = resolve_expr(path)
    out.push(
      indent +
      "git clone" +
      depth +
      " \"$\u007bGITHUB_SERVER_URL:-https://github.com}/$\u007bGITHUB_REPOSITORY}\" " +
      shell_quote(resolved_path),
    )
    if ref_val.length() > 0 {
      let resolved_ref = resolve_expr(ref_val)
      out.push(
        indent +
        "(cd " +
        shell_quote(resolved_path) +
        " && git checkout " +
        shell_quote(resolved_ref) +
        ")",
      )
    }
  } else if ref_val.length() > 0 {
    out.push(indent + "git checkout " + shell_quote(resolve_expr(ref_val)))
  } else {
    out.push(indent + "git fetch --depth 1 origin")
    if fetch_depth.length() > 0 && fetch_depth != "1" {
      out.push(indent + "git fetch --depth " + fetch_depth + " origin")
    }
  }
  if submodules == "true" || submodules == "recursive" {
    out.push(indent + "git submodule update --init --recursive")
  }
}

///|
fn emit_setup_node(
  with_values : Map[String, String],
  out : Array[String],
  indent : String,
) -> Unit {
  let version = get_with(with_values, "node-version")
  let version_file = get_with(with_values, "node-version-file")
  let registry = get_with(with_values, "registry-url")
  out.push(
    indent +
    "# actions/setup-node — uncomment your preferred version manager:",
  )
  if version.length() > 0 {
    out.push(indent + "# Node.js " + version)
    out.push(indent + "# mise use node@" + version)
    out.push(indent + "# fnm use " + version + " || fnm install " + version)
    out.push(indent + "# nvm use " + version + " || nvm install " + version)
  } else if version_file.length() > 0 {
    out.push(indent + "# Node version from " + version_file)
    out.push(
      indent +
      "# mise use node@$(cat " +
      shell_quote(version_file) +
      " | head -1 | tr -d 'v ')",
    )
  } else {
    out.push(indent + "# Using system Node.js")
  }
  out.push(indent + "node --version")
  if registry.length() > 0 {
    out.push(indent + "npm config set registry " + shell_quote(registry))
  }
  let cache = get_with(with_values, "cache")
  if cache.length() > 0 {
    out.push(indent + "# cache: " + cache + " (handled by package manager)")
  }
}

///|
fn emit_setup_python(
  with_values : Map[String, String],
  out : Array[String],
  indent : String,
) -> Unit {
  let version = get_with(with_values, "python-version")
  out.push(
    indent +
    "# actions/setup-python — uncomment your preferred version manager:",
  )
  if version.length() > 0 {
    out.push(indent + "# Python " + version)
    out.push(indent + "# mise use python@" + version)
    out.push(indent + "# uv python install " + version)
    out.push(
      indent + "# pyenv install -s " + version + " && pyenv local " + version,
    )
  } else {
    out.push(indent + "# Using system Python")
  }
  out.push(indent + "python3 --version")
}

///|
fn emit_upload_artifact(
  with_values : Map[String, String],
  out : Array[String],
  indent : String,
) -> Unit {
  let name = resolve_expr(get_with(with_values, "name"))
  let path = resolve_expr(get_with(with_values, "path"))
  let artifact_name = if name.length() > 0 { name } else { "artifact" }
  if path.length() > 0 {
    out.push(indent + "# Upload artifact: " + artifact_name)
    out.push(
      indent +
      "mkdir -p \"$\u007bACTRUN_ARTIFACT_DIR:-.artifacts}/" +
      artifact_name +
      "\"",
    )
    out.push(
      indent +
      "cp -r " +
      shell_quote(path) +
      " \"$\u007bACTRUN_ARTIFACT_DIR:-.artifacts}/" +
      artifact_name +
      "/\"",
    )
  } else {
    out.push(indent + "# upload-artifact: no path specified")
  }
}

///|
fn emit_download_artifact(
  with_values : Map[String, String],
  out : Array[String],
  indent : String,
) -> Unit {
  let name = resolve_expr(get_with(with_values, "name"))
  let path = resolve_expr(get_with(with_values, "path"))
  let dest = if path.length() > 0 { path } else { "." }
  if name.length() > 0 {
    out.push(indent + "# Download artifact: " + name)
    out.push(
      indent +
      "cp -r \"$\u007bACTRUN_ARTIFACT_DIR:-.artifacts}/" +
      name +
      "/.\" " +
      shell_quote(dest),
    )
  } else {
    out.push(indent + "# download-artifact: no name specified")
  }
}

///|
fn emit_cache(
  uses : String,
  with_values : Map[String, String],
  out : Array[String],
  indent : String,
) -> Unit {
  let key = get_with(with_values, "key")
  let path = get_with(with_values, "path")
  out.push(indent + "# " + uses)
  if key.length() > 0 {
    out.push(indent + "# cache key: " + key)
  }
  if path.length() > 0 {
    out.push(indent + "# cache path: " + path)
  }
  out.push(indent + "# (caching is a no-op in shell export)")
}

///|
/// Replace ${{ expr }} with shell variable references
fn resolve_expr(text : String) -> String {
  let prefix = "$\u007b\u007b"
  let suffix = "}}"
  let mut result = text
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
/// Generate " # ← original" comment if value was transformed
fn comment_origin(original : String) -> String {
  if original.contains("$\u007b\u007b") {
    "  # \u2190 " + original.trim(chars=" \t\r\n").to_string()
  } else {
    ""
  }
}

///|
/// Add origin comments to multi-line scripts where lines changed
fn add_origin_comments(original : String, resolved : String) -> String {
  let orig_lines : Array[String] = []
  for v in original.split("\n") {
    orig_lines.push(v.to_string())
  }
  let res_lines : Array[String] = []
  for v in resolved.split("\n") {
    res_lines.push(v.to_string())
  }
  // If same number of lines, compare per-line
  if orig_lines.length() == res_lines.length() {
    let out : Array[String] = []
    for i, res_line in res_lines {
      let orig_line = orig_lines[i]
      if res_line != orig_line && orig_line.contains("$\u007b\u007b") {
        out.push(
          res_line + "  # \u2190 " + orig_line.trim(chars=" \t\r").to_string(),
        )
      } else {
        out.push(res_line)
      }
    }
    out.join("\n")
  } else {
    resolved
  }
}

///|
fn expr_to_shell_var(expr : String) -> String {
  if expr.has_prefix("env.") {
    let var_name = String::unsafe_substring(expr, start=4, end=expr.length())
    return "$" + var_name
  }
  if expr.has_prefix("secrets.") {
    let var_name = String::unsafe_substring(expr, start=8, end=expr.length())
    return "$SECRET_" + to_shell_var(var_name)
  }
  if expr.has_prefix("github.") {
    return resolve_github_context(expr)
  }
  if expr.has_prefix("matrix.") {
    let var_name = String::unsafe_substring(expr, start=7, end=expr.length())
    return "$MATRIX_" + to_shell_var(var_name)
  }
  if expr.has_prefix("inputs.") {
    let var_name = String::unsafe_substring(expr, start=7, end=expr.length())
    return "$INPUT_" + to_shell_var(var_name)
  }
  if expr.has_prefix("runner.") {
    let field = String::unsafe_substring(expr, start=7, end=expr.length())
    return "$RUNNER_" + to_shell_var(field)
  }
  if expr.has_prefix("steps.") {
    return resolve_step_ref(expr)
  }
  if expr.has_prefix("needs.") {
    return resolve_needs_ref(expr)
  }
  if expr.contains("(") {
    return resolve_function_call(expr)
  }
  "$\u007b" + expr + "}"
}

///|
fn resolve_function_call(expr : String) -> String {
  // Parse the expression to get structured function call
  let (parsed, _errors) = parse_expression(expr)
  match parsed {
    FunctionCall(name, args) => {
      let resolved_args : Array[String] = []
      for arg in args {
        resolved_args.push(resolve_expr_node(arg))
      }
      match name {
        "contains" =>
          if resolved_args.length() == 2 {
            "$(gha_contains " +
            shell_quote(resolved_args[0]) +
            " " +
            shell_quote(resolved_args[1]) +
            " && echo true || echo false)"
          } else {
            "# " + expr
          }
        "startsWith" =>
          if resolved_args.length() == 2 {
            "$(gha_startsWith " +
            shell_quote(resolved_args[0]) +
            " " +
            shell_quote(resolved_args[1]) +
            " && echo true || echo false)"
          } else {
            "# " + expr
          }
        "endsWith" =>
          if resolved_args.length() == 2 {
            "$(gha_endsWith " +
            shell_quote(resolved_args[0]) +
            " " +
            shell_quote(resolved_args[1]) +
            " && echo true || echo false)"
          } else {
            "# " + expr
          }
        "format" => {
          let fmt_args = resolved_args.join(" ")
          "$(gha_format " + fmt_args + ")"
        }
        "toJSON" => "$(gha_toJSON)"
        "fromJSON" =>
          if resolved_args.length() == 1 {
            "$(gha_fromJSON " + shell_quote(resolved_args[0]) + ")"
          } else {
            "# " + expr
          }
        "hashFiles" => {
          let paths = resolved_args.join(" ")
          "$(gha_hashFiles " + paths + ")"
        }
        "join" => {
          let join_args = resolved_args.join(" ")
          "$(gha_join " + join_args + ")"
        }
        "success" => "$(gha_success && echo true || echo false)"
        "failure" => "$(gha_failure && echo true || echo false)"
        "always" => "true"
        "cancelled" => "false"
        _ => "# " + expr
      }
    }
    _ =>
      // Not a simple function call, fallback
      "# " + expr
  }
}

///|
/// Convert an AST expression node to a shell string (for function arguments)
fn resolve_expr_node(expr : Expr) -> String {
  match expr {
    Literal(LitString(s)) => s
    Literal(LitNumber(n)) => n
    Literal(LitBool(b)) => if b { "true" } else { "false" }
    Literal(LitNull) => ""
    Ident(name) => expr_to_shell_var(name)
    PropertyAccess(_, _) => {
      let (parsed_expr, _) = parse_expression(expr.to_string())
      ignore(parsed_expr)
      // Reconstruct dot path and resolve
      let path = expr_node_to_dot_path(expr)
      if path.length() > 0 {
        expr_to_shell_var(path)
      } else {
        expr.to_string()
      }
    }
    FunctionCall(_, _) => resolve_function_call(expr.to_string())
    _ => expr.to_string()
  }
}

///|
fn expr_node_to_dot_path(expr : Expr) -> String {
  match expr {
    Ident(name) => name
    PropertyAccess(obj, prop) => {
      let base = expr_node_to_dot_path(obj)
      if base.length() > 0 {
        base + "." + prop
      } else {
        prop
      }
    }
    _ => ""
  }
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
  let rest = String::unsafe_substring(expr, start=6, end=expr.length())
  let parts = split_by_dot(rest)
  if parts.length() >= 3 && parts[1] == "outputs" {
    "$_STEP_" + to_shell_var(parts[0]) + "_" + to_shell_var(parts[2])
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
  let rest = String::unsafe_substring(expr, start=6, end=expr.length())
  let parts = split_by_dot(rest)
  if parts.length() >= 3 && parts[1] == "outputs" {
    "$_NEEDS_" + to_shell_var(parts[0]) + "_OUT_" + to_shell_var(parts[2])
  } else if parts.length() >= 2 && parts[1] == "result" {
    "$_NEEDS_" + to_shell_var(parts[0]) + "_RESULT"
  } else {
    "$\u007bneeds." + rest + "}"
  }
}

///|
fn convert_github_output(
  script : String,
  step_id : String,
  _job_id : String,
) -> String {
  if not(script.contains("GITHUB_OUTPUT")) && not(script.contains("GITHUB_ENV")) {
    return script
  }
  let lines : Array[String] = []
  for line_view in script.split("\n") {
    let line = line_view.to_string()
    let trimmed = line.trim(chars=" \t\r").to_string()
    if trimmed.contains(">>") && trimmed.contains("GITHUB_OUTPUT") {
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
fn extract_output_kv(line : String) -> (String, String)? {
  let echo_idx = find_substr(line, "echo ", 0)
  if echo_idx < 0 {
    return Option::None
  }
  let content_start = echo_idx + 5
  let mut start = content_start
  if start < line.length() && line.unsafe_get(start) == '"' {
    start += 1
  }
  let redir = find_substr(line, ">>", start)
  if redir < 0 {
    return Option::None
  }
  let mut end = redir
  while end > start &&
        (line.unsafe_get(end - 1) == '"' || line.unsafe_get(end - 1) == ' ') {
    end -= 1
  }
  let content = String::unsafe_substring(line, start~, end~)
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
fn translate_if_condition(cond : String) -> String {
  let expr = unwrap_expr_for_codegen(cond)
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
  "true"
}

///|
fn unwrap_expr_for_codegen(text : String) -> String {
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
