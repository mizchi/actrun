///|
fn prop_push_trigger_without_filters_accepts_any_branch(
  ref_name : String,
) -> Bool {
  matches_push_trigger(
    new_push_trigger(),
    new_push_event(ref_name, ["src/lib.mbt"]),
  )
}

///|
test "quickcheck push trigger without filters accepts everything" {
  @qc.quick_check_fn(prop_push_trigger_without_filters_accepts_any_branch)
}
