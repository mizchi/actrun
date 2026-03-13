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
  inspect(github_checkout.capabilities.host, content="true")
  inspect(github_checkout.capabilities.docker, content="false")
  inspect(github_checkout.capabilities.wasm, content="false")
  inspect(builtin_checkout.kind, content="checkout")
  inspect(builtin_checkout.backend, content="builtin")
  inspect(builtin_checkout.capabilities.host, content="true")
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
  inspect(upload.capabilities.host, content="true")
  inspect(download.kind, content="download-artifact")
  inspect(download.backend, content="builtin")
  inspect(download.capabilities.host, content="true")
}

///|
test "action ref: resolve builtin cache aliases" {
  let restore = expect_resolved(resolve_action_uses("actions/cache/restore@v4"))
  let save = expect_resolved(resolve_action_uses("actions/cache/save@v4"))

  inspect(restore.kind, content="cache-restore")
  inspect(restore.backend, content="builtin")
  inspect(restore.capabilities.host, content="true")
  inspect(save.kind, content="cache-save")
  inspect(save.backend, content="builtin")
  inspect(save.capabilities.host, content="true")
}

///|
test "action ref: resolve builtin cache main alias" {
  let cache = expect_resolved(resolve_action_uses("actions/cache@v4"))

  inspect(cache.kind, content="cache")
  inspect(cache.backend, content="builtin")
  inspect(cache.capabilities.host, content="true")
}

///|
test "action ref: resolve builtin setup-node alias" {
  let setup = expect_resolved(resolve_action_uses("actions/setup-node@v4"))

  inspect(setup.kind, content="setup-node")
  inspect(setup.backend, content="builtin")
  inspect(setup.capabilities.host, content="true")
}

///|
test "action ref: resolve docker image action" {
  let docker_action = expect_resolved(
    resolve_action_uses("docker://alpine:3.21"),
  )

  inspect(docker_action.kind, content="docker-image")
  inspect(docker_action.backend, content="docker")
  inspect(docker_action.capabilities.host, content="false")
  inspect(docker_action.capabilities.docker, content="true")
  inspect(docker_action.capabilities.wasm, content="false")
  inspect(docker_action.uses, content="docker://alpine:3.21")
  inspect(docker_action.image.unwrap_or(""), content="alpine:3.21")
  inspect(docker_action.args, content="[]")
}

///|
test "action ref: resolve wasm registry action" {
  let wasm_action = expect_resolved(resolve_action_uses("wasm://std/echo@v1"))

  inspect(wasm_action.kind, content="wasm-module")
  inspect(wasm_action.backend, content="wasm")
  inspect(wasm_action.capabilities.host, content="false")
  inspect(wasm_action.capabilities.docker, content="false")
  inspect(wasm_action.capabilities.wasm, content="true")
  inspect(wasm_action.entrypoint.unwrap_or(""), content="std/echo@v1")
}

///|
test "action ref: backend capability presets include wasm" {
  let host = backend_capabilities_for("node")
  let docker = backend_capabilities_for("docker")
  let wasm = backend_capabilities_for("wasm")

  inspect(host.host, content="true")
  inspect(host.docker, content="false")
  inspect(docker.host, content="false")
  inspect(docker.docker, content="true")
  inspect(wasm.host, content="false")
  inspect(wasm.wasm, content="true")
}

///|
test "action ref: unresolved custom registry action is rejected" {
  let result = resolve_action_uses("bit://std/cache@v1")

  inspect(
    result.errors,
    content="[\"action 'bit://std/cache@v1' is not supported in MVP\"]",
  )
}
