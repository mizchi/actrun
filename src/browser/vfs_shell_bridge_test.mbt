///|
test "vfs_shell_env: echo writes to stdout" {
  let vfs = @wr.VirtualFs::new()
  let env = new_vfs_shell_env(vfs, {})
  let code = @actrun.shell_exec(env, "echo hello")
  inspect(code, content="0")
  inspect(@actrun.shell_stdout(env), content="hello\n")
}

///|
test "vfs_shell_env: variable expansion" {
  let vfs = @wr.VirtualFs::new()
  let env = new_vfs_shell_env(vfs, { "NAME": "world" })
  ignore(@actrun.shell_exec(env, "echo \"hello $NAME\""))
  inspect(@actrun.shell_stdout(env), content="hello world\n")
}

///|
test "vfs_shell_env: redirect writes to VFS" {
  let vfs = @wr.VirtualFs::new()
  let env = new_vfs_shell_env(vfs, {})
  ignore(@actrun.shell_exec(env, "echo content > /workspace/out.txt"))
  inspect(vfs.read("/workspace/out.txt"), content="Some(\"content\\n\")")
}

///|
test "vfs_shell_env: append redirect" {
  let vfs = @wr.VirtualFs::new()
  let env = new_vfs_shell_env(vfs, {})
  ignore(@actrun.shell_exec(env, "echo a > /workspace/out.txt"))
  ignore(@actrun.shell_exec(env, "echo b >> /workspace/out.txt"))
  inspect(vfs.read("/workspace/out.txt"), content="Some(\"a\\nb\\n\")")
}

///|
test "vfs_shell_env: cat reads from VFS" {
  let vfs = @wr.VirtualFs::new()
  vfs.write("/workspace/data.txt", "file content")
  let env = new_vfs_shell_env(vfs, {})
  ignore(@actrun.shell_exec(env, "cat /workspace/data.txt"))
  inspect(@actrun.shell_stdout(env), content="file content")
}

///|
test "vfs_shell_env: mkdir and cd" {
  let vfs = @wr.VirtualFs::new()
  let env = new_vfs_shell_env(vfs, {})
  ignore(@actrun.shell_exec(env, "mkdir -p /workspace/sub"))
  inspect(vfs.is_dir("/workspace/sub"), content="true")
  let code = @actrun.shell_exec(env, "cd /workspace/sub && pwd")
  inspect(code, content="0")
  inspect(@actrun.shell_stdout(env), content="/workspace/sub\n")
}

///|
test "vfs_shell_env: GITHUB_OUTPUT pattern" {
  let vfs = @wr.VirtualFs::new()
  vfs.write("/workspace/github_output", "")
  let vars : Map[String, String] = { "GITHUB_OUTPUT": "/workspace/github_output" }
  let env = new_vfs_shell_env(vfs, vars)
  ignore(@actrun.shell_exec(env, "echo \"key=value\" >> $GITHUB_OUTPUT"))
  let content = vfs.read("/workspace/github_output").unwrap()
  inspect(content.contains("key=value"), content="true")
}
