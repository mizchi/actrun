///|

///|
struct CompatFixture {
  id : String
  source : String
  mode : String
  kind : String
  url : String
  docs_urls : Array[String]
  added_at : String
  notes : String
  root_dir : String
  workflow_path : String
  workflow_text : String
  event_path : String?
  event_text : String?
}

///|
struct CompatFixtureLoadResult {
  fixture : CompatFixture?
  errors : Array[String]
}

///|
fn compat_join_path(base : String, child : String) -> String {
  if child.has_prefix("/") {
    return child
  }
  if base.length() == 0 || base == "." {
    child
  } else if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
fn compat_read_text(path : String) -> String? {
  try @xfs.read_file_to_string(path) catch {
    _ => None
  } noraise {
    content => Some(content)
  }
}

///|
fn compat_trim_cr(text : String) -> String {
  text.trim_end(chars="\r").to_string()
}

///|
fn compat_parse_metadata(text : String) -> Map[String, String] {
  let values : Map[String, String] = {}
  for line_view in text.split("\n") {
    let line = compat_trim_cr(line_view.to_string()).trim(chars=" ").to_string()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    match line.find("=") {
      Some(idx) => {
        let key = String::unsafe_substring(line, start=0, end=idx)
          .trim(chars=" ")
          .to_string()
        let value = String::unsafe_substring(
            line,
            start=idx + 1,
            end=line.length(),
          )
          .trim(chars=" ")
          .to_string()
        if key.length() > 0 {
          values[key] = value
        }
      }
      None => ()
    }
  }
  values
}

///|
fn compat_parse_docs_urls(text : String) -> Array[String] {
  let urls : Array[String] = []
  for part in text.split(";") {
    let url = part.to_string().trim(chars=" ").to_string()
    if url.length() > 0 {
      urls.push(url)
    }
  }
  urls
}

///|
fn compat_fixture_leaf_name(path : String) -> String {
  let mut leaf = ""
  for part_view in path.trim(chars="/").split("/") {
    let part = part_view.to_string()
    if part.length() > 0 {
      leaf = part
    }
  }
  if leaf.length() == 0 {
    abort("invalid fixture path: " + path)
  }
  leaf
}

///|
fn compat_fixture_workspace_name(
  prefix : String,
  fixture_dir : String,
) -> String {
  let leaf = compat_fixture_leaf_name(fixture_dir)
  if prefix.length() == 0 {
    leaf
  } else {
    prefix + "-" + leaf
  }
}

///|
fn compat_fixture_dir(root : String, fixture_name : String) -> String {
  compat_join_path(root, fixture_name)
}

///|
fn load_compat_fixture(dir : String) -> CompatFixtureLoadResult {
  let errors : Array[String] = []
  let metadata_path = compat_join_path(dir, "fixture.txt")
  let workflow_path = compat_join_path(dir, "workflow.yml")

  guard compat_read_text(metadata_path) is Some(metadata_text) else {
    return { fixture: None, errors: ["missing fixture.txt: " + metadata_path] }
  }
  guard compat_read_text(workflow_path) is Some(workflow_text) else {
    return { fixture: None, errors: ["missing workflow.yml: " + workflow_path] }
  }

  let metadata = compat_parse_metadata(metadata_text)
  let id = metadata.get("id").unwrap_or("")
  let source = metadata.get("source").unwrap_or("")
  let mode = metadata.get("mode").unwrap_or("")
  let kind = metadata.get("kind").unwrap_or("")
  let url = metadata.get("url").unwrap_or("")
  let docs_urls = compat_parse_docs_urls(
    metadata.get("docs_urls").unwrap_or(""),
  )
  let added_at = metadata.get("added_at").unwrap_or("")
  let notes = metadata.get("notes").unwrap_or("")

  if id.length() == 0 {
    errors.push("fixture metadata is missing id")
  }
  if source.length() == 0 {
    errors.push("fixture metadata is missing source")
  }
  if mode.length() == 0 {
    errors.push("fixture metadata is missing mode")
  }
  if kind.length() == 0 {
    errors.push("fixture metadata is missing kind")
  }
  if url.length() == 0 {
    errors.push("fixture metadata is missing url")
  }

  let event_path = compat_join_path(dir, "event.json")
  let event_text = compat_read_text(event_path)
  if errors.length() > 0 {
    return { fixture: None, errors }
  }

  {
    fixture: Some({
      id,
      source,
      mode,
      kind,
      url,
      docs_urls,
      added_at,
      notes,
      root_dir: dir,
      workflow_path,
      workflow_text,
      event_path: if event_text is Some(_) {
        Some(event_path)
      } else {
        None
      },
      event_text,
    }),
    errors: [],
  }
}

///|
fn compat_expect_fixture(result : CompatFixtureLoadResult) -> CompatFixture {
  match result.fixture {
    Some(fixture) => fixture
    None => abort(result.errors.join("\n"))
  }
}

///|
fn compat_expect_workflow(parsed : WorkflowParseResult) -> WorkflowSpec {
  match parsed.workflow {
    Some(workflow) => workflow
    None => abort(parsed.errors.join("\n"))
  }
}

///|
fn compat_expect_task_plan(plan : ExecutionPlan, id : String) -> TaskPlan {
  match find_task_plan(plan, id) {
    Some(task) => task
    None => abort("missing task plan: " + id)
  }
}

///|
fn compat_expect_task_report(
  report : WorkflowRunReport,
  id : String,
) -> TaskRunReport {
  match find_task_run_report(report, id) {
    Some(task) => task
    None => abort("missing task report: " + id)
  }
}

///|
fn compat_expect_step_report(
  report : WorkflowRunReport,
  id : String,
) -> WorkflowStepReport {
  match find_workflow_step_report(report, id) {
    Some(step) => step
    None => abort("missing step report: " + id)
  }
}

///|
fn compat_expect_workflow_fixture(
  fixture_dir : String,
) -> (CompatFixture, WorkflowSpec) {
  let fixture = compat_expect_fixture(load_compat_fixture(fixture_dir))
  let workflow = compat_expect_workflow(
    parse_workflow_yaml(fixture.workflow_text),
  )
  (fixture, workflow)
}

///|
fn compat_expect_workflow_fixture_in(
  root : String,
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec) {
  compat_expect_workflow_fixture(compat_fixture_dir(root, fixture_name))
}

///|
fn compat_expect_lowered_workflow_fixture(
  fixture_dir : String,
) -> (CompatFixture, WorkflowSpec, LoweringResult) {
  let (fixture, workflow) = compat_expect_workflow_fixture(fixture_dir)
  (fixture, workflow, lower_push_workflow(workflow))
}

///|
fn compat_expect_lowered_workflow_fixture_in(
  root : String,
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec, LoweringResult) {
  compat_expect_lowered_workflow_fixture(compat_fixture_dir(root, fixture_name))
}

///|
fn compat_push_event_fixture(fixture : CompatFixture) -> PushEvent? {
  match fixture.event_text {
    Some(event_text) =>
      match parse_github_push_event_json(event_text) {
        { event: Some(event), errors: [] } => Some(event)
        { event: None, errors } => abort(errors.join("\n"))
        { event: Some(_), errors } if errors.length() > 0 =>
          abort(errors.join("\n"))
        _ => None
      }
    None => None
  }
}

///|
fn compat_expect_push_event_fixture(fixture : CompatFixture) -> PushEvent {
  match compat_push_event_fixture(fixture) {
    Some(event) => event
    None => abort("fixture has no event.json: " + fixture.root_dir)
  }
}

///|
fn compat_remove_tree(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    return
  }
  if @xfs.is_dir(path) {
    for entry in @xfs.read_dir(path) {
      compat_remove_tree(compat_join_path(path, entry))
    }
    @xfs.remove_dir(path)
  } else {
    @xfs.remove_file(path)
  }
}

