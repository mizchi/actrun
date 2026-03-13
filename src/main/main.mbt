///|
struct CliOptions {
  workflow_path : String
  repo_root : String?
  workspace_root : String?
  run_root : String?
  artifact_root : String?
  cache_root : String?
  github_action_cache_root : String?
  registry_root : String?
  wasm_action_root : String?
  workspace_mode : String
  event_path : String?
  repository : String
  ref_name : String
  before_sha : String
  after_sha : String
  changed_paths : Array[String]
}

///|
struct CliParseResult {
  options : CliOptions?
  errors : Array[String]
}

///|
struct RunReadOptions {
  action : String
  run_id : String
  run_root : String?
  task_id : String?
  artifact_root : String?
  download_dir : String
  json_output : Bool
}

///|
struct RunReadParseResult {
  options : RunReadOptions?
  errors : Array[String]
}

///|
struct ArtifactReadOptions {
  action : String
  run_id : String
  run_root : String?
  artifact_root : String?
  artifact_name : String
  download_dir : String
  json_output : Bool
}

///|
struct ArtifactReadParseResult {
  options : ArtifactReadOptions?
  errors : Array[String]
}

///|
struct CacheReadOptions {
  action : String
  cache_root : String?
  json_output : Bool
}

///|
struct CacheReadParseResult {
  options : CacheReadOptions?
  errors : Array[String]
}

///|
struct RunRecord {
  run_id : String
  workflow_name : String
  workflow_path : String
  workspace_root : String
  workspace_mode : String
  started_at_ms : UInt64
  finished_at_ms : UInt64
  state : String
  ok : Bool
  repository : String
  ref_name : String
  before_sha : String
  after_sha : String
  changed_paths : Array[String]
}

///|
struct RunTaskFiles {
  stdout_path : String
  stderr_path : String
  summary_path : String?
}

///|
struct RunJobRecord {
  id : String
  status : String
  needs : Array[String]
  task_ids : Array[String]
}

///|
struct RunArtifactRecord {
  name : String
  files : Array[String]
}

///|
struct RunCacheRecord {
  key : String
  sequence : Int?
  files : Array[String]
}

///|
struct CacheListRecord {
  workspace_key : String
  key : String
  sequence : Int?
  files : Array[String]
}

///|
fn usage_text() -> String {
  "Usage: action_runner <workflow.yml> [--repo <repo_root>] [--workspace <workspace_root>] [--run-root <run_root>] [--artifact-root <artifact_root>] [--cache-root <cache_root>] [--github-action-cache-root <github_action_cache_root>] [--registry-root <registry_root>] [--wasm-action-root <wasm_action_root>] [--workspace-mode <worktree|tmp|docker>] [--event <push-event.json>] [--repository <owner/repo>] [--ref <ref_name>] [--before <sha>] [--after <sha>] [--changed <path>]...\n       action_runner run list [--run-root <run_root>] [--json]\n       action_runner run view <run-id> [--run-root <run_root>] [--json]\n       action_runner run watch <run-id> [--run-root <run_root>] [--json]\n       action_runner run logs <run-id> [--run-root <run_root>] [--task <task-id>]\n       action_runner run download <run-id> [--dir <dest_dir>] [--run-root <run_root>] [--artifact-root <artifact_root>]\n       action_runner artifact list <run-id> [--run-root <run_root>] [--json]\n       action_runner artifact download <run-id> --name <artifact-name> [--dir <dest_dir>] [--run-root <run_root>] [--artifact-root <artifact_root>]\n       action_runner cache list [--cache-root <cache_root>] [--json]"
}

///|
fn parent_dir(path : String) -> String {
  let parts : Array[String] = []
  for part in path.split("/") {
    parts.push(part.to_string())
  }
  if parts.length() <= 1 {
    return "."
  }
  let dirs : Array[String] = []
  for i in 0..<(parts.length() - 1) {
    dirs.push(parts[i])
  }
  let joined = dirs.join("/")
  if joined.length() > 0 {
    joined
  } else if path.has_prefix("/") {
    "/"
  } else {
    "."
  }
}

