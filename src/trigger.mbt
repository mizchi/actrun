///|
fn wildcard_match(pattern : String, text : String) -> Bool {
  let mut p = 0
  let mut t = 0
  let mut star = -1
  let mut mark = 0
  while t < text.length() {
    if p < pattern.length() {
      let pc = pattern.unsafe_get(p)
      let tc = text.unsafe_get(t)
      if pc == '*' {
        star = p
        p += 1
        mark = t
        continue
      }
      if pc == tc {
        p += 1
        t += 1
        continue
      }
    }
    if star >= 0 {
      p = star + 1
      mark += 1
      t = mark
    } else {
      return false
    }
  }
  while p < pattern.length() && pattern.unsafe_get(p) == '*' {
    p += 1
  }
  p == pattern.length()
}

///|
fn matches_any_pattern(patterns : Array[String], value : String) -> Bool {
  for pattern in patterns {
    if wildcard_match(pattern, value) {
      return true
    }
  }
  false
}

///|
fn has_matching_changed_path(
  patterns : Array[String],
  changed_paths : Array[String],
) -> Bool {
  for path in changed_paths {
    if matches_any_pattern(patterns, path) {
      return true
    }
  }
  false
}

///|
fn has_non_ignored_path(
  ignored_patterns : Array[String],
  changed_paths : Array[String],
) -> Bool {
  for path in changed_paths {
    if !matches_any_pattern(ignored_patterns, path) {
      return true
    }
  }
  false
}

///|
pub fn matches_push_trigger(trigger : PushTrigger, event : PushEvent) -> Bool {
  if trigger.tags.length() > 0 &&
    !matches_any_pattern(trigger.tags, event.ref_name) {
    return false
  }
  if trigger.tags_ignore.length() > 0 &&
    matches_any_pattern(trigger.tags_ignore, event.ref_name) {
    return false
  }
  if trigger.branches.length() > 0 &&
    !matches_any_pattern(trigger.branches, event.ref_name) {
    return false
  }
  if trigger.branches_ignore.length() > 0 &&
    matches_any_pattern(trigger.branches_ignore, event.ref_name) {
    return false
  }
  if trigger.paths.length() > 0 &&
    !has_matching_changed_path(trigger.paths, event.changed_paths) {
    return false
  }
  if trigger.paths_ignore.length() > 0 &&
    event.changed_paths.length() > 0 &&
    !has_non_ignored_path(trigger.paths_ignore, event.changed_paths) {
    return false
  }
  true
}
