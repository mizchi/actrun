///|
test "version consistency: detects mixed versions" {
  let w1 = @ar.new_workflow("ci", [
    @ar.new_job("build", [@ar.new_uses_step("s1", "actions/checkout@v5")]),
  ])
  let w2 = @ar.new_workflow("release", [
    @ar.new_job("build", [@ar.new_uses_step("s1", "actions/checkout@v4")]),
  ])
  let refs1 = collect_action_refs(w1)
  let refs2 = collect_action_refs(w2)
  let diags = check_version_consistency([
    ("ci.yml", refs1),
    ("release.yml", refs2),
  ])
  assert_true(diags.length() > 0)
  assert_eq(diags[0].code, "inconsistent-action-version")
  assert_eq(diags[0].severity, Warning)
  assert_true(diags[0].message.contains("actions/checkout"))
}

///|
test "version consistency: same version no warnings" {
  let w1 = @ar.new_workflow("ci", [
    @ar.new_job("build", [@ar.new_uses_step("s1", "actions/checkout@v5")]),
  ])
  let w2 = @ar.new_workflow("release", [
    @ar.new_job("build", [@ar.new_uses_step("s1", "actions/checkout@v5")]),
  ])
  let refs1 = collect_action_refs(w1)
  let refs2 = collect_action_refs(w2)
  let diags = check_version_consistency([
    ("ci.yml", refs1),
    ("release.yml", refs2),
  ])
  assert_eq(diags.length(), 0)
}
