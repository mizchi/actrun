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
pub struct WasmSandboxResult {
  code : Int
  stdout : String
  stderr : String
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
  let tempdir = "/tmp/actrun-wasm-" + safe_id
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
  // Override file command paths to point inside the sandbox
  let sandboxed_env : Map[String, String] = {}
  for key, value in env {
    match key {
      "GITHUB_ENV" => sandboxed_env[key] = sandbox.env_path
      "GITHUB_OUTPUT" => sandboxed_env[key] = sandbox.output_path
      "GITHUB_PATH" => sandboxed_env[key] = sandbox.path_path
      "GITHUB_STEP_SUMMARY" => sandboxed_env[key] = sandbox.summary_path
      "GITHUB_STATE" => sandboxed_env[key] = sandbox.state_path
      // Strip workspace path — module runs in sandbox only
      "GITHUB_WORKSPACE" => sandboxed_env[key] = sandbox.tempdir
      _ => sandboxed_env[key] = value
    }
  }
  for key, value in sandboxed_env {
    args.push("--env")
    args.push(key + "=" + value)
  }
  // Only mount the sandbox tempdir — nothing else
  args.push("--dir")
  args.push(sandbox.tempdir)
  args.push(module_path)
  args
}

///|
/// Read results from the sandbox after WASM execution.
#cfg(target="native")
pub fn read_sandbox_results(
  sandbox : WasmSandbox,
  code : Int,
  stdout : String,
  stderr : String,
) -> WasmSandboxResult {
  let env_updates = parse_env_updates(sandbox.env_path)
  let path_entries = parse_path_updates(sandbox.path_path)
  let output_values = parse_output_values(sandbox.output_path)
  let state_updates = parse_state_values(sandbox.state_path)
  let summary = parse_summary_text(sandbox.summary_path)
  {
    code,
    stdout,
    stderr,
    env_updates,
    path_entries,
    output_values,
    state_updates,
    summary,
  }
}

///|
/// Clean up the sandbox tempdir after use.
#cfg(target="native")
pub async fn cleanup_wasm_sandbox(sandbox : WasmSandbox) -> Unit {
  let _ = run_command("rm", ["-rf", sandbox.tempdir])
}