///|
fn compat_copy_tree(src : String, dst : String) -> Unit raise {
  if @xfs.is_dir(src) {
    if not(@xfs.path_exists(dst)) {
      @xfs.create_dir(dst)
    }
    for entry in @xfs.read_dir(src) {
      compat_copy_tree(
        compat_join_path(src, entry),
        compat_join_path(dst, entry),
      )
    }
    let github_dir = compat_join_path(src, ".github")
    if @xfs.path_exists(github_dir) &&
      not(@xfs.path_exists(compat_join_path(dst, ".github"))) {
      compat_copy_tree(github_dir, compat_join_path(dst, ".github"))
    }
  } else {
    @xfs.write_bytes_to_file(dst, @xfs.read_file_to_bytes(src))
  }
}

///|
fn compat_ensure_dir(path : String) -> Unit raise {
  if not(@xfs.path_exists(path)) {
    @xfs.create_dir(path)
  }
}

///|
fn compat_absolute_path(path : String) -> String {
  if path.has_prefix("/") {
    return path
  }
  let cwd = @xsys.get_env_var("PWD").unwrap_or(".")
  if cwd.has_suffix("/") {
    cwd + path
  } else {
    cwd + "/" + path
  }
}

///|
fn compat_prepare_workspace_in(
  root_dir : String,
  name : String,
  clean? : Bool = false,
  absolute? : Bool = false,
) -> String raise {
  compat_ensure_dir("_build")
  compat_ensure_dir(root_dir)
  let dir = compat_join_path(root_dir, name)
  if clean {
    compat_remove_tree(dir)
  }
  compat_ensure_dir(dir)
  if absolute {
    compat_absolute_path(dir)
  } else {
    dir
  }
}

