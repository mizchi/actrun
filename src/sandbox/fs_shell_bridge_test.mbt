///|
test "fs_shell_env: echo writes to stdout" {
  let fs = MemFs::new()
  let env = new_fs_shell_env(fs, {})
  let code = @actrun.shell_exec(env, "echo hello")
  inspect(code, content="0")
  inspect(@actrun.shell_stdout(env), content="hello\n")
}

///|
test "fs_shell_env: variable expansion" {
  let fs = MemFs::new()
  let env = new_fs_shell_env(fs, { "NAME": "world" })
  ignore(@actrun.shell_exec(env, "echo \"hello $NAME\""))
  inspect(@actrun.shell_stdout(env), content="hello world\n")
}

///|
test "fs_shell_env: redirect writes to fs" {
  let fs = MemFs::new()
  let env = new_fs_shell_env(fs, {})
  ignore(@actrun.shell_exec(env, "echo content > /workspace/out.txt"))
  inspect(fs.fs_read("/workspace/out.txt"), content="Some(\"content\\n\")")
}

///|
test "fs_shell_env: append redirect" {
  let fs = MemFs::new()
  let env = new_fs_shell_env(fs, {})
  ignore(@actrun.shell_exec(env, "echo a > /workspace/out.txt"))
  ignore(@actrun.shell_exec(env, "echo b >> /workspace/out.txt"))
  inspect(fs.fs_read("/workspace/out.txt"), content="Some(\"a\\nb\\n\")")
}

///|
test "fs_shell_env: cat reads from fs" {
  let fs = MemFs::new()
  fs.fs_write("/workspace/data.txt", "file content", false)
  let env = new_fs_shell_env(fs, {})
  ignore(@actrun.shell_exec(env, "cat /workspace/data.txt"))
  inspect(@actrun.shell_stdout(env), content="file content")
}

///|
test "fs_shell_env: mkdir and cd" {
  let fs = MemFs::new()
  let env = new_fs_shell_env(fs, {})
  ignore(@actrun.shell_exec(env, "mkdir -p /workspace/sub"))
  inspect(fs.fs_is_dir("/workspace/sub"), content="true")
  let code = @actrun.shell_exec(env, "cd /workspace/sub && pwd")
  inspect(code, content="0")
  inspect(@actrun.shell_stdout(env), content="/workspace/sub\n")
}

///|
test "fs_shell_env: GITHUB_OUTPUT pattern" {
  let fs = MemFs::new()
  fs.fs_write("/workspace/github_output", "", false)
  let vars : Map[String, String] = { "GITHUB_OUTPUT": "/workspace/github_output" }
  let env = new_fs_shell_env(fs, vars)
  ignore(@actrun.shell_exec(env, "echo \"key=value\" >> $GITHUB_OUTPUT"))
  let content = fs.fs_read("/workspace/github_output").unwrap()
  inspect(content.contains("key=value"), content="true")
}
