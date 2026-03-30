///|
fn wasm_sandbox_has_string(values : Array[String], expected : String) -> Bool {
  let mut found = false
  for value in values {
    if value == expected {
      found = true
    }
  }
  found
}

///|
test "resolve_wasm_runner_command: nodejs uses wasi shim" {
  let (cmd, args) = resolve_wasm_runner_command(
    "nodejs",
    ["run", "module.wasm"],
    "",
  )
  inspect(cmd, content="nodejs")
  assert_eq(args[0].contains("wasi-runner.mjs"), true)
  inspect(args[1], content="run")
  inspect(args[2], content="module.wasm")
}

///|
test "resolve_wasm_runner_command: node.exe uses wasi shim" {
  let (cmd, args) = resolve_wasm_runner_command(
    "/tmp/tools/node.exe",
    ["run", "module.wasm"],
    "",
  )
  inspect(cmd, content="/tmp/tools/node.exe")
  assert_eq(args[0].contains("wasi-runner.mjs"), true)
  inspect(args[1], content="run")
  inspect(args[2], content="module.wasm")
}

///|
test "wasi_runner_shim_candidates: includes install path patterns" {
  let candidates = wasi_runner_shim_candidates("/tmp/actrun-workspace")
  assert_eq(
    wasm_sandbox_has_string(candidates, "/usr/local/lib/actrun/wasi-runner.mjs"),
    true,
  )
  assert_eq(
    wasm_sandbox_has_string(
      candidates, "/tmp/actrun-workspace/node_modules/@mizchi/actrun/scripts/wasi-runner.mjs",
    ),
    true,
  )
}
