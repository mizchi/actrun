///|
#cfg(target="native")
fn start_server() -> Unit {
  println("Error: wasi-worker requires JS target (Deno Deploy).")
  println("Build with: moon build src/cmd/wasi_worker --target js")
}
