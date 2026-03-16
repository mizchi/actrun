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
  dispatch_inputs : Map[String, String]
  dry_run : Bool
  trust_actions : Bool
  nix_mode : String
  nix_packages : Array[String]
  container_runtime : String
  affected : Bool
  affected_base : String
  retry : Bool
  job_filter : String
  step_filter : String
  trigger : String
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
  max_age_days : Int
  prune_all : Bool
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
  "  list [patterns...]           List workflows and their run commands\n" +
  "  cron [show|install|uninstall] Manage cron schedules from workflows\n" +
  "  init                         Create actrun.toml config file\n" +
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
  "  --input <key=value>          Set workflow_dispatch input (repeatable)\n" +
  "  --trust                      Trust all third-party actions without prompt\n" +
  "  --env <file>                 Load environment variables from file\n" +
  "  --nix                        Force nix-shell wrapping for run steps\n" +
  "  --no-nix                     Disable nix wrapping even if flake.nix/shell.nix exists\n" +
  "  --nix-packages <pkgs>        Additional nix packages (space-separated)\n" +
  "  --container-runtime <name>   Container runtime: docker, podman, container, lima, nerdctl\n" +
  "  --affected [base]             Only run if files matching patterns changed (default: last success, or rev like HEAD~3)\n" +
  "  --retry                      Re-run only failed jobs from the latest run\n" +
  "  --job <id>                   Run only the specified job\n" +
  "  --step <id>                  Run only the specified step (use with --job)\n" +
  "  --trigger <event>            Force trigger type: push, pull_request, schedule, workflow_dispatch\n" +
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
        // For workflows outside .github/workflows/, use the workflow's
        // parent directory as workspace root so that relative references
        // (e.g. reusable workflows) resolve correctly
        workflow_parent_dir(workflow_path)
      }
  }
}

///|
fn workflow_parent_dir(path : String) -> String {
  let mut last_slash = -1
  for i = 0; i < path.length(); i = i + 1 {
    if path.unsafe_get(i) == '/' {
      last_slash = i
    }
  }
  if last_slash <= 0 {
    "."
  } else {
    String::unsafe_substring(path, start=0, end=last_slash)
  }
}

///|
struct LocalWorkspace {
  execution_root : String
  cleanup_mode : String // "worktree" | "tmp" | "none"
  source_root : String // original repo root (for worktree removal)
}

