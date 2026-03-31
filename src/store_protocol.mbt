///|
/// Store protocol types for WASM worker CI.
///
/// Defines the HTTP API contract between WASM step modules and the store.
/// In file mode (default), actrun uses GITHUB_OUTPUT/GITHUB_ENV files.
/// In HTTP mode (worker environments), the same data flows over HTTP.

///|
pub enum StoreMode {
  FileStore
  HttpStore(String) // base URL
}

///|
pub fn store_mode_from_env(env : Map[String, String]) -> StoreMode {
  match env.get("ACTRUN_STORE_URL") {
    Some(url) if url.length() > 0 => HttpStore(url)
    _ => FileStore
  }
}

///|
/// Step output: maps to GITHUB_OUTPUT (key=value per line)
/// HTTP: POST /steps/{step_id}/outputs  body: {"key": "...", "value": "..."}
pub struct StoreOutputEntry {
  key : String
  value : String
} derive(ToJson, FromJson, Show)

///|
/// Env update: maps to GITHUB_ENV (key=value or heredoc)
/// HTTP: POST /runs/{run_id}/env  body: {"key": "...", "value": "..."}
pub struct StoreEnvEntry {
  key : String
  value : String
} derive(ToJson, FromJson, Show)

///|
/// Path update: maps to GITHUB_PATH (one path per line)
/// HTTP: POST /runs/{run_id}/path  body: {"path": "..."}
pub struct StorePathEntry {
  path : String
} derive(ToJson, FromJson, Show)

///|
/// Step summary: maps to GITHUB_STEP_SUMMARY (markdown text)
/// HTTP: POST /steps/{step_id}/summary  body: {"content": "..."}
pub struct StoreSummaryEntry {
  content : String
} derive(ToJson, FromJson, Show)

///|
/// Collected results for a step execution.
/// In file mode: parsed from GITHUB_OUTPUT/GITHUB_ENV files.
/// In HTTP mode: GET /steps/{step_id}/result
pub struct StoreStepResult {
  outputs : Map[String, String]
  env_updates : Map[String, String]
  path_entries : Array[String]
  summary : String
} derive(ToJson, FromJson, Show)

///|
pub fn empty_step_result() -> StoreStepResult {
  { outputs: {}, env_updates: {}, path_entries: [], summary: "" }
}

///|
/// HTTP API route definitions.
/// These are path templates — the dispatcher fills in {run_id} and {step_id}.
pub fn store_outputs_path(run_id : String, step_id : String) -> String {
  "/runs/" + run_id + "/steps/" + step_id + "/outputs"
}

///|
pub fn store_env_path(run_id : String) -> String {
  "/runs/" + run_id + "/env"
}

///|
pub fn store_path_path(run_id : String) -> String {
  "/runs/" + run_id + "/path"
}

///|
pub fn store_summary_path(run_id : String, step_id : String) -> String {
  "/runs/" + run_id + "/steps/" + step_id + "/summary"
}

///|
pub fn store_step_result_path(run_id : String, step_id : String) -> String {
  "/runs/" + run_id + "/steps/" + step_id + "/result"
}

///|
/// WASM module registry route.
/// GET /modules/{name}/{version}/main.wasm → binary
pub fn registry_module_path(name : String, version : String) -> String {
  "/modules/" + name + "/" + version + "/main.wasm"
}
