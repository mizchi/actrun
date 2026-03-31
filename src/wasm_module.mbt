///|
/// WASM module validation and optimization using wite.
///
/// wite provides:
/// - Module profiling (section sizes, function counts)
/// - Dead code elimination
/// - Size optimization (-O0 to -Oz)
/// - Call graph analysis

///|
pub struct WasmModuleInfo {
  total_bytes : Int
  function_count : Int
  import_count : Int
  export_count : Int
  valid : Bool
  error : String
}

///|
pub fn inspect_wasm_module(bytes : Bytes) -> WasmModuleInfo {
  match @wite.profile_module(bytes) {
    Ok(profile) =>
      {
        total_bytes: profile.total_bytes.reinterpret_as_int(),
        function_count: profile.function_count.reinterpret_as_int(),
        import_count: profile.import_count.reinterpret_as_int(),
        export_count: profile.export_count.reinterpret_as_int(),
        valid: true,
        error: "",
      }
    Err(err) =>
      {
        total_bytes: 0,
        function_count: 0,
        import_count: 0,
        export_count: 0,
        valid: false,
        error: @wite.error_to_string(err),
      }
  }
}

///|
pub struct WasmOptimizeResult {
  original_size : Int
  optimized_size : Int
  optimized_bytes : Bytes
  ok : Bool
  error : String
}

///|
pub fn optimize_wasm_module(
  bytes : Bytes,
  level? : String = "-Os",
) -> WasmOptimizeResult {
  let config = match @wite.optimize_config_from_opt_level(level) {
    Some(c) => c
    None => @wite.OptimizeConfig::os()
  }
  match @wite.optimize_for_size(bytes, config~) {
    Ok(result) =>
      {
        original_size: result.before_size.reinterpret_as_int(),
        optimized_size: result.after_size.reinterpret_as_int(),
        optimized_bytes: result.bytes,
        ok: true,
        error: "",
      }
    Err(err) =>
      {
        original_size: bytes.length(),
        optimized_size: bytes.length(),
        optimized_bytes: bytes,
        ok: false,
        error: @wite.error_to_string(err),
      }
  }
}

///|
pub struct WasmDceReport {
  removable_functions : Int
  removable_bytes : Int
  ok : Bool
  error : String
}

///|
pub fn analyze_wasm_dead_code(bytes : Bytes) -> WasmDceReport {
  match @wite.analyze_dce_report(bytes) {
    Ok(report) =>
      {
        removable_functions: report.removable_function_count.reinterpret_as_int(),
        removable_bytes: report.removable_body_bytes.reinterpret_as_int(),
        ok: true,
        error: "",
      }
    Err(err) =>
      {
        removable_functions: 0,
        removable_bytes: 0,
        ok: false,
        error: @wite.error_to_string(err),
      }
  }
}