///|
fn join_path(base : String, child : String) -> String {
  if child.has_prefix("/") {
    return child
  }
  if base == "." || base.length() == 0 {
    return child
  }
  if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
fn default_workspace_root() -> String {
  "_build/action_runner/workspace"
}

///|
fn default_run_root() -> String {
  "_build/action_runner/runs"
}

///|
fn default_workspace_mode(repo_root : String?) -> String {
  if repo_root is Some(_) {
    "tmp"
  } else {
    "worktree"
  }
}

///|
fn valid_workspace_mode(mode : String) -> Bool {
  mode == "worktree" || mode == "tmp" || mode == "docker"
}

///|
fn resolved_workspace_mode(options : CliOptions) -> String {
  if options.workspace_mode.length() > 0 {
    options.workspace_mode
  } else {
    default_workspace_mode(options.repo_root)
  }
}

///|
fn apply_cli_root_overrides(options : CliOptions) -> Unit {
  match options.artifact_root {
    Some(path) => @xsys.set_env_var("ACTION_RUNNER_ARTIFACT_ROOT", path)
    None => ()
  }
  match options.cache_root {
    Some(path) => @xsys.set_env_var("ACTION_RUNNER_CACHE_ROOT", path)
    None => ()
  }
  match options.github_action_cache_root {
    Some(path) =>
      @xsys.set_env_var("ACTION_RUNNER_GITHUB_ACTION_CACHE_ROOT", path)
    None => ()
  }
  match options.registry_root {
    Some(path) => @xsys.set_env_var("ACTION_RUNNER_ACTION_REGISTRY_ROOT", path)
    None => ()
  }
  match options.wasm_action_root {
    Some(path) => @xsys.set_env_var("ACTION_RUNNER_WASM_ACTION_ROOT", path)
    None => ()
  }
}

///|
fn local_workspace_root(workflow_path : String) -> String {
  let marker = "/.github/workflows/"
  match workflow_path.find(marker) {
    Some(idx) =>
      if idx == 0 {
        "/"
      } else {
        String::unsafe_substring(workflow_path, start=0, end=idx)
      }
    None =>
      if workflow_path.has_prefix(".github/workflows/") {
        "."
      } else {
        parent_dir(workflow_path)
      }
  }
}

///|
fn trim_git_suffix(text : String) -> String {
  if text.has_suffix(".git") && text.length() > 4 {
    String::unsafe_substring(text, start=0, end=text.length() - 4)
  } else {
    text
  }
}

///|
fn origin_remote_url_from_git_config(config_text : String) -> String? {
  let mut in_origin = false
  for line_view in config_text.split("\n") {
    let line = line_view.to_string().trim(chars=" \t\r").to_string()
    if line.length() == 0 {
      continue
    }
    if line.has_prefix("[") && line.has_suffix("]") {
      in_origin = line == "[remote \"origin\"]"
      continue
    }
    if not(in_origin) {
      continue
    }
    match line.find("=") {
      Some(idx) => {
        let key = String::unsafe_substring(line, start=0, end=idx)
          .trim(chars=" \t")
          .to_string()
        if key == "url" {
          let value = String::unsafe_substring(
              line,
              start=idx + 1,
              end=line.length(),
            )
            .trim(chars=" \t")
            .to_string()
          if value.length() > 0 {
            return Some(value)
          }
        }
      }
      None => ()
    }
  }
  None
}

///|
fn github_repository_from_remote_url(remote_url : String) -> String {
  let trimmed = trim_git_suffix(remote_url.trim(chars=" \t\r\n/").to_string())
  if trimmed.length() == 0 {
    return ""
  }
  let path = match trimmed.find("://") {
    Some(idx) => {
      let rest = String::unsafe_substring(
        trimmed,
        start=idx + 3,
        end=trimmed.length(),
      )
      match rest.find("/") {
        Some(slash_idx) =>
          String::unsafe_substring(rest, start=slash_idx + 1, end=rest.length())
        None => ""
      }
    }
    None =>
      match trimmed.find(":") {
        Some(idx) =>
          String::unsafe_substring(trimmed, start=idx + 1, end=trimmed.length())
        None =>
          match trimmed.find("/") {
            Some(idx) =>
              String::unsafe_substring(
                trimmed,
                start=idx + 1,
                end=trimmed.length(),
              )
            None => ""
          }
      }
  }
  let segments : Array[String] = []
  for part_view in path.trim(chars="/").split("/") {
    let part = part_view.to_string().trim(chars=" ").to_string()
    if part.length() > 0 {
      segments.push(part)
    }
  }
  if segments.length() < 2 {
    return ""
  }
  let owner = segments[segments.length() - 2]
  let repo = segments[segments.length() - 1]
  owner + "/" + repo
}

///|
fn github_repository_from_git_config(config_text : String) -> String? {
  match origin_remote_url_from_git_config(config_text) {
    Some(remote_url) => {
      let repository = github_repository_from_remote_url(remote_url)
      if repository.length() > 0 {
        Some(repository)
      } else {
        None
      }
    }
    None => None
  }
}

///|
fn github_repository_from_repo_root(repo_root : String) -> String? {
  let config_paths = [
    join_path(repo_root, ".git/config"),
    join_path(repo_root, "config"),
  ]
  for config_path in config_paths {
    match read_text(config_path) {
      Some(config_text) =>
        match github_repository_from_git_config(config_text) {
          Some(repository) => return Some(repository)
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
fn merge_cli_push_event(
  base : @ar.PushEvent,
  options : CliOptions,
) -> @ar.PushEvent {
  let ref_name = if options.ref_name.length() > 0 {
    options.ref_name
  } else {
    base.ref_name
  }
  let changed_paths = if options.changed_paths.length() > 0 {
    options.changed_paths
  } else {
    base.changed_paths
  }
  let before_sha = if options.before_sha.length() > 0 {
    options.before_sha
  } else {
    base.before_sha
  }
  let after_sha = if options.after_sha.length() > 0 {
    options.after_sha
  } else {
    base.after_sha
  }
  let repository = if options.repository.length() > 0 {
    options.repository
  } else {
    base.repository
  }
  @ar.new_push_event(
    ref_name,
    changed_paths,
    before_sha~,
    after_sha~,
    repository~,
    actor=base.actor,
  )
}

///|
fn origin_remote_url_from_repo_root(repo_root : String) -> String? {
  let config_paths = [
    join_path(repo_root, ".git/config"),
    join_path(repo_root, "config"),
  ]
  for config_path in config_paths {
    match read_text(config_path) {
      Some(config_text) =>
        match origin_remote_url_from_git_config(config_text) {
          Some(remote_url) => return Some(remote_url)
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
fn ensure_dir(path : String) -> Unit raise {
  if path.length() == 0 || path == "." || path == "/" {
    return
  }
  let parent = parent_dir(path)
  if parent != path && not(@xfs.path_exists(parent)) {
    ensure_dir(parent)
  }
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
fn next_run_slot(run_root : String) -> (String, String) raise {
  ensure_dir(run_root)
  let mut index = 1
  while true {
    let run_id = "run-" + index.to_string()
    let run_dir = join_path(run_root, run_id)
    if not(@xfs.path_exists(run_dir)) {
      @xfs.create_dir(run_dir)
      return (run_id, run_dir)
    }
    index += 1
  }
  abort("unreachable")
}

///|
fn json_escape(text : String) -> String {
  text
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\n", new="\\n")
  .replace_all(old="\r", new="\\r")
  .replace_all(old="\t", new="\\t")
}

///|
fn json_string(text : String) -> String {
  "\"" + json_escape(text) + "\""
}

///|
fn json_string_array(values : Array[String]) -> String {
  let items : Array[String] = []
  for value in values {
    items.push(json_string(value))
  }
  "[" + items.join(", ") + "]"
}

///|
fn json_optional_string(value : String?) -> String {
  match value {
    Some(text) => json_string(text)
    None => "null"
  }
}

///|
fn json_optional_int(value : Int?) -> String {
  match value {
    Some(number) => number.to_string()
    None => "null"
  }
}

///|
fn json_uint64(value : UInt64) -> String {
  value.to_string()
}

///|
fn task_file_stem(task_id : String) -> String {
  task_id.replace_all(old="/", new="__").replace_all(old=":", new="_")
}

///|
fn run_store_sanitize_id(text : String) -> String {
  text.replace_all(old="/", new="__").replace_all(old=":", new="_")
}

///|
fn absolute_run_store_path(path : String) -> String {
  if path.has_prefix("/") {
    return path
  }
  let pwd = @env.current_dir().unwrap_or(
    @xsys.get_env_var("PWD").unwrap_or("."),
  )
  join_path(pwd, path)
}

///|
fn run_store_workspace_key(workspace_root : String) -> String {
  run_store_sanitize_id(absolute_run_store_path(workspace_root))
}

///|
fn artifact_store_root_for_run(workspace_root : String) -> String {
  let base = @xsys.get_env_var("ACTION_RUNNER_ARTIFACT_ROOT").unwrap_or(
    "_build/action_runner/artifacts",
  )
  absolute_run_store_path(base + "/" + run_store_workspace_key(workspace_root))
}

///|
fn cache_store_root_for_run(workspace_root : String) -> String {
  let base = @xsys.get_env_var("ACTION_RUNNER_CACHE_ROOT").unwrap_or(
    "_build/action_runner/cache",
  )
  absolute_run_store_path(base + "/" + run_store_workspace_key(workspace_root))
}

///|
fn sorted_dir_entries(path : String) -> Array[String] {
  let entries = try @xfs.read_dir(path) catch {
    _ => []
  } noraise {
    value => value
  }
  entries.sort_by(String::lexical_compare)
  entries
}

///|
fn run_store_is_dir(path : String) -> Bool {
  try @xfs.is_dir(path) catch {
    _ => false
  } noraise {
    value => value
  }
}

///|
fn collect_relative_files(
  root : String,
  current? : String = "",
  ignored? : Map[String, Bool] = {},
) -> Array[String] {
  let files : Array[String] = []
  let dir = if current.length() > 0 { join_path(root, current) } else { root }
  for entry in sorted_dir_entries(dir) {
    let relative = if current.length() > 0 {
      current + "/" + entry
    } else {
      entry
    }
    if ignored.get(relative) is Some(_) {
      continue
    }
    let full_path = join_path(root, relative)
    if run_store_is_dir(full_path) {
      for child in collect_relative_files(root, current=relative, ignored~) {
        files.push(child)
      }
    } else {
      files.push(relative)
    }
  }
  files
}

///|
fn task_status_map(report : @ar.WorkflowRunReport) -> Map[String, String] {
  let statuses : Map[String, String] = {}
  for task in report.task_reports {
    statuses[task.id] = task.status
  }
  statuses
}

///|
fn derive_job_status(task_statuses : Array[String]) -> String {
  if task_statuses.length() == 0 {
    return "skipped"
  }
  for status in task_statuses {
    if status == "failed" {
      return "failure"
    }
  }
  for status in task_statuses {
    if status == "cancelled" {
      return "cancelled"
    }
  }
  for status in task_statuses {
    if status == "success" {
      return "success"
    }
  }
  for status in task_statuses {
    if status == "skipped" || status == "blocked" {
      return "skipped"
    }
  }
  "unknown"
}

///|
fn collect_run_jobs(
  plan : @ar.ExecutionPlan,
  report : @ar.WorkflowRunReport,
) -> Array[RunJobRecord] {
  let task_statuses = task_status_map(report)
  let by_job : Map[String, Array[String]] = {}
  let job_order : Array[String] = []
  for task in plan.tasks {
    let current = by_job.get(task.job_id).unwrap_or([])
    if current.length() == 0 {
      job_order.push(task.job_id)
    }
    current.push(task.id)
    by_job[task.job_id] = current
  }
  let jobs : Array[RunJobRecord] = []
  for job_id in job_order {
    let task_ids = by_job.get(job_id).unwrap_or([])
    let statuses : Array[String] = []
    for task_id in task_ids {
      statuses.push(task_statuses.get(task_id).unwrap_or("skipped"))
    }
    jobs.push({
      id: job_id,
      status: derive_job_status(statuses),
      needs: plan.job_needs.get(job_id).unwrap_or([]),
      task_ids,
    })
  }
  jobs
}

///|
fn artifact_name_index(
  plan : @ar.ExecutionPlan,
  report : @ar.WorkflowRunReport,
) -> Map[String, String] {
  let names : Map[String, String] = {}
  let statuses = task_status_map(report)
  for task in plan.tasks {
    guard statuses.get(task.id) is Some(status) else { continue }
    if status != "success" {
      continue
    }
    guard task.action is Some(action) else { continue }
    if action.kind != "upload-artifact" {
      continue
    }
    let name = task.env.get("INPUT_NAME").unwrap_or("")
    if name.length() == 0 {
      continue
    }
    names[run_store_sanitize_id(name)] = name
  }
  names
}

///|
fn collect_run_artifacts(
  workspace_root : String,
  plan? : @ar.ExecutionPlan? = None,
  report? : @ar.WorkflowRunReport? = None,
) -> Array[RunArtifactRecord] {
  let store_root = artifact_store_root_for_run(workspace_root)
  if not(@xfs.path_exists(store_root)) {
    return []
  }
  let name_map = match (plan, report) {
    (Some(actual_plan), Some(actual_report)) =>
      artifact_name_index(actual_plan, actual_report)
    _ => {}
  }
  let artifacts : Array[RunArtifactRecord] = []
  for entry in sorted_dir_entries(store_root) {
    let artifact_root = join_path(store_root, entry)
    if not(run_store_is_dir(artifact_root)) {
      continue
    }
    artifacts.push({
      name: name_map.get(entry).unwrap_or(entry),
      files: collect_relative_files(artifact_root),
    })
  }
  artifacts
}

///|
fn read_text_file(path : String) -> String? {
  try Some(@xfs.read_file_to_string(path)) catch {
    _ => None
  } noraise {
    value => value
  }
}

///|
fn read_cache_sequence(path : String) -> Int? {
  match read_text_file(path) {
    Some(content) => {
      let trimmed = content.trim(chars=" \t\r\n").to_string()
      if trimmed.length() == 0 {
        return None
      }
      let parsed = @strconv.parse_int64(trimmed) catch { _ => return None }
      Some(parsed.to_int())
    }
    None => None
  }
}

///|
fn collect_run_caches(workspace_root : String) -> Array[RunCacheRecord] {
  let store_root = cache_store_root_for_run(workspace_root)
  if not(@xfs.path_exists(store_root)) {
    return []
  }
  let ignored : Map[String, Bool] = {
    "__action_runner_cache_key.txt": true,
    "__action_runner_cache_sequence.txt": true,
  }
  let caches : Array[RunCacheRecord] = []
  for entry in sorted_dir_entries(store_root) {
    if entry == "__action_runner_sequence.txt" {
      continue
    }
    let cache_root = join_path(store_root, entry)
    if not(run_store_is_dir(cache_root)) {
      continue
    }
    let key = match
      read_text_file(join_path(cache_root, "__action_runner_cache_key.txt")) {
      Some(content) => content.trim(chars=" \t\r\n").to_string()
      None => entry
    }
    caches.push({
      key,
      sequence: read_cache_sequence(
        join_path(cache_root, "__action_runner_cache_sequence.txt"),
      ),
      files: collect_relative_files(cache_root, ignored~),
    })
  }
  caches
}

///|
fn run_job_json(job : RunJobRecord) -> String {
  "{ " +
  "\"id\": " +
  json_string(job.id) +
  ", " +
  "\"status\": " +
  json_string(job.status) +
  ", " +
  "\"needs\": " +
  json_string_array(job.needs) +
  ", " +
  "\"task_ids\": " +
  json_string_array(job.task_ids) +
  " }"
}

///|
fn run_artifact_json(artifact : RunArtifactRecord) -> String {
  "{ " +
  "\"name\": " +
  json_string(artifact.name) +
  ", " +
  "\"files\": " +
  json_string_array(artifact.files) +
  " }"
}

///|
fn run_cache_json(cache : RunCacheRecord) -> String {
  "{ " +
  "\"key\": " +
  json_string(cache.key) +
  ", " +
  "\"sequence\": " +
  json_optional_int(cache.sequence) +
  ", " +
  "\"files\": " +
  json_string_array(cache.files) +
  " }"
}

///|
fn run_jobs_json(jobs : Array[RunJobRecord]) -> String {
  let items : Array[String] = []
  for job in jobs {
    items.push(run_job_json(job))
  }
  "[" + items.join(", ") + "]"
}

///|
fn run_artifacts_json(artifacts : Array[RunArtifactRecord]) -> String {
  let items : Array[String] = []
  for artifact in artifacts {
    items.push(run_artifact_json(artifact))
  }
  "[" + items.join(", ") + "]"
}

///|
fn run_caches_json(caches : Array[RunCacheRecord]) -> String {
  let items : Array[String] = []
  for cache in caches {
    items.push(run_cache_json(cache))
  }
  "[" + items.join(", ") + "]"
}

///|
fn run_step_json(step : @ar.WorkflowStepReport) -> String {
  "{ " +
  "\"id\": " +
  json_string(step.id) +
  ", " +
  "\"status\": " +
  json_string(step.status) +
  ", " +
  "\"required\": " +
  (if step.required { "true" } else { "false" }) +
  ", " +
  "\"message\": " +
  json_string(step.message) +
  " }"
}

///|
fn run_task_json(task : @ar.TaskRunReport, files : RunTaskFiles?) -> String {
  let stdout_path = match files {
    Some(value) => value.stdout_path
    None => ""
  }
  let stderr_path = match files {
    Some(value) => value.stderr_path
    None => ""
  }
  let summary_path = match files {
    Some(value) => value.summary_path
    None => None
  }
  "{ " +
  "\"id\": " +
  json_string(task.id) +
  ", " +
  "\"kind\": " +
  json_string(task.kind) +
  ", " +
  "\"status\": " +
  json_string(task.status) +
  ", " +
  "\"code\": " +
  task.code.to_string() +
  ", " +
  "\"shell\": " +
  json_string(task.shell) +
  ", " +
  "\"cwd\": " +
  json_string(task.cwd) +
  ", " +
  "\"stdout_path\": " +
  json_string(stdout_path) +
  ", " +
  "\"stderr_path\": " +
  json_string(stderr_path) +
  ", " +
  "\"summary_path\": " +
  json_optional_string(summary_path) +
  " }"
}

///|
fn run_record_json(
  record : RunRecord,
  report? : @ar.WorkflowRunReport? = None,
  jobs? : Array[RunJobRecord] = [],
  artifacts? : Array[RunArtifactRecord] = [],
  caches? : Array[RunCacheRecord] = [],
  task_files? : Map[String, RunTaskFiles] = {},
) -> String {
  let order_json = match report {
    Some(run_report) => json_string_array(run_report.order)
    None => "[]"
  }
  let issues_json = match report {
    Some(run_report) => json_string_array(run_report.issues)
    None => "[]"
  }
  let steps_json = match report {
    Some(run_report) => {
      let items : Array[String] = []
      for step in run_report.steps {
        items.push(run_step_json(step))
      }
      "[" + items.join(", ") + "]"
    }
    None => "[]"
  }
  let tasks_json = match report {
    Some(run_report) => {
      let items : Array[String] = []
      for task in run_report.task_reports {
        items.push(run_task_json(task, task_files.get(task.id)))
      }
      "[" + items.join(", ") + "]"
    }
    None => "[]"
  }
  let jobs_json = run_jobs_json(jobs)
  let artifacts_json = run_artifacts_json(artifacts)
  let caches_json = run_caches_json(caches)
  "{\n" +
  "  \"run_id\": " +
  json_string(record.run_id) +
  ",\n" +
  "  \"workflow_name\": " +
  json_string(record.workflow_name) +
  ",\n" +
  "  \"workflow_path\": " +
  json_string(record.workflow_path) +
  ",\n" +
  "  \"workspace_root\": " +
  json_string(record.workspace_root) +
  ",\n" +
  "  \"workspace_mode\": " +
  json_string(record.workspace_mode) +
  ",\n" +
  "  \"started_at_ms\": " +
  json_uint64(record.started_at_ms) +
  ",\n" +
  "  \"finished_at_ms\": " +
  json_uint64(record.finished_at_ms) +
  ",\n" +
  "  \"state\": " +
  json_string(record.state) +
  ",\n" +
  "  \"ok\": " +
  (if record.ok { "true" } else { "false" }) +
  ",\n" +
  "  \"repository\": " +
  json_string(record.repository) +
  ",\n" +
  "  \"ref_name\": " +
  json_string(record.ref_name) +
  ",\n" +
  "  \"before_sha\": " +
  json_string(record.before_sha) +
  ",\n" +
  "  \"after_sha\": " +
  json_string(record.after_sha) +
  ",\n" +
  "  \"changed_paths\": " +
  json_string_array(record.changed_paths) +
  ",\n" +
  "  \"order\": " +
  order_json +
  ",\n" +
  "  \"issues\": " +
  issues_json +
  ",\n" +
  "  \"steps\": " +
  steps_json +
  ",\n" +
  "  \"tasks\": " +
  tasks_json +
  ",\n" +
  "  \"jobs\": " +
  jobs_json +
  ",\n" +
  "  \"artifacts\": " +
  artifacts_json +
  ",\n" +
  "  \"caches\": " +
  caches_json +
  "\n" +
  "}\n"
}

///|
fn persist_task_files(
  run_dir : String,
  report : @ar.WorkflowRunReport,
) -> Map[String, RunTaskFiles] raise {
  let files : Map[String, RunTaskFiles] = {}
  let tasks_dir = join_path(run_dir, "tasks")
  ensure_dir(tasks_dir)
  if report.task_reports.length() == 0 {
    return files
  }
  for task in report.task_reports {
    let stem = task_file_stem(task.id)
    let stdout_rel = "tasks/" + stem + ".stdout.log"
    let stderr_rel = "tasks/" + stem + ".stderr.log"
    @xfs.write_string_to_file(join_path(run_dir, stdout_rel), task.stdout)
    @xfs.write_string_to_file(join_path(run_dir, stderr_rel), task.stderr)
    let summary_rel = if task.summary.length() > 0 {
      Some("tasks/" + stem + ".summary.md")
    } else {
      None
    }
    match summary_rel {
      Some(rel) =>
        @xfs.write_string_to_file(join_path(run_dir, rel), task.summary)
      None => ()
    }
    files[task.id] = {
      stdout_path: stdout_rel,
      stderr_path: stderr_rel,
      summary_path: summary_rel,
    }
  }
  files
}

///|
fn persist_run_layout_files(
  run_dir : String,
  jobs : Array[RunJobRecord],
  artifacts : Array[RunArtifactRecord],
  caches : Array[RunCacheRecord],
) -> Unit raise {
  @xfs.write_string_to_file(
    join_path(run_dir, "jobs.json"),
    run_jobs_json(jobs) + "\n",
  )
  @xfs.write_string_to_file(
    join_path(run_dir, "artifacts.json"),
    run_artifacts_json(artifacts) + "\n",
  )
  @xfs.write_string_to_file(
    join_path(run_dir, "caches.json"),
    run_caches_json(caches) + "\n",
  )
}

///|
fn persist_run_record(
  run_root : String,
  record : RunRecord,
  report? : @ar.WorkflowRunReport? = None,
  plan? : @ar.ExecutionPlan? = None,
) -> String? {
  try {
    let (run_id, run_dir) = next_run_slot(run_root)
    let task_files = match report {
      Some(run_report) => persist_task_files(run_dir, run_report)
      None => {}
    }
    let jobs = match (plan, report) {
      (Some(actual_plan), Some(actual_report)) =>
        collect_run_jobs(actual_plan, actual_report)
      _ => []
    }
    let artifacts = collect_run_artifacts(record.workspace_root, plan~, report~)
    let caches = collect_run_caches(record.workspace_root)
    persist_run_layout_files(run_dir, jobs, artifacts, caches)
    @xfs.write_string_to_file(
      join_path(run_dir, "run.json"),
      run_record_json(
        {
          run_id,
          workflow_name: record.workflow_name,
          workflow_path: record.workflow_path,
          workspace_root: record.workspace_root,
          workspace_mode: record.workspace_mode,
          started_at_ms: record.started_at_ms,
          finished_at_ms: record.finished_at_ms,
          state: record.state,
          ok: record.ok,
          repository: record.repository,
          ref_name: record.ref_name,
          before_sha: record.before_sha,
          after_sha: record.after_sha,
          changed_paths: record.changed_paths,
        },
        report~,
        jobs~,
        artifacts~,
        caches~,
        task_files~,
      ),
    )
    Some(run_id)
  } catch {
    _ => None
  } noraise {
    value => value
  }
}

///|
fn parse_cli_args(args : Array[String]) -> CliParseResult {
  let errors : Array[String] = []
  let mut workflow_path = ""
  let mut repo_root : String? = None
  let mut workspace_root : String? = None
  let mut run_root : String? = None
  let mut artifact_root : String? = None
  let mut cache_root : String? = None
  let mut github_action_cache_root : String? = None
  let mut registry_root : String? = None
  let mut wasm_action_root : String? = None
  let mut workspace_mode = ""
  let mut event_path : String? = None
  let mut repository = ""
  let mut ref_name = ""
  let mut before_sha = ""
  let mut after_sha = ""
  let changed_paths : Array[String] = []
  let mut index = 1

  while index < args.length() {
    let arg = args[index]
    if arg == "--repo" ||
      arg == "--workspace" ||
      arg == "--run-root" ||
      arg == "--artifact-root" ||
      arg == "--cache-root" ||
      arg == "--github-action-cache-root" ||
      arg == "--registry-root" ||
      arg == "--wasm-action-root" ||
      arg == "--workspace-mode" ||
      arg == "--event" ||
      arg == "--repository" ||
      arg == "--ref" ||
      arg == "--before" ||
      arg == "--after" ||
      arg == "--changed" {
      if index + 1 >= args.length() {
        errors.push("missing value for " + arg)
        break
      }
      let value = args[index + 1]
      if arg == "--repo" {
        repo_root = Some(value)
      } else if arg == "--workspace" {
        workspace_root = Some(value)
      } else if arg == "--run-root" {
        run_root = Some(value)
      } else if arg == "--artifact-root" {
        artifact_root = Some(value)
      } else if arg == "--cache-root" {
        cache_root = Some(value)
      } else if arg == "--github-action-cache-root" {
        github_action_cache_root = Some(value)
      } else if arg == "--registry-root" {
        registry_root = Some(value)
      } else if arg == "--wasm-action-root" {
        wasm_action_root = Some(value)
      } else if arg == "--workspace-mode" {
        workspace_mode = value
      } else if arg == "--event" {
        event_path = Some(value)
      } else if arg == "--repository" {
        repository = value
      } else if arg == "--ref" {
        ref_name = value
      } else if arg == "--before" {
        before_sha = value
      } else if arg == "--after" {
        after_sha = value
      } else {
        changed_paths.push(value)
      }
      index += 2
      continue
    }
    if arg == "--help" {
      errors.push(usage_text())
      break
    }
    if arg.has_prefix("--") {
      errors.push("unknown option: " + arg)
      index += 1
      continue
    }
    if workflow_path.length() == 0 {
      workflow_path = arg
    } else {
      errors.push("unexpected argument: " + arg)
    }
    index += 1
  }

  if workflow_path.length() == 0 && errors.length() == 0 {
    errors.push("workflow path is required")
  }
  if repo_root is Some(_) && workflow_path.has_prefix("/") {
    errors.push("workflow path must be relative when --repo is used")
  }
  if workspace_mode.length() > 0 && not(valid_workspace_mode(workspace_mode)) {
    errors.push("workspace mode must be one of: worktree, tmp, docker")
  }
  if errors.length() > 0 {
    return { options: None, errors }
  }
  {
    options: Some({
      workflow_path,
      repo_root,
      workspace_root,
      run_root,
      artifact_root,
      cache_root,
      github_action_cache_root,
      registry_root,
      wasm_action_root,
      workspace_mode,
      event_path,
      repository,
      ref_name,
      before_sha,
      after_sha,
      changed_paths,
    }),
    errors,
  }
}

///|
fn parse_run_read_args(args : Array[String]) -> RunReadParseResult {
  let errors : Array[String] = []
  if args.length() < 3 {
    return { options: None, errors: ["run subcommand requires an action"] }
  }
  let action = args[2]
  if action != "list" &&
    action != "view" &&
    action != "watch" &&
    action != "logs" &&
    action != "download" {
    return { options: None, errors: ["unknown run subcommand: " + action] }
  }
  let mut run_id = ""
  let mut index = 3
  if action != "list" {
    if args.length() < 4 {
      return {
        options: None,
        errors: ["run subcommand requires an action and run id"],
      }
    }
    run_id = args[3]
    if run_id.length() == 0 {
      errors.push("run id is required")
    }
    index = 4
  }
  let mut run_root : String? = None
  let mut task_id : String? = None
  let mut artifact_root : String? = None
  let mut download_dir = "."
  let mut json_output = false
  while index < args.length() {
    let arg = args[index]
    if arg == "--json" {
      json_output = true
      index += 1
      continue
    }
    if arg == "--run-root" ||
      arg == "--task" ||
      arg == "--artifact-root" ||
      arg == "--dir" {
      if index + 1 >= args.length() {
        errors.push("missing value for " + arg)
        break
      }
      let value = args[index + 1]
      if arg == "--run-root" {
        run_root = Some(value)
      } else if arg == "--artifact-root" {
        artifact_root = Some(value)
      } else if arg == "--dir" {
        download_dir = value
      } else {
        task_id = Some(value)
      }
      index += 2
      continue
    }
    if arg == "--help" {
      errors.push(usage_text())
      break
    }
    errors.push("unknown option: " + arg)
    index += 1
  }
  if action == "view" && task_id is Some(_) {
    errors.push("--task is only supported for `run logs`")
  }
  if action == "watch" && task_id is Some(_) {
    errors.push("--task is only supported for `run logs`")
  }
  if action == "list" && task_id is Some(_) {
    errors.push("--task is only supported for `run logs`")
  }
  if action != "download" && artifact_root is Some(_) {
    errors.push("--artifact-root is only supported for `run download`")
  }
  if action != "download" && download_dir != "." {
    errors.push("--dir is only supported for `run download`")
  }
  if action != "list" && json_output && action != "view" && action != "watch" {
    errors.push(
      "--json is only supported for `run list`, `run view`, or `run watch`",
    )
  }
  if errors.length() > 0 {
    return { options: None, errors }
  }
  {
    options: Some({
      action,
      run_id,
      run_root,
      task_id,
      artifact_root,
      download_dir,
      json_output,
    }),
    errors: [],
  }
}

///|
fn parse_artifact_read_args(args : Array[String]) -> ArtifactReadParseResult {
  let errors : Array[String] = []
  if args.length() < 4 {
    return {
      options: None,
      errors: ["artifact subcommand requires an action and run id"],
    }
  }
  let action = args[2]
  if action != "list" && action != "download" {
    return { options: None, errors: ["unknown artifact subcommand: " + action] }
  }
  let run_id = args[3]
  if run_id.length() == 0 {
    errors.push("run id is required")
  }
  let mut run_root : String? = None
  let mut artifact_root : String? = None
  let mut artifact_name = ""
  let mut download_dir = "."
  let mut json_output = false
  let mut index = 4
  while index < args.length() {
    let arg = args[index]
    if arg == "--json" {
      json_output = true
      index += 1
      continue
    }
    if arg == "--run-root" ||
      arg == "--artifact-root" ||
      arg == "--name" ||
      arg == "--dir" {
      if index + 1 >= args.length() {
        errors.push("missing value for " + arg)
        break
      }
      let value = args[index + 1]
      if arg == "--run-root" {
        run_root = Some(value)
      } else if arg == "--artifact-root" {
        artifact_root = Some(value)
      } else if arg == "--name" {
        artifact_name = value
      } else {
        download_dir = value
      }
      index += 2
      continue
    }
    if arg == "--help" {
      errors.push(usage_text())
      break
    }
    errors.push("unknown option: " + arg)
    index += 1
  }
  if action == "list" {
    if artifact_name.length() > 0 {
      errors.push("--name is only supported for `artifact download`")
    }
    if download_dir != "." {
      errors.push("--dir is only supported for `artifact download`")
    }
    if artifact_root is Some(_) {
      errors.push("--artifact-root is only supported for `artifact download`")
    }
  } else if artifact_name.length() == 0 {
    errors.push("--name is required for `artifact download`")
  }
  if errors.length() > 0 {
    return { options: None, errors }
  }
  {
    options: Some({
      action,
      run_id,
      run_root,
      artifact_root,
      artifact_name,
      download_dir,
      json_output,
    }),
    errors: [],
  }
}

///|
fn parse_cache_read_args(args : Array[String]) -> CacheReadParseResult {
  let errors : Array[String] = []
  if args.length() < 3 {
    return { options: None, errors: ["cache subcommand requires an action"] }
  }
  let action = args[2]
  if action != "list" {
    return { options: None, errors: ["unknown cache subcommand: " + action] }
  }
  let mut cache_root : String? = None
  let mut json_output = false
  let mut index = 3
  while index < args.length() {
    let arg = args[index]
    if arg == "--json" {
      json_output = true
      index += 1
      continue
    }
    if arg == "--cache-root" {
      if index + 1 >= args.length() {
        errors.push("missing value for --cache-root")
        break
      }
      cache_root = Some(args[index + 1])
      index += 2
      continue
    }
    if arg == "--help" {
      errors.push(usage_text())
      break
    }
    errors.push("unknown option: " + arg)
    index += 1
  }
  if errors.length() > 0 {
    return { options: None, errors }
  }
  { options: Some({ action, cache_root, json_output }), errors: [] }
}

///|
fn print_errors(errors : Array[String]) -> Unit {
  for err in errors {
    println("error: " + err)
  }
}

///|
fn read_text(path : String) -> String? {
  try @xfs.read_file_to_string(path) catch {
    _ => None
  } noraise {
    content => Some(content)
  }
}

///|
fn run_json_field(obj : Json, key : String) -> Json? {
  if obj is Object(fields) {
    fields.get(key)
  } else {
    None
  }
}

///|
fn run_json_string(obj : Json, key : String) -> String {
  match run_json_field(obj, key) {
    Some(String(value)) => value
    _ => ""
  }
}

///|
fn run_json_number_text(obj : Json, key : String) -> String {
  match run_json_field(obj, key) {
    Some(Number(value, ..)) => value.to_string()
    _ => ""
  }
}

///|
fn run_json_array(obj : Json, key : String) -> Array[Json] {
  match run_json_field(obj, key) {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn ensure_trailing_newline(text : String) -> String {
  if text.length() == 0 || text.has_suffix("\n") {
    text
  } else {
    text + "\n"
  }
}

///|
fn run_json_texts_in_order(run_root : String) -> Array[String] {
  if not(@xfs.path_exists(run_root)) {
    return []
  }
  let entries = sorted_dir_entries(run_root)
  let run_json_texts : Array[String] = []
  for idx in 0..<entries.length() {
    let entry = entries[entries.length() - 1 - idx]
    let run_dir = join_path(run_root, entry)
    if not(run_store_is_dir(run_dir)) {
      continue
    }
    let run_json_path = join_path(run_dir, "run.json")
    match read_text(run_json_path) {
      Some(text) => run_json_texts.push(text.trim_end(chars="\n").to_string())
      None => ()
    }
  }
  run_json_texts
}

///|
fn collect_run_list_json(run_root : String) -> String? {
  let items = run_json_texts_in_order(run_root)
  Some("[" + items.join(", ") + "]\n")
}

///|
fn format_run_list_text(run_root : String) -> String? {
  let run_json_texts = run_json_texts_in_order(run_root)
  let lines : Array[String] = []
  for run_json_text in run_json_texts {
    let payload = @json.parse(run_json_text) catch { _ => return None }
    guard payload is Object(_) else { return None }
    let run_id = run_json_string(payload, "run_id")
    let state = run_json_string(payload, "state")
    let workflow_name = run_json_string(payload, "workflow_name")
    lines.push(run_id + "\t" + state + "\t" + workflow_name)
  }
  Some(if lines.length() == 0 { "" } else { lines.join("\n") + "\n" })
}

///|
fn artifact_store_root_for_read(
  workspace_root : String,
  artifact_root_override : String?,
) -> String {
  match artifact_root_override {
    Some(base) =>
      absolute_run_store_path(
        base + "/" + run_store_workspace_key(workspace_root),
      )
    None => artifact_store_root_for_run(workspace_root)
  }
}

///|
fn cache_store_base_root_for_read(cache_root_override : String?) -> String {
  match cache_root_override {
    Some(base) => absolute_run_store_path(base)
    None =>
      absolute_run_store_path(
        @xsys.get_env_var("ACTION_RUNNER_CACHE_ROOT").unwrap_or(
          "_build/action_runner/cache",
        ),
      )
  }
}

///|
fn collect_cache_list_records(
  cache_root_base : String,
) -> Array[CacheListRecord] {
  if not(@xfs.path_exists(cache_root_base)) {
    return []
  }
  let ignored : Map[String, Bool] = {
    "__action_runner_cache_key.txt": true,
    "__action_runner_cache_sequence.txt": true,
  }
  let caches : Array[CacheListRecord] = []
  for workspace_key in sorted_dir_entries(cache_root_base) {
    let workspace_root = join_path(cache_root_base, workspace_key)
    if not(run_store_is_dir(workspace_root)) {
      continue
    }
    for entry in sorted_dir_entries(workspace_root) {
      if entry == "__action_runner_sequence.txt" {
        continue
      }
      let cache_root = join_path(workspace_root, entry)
      if not(run_store_is_dir(cache_root)) {
        continue
      }
      let key = match
        read_text_file(join_path(cache_root, "__action_runner_cache_key.txt")) {
        Some(content) => content.trim(chars=" \t\r\n").to_string()
        None => entry
      }
      caches.push({
        workspace_key,
        key,
        sequence: read_cache_sequence(
          join_path(cache_root, "__action_runner_cache_sequence.txt"),
        ),
        files: collect_relative_files(cache_root, ignored~),
      })
    }
  }
  caches
}

///|
fn cache_list_record_json(cache : CacheListRecord) -> String {
  "{ " +
  "\"workspace_key\": " +
  json_string(cache.workspace_key) +
  ", " +
  "\"key\": " +
  json_string(cache.key) +
  ", " +
  "\"sequence\": " +
  json_optional_int(cache.sequence) +
  ", " +
  "\"files\": " +
  json_string_array(cache.files) +
  " }"
}

///|
fn cache_list_json(caches : Array[CacheListRecord]) -> String {
  let items : Array[String] = []
  for cache in caches {
    items.push(cache_list_record_json(cache))
  }
  "[" + items.join(", ") + "]"
}

///|
fn format_cache_list_text(caches : Array[CacheListRecord]) -> String {
  let lines : Array[String] = []
  for cache in caches {
    let sequence_text = match cache.sequence {
      Some(value) => value.to_string()
      None => ""
    }
    lines.push(
      cache.workspace_key +
      "\t" +
      cache.key +
      "\t" +
      sequence_text +
      "\t" +
      cache.files.join(","),
    )
  }
  if lines.length() == 0 {
    ""
  } else {
    lines.join("\n") + "\n"
  }
}

///|
fn format_artifact_list_text(artifacts_json_text : String) -> String? {
  let payload = @json.parse(artifacts_json_text) catch { _ => return None }
  guard payload is Array(items) else { return None }
  let lines : Array[String] = []
  for item in items {
    if item is { "name": String(name), "files": Array(files), .. } {
      let paths : Array[String] = []
      for file in files {
        if file is String(path) {
          paths.push(path)
        }
      }
      lines.push(name + "\t" + paths.join(","))
    }
  }
  Some(if lines.length() == 0 { "" } else { lines.join("\n") + "\n" })
}

///|
fn artifact_files_from_json_text(
  artifacts_json_text : String,
  artifact_name : String,
) -> Array[String]? {
  let payload = @json.parse(artifacts_json_text) catch { _ => return None }
  guard payload is Array(items) else { return None }
  for item in items {
    if item is { "name": String(name), "files": Array(files), .. } &&
      name == artifact_name {
      let paths : Array[String] = []
      for file in files {
        if file is String(path) {
          paths.push(path)
        }
      }
      return Some(paths)
    }
  }
  Some([])
}

///|
fn artifact_names_from_json_text(
  artifacts_json_text : String,
) -> Array[String]? {
  let payload = @json.parse(artifacts_json_text) catch { _ => return None }
  guard payload is Array(items) else { return None }
  let names : Array[String] = []
  for item in items {
    if item is { "name": String(name), .. } {
      names.push(name)
    }
  }
  Some(names)
}

///|
fn copy_file(src : String, dst : String) -> Bool {
  try {
    ensure_dir(parent_dir(dst))
    @xfs.write_bytes_to_file(dst, @xfs.read_file_to_bytes(src))
    true
  } catch {
    _ => false
  } noraise {
    value => value
  }
}

///|
fn format_run_view_text(run_json_text : String) -> String? {
  let payload = @json.parse(run_json_text) catch { _ => return None }
  guard payload is Object(_) else { return None }
  let lines : Array[String] = []
  let run_id = run_json_string(payload, "run_id")
  let workflow_name = run_json_string(payload, "workflow_name")
  let state = run_json_string(payload, "state")
  let workspace_mode = run_json_string(payload, "workspace_mode")
  lines.push("run_id=\{run_id}")
  lines.push("workflow=\{workflow_name}")
  lines.push("state=\{state}")
  lines.push("workspace_mode=\{workspace_mode}")
  let started_at_ms = run_json_number_text(payload, "started_at_ms")
  if started_at_ms.length() > 0 {
    lines.push("started_at_ms=\{started_at_ms}")
  }
  let finished_at_ms = run_json_number_text(payload, "finished_at_ms")
  if finished_at_ms.length() > 0 {
    lines.push("finished_at_ms=\{finished_at_ms}")
  }
  for job_json in run_json_array(payload, "jobs") {
    if job_json is { "id": String(id), "status": String(status), .. } {
      lines.push("job/\{id}=\{status}")
    }
  }
  for artifact_json in run_json_array(payload, "artifacts") {
    if artifact_json is { "name": String(name), "files": Array(files), .. } {
      let paths : Array[String] = []
      for file in files {
        if file is String(path) {
          paths.push(path)
        }
      }
      let joined_paths = paths.join(",")
      lines.push("artifact/\{name}=\{joined_paths}")
    }
  }
  for cache_json in run_json_array(payload, "caches") {
    if cache_json is { "key": String(key), "files": Array(files), .. } {
      let paths : Array[String] = []
      for file in files {
        if file is String(path) {
          paths.push(path)
        }
      }
      let joined_paths = paths.join(",")
      lines.push("cache/\{key}=\{joined_paths}")
    }
  }
  Some(lines.join("\n") + "\n")
}

///|
fn format_run_logs_text(
  run_dir : String,
  run_json_text : String,
  task_id? : String? = None,
) -> String? {
  let payload = @json.parse(run_json_text) catch { _ => return None }
  guard payload is Object(_) else { return None }
  let sections : Array[String] = []
  let mut matched_task = task_id is None
  for task_json in run_json_array(payload, "tasks") {
    guard task_json is { "id": String(id), .. } else { continue }
    match task_id {
      Some(expected) if expected != id => continue
      Some(_) => matched_task = true
      None => ()
    }
    let stdout_path = run_json_string(task_json, "stdout_path")
    if stdout_path.length() > 0 {
      match read_text(join_path(run_dir, stdout_path)) {
        Some(stdout) if stdout.length() > 0 =>
          sections.push("==> \{id} stdout\n" + ensure_trailing_newline(stdout))
        _ => ()
      }
    }
    let stderr_path = run_json_string(task_json, "stderr_path")
    if stderr_path.length() > 0 {
      match read_text(join_path(run_dir, stderr_path)) {
        Some(stderr) if stderr.length() > 0 =>
          sections.push("==> \{id} stderr\n" + ensure_trailing_newline(stderr))
        _ => ()
      }
    }
    match run_json_field(task_json, "summary_path") {
      Some(String(summary_path)) if summary_path.length() > 0 =>
        match read_text(join_path(run_dir, summary_path)) {
          Some(summary) if summary.length() > 0 =>
            sections.push(
              "==> \{id} summary\n" + ensure_trailing_newline(summary),
            )
          _ => ()
        }
      _ => ()
    }
  }
  if not(matched_task) {
    return None
  }
  Some(sections.join("\n"))
}

///|
fn handle_artifact_read_command(options : ArtifactReadOptions) -> Int {
  let run_root = options.run_root.unwrap_or(default_run_root())
  let run_dir = join_path(run_root, options.run_id)
  let artifacts_json_path = join_path(run_dir, "artifacts.json")
  let artifacts_json_text = match read_text(artifacts_json_path) {
    Some(content) => content
    None => {
      print_errors(["failed to read " + artifacts_json_path])
      return 1
    }
  }
  if options.action == "list" {
    if options.json_output {
      println(artifacts_json_text.trim_end(chars="\n").to_string())
      return 0
    }
    match format_artifact_list_text(artifacts_json_text) {
      Some(text) => {
        if text.length() > 0 {
          println(text.trim_end(chars="\n").to_string())
        }
        return 0
      }
      None => {
        print_errors(["failed to parse " + artifacts_json_path])
        return 1
      }
    }
  }
  let run_json_path = join_path(run_dir, "run.json")
  let run_json_text = match read_text(run_json_path) {
    Some(content) => content
    None => {
      print_errors(["failed to read " + run_json_path])
      return 1
    }
  }
  let payload = @json.parse(run_json_text) catch {
    _ => {
      print_errors(["failed to parse " + run_json_path])
      return 1
    }
  }
  guard payload is Object(_) else {
    print_errors(["failed to parse " + run_json_path])
    return 1
  }
  let workspace_root = run_json_string(payload, "workspace_root")
  if workspace_root.length() == 0 {
    print_errors(["workspace_root missing in " + run_json_path])
    return 1
  }
  let artifact_files = match
    artifact_files_from_json_text(artifacts_json_text, options.artifact_name) {
    Some(files) => files
    None => {
      print_errors(["failed to parse " + artifacts_json_path])
      return 1
    }
  }
  if artifact_files.length() == 0 {
    print_errors([
      "artifact not found: " + options.artifact_name + " in " + options.run_id,
    ])
    return 1
  }
  let artifact_dir = join_path(
    artifact_store_root_for_read(workspace_root, options.artifact_root),
    run_store_sanitize_id(options.artifact_name),
  )
  if not(@xfs.path_exists(artifact_dir)) {
    print_errors(["failed to read artifact dir " + artifact_dir])
    return 1
  }
  let download_dir = absolute_run_store_path(options.download_dir)
  let copied : Array[String] = []
  for relative_path in artifact_files {
    let src = join_path(artifact_dir, relative_path)
    let dst = join_path(download_dir, relative_path)
    if not(copy_file(src, dst)) {
      print_errors(["failed to copy artifact file " + relative_path])
      return 1
    }
    copied.push(relative_path)
  }
  let copied_text = copied.join(",")
  println("artifact=\{options.artifact_name}")
  println("dir=\{download_dir}")
  println("files=\{copied_text}")
  0
}

///|
fn handle_cache_read_command(options : CacheReadOptions) -> Int {
  if options.action != "list" {
    print_errors(["unknown cache subcommand: " + options.action])
    return 1
  }
  let cache_root = cache_store_base_root_for_read(options.cache_root)
  let caches = collect_cache_list_records(cache_root)
  if options.json_output {
    println(cache_list_json(caches))
    return 0
  }
  let text = format_cache_list_text(caches)
  if text.length() > 0 {
    println(text.trim_end(chars="\n").to_string())
  }
  0
}

///|
fn handle_run_download_command(
  options : RunReadOptions,
  run_json_text : String,
  artifacts_json_text : String,
) -> Int {
  let payload = @json.parse(run_json_text) catch {
    _ => {
      print_errors(["failed to parse run metadata"])
      return 1
    }
  }
  guard payload is Object(_) else {
    print_errors(["failed to parse run metadata"])
    return 1
  }
  let workspace_root = run_json_string(payload, "workspace_root")
  if workspace_root.length() == 0 {
    print_errors(["workspace_root missing in run metadata"])
    return 1
  }
  let artifact_names = match
    artifact_names_from_json_text(artifacts_json_text) {
    Some(names) => names
    None => {
      print_errors(["failed to parse artifact metadata"])
      return 1
    }
  }
  if artifact_names.length() == 0 {
    print_errors(["no artifacts found for " + options.run_id])
    return 1
  }
  let store_root = artifact_store_root_for_read(
    workspace_root,
    options.artifact_root,
  )
  let download_dir = absolute_run_store_path(options.download_dir)
  let downloaded : Array[String] = []
  for artifact_name in artifact_names {
    let artifact_files = match
      artifact_files_from_json_text(artifacts_json_text, artifact_name) {
      Some(files) => files
      None => {
        print_errors(["failed to parse artifact metadata"])
        return 1
      }
    }
    let artifact_dir = join_path(
      store_root,
      run_store_sanitize_id(artifact_name),
    )
    if not(@xfs.path_exists(artifact_dir)) {
      print_errors(["failed to read artifact dir " + artifact_dir])
      return 1
    }
    for relative_path in artifact_files {
      let src = join_path(artifact_dir, relative_path)
      let dst = join_path(join_path(download_dir, artifact_name), relative_path)
      if not(copy_file(src, dst)) {
        print_errors(["failed to copy artifact file " + relative_path])
        return 1
      }
    }
    downloaded.push(artifact_name)
  }
  let downloaded_text = downloaded.join(",")
  println("run_id=\{options.run_id}")
  println("dir=\{download_dir}")
  println("artifacts=\{downloaded_text}")
  0
}

///|
fn run_state_is_terminal(state : String) -> Bool {
  state == "completed" ||
  state == "partial_failed" ||
  state == "skipped" ||
  state == "cancelled" ||
  state == "failure" ||
  state == "success"
}

///|
async fn handle_run_watch_command(options : RunReadOptions) -> Int {
  let run_root = options.run_root.unwrap_or(default_run_root())
  let run_dir = join_path(run_root, options.run_id)
  let run_json_path = join_path(run_dir, "run.json")
  while true {
    let run_json_text = match read_text(run_json_path) {
      Some(content) => content
      None => {
        print_errors(["failed to read " + run_json_path])
        return 1
      }
    }
    let payload = @json.parse(run_json_text) catch {
      _ => {
        print_errors(["failed to parse " + run_json_path])
        return 1
      }
    }
    guard payload is Object(_) else {
      print_errors(["failed to parse " + run_json_path])
      return 1
    }
    let state = run_json_string(payload, "state")
    if run_state_is_terminal(state) {
      if options.json_output {
        println(run_json_text.trim_end(chars="\n").to_string())
        return 0
      }
      match format_run_view_text(run_json_text) {
        Some(text) => {
          println(text.trim_end(chars="\n").to_string())
          return 0
        }
        None => {
          print_errors(["failed to parse " + run_json_path])
          return 1
        }
      }
    }
    @async.sleep(100)
  }
  abort("unreachable")
}

///|
fn handle_run_read_command(options : RunReadOptions) -> Int {
  let run_root = options.run_root.unwrap_or(default_run_root())
  if options.action == "list" {
    if options.json_output {
      match collect_run_list_json(run_root) {
        Some(text) => {
          println(text.trim_end(chars="\n").to_string())
          return 0
        }
        None => {
          print_errors(["failed to read run list from " + run_root])
          return 1
        }
      }
    }
    match format_run_list_text(run_root) {
      Some(text) => {
        if text.length() > 0 {
          println(text.trim_end(chars="\n").to_string())
        }
        return 0
      }
      None => {
        print_errors(["failed to read run list from " + run_root])
        return 1
      }
    }
  }
  let run_dir = join_path(run_root, options.run_id)
  let run_json_path = join_path(run_dir, "run.json")
  let run_json_text = match read_text(run_json_path) {
    Some(content) => content
    None => {
      print_errors(["failed to read " + run_json_path])
      return 1
    }
  }
  if options.action == "view" {
    if options.json_output {
      println(run_json_text.trim_end(chars="\n").to_string())
      return 0
    }
    match format_run_view_text(run_json_text) {
      Some(text) => {
        println(text.trim_end(chars="\n").to_string())
        return 0
      }
      None => {
        print_errors(["failed to parse " + run_json_path])
        return 1
      }
    }
  }
  if options.action == "download" {
    let artifacts_json_path = join_path(run_dir, "artifacts.json")
    let artifacts_json_text = match read_text(artifacts_json_path) {
      Some(content) => content
      None => {
        print_errors(["failed to read " + artifacts_json_path])
        return 1
      }
    }
    return handle_run_download_command(
      options, run_json_text, artifacts_json_text,
    )
  }
  match format_run_logs_text(run_dir, run_json_text, task_id=options.task_id) {
    Some(text) => {
      println(text.trim_end(chars="\n").to_string())
      0
    }
    None => {
      match options.task_id {
        Some(task_id) =>
          print_errors(["task logs not found for " + task_id + " in " + run_dir])
        None => print_errors(["failed to parse " + run_json_path])
      }
      1
    }
  }
}

///|
fn should_check_trigger(options : CliOptions) -> Bool {
  options.event_path is Some(_) ||
  options.repo_root is Some(_) ||
  options.ref_name.length() > 0 ||
  options.before_sha.length() > 0 ||
  options.changed_paths.length() > 0 ||
  options.after_sha.length() > 0
}

///|
fn print_report(
  workflow : @ar.WorkflowSpec,
  report : @ar.WorkflowRunReport,
  run_id? : String = "",
) -> Unit {
  if run_id.length() > 0 {
    println("run_id=\{run_id}")
  }
  println("workflow=\{workflow.name}")
  println("state=\{report.state}")
  for step in report.steps {
    println("\{step.id}: \{step.status}")
  }
}

///|
fn print_skipped_report(workflow_name : String, run_id : String) -> Unit {
  if run_id.length() > 0 {
    println("run_id=\{run_id}")
  }
  println("workflow=\{workflow_name}")
  println("state=skipped")
}

///|
#cfg(target="native")
async fn main {
  let cli_args = @xsys.get_cli_args()
  if cli_args.length() > 1 && cli_args[1] == "run" {
    let parsed_run_args = parse_run_read_args(cli_args)
    if parsed_run_args.errors.length() > 0 {
      print_errors(parsed_run_args.errors)
      @xsys.exit(1)
    }
    guard parsed_run_args.options is Some(run_options) else {
      print_errors([usage_text()])
      @xsys.exit(1)
    }
    if run_options.action == "watch" {
      let exit_code = handle_run_watch_command(run_options)
      if exit_code != 0 {
        @xsys.exit(exit_code)
      }
      return
    }
    let exit_code = handle_run_read_command(run_options)
    if exit_code != 0 {
      @xsys.exit(exit_code)
    }
    return
  }
  if cli_args.length() > 1 && cli_args[1] == "artifact" {
    let parsed_artifact_args = parse_artifact_read_args(cli_args)
    if parsed_artifact_args.errors.length() > 0 {
      print_errors(parsed_artifact_args.errors)
      @xsys.exit(1)
    }
    guard parsed_artifact_args.options is Some(artifact_options) else {
      print_errors([usage_text()])
      @xsys.exit(1)
    }
    let exit_code = handle_artifact_read_command(artifact_options)
    if exit_code != 0 {
      @xsys.exit(exit_code)
    }
    return
  }
  if cli_args.length() > 1 && cli_args[1] == "cache" {
    let parsed_cache_args = parse_cache_read_args(cli_args)
    if parsed_cache_args.errors.length() > 0 {
      print_errors(parsed_cache_args.errors)
      @xsys.exit(1)
    }
    guard parsed_cache_args.options is Some(cache_options) else {
      print_errors([usage_text()])
      @xsys.exit(1)
    }
    let exit_code = handle_cache_read_command(cache_options)
    if exit_code != 0 {
      @xsys.exit(exit_code)
    }
    return
  }

  let run_started_at_ms = @env.now()
  let parsed_args = parse_cli_args(cli_args)
  if parsed_args.errors.length() > 0 {
    print_errors(parsed_args.errors)
    @xsys.exit(1)
  }
  guard parsed_args.options is Some(options) else {
    print_errors([usage_text()])
    @xsys.exit(1)
  }
  apply_cli_root_overrides(options)
  let run_root = options.run_root.unwrap_or(default_run_root())
  let workspace_mode = resolved_workspace_mode(options)
  if options.repo_root is Some(_) {
    if workspace_mode != "tmp" {
      print_errors([
        "workspace mode '\{workspace_mode}' is not implemented yet for --repo execution",
      ])
      @xsys.exit(1)
    }
  } else if workspace_mode != "worktree" {
    print_errors([
      "workspace mode '\{workspace_mode}' is not implemented yet for local workflow execution",
    ])
    @xsys.exit(1)
  }

  let mut workflow_path = options.workflow_path
  let mut execution_root = local_workspace_root(workflow_path)
  let base_event = match options.event_path {
    Some(event_path) =>
      match read_text(event_path) {
        Some(event_text) => {
          let parsed_event = @ar.parse_github_push_event_json(event_text)
          if parsed_event.errors.length() > 0 {
            print_errors(parsed_event.errors)
            @xsys.exit(1)
          }
          parsed_event.event.unwrap()
        }
        None => {
          print_errors(["failed to read " + event_path])
          @xsys.exit(1)
          @ar.new_push_event("", [])
        }
      }
    None => @ar.new_push_event("", [])
  }
  let mut trigger_event = merge_cli_push_event(base_event, options)
  let mut changed_paths = trigger_event.changed_paths
  let mut repository = trigger_event.repository
  let mut origin_remote_url = ""
  match options.repo_root {
    Some(repo_root) => {
      origin_remote_url = origin_remote_url_from_repo_root(repo_root).unwrap_or(
        "",
      )
      if repository.length() == 0 {
        repository = github_repository_from_repo_root(repo_root).unwrap_or("")
      }
    }
    None => ()
  }
  trigger_event = @ar.new_push_event(
    trigger_event.ref_name,
    trigger_event.changed_paths,
    before_sha=trigger_event.before_sha,
    after_sha=trigger_event.after_sha,
    repository~,
    actor=trigger_event.actor,
  )

  if options.repo_root is Some(repo_root) {
    let workspace_root = options.workspace_root.unwrap_or(
      default_workspace_root(),
    )
    let workspace_result = @ar.materialize_bit_push_workspace_native(
      repo_root,
      trigger_event,
      workspace_root,
      remote_url=origin_remote_url,
    )
    if workspace_result.errors.length() > 0 {
      print_errors(workspace_result.errors)
      @xsys.exit(1)
    }
    guard workspace_result.workspace is Some(workspace) else {
      print_errors(["failed to materialize bit workspace"])
      @xsys.exit(1)
    }
    workflow_path = join_path(workspace.workspace_root, options.workflow_path)
    execution_root = workspace.workspace_root
    let computed_event = @ar.new_push_event(
      workspace.refname,
      [],
      before_sha=options.before_sha,
      after_sha=workspace.commit_sha,
      repository~,
      actor=trigger_event.actor,
    )
    if changed_paths.length() == 0 {
      let changed_result = @ar.compute_bit_changed_paths_native(
        repo_root, computed_event,
      )
      if changed_result.errors.length() > 0 {
        print_errors(changed_result.errors)
        @xsys.exit(1)
      }
      changed_paths = changed_result.paths
      trigger_event = @ar.new_push_event(
        workspace.refname,
        changed_paths,
        before_sha=changed_result.base_sha,
        after_sha=changed_result.head_sha,
        repository~,
        actor=trigger_event.actor,
      )
    } else {
      trigger_event = @ar.new_push_event(
        workspace.refname,
        changed_paths,
        before_sha=options.before_sha,
        after_sha=workspace.commit_sha,
        repository~,
        actor=trigger_event.actor,
      )
    }
  }

  let text = match read_text(workflow_path) {
    Some(content) => content
    None => {
      println("error: failed to read " + workflow_path)
      @xsys.exit(1)
      ""
    }
  }

  let parsed = @ar.parse_workflow_yaml(text)
  if parsed.errors.length() > 0 {
    print_errors(parsed.errors)
    @xsys.exit(1)
  }
  guard parsed.workflow is Some(workflow) else {
    println("error: workflow parse failed")
    @xsys.exit(1)
  }

  if should_check_trigger(options) &&
    not(@ar.matches_push_trigger(workflow.trigger, trigger_event)) {
    let skipped_run_dir = persist_run_record(run_root, {
      run_id: "",
      workflow_name: workflow.name,
      workflow_path,
      workspace_root: execution_root,
      workspace_mode,
      started_at_ms: run_started_at_ms,
      finished_at_ms: @env.now(),
      state: "skipped",
      ok: true,
      repository,
      ref_name: trigger_event.ref_name,
      before_sha: trigger_event.before_sha,
      after_sha: trigger_event.after_sha,
      changed_paths: trigger_event.changed_paths,
    })
    let skipped_run_id = skipped_run_dir.unwrap_or("")
    print_skipped_report(workflow.name, skipped_run_id)
    return
  }

  let prefetch = @ar.prefetch_workflow_github_actions_native(
    workflow, execution_root,
  )
  if prefetch.errors.length() > 0 {
    print_errors(prefetch.errors)
    @xsys.exit(1)
  }

  let lowered = @ar.lower_push_workflow_in_workspace(workflow, execution_root)
  if lowered.errors.length() > 0 {
    print_errors(lowered.errors)
    @xsys.exit(1)
  }

  let report = @ar.execute_lowered_native(
    lowered,
    workspace_root=execution_root,
    push_event=Some(trigger_event),
  )
  if report.issues.length() > 0 {
    print_errors(report.issues)
  }
  let run_dir = persist_run_record(
    run_root,
    {
      run_id: "",
      workflow_name: workflow.name,
      workflow_path,
      workspace_root: execution_root,
      workspace_mode,
      started_at_ms: run_started_at_ms,
      finished_at_ms: @env.now(),
      state: report.state,
      ok: report.ok,
      repository,
      ref_name: trigger_event.ref_name,
      before_sha: trigger_event.before_sha,
      after_sha: trigger_event.after_sha,
      changed_paths: trigger_event.changed_paths,
    },
    report=Some(report),
    plan=Some(lowered.plan),
  )
  let run_id = run_dir.unwrap_or("")
  print_report(workflow, report, run_id~)
  if not(report.ok) {
    @xsys.exit(1)
  }
}

///|
#cfg(not(target="native"))
fn main {
  println("action_runner CLI execute is supported on native target only")
}