///|
fn compat_prepare_copied_workspace_in(
  root_dir : String,
  name : String,
  source_dir : String,
  absolute? : Bool = false,
) -> String raise {
  let workspace = compat_prepare_workspace_in(
    root_dir,
    name,
    clean=true,
    absolute~,
  )
  compat_copy_tree(source_dir, workspace)
  workspace
}

///|
#cfg(target="native")
fn compat_prepare_workflow_fixture(
  fixture_dir : String,
  workspace_root : String,
  workspace_name : String,
  copy_fixture? : Bool = false,
  absolute? : Bool = false,
) -> (CompatFixture, WorkflowSpec, String) raise {
  let (fixture, workflow) = compat_expect_workflow_fixture(fixture_dir)
  let workspace = if copy_fixture {
    compat_prepare_copied_workspace_in(
      workspace_root,
      workspace_name,
      fixture.root_dir,
      absolute~,
    )
  } else {
    compat_prepare_workspace_in(workspace_root, workspace_name, absolute~)
  }
  (fixture, workflow, workspace)
}

///|
#cfg(target="native")
fn compat_prepare_workflow_fixture_auto(
  fixture_dir : String,
  workspace_root : String,
  workspace_prefix? : String = "",
  copy_fixture? : Bool = false,
  absolute? : Bool = false,
) -> (CompatFixture, WorkflowSpec, String) raise {
  compat_prepare_workflow_fixture(
    fixture_dir,
    workspace_root,
    compat_fixture_workspace_name(workspace_prefix, fixture_dir),
    copy_fixture~,
    absolute~,
  )
}

///|
fn compat_prepare_workspace(name : String) -> String raise {
  compat_prepare_workspace_in("_build/test-compat-fixtures", name)
}

///|
fn compat_fixture_dirs(root : String) -> Array[String] raise {
  let dirs : Array[String] = []
  if not(@xfs.path_exists(root)) || not(@xfs.is_dir(root)) {
    return dirs
  }
  if @xfs.path_exists(compat_join_path(root, "fixture.txt")) &&
    @xfs.path_exists(compat_join_path(root, "workflow.yml")) {
    dirs.push(root)
  }
  for entry in @xfs.read_dir(root) {
    let path = compat_join_path(root, entry)
    if @xfs.is_dir(path) {
      for child in compat_fixture_dirs(path) {
        dirs.push(child)
      }
    }
  }
  dirs
}

///|
test "compat fixture: load docs sample fixture" {
  let result = load_compat_fixture("testdata/docs/push-scalar")
  let fixture = compat_expect_fixture(result)

  inspect(fixture.id, content="docs-push-scalar")
  inspect(fixture.source, content="docs")
  inspect(fixture.mode, content="supported")
  inspect(fixture.kind, content="parse")
  inspect(fixture.url.has_prefix("https://docs.github.com/"), content="true")
  inspect(fixture.docs_urls, content="[]")
  inspect(fixture.added_at, content="2026-03-11")
  inspect(fixture.notes.length() > 0, content="true")
  inspect(fixture.root_dir, content="testdata/docs/push-scalar")
  inspect(
    fixture.workflow_path,
    content="testdata/docs/push-scalar/workflow.yml",
  )
  inspect(fixture.workflow_text.contains("'on': push"), content="true")
  inspect(fixture.event_path, content="None")
  inspect(fixture.event_text, content="None")
}

