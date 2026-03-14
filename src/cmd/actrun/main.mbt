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
  skip_actions : Array[String]
  dry_run : Bool
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
  key_filter : String
  workspace_key_filter : String
  json_output : Bool
}

///|
struct CacheReadParseResult {
  options : CacheReadOptions?
  errors : Array[String]
}

///|
struct WorkflowReadOptions {
  action : String
  repo_root : String?
  json_output : Bool
}

///|
struct WorkflowReadParseResult {
  options : WorkflowReadOptions?
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
  exit_code : Int
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
  store_path : String
}

///|
struct WorkflowListRecord {
  name : String
  path : String
}

///|
fn usage_text() -> String {
  "Usage: actrun <command>\n" +
  "\n" +
  "Workflow commands:\n" +
  "  workflow run <workflow.yml>   Run a workflow locally\n" +
  "  workflow list                 List workflows in a repository\n" +
  "\n" +
  "Run commands:\n" +
  "  run list                     List workflow runs\n" +
  "  run view <run-id>            View a workflow run\n" +
  "  run watch <run-id>           Watch a workflow run until it completes\n" +
  "  run logs <run-id>            View logs for a workflow run\n" +
  "  run download <run-id>        Download artifacts from a workflow run\n" +
  "\n" +
  "Artifact commands:\n" +
  "  artifact list <run-id>       List artifacts for a workflow run\n" +
  "  artifact download <run-id>   Download a specific artifact\n" +
  "\n" +
  "Cache commands:\n" +
  "  cache list                   List cache entries\n" +
  "  cache prune                  Delete cache entries\n" +
  "\n" +
  "Other commands:\n" +
  "  doctor                       Check tool dependencies\n" +
  "\n" +
  "Workflow run flags:\n" +
  "  --repo <path>                Run from a git repository\n" +
  "  --workspace <path>           Workspace root for isolated execution\n" +
  "  --workspace-mode <mode>      Execution mode: local, worktree, tmp, docker\n" +
  "  --run-root <path>            Run record storage root\n" +
  "  --event <path>               Push event JSON file\n" +
  "  --repository <owner/repo>    GitHub repository name\n" +
  "  --ref <ref>                  Git ref name\n" +
  "  --before <sha>               Before commit SHA\n" +
  "  --after <sha>                After commit SHA\n" +
  "  --changed <path>             Changed file path (repeatable)\n" +
  "  --skip-action <pattern>      Skip actions matching pattern (repeatable)\n" +
  "  --dry-run                    Show execution plan without running\n" +
  "  --local                      Shorthand for --workspace-mode local\n" +
  "  --worktree                   Shorthand for --workspace-mode worktree\n" +
  "  --tmp                        Shorthand for --workspace-mode tmp\n" +
  "  --env <file>                 Load environment variables from file\n" +
  "\n" +
  "Storage flags:\n" +
  "  --artifact-root <path>       Artifact storage root\n" +
  "  --cache-root <path>          Cache storage root\n" +
  "  --github-action-cache-root <path>  GitHub Action cache root\n" +
  "  --registry-root <path>       Action registry root\n" +
  "  --wasm-action-root <path>    Wasm action root\n" +
  "\n" +
  "Output flags:\n" +
  "  --json                       Output in JSON format\n" +
  "  --task <task-id>             Filter logs by task ID\n" +
  "  --name <name>                Artifact name for download\n" +
  "  --dir <path>                 Download destination directory\n" +
  "  --key <key>                  Cache key filter\n" +
  "  --workspace-key <key>        Workspace key filter"
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
  "_build/actrun/workspace"
}

///|
fn default_run_root() -> String {
  "_build/actrun/runs"
}

///|
fn default_workspace_mode(repo_root : String?) -> String {
  if repo_root is Some(_) {
    "tmp"
  } else {
    "local"
  }
}

///|
fn valid_workspace_mode(mode : String) -> Bool {
  mode == "local" || mode == "worktree" || mode == "tmp" || mode == "docker"
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
    Some(path) => @xsys.set_env_var("ACTRUN_ARTIFACT_ROOT", path)
    None => ()
  }
  match options.cache_root {
    Some(path) => @xsys.set_env_var("ACTRUN_CACHE_ROOT", path)
    None => ()
  }
  match options.github_action_cache_root {
    Some(path) => @xsys.set_env_var("ACTRUN_GITHUB_ACTION_CACHE_ROOT", path)
    None => ()
  }
  match options.registry_root {
    Some(path) => @xsys.set_env_var("ACTRUN_ACTION_REGISTRY_ROOT", path)
    None => ()
  }
  match options.wasm_action_root {
    Some(path) => @xsys.set_env_var("ACTRUN_WASM_ACTION_ROOT", path)
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
        // For workflows outside .github/workflows/, use current directory
        "."
      }
  }
}

///|
struct LocalWorkspace {
  execution_root : String
  cleanup_mode : String // "worktree" | "tmp" | "none"
  source_root : String // original repo root (for worktree removal)
}

