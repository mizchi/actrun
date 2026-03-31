///|
/// Deno Deploy HTTP server with WASI execution.
/// All WASI logic is in the wasi_runner package;
/// this file is just the HTTP glue.

///|
#cfg(target="js")
extern "js" fn js_start_server(handler_fn_name : String) -> Unit =
  #| function(_handlerFnName) {
  #|   if (typeof Deno === 'undefined' || !Deno.serve) {
  #|     console.error('Deno.serve not available. Run with: deno run --allow-all');
  #|     return;
  #|   }
  #|   Deno.serve(async (req) => {
  #|     const url = new URL(req.url);
  #|     if (url.pathname === '/health') {
  #|       return Response.json({ status: 'ok', runtime: 'deno', wasi: true, backend: 'moonbit' });
  #|     }
  #|     if (url.pathname === '/run' && req.method === 'POST') {
  #|       try {
  #|         const body = await req.json();
  #|         var moduleUrl = body.module_url || '';
  #|         if (!moduleUrl) return Response.json({ error: 'module_url required' }, { status: 400 });
  #|         var resp = await fetch(moduleUrl);
  #|         if (!resp.ok) return Response.json({ error: 'fetch ' + moduleUrl + ': ' + resp.status }, { status: 400 });
  #|         var bytes = new Uint8Array(await resp.arrayBuffer());
  #|         body._module_bytes_json = JSON.stringify(Array.from(bytes));
  #|         var result = globalThis._actrun_handle_run(JSON.stringify(body));
  #|         return new Response(result, { headers: { 'content-type': 'application/json' } });
  #|       } catch(e) {
  #|         return Response.json({ error: String(e) }, { status: 500 });
  #|       }
  #|     }
  #|     return new Response('actrun wasi-worker (moonbit)\n\nPOST /run\nGET /health\n');
  #|   });
  #| }

///|
#cfg(target="js")
extern "js" fn js_register_handler(handler : (String) -> String) -> Unit =
  #| function(handler) {
  #|   globalThis._actrun_handle_run = handler;
  #| }

///|
#cfg(target="js")
fn handle_run_request(body_json : String) -> String {
  let body : Json = @json.parse(body_json) catch {
    _ => return "{\"error\":\"invalid json\"}"
  }
  let env : Map[String, String] = {}
  let inputs : Map[String, String] = {}
  match body {
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
              String(s) => inputs[k] = s
              _ => ()
            }
          }
        _ => ()
      }
    }
    _ => ()
  }
  // Module bytes are pre-fetched by the JS HTTP handler (async fetch)
  // and passed as _module_bytes_json in the body
  let bytes_json = match body {
    Object(m) =>
      match m.get("_module_bytes_json") {
        Some(String(s)) => s
        _ => "[]"
      }
    _ => "[]"
  }
  if bytes_json == "[]" {
    return "{\"error\":\"module_url required or fetch failed\"}"
  }
  // Build env with inputs
  let merged_env : Map[String, String] = {}
  for k, v in env {
    merged_env[k] = v
  }
  for k, v in inputs {
    merged_env["INPUT_" + to_upper(k)] = v
  }
  let workdir = "/workspace"
  merged_env["GITHUB_OUTPUT"] = workdir + "/github_output"
  merged_env["GITHUB_ENV"] = workdir + "/github_env"
  merged_env["GITHUB_WORKSPACE"] = workdir
  let env_json = merged_env.to_json().stringify()
  @wr.run_wasi_module_js_raw(bytes_json, env_json, workdir)
}

///|
#cfg(target="js")
fn start_server() -> Unit {
  js_register_handler(handle_run_request)
  js_start_server("_actrun_handle_run")
}

///|
fn to_upper(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    if ch >= 'a' && ch <= 'z' {
      buf.write_char(Char::from_int(ch.to_int() - 32))
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}
