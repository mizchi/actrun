///|
fn sample_workflow() -> WorkflowSpec {
  new_workflow(
    "ci",
    [
      new_job("build", [
        new_run_step("install", "pnpm install"),
        new_run_step("test", "pnpm test"),
      ]),
      new_job("lint", [new_run_step("lint", "pnpm lint")], needs=["build"]),
    ],
    defaults=new_run_defaults(shell=Some("bash")),
  )
}

///|
test "lowering benchmark" (b : @bench.T) {
  let workflow = sample_workflow()
  b.bench(() => ignore(lower_push_workflow(workflow)))
}