///|
#cfg(target="native")
async fn setup_local_workspace(
  workspace_mode : String,
  source_root : String,
  workspace_base : String,
) -> (LocalWorkspace?, Array[String]) {
  if workspace_mode == "local" {
    return (
      Some({ execution_root: source_root, cleanup_mode: "none", source_root }),
      [],
    )
  }
  let abs_source = absolute_run_store_path(source_root)
  let abs_workspace_base = absolute_run_store_path(workspace_base)
  let timestamp = @env.now().to_string()
  let workspace_dir = join_path(abs_workspace_base, "ws-" + timestamp)
  if workspace_mode == "worktree" {
    let (code, _, stderr) = @process.collect_output(
      "git",
      ["worktree", "add", "--detach", workspace_dir],
      cwd=abs_source,
    )
    if code != 0 {
      return (
        None,
        [
          "git worktree add failed: " +
          stderr.text().trim(chars=" \t\n\r").to_string(),
        ],
      )
    }
    return (
      Some({
        execution_root: workspace_dir,
        cleanup_mode: "worktree",
        source_root: abs_source,
      }),
      [],
    )
  }
  if workspace_mode == "tmp" {
    let (code, _, stderr) = @process.collect_output(
      "git",
      ["clone", "--quiet", "--no-local", "file://" + abs_source, workspace_dir],
      cwd=".",
    )
    if code != 0 {
      return (
        None,
        ["git clone failed: " + stderr.text().trim(chars=" \t\n\r").to_string()],
      )
    }
    return (
      Some({
        execution_root: workspace_dir,
        cleanup_mode: "tmp",
        source_root: abs_source,
      }),
      [],
    )
  }
  (None, ["unsupported workspace mode: " + workspace_mode])
}

