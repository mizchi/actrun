///|
#cfg(target="js")
extern "js" fn js_read_file_bytes_json(path : String) -> String =
  #| function(path) {
  #|   try {
  #|     var bytes;
  #|     if (typeof Deno !== 'undefined') {
  #|       bytes = Deno.readFileSync(path);
  #|     } else {
  #|       var fs = require('node:fs');
  #|       bytes = fs.readFileSync(path);
  #|     }
  #|     return JSON.stringify(Array.from(bytes));
  #|   } catch(e) {
  #|     return '[]';
  #|   }
  #| }

///|
#cfg(target="js")
extern "js" fn js_print_and_exit(result_json : String) -> Unit =
  #| function(json) {
  #|   try {
  #|     var r = JSON.parse(json);
  #|     if (r.stdout) {
  #|       if (typeof Deno !== 'undefined') Deno.stdout.writeSync(new TextEncoder().encode(r.stdout));
  #|       else process.stdout.write(r.stdout);
  #|     }
  #|     if (r.stderr) {
  #|       if (typeof Deno !== 'undefined') Deno.stderr.writeSync(new TextEncoder().encode(r.stderr));
  #|       else process.stderr.write(r.stderr);
  #|     }
  #|     if (r.exit_code !== 0) {
  #|       if (typeof Deno !== 'undefined') Deno.exit(r.exit_code);
  #|       else process.exit(r.exit_code);
  #|     }
  #|   } catch(e) { console.error('error:', e); }
  #| }

///|
#cfg(target="js")
fn run_module(module_path : String, env : Map[String, String]) -> Unit {
  let bytes_json = js_read_file_bytes_json(module_path)
  if bytes_json == "[]" {
    println("Error: could not read " + module_path)
    return
  }
  let env_json = env.to_json().stringify()
  let result = @wr.run_wasi_module_js_raw(bytes_json, env_json, "/workspace")
  js_print_and_exit(result)
}
