///|
struct CliOptions {
  workflow_path : String
  repo_root : String?
  workspace_root : String?
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
fn usage_text() -> String {
  "Usage: action_runner <workflow.yml> [--repo <repo_root>] [--workspace <workspace_root>] [--event <push-event.json>] [--repository <owner/repo>] [--ref <ref_name>] [--before <sha>] [--after <sha>] [--changed <path>]..."
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
fn parse_cli_args(args : Array[String]) -> CliParseResult {
  let errors : Array[String] = []
  let mut workflow_path = ""
  let mut repo_root : String? = None
  let mut workspace_root : String? = None
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
  if errors.length() > 0 {
    return { options: None, errors }
  }
  {
    options: Some({
      workflow_path,
      repo_root,
      workspace_root,
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
) -> Unit {
  println("workflow=\{workflow.name}")
  println("state=\{report.state}")
  for step in report.steps {
    println("\{step.id}: \{step.status}")
  }
}

///|
#cfg(target="native")
async fn main {
  let parsed_args = parse_cli_args(@xsys.get_cli_args())
  if parsed_args.errors.length() > 0 {
    print_errors(parsed_args.errors)
    @xsys.exit(1)
  }
  guard parsed_args.options is Some(options) else {
    print_errors([usage_text()])
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
    println("workflow=\{workflow.name}")
    println("state=skipped")
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
  print_report(workflow, report)
  if not(report.ok) {
    @xsys.exit(1)
  }
}

///|
#cfg(not(target="native"))
fn main {
  println("action_runner CLI execute is supported on native target only")
}