///|
test "compat fixture: load docs fixture with event json" {
  let fixture = compat_expect_fixture(
    load_compat_fixture("testdata/docs/context-github-actor"),
  )
  let parsed_event = compat_expect_push_event_fixture(fixture)

  inspect(
    fixture.event_path.unwrap_or(""),
    content="testdata/docs/context-github-actor/event.json",
  )
  inspect(parsed_event.actor, content="octocat")
  inspect(parsed_event.after_sha, content="abc123def456")
}

///|
test "compat fixture: github context docs fixtures include event json" {
  let dirs = [
    "testdata/docs/context-github-ref", "testdata/docs/context-github-repository",
    "testdata/docs/context-github-repository-owner", "testdata/docs/context-github-actor",
  ]
  for dir in dirs {
    let fixture = compat_expect_fixture(load_compat_fixture(dir))
    let event = compat_expect_push_event_fixture(fixture)
    inspect(fixture.event_path is Some(_), content="true")
    inspect(event.ref_name, content="main")
    inspect(event.after_sha, content="abc123def456")
  }
}

///|
test "compat fixture: workspace name derives from leaf dir" {
  inspect(
    compat_fixture_leaf_name("testdata/docs/context-github-actor"),
    content="context-github-actor",
  )
  inspect(
    compat_fixture_dir("testdata/docs", "push-scalar"),
    content="testdata/docs/push-scalar",
  )
  inspect(
    compat_fixture_workspace_name(
      "languageservices", "testdata/upstream/languageservices/expr-env-basic",
    ),
    content="languageservices-expr-env-basic",
  )
  inspect(
    compat_fixture_workspace_name("", "testdata/upstream/act/shells-bash"),
    content="shells-bash",
  )
}

///|
test "compat fixture: suite configs centralize roots and prefixes" {
  let docs = compat_docs_suite()
  let languageservices = compat_languageservices_suite()
  let act = compat_act_suite()

  inspect(docs.expected_source, content="docs")
  inspect(docs.fixture_root, content="testdata/docs")
  inspect(languageservices.expected_source, content="actions-languageservices")
  inspect(languageservices.workspace_prefix, content="languageservices")
  inspect(act.expected_source, content="nektos-act")
  inspect(act.workspace_root, content="_build/test-workspaces")
  inspect(
    act.copied_workspace_root,
    content="_build/test-compat-act-workspaces",
  )
  inspect(act.copied_workspace_prefix, content="")
}

///|
test "compat fixture: prepare workspace in root can return absolute path" {
  let workspace = compat_prepare_workspace_in(
    "_build/test-compat-shared-workspaces",
    "absolute",
    absolute=true,
  )

  inspect(workspace.has_prefix("/"), content="true")
  inspect(
    @xfs.path_exists("_build/test-compat-shared-workspaces/absolute"),
    content="true",
  )
}

///|
test "compat fixture: copied workspace clears stale files" {
  let source = compat_prepare_workspace_in(
    "_build/test-compat-shared-sources",
    "copy-source",
    clean=true,
  )
  @xfs.write_string_to_file(source + "/fresh.txt", "fresh")

  let copied = compat_prepare_copied_workspace_in(
    "_build/test-compat-shared-copies", "copy-dst", source,
  )
  @xfs.write_string_to_file(copied + "/stale.txt", "stale")

  let copied_again = compat_prepare_copied_workspace_in(
    "_build/test-compat-shared-copies", "copy-dst", source,
  )

  inspect(copied_again, content="_build/test-compat-shared-copies/copy-dst")
  inspect(@xfs.path_exists(copied_again + "/fresh.txt"), content="true")
  inspect(@xfs.path_exists(copied_again + "/stale.txt"), content="false")
}

///|
#cfg(target="native")
test "compat fixture: prepare workflow fixture auto loads workflow" {
  let suite : CompatFixtureSuite = {
    expected_source: "docs",
    fixture_root: "testdata/docs",
    workspace_root: "_build/test-compat-shared-workflow-fixtures",
    workspace_prefix: "",
    copied_workspace_root: "_build/test-compat-shared-workflow-fixtures",
    copied_workspace_prefix: "",
  }
  let (fixture, workflow, workspace) = compat_prepare_suite_fixture_auto(
    suite, "push-scalar",
  )

  inspect(fixture.id, content="docs-push-scalar")
  inspect(workflow.name, content="ci")
  inspect(workspace.has_prefix("/"), content="true")
  inspect(@xfs.path_exists(workspace), content="true")
}

