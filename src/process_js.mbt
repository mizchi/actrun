///|
#cfg(target="js")
extern "js" fn js_spawn_sync_ffi(
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
  #|     globalThis._proc_stdout = (result.stdout || Buffer.alloc(0)).toString('utf8');
  #|     globalThis._proc_stderr = (result.stderr || Buffer.alloc(0)).toString('utf8');
  #|     return result.status !== null ? result.status : (result.signal ? 128 : -1);
  #|   } catch(e) {
  #|     globalThis._proc_stdout = '';
  #|     globalThis._proc_stderr = e.message;
  #|     return -1;
  #|   }
  #| }

///|
#cfg(target="js")
extern "js" fn js_spawn_sync_stdin_ffi(
  cmd : String,
  args : Array[String],
  stdin_text : String,
  cwd : String,
) -> Int =
  #| function(cmd, args, stdin_text, cwd) {
  #|   var cp = require('child_process');
  #|   try {
  #|     var result = cp.spawnSync(cmd, args, {
  #|       input: stdin_text,
  #|       cwd: cwd,
  #|       encoding: 'buffer',
  #|       maxBuffer: 50 * 1024 * 1024,
  #|     });
  #|     globalThis._proc_stdout = (result.stdout || Buffer.alloc(0)).toString('utf8');
  #|     globalThis._proc_stderr = (result.stderr || Buffer.alloc(0)).toString('utf8');
  #|     return result.status !== null ? result.status : -1;
  #|   } catch(e) {
  #|     globalThis._proc_stdout = '';
  #|     globalThis._proc_stderr = e.message;
  #|     return -1;
  #|   }
  #| }

///|
#cfg(target="js")
extern "js" fn js_get_proc_stdout() -> String =
  #| function() { return globalThis._proc_stdout || ''; }

///|
#cfg(target="js")
extern "js" fn js_get_proc_stderr() -> String =
  #| function() { return globalThis._proc_stderr || ''; }

///|
#cfg(target="js")
async fn run_command(
  cmd : String,
  args : Array[String],
  cwd~ : String = ".",
) -> (Int, String, String) {
  let code = js_spawn_sync_ffi(cmd, args, cwd)
  let stdout = js_get_proc_stdout()
  let stderr = js_get_proc_stderr()
  (code, stdout, stderr)
}

///|
#cfg(target="js")
async fn run_command_with_stdin(
  cmd : String,
  args : Array[String],
  stdin_text : String,
  cwd~ : String = ".",
) -> (Int, String, String) {
  let code = js_spawn_sync_stdin_ffi(cmd, args, stdin_text, cwd)
  let stdout = js_get_proc_stdout()
  let stderr = js_get_proc_stderr()
  (code, stdout, stderr)
}
