///|
/// Sandboxed step executor — runs workflow steps entirely in-memory via VFS.

///|
pub struct StepResult {
  status : String // "success" | "failed" | "skipped"
  exit_code : Int
  stdout : String
  stderr : String
  outputs : Map[String, String]
  env_updates : Map[String, String]
} derive(ToJson, Show)

///|
pub fn execute_shell_step(
  script : String,
  env~ : Map[String, String] = {},
  vfs~ : @wr.VirtualFs = @wr.VirtualFs::new(),
  workdir~ : String = "/workspace",
) -> StepResult {
  let output_path = workdir + "/github_output"
  let env_path = workdir + "/github_env"
  if not(vfs.exists(output_path)) {
    vfs.write(output_path, "")
  }
  if not(vfs.exists(env_path)) {
    vfs.write(env_path, "")
  }
  let merged_env : Map[String, String] = {}
  for k, v in env {
    merged_env[k] = v
  }
  merged_env["GITHUB_OUTPUT"] = output_path
  merged_env["GITHUB_ENV"] = env_path
  merged_env["GITHUB_WORKSPACE"] = workdir
  let shell_env = new_vfs_shell_env(vfs, merged_env, cwd=workdir)
  let exit_code = @actrun.shell_exec(shell_env, script)
  let stdout = @actrun.shell_stdout(shell_env)
  let stderr = @actrun.shell_stderr(shell_env)
  let outputs = vfs.parse_key_values(output_path)
  let env_updates = vfs.parse_key_values(env_path)
  {
    status: if exit_code == 0 { "success" } else { "failed" },
    exit_code,
    stdout,
    stderr,
    outputs,
    env_updates,
  }
}

///|
pub fn step_result_to_json(result : StepResult) -> String {
  result.to_json().stringify()
}
