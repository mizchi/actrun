///|
#cfg(target="js")
extern "js" fn js_cmd_spawn_sync_ffi(
  cmd : String,
  args : Array[String],
  cwd : String,
) -> Int =
  #| function(cmd, args, cwd) {
  #|   var cp = require('child_process');
  #|   try {
  #|     var result = cp.spawnSync(cmd, args, {
  #|       cwd: cwd,
  #|       encoding: 'buffer',
  #|       maxBuffer: 50 * 1024 * 1024,
  #|     });
  #|     globalThis._cmd_stdout = (result.stdout || Buffer.alloc(0)).toString('utf8');
  #|     globalThis._cmd_stderr = (result.stderr || Buffer.alloc(0)).toString('utf8');
  #|     return result.status !== null ? result.status : (result.signal ? 128 : -1);
  #|   } catch(e) {
  #|     globalThis._cmd_stdout = '';
  #|     globalThis._cmd_stderr = e.message;
  #|     return -1;
  #|   }
  #| }

///|
#cfg(target="js")
extern "js" fn js_cmd_get_stdout() -> String =
  #| function() { return globalThis._cmd_stdout || ''; }

///|
#cfg(target="js")
extern "js" fn js_cmd_get_stderr() -> String =
  #| function() { return globalThis._cmd_stderr || ''; }

///|
#cfg(target="js")
async fn run_command(
  cmd : String,
  args : Array[String],
  cwd~ : String = ".",
) -> (Int, String, String) {
  let code = js_cmd_spawn_sync_ffi(cmd, args, cwd)
  let stdout = js_cmd_get_stdout()
  let stderr = js_cmd_get_stderr()
  (code, stdout, stderr)
}