///|
#cfg(target="native")
async fn cleanup_local_workspace(workspace : LocalWorkspace) -> Unit {
  match workspace.cleanup_mode {
    "worktree" => {
      // Remove the worktree directory directly (not via git worktree remove)
      // because checkout actions may overwrite the .git pointer file,
      // causing git worktree remove to corrupt the main working tree.
      let _ = remove_tree(workspace.execution_root)
      // Clean up stale worktree references in the main repo
      let _ = @process.collect_output(
        "git",
        ["worktree", "prune"],
        cwd=workspace.source_root,
      )
    }
    "tmp" => {
      let _ = remove_tree(workspace.execution_root)
    }
    _ => ()
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
fn json_int(value : Int) -> String {
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
  let base = @xsys.get_env_var("ACTRUN_ARTIFACT_ROOT").unwrap_or(
    "_build/actrun/artifacts",
  )
  absolute_run_store_path(base + "/" + run_store_workspace_key(workspace_root))
}

///|
fn cache_store_root_for_run(workspace_root : String) -> String {
  let base = @xsys.get_env_var("ACTRUN_CACHE_ROOT").unwrap_or(
    "_build/actrun/cache",
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
fn path_file_name(path : String) -> String {
  let parts : Array[String] = []
  for part in path.split("/") {
    parts.push(part.to_string())
  }
  if parts.length() == 0 {
    ""
  } else {
    parts[parts.length() - 1]
  }
}

///|
fn workflow_name_from_path(path : String) -> String {
  let name = path_file_name(path)
  name.split(".").next().unwrap_or("").to_string()
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
    "__actrun_cache_key.txt": true,
    "__actrun_cache_sequence.txt": true,
  }
  let caches : Array[RunCacheRecord] = []
  for entry in sorted_dir_entries(store_root) {
    if entry == "__actrun_sequence.txt" {
      continue
    }
    let cache_root = join_path(store_root, entry)
    if not(run_store_is_dir(cache_root)) {
      continue
    }
    let key = match
      read_text_file(join_path(cache_root, "__actrun_cache_key.txt")) {
      Some(content) => content.trim(chars=" \t\r\n").to_string()
      None => entry
    }
    caches.push({
      key,
      sequence: read_cache_sequence(
        join_path(cache_root, "__actrun_cache_sequence.txt"),
      ),
      files: collect_relative_files(cache_root, ignored~),
    })
  }
  caches
}

///|
fn workflow_list_record_json(entry : WorkflowListRecord) -> String {
  "{ " +
  "\"name\": " +
  json_string(entry.name) +
  ", " +
  "\"path\": " +
  json_string(entry.path) +
  " }"
}

///|
fn workflow_list_json(entries : Array[WorkflowListRecord]) -> String {
  let items : Array[String] = []
  for entry in entries {
    items.push(workflow_list_record_json(entry))
  }
  "[" + items.join(", ") + "]"
}

///|
fn format_workflow_list_text(entries : Array[WorkflowListRecord]) -> String {
  let lines : Array[String] = []
  for entry in entries {
    lines.push(entry.name + "\t" + entry.path)
  }
  if lines.length() == 0 {
    ""
  } else {
    lines.join("\n") + "\n"
  }
}

///|
fn collect_workflow_list_records(
  repo_root : String,
) -> Array[WorkflowListRecord] {
  let workflow_dir = join_path(repo_root, ".github/workflows")
  if not(@xfs.path_exists(workflow_dir)) {
    return []
  }
  let records : Array[WorkflowListRecord] = []
  for entry in sorted_dir_entries(workflow_dir) {
    if not(entry.has_suffix(".yml")) && not(entry.has_suffix(".yaml")) {
      continue
    }
    let relative_path = ".github/workflows/" + entry
    let absolute_path = join_path(repo_root, relative_path)
    let name = match read_text(absolute_path) {
      Some(text) =>
        match @ar.parse_workflow_yaml(text).workflow {
          Some(workflow) =>
            if workflow.name.length() > 0 {
              workflow.name
            } else {
              workflow_name_from_path(relative_path)
            }
          None => workflow_name_from_path(relative_path)
        }
      None => workflow_name_from_path(relative_path)
    }
    records.push({ name, path: relative_path })
  }
  records
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
  "  \"exit_code\": " +
  json_int(record.exit_code) +
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
          exit_code: record.exit_code,
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
struct DotenvParseResult {
  entries : Map[String, String]
  errors : Array[String]
}

///|
fn parse_dotenv(content : String) -> DotenvParseResult {
  let entries : Map[String, String] = {}
  let errors : Array[String] = []
  let lines : Array[String] = []
  for part in content.split("\n") {
    lines.push(part.to_string())
  }
  let mut i = 0
  while i < lines.length() {
    let raw = lines[i].trim(chars="\r").to_string()
    let line = raw.trim(chars=" \t").to_string()
    if line.length() == 0 || line.has_prefix("#") {
      i += 1
      continue
    }
    // Strip optional "export " prefix
    let effective = if line.has_prefix("export ") {
      String::unsafe_substring(line, start=7, end=line.length())
      .trim(chars=" \t")
      .to_string()
    } else {
      line
    }
    guard effective.find("=") is Some(eq_idx) else {
      i += 1
      continue
    }
    let key = String::unsafe_substring(effective, start=0, end=eq_idx)
      .trim(chars=" \t")
      .to_string()
    let raw_value = String::unsafe_substring(
        effective,
        start=eq_idx + 1,
        end=effective.length(),
      )
      .trim(chars=" \t")
      .to_string()
    if key.length() == 0 {
      i += 1
      continue
    }
    // Double-quoted value: supports multiline, escapes, variable expansion
    if raw_value.has_prefix("\"") {
      let (value, next_i) = parse_dotenv_double_quoted(
        raw_value, lines, i, entries,
      )
      entries[key] = value
      i = next_i
      continue
    }
    // Single-quoted value: literal, no escapes, no expansion
    if raw_value.has_prefix("'") {
      let (value, next_i) = parse_dotenv_single_quoted(raw_value, lines, i)
      entries[key] = value
      i = next_i
      continue
    }
    // Unquoted value: strip inline comment, expand variables
    let value = dotenv_strip_inline_comment(raw_value)
    entries[key] = dotenv_expand_vars(value, entries)
    i += 1
  }
  { entries, errors }
}

///|
fn parse_dotenv_double_quoted(
  first_raw : String,
  lines : Array[String],
  start_line : Int,
  env : Map[String, String],
) -> (String, Int) {
  // Remove leading "
  let mut buf = String::unsafe_substring(
    first_raw,
    start=1,
    end=first_raw.length(),
  )
  let mut line_idx = start_line
  // Check if closing " is on the same line
  while true {
    match dotenv_find_unescaped_quote(buf) {
      Some(close_idx) => {
        let inner = String::unsafe_substring(buf, start=0, end=close_idx)
        let expanded = dotenv_expand_vars(dotenv_unescape_double(inner), env)
        return (expanded, line_idx + 1)
      }
      None => {
        line_idx += 1
        if line_idx >= lines.length() {
          // Unterminated quote: return what we have
          let expanded = dotenv_expand_vars(dotenv_unescape_double(buf), env)
          return (expanded, line_idx)
        }
        buf = buf + "\n" + lines[line_idx].trim(chars="\r").to_string()
      }
    }
  }
  // unreachable but needed for type checker
  (buf, line_idx)
}

///|
fn parse_dotenv_single_quoted(
  first_raw : String,
  lines : Array[String],
  start_line : Int,
) -> (String, Int) {
  let mut buf = String::unsafe_substring(
    first_raw,
    start=1,
    end=first_raw.length(),
  )
  let mut line_idx = start_line
  while true {
    match buf.find("'") {
      Some(close_idx) => {
        let inner = String::unsafe_substring(buf, start=0, end=close_idx)
        return (inner, line_idx + 1)
      }
      None => {
        line_idx += 1
        if line_idx >= lines.length() {
          return (buf, line_idx)
        }
        buf = buf + "\n" + lines[line_idx].trim(chars="\r").to_string()
      }
    }
  }
  // unreachable but needed for type checker
  (buf, line_idx)
}

///|
fn dotenv_unescape_double(text : String) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < text.length() {
    if text.unsafe_get(i).to_int() == '\\'.to_int() && i + 1 < text.length() {
      let next = text.unsafe_get(i + 1).to_int()
      if next == 'n'.to_int() {
        buf.write_char('\n')
        i += 2
      } else if next == 't'.to_int() {
        buf.write_char('\t')
        i += 2
      } else if next == 'r'.to_int() {
        buf.write_char('\r')
        i += 2
      } else if next == '\\'.to_int() {
        buf.write_char('\\')
        i += 2
      } else if next == '"'.to_int() {
        buf.write_char('"')
        i += 2
      } else {
        buf.write_char('\\')
        i += 1
      }
    } else {
      buf.write_char(text.unsafe_get(i).to_int().unsafe_to_char())
      i += 1
    }
  }
  buf.to_string()
}

///|
fn dotenv_strip_inline_comment(text : String) -> String {
  // Look for # preceded by whitespace (not inside value)
  let mut i = 0
  while i < text.length() {
    if text.unsafe_get(i).to_int() == '#'.to_int() && i > 0 {
      let prev = text.unsafe_get(i - 1).to_int()
      if prev == ' '.to_int() || prev == '\t'.to_int() {
        return String::unsafe_substring(text, start=0, end=i)
          .trim(chars=" \t")
          .to_string()
      }
    }
    i += 1
  }
  text
}

///|
fn dotenv_expand_vars(text : String, env : Map[String, String]) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < text.length() {
    if text.unsafe_get(i).to_int() == '$'.to_int() && i + 1 < text.length() {
      if text.unsafe_get(i + 1).to_int() == '{'.to_int() {
        // ${VAR} form
        match dotenv_find_char(text, '}', i + 2) {
          Some(close) => {
            let var_name = String::unsafe_substring(
              text,
              start=i + 2,
              end=close,
            )
            let resolved = match env.get(var_name) {
              Some(v) => v
              None => @xsys.get_env_var(var_name).unwrap_or("")
            }
            buf.write_string(resolved)
            i = close + 1
          }
          None => {
            buf.write_char('$')
            i += 1
          }
        }
      } else {
        // $VAR form
        let var_start = i + 1
        let mut var_end = var_start
        while var_end < text.length() {
          let ch = text.unsafe_get(var_end).to_int()
          if (ch >= 'A'.to_int() && ch <= 'Z'.to_int()) ||
            (ch >= 'a'.to_int() && ch <= 'z'.to_int()) ||
            (ch >= '0'.to_int() && ch <= '9'.to_int()) ||
            ch == '_'.to_int() {
            var_end += 1
          } else {
            break
          }
        }
        if var_end > var_start {
          let var_name = String::unsafe_substring(
            text,
            start=var_start,
            end=var_end,
          )
          let resolved = match env.get(var_name) {
            Some(v) => v
            None => @xsys.get_env_var(var_name).unwrap_or("")
          }
          buf.write_string(resolved)
          i = var_end
        } else {
          buf.write_char('$')
          i += 1
        }
      }
    } else {
      buf.write_char(text.unsafe_get(i).to_int().unsafe_to_char())
      i += 1
    }
  }
  buf.to_string()
}

///|
fn dotenv_find_unescaped_quote(text : String) -> Int? {
  let quote_code = '"'.to_int()
  let backslash_code = '\\'.to_int()
  let mut i = 0
  while i < text.length() {
    if text.unsafe_get(i).to_int() == backslash_code && i + 1 < text.length() {
      i += 2 // skip escaped character
    } else if text.unsafe_get(i).to_int() == quote_code {
      return Some(i)
    } else {
      i += 1
    }
  }
  None
}

///|
fn dotenv_find_char(text : String, ch : Char, start : Int) -> Int? {
  let ch_code = ch.to_int()
  let mut i = start
  while i < text.length() {
    if text.unsafe_get(i).to_int() == ch_code {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn load_env_file(path : String) -> Array[String] {
  let content = try @xfs.read_file_to_string(path) catch {
    _ => return ["failed to read env file: " + path]
  } noraise {
    value => value
  }
  let result = parse_dotenv(content)
  for key, value in result.entries {
    @xsys.set_env_var(key, value)
  }
  result.errors
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
  let skip_actions : Array[String] = []
  let mut dry_run = false
  let mut index = 1

  while index < args.length() {
    let arg = args[index]
    if arg == "--dry-run" {
      dry_run = true
      index += 1
      continue
    }
    if arg == "--tmp" {
      workspace_mode = "tmp"
      index += 1
      continue
    }
    if arg == "--worktree" {
      workspace_mode = "worktree"
      index += 1
      continue
    }
    if arg == "--local" {
      workspace_mode = "local"
      index += 1
      continue
    }
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
      arg == "--changed" ||
      arg == "--skip-action" ||
      arg == "--env" {
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
      } else if arg == "--skip-action" {
        skip_actions.push(value)
      } else if arg == "--env" {
        for err in load_env_file(value) {
          errors.push(err)
        }
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
    errors.push("workspace mode must be one of: local, worktree, tmp, docker")
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
      skip_actions,
      dry_run,
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
  if action != "list" && action != "prune" {
    return { options: None, errors: ["unknown cache subcommand: " + action] }
  }
  let mut cache_root : String? = None
  let mut key_filter = ""
  let mut workspace_key_filter = ""
  let mut json_output = false
  let mut index = 3
  while index < args.length() {
    let arg = args[index]
    if arg == "--json" {
      json_output = true
      index += 1
      continue
    }
    if arg == "--cache-root" || arg == "--key" || arg == "--workspace-key" {
      if index + 1 >= args.length() {
        errors.push("missing value for " + arg)
        break
      }
      let value = args[index + 1]
      if arg == "--cache-root" {
        cache_root = Some(value)
      } else if arg == "--key" {
        key_filter = value
      } else {
        workspace_key_filter = value
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
  if action == "prune" && key_filter.length() == 0 {
    errors.push("--key is required for `cache prune`")
  }
  if errors.length() > 0 {
    return { options: None, errors }
  }
  {
    options: Some({
      action,
      cache_root,
      key_filter,
      workspace_key_filter,
      json_output,
    }),
    errors: [],
  }
}

///|
fn parse_workflow_read_args(args : Array[String]) -> WorkflowReadParseResult {
  let errors : Array[String] = []
  if args.length() < 3 {
    return { options: None, errors: ["workflow subcommand requires an action"] }
  }
  let action = args[2]
  if action != "list" {
    return { options: None, errors: ["unknown workflow subcommand: " + action] }
  }
  let mut repo_root : String? = None
  let mut json_output = false
  let mut index = 3
  while index < args.length() {
    let arg = args[index]
    if arg == "--json" {
      json_output = true
      index += 1
      continue
    }
    if arg == "--repo" {
      if index + 1 >= args.length() {
        errors.push("missing value for --repo")
        break
      }
      repo_root = Some(args[index + 1])
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
  { options: Some({ action, repo_root, json_output }), errors: [] }
}

///|
fn parse_workflow_run_args(args : Array[String]) -> CliParseResult {
  if args.length() < 3 {
    return { options: None, errors: ["workflow subcommand requires an action"] }
  }
  let action = args[2]
  if action != "run" {
    return { options: None, errors: ["unknown workflow subcommand: " + action] }
  }
  let normalized : Array[String] = ["actrun"]
  for i in 3..<args.length() {
    normalized.push(args[i])
  }
  parse_cli_args(normalized)
}

///|
fn print_errors(errors : Array[String]) -> Unit {
  for err in errors {
    println("error: " + err)
  }
}

///|
struct DoctorCheck {
  name : String
  bin : String
  env_override : String
  required : Bool
}

///|
#cfg(target="native")
async fn handle_doctor_command() -> Int {
  let checks : Array[DoctorCheck] = [
    { name: "git", bin: "git", env_override: "ACTRUN_GIT_BIN", required: true },
    {
      name: "node",
      bin: "node",
      env_override: "ACTRUN_NODE_BIN",
      required: false,
    },
    {
      name: "docker",
      bin: "docker",
      env_override: "ACTRUN_DOCKER_BIN",
      required: false,
    },
    { name: "bash", bin: "bash", env_override: "", required: true },
    { name: "sh", bin: "sh", env_override: "", required: true },
    {
      name: "wasmtime",
      bin: "wasmtime",
      env_override: "ACTRUN_WASM_BIN",
      required: false,
    },
    {
      name: "container (apple)",
      bin: "container",
      env_override: "",
      required: false,
    },
    { name: "podman", bin: "podman", env_override: "", required: false },
    { name: "moonrun", bin: "moonrun", env_override: "", required: false },
  ]
  let mut has_error = false
  for check in checks {
    let bin = if check.env_override.length() > 0 {
      @xsys.get_env_var(check.env_override).unwrap_or(check.bin)
    } else {
      check.bin
    }
    let (code, stdout, _) = @process.collect_output(bin, ["--version"], cwd=".")
    if code == 0 {
      let version = stdout.text().trim(chars=" \t\r\n").to_string()
      let short_version = match version.find("\n") {
        Some(idx) => String::unsafe_substring(version, start=0, end=idx)
        None => version
      }
      println("ok  " + check.name + ": " + short_version)
    } else if check.required {
      println("ERR " + check.name + ": not found (required)")
      has_error = true
    } else {
      let hint = if check.env_override.length() > 0 {
        " (optional, override with " + check.env_override + ")"
      } else {
        " (optional)"
      }
      println("--  " + check.name + ": not found" + hint)
    }
  }
  // Check .github/workflows/ exists
  if @xfs.path_exists(".github/workflows") {
    let entries = try @xfs.read_dir(".github/workflows") catch {
      _ => []
    } noraise {
      value => value
    }
    let mut yml_count = 0
    for entry in entries {
      if entry.has_suffix(".yml") || entry.has_suffix(".yaml") {
        yml_count += 1
      }
    }
    println(
      "ok  workflows: " + yml_count.to_string() + " found in .github/workflows/",
    )
  } else {
    println("--  workflows: .github/workflows/ not found")
  }
  if has_error {
    1
  } else {
    0
  }
}

///|
fn print_dry_run_plan(
  workflow : @ar.WorkflowSpec,
  lowered : @ar.LoweringResult,
) -> Unit {
  println("workflow=" + workflow.name)
  println("mode=dry-run")
  println("")
  let mut current_job = ""
  for task in lowered.plan.tasks {
    if task.job_id != current_job {
      current_job = task.job_id
      println("job: " + current_job)
    }
    let kind_label = match task.action {
      Some(action) => task.kind + " (" + action.uses + ")"
      None => task.kind
    }
    let if_label = if task.if_condition.length() > 0 &&
      task.if_condition != "success()" {
      " [if: " + task.if_condition + "]"
    } else {
      ""
    }
    println("  " + task.id + ": " + kind_label + if_label)
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
        @xsys.get_env_var("ACTRUN_CACHE_ROOT").unwrap_or("_build/actrun/cache"),
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
    "__actrun_cache_key.txt": true,
    "__actrun_cache_sequence.txt": true,
  }
  let caches : Array[CacheListRecord] = []
  for workspace_key in sorted_dir_entries(cache_root_base) {
    let workspace_root = join_path(cache_root_base, workspace_key)
    if not(run_store_is_dir(workspace_root)) {
      continue
    }
    for entry in sorted_dir_entries(workspace_root) {
      if entry == "__actrun_sequence.txt" {
        continue
      }
      let cache_root = join_path(workspace_root, entry)
      if not(run_store_is_dir(cache_root)) {
        continue
      }
      let key = match
        read_text_file(join_path(cache_root, "__actrun_cache_key.txt")) {
        Some(content) => content.trim(chars=" \t\r\n").to_string()
        None => entry
      }
      caches.push({
        workspace_key,
        key,
        sequence: read_cache_sequence(
          join_path(cache_root, "__actrun_cache_sequence.txt"),
        ),
        files: collect_relative_files(cache_root, ignored~),
        store_path: cache_root,
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
fn cache_record_matches(
  record : CacheListRecord,
  options : CacheReadOptions,
) -> Bool {
  if options.key_filter.length() > 0 && record.key != options.key_filter {
    return false
  }
  if options.workspace_key_filter.length() > 0 &&
    record.workspace_key != options.workspace_key_filter {
    return false
  }
  true
}

///|
fn remove_tree(path : String) -> Bool {
  try {
    if not(@xfs.path_exists(path)) {
      return true
    }
    if @xfs.is_dir(path) {
      for entry in @xfs.read_dir(path) {
        if not(remove_tree(join_path(path, entry))) {
          return false
        }
      }
      @xfs.remove_dir(path)
      true
    } else {
      @xfs.remove_file(path)
      true
    }
  } catch {
    _ => false
  } noraise {
    value => value
  }
}

///|
fn prune_empty_workspace_cache_dirs(cache_root_base : String) -> Unit {
  if not(@xfs.path_exists(cache_root_base)) {
    return
  }
  for workspace_key in sorted_dir_entries(cache_root_base) {
    let workspace_dir = join_path(cache_root_base, workspace_key)
    if not(run_store_is_dir(workspace_dir)) {
      continue
    }
    let entries = sorted_dir_entries(workspace_dir)
    if entries.length() == 0 {
      ignore(try? @xfs.remove_dir(workspace_dir))
    }
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
  let exit_code = run_json_number_text(payload, "exit_code")
  if exit_code.length() > 0 {
    lines.push("exit_code=\{exit_code}")
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
fn read_optional_text(path : String) -> String? {
  match read_text(path) {
    Some(text) => Some(text.trim_end(chars="\n").to_string())
    None => None
  }
}

///|
fn run_task_logs_json(
  run_dir : String,
  run_json_text : String,
  task_id? : String? = None,
) -> String? {
  let payload = @json.parse(run_json_text) catch { _ => return None }
  guard payload is Object(_) else { return None }
  let items : Array[String] = []
  let mut matched_task = task_id is None
  for task_json in run_json_array(payload, "tasks") {
    guard task_json is { "id": String(id), .. } else { continue }
    match task_id {
      Some(expected) if expected != id => continue
      Some(_) => matched_task = true
      None => ()
    }
    let stdout_path = run_json_string(task_json, "stdout_path")
    let stdout = if stdout_path.length() > 0 {
      read_optional_text(join_path(run_dir, stdout_path)).unwrap_or("")
    } else {
      ""
    }
    let stderr_path = run_json_string(task_json, "stderr_path")
    let stderr = if stderr_path.length() > 0 {
      read_optional_text(join_path(run_dir, stderr_path)).unwrap_or("")
    } else {
      ""
    }
    let summary : String? = match run_json_field(task_json, "summary_path") {
      Some(String(summary_path)) if summary_path.length() > 0 =>
        read_optional_text(join_path(run_dir, summary_path))
      _ => None
    }
    items.push(
      "{ " +
      "\"task_id\": " +
      json_string(id) +
      ", " +
      "\"stdout\": " +
      json_string(stdout) +
      ", " +
      "\"stderr\": " +
      json_string(stderr) +
      ", " +
      "\"summary\": " +
      json_optional_string(summary) +
      " }",
    )
  }
  if not(matched_task) {
    return None
  }
  Some("{ \"tasks\": [" + items.join(", ") + "] }")
}

///|
fn artifact_download_json(
  artifact_name : String,
  download_dir : String,
  files : Array[String],
) -> String {
  "{ " +
  "\"artifact\": " +
  json_string(artifact_name) +
  ", " +
  "\"dir\": " +
  json_string(download_dir) +
  ", " +
  "\"files\": " +
  json_string_array(files) +
  " }"
}

///|
fn run_download_json(
  run_id : String,
  download_dir : String,
  artifacts : Array[String],
) -> String {
  "{ " +
  "\"run_id\": " +
  json_string(run_id) +
  ", " +
  "\"dir\": " +
  json_string(download_dir) +
  ", " +
  "\"artifacts\": " +
  json_string_array(artifacts) +
  " }"
}

///|
fn handle_workflow_read_command(options : WorkflowReadOptions) -> Int {
  if options.action != "list" {
    print_errors(["unknown workflow subcommand: " + options.action])
    return 1
  }
  let repo_root = absolute_run_store_path(options.repo_root.unwrap_or("."))
  let records = collect_workflow_list_records(repo_root)
  if options.json_output {
    println(workflow_list_json(records))
    return 0
  }
  let text = format_workflow_list_text(records)
  if text.length() > 0 {
    println(text.trim_end(chars="\n").to_string())
  }
  0
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
  if options.json_output {
    println(artifact_download_json(options.artifact_name, download_dir, copied))
    return 0
  }
  println("artifact=\{options.artifact_name}")
  println("dir=\{download_dir}")
  println("files=\{copied_text}")
  0
}

///|
fn handle_cache_read_command(options : CacheReadOptions) -> Int {
  if options.action != "list" && options.action != "prune" {
    print_errors(["unknown cache subcommand: " + options.action])
    return 1
  }
  let cache_root = cache_store_base_root_for_read(options.cache_root)
  let caches = collect_cache_list_records(cache_root)
  let filtered : Array[CacheListRecord] = []
  for cache in caches {
    if cache_record_matches(cache, options) {
      filtered.push(cache)
    }
  }
  if options.action == "prune" {
    for cache in filtered {
      if not(remove_tree(cache.store_path)) {
        print_errors(["failed to remove cache " + cache.key])
        return 1
      }
    }
    prune_empty_workspace_cache_dirs(cache_root)
  }
  if options.json_output {
    println(cache_list_json(filtered))
    return 0
  }
  let text = format_cache_list_text(filtered)
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
  if options.json_output {
    println(run_download_json(options.run_id, download_dir, downloaded))
    return 0
  }
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
fn run_state_exit_code(state : String) -> Int {
  if state == "completed" || state == "success" || state == "skipped" {
    0
  } else {
    1
  }
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
      let exit_code_text = run_json_number_text(payload, "exit_code")
      let exit_code = if exit_code_text.length() > 0 {
        let parsed = @strconv.parse_int64(exit_code_text) catch {
          _ => return run_state_exit_code(state)
        }
        parsed.to_int()
      } else {
        run_state_exit_code(state)
      }
      if options.json_output {
        println(run_json_text.trim_end(chars="\n").to_string())
        return exit_code
      }
      match format_run_view_text(run_json_text) {
        Some(text) => {
          println(text.trim_end(chars="\n").to_string())
          return exit_code
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
  if options.json_output {
    match run_task_logs_json(run_dir, run_json_text, task_id=options.task_id) {
      Some(text) => {
        println(text)
        return 0
      }
      None => {
        match options.task_id {
          Some(task_id) =>
            print_errors([
              "task logs not found for " + task_id + " in " + run_dir,
            ])
          None => print_errors(["failed to parse " + run_json_path])
        }
        return 1
      }
    }
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
async fn handle_workflow_run_command(options : CliOptions) -> Int {
  let run_started_at_ms = @env.now()
  apply_cli_root_overrides(options)
  let run_root = options.run_root.unwrap_or(default_run_root())
  let workspace_mode = resolved_workspace_mode(options)
  if options.repo_root is Some(_) {
    if workspace_mode != "tmp" {
      print_errors([
        "workspace mode '\{workspace_mode}' is not implemented yet for --repo execution",
      ])
      return 1
    }
  } else if workspace_mode == "docker" {
    print_errors([
      "workspace mode 'docker' is not implemented yet for local workflow execution",
    ])
    return 1
  }

  let mut workflow_path = options.workflow_path
  let source_root = local_workspace_root(workflow_path)
  let mut execution_root = source_root
  let mut local_workspace : LocalWorkspace? = None
  if options.repo_root is None && workspace_mode != "local" {
    let workspace_base = options.workspace_root.unwrap_or(
      default_workspace_root(),
    )
    let (ws, ws_errors) = setup_local_workspace(
      workspace_mode, source_root, workspace_base,
    )
    if ws_errors.length() > 0 {
      print_errors(ws_errors)
      return 1
    }
    guard ws is Some(workspace) else {
      print_errors(["failed to setup workspace"])
      return 1
    }
    execution_root = workspace.execution_root
    workflow_path = join_path(execution_root, options.workflow_path)
    local_workspace = Some(workspace)
  }
  let base_event = match options.event_path {
    Some(event_path) =>
      match read_text(event_path) {
        Some(event_text) => {
          let parsed_event = @ar.parse_github_push_event_json(event_text)
          if parsed_event.errors.length() > 0 {
            print_errors(parsed_event.errors)
            return 1
          }
          parsed_event.event.unwrap()
        }
        None => {
          print_errors(["failed to read " + event_path])
          return 1
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
      return 1
    }
    guard workspace_result.workspace is Some(workspace) else {
      print_errors(["failed to materialize bit workspace"])
      return 1
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
        return 1
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
      print_errors(["failed to read " + workflow_path])
      return 1
    }
  }

  let parsed = @ar.parse_workflow_yaml(text)
  if parsed.errors.length() > 0 {
    print_errors(parsed.errors)
    return 1
  }
  guard parsed.workflow is Some(workflow) else {
    print_errors(["workflow parse failed"])
    return 1
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
      exit_code: 0,
      repository,
      ref_name: trigger_event.ref_name,
      before_sha: trigger_event.before_sha,
      after_sha: trigger_event.after_sha,
      changed_paths: trigger_event.changed_paths,
    })
    let skipped_run_id = skipped_run_dir.unwrap_or("")
    print_skipped_report(workflow.name, skipped_run_id)
    return 0
  }

  // Strip unsupported fields and filter skipped actions
  let should_strip = options.skip_actions.length() > 0 || options.dry_run
  let stripped_workflow = if should_strip {
    @ar.strip_unsupported_workflow_fields(workflow)
  } else {
    workflow
  }
  let effective_workflow = if options.skip_actions.length() > 0 {
    @ar.filter_workflow_steps(stripped_workflow, options.skip_actions)
  } else {
    stripped_workflow
  }

  if options.dry_run {
    let lowered = @ar.lower_push_workflow_in_workspace(
      effective_workflow, execution_root,
    )
    if lowered.errors.length() > 0 {
      for err in lowered.errors {
        println("warning: " + err)
      }
    }
    print_dry_run_plan(effective_workflow, lowered)
    return 0
  }

  let prefetch = @ar.prefetch_workflow_github_actions_native(
    effective_workflow, execution_root,
  )
  if prefetch.errors.length() > 0 {
    print_errors(prefetch.errors)
    return 1
  }

  let lowered = @ar.lower_push_workflow_in_workspace(
    effective_workflow, execution_root,
  )
  if lowered.errors.length() > 0 {
    print_errors(lowered.errors)
    return 1
  }

  let raw_report = @ar.execute_lowered_native(
    lowered,
    workspace_root=execution_root,
    push_event=Some(trigger_event),
  )
  let report = @ar.mask_report_secrets(raw_report, @ar.collect_secret_values())
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
      exit_code: if report.ok {
        0
      } else {
        run_state_exit_code(report.state)
      },
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
  @ar.cleanup_run_temp_files(execution_root)
  match local_workspace {
    Some(ws) => cleanup_local_workspace(ws)
    None => ()
  }
  if not(report.ok) {
    return 1
  }
  0
}

///|
#cfg(target="native")
async fn main {
  let cli_args = @xsys.get_cli_args()
  if cli_args.length() <= 1 ||
    (
      cli_args.length() > 1 &&
      (cli_args[1] == "--help" || cli_args[1] == "-h" || cli_args[1] == "help")
    ) {
    println(usage_text())
    return
  }
  if cli_args.length() > 1 && cli_args[1] == "doctor" {
    let exit_code = handle_doctor_command()
    if exit_code != 0 {
      @xsys.exit(exit_code)
    }
    return
  }
  if cli_args.length() > 1 && cli_args[1] == "workflow" {
    if cli_args.length() < 3 {
      print_errors(["workflow subcommand requires an action"])
      @xsys.exit(1)
    }
    if cli_args[2] == "list" {
      let parsed_workflow_args = parse_workflow_read_args(cli_args)
      if parsed_workflow_args.errors.length() > 0 {
        print_errors(parsed_workflow_args.errors)
        @xsys.exit(1)
      }
      guard parsed_workflow_args.options is Some(workflow_options) else {
        print_errors([usage_text()])
        @xsys.exit(1)
      }
      let exit_code = handle_workflow_read_command(workflow_options)
      if exit_code != 0 {
        @xsys.exit(exit_code)
      }
      return
    }
    if cli_args[2] == "run" {
      let parsed_workflow_run_args = parse_workflow_run_args(cli_args)
      if parsed_workflow_run_args.errors.length() > 0 {
        print_errors(parsed_workflow_run_args.errors)
        @xsys.exit(1)
      }
      guard parsed_workflow_run_args.options is Some(workflow_run_options) else {
        print_errors([usage_text()])
        @xsys.exit(1)
      }
      let exit_code = handle_workflow_run_command(workflow_run_options)
      if exit_code != 0 {
        @xsys.exit(exit_code)
      }
      return
    }
    print_errors(["unknown workflow subcommand: " + cli_args[2]])
    @xsys.exit(1)
  }
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

  // Shorthand: actrun <workflow.yml> is equivalent to actrun workflow run <workflow.yml>
  let parsed_args = parse_cli_args(cli_args)
  if parsed_args.errors.length() > 0 {
    print_errors(parsed_args.errors)
    @xsys.exit(1)
  }
  guard parsed_args.options is Some(options) else {
    print_errors([usage_text()])
    @xsys.exit(1)
  }
  let exit_code = handle_workflow_run_command(options)
  if exit_code != 0 {
    @xsys.exit(exit_code)
  }
}

///|
#cfg(not(target="native"))
fn main {
  println("actrun CLI execute is supported on native target only")
}
