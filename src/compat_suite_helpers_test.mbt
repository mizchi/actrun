///|
struct CompatFixtureSuite {
  expected_source : String
  fixture_root : String
  workspace_root : String
  workspace_prefix : String
  copied_workspace_root : String
  copied_workspace_prefix : String
}

///|
fn compat_docs_suite() -> CompatFixtureSuite {
  {
    expected_source: "docs",
    fixture_root: "testdata/docs",
    workspace_root: "_build/test-compat-docs-workspaces",
    workspace_prefix: "",
    copied_workspace_root: "_build/test-compat-docs-workspaces",
    copied_workspace_prefix: "",
  }
}

///|
fn compat_languageservices_suite() -> CompatFixtureSuite {
  {
    expected_source: "actions-languageservices",
    fixture_root: "testdata/upstream/languageservices",
    workspace_root: "_build/test-compat-docs-workspaces",
    workspace_prefix: "languageservices",
    copied_workspace_root: "_build/test-compat-docs-workspaces",
    copied_workspace_prefix: "languageservices",
  }
}

///|
fn compat_act_suite() -> CompatFixtureSuite {
  {
    expected_source: "nektos-act",
    fixture_root: "testdata/upstream/act",
    workspace_root: "_build/test-workspaces",
    workspace_prefix: "compat-act",
    copied_workspace_root: "_build/test-compat-act-workspaces",
    copied_workspace_prefix: "",
  }
}

///|
fn compat_expect_suite_source(
  suite : CompatFixtureSuite,
  fixture : CompatFixture,
) -> CompatFixture {
  if fixture.source != suite.expected_source {
    abort(
      "fixture source mismatch: expected " +
      suite.expected_source +
      " but got " +
      fixture.source +
      " for " +
      fixture.root_dir,
    )
  }
  fixture
}

///|
#cfg(target="native")
fn compat_prepare_suite_fixture_auto(
  suite : CompatFixtureSuite,
  fixture_name : String,
  copy_fixture? : Bool = false,
) -> (CompatFixture, WorkflowSpec, String) raise {
  let fixture_dir = compat_fixture_dir(suite.fixture_root, fixture_name)
  if copy_fixture {
    let (fixture, workflow, workspace) = compat_prepare_workflow_fixture_auto(
      fixture_dir,
      suite.copied_workspace_root,
      workspace_prefix=suite.copied_workspace_prefix,
      copy_fixture=true,
      absolute=true,
    )
    (compat_expect_suite_source(suite, fixture), workflow, workspace)
  } else {
    let (fixture, workflow, workspace) = compat_prepare_workflow_fixture_auto(
      fixture_dir,
      suite.workspace_root,
      workspace_prefix=suite.workspace_prefix,
      absolute=true,
    )
    (compat_expect_suite_source(suite, fixture), workflow, workspace)
  }
}

///|
fn compat_expect_suite_fixture(
  suite : CompatFixtureSuite,
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec) {
  let (fixture, workflow) = compat_expect_workflow_fixture_in(
    suite.fixture_root,
    fixture_name,
  )
  (compat_expect_suite_source(suite, fixture), workflow)
}

///|
fn compat_expect_lowered_suite_fixture(
  suite : CompatFixtureSuite,
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec, LoweringResult) {
  let (fixture, workflow, lowered) = compat_expect_lowered_workflow_fixture_in(
    suite.fixture_root,
    fixture_name,
  )
  (compat_expect_suite_source(suite, fixture), workflow, lowered)
}

///|
#cfg(target="native")
fn compat_prepare_docs_fixture_auto(
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec, String) raise {
  compat_prepare_suite_fixture_auto(compat_docs_suite(), fixture_name)
}

///|
fn compat_expect_docs_fixture(
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec) {
  compat_expect_suite_fixture(compat_docs_suite(), fixture_name)
}

///|
fn compat_expect_lowered_docs_fixture(
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec, LoweringResult) {
  compat_expect_lowered_suite_fixture(compat_docs_suite(), fixture_name)
}

///|
#cfg(target="native")
fn compat_prepare_languageservices_fixture_auto(
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec, String) raise {
  compat_prepare_suite_fixture_auto(
    compat_languageservices_suite(),
    fixture_name,
  )
}

///|
fn compat_expect_languageservices_fixture(
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec) {
  compat_expect_suite_fixture(compat_languageservices_suite(), fixture_name)
}

///|
fn compat_expect_lowered_languageservices_fixture(
  fixture_name : String,
) -> (CompatFixture, WorkflowSpec, LoweringResult) {
  compat_expect_lowered_suite_fixture(
    compat_languageservices_suite(),
    fixture_name,
  )
}

///|
#cfg(target="native")
fn compat_prepare_act_fixture_auto(
  fixture_name : String,
  copy_fixture? : Bool = false,
) -> (CompatFixture, WorkflowSpec, String) raise {
  compat_prepare_suite_fixture_auto(
    compat_act_suite(),
    fixture_name,
    copy_fixture~,
  )
}
