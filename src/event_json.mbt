///|
fn push_event_json_error(message : String) -> PushEventJsonParseResult {
  { event: None, errors: [message] }
}

///|
fn push_event_json_field(obj : Json, key : String) -> Json? {
  if obj is Object(fields) {
    fields.get(key)
  } else {
    None
  }
}

///|
fn push_event_json_string(obj : Json, key : String) -> String? {
  match push_event_json_field(obj, key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn push_event_json_object(obj : Json, key : String) -> Json? {
  match push_event_json_field(obj, key) {
    Some(value) => if value is Object(_) { Some(value) } else { None }
    _ => None
  }
}

///|
fn push_event_json_string_array(obj : Json, key : String) -> Array[String] {
  let values : Array[String] = []
  match push_event_json_field(obj, key) {
    Some(Array(items)) =>
      for item in items {
        if item is String(value) {
          values.push(value)
        }
      }
    _ => ()
  }
  values
}

///|
fn push_event_strip_ref(ref_name : String) -> String {
  if ref_name.has_prefix("refs/heads/") {
    return String::unsafe_substring(ref_name, start=11, end=ref_name.length())
  }
  if ref_name.has_prefix("refs/tags/") {
    return String::unsafe_substring(ref_name, start=10, end=ref_name.length())
  }
  ref_name
}

///|
fn push_event_append_unique(
  paths : Array[String],
  extra : Array[String],
) -> Unit {
  for path in extra {
    if path.length() == 0 {
      continue
    }
    if not(paths.contains(path)) {
      paths.push(path)
    }
  }
}

///|
fn push_event_collect_changed_paths(payload : Json) -> Array[String] {
  let paths : Array[String] = []
  match push_event_json_field(payload, "commits") {
    Some(Array(commits)) =>
      for commit in commits {
        push_event_append_unique(
          paths,
          push_event_json_string_array(commit, "added"),
        )
        push_event_append_unique(
          paths,
          push_event_json_string_array(commit, "modified"),
        )
        push_event_append_unique(
          paths,
          push_event_json_string_array(commit, "removed"),
        )
      }
    _ => ()
  }
  match push_event_json_object(payload, "head_commit") {
    Some(head_commit) if paths.length() == 0 => {
      push_event_append_unique(
        paths,
        push_event_json_string_array(head_commit, "added"),
      )
      push_event_append_unique(
        paths,
        push_event_json_string_array(head_commit, "modified"),
      )
      push_event_append_unique(
        paths,
        push_event_json_string_array(head_commit, "removed"),
      )
    }
    _ => ()
  }
  paths.sort_by(String::lexical_compare)
  paths
}

///|
pub fn parse_github_push_event_json(text : String) -> PushEventJsonParseResult {
  let payload = @json.parse(text) catch {
    err =>
      return push_event_json_error(
        "failed to parse push event JSON: " + err.to_string(),
      )
  }
  guard payload is Object(_) else {
    return push_event_json_error("push event payload must be a JSON object")
  }

  let errors : Array[String] = []
  let ref_value = push_event_json_string(payload, "ref").unwrap_or("")
  let before_sha = push_event_json_string(payload, "before").unwrap_or("")
  let after_sha = push_event_json_string(payload, "after").unwrap_or("")
  if ref_value.length() == 0 {
    errors.push("push event JSON is missing string field `ref`")
  }
  if before_sha.length() == 0 {
    errors.push("push event JSON is missing string field `before`")
  }
  if after_sha.length() == 0 {
    errors.push("push event JSON is missing string field `after`")
  }
  if errors.length() > 0 {
    return { event: None, errors }
  }

  let repository = match push_event_json_object(payload, "repository") {
    Some(repo) => push_event_json_string(repo, "full_name").unwrap_or("")
    None => ""
  }
  let actor = match push_event_json_object(payload, "sender") {
    Some(sender) => push_event_json_string(sender, "login").unwrap_or("")
    None => ""
  }
  let changed_paths = push_event_collect_changed_paths(payload)

  {
    event: Some(
      new_push_event(
        push_event_strip_ref(ref_value),
        changed_paths,
        before_sha~,
        after_sha~,
        repository~,
        actor~,
      ),
    ),
    errors: [],
  }
}
