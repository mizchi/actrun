///|
fn normalize_setup_node_registry_url(value : String) -> String {
  let trimmed = value.trim(chars=" \t\r\n").to_string()
  if trimmed.length() == 0 {
    ""
  } else if trimmed.has_suffix("/") {
    trimmed
  } else {
    trimmed + "/"
  }
}

///|
fn normalize_setup_node_version(
  value : String,
  current_version : String,
) -> String {
  let trimmed = value.trim(chars=" \t\r\n").to_string()
  if trimmed.length() == 0 {
    return current_version
  }
  let bare = if trimmed.has_prefix("v") {
    exec_text_slice(trimmed, 1, trimmed.length())
  } else {
    trimmed
  }
  let first = bare.split(".").next().unwrap_or("").to_string()
  let mut digits = ""
  for c in first {
    if c >= '0' && c <= '9' {
      digits += c.to_string()
    } else {
      break
    }
  }
  if digits.length() == 0 {
    return current_version
  }
  let parts : Array[String] = []
  for part_view in bare.split(".") {
    let part = part_view.to_string()
    if part.length() == 0 {
      continue
    }
    if part == "x" || part == "*" {
      break
    }
    let mut numeric = ""
    for c in part {
      if c >= '0' && c <= '9' {
        numeric += c.to_string()
      } else {
        break
      }
    }
    if numeric.length() == 0 {
      break
    }
    parts.push(numeric)
  }
  let major = parts.get(0).unwrap_or(digits)
  let minor = parts.get(1).unwrap_or("0")
  let patch = parts.get(2).unwrap_or("0")
  "v" + major + "." + minor + "." + patch
}

///|
fn read_node_version_from_file(file_path : String) -> String {
  let content = try @xfs.read_file_to_string(file_path) catch {
    _ => return ""
  } noraise {
    value => value
  }
  let trimmed = content.trim(chars=" \t\r\n").to_string()
  if trimmed.length() == 0 {
    return ""
  }
  // .nvmrc / .node-version: single line with version
  if file_path.has_suffix(".nvmrc") ||
    file_path.has_suffix(".node-version") ||
    file_path.has_suffix(".tool-versions") {
    // .tool-versions: find "nodejs <version>" line
    if file_path.has_suffix(".tool-versions") {
      for line_view in trimmed.split("\n") {
        let line = line_view.trim(chars=" \t\r").to_string()
        if line.has_prefix("nodejs ") || line.has_prefix("nodejs\t") {
          return exec_text_slice(line, 7, line.length())
            .trim(chars=" \t\r\n")
            .to_string()
        }
      }
      return ""
    }
    // First non-empty line
    for line_view in trimmed.split("\n") {
      let line = line_view.trim(chars=" \t\r").to_string()
      if line.length() > 0 && not(line.has_prefix("#")) {
        return line
      }
    }
    return ""
  }
  // package.json: extract engines.node
  if file_path.has_suffix("package.json") {
    let parsed = try @json.parse(trimmed) catch {
      _ => return ""
    } noraise {
      value => value
    }
    match parsed {
      Object(fields) =>
        match fields.get("engines") {
          Some(Object(engines)) =>
            match engines.get("node") {
              Some(String(version)) => return version
              _ => return ""
            }
          _ => return ""
        }
      _ => return ""
    }
  }
  // Default: treat entire content as version
  trimmed
}

///|
fn setup_node_store_root(workspace_root : String) -> String {
  ignore(ensure_exec_dir_recursive("_build/actrun/setup_node"))
  let workspace_key = sanitize_task_id(
    absolute_exec_path(resolve_task_cwd(workspace_root, "")),
  )
  let root = absolute_exec_path("_build/actrun/setup_node/" + workspace_key)
  ignore(ensure_exec_dir_recursive(root))
  root
}

///|
async fn exec_make_executable(path : String) -> Bool {
  let (code, _, _) = run_command("chmod", ["+x", path], cwd=".")
  code == 0
}

