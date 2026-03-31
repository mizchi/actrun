///|
/// JS binding for the sandbox executor.
/// Registers plan / executeShellStep / executeWasmStep on globalThis._actrun_sandbox.
/// This is an example of how to expose the target-agnostic sandbox layer to JS.

///|
#cfg(target="js")
extern "js" fn js_register_api(
  plan_fn : (String) -> String,
  exec_shell_fn : (String) -> String,
  exec_wasm_fn : (String) -> String,
) -> Unit =
  #| function(planFn, execShellFn, execWasmFn) {
  #|   globalThis._actrun_sandbox = {
  #|     plan: planFn,
  #|     executeShellStep: execShellFn,
  #|     executeWasmStep: execWasmFn,
  #|   };
  #| }

///|
#cfg(target="js")
fn plan_handler(yaml_text : String) -> String {
  let result = @actrun.plan_workflow(yaml_text)
  @actrun.plan_result_to_json(result)
}

///|
#cfg(target="js")
fn exec_shell_handler(config_json : String) -> String {
  let config : Json = @json.parse(config_json) catch {
    _ => return "{\"error\":\"invalid json\"}"
  }
  let script = match config {
    Object(m) =>
      match m.get("script") {
        Some(String(s)) => s
        _ => return "{\"error\":\"script required\"}"
      }
    _ => return "{\"error\":\"invalid config\"}"
  }
  let env : Map[String, String] = {}
  let fs = MemFs::new()
  let mut workdir = "/workspace"
  match config {
    Object(m) => {
      match m.get("env") {
        Some(Object(e)) =>
          for k, v in e {
            match v {
              String(s) => env[k] = s
              _ => ()
            }
          }
        _ => ()
      }
      match m.get("vfs") {
        Some(Object(files)) =>
          for path, content in files {
            match content {
              String(s) => fs.fs_write(path, s, false)
              _ => ()
            }
          }
        _ => ()
      }
      match m.get("workdir") {
        Some(String(s)) => workdir = s
        _ => ()
      }
    }
    _ => ()
  }
  let result = execute_shell_step(script, fs, env~, workdir~)
  step_result_to_json(result)
}

