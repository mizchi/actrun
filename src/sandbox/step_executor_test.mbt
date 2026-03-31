///|
test "execute_shell_step: basic echo" {
  let fs = MemFs::new()
  let result = execute_shell_step("echo hello", fs)
  inspect(result.status, content="success")
  inspect(result.exit_code, content="0")
  inspect(result.stdout, content="hello\n")
  inspect(result.stderr, content="")
}

///|
test "execute_shell_step: failed step" {
  let fs = MemFs::new()
  let result = execute_shell_step("exit 1", fs)
  inspect(result.status, content="failed")
  inspect(result.exit_code, content="1")
}

///|
test "execute_shell_step: GITHUB_OUTPUT parsing" {
  let fs = MemFs::new()
  let result = execute_shell_step(
    "echo \"result=42\" >> $GITHUB_OUTPUT && echo \"name=test\" >> $GITHUB_OUTPUT",
    fs,
  )
  inspect(result.status, content="success")
  inspect(result.outputs.get("result"), content="Some(\"42\")")
  inspect(result.outputs.get("name"), content="Some(\"test\")")
}

///|
test "execute_shell_step: GITHUB_ENV parsing" {
  let fs = MemFs::new()
  let script =
    #|echo "MY_VAR=hello" >> $GITHUB_ENV
  let result = execute_shell_step(script, fs)
  inspect(result.status, content="success")
  inspect(result.env_updates.get("MY_VAR"), content="Some(\"hello\")")
}

///|
test "execute_shell_step: custom env" {
  let fs = MemFs::new()
  let result = execute_shell_step(
    "echo \"hello $NAME\"",
    fs,
    env={ "NAME": "world" },
  )
  inspect(result.stdout, content="hello world\n")
}

///|
test "execute_shell_step: pre-populated fs" {
  let fs = MemFs::new()
  fs.write("/workspace/input.txt", "data from outside", false)
  let result = execute_shell_step("cat /workspace/input.txt", fs)
  inspect(result.stdout, content="data from outside")
}

///|
test "execute_shell_step: to_json roundtrip" {
  let fs = MemFs::new()
  let result = execute_shell_step("echo ok", fs)
  let json_str = step_result_to_json(result)
  inspect(json_str.contains("\"status\":\"success\""), content="true")
  inspect(json_str.contains("\"exit_code\":0"), content="true")
}

///|
test "execute_shell_step: stderr capture" {
  let fs = MemFs::new()
  let result = execute_shell_step("unknown_cmd", fs)
  inspect(result.status, content="failed")
  inspect(result.exit_code, content="127")
  inspect(result.stderr.contains("command not found"), content="true")
}
