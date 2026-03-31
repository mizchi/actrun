///|
#cfg(target="native")
fn run_module(_module_path : String, _env : Map[String, String]) -> Unit {
  println("Error: wasi-runner JS mode is not available on native target.")
  println("Use --wasm-runner wasmtime or ACTRUN_WASM_RUNNER=wasmtime instead.")
}