///|
async fn write_setup_node_shim(
  workspace_root : String,
  task_id : String,
  node_bin : String,
  node_version : String,
) -> String? {
  let shim_root = setup_node_store_root(workspace_root) +
    "/" +
    sanitize_task_id(task_id)
  let shim_dir = shim_root + "/bin"
  if not(ensure_exec_dir_recursive(shim_dir)) {
    return None
  }
  let shim_path = shim_dir + "/node"
  let d = "$"
  let script = "#!/bin/sh\n" +
    "set -eu\n" +
    "if [ \"" +
    d +
    "{1:-}\" = \"--version\" ] || [ \"" +
    d +
    "{1:-}\" = \"-v\" ]; then\n" +
    "  printf '%s\\n' '" +
    node_version +
    "'\n" +
    "  exit 0\n" +
    "fi\n" +
    "exec '" +
    node_bin.replace_all(old="'", new="'\"'\"'") +
    "' \"" +
    d +
    "@\"\n"
  if not(write_exec_text(shim_path, script)) {
    return None
  }
  if not(exec_make_executable(shim_path)) {
    return None
  }
  Some(shim_dir)
}

///|
fn write_setup_node_npmrc(
  path : String,
  registry_url : String,
  always_auth? : Bool = false,
  scope? : String = "",
) -> Bool {
  let stripped = if registry_url.has_prefix("https://") {
    "//" + exec_text_slice(registry_url, 8, registry_url.length())
  } else if registry_url.has_prefix("http://") {
    "//" + exec_text_slice(registry_url, 7, registry_url.length())
  } else {
    registry_url
  }
  let mut content = stripped + ":_authToken=${NODE_AUTH_TOKEN}\n"
  if scope.length() > 0 {
    let scoped = if scope.has_prefix("@") { scope } else { "@" + scope }
    content = content + scoped + ":registry=" + registry_url + "\n"
  }
  content = content + "registry=" + registry_url + "\n"
  if always_auth {
    content = content + "always-auth=true\n"
  }
  write_exec_text(path, content)
}

///|
fn setup_node_cache_relative_path(cache_name : String) -> String {
  ".setup-node/" + cache_name + "-cache"
}

///|
fn setup_node_default_dependency_paths(cache_name : String) -> Array[String] {
  if cache_name == "npm" {
    ["package-lock.json", "npm-shrinkwrap.json"]
  } else if cache_name == "yarn" {
    ["yarn.lock"]
  } else if cache_name == "pnpm" {
    ["pnpm-lock.yaml"]
  } else {
    []
  }
}

///|
priv enum SetupNodeDependencyResolution {
  Ok(Array[String])
  Err(String)
}

///|
fn resolve_setup_node_dependency_paths(
  workspace_root : String,
  cache_name : String,
  dependency_input : String,
) -> SetupNodeDependencyResolution {
  let candidates = if dependency_input.trim(chars=" \t\r\n").length() > 0 {
    split_nonempty_lines(dependency_input)
  } else {
    setup_node_default_dependency_paths(cache_name)
  }
  if candidates.length() == 0 {
    return Err(
      "setup-node cache '\{cache_name}' requires cache-dependency-path or a default lockfile",
    )
  }
  let resolved : Array[String] = []
  let explicit = dependency_input.trim(chars=" \t\r\n").length() > 0
  for candidate in candidates {
    let resolved_path = resolve_task_cwd(workspace_root, candidate)
    if explicit && not(@xfs.path_exists(resolved_path)) {
      return Err(
        "setup-node cache dependency path '\{candidate}' does not exist",
      )
    }
    if not(@xfs.path_exists(resolved_path)) {
      continue
    }
    guard workspace_relative_store_path(workspace_root, resolved_path)
      is Some(relative_path) else {
      return Err(
        "setup-node cache dependency path '\{candidate}' must stay within the workspace",
      )
    }
    resolved.push(relative_path)
  }
  if resolved.length() == 0 {
    Err("setup-node cache '\{cache_name}' found no dependency files")
  } else {
    Ok(resolved)
  }
}

///|
fn setup_node_cache_key_text(
  workspace_root : String,
  cache_name : String,
  dependency_paths : Array[String],
) -> String? {
  let parts : Array[String] = []
  parts.push("cache=" + cache_name)
  for relative_path in dependency_paths {
    let resolved_path = resolve_task_cwd(workspace_root, relative_path)
    guard read_exec_text(resolved_path) is Some(content) else { return None }
    parts.push("--")
    parts.push(relative_path)
    parts.push(content)
  }
  Some(parts.join("\n"))
}

