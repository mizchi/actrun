///|
fn expect_action(result : @actrun.ActionRefParseResult) -> @actrun.ActionRef {
  match result.action {
    Some(action) => action
    None => abort(result.errors.join("\n"))
  }
}

///|
fn expect_resolved(
  result : @actrun.ActionResolutionResult,
) -> @actrun.ResolvedAction {
  match result.action {
    Some(action) => action
    None => abort(result.errors.join("\n"))
  }
}

///|
test "action ref: parse github repo action" {
  let action = expect_action(@actrun.parse_action_ref("actions/checkout@v4"))

  match action {
    GitHubRepo(owner, repo, version, subpath) => {
      @debug.debug_inspect(
        owner,
        content=(
          #|"actions"
        ),
      )
      @debug.debug_inspect(
        repo,
        content=(
          #|"checkout"
        ),
      )
      @debug.debug_inspect(
        version,
        content=(
          #|"v4"
        ),
      )
      @debug.debug_inspect(subpath, content="None")
    }
    _ => abort("expected github repo action")
  }
}

///|
test "action ref: parse custom registry action" {
  let action = expect_action(@actrun.parse_action_ref("bit://std/cache@v1"))

  match action {
    Registry(scheme, name, version) => {
      @debug.debug_inspect(
        scheme,
        content=(
          #|"bit"
        ),
      )
      @debug.debug_inspect(
        name,
        content=(
          #|"std/cache"
        ),
      )
      @debug.debug_inspect(
        version,
        content=(
          #|"v1"
        ),
      )
    }
    _ => abort("expected registry action")
  }
}

///|
test "action ref: resolve builtin checkout aliases" {
  let github_checkout = expect_resolved(
    @actrun.resolve_action_uses("actions/checkout@v4"),
  )
  let builtin_checkout = expect_resolved(
    @actrun.resolve_action_uses("builtin://checkout"),
  )

  @debug.debug_inspect(
    github_checkout.kind,
    content=(
      #|"checkout"
    ),
  )
  @debug.debug_inspect(
    github_checkout.backend,
    content=(
      #|"builtin"
    ),
  )
  @debug.debug_inspect(github_checkout.capabilities.host, content="true")
  @debug.debug_inspect(github_checkout.capabilities.docker, content="false")
  @debug.debug_inspect(github_checkout.capabilities.wasm, content="false")
  @debug.debug_inspect(
    builtin_checkout.kind,
    content=(
      #|"checkout"
    ),
  )
  @debug.debug_inspect(
    builtin_checkout.backend,
    content=(
      #|"builtin"
    ),
  )
  @debug.debug_inspect(builtin_checkout.capabilities.host, content="true")
}

///|
test "action ref: resolve builtin artifact aliases" {
  let upload = expect_resolved(
    @actrun.resolve_action_uses("actions/upload-artifact@v4"),
  )
  let download = expect_resolved(
    @actrun.resolve_action_uses("actions/download-artifact@v4"),
  )

  @debug.debug_inspect(
    upload.kind,
    content=(
      #|"upload-artifact"
    ),
  )
  @debug.debug_inspect(
    upload.backend,
    content=(
      #|"builtin"
    ),
  )
  @debug.debug_inspect(upload.capabilities.host, content="true")
  @debug.debug_inspect(
    download.kind,
    content=(
      #|"download-artifact"
    ),
  )
  @debug.debug_inspect(
    download.backend,
    content=(
      #|"builtin"
    ),
  )
  @debug.debug_inspect(download.capabilities.host, content="true")
}

