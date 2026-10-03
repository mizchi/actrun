///|
fn expect_parsed_push_event(
  result : @actrun.PushEventJsonParseResult,
) -> @actrun.PushEvent {
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
    #|  "repository": { "full_name": "mizchi/actrun" },
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
  let result = @actrun.parse_github_push_event_json(payload)
  let event = expect_parsed_push_event(result)

  @debug.debug_inspect(result.errors, content="[]")
  @debug.debug_inspect(
    event.ref_name,
    content=(
      #|"main"
    ),
  )
  @debug.debug_inspect(
    event.before_sha,
    content=(
      #|"def456"
    ),
  )
  @debug.debug_inspect(
    event.after_sha,
    content=(
      #|"abc123"
    ),
  )
  @debug.debug_inspect(
    event.repository,
    content=(
      #|"mizchi/actrun"
    ),
  )
  @debug.debug_inspect(
    event.actor,
    content=(
      #|"octocat"
    ),
  )
  @debug.debug_inspect(
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
  let result = @actrun.parse_github_push_event_json(payload)
  let event = expect_parsed_push_event(result)

  @debug.debug_inspect(result.errors, content="[]")
  @debug.debug_inspect(
    event.changed_paths,
    content="[\"README.md\", \"old.txt\", \"src/new.mbt\"]",
  )
}

///|
test "push event json: reports missing required fields" {
  let result = @actrun.parse_github_push_event_json("{\"repository\":{}}")

  @debug.debug_inspect(
    result.errors,
    content=(
      #|[
      #|  "push event JSON is missing string field `ref`",
      #|  "push event JSON is missing string field `before`",
      #|  "push event JSON is missing string field `after`",
      #|]
    ),
  )
}
