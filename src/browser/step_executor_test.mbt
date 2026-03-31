///|
test "execute_shell_step: basic echo" {
  let result = execute_shell_step("echo hello")
  inspect(result.status, content="success")
  inspect(result.exit_code, content="0")
  inspect(result.stdout, content="hello\n")
  inspect(result.stderr, content="")
}

///|
test "execute_shell_step: failed step" {
  let result = execute_shell_step("exit 1")
  inspect(result.status, content="failed")
  inspect(result.exit_code, content="1")
}

///|
test "execute_shell_step: GITHUB_OUTPUT parsing" {
  let result = execute_shell_step(
    "echo \"result=42\" >> $GITHUB_OUTPUT && echo \"name=test\" >> $GITHUB_OUTPUT",
  )
  inspect(result.status, content="success")
  inspect(result.outputs.get("result"), content="Some(\"42\")")
  inspect(result.outputs.get("name"), content="Some(\"test\")")
}

///|
test "execute_shell_step: GITHUB_ENV parsing" {
  let script =
    #|echo "MY_VAR=hello" >> $GITHUB_ENV
  let result = execute_shell_step(script)
  inspect(result.status, content="success")
  inspect(result.env_updates.get("MY_VAR"), content="Some(\"hello\")")
}

///|
test "execute_shell_step: custom env" {
  let result = execute_shell_step(
    "echo \"hello $NAME\"",
    env={ "NAME": "world" },
  )
  inspect(result.stdout, content="hello world\n")
}

///|
test "execute_shell_step: pre-populated VFS" {
  let vfs = @wr.VirtualFs::new()
  vfs.write("/workspace/input.txt", "data from outside")
  let result = execute_shell_step("cat /workspace/input.txt", vfs=vfs)
  inspect(result.stdout, content="data from outside")
}

///|
test "execute_shell_step: to_json roundtrip" {
  let result = execute_shell_step("echo ok")
  let json_str = step_result_to_json(result)
  inspect(json_str.contains("\"status\":\"success\""), content="true")
  inspect(json_str.contains("\"exit_code\":0"), content="true")
}

///|
test "execute_shell_step: stderr capture" {
  // Unknown command goes to stderr
  let result = execute_shell_step("unknown_cmd")
  inspect(result.status, content="failed")
  inspect(result.exit_code, content="127")
  inspect(result.stderr.contains("command not found"), content="true")
}
