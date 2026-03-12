///|
fn expect_parsed_push_event(result : PushEventJsonParseResult) -> PushEvent {
  match result.event {
    Some(event) => event
    None => abort(result.errors.join("\n"))
  }
}

///|
test "push event json: parses minimal GitHub push payload" {
  let payload =
    #|{
    #|  "ref": "refs/heads/main",
    #|  "before": "def456",
    #|  "after": "abc123",
    #|  "repository": { "full_name": "mizchi/action_runner" },
    #|  "sender": { "login": "octocat" },
    #|  "commits": [
    #|    {
    #|      "added": ["src/new.mbt"],
    #|      "modified": ["README.md", "src/lib.mbt"],
    #|      "removed": []
    #|    },
    #|    {
    #|      "added": [],
    #|      "modified": ["src/lib.mbt"],
    #|      "removed": ["old.txt"]
    #|    }
    #|  ]
    #|}
  let result = parse_github_push_event_json(payload)
  let event = expect_parsed_push_event(result)

  inspect(result.errors, content="[]")
  inspect(event.ref_name, content="main")
  inspect(event.before_sha, content="def456")
  inspect(event.after_sha, content="abc123")
  inspect(event.repository, content="mizchi/action_runner")
  inspect(event.actor, content="octocat")
  inspect(
    event.changed_paths,
    content="[\"README.md\", \"old.txt\", \"src/lib.mbt\", \"src/new.mbt\"]",
  )
}

///|
test "push event json: falls back to head_commit changed paths" {
  let payload =
    #|{
    #|  "ref": "refs/heads/main",
    #|  "before": "def456",
    #|  "after": "abc123",
    #|  "head_commit": {
    #|    "added": ["src/new.mbt"],
    #|    "modified": ["README.md"],
    #|    "removed": ["old.txt"]
    #|  }
    #|}
  let result = parse_github_push_event_json(payload)
  let event = expect_parsed_push_event(result)

  inspect(result.errors, content="[]")
  inspect(
    event.changed_paths,
    content="[\"README.md\", \"old.txt\", \"src/new.mbt\"]",
  )
}

///|
test "push event json: reports missing required fields" {
  let result = parse_github_push_event_json("{\"repository\":{}}")

  inspect(
    result.errors,
    content="[\"push event JSON is missing string field `ref`\", \"push event JSON is missing string field `before`\", \"push event JSON is missing string field `after`\"]",
  )
}