///|
/// Run a WASM module with WASI P1 using a pre-compiled WebAssembly.Module.
/// The module is stored in globalThis._actrun_wasm_modules by the JS caller.
#cfg(target="js")
extern "js" fn js_run_wasi_from_module(
  module_id : String,
  env_json : String,
  workdir : String,
) -> String =
  #| function(moduleId, envJson, workdir) {
  #|   const modules = globalThis._actrun_wasm_modules;
  #|   if (!modules || !modules.has(moduleId)) {
  #|     return JSON.stringify({ error: 'module not found: ' + moduleId, status: 'failed', exit_code: 1, stdout: '', stderr: 'module not found: ' + moduleId, outputs: {}, env_updates: {} });
  #|   }
  #|   const mod = modules.get(moduleId);
  #|   const env = JSON.parse(envJson);
  #|   const normalizePath = (path) => {
  #|     const raw = String(path || '').replaceAll('\\\\', '/');
  #|     const driveMatch = raw.match(/^[A-Za-z]:/);
  #|     const drive = driveMatch ? driveMatch[0] : '';
  #|     const rest = drive ? raw.slice(drive.length) : raw;
  #|     const isAbs = rest.startsWith('/');
  #|     const parts = [];
  #|     for (const part of rest.split('/')) {
  #|       if (!part || part === '.') continue;
  #|       if (part === '..') {
  #|         if (parts.length > 0 && parts[parts.length - 1] !== '..') parts.pop();
  #|         else if (!isAbs) parts.push('..');
  #|         continue;
  #|       }
  #|       parts.push(part);
  #|     }
  #|     const prefix = drive ? `${drive}${isAbs ? '/' : ''}` : (isAbs ? '/' : '');
  #|     if (prefix.length > 0 || parts.length > 0) return prefix + parts.join('/');
  #|     return '.';
  #|   };
  #|   const pathWithinPreopen = (basePath, candidatePath) => {
  #|     const base = normalizePath(basePath);
  #|     const candidate = normalizePath(candidatePath);
  #|     return candidate === base || candidate.startsWith(base + '/');
  #|   };
  #|   const resolvePreopenPath = (basePath, relativePath) => {
  #|     const base = normalizePath(basePath);
  #|     const candidate = /^[A-Za-z]:[\\\\/]/.test(relativePath) || relativePath.startsWith('/')
  #|       ? normalizePath(relativePath)
  #|       : normalizePath(base + '/' + relativePath);
  #|     if (!pathWithinPreopen(base, candidate)) return null;
  #|     return candidate;
  #|   };
  #|
  #|   const vfs = new Map();
  #|   vfs.set(workdir + '/github_output', '');
  #|   vfs.set(workdir + '/github_env', '');
  #|
  #|   const fds = new Map();
  #|   let nextFd = 3;
  #|   fds.set(0, { isDir: false });
  #|   fds.set(1, { isDir: false });
  #|   fds.set(2, { isDir: false });
  #|   fds.set(nextFd++, { path: workdir, isDir: true });
  #|
  #|   const stdoutBuf = [];
  #|   const stderrBuf = [];
  #|   const dec = new TextDecoder();
  #|   const enc = new TextEncoder();
  #|   let memory;
  #|   let exitCode = 0;
  #|
  #|   class WasiExit extends Error { constructor(c) { super('exit'); this.code = c; } }
  #|
  #|   const v = () => new DataView(memory.buffer);
  #|   const u8 = () => new Uint8Array(memory.buffer);
  #|
  #|   const imports = { wasi_snapshot_preview1: {
  #|     args_get: () => 0,
  #|     args_sizes_get: (c, s) => { v().setUint32(c, 0, true); v().setUint32(s, 0, true); return 0; },
  #|     environ_get: (ep, bp) => {
  #|       const entries = Object.entries(env);
  #|       let off = bp;
  #|       for (let i = 0; i < entries.length; i++) {
  #|         v().setUint32(ep + i * 4, off, true);
  #|         const s = enc.encode(entries[i][0] + '=' + entries[i][1] + '\0');
  #|         u8().set(s, off); off += s.length;
  #|       }
  #|       return 0;
  #|     },
  #|     environ_sizes_get: (cp, sp) => {
  #|       const entries = Object.entries(env);
  #|       let sz = 0;
  #|       for (const [k, val] of entries) sz += k.length + 1 + val.length + 1;
  #|       v().setUint32(cp, entries.length, true);
  #|       v().setUint32(sp, sz, true);
  #|       return 0;
  #|     },
  #|     fd_write: (fd, iovs, iovsLen, nw) => {
  #|       let written = 0;
  #|       for (let i = 0; i < iovsLen; i++) {
  #|         const ptr = v().getUint32(iovs + i * 8, true);
  #|         const len = v().getUint32(iovs + i * 8 + 4, true);
  #|         const data = u8().subarray(ptr, ptr + len);
  #|         if (fd === 1) stdoutBuf.push(dec.decode(data));
  #|         else if (fd === 2) stderrBuf.push(dec.decode(data));
  #|         else {
  #|           const e = fds.get(fd);
  #|           if (e && e.path) vfs.set(e.path, (vfs.get(e.path) || '') + dec.decode(data));
  #|         }
  #|         written += len;
  #|       }
  #|       v().setUint32(nw, written, true);
  #|       return 0;
  #|     },
  #|     fd_read: () => 0,
  #|     fd_close: () => 0,
  #|     fd_seek: () => 0,
  #|     fd_fdstat_get: (fd, buf) => {
  #|       const e = fds.get(fd);
  #|       v().setUint8(buf, fd <= 2 ? 2 : e && e.isDir ? 3 : 4);
  #|       v().setUint16(buf + 2, 0, true);
  #|       v().setBigUint64(buf + 8, 0n, true);
  #|       v().setBigUint64(buf + 16, 0n, true);
  #|       return 0;
  #|     },
  #|     fd_prestat_get: (fd, buf) => {
  #|       const e = fds.get(fd);
  #|       if (!e || !e.isDir || !e.path) return 8;
  #|       v().setUint8(buf, 0);
  #|       v().setUint32(buf + 4, enc.encode(e.path).length, true);
  #|       return 0;
  #|     },
  #|     fd_prestat_dir_name: (fd, p, l) => {
  #|       const e = fds.get(fd);
  #|       if (!e || !e.path) return 8;
  #|       u8().set(enc.encode(e.path).slice(0, l), p);
  #|       return 0;
  #|     },
  #|     path_open: (dirfd, _, pp, pl, __, ___, ____, _____, fdp) => {
  #|       const dir = fds.get(dirfd);
  #|       if (!dir || !dir.path) return 8;
  #|       const rel = dec.decode(u8().subarray(pp, pp + pl));
  #|       const full = resolvePreopenPath(dir.path, rel);
  #|       if (full === null) return 76;
  #|       const nfd = nextFd++;
  #|       fds.set(nfd, { path: full, isDir: false });
  #|       if (!vfs.has(full)) vfs.set(full, '');
  #|       v().setUint32(fdp, nfd, true);
  #|       return 0;
  #|     },
  #|     clock_time_get: (_, __, p) => {
  #|       v().setBigUint64(p, BigInt(Date.now()) * 1000000n, true);
  #|       return 0;
  #|     },
  #|     proc_exit: (code) => { exitCode = code; throw new WasiExit(code); },
  #|     sched_yield: () => 0,
  #|     random_get: (buf, len) => {
  #|       crypto.getRandomValues(u8().subarray(buf, buf + len));
  #|       return 0;
  #|     },
  #|     poll_oneoff: () => 0,
  #|     path_filestat_get: () => 8,
  #|     path_create_directory: () => 0,
  #|     path_remove_directory: () => 0,
  #|     path_unlink_file: () => 0,
  #|     path_rename: () => 0,
  #|     fd_readdir: () => 0,
  #|     fd_filestat_get: () => 0,
  #|   }};
  #|
  #|   const inst = new WebAssembly.Instance(mod, imports);
  #|   memory = inst.exports.memory;
  #|   try { inst.exports._start(); } catch(e) {
  #|     if (!(e instanceof WasiExit)) throw e;
  #|   }
  #|
  #|   function parseKV(path) {
  #|     const r = {};
  #|     for (const line of (vfs.get(path) || '').split('\n')) {
  #|       if (!line) continue;
  #|       const eq = line.indexOf('=');
  #|       if (eq > 0) r[line.substring(0, eq)] = line.substring(eq + 1);
  #|     }
  #|     return r;
  #|   }
  #|
  #|   return JSON.stringify({
  #|     status: exitCode === 0 ? 'success' : 'failed',
  #|     exit_code: exitCode,
  #|     stdout: stdoutBuf.join(''),
  #|     stderr: stderrBuf.join(''),
  #|     outputs: parseKV(workdir + '/github_output'),
  #|     env_updates: parseKV(workdir + '/github_env'),
  #|   });
  #| }