///|
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
    let (code, _, stderr) = run_command(
      "git",
      ["worktree", "add", "--detach", workspace_dir],
      cwd=abs_source,
    )
    if code != 0 {
      return (
        None,
        ["git worktree add failed: " + stderr.trim(chars=" \t\n\r").to_string()],
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
    let (code, _, stderr) = run_command(
      "git",
      ["clone", "--quiet", "--no-local", "file://" + abs_source, workspace_dir],
      cwd=".",
    )
    if code != 0 {
      return (
        None,
        ["git clone failed: " + stderr.trim(chars=" \t\n\r").to_string()],
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
async fn cleanup_local_workspace(workspace : LocalWorkspace) -> Unit {
  match workspace.cleanup_mode {
    "worktree" => {
      // Remove the worktree directory directly (not via git worktree remove)
      // because checkout actions may overwrite the .git pointer file,
      // causing git worktree remove to corrupt the main working tree.
      let _ = remove_tree(workspace.execution_root)
      // Clean up stale worktree references in the main repo
      let _ = run_command(
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
struct ActrunConfig {
  workspace_mode : String
  local_skip_actions : Array[String]
  trust_actions : Bool
  nix_mode : String
  nix_packages : Array[String]
  container_runtime : String
  affected : Map[String, Array[String]]
  includes : Array[String]
}

///|
fn default_actrun_config() -> ActrunConfig {
  {
    workspace_mode: "",
    local_skip_actions: [],
    trust_actions: false,
    nix_mode: "",
    nix_packages: [],
    container_runtime: "",
    affected: {},
    includes: [],
  }
}

///|
async fn generate_actrun_config() -> String {
  // Detect available tools and generate a config with sensible defaults
  let skip : Array[String] = []
  // Always suggest skipping checkout for local runs
  skip.push("actions/checkout")
  // Detect local toolchains and suggest skipping their setup actions
  let tool_checks : Array[(String, String, String)] = [
    ("node", "--version", "actions/setup-node"),
    ("python3", "--version", "actions/setup-python"),
    ("go", "version", "actions/setup-go"),
    ("java", "-version", "actions/setup-java"),
    ("rustup", "--version", "actions-rust-lang/setup-rust-toolchain"),
  ]
  let detected_tools : Array[String] = []
  for check in tool_checks {
    let (tool, flag, action) = check
    let (code, _, _) = run_command(tool, [flag], cwd=".")
    if code == 0 {
      skip.push(action)
      detected_tools.push(tool)
    }
  }
  let mut config = "# actrun configuration file\n" +
    "# Generated by: actrun init\n\n"
  config = config + "# Workspace mode: local, worktree, tmp, docker\n"
  config = config + "# workspace_mode = \"local\"\n\n"
  // skip_actions with detected tools
  if skip.length() > 0 {
    let items : Array[String] = []
    for s in skip {
      items.push("\"" + s + "\"")
    }
    config = config + "# Skip setup actions — use local toolchain instead\n"
    if detected_tools.length() > 0 {
      config = config + "# Detected: " + detected_tools.join(", ") + "\n"
    }
    config = config + "local_skip_actions = [" + items.join(", ") + "]\n\n"
  }
  config = config + "# Trust all third-party actions without prompt\n"
  config = config + "# trust_actions = true\n\n"
  // nix
  if @xfs.path_exists("flake.nix") {
    config = config +
      "# Nix: flake.nix detected, auto-detection enabled by default\n"
    config = config + "# nix_mode = \"\"\n\n"
  } else if @xfs.path_exists("shell.nix") {
    config = config +
      "# Nix: shell.nix detected, auto-detection enabled by default\n"
    config = config + "# nix_mode = \"\"\n\n"
  } else {
    config = config +
      "# Nix integration: \"auto\" (force), \"off\" (disable), or empty (auto-detect)\n"
    config = config + "# nix_mode = \"\"\n\n"
  }
  config = config + "# Additional nix packages\n"
  config = config + "# nix_packages = [\"python312\", \"jq\"]\n\n"
  // container runtime
  let runtimes = ["docker", "podman", "nerdctl"]
  let mut detected_runtime = ""
  for rt in runtimes {
    let (code, _, _) = run_command(rt, ["--version"], cwd=".")
    if code == 0 {
      detected_runtime = rt
      break
    }
  }
  if detected_runtime.length() > 0 {
    config = config +
      "# Container runtime (detected: " +
      detected_runtime +
      ")\n"
    config = config + "# container_runtime = \"" + detected_runtime + "\"\n"
  } else {
    config = config +
      "# Container runtime: docker, podman, container, lima, nerdctl\n"
    config = config + "# container_runtime = \"docker\"\n"
  }
  config = config + "\n# Additional workflow file patterns for `actrun list`\n"
  config = config +
    "# includes = [\".github/workflows/*.yml\", \"ci/**/*.yaml\"]\n"
  config = config + "\n# Affected file patterns per workflow (optional)\n"
  config = config +
    "# If not set, on:push:paths from workflow is used as fallback\n"
  config = config + "# [affected.\"ci.yml\"]\n"
  config = config + "# patterns = [\"src/**\", \"package.json\"]\n"
  config
}

///|
struct TomlParseResult {
  entries : Map[String, String]
  arrays : Map[String, Array[String]]
}

///|
/// Normalize TOML section key: strip quotes from dotted keys.
/// "affected.\"ci.yml\"" → "affected.ci.yml"
/// "affected.\".github/workflows/ci.yml\"" → "affected..github/workflows/ci.yml"
fn toml_normalize_section(raw : String) -> String {
  let parts : Array[String] = []
  let mut idx = 0
  let mut start = 0
  while idx < raw.length() {
    let ch = raw.unsafe_get(idx)
    if ch == '"' {
      // Read quoted segment
      idx += 1
      let qstart = idx
      while idx < raw.length() && raw.unsafe_get(idx) != '"' {
        idx += 1
      }
      parts.push(String::unsafe_substring(raw, start=qstart, end=idx))
      if idx < raw.length() {
        idx += 1 // skip closing quote
      }
      // skip dot after quote
      if idx < raw.length() && raw.unsafe_get(idx) == '.' {
        idx += 1
      }
      start = idx
    } else if ch == '.' {
      if idx > start {
        parts.push(
          String::unsafe_substring(raw, start~, end=idx)
          .trim(chars=" \t")
          .to_string(),
        )
      }
      idx += 1
      start = idx
    } else {
      idx += 1
    }
  }
  if start < raw.length() {
    parts.push(
      String::unsafe_substring(raw, start~, end=raw.length())
      .trim(chars=" \t")
      .to_string(),
    )
  }
  parts.join(".")
}

///|
fn parse_toml_minimal(content : String) -> TomlParseResult {
  let entries : Map[String, String] = {}
  let arrays : Map[String, Array[String]] = {}
  let mut section = ""
  for part in content.split("\n") {
    let raw = part.to_string().trim(chars="\r").to_string()
    let line = raw.trim(chars=" \t").to_string()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    // Parse section headers: [section], [section."key"], [section."path/key"]
    if line.has_prefix("[") && line.has_suffix("]") {
      let raw_section = String::unsafe_substring(
          line,
          start=1,
          end=line.length() - 1,
        )
        .trim(chars=" \t")
        .to_string()
      // Normalize quoted keys: [affected."ci.yml"] → affected.ci.yml
      section = toml_normalize_section(raw_section)
      continue
    }
    match line.find("=") {
      None => continue
      Some(eq_idx) => {
        let raw_key = String::unsafe_substring(line, start=0, end=eq_idx)
          .trim(chars=" \t")
          .to_string()
        let key = if section.length() > 0 {
          section + "." + raw_key
        } else {
          raw_key
        }
        let val_raw = String::unsafe_substring(
            line,
            start=eq_idx + 1,
            end=line.length(),
          )
          .trim(chars=" \t")
          .to_string()
        if val_raw.has_prefix("[") {
          // Parse array: ["item1", "item2"]
          let items : Array[String] = []
          let inner = if val_raw.has_suffix("]") {
            String::unsafe_substring(val_raw, start=1, end=val_raw.length() - 1)
          } else {
            String::unsafe_substring(val_raw, start=1, end=val_raw.length())
          }
          for item_view in inner.split(",") {
            let item = item_view.to_string().trim(chars=" \t\"'").to_string()
            if item.length() > 0 {
              items.push(item)
            }
          }
          arrays[key] = items
        } else if val_raw == "true" || val_raw == "false" {
          entries[key] = val_raw
        } else if val_raw.has_prefix("\"") &&
          val_raw.has_suffix("\"") &&
          val_raw.length() >= 2 {
          entries[key] = String::unsafe_substring(
            val_raw,
            start=1,
            end=val_raw.length() - 1,
          )
        } else {
          entries[key] = val_raw
        }
      }
    }
  }
  { entries, arrays }
}

///|
let known_config_keys : Array[String] = [
  "workspace_mode", "local_skip_actions", "trust_actions", "nix_mode", "nix_packages",
  "container_runtime", "includes",
]

///|
fn is_known_config_key(key : String) -> Bool {
  // Allow any key under [affected.*] section
  if key.has_prefix("affected.") {
    return true
  }
  for k in known_config_keys {
    if k == key {
      return true
    }
  }
  false
}

///|
fn load_actrun_config(dir : String) -> ActrunConfig {
  let config_path = if dir == "." || dir == "" {
    "actrun.toml"
  } else {
    dir + "/actrun.toml"
  }
  if not(@xfs.path_exists(config_path)) {
    return default_actrun_config()
  }
  let content = try @xfs.read_file_to_string(config_path) catch {
    _ => return default_actrun_config()
  } noraise {
    value => value
  }
  let parsed = parse_toml_minimal(content)
  // Warn on unknown keys
  for key, _ in parsed.entries {
    if not(is_known_config_key(key)) {
      println("warning: unknown key '" + key + "' in " + config_path)
    }
  }
  for key, _ in parsed.arrays {
    if not(is_known_config_key(key)) {
      println("warning: unknown key '" + key + "' in " + config_path)
    }
  }
  {
    workspace_mode: parsed.entries.get("workspace_mode").unwrap_or(""),
    local_skip_actions: parsed.arrays.get("local_skip_actions").unwrap_or([]),
    trust_actions: parsed.entries.get("trust_actions").unwrap_or("false") ==
    "true",
    nix_mode: parsed.entries.get("nix_mode").unwrap_or(""),
    nix_packages: parsed.arrays.get("nix_packages").unwrap_or([]),
    container_runtime: parsed.entries.get("container_runtime").unwrap_or(""),
    affected: {
      let result : Map[String, Array[String]] = {}
      // Parse affected keys: "affected.WORKFLOW.patterns" → workflow → patterns
      // After section normalization, key is e.g.:
      //   "affected.ci.yml.patterns" (from [affected."ci.yml"])
      //   "affected..github/workflows/ci.yml.patterns"
      let prefix = "affected."
      let suffix = ".patterns"
      for key, patterns in parsed.arrays {
        if key.has_prefix(prefix) && key.has_suffix(suffix) {
          let wf = String::unsafe_substring(
            key,
            start=prefix.length(),
            end=key.length() - suffix.length(),
          )
          if wf.length() > 0 {
            result[wf] = patterns
          }
        }
      }
      result
    },
    includes: parsed.arrays.get("includes").unwrap_or([]),
  }
}

///|
fn merge_config_into_options(
  options : CliOptions,
  config : ActrunConfig,
) -> CliOptions {
  {
    workflow_path: options.workflow_path,
    repo_root: options.repo_root,
    workspace_root: options.workspace_root,
    run_root: options.run_root,
    artifact_root: options.artifact_root,
    cache_root: options.cache_root,
    github_action_cache_root: options.github_action_cache_root,
    registry_root: options.registry_root,
    wasm_action_root: options.wasm_action_root,
    workspace_mode: if options.workspace_mode.length() > 0 {
      options.workspace_mode
    } else {
      config.workspace_mode
    },
    event_path: options.event_path,
    repository: options.repository,
    ref_name: options.ref_name,
    before_sha: options.before_sha,
    after_sha: options.after_sha,
    changed_paths: options.changed_paths,
    skip_actions: if options.skip_actions.length() > 0 {
      options.skip_actions
    } else {
      config.local_skip_actions
    },
    dispatch_inputs: options.dispatch_inputs,
    dry_run: options.dry_run,
    trust_actions: if options.trust_actions {
      true
    } else {
      config.trust_actions
    },
    nix_mode: if options.nix_mode.length() > 0 {
      options.nix_mode
    } else {
      config.nix_mode
    },
    nix_packages: if options.nix_packages.length() > 0 {
      options.nix_packages
    } else {
      config.nix_packages
    },
    container_runtime: if options.container_runtime.length() > 0 {
      options.container_runtime
    } else {
      config.container_runtime
    },
    affected: options.affected,
    affected_base: options.affected_base,
    retry: options.retry,
    job_filter: options.job_filter,
    step_filter: options.step_filter,
    trigger: options.trigger,
  }
}

///|
/// Find the latest run record for a workflow path from run store
fn find_latest_run_for_workflow(
  run_root : String,
  workflow_path : String,
  ok_only : Bool,
) -> (Json, String)? {
  if not(@xfs.path_exists(run_root)) {
    return None
  }
  let entries = try @xfs.read_dir(run_root) catch {
    _ => return None
  } noraise {
    value => value
  }
  // Sort descending by index
  let sorted : Array[String] = []
  for entry in entries {
    if entry.has_prefix("run-") {
      sorted.push(entry)
    }
  }
  // Reverse iterate (highest index = latest)
  for i in 0..<sorted.length() {
    let entry = sorted[sorted.length() - 1 - i]
    let run_json_path = join_path(join_path(run_root, entry), "run.json")
    let text = match read_text(run_json_path) {
      Some(t) => t
      None => continue
    }
    let payload = @json.parse(text) catch { _ => continue }
    let wf_path = run_json_string(payload, "workflow_path")
    if wf_path != workflow_path {
      continue
    }
    if ok_only {
      let ok_str = match run_json_field(payload, "ok") {
        Some(True) => "true"
        _ => "false"
      }
      if ok_str != "true" {
        continue
      }
    }
    return Some((payload, entry))
  }
  None
}

///|
/// Get changed files between two git refs
async fn git_diff_files(base : String, head : String) -> Array[String] {
  let (code, stdout, _) = run_command(
    "git",
    ["diff", "--name-only", base, head],
    cwd=".",
  )
  if code != 0 {
    return []
  }
  let files : Array[String] = []
  for line_view in stdout.split("\n") {
    let line = line_view.trim(chars=" \t\r\n").to_string()
    if line.length() > 0 {
      files.push(line)
    }
  }
  files
}

///|
/// Get uncommitted changes (staged + unstaged)
async fn git_uncommitted_files() -> Array[String] {
  let (code, stdout, _) = run_command(
    "git",
    ["diff", "--name-only", "HEAD"],
    cwd=".",
  )
  let files : Array[String] = []
  if code == 0 {
    for line_view in stdout.split("\n") {
      let line = line_view.trim(chars=" \t\r\n").to_string()
      if line.length() > 0 {
        files.push(line)
      }
    }
  }
  // Also include untracked files
  let (code2, stdout2, _) = run_command(
    "git",
    ["ls-files", "--others", "--exclude-standard"],
    cwd=".",
  )
  if code2 == 0 {
    for line_view in stdout2.split("\n") {
      let line = line_view.trim(chars=" \t\r\n").to_string()
      if line.length() > 0 {
        files.push(line)
      }
    }
  }
  files
}

///|
/// Check if any changed file matches the glob patterns (simple prefix/suffix match)
fn files_match_patterns(
  files : Array[String],
  patterns : Array[String],
) -> Bool {
  for file in files {
    for pattern in patterns {
      if glob_match(pattern, file) {
        return true
      }
    }
  }
  false
}

///|
/// Simple glob matching: supports * (any chars), ** (any path), prefix/suffix match
fn glob_match(pattern : String, path : String) -> Bool {
  if pattern == "*" || pattern == "**" || pattern == "**/*" {
    return true
  }
  // "src/**" → path starts with "src/"
  if pattern.has_suffix("/**") {
    let prefix = String::unsafe_substring(
      pattern,
      start=0,
      end=pattern.length() - 3,
    )
    return path.has_prefix(prefix + "/") || path == prefix
  }
  // "**/*.rs" → path ends with ".rs"
  if pattern.has_prefix("**/") {
    let suffix = String::unsafe_substring(
      pattern,
      start=3,
      end=pattern.length(),
    )
    // suffix could be "*.rs"
    if suffix.has_prefix("*") {
      let ext = String::unsafe_substring(suffix, start=1, end=suffix.length())
      return path.has_suffix(ext)
    }
    return path.has_suffix("/" + suffix) || path == suffix
  }
  // "*.rs" → path ends with ".rs"
  if pattern.has_prefix("*") {
    let ext = String::unsafe_substring(pattern, start=1, end=pattern.length())
    return path.has_suffix(ext)
  }
  // Directory wildcard (non-recursive): src/* matches src/foo but not src/sub/foo
  if pattern.has_suffix("/*") {
    let prefix = String::unsafe_substring(
        pattern,
        start=0,
        end=pattern.length() - 2,
      ) +
      "/"
    if not(path.has_prefix(prefix)) {
      return false
    }
    // Check no further "/" after prefix
    let rest = String::unsafe_substring(
      path,
      start=prefix.length(),
      end=path.length(),
    )
    return not(rest.contains("/"))
  }
  // "dir/*.ext" → path starts with "dir/" and ends with ".ext", no subdirs
  if pattern.contains("/*") {
    match pattern.find("/*") {
      Some(star_idx) => {
        let dir_prefix = String::unsafe_substring(
            pattern,
            start=0,
            end=star_idx,
          ) +
          "/"
        let ext_part = String::unsafe_substring(
          pattern,
          start=star_idx + 2,
          end=pattern.length(),
        )
        if not(path.has_prefix(dir_prefix)) {
          return false
        }
        let rest = String::unsafe_substring(
          path,
          start=dir_prefix.length(),
          end=path.length(),
        )
        if rest.contains("/") {
          return false
        }
        return if ext_part.length() > 0 {
          rest.has_suffix(ext_part)
        } else {
          true
        }
      }
      None => ()
    }
  }
  path == pattern || path.has_prefix(pattern + "/")
}

///|
/// Extract failed job IDs from a run record JSON
fn extract_failed_job_ids(run_json : Json) -> Array[String] {
  let failed_jobs : Array[String] = []
  match run_json {
    Object(obj) =>
      match obj.get("steps") {
        Some(Array(steps)) =>
          for step in steps {
            match step {
              Object(_) => {
                let status = run_json_string(step, "status")
                let id = run_json_string(step, "id")
                if status == "failed" && id.length() > 0 {
                  // id is "job_id/step_id" → extract job_id
                  match id.find("/") {
                    Some(slash) => {
                      let job_id = String::unsafe_substring(
                        id,
                        start=0,
                        end=slash,
                      )
                      let mut already = false
                      for j in failed_jobs {
                        if j == job_id {
                          already = true
                          break
                        }
                      }
                      if not(already) {
                        failed_jobs.push(job_id)
                      }
                    }
                    None => ()
                  }
                }
              }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  failed_jobs
}

///|
fn resolve_container_runtime_bin(runtime : String) -> (String, Array[String]) {
  if runtime == "docker" || runtime == "" {
    return ("docker", [])
  }
  if runtime == "podman" {
    return ("podman", [])
  }
  if runtime == "nerdctl" {
    return ("nerdctl", [])
  }
  if runtime == "container" {
    return ("container", [])
  }
  if runtime == "lima" {
    return ("lima", ["nerdctl"])
  }
  // Custom binary path
  (runtime, [])
}

///|
async fn apply_container_runtime(options : CliOptions) -> Unit {
  let runtime = options.container_runtime
  if runtime.length() == 0 {
    return
  }
  let (bin, prefix_args) = resolve_container_runtime_bin(runtime)
  if prefix_args.length() > 0 {
    // For lima: generate wrapper script so all docker calls go through "lima nerdctl ..."
    let wrapper_path = "/tmp/actrun-container-wrapper"
    let inner = prefix_args.join(" ")
    let script = "#!/bin/sh\nexec " + bin + " " + inner + " \"$@\"\n"
    try @xfs.write_string_to_file(wrapper_path, script) catch {
      _ => {
        println("warning: failed to create container wrapper script")
        @xsys.set_env_var("ACTRUN_CONTAINER_RUNTIME", bin)
        return
      }
    } noraise {
      _ => ()
    }
    ignore(run_command("chmod", ["+x", wrapper_path], cwd="."))
    @xsys.set_env_var("ACTRUN_CONTAINER_RUNTIME", wrapper_path)
  } else {
    @xsys.set_env_var("ACTRUN_CONTAINER_RUNTIME", bin)
  }
}

///|
async fn handle_init_command() -> Int {
  if @xfs.path_exists("actrun.toml") {
    println("actrun.toml already exists")
    return 1
  }
  let content = generate_actrun_config()
  try @xfs.write_string_to_file("actrun.toml", content) catch {
    _ => {
      println("error: failed to write actrun.toml")
      return 1
    }
  } noraise {
    _ => ()
  }
  println("Created actrun.toml")
  0
}

///|
/// Recursively scan a directory for .yml/.yaml files
fn scan_yaml_files(dir : String, prefix : String) -> Array[String] raise {
  let results : Array[String] = []
  let entries = try @xfs.read_dir(dir) catch {
    _ => return results
  } noraise {
    value => value
  }
  for entry in entries {
    let full_path = dir + "/" + entry
    let rel_path = if prefix.length() > 0 {
      prefix + "/" + entry
    } else {
      entry
    }
    if @xfs.is_dir(full_path) {
      for sub in scan_yaml_files(full_path, rel_path) {
        results.push(sub)
      }
    } else if entry.has_suffix(".yml") || entry.has_suffix(".yaml") {
      results.push(rel_path)
    }
  }
  results
}

///|
/// Collect workflow files matching include patterns
fn collect_list_workflows(
  patterns : Array[String],
) -> Array[WorkflowListRecord] raise {
  let paths : Array[String] = []
  let seen : Map[String, Bool] = {}
  for pattern in patterns {
    // Simple glob expansion
    if pattern.contains("*") {
      // e.g. "**/*.yml" or ".github/workflows/*.yml"
      // Find the static prefix before the first *
      let mut prefix_end = 0
      for i in 0..<pattern.length() {
        if pattern[i] == '*' {
          break
        }
        if pattern[i] == '/' {
          prefix_end = i + 1
        }
      }
      let dir = if prefix_end > 0 {
        String::unsafe_substring(pattern, start=0, end=prefix_end - 1)
      } else {
        "."
      }
      let dir_prefix = if prefix_end > 0 {
        String::unsafe_substring(pattern, start=0, end=prefix_end)
      } else {
        ""
      }
      if @xfs.path_exists(dir) {
        let all_files = scan_yaml_files(dir, "")
        for file in all_files {
          let full_rel = if dir_prefix.length() > 0 {
            dir_prefix + file
          } else {
            file
          }
          if glob_match(pattern, full_rel) &&
            not(seen.get(full_rel).unwrap_or(false)) {
            paths.push(full_rel)
            seen[full_rel] = true
          }
        }
      }
    } else if @xfs.path_exists(pattern) {
      if @xfs.is_dir(pattern) {
        // Directory: scan for yaml files
        let all_files = scan_yaml_files(pattern, pattern)
        for file in all_files {
          if not(seen.get(file).unwrap_or(false)) {
            paths.push(file)
            seen[file] = true
          }
        }
      } else if not(seen.get(pattern).unwrap_or(false)) {
        // Exact file
        paths.push(pattern)
        seen[pattern] = true
      }
    }
  }
  let records : Array[WorkflowListRecord] = []
  for path in paths {
    let name = match read_text(path) {
      Some(text) =>
        match @ar.parse_workflow_yaml(text).workflow {
          Some(workflow) =>
            if workflow.name.length() > 0 {
              workflow.name
            } else {
              workflow_name_from_path(path)
            }
          None => workflow_name_from_path(path)
        }
      None => workflow_name_from_path(path)
    }
    records.push({ name, path })
  }
  records
}

///|
fn handle_list_command(args : Array[String]) -> Int {
  let config = load_actrun_config(".")
  // Collect patterns: CLI args or config includes or default
  let patterns : Array[String] = []
  for i in 2..<args.length() {
    patterns.push(args[i])
  }
  if patterns.length() == 0 {
    for inc in config.includes {
      patterns.push(inc)
    }
  }
  if patterns.length() == 0 {
    patterns.push(".github/workflows/*.yml")
    patterns.push(".github/workflows/*.yaml")
  }
  let records = try collect_list_workflows(patterns) catch {
    _ => return 1
  } noraise {
    value => value
  }
  if records.length() == 0 {
    println("No workflows found.")
    return 0
  }
  for record in records {
    println(record.name)
    println("  actrun " + record.path)
    println("")
  }
  0
}

///|
/// Extract cron schedule expressions from workflow YAML text
fn extract_cron_schedules(text : String) -> Array[String] {
  let schedules : Array[String] = []
  let mut in_schedule = false
  for part in text.split("\n") {
    let line = part.to_string().trim(chars=" \t\r\n").to_string()
    if line == "schedule:" {
      in_schedule = true
      continue
    }
    if in_schedule {
      if line.has_prefix("- cron:") {
        let cron_part = String::unsafe_substring(
            line,
            start=7,
            end=line.length(),
          )
          .trim(chars=" \t\"'")
          .to_string()
        if cron_part.length() > 0 {
          schedules.push(cron_part)
        }
      } else if line.length() > 0 &&
        not(line.has_prefix("-")) &&
        not(line.has_prefix("#")) {
        in_schedule = false
      }
    }
  }
  schedules
}

///|
async fn handle_cron_command(args : Array[String]) -> Int {
  let config = load_actrun_config(".")
  let mut action = "show"
  if args.length() > 2 {
    action = args[2]
  }
  if action != "show" && action != "install" && action != "uninstall" {
    print_errors(["unknown cron subcommand: " + action])
    return 1
  }
  // Collect workflow patterns
  let patterns : Array[String] = []
  for inc in config.includes {
    patterns.push(inc)
  }
  if patterns.length() == 0 {
    patterns.push(".github/workflows/*.yml")
    patterns.push(".github/workflows/*.yaml")
  }
  let records = try collect_list_workflows(patterns) catch {
    _ => return 1
  } noraise {
    value => value
  }
  // Find workflows with schedule triggers
  let cron_entries : Array[(String, String, String)] = []
  for record in records {
    let text = match read_text(record.path) {
      Some(t) => t
      None => continue
    }
    let schedules = extract_cron_schedules(text)
    for cron_expr in schedules {
      cron_entries.push((record.name, record.path, cron_expr))
    }
  }
  if cron_entries.length() == 0 {
    println("No schedule triggers found in workflows.")
    return 0
  }
  let cwd = @env.current_dir().unwrap_or(
    @xsys.get_env_var("PWD").unwrap_or("."),
  )
  let actrun_bin = @xsys.get_cli_args()[0]
  if action == "show" {
    println("# actrun cron entries")
    for entry in cron_entries {
      let (name, path, cron_expr) = entry
      println("# " + name + " (" + path + ")")
      println(
        cron_expr +
        " cd " +
        cwd +
        " && " +
        actrun_bin +
        " " +
        path +
        " --trigger schedule --trust",
      )
      println("")
    }
  } else if action == "install" {
    let lines : Array[String] = []
    // Read existing crontab
    let (code, stdout, _) = run_command("crontab", ["-l"], cwd=".")
    if code == 0 {
      for line_view in stdout.split("\n") {
        let line = line_view.to_string()
        if not(line.contains("# actrun:")) {
          lines.push(line)
        }
      }
    }
    // Add actrun entries
    for entry in cron_entries {
      let (name, path, cron_expr) = entry
      lines.push(
        cron_expr +
        " cd " +
        cwd +
        " && " +
        actrun_bin +
        " " +
        path +
        " --trigger schedule --trust # actrun:" +
        name,
      )
    }
    let crontab_text = lines.join("\n") + "\n"
    let tmp_path = "/tmp/actrun-crontab-" + @env.now().to_string()
    try @xfs.write_string_to_file(tmp_path, crontab_text) catch {
      _ => {
        print_errors(["failed to write temp crontab file"])
        return 1
      }
    } noraise {
      _ => ()
    }
    let (install_code, _, install_err) = run_command(
      "crontab",
      [tmp_path],
      cwd=".",
    )
    ignore(run_command("rm", ["-f", tmp_path], cwd="."))
    if install_code != 0 {
      print_errors([install_err.trim(chars=" \t\r\n").to_string()])
      return 1
    }
    println("Installed " + cron_entries.length().to_string() + " cron entries")
    for entry in cron_entries {
      let (name, path, cron_expr) = entry
      println("  " + cron_expr + "  " + name + " (" + path + ")")
    }
  } else if action == "uninstall" {
    let (code, stdout, _) = run_command("crontab", ["-l"], cwd=".")
    if code != 0 {
      println("No crontab found")
      return 0
    }
    let lines : Array[String] = []
    let mut removed = 0
    for line_view in stdout.split("\n") {
      let line = line_view.to_string()
      if line.contains("# actrun:") {
        removed += 1
      } else {
        lines.push(line)
      }
    }
    if removed == 0 {
      println("No actrun cron entries found")
      return 0
    }
    let crontab_text = lines.join("\n")
    let tmp_path = "/tmp/actrun-crontab-" + @env.now().to_string()
    try @xfs.write_string_to_file(tmp_path, crontab_text) catch {
      _ => {
        print_errors(["failed to write temp crontab file"])
        return 1
      }
    } noraise {
      _ => ()
    }
    let (install_code, _, install_err) = run_command(
      "crontab",
      [tmp_path],
      cwd=".",
    )
    ignore(run_command("rm", ["-f", tmp_path], cwd="."))
    if install_code != 0 {
      print_errors([install_err.trim(chars=" \t\r\n").to_string()])
      return 1
    }
    println("Removed " + removed.to_string() + " actrun cron entries")
  }
  0
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
  let dispatch_inputs : Map[String, String] = {}
  let mut dry_run = false
  let mut trust_actions = false
  let mut nix_mode = ""
  let nix_packages : Array[String] = []
  let mut container_runtime = ""
  let mut affected = false
  let mut affected_base = ""
  let mut retry = false
  let mut job_filter = ""
  let mut step_filter = ""
  let mut trigger = ""
  let mut index = 1

  while index < args.length() {
    let arg = args[index]
    if arg == "--dry-run" {
      dry_run = true
      index += 1
      continue
    }
    if arg == "--trust" {
      trust_actions = true
      index += 1
      continue
    }
    if arg == "--nix" {
      nix_mode = "auto"
      index += 1
      continue
    }
    if arg == "--no-nix" {
      nix_mode = "off"
      index += 1
      continue
    }
    if arg == "--affected" {
      affected = true
      index += 1
      // Optional: --affected HEAD~3 or --affected abc123
      if index < args.length() && not(args[index].has_prefix("-")) {
        affected_base = args[index]
        index += 1
      }
      continue
    }
    if arg == "--retry" {
      retry = true
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
      arg == "--input" ||
      arg == "--env" ||
      arg == "--nix-packages" ||
      arg == "--container-runtime" ||
      arg == "--job" ||
      arg == "--step" ||
      arg == "--trigger" {
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
      } else if arg == "--input" {
        match value.find("=") {
          Some(eq) => {
            let k = String::unsafe_substring(value, start=0, end=eq)
            let v = String::unsafe_substring(
              value,
              start=eq + 1,
              end=value.length(),
            )
            dispatch_inputs[k] = v
          }
          None => errors.push("--input value must be key=value, got: " + value)
        }
      } else if arg == "--env" {
        for err in load_env_file(value) {
          errors.push(err)
        }
      } else if arg == "--nix-packages" {
        for part_view in value.split(" ") {
          let part = part_view.trim(chars=" \t").to_string()
          if part.length() > 0 {
            nix_packages.push(part)
          }
        }
      } else if arg == "--container-runtime" {
        container_runtime = value
      } else if arg == "--job" {
        job_filter = value
      } else if arg == "--step" {
        step_filter = value
      } else if arg == "--trigger" {
        trigger = value
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
    if arg == "--json" {
      // Accepted but handled at dry-run output level
      index += 1
      continue
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
      dispatch_inputs,
      dry_run,
      trust_actions,
      nix_mode,
      nix_packages,
      container_runtime,
      affected,
      affected_base,
      retry,
      job_filter,
      step_filter,
      trigger,
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
  let mut max_age_days = 0
  let mut prune_all = false
  let mut json_output = false
  let mut index = 3
  while index < args.length() {
    let arg = args[index]
    if arg == "--json" {
      json_output = true
      index += 1
      continue
    }
    if arg == "--all" {
      prune_all = true
      index += 1
      continue
    }
    if arg == "--cache-root" ||
      arg == "--key" ||
      arg == "--workspace-key" ||
      arg == "--max-age" {
      if index + 1 >= args.length() {
        errors.push("missing value for " + arg)
        break
      }
      let value = args[index + 1]
      if arg == "--cache-root" {
        cache_root = Some(value)
      } else if arg == "--key" {
        key_filter = value
      } else if arg == "--max-age" {
        max_age_days = try @strconv.parse_int64(value).to_int() catch {
          _ => {
            errors.push("--max-age must be a number")
            0
          }
        } noraise {
          v => v
        }
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
  if action == "prune" &&
    key_filter.length() == 0 &&
    not(prune_all) &&
    max_age_days == 0 {
    errors.push("--key, --all, or --max-age is required for `cache prune`")
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
      max_age_days,
      prune_all,
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
    { name: "nix", bin: "nix", env_override: "", required: false },
  ]
  let mut has_error = false
  for check in checks {
    let bin = if check.env_override.length() > 0 {
      @xsys.get_env_var(check.env_override).unwrap_or(check.bin)
    } else {
      check.bin
    }
    let (code, stdout, _) = run_command(bin, ["--version"], cwd=".")
    if code == 0 {
      let version = stdout.trim(chars=" \t\r\n").to_string()
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
  // Check nix environment
  if @xfs.path_exists("flake.nix") {
    println("ok  nix-env: flake.nix detected")
  } else if @xfs.path_exists("shell.nix") {
    println("ok  nix-env: shell.nix detected")
  } else {
    println("--  nix-env: no flake.nix or shell.nix found")
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
  // Check actrun.toml configuration
  if @xfs.path_exists("actrun.toml") {
    println("")
    println("=== actrun.toml ===")
    let config = load_actrun_config(".")
    // workspace_mode
    if config.workspace_mode.length() > 0 {
      println("  workspace_mode: " + config.workspace_mode)
    }
    // trust_actions
    if config.trust_actions {
      println("  trust_actions: true")
    }
    // local_skip_actions
    if config.local_skip_actions.length() > 0 {
      println("  local_skip_actions:")
      for action in config.local_skip_actions {
        println("    - " + action)
      }
    }
    // nix_mode
    if config.nix_mode.length() > 0 {
      println("  nix_mode: " + config.nix_mode)
    }
    // nix_packages
    if config.nix_packages.length() > 0 {
      println("  nix_packages: " + config.nix_packages.join(", "))
    }
    // container_runtime
    if config.container_runtime.length() > 0 {
      let (bin, _) = resolve_container_runtime_bin(config.container_runtime)
      let (rt_code, rt_stdout, _) = run_command(bin, ["--version"], cwd=".")
      if rt_code == 0 {
        let rt_ver = rt_stdout.trim(chars=" \t\r\n").to_string()
        let short_ver = match rt_ver.find("\n") {
          Some(idx) => String::unsafe_substring(rt_ver, start=0, end=idx)
          None => rt_ver
        }
        println(
          "  container_runtime: " +
          config.container_runtime +
          " (" +
          short_ver +
          ")",
        )
      } else {
        println(
          "  container_runtime: " + config.container_runtime + " (NOT FOUND)",
        )
        has_error = true
      }
    }
    // Validate local_skip_actions: check if skipped setup actions have local equivalents
    let skip_tool_checks : Array[(String, String, String)] = [
      ("setup-node", "node", "--version"),
      ("setup-python", "python3", "--version"),
      ("setup-go", "go", "version"),
      ("setup-java", "java", "-version"),
      ("setup-rust", "rustc", "--version"),
    ]
    for action in config.local_skip_actions {
      for check in skip_tool_checks {
        let (pattern, tool, flag) = check
        if action.contains(pattern) {
          let (tool_code, tool_stdout, tool_stderr) = run_command(
            tool,
            [flag],
            cwd=".",
          )
          if tool_code == 0 {
            // Some tools output to stderr (java -version)
            let out = tool_stdout.trim(chars=" \t\r\n").to_string()
            let raw = if out.length() > 0 {
              out
            } else {
              tool_stderr.trim(chars=" \t\r\n").to_string()
            }
            let short_ver = match raw.find("\n") {
              Some(idx) => String::unsafe_substring(raw, start=0, end=idx)
              None => raw
            }
            println(
              "ok  skip " +
              action +
              ": local " +
              tool +
              " found (" +
              short_ver +
              ")",
            )
          } else {
            println("ERR skip " + action + ": " + tool + " not found locally")
            has_error = true
          }
          break
        }
      }
    }
  } else {
    println("--  actrun.toml: not found (run 'actrun init' to create)")
  }
  if has_error {
    1
  } else {
    0
  }
}

///|
async fn run_in_docker_container(options : CliOptions) -> Int {
  let docker_bin = @xsys.get_env_var("ACTRUN_CONTAINER_RUNTIME").unwrap_or(
    @xsys.get_env_var("ACTRUN_DOCKER_BIN").unwrap_or("docker"),
  )
  let image = @xsys.get_env_var("ACTRUN_DOCKER_IMAGE").unwrap_or(
    "ghcr.io/mizchi/actrun:latest",
  )
  let cwd = @env.current_dir().unwrap_or(
    @xsys.get_env_var("PWD").unwrap_or("."),
  )
  let args : Array[String] = [
    "run",
    "--rm",
    "-v",
    cwd + ":/workspace",
    "-w",
    "/workspace",
  ]
  // Forward ACTRUN_SECRET_* and ACTRUN_VAR_* env vars
  for key, value in @xsys.get_env_vars() {
    if key.has_prefix("ACTRUN_SECRET_") || key.has_prefix("ACTRUN_VAR_") {
      args.push("-e")
      args.push(key + "=" + value)
    }
  }
  // Forward dispatch inputs
  for key, value in options.dispatch_inputs {
    args.push("-e")
    args.push("ACTRUN_INPUT_" + key + "=" + value)
  }
  args.push(image)
  args.push("workflow")
  args.push("run")
  args.push(options.workflow_path)
  for pattern in options.skip_actions {
    args.push("--skip-action")
    args.push(pattern)
  }
  if options.dry_run {
    args.push("--dry-run")
  }
  let (code, stdout, stderr) = run_command(docker_bin, args, cwd=".")
  if stdout.length() > 0 {
    println(stdout.trim_end(chars="\n").to_string())
  }
  if stderr.length() > 0 {
    print_errors([stderr.trim_end(chars="\n").to_string()])
  }
  code
}

///|
fn is_trusted_action_owner(uses : String) -> Bool {
  uses.has_prefix("actions/") ||
  uses.has_prefix("./") ||
  uses.has_prefix("../") ||
  uses.has_prefix("docker://") ||
  uses.has_prefix("wasm://") ||
  uses.has_prefix("builtin://")
}

///|
fn collect_third_party_actions(
  workflow : @ar.WorkflowSpec,
  workspace_root? : String = ".",
) -> Array[String] {
  let seen : Map[String, Bool] = {}
  let result : Array[String] = []
  for job in workflow.jobs {
    // Scan reusable workflow files
    match job.reusable_workflow {
      Some(path) if path.has_prefix("./") => {
        let full = join_path(workspace_root, path)
        let callee_text = try @xfs.read_file_to_string(full) catch {
          _ => ""
        } noraise {
          v => v
        }
        if callee_text.length() > 0 {
          let parsed = @ar.parse_workflow_yaml(callee_text)
          match parsed.workflow {
            Some(callee) =>
              for cj in callee.jobs {
                scan_steps_for_third_party(cj.steps, seen, result, "")
              }
            None => ()
          }
        }
      }
      _ => ()
    }
    for step in job.steps {
      match step.uses {
        Some(uses) => {
          // Direct third-party check
          if not(is_trusted_action_owner(uses)) && not(seen.contains(uses)) {
            seen[uses] = true
            result.push(uses)
          }
          // Scan local composite action internals
          if uses.has_prefix("./") || uses.has_prefix("../") {
            scan_local_action_manifest(
              join_path(workspace_root, uses),
              uses,
              seen,
              result,
            )
          }
        }
        None => ()
      }
    }
  }
  result
}

///|
fn scan_steps_for_third_party(
  steps : Array[@ar.StepSpec],
  seen : Map[String, Bool],
  result : Array[String],
  via : String,
) -> Unit {
  for step in steps {
    match step.uses {
      Some(uses) =>
        if not(is_trusted_action_owner(uses)) && not(seen.contains(uses)) {
          seen[uses] = true
          if via.length() > 0 {
            result.push(uses + " (via " + via + ")")
          } else {
            result.push(uses)
          }
        }
      None => ()
    }
  }
}

///|
fn scan_local_action_manifest(
  action_dir : String,
  via : String,
  seen : Map[String, Bool],
  result : Array[String],
) -> Unit {
  let yml = action_dir + "/action.yml"
  let yaml = action_dir + "/action.yaml"
  let text = try @xfs.read_file_to_string(yml) catch {
    _ =>
      try @xfs.read_file_to_string(yaml) catch {
        _ => ""
      } noraise {
        v => v
      }
  } noraise {
    v => v
  }
  if text.length() == 0 {
    return
  }
  // Extract uses: lines from manifest text (simple grep approach)
  for line_view in text.split("\n") {
    let line = line_view.trim(chars=" \t\r").to_string()
    if line.has_prefix("uses:") {
      let uses = String::unsafe_substring(line, start=5, end=line.length())
        .trim(chars=" \t'\"")
        .to_string()
      if uses.length() > 0 &&
        not(is_trusted_action_owner(uses)) &&
        not(seen.contains(uses)) {
        seen[uses] = true
        result.push(uses + " (via " + via + ")")
      }
    }
  }
}

///|
async fn read_stdin_line() -> String {
  let (code, stdout, _) = run_command(
    "sh",
    ["-c", "read answer && echo \"$answer\""],
    cwd=".",
  )
  if code == 0 {
    stdout.trim(chars=" \t\r\n").to_string()
  } else {
    ""
  }
}

///|
fn is_workspace_modifying_action(uses : String) -> Bool {
  uses.has_prefix("actions/checkout") ||
  uses.has_prefix("actions/cache/restore") ||
  (
    uses.has_prefix("actions/cache") &&
    not(uses.has_prefix("actions/cache/save"))
  )
}

///|
fn collect_workspace_modifying_steps(
  workflow : @ar.WorkflowSpec,
) -> Array[String] {
  let result : Array[String] = []
  for job in workflow.jobs {
    for step in job.steps {
      match step.uses {
        Some(uses) =>
          if is_workspace_modifying_action(uses) {
            let label = if step.name.length() > 0 { step.name } else { uses }
            result.push(job.id + "/" + label)
          }
        None => ()
      }
    }
  }
  result
}

///|
fn print_dry_run_plan(
  workflow : @ar.WorkflowSpec,
  lowered : @ar.LoweringResult,
) -> Unit {
  println("workflow=" + workflow.name)
  if workflow.run_name.length() > 0 {
    println("run-name=" + workflow.run_name)
  }
  println("mode=dry-run")
  println("")
  let mut current_job = ""
  for task in lowered.plan.tasks {
    if task.job_id != current_job {
      current_job = task.job_id
      let needs = lowered.plan.job_needs.get(current_job).unwrap_or([])
      let needs_label = if needs.length() > 0 {
        " [needs: " + needs.join(", ") + "]"
      } else {
        ""
      }
      println("job: " + current_job + needs_label)
    }
    if task.kind == "barrier" {
      continue
    }
    let kind_label = match task.action {
      Some(action) => task.kind + " (" + action.uses + ")"
      None => task.kind
    }
    let name_label = if task.name.length() > 0 && task.name != task.step_id {
      " \"" + task.name + "\""
    } else {
      ""
    }
    let if_label = if task.if_condition.length() > 0 &&
      task.if_condition != "success()" {
      " [if: " + task.if_condition + "]"
    } else {
      ""
    }
    let shell_label = if task.shell.length() > 0 && task.kind == "run" {
      " [" + task.shell + "]"
    } else {
      ""
    }
    println(
      "  " + task.id + ": " + kind_label + name_label + shell_label + if_label,
    )
  }
}

///|
fn print_dry_run_plan_json(
  workflow : @ar.WorkflowSpec,
  lowered : @ar.LoweringResult,
) -> Unit {
  let job_steps : Map[String, Array[String]] = {}
  let job_order : Array[String] = []
  for task in lowered.plan.tasks {
    if task.kind == "barrier" {
      continue
    }
    if job_steps.get(task.job_id) is None {
      job_steps[task.job_id] = []
      job_order.push(task.job_id)
    }
    let parts : Array[String] = []
    parts.push("\"id\": " + json_string(task.id))
    parts.push("\"kind\": " + json_string(task.kind))
    if task.name.length() > 0 {
      parts.push("\"name\": " + json_string(task.name))
    }
    if task.shell.length() > 0 {
      parts.push("\"shell\": " + json_string(task.shell))
    }
    match task.action {
      Some(action) => parts.push("\"uses\": " + json_string(action.uses))
      None => ()
    }
    if task.if_condition.length() > 0 && task.if_condition != "success()" {
      parts.push("\"if\": " + json_string(task.if_condition))
    }
    if task.working_directory.length() > 0 {
      parts.push(
        "\"working_directory\": " + json_string(task.working_directory),
      )
    }
    if task.env.length() > 0 {
      let env_items : Array[String] = []
      for key, value in task.env {
        env_items.push(json_string(key) + ": " + json_string(value))
      }
      parts.push("\"env\": { " + env_items.join(", ") + " }")
    }
    job_steps.get(task.job_id).unwrap().push("{ " + parts.join(", ") + " }")
  }
  let job_items : Array[String] = []
  for job_id in job_order {
    let parts : Array[String] = []
    parts.push("\"id\": " + json_string(job_id))
    let needs = lowered.plan.job_needs.get(job_id).unwrap_or([])
    if needs.length() > 0 {
      parts.push("\"needs\": " + json_string_array(needs))
    }
    parts.push("\"steps\": [" + job_steps.get(job_id).unwrap().join(", ") + "]")
    job_items.push("{ " + parts.join(", ") + " }")
  }
  let root_parts : Array[String] = []
  root_parts.push("\"workflow\": " + json_string(workflow.name))
  root_parts.push("\"jobs\": [" + job_items.join(", ") + "]")
  if lowered.errors.length() > 0 {
    root_parts.push("\"warnings\": " + json_string_array(lowered.errors))
  }
  println("{ " + root_parts.join(", ") + " }")
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
  let now_ms = @env.now()
  for cache in caches {
    if options.prune_all {
      filtered.push(cache)
    } else if options.max_age_days > 0 {
      // Use file mtime via sequence as proxy for age
      // Simplified: prune all if max_age requested (proper mtime needs fs API)
      filtered.push(cache)
    } else if cache_record_matches(cache, options) {
      filtered.push(cache)
    }
  }
  ignore(now_ms)
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
  if workflow.run_name.length() > 0 {
    println("run-name=\{workflow.run_name}")
  }
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
async fn handle_workflow_run_command(raw_options : CliOptions) -> Int {
  let config = load_actrun_config(".")
  let options = merge_config_into_options(raw_options, config)
  apply_container_runtime(options)
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
    return run_in_docker_container(options)
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

  // --trigger: skip trigger matching when explicitly specified
  if options.trigger.length() > 0 {
    println("trigger: using " + options.trigger + " (trigger matching skipped)")
  }
  if options.trigger.length() == 0 &&
    should_check_trigger(options) &&
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

  // --affected: check if workflow is affected by changes
  if options.affected {
    let wf_key = options.workflow_path
    // Resolve patterns: actrun.toml > on.push.paths > skip
    let mut patterns = config.affected.get(wf_key).unwrap_or([])
    if patterns.length() == 0 {
      let mut last_slash = -1
      for i in 0..<wf_key.length() {
        if wf_key[i] == '/' {
          last_slash = i
        }
      }
      if last_slash >= 0 {
        let basename = String::unsafe_substring(
          wf_key,
          start=last_slash + 1,
          end=wf_key.length(),
        )
        patterns = config.affected.get(basename).unwrap_or([])
      }
    }
    // Fallback to on:push:paths from the workflow trigger
    if patterns.length() == 0 && workflow.trigger.paths.length() > 0 {
      patterns = workflow.trigger.paths
      println(
        "affected: using on.push.paths from workflow (" +
        patterns.join(", ") +
        ")",
      )
    }
    if patterns.length() > 0 {
      // Determine base ref for diff
      let (base_ref, base_label) = if options.affected_base.length() > 0 {
        // Explicit base: --affected HEAD~3
        (options.affected_base, options.affected_base)
      } else {
        // Default: last successful run's after_sha
        match find_latest_run_for_workflow(run_root, workflow_path, true) {
          Some((last_run, last_run_id)) => {
            let sha = run_json_string(last_run, "after_sha")
            if sha.length() > 0 {
              (sha, last_run_id)
            } else {
              ("", last_run_id)
            }
          }
          None => {
            println("affected: no previous successful run found, running")
            ("", "")
          }
        }
      }
      if base_label.length() > 0 {
        let changed = if base_ref.length() > 0 {
          let committed = git_diff_files(base_ref, "HEAD")
          let uncommitted = git_uncommitted_files()
          let all : Array[String] = []
          for f in committed {
            all.push(f)
          }
          for f in uncommitted {
            all.push(f)
          }
          all
        } else {
          git_uncommitted_files()
        }
        if not(files_match_patterns(changed, patterns)) {
          println(
            "affected: no changes match patterns for " +
            wf_key +
            " (since " +
            base_label +
            ")",
          )
          if not(options.dry_run) {
            return 0
          }
          println("affected: would skip (dry-run continues)")
        } else {
          println(
            "affected: changes detected for " +
            wf_key +
            " (since " +
            base_label +
            ")",
          )
        }
      }
    } else {
      println("affected: no patterns configured for " + wf_key + ", running")
    }
  }

  // --retry: filter to only failed jobs from the latest run
  let retry_skip_jobs : Array[String] = []
  if options.retry {
    match find_latest_run_for_workflow(run_root, workflow_path, false) {
      Some((last_run, last_run_id)) => {
        let last_ok = match run_json_field(last_run, "ok") {
          Some(True) => true
          _ => false
        }
        if last_ok {
          println(
            "retry: last run " +
            last_run_id +
            " was successful, nothing to retry",
          )
          return 0
        }
        let failed_jobs = extract_failed_job_ids(last_run)
        if failed_jobs.length() == 0 {
          println("retry: no failed jobs found in " + last_run_id)
          return 0
        }
        // Collect successful job IDs to skip
        match last_run {
          Object(obj) =>
            match obj.get("steps") {
              Some(Array(steps)) =>
                for step in steps {
                  let id = run_json_string(step, "id")
                  let status = run_json_string(step, "status")
                  if status == "success" && id.contains("/") {
                    match id.find("/") {
                      Some(slash) => {
                        let job_id = String::unsafe_substring(
                          id,
                          start=0,
                          end=slash,
                        )
                        let mut is_failed = false
                        for fj in failed_jobs {
                          if fj == job_id {
                            is_failed = true
                            break
                          }
                        }
                        if not(is_failed) {
                          let mut already = false
                          for j in retry_skip_jobs {
                            if j == job_id {
                              already = true
                              break
                            }
                          }
                          if not(already) {
                            retry_skip_jobs.push(job_id)
                          }
                        }
                      }
                      None => ()
                    }
                  }
                }
              _ => ()
            }
          _ => ()
        }
        println("retry: re-running failed jobs from " + last_run_id + ":")
        for job_id in failed_jobs {
          println("  - " + job_id)
        }
        if retry_skip_jobs.length() > 0 {
          println("retry: skipping successful jobs:")
          for job_id in retry_skip_jobs {
            println("  - " + job_id)
          }
        }
      }
      None => println("retry: no previous run found, running all jobs")
    }
  }

  // Strip unsupported fields and filter skipped actions
  let should_strip = options.skip_actions.length() > 0 ||
    options.dry_run ||
    retry_skip_jobs.length() > 0
  let stripped_workflow = if should_strip {
    @ar.strip_unsupported_workflow_fields(workflow)
  } else {
    workflow
  }
  let effective_workflow = if options.skip_actions.length() > 0 {
    // Log skipped steps before filtering
    for job in stripped_workflow.jobs {
      for step in job.steps {
        match step.uses {
          Some(uses) =>
            if @ar.step_matches_skip_pattern(step, options.skip_actions) {
              let label = if step.name.length() > 0 { step.name } else { uses }
              println("skip  " + job.id + "/" + label + " (" + uses + ")")
            }
          None => ()
        }
      }
    }
    @ar.filter_workflow_steps(stripped_workflow, options.skip_actions)
  } else {
    stripped_workflow
  }

  // --retry: filter out successful jobs from previous run
  let retry_workflow = @ar.filter_workflow_jobs(
    effective_workflow, retry_skip_jobs,
  )

  // --job / --step: select specific job and/or step
  let filtered_workflow = if options.job_filter.length() > 0 ||
    options.step_filter.length() > 0 {
    let job_selected = @ar.select_workflow_job(
      retry_workflow,
      options.job_filter,
    )
    let step_selected = @ar.select_workflow_step(
      job_selected,
      options.job_filter,
      options.step_filter,
    )
    if step_selected.jobs.length() == 0 {
      let target = if options.step_filter.length() > 0 {
        options.job_filter + "/" + options.step_filter
      } else {
        options.job_filter
      }
      print_errors(["no matching job/step found: " + target])
      return 1
    }
    for job in step_selected.jobs {
      let steps_desc : Array[String] = []
      for step in job.steps {
        let label = if step.name.length() > 0 { step.name } else { step.id }
        steps_desc.push(label)
      }
      println("run   " + job.id + ": " + steps_desc.join(", "))
    }
    step_selected
  } else {
    retry_workflow
  }

  if options.dry_run {
    let lowered = @ar.lower_push_workflow_in_workspace(
      filtered_workflow, execution_root,
    )
    let cli_args = @xsys.get_cli_args()
    let json_mode = cli_args.contains("--json")
    if json_mode {
      print_dry_run_plan_json(filtered_workflow, lowered)
    } else {
      if lowered.errors.length() > 0 {
        for err in lowered.errors {
          println("warning: " + err)
        }
      }
      print_dry_run_plan(filtered_workflow, lowered)
    }
    return 0
  }

  // Check for third-party actions and prompt for confirmation
  let trust_env = @xsys.get_env_var("ACTRUN_TRUST").unwrap_or("") == "true"
  if not(options.trust_actions) && not(trust_env) && not(options.dry_run) {
    let third_party = collect_third_party_actions(filtered_workflow)
    if third_party.length() > 0 {
      println("The following third-party actions will be fetched and executed:")
      for action_ref in third_party {
        println("  " + action_ref)
      }
      println("")
      println("Use --trust to skip this prompt, or Ctrl+C to cancel.")
      println("Continue? [y/N]")
      let answer = read_stdin_line()
      let trimmed = answer.trim(chars=" \t\r\n").to_lower()
      if trimmed != "y" && trimmed != "yes" {
        println("Aborted.")
        return 1
      }
    }
  }

  // Warn when local mode will modify workspace files
  if workspace_mode == "local" &&
    not(options.trust_actions) &&
    not(trust_env) &&
    not(options.dry_run) {
    let modifying = collect_workspace_modifying_steps(filtered_workflow)
    if modifying.length() > 0 {
      println(
        "Warning: running in local mode will modify files in your working directory.",
      )
      println("The following steps write to the workspace:")
      for desc in modifying {
        println("  " + desc)
      }
      println("")
      println(
        "Use --worktree or --tmp for isolated execution, --skip-action to skip, or --trust to suppress this prompt.",
      )
      println("Continue? [y/N]")
      let answer = read_stdin_line()
      let trimmed = answer.trim(chars=" \t\r\n").to_lower()
      if trimmed != "y" && trimmed != "yes" {
        println("Aborted.")
        return 1
      }
    }
  }
  let prefetch = @ar.prefetch_workflow_github_actions_native(
    filtered_workflow, execution_root,
  )
  if prefetch.errors.length() > 0 {
    print_errors(prefetch.errors)
    return 1
  }

  let lowered = @ar.lower_push_workflow_in_workspace(
    filtered_workflow, execution_root,
  )
  if lowered.errors.length() > 0 {
    print_errors(lowered.errors)
    return 1
  }

  let raw_report = @ar.execute_lowered_native(
    lowered,
    workspace_root=execution_root,
    push_event=Some(trigger_event),
    dispatch_inputs=options.dispatch_inputs,
    nix_mode=options.nix_mode,
    nix_packages=options.nix_packages,
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
  if cli_args.length() > 1 && cli_args[1] == "init" {
    let exit_code = handle_init_command()
    if exit_code != 0 {
      @xsys.exit(exit_code)
    }
    return
  }
  if cli_args.length() > 1 && cli_args[1] == "list" {
    let exit_code = handle_list_command(cli_args)
    if exit_code != 0 {
      @xsys.exit(exit_code)
    }
    return
  }
  if cli_args.length() > 1 && cli_args[1] == "cron" {
    let exit_code = handle_cron_command(cli_args)
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