///|
fn stable_setup_node_hash(text : String) -> String {
  let mut hash = 7
  let mut idx = 0
  while idx < text.length() {
    hash = (hash * 131 + text.unsafe_get(idx).to_int()) % 2147483647
    idx += 1
  }
  hash.to_string()
}

///|
fn compute_setup_node_cache_key(
  workspace_root : String,
  cache_name : String,
  dependency_paths : Array[String],
) -> String? {
  guard setup_node_cache_key_text(workspace_root, cache_name, dependency_paths)
    is Some(key_text) else {
    return None
  }
  Some("setup-node-" + cache_name + "-" + stable_setup_node_hash(key_text))
}

///|
async fn execute_setup_node_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
) -> TaskExecutionResult {
  let cache_input = resolved_plan_env
    .get("INPUT_CACHE")
    .unwrap_or(
      resolved_plan_env.get("INPUT_PACKAGE_MANAGER_CACHE").unwrap_or(""),
    )
  let normalized_cache_input = cache_input.trim(chars=" \t\r\n").to_string()
  let requested_node_file = resolved_plan_env
    .get("INPUT_NODE_VERSION_FILE")
    .unwrap_or("")
  let node_version_from_file = if requested_node_file
    .trim(chars=" \t\r\n")
    .length() >
    0 {
    let file_path = resolve_task_cwd(
      workspace_root,
      requested_node_file.trim(chars=" \t\r\n").to_string(),
    )
    read_node_version_from_file(file_path)
  } else {
    ""
  }
  let configured_node_fallback = resolved_plan_env
    .get("ACTRUN_NODE_BIN")
    .unwrap_or(@xsys.get_env_var("ACTRUN_NODE_BIN").unwrap_or("node"))
  let fallback_node_bin = resolve_exec_bin_for_workspace(
    configured_node_fallback, workspace_root,
  )
  let configured_setup_node_bin = resolved_plan_env
    .get("ACTRUN_SETUP_NODE_BIN")
    .unwrap_or(
      @xsys.get_env_var("ACTRUN_SETUP_NODE_BIN").unwrap_or(fallback_node_bin),
    )
  let node_bin = resolve_exec_bin_for_workspace(
    configured_setup_node_bin, workspace_root,
  )
  let (version_code, version_stdout, version_stderr) = run_command(
    node_bin,
    ["--version"],
    cwd=resolve_task_cwd(workspace_root, ""),
  )
  if version_code != 0 {
    return failure_execution_result(
      plan,
      workspace_root,
      exec_command_message(
        version_stdout, version_stderr, "failed to inspect node version",
      ),
    )
  }
  let actual_version = version_stdout.trim(chars=" \t\r\n").to_string()
  let explicit_version = resolved_plan_env
    .get("INPUT_NODE_VERSION")
    .unwrap_or("")
  let version_input = if explicit_version.trim(chars=" \t\r\n").length() > 0 {
    explicit_version
  } else {
    node_version_from_file
  }
  let node_version = normalize_setup_node_version(version_input, actual_version)
  guard write_setup_node_shim(workspace_root, plan.id, node_bin, node_version)
    is Some(shim_dir) else {
    return failure_execution_result(
      plan, workspace_root, "failed to prepare setup-node shim",
    )
  }
  let architecture_input = resolved_plan_env
    .get("INPUT_ARCHITECTURE")
    .unwrap_or("")
    .trim(chars=" \t\r\n")
    .to_string()
  let env_updates : Map[String, String] = {}
  let output_values : Map[String, String] = { "node-version": node_version }
  if architecture_input.length() > 0 {
    output_values["node-architecture"] = architecture_input
  }
  let state_updates : Map[String, String] = {}
  if normalized_cache_input.length() > 0 {
    if normalized_cache_input != "npm" {
      return failure_execution_result(
        plan,
        workspace_root,
        "setup-node cache '\{normalized_cache_input}' is not supported yet",
      )
    }
    let dependency_input = resolved_plan_env
      .get("INPUT_CACHE_DEPENDENCY_PATH")
      .unwrap_or("")
    let dependency_paths = match
      resolve_setup_node_dependency_paths(
        workspace_root, normalized_cache_input, dependency_input,
      ) {
      Ok(paths) => paths
      Err(message) =>
        return failure_execution_result(plan, workspace_root, message)
    }
    guard compute_setup_node_cache_key(
        workspace_root, normalized_cache_input, dependency_paths,
      )
      is Some(cache_key) else {
      return failure_execution_result(
        plan, workspace_root, "failed to compute setup-node cache key",
      )
    }
    let cache_relative_path = setup_node_cache_relative_path(
      normalized_cache_input,
    )
    let cache_abs_path = resolve_task_cwd(workspace_root, cache_relative_path)
    if not(ensure_exec_dir_recursive(cache_abs_path)) {
      return failure_execution_result(
        plan, workspace_root, "failed to prepare setup-node cache directory",
      )
    }
    let cache_result = execute_restore_cache_native(plan, workspace_root, {
      "INPUT_KEY": cache_key,
      "INPUT_PATH": cache_relative_path,
    })
    if cache_result.report.status != "success" {
      return cache_result
    }
    let cache_hit = cache_result.output_values
      .get("cache-hit")
      .unwrap_or("false")
    env_updates["NPM_CONFIG_CACHE"] = cache_abs_path
    env_updates["npm_config_cache"] = cache_abs_path
    output_values["cache-hit"] = cache_hit
    state_updates["SETUP_NODE_CACHE_NAME"] = normalized_cache_input
    state_updates["SETUP_NODE_CACHE_KEY"] = cache_key
    state_updates["SETUP_NODE_CACHE_PATH"] = cache_relative_path
    state_updates["SETUP_NODE_CACHE_HIT"] = cache_hit
  }
  let registry_url = normalize_setup_node_registry_url(
    resolved_plan_env.get("INPUT_REGISTRY_URL").unwrap_or(""),
  )
  if registry_url.length() > 0 {
    let always_auth = parse_bool_false_default(
      resolved_plan_env.get("INPUT_ALWAYS_AUTH").unwrap_or("false"),
    )
    let scope = resolved_plan_env
      .get("INPUT_SCOPE")
      .unwrap_or("")
      .trim(chars=" \t\r\n")
      .to_string()
    let npmrc_path = prepare_runner_temp_dir(plan.job_id, workspace_root) +
      "/.npmrc"
    if not(
        write_setup_node_npmrc(npmrc_path, registry_url, always_auth~, scope~),
      ) {
      return failure_execution_result(
        plan, workspace_root, "failed to write setup-node npm auth config",
      )
    }
    let node_auth_token = resolved_plan_env
      .get("NODE_AUTH_TOKEN")
      .unwrap_or(
        @xsys.get_env_var("NODE_AUTH_TOKEN").unwrap_or(
          "XXXXX-XXXXX-XXXXX-XXXXX",
        ),
      )
    env_updates["NPM_CONFIG_USERCONFIG"] = npmrc_path
    env_updates["NODE_AUTH_TOKEN"] = node_auth_token
  }
  {
    report: task_report_success(plan, workspace_root),
    env_updates,
    path_entries: [shim_dir],
    output_values,
    state_updates,
  }
}

