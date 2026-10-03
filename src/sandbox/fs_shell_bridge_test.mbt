///|
test "fs_shell_env: echo writes to stdout" {
  let fs = @sandbox.MemFs::new()
  let env = @sandbox.new_fs_shell_env(fs, {})
  let code = @actrun.shell_exec(env, "echo hello")
  @debug.debug_inspect(code, content="0")
  @debug.debug_inspect(
    @actrun.shell_stdout(env),
    content=(
      #|"hello\n"
    ),
  )
}

///|
test "fs_shell_env: variable expansion" {
  let fs = @sandbox.MemFs::new()
  let env = @sandbox.new_fs_shell_env(fs, { "NAME": "world" })
  ignore(@actrun.shell_exec(env, "echo \"hello $NAME\""))
  @debug.debug_inspect(
    @actrun.shell_stdout(env),
    content=(
      #|"hello world\n"
    ),
  )
}

///|
test "fs_shell_env: redirect writes to fs" {
  let fs = @sandbox.MemFs::new()
  let env = @sandbox.new_fs_shell_env(fs, {})
  ignore(@actrun.shell_exec(env, "echo content > /workspace/out.txt"))
  @debug.debug_inspect(
    fs.read("/workspace/out.txt"),
    content="Some(\"content\\n\")",
  )
}

///|
test "fs_shell_env: append redirect" {
  let fs = @sandbox.MemFs::new()
  let env = @sandbox.new_fs_shell_env(fs, {})
  ignore(@actrun.shell_exec(env, "echo a > /workspace/out.txt"))
  ignore(@actrun.shell_exec(env, "echo b >> /workspace/out.txt"))
  @debug.debug_inspect(
    fs.read("/workspace/out.txt"),
    content="Some(\"a\\nb\\n\")",
  )
}

///|
test "fs_shell_env: cat reads from fs" {
  let fs = @sandbox.MemFs::new()
  fs.write("/workspace/data.txt", "file content", false)
  let env = @sandbox.new_fs_shell_env(fs, {})
  ignore(@actrun.shell_exec(env, "cat /workspace/data.txt"))
  @debug.debug_inspect(
    @actrun.shell_stdout(env),
    content=(
      #|"file content"
    ),
  )
}

///|
test "fs_shell_env: mkdir and cd" {
  let fs = @sandbox.MemFs::new()
  let env = @sandbox.new_fs_shell_env(fs, {})
  ignore(@actrun.shell_exec(env, "mkdir -p /workspace/sub"))
  @debug.debug_inspect(fs.is_dir("/workspace/sub"), content="true")
  let code = @actrun.shell_exec(env, "cd /workspace/sub && pwd")
  @debug.debug_inspect(code, content="0")
  @debug.debug_inspect(
    @actrun.shell_stdout(env),
    content=(
      #|"/workspace/sub\n"
    ),
  )
}

///|
test "fs_shell_env: GITHUB_OUTPUT pattern" {
  let fs = @sandbox.MemFs::new()
  fs.write("/workspace/github_output", "", false)
  let vars : Map[String, String] = {
    "GITHUB_OUTPUT": "/workspace/github_output",
  }
  let env = @sandbox.new_fs_shell_env(fs, vars)
  ignore(@actrun.shell_exec(env, "echo \"key=value\" >> $GITHUB_OUTPUT"))
  let content = fs.read("/workspace/github_output").unwrap()
  @debug.debug_inspect(content.contains("key=value"), content="true")
}
