///|
/// WASI Runner CLI entry point.
/// Compiled to JS via `moon build src/cmd/wasi_runner --target js`.
///
/// Usage (same interface as wasmtime):
///   node wasi-runner.js run --env K=V --dir /path module.wasm
///   deno run --allow-all wasi-runner.js run --env K=V --dir /path module.wasm

///|
fn main {
  let args = @env.args()
  let env : Map[String, String] = {}
  let mut module_path = ""
  let mut i = 0
  // Skip program name if present
  while i < args.length() {
    let arg = args[i]
    if arg == "run" {
      i += 1
      continue
    }
    if arg == "--env" && i + 1 < args.length() {
      let kv = args[i + 1]
      let eq = find_eq(kv)
      if eq > 0 {
        env[String::unsafe_substring(kv, start=0, end=eq)] = String::unsafe_substring(
          kv,
          start=eq + 1,
          end=kv.length(),
        )
      }
      i += 2
      continue
    }
    if arg == "--dir" && i + 1 < args.length() {
      // dirs are handled by the JS WASI host, no MoonBit processing needed
      i += 2
      continue
    }
    module_path = arg
    i += 1
  }
  if module_path.length() == 0 {
    println("Usage: wasi-runner run [--env K=V]... [--dir D]... <module.wasm>")
    return
  }
  run_module(module_path, env)
}

///|
fn find_eq(s : String) -> Int {
  let eq = '='.to_int().to_uint16()
  let mut idx = 0
  while idx < s.length() {
    if s.unsafe_get(idx) == eq {
      return idx
    }
    idx += 1
  }
  -1
}
