///|
/// WASI Worker entry point for Deno Deploy.
/// Compiled to JS via `moon build src/cmd/wasi_worker --target js`.
///
/// Usage:
///   deno run --allow-all wasi_worker.js

///|
fn main {
  start_server()
}
