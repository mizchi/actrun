///|
/// WASM sandbox: run WASI modules in an isolated tempdir.
///
/// Instead of granting access to the real workspace via --dir,
/// we materialize only the necessary files into a tempdir,
/// run the WASM module there, and read results back.
/// The module never sees the host filesystem.

///|
pub struct WasmSandbox {
  tempdir : String
  env_path : String
  output_path : String
  path_path : String
  summary_path : String
  state_path : String
}

///|
fn WasmSandbox::to_file_commands(self : WasmSandbox) -> StepFileCommands {
  {
    env_path: self.env_path,
    path_path: self.path_path,
    output_path: self.output_path,
    summary_path: self.summary_path,
    state_path: self.state_path,
    script_path: "",
  }
}

///|
pub struct WasmSandboxResult {
  env_updates : Map[String, String]
  path_entries : Array[String]
  output_values : Map[String, String]
  state_updates : Map[String, String]
  summary : String
}

///|
#cfg(target="native")
pub fn create_wasm_sandbox(step_id : String) -> WasmSandbox? {
  let safe_id = sanitize_path_component(step_id)
  let pid = @xsys.get_env_var("PPID").unwrap_or("0")
  let tempdir = "/tmp/actrun-wasm-" + pid + "-" + safe_id
  try @xfs.create_dir(tempdir) catch {
    _ => return None
  } noraise {
    _ => ()
  }
  // Create file command files inside the sandbox
  let env_path = tempdir + "/github_env"
  let output_path = tempdir + "/github_output"
  let path_path = tempdir + "/github_path"
  let summary_path = tempdir + "/step_summary"
  let state_path = tempdir + "/github_state"
  try {
    @xfs.write_string_to_file(env_path, "")
    @xfs.write_string_to_file(output_path, "")
    @xfs.write_string_to_file(path_path, "")
    @xfs.write_string_to_file(summary_path, "")
    @xfs.write_string_to_file(state_path, "")
  } catch {
    _ => return None
  } noraise {
    _ => ()
  }
  Some({ tempdir, env_path, output_path, path_path, summary_path, state_path })
}

///|
fn sanitize_path_component(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' {
      buf.write_char(ch)
    } else {
      buf.write_char('_')
    }
  }
  buf.to_string()
}

///|
/// Build wasmtime arguments for sandboxed execution.
/// Only the tempdir is mounted — no access to host filesystem.
#cfg(target="native")
pub fn build_sandboxed_wasmtime_args(
  sandbox : WasmSandbox,
  env : Map[String, String],
  module_path : String,
) -> Array[String] {
  let args : Array[String] = ["run"]
  for key, value in env {
    let actual = match key {
      "GITHUB_ENV" => sandbox.env_path
      "GITHUB_OUTPUT" => sandbox.output_path
      "GITHUB_PATH" => sandbox.path_path
      "GITHUB_STEP_SUMMARY" => sandbox.summary_path
      "GITHUB_STATE" => sandbox.state_path
      "GITHUB_WORKSPACE" => sandbox.tempdir
      _ => value
    }
    args.push("--env")
    args.push(key + "=" + actual)
  }
  args.push("--dir")
  args.push(sandbox.tempdir)
  args.push(module_path)
  args
}

///|
/// Resolve the WASM runner command.
/// - "wasmtime" (default): use wasmtime directly with CLI args
/// - "deno": use deno with wasi-runner.mjs shim
/// - "node"/"bun": use node/bun with wasi-runner.mjs shim
/// - anything else: use as-is (custom runner with wasmtime-compatible CLI)
#cfg(target="native")
pub fn resolve_wasm_runner_command(
  wasm_bin : String,
  wasm_args : Array[String],
  workspace_root : String,
) -> (String, Array[String]) {
  let bin_name = basename_of(wasm_bin)
  if bin_name == "deno" || bin_name == "node" || bin_name == "bun" {
    let shim_path = find_wasi_runner_shim(workspace_root)
    let args : Array[String] = []
    if bin_name == "deno" {
      args.push("run")
      args.push("--allow-all")
    }
    args.push(shim_path)
    for arg in wasm_args {
      args.push(arg)
    }
    (wasm_bin, args)
  } else {
    (wasm_bin, wasm_args)
  }
}

///|
fn basename_of(path : String) -> String {
  let slash = '/'.to_int().to_uint16()
  let mut last_slash = -1
  let mut idx = 0
  while idx < path.length() {
    if path.unsafe_get(idx) == slash {
      last_slash = idx
    }
    idx += 1
  }
  if last_slash >= 0 {
    exec_text_slice(path, last_slash + 1, path.length())
  } else {
    path
  }
}

///|
fn find_wasi_runner_shim(workspace_root : String) -> String {
  // Look for wasi-runner.mjs relative to cwd first, then workspace
  let candidates = [
    "scripts/wasi-runner.mjs", "node_modules/@mizchi/actrun/scripts/wasi-runner.mjs",
  ]
  if workspace_root.length() > 0 {
    candidates.push(workspace_root + "/scripts/wasi-runner.mjs")
    candidates.push(
      workspace_root + "/node_modules/@mizchi/actrun/scripts/wasi-runner.mjs",
    )
  }
  for candidate in candidates {
    if @xfs.path_exists(candidate) {
      return absolute_exec_path(candidate)
    }
  }
  // Fallback: return absolute path to cwd-relative location
  absolute_exec_path("scripts/wasi-runner.mjs")
}

///|
/// Read results from the sandbox after WASM execution.
#cfg(target="native")
pub fn read_sandbox_results(sandbox : WasmSandbox) -> WasmSandboxResult {
  {
    env_updates: parse_env_updates(sandbox.env_path),
    path_entries: parse_path_updates(sandbox.path_path),
    output_values: parse_output_values(sandbox.output_path),
    state_updates: parse_state_values(sandbox.state_path),
    summary: parse_summary_text(sandbox.summary_path),
  }
}

///|
/// Clean up the sandbox tempdir after use.
#cfg(target="native")
pub fn cleanup_wasm_sandbox(sandbox : WasmSandbox) -> Unit {
  remove_file(sandbox.env_path)
  remove_file(sandbox.output_path)
  remove_file(sandbox.path_path)
  remove_file(sandbox.summary_path)
  remove_file(sandbox.state_path)
  try @xfs.remove_dir(sandbox.tempdir) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}
