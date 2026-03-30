///|
#cfg(target="native")
fn run_module(_module_path : String, _env : Map[String, String]) -> Unit {
  println("Error: wasi-runner JS mode is not available on native target.")
  println("Use ACTRUN_WASM_BIN=wasmtime instead.")
}