///|
#cfg(target="js")
fn exec_wasm_handler(config_json : String) -> String {
  let config : Json = @json.parse(config_json) catch {
    _ => return "{\"error\":\"invalid json\"}"
  }
  let module_id = match config {
    Object(m) =>
      match m.get("module_id") {
        Some(String(s)) => s
        _ => return "{\"error\":\"module_id required\"}"
      }
    _ => return "{\"error\":\"invalid config\"}"
  }
  let env : Map[String, String] = {}
  let mut workdir = "/workspace"
  match config {
    Object(m) => {
      match m.get("env") {
        Some(Object(e)) =>
          for k, v in e {
            match v {
              String(s) => env[k] = s
              _ => ()
            }
          }
        _ => ()
      }
      match m.get("inputs") {
        Some(Object(e)) =>
          for k, v in e {
            match v {
              String(s) => env["INPUT_" + to_upper(k)] = s
              _ => ()
            }
          }
        _ => ()
      }
      match m.get("workdir") {
        Some(String(s)) => workdir = s
        _ => ()
      }
    }
    _ => ()
  }
  env["GITHUB_OUTPUT"] = workdir + "/github_output"
  env["GITHUB_ENV"] = workdir + "/github_env"
  env["GITHUB_WORKSPACE"] = workdir
  let env_json = env.to_json().stringify()
  js_run_wasi_from_module(module_id, env_json, workdir)
}

///|
#cfg(target="js")
pub fn register_api() -> Unit {
  js_register_api(plan_handler, exec_shell_handler, exec_wasm_handler)
}

///|
fn to_upper(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    if ch >= 'a' && ch <= 'z' {
      buf.write_char(Int::unsafe_to_char(ch.to_int() - 32))
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}
