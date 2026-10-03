///|
test "execute_shell_step: basic echo" {
  let fs = @sandbox.MemFs::new()
  let result = @sandbox.execute_shell_step("echo hello", fs)
  @debug.debug_inspect(
    result.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(result.exit_code, content="0")
  @debug.debug_inspect(
    result.stdout,
    content=(
      #|"hello\n"
    ),
  )
  @debug.debug_inspect(
    result.stderr,
    content=(
      #|""
    ),
  )
}

///|
test "execute_shell_step: failed step" {
  let fs = @sandbox.MemFs::new()
  let result = @sandbox.execute_shell_step("exit 1", fs)
  @debug.debug_inspect(
    result.status,
    content=(
      #|"failed"
    ),
  )
  @debug.debug_inspect(result.exit_code, content="1")
}

///|
test "execute_shell_step: GITHUB_OUTPUT parsing" {
  let fs = @sandbox.MemFs::new()
  let result = @sandbox.execute_shell_step(
    "echo \"result=42\" >> $GITHUB_OUTPUT && echo \"name=test\" >> $GITHUB_OUTPUT",
    fs,
  )
  @debug.debug_inspect(
    result.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(result.outputs.get("result"), content="Some(\"42\")")
  @debug.debug_inspect(result.outputs.get("name"), content="Some(\"test\")")
}

///|
test "execute_shell_step: GITHUB_ENV parsing" {
  let fs = @sandbox.MemFs::new()
  let script =
    #|echo "MY_VAR=hello" >> $GITHUB_ENV
  let result = @sandbox.execute_shell_step(script, fs)
  @debug.debug_inspect(
    result.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(
    result.env_updates.get("MY_VAR"),
    content="Some(\"hello\")",
  )
}

///|
test "execute_shell_step: custom env" {
  let fs = @sandbox.MemFs::new()
  let result = @sandbox.execute_shell_step("echo \"hello $NAME\"", fs, env={
    "NAME": "world",
  })
  @debug.debug_inspect(
    result.stdout,
    content=(
      #|"hello world\n"
    ),
  )
}

///|
test "execute_shell_step: pre-populated fs" {
  let fs = @sandbox.MemFs::new()
  fs.write("/workspace/input.txt", "data from outside", false)
  let result = @sandbox.execute_shell_step("cat /workspace/input.txt", fs)
  @debug.debug_inspect(
    result.stdout,
    content=(
      #|"data from outside"
    ),
  )
}

///|
test "execute_shell_step: to_json roundtrip" {
  let fs = @sandbox.MemFs::new()
  let result = @sandbox.execute_shell_step("echo ok", fs)
  let json_str = @sandbox.step_result_to_json(result)
  @debug.debug_inspect(
    json_str.contains("\"status\":\"success\""),
    content="true",
  )
  @debug.debug_inspect(json_str.contains("\"exit_code\":0"), content="true")
}

///|
test "execute_shell_step: stderr capture" {
  let fs = @sandbox.MemFs::new()
  let result = @sandbox.execute_shell_step("unknown_cmd", fs)
  @debug.debug_inspect(
    result.status,
    content=(
      #|"failed"
    ),
  )
  @debug.debug_inspect(result.exit_code, content="127")
  @debug.debug_inspect(
    result.stderr.contains("command not found"),
    content="true",
  )
}