///|
fn execute_setup_node_cache_post_native(
  plan : TaskPlan,
  workspace_root : String,
  resolved_plan_env : Map[String, String],
  state : JobRuntimeState,
) -> TaskRunReport {
  let saved_state = action_scope_state(state, plan.action_scope)
  if saved_state.length() == 0 {
    return task_report_success(plan, workspace_root)
  }
  if saved_state.get("SETUP_NODE_CACHE_HIT").unwrap_or("") == "true" {
    return task_report_success(plan, workspace_root)
  }
  let cache_name = saved_state
    .get("SETUP_NODE_CACHE_NAME")
    .unwrap_or(resolved_plan_env.get("INPUT_CACHE").unwrap_or(""))
  let path_input = saved_state
    .get("SETUP_NODE_CACHE_PATH")
    .unwrap_or(
      setup_node_cache_relative_path(
        cache_name.trim(chars=" \t\r\n").to_string(),
      ),
    )
  let key = saved_state.get("SETUP_NODE_CACHE_KEY").unwrap_or("")
  if key.length() == 0 {
    return task_report_success(plan, workspace_root)
  }
  let resolved_path = resolve_task_cwd(workspace_root, path_input)
  if not(@xfs.path_exists(resolved_path)) {
    return task_report_success(plan, workspace_root)
  }
  return execute_save_cache_native(
    plan,
    workspace_root,
    merge_runner_env(resolved_plan_env, {
      "INPUT_KEY": key,
      "INPUT_PATH": path_input,
    }),
  )
}
