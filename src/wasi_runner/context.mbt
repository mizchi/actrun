///|
/// WASI execution context — manages env, inputs, VFS, and result collection.

///|
pub struct WasiContext {
  env : Map[String, String]
  vfs : VirtualFs
  workdir : String
  stdout_buf : Array[String]
  stderr_buf : Array[String]
  exit_code : Int
}

///|
pub fn WasiContext::new(
  env? : Map[String, String] = {},
  inputs? : Map[String, String] = {},
  workdir? : String = "/workspace",
) -> WasiContext {
  let merged_env : Map[String, String] = {}
  for k, v in env {
    merged_env[k] = v
  }
  for k, v in inputs {
    merged_env["INPUT_" + to_upper(k)] = v
  }
  let vfs = VirtualFs::new()
  let output_path = workdir + "/github_output"
  let env_path = workdir + "/github_env"
  vfs.write(output_path, "")
  vfs.write(env_path, "")
  merged_env["GITHUB_OUTPUT"] = output_path
  merged_env["GITHUB_ENV"] = env_path
  merged_env["GITHUB_WORKSPACE"] = workdir
  {
    env: merged_env,
    vfs,
    workdir,
    stdout_buf: [],
    stderr_buf: [],
    exit_code: 0,
  }
}

///|
pub fn WasiContext::get_stdout(self : WasiContext) -> String {
  self.stdout_buf.join("")
}

///|
pub fn WasiContext::get_stderr(self : WasiContext) -> String {
  self.stderr_buf.join("")
}

///|
pub fn WasiContext::get_outputs(self : WasiContext) -> Map[String, String] {
  self.vfs.parse_key_values(self.workdir + "/github_output")
}

///|
pub fn WasiContext::get_env_updates(self : WasiContext) -> Map[String, String] {
  self.vfs.parse_key_values(self.workdir + "/github_env")
}

///|
pub struct WasiRunResult {
  status : String // "success" | "failed"
  exit_code : Int
  stdout : String
  stderr : String
  outputs : Map[String, String]
  env_updates : Map[String, String]
} derive(ToJson, Show)

///|
pub fn WasiContext::collect_result(self : WasiContext) -> WasiRunResult {
  {
    status: if self.exit_code == 0 {
      "success"
    } else {
      "failed"
    },
    exit_code: self.exit_code,
    stdout: self.get_stdout(),
    stderr: self.get_stderr(),
    outputs: self.get_outputs(),
    env_updates: self.get_env_updates(),
  }
}

///|
fn to_upper(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    if ch >= 'a' && ch <= 'z' {
      buf.write_char(Int::unsafe_to_char(ch.to_int() - 32))
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}
