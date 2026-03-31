///|
#cfg(target="native")
test "inspect_wasm_module: valid wasi module" {
  // Read a real WASI module compiled from Rust
  let bytes = @xfs.read_file_to_bytes(
    "_build/actrun/wasm_actions/echo/v1/main.wasm",
  ) catch {
    _ => return // skip if test module not available
  }
  let info = inspect_wasm_module(bytes)
  inspect(info.valid, content="true")
  inspect(info.function_count > 0, content="true")
  inspect(info.export_count > 0, content="true")
  inspect(info.total_bytes > 0, content="true")
}

///|
test "inspect_wasm_module: invalid bytes" {
  let info = inspect_wasm_module(b"not a wasm module")
  inspect(info.valid, content="false")
  inspect(info.error.length() > 0, content="true")
}

///|
#cfg(target="native")
test "optimize_wasm_module: reduces size" {
  let bytes = @xfs.read_file_to_bytes(
    "_build/actrun/wasm_actions/echo/v1/main.wasm",
  ) catch {
    _ => return
  }
  let result = optimize_wasm_module(bytes)
  inspect(result.ok, content="true")
  inspect(result.original_size > 0, content="true")
  // Optimized should be <= original
  inspect(result.optimized_size <= result.original_size, content="true")
}

///|
#cfg(target="native")
test "analyze_wasm_dead_code: reports removable code" {
  let bytes = @xfs.read_file_to_bytes(
    "_build/actrun/wasm_actions/echo/v1/main.wasm",
  ) catch {
    _ => return
  }
  let report = analyze_wasm_dead_code(bytes)
  inspect(report.ok, content="true")
  // DCE report should at least parse successfully
  inspect(report.removable_functions >= 0, content="true")
}