///|
#cfg(target="native")
test "compat fixture: expect lowered workflow fixture lowers workflow" {
  let (fixture, _, lowered) = compat_expect_lowered_suite_fixture(
    compat_docs_suite(),
    "env-precedence",
  )

  inspect(fixture.id, content="docs-env-precedence")
  inspect(lowered.errors, content="[]")
  inspect(
    find_task_plan(lowered.plan, "build/print") is Some(_),
    content="true",
  )
}

///|
#cfg(target="native")
test "compat fixture: expect workflow fixture in root loads workflow" {
  let (fixture, workflow) = compat_expect_suite_fixture(
    compat_docs_suite(),
    "push-scalar",
  )

  inspect(fixture.id, content="docs-push-scalar")
  inspect(workflow.name, content="ci")
}

///|
#cfg(target="native")
test "compat fixture: prepare copied workflow fixture auto copies fixture files" {
  let suite : CompatFixtureSuite = {
    expected_source: "nektos-act",
    fixture_root: "testdata/upstream/act",
    workspace_root: "_build/test-compat-shared-workflow-copies",
    workspace_prefix: "compat-act",
    copied_workspace_root: "_build/test-compat-shared-workflow-copies",
    copied_workspace_prefix: "",
  }
  let (fixture, _, workspace) = compat_prepare_suite_fixture_auto(
    suite,
    "set-env-step-env-override",
    copy_fixture=true,
  )

  inspect(fixture.id, content="act-set-env-step-env-override")
  inspect(@xfs.path_exists(workspace + "/workflow.yml"), content="true")
  inspect(@xfs.path_exists(workspace + "/action/action.yml"), content="true")
}

///|
test "compat fixture: reject missing metadata" {
  let dir = compat_prepare_workspace("missing-metadata")
  let workflow_text =
    #|name: ci
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo ok
  @xfs.write_string_to_file(dir + "/workflow.yml", workflow_text)

  let result = load_compat_fixture(dir)
  match result.fixture {
    Some(_) => abort("fixture should be None")
    None => ()
  }
  inspect(
    result.errors,
    content="[\"missing fixture.txt: _build/test-compat-fixtures/missing-metadata/fixture.txt\"]",
  )
}

///|
test "compat fixture: act fixtures include official docs refs" {
  let fixture_dirs = compat_fixture_dirs("testdata/upstream/act")
  inspect(fixture_dirs.length() > 0, content="true")

  for dir in fixture_dirs {
    let fixture = compat_expect_fixture(load_compat_fixture(dir))
    inspect(fixture.source, content="nektos-act")
    inspect(fixture.docs_urls.length() > 0, content="true")
    for url in fixture.docs_urls {
      inspect(url.has_prefix("https://docs.github.com/"), content="true")
    }
  }
}

///|
test "compat fixture: upstream fixtures are classified with stable metadata" {
  let fixture_dirs = compat_fixture_dirs("testdata/upstream")
  let ids : Map[String, Bool] = {}

  inspect(fixture_dirs.length() > 0, content="true")
  for dir in fixture_dirs {
    let fixture = compat_expect_fixture(load_compat_fixture(dir))
    let valid_source = fixture.source == "actions-languageservices" ||
      fixture.source == "nektos-act"
    let valid_mode = fixture.mode == "supported" ||
      fixture.mode == "unsupported" ||
      fixture.mode == "known_diff"

    inspect(valid_source, content="true")
    inspect(valid_mode, content="true")
    inspect(fixture.url.has_prefix("https://"), content="true")
    inspect(fixture.notes.length() > 0, content="true")
    inspect(ids.get(fixture.id) is None, content="true")
    ids[fixture.id] = true

    if fixture.mode != "supported" {
      inspect(fixture.notes.length() > 0, content="true")
    }
    if fixture.source == "nektos-act" {
      inspect(fixture.docs_urls.length() > 0, content="true")
      for url in fixture.docs_urls {
        inspect(url.has_prefix("https://docs.github.com/"), content="true")
      }
    }
  }
}