///|
test "action ref: resolve builtin cache aliases" {
  let restore = expect_resolved(
    @actrun.resolve_action_uses("actions/cache/restore@v4"),
  )
  let save = expect_resolved(
    @actrun.resolve_action_uses("actions/cache/save@v4"),
  )

  @debug.debug_inspect(
    restore.kind,
    content=(
      #|"cache-restore"
    ),
  )
  @debug.debug_inspect(
    restore.backend,
    content=(
      #|"builtin"
    ),
  )
  @debug.debug_inspect(restore.capabilities.host, content="true")
  @debug.debug_inspect(
    save.kind,
    content=(
      #|"cache-save"
    ),
  )
  @debug.debug_inspect(
    save.backend,
    content=(
      #|"builtin"
    ),
  )
  @debug.debug_inspect(save.capabilities.host, content="true")
}

///|
test "action ref: resolve builtin cache main alias" {
  let cache = expect_resolved(@actrun.resolve_action_uses("actions/cache@v4"))

  @debug.debug_inspect(
    cache.kind,
    content=(
      #|"cache"
    ),
  )
  @debug.debug_inspect(
    cache.backend,
    content=(
      #|"builtin"
    ),
  )
  @debug.debug_inspect(cache.capabilities.host, content="true")
}

///|
test "action ref: resolve builtin setup-node alias" {
  let setup = expect_resolved(
    @actrun.resolve_action_uses("actions/setup-node@v4"),
  )

  @debug.debug_inspect(
    setup.kind,
    content=(
      #|"setup-node"
    ),
  )
  @debug.debug_inspect(
    setup.backend,
    content=(
      #|"builtin"
    ),
  )
  @debug.debug_inspect(setup.capabilities.host, content="true")
}

///|
test "action ref: resolve docker image action" {
  let docker_action = expect_resolved(
    @actrun.resolve_action_uses("docker://alpine:3.21"),
  )

  @debug.debug_inspect(
    docker_action.kind,
    content=(
      #|"docker-image"
    ),
  )
  @debug.debug_inspect(
    docker_action.backend,
    content=(
      #|"docker"
    ),
  )
  @debug.debug_inspect(docker_action.capabilities.host, content="false")
  @debug.debug_inspect(docker_action.capabilities.docker, content="true")
  @debug.debug_inspect(docker_action.capabilities.wasm, content="false")
  @debug.debug_inspect(
    docker_action.uses,
    content=(
      #|"docker://alpine:3.21"
    ),
  )
  @debug.debug_inspect(
    docker_action.image.unwrap_or(""),
    content=(
      #|"alpine:3.21"
    ),
  )
  @debug.debug_inspect(docker_action.args, content="[]")
}

///|
test "action ref: resolve wasm registry action" {
  let wasm_action = expect_resolved(
    @actrun.resolve_action_uses("wasm://std/echo@v1"),
  )

  @debug.debug_inspect(
    wasm_action.kind,
    content=(
      #|"wasm-module"
    ),
  )
  @debug.debug_inspect(
    wasm_action.backend,
    content=(
      #|"wasm"
    ),
  )
  @debug.debug_inspect(wasm_action.capabilities.host, content="false")
  @debug.debug_inspect(wasm_action.capabilities.docker, content="false")
  @debug.debug_inspect(wasm_action.capabilities.wasm, content="true")
  @debug.debug_inspect(
    wasm_action.entrypoint.unwrap_or(""),
    content=(
      #|"std/echo@v1"
    ),
  )
}

///|
test "action ref: backend capability presets include wasm" {
  let host = @actrun.backend_capabilities_for("node")
  let docker = @actrun.backend_capabilities_for("docker")
  let wasm = @actrun.backend_capabilities_for("wasm")

  @debug.debug_inspect(host.host, content="true")
  @debug.debug_inspect(host.docker, content="false")
  @debug.debug_inspect(docker.host, content="false")
  @debug.debug_inspect(docker.docker, content="true")
  @debug.debug_inspect(wasm.host, content="false")
  @debug.debug_inspect(wasm.wasm, content="true")
}

///|
test "action ref: unresolved custom registry action is rejected" {
  let result = @actrun.resolve_action_uses("bit://std/cache@v1")

  @debug.debug_inspect(
    result.errors,
    content="[\"action 'bit://std/cache@v1' is not supported in MVP\"]",
  )
}
