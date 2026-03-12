///|
fn expect_action(result : ActionRefParseResult) -> ActionRef {
  match result.action {
    Some(action) => action
    None => abort(result.errors.join("\n"))
  }
}

///|
fn expect_resolved(result : ActionResolutionResult) -> ResolvedAction {
  match result.action {
    Some(action) => action
    None => abort(result.errors.join("\n"))
  }
}

///|
test "action ref: parse github repo action" {
  let action = expect_action(parse_action_ref("actions/checkout@v4"))

  match action {
    GitHubRepo(owner, repo, version, subpath) => {
      inspect(owner, content="actions")
      inspect(repo, content="checkout")
      inspect(version, content="v4")
      inspect(subpath, content="None")
    }
    _ => abort("expected github repo action")
  }
}

///|
test "action ref: parse custom registry action" {
  let action = expect_action(parse_action_ref("bit://std/cache@v1"))

  match action {
    Registry(scheme, name, version) => {
      inspect(scheme, content="bit")
      inspect(name, content="std/cache")
      inspect(version, content="v1")
    }
    _ => abort("expected registry action")
  }
}

///|
test "action ref: resolve builtin checkout aliases" {
  let github_checkout = expect_resolved(
    resolve_action_uses("actions/checkout@v4"),
  )
  let builtin_checkout = expect_resolved(
    resolve_action_uses("builtin://checkout"),
  )

  inspect(github_checkout.kind, content="checkout")
  inspect(github_checkout.backend, content="builtin")
  inspect(builtin_checkout.kind, content="checkout")
  inspect(builtin_checkout.backend, content="builtin")
}

///|
test "action ref: resolve builtin artifact aliases" {
  let upload = expect_resolved(
    resolve_action_uses("actions/upload-artifact@v4"),
  )
  let download = expect_resolved(
    resolve_action_uses("actions/download-artifact@v4"),
  )

  inspect(upload.kind, content="upload-artifact")
  inspect(upload.backend, content="builtin")
  inspect(download.kind, content="download-artifact")
  inspect(download.backend, content="builtin")
}

///|
test "action ref: resolve builtin cache aliases" {
  let restore = expect_resolved(resolve_action_uses("actions/cache/restore@v4"))
  let save = expect_resolved(resolve_action_uses("actions/cache/save@v4"))

  inspect(restore.kind, content="cache-restore")
  inspect(restore.backend, content="builtin")
  inspect(save.kind, content="cache-save")
  inspect(save.backend, content="builtin")
}

///|
test "action ref: resolve builtin cache main alias" {
  let cache = expect_resolved(resolve_action_uses("actions/cache@v4"))

  inspect(cache.kind, content="cache")
  inspect(cache.backend, content="builtin")
}

///|
test "action ref: resolve builtin setup-node alias" {
  let setup = expect_resolved(resolve_action_uses("actions/setup-node@v4"))

  inspect(setup.kind, content="setup-node")
  inspect(setup.backend, content="builtin")
}

///|
test "action ref: resolve docker image action" {
  let docker_action = expect_resolved(
    resolve_action_uses("docker://alpine:3.21"),
  )

  inspect(docker_action.kind, content="docker-image")
  inspect(docker_action.backend, content="docker")
  inspect(docker_action.uses, content="docker://alpine:3.21")
  inspect(docker_action.image.unwrap_or(""), content="alpine:3.21")
  inspect(docker_action.args, content="[]")
}

///|
test "action ref: unresolved custom registry action is rejected" {
  let result = resolve_action_uses("bit://std/cache@v1")

  inspect(
    result.errors,
    content="[\"action 'bit://std/cache@v1' is not supported in MVP\"]",
  )
}
