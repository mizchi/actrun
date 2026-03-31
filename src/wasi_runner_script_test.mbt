///|
fn wasi_runner_test_repo_root() -> String {
  @xsys.get_env_var("PWD").unwrap_or(".")
}

///|
fn wasi_runner_test_script_url() -> String {
  "file://" + wasi_runner_test_repo_root() + "/scripts/wasi-runner.mjs"
}

///|
async fn wasi_runner_test_run_node(code : String) -> (Int, String, String) {
  let (status, stdout, stderr) = @process.collect_output(
    "node",
    ["--input-type=module", "-e", code],
    cwd=wasi_runner_test_repo_root(),
  )
  (status, stdout.text(), stderr.text())
}

///|
async test "wasi_runner script: rejects traversal outside preopen" {
  let script_url = wasi_runner_test_script_url()
  let code = "import { resolvePreopenPath } from '" +
    script_url +
    "';\n" +
    "console.log(resolvePreopenPath('/tmp/actrun-wasm-step', '../escape.txt') ?? 'null');\n"
  let (status, stdout, stderr) = wasi_runner_test_run_node(code)
  inspect(status, content="0")
  inspect(stderr, content="")
  inspect(stdout, content="null\n")
}

///|
async test "wasi_runner script: keeps writes inside preopen" {
  let script_url = wasi_runner_test_script_url()
  let code = "import { resolvePreopenPath } from '" +
    script_url +
    "';\n" +
    "console.log(resolvePreopenPath('/tmp/actrun-wasm-step', 'nested/out.txt') ?? 'null');\n"
  let (status, stdout, stderr) = wasi_runner_test_run_node(code)
  inspect(status, content="0")
  inspect(stderr, content="")
  inspect(stdout, content="/tmp/actrun-wasm-step/nested/out.txt\n")
}

///|
async test "wasi_runner script: node fs helpers work in esm" {
  let script_url = wasi_runner_test_script_url()
  let tmp_path = "/tmp/actrun-wasi-runner-script-test.txt"
  let code = "import fs from 'node:fs';\n" +
    "import { writeFileAppend, writeFileCreate } from '" +
    script_url +
    "';\n" +
    "fs.rmSync('" +
    tmp_path +
    "', { force: true });\n" +
    "writeFileCreate('" +
    tmp_path +
    "');\n" +
    "writeFileAppend('" +
    tmp_path +
    "', new Uint8Array([65, 66]));\n" +
    "console.log(fs.readFileSync('" +
    tmp_path +
    "', 'utf8'));\n" +
    "fs.rmSync('" +
    tmp_path +
    "', { force: true });\n"
  let (status, stdout, stderr) = wasi_runner_test_run_node(code)
  inspect(status, content="0")
  inspect(stderr, content="")
  inspect(stdout, content="AB\n")
}
