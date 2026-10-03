///|
test "VirtualFs: write and read" {
  let vfs = @wasi_runner.VirtualFs::new()
  vfs.write("/test.txt", "hello")
  @debug.debug_inspect(vfs.read("/test.txt"), content="Some(\"hello\")")
}

///|
test "VirtualFs: append" {
  let vfs = @wasi_runner.VirtualFs::new()
  vfs.write("/test.txt", "a")
  vfs.write("/test.txt", "b", append=true)
  @debug.debug_inspect(vfs.read("/test.txt"), content="Some(\"ab\")")
}

///|
test "VirtualFs: overwrite" {
  let vfs = @wasi_runner.VirtualFs::new()
  vfs.write("/test.txt", "old")
  vfs.write("/test.txt", "new")
  @debug.debug_inspect(vfs.read("/test.txt"), content="Some(\"new\")")
}

///|
test "VirtualFs: read non-existent" {
  let vfs = @wasi_runner.VirtualFs::new()
  @debug.debug_inspect(vfs.read("/missing.txt"), content="None")
}

///|
test "VirtualFs: exists" {
  let vfs = @wasi_runner.VirtualFs::new()
  vfs.write("/test.txt", "x")
  @debug.debug_inspect(vfs.exists("/test.txt"), content="true")
  @debug.debug_inspect(vfs.exists("/missing.txt"), content="false")
}

///|
test "VirtualFs: parse_key_values" {
  let vfs = @wasi_runner.VirtualFs::new()
  vfs.write("/out", "key1=value1\nkey2=value2\n")
  let kv = vfs.parse_key_values("/out")
  @debug.debug_inspect(kv.get("key1"), content="Some(\"value1\")")
  @debug.debug_inspect(kv.get("key2"), content="Some(\"value2\")")
}

///|
test "VirtualFs: parse_key_values empty" {
  let vfs = @wasi_runner.VirtualFs::new()
  vfs.write("/out", "")
  let kv = vfs.parse_key_values("/out")
  @debug.debug_inspect(kv.length(), content="0")
}

///|
test "VirtualFs: remove" {
  let vfs = @wasi_runner.VirtualFs::new()
  vfs.write("/test.txt", "x")
  @debug.debug_inspect(vfs.remove("/test.txt"), content="true")
  @debug.debug_inspect(vfs.exists("/test.txt"), content="false")
  @debug.debug_inspect(vfs.remove("/missing.txt"), content="false")
}

///|
test "VirtualFs: mkdir and is_dir" {
  let vfs = @wasi_runner.VirtualFs::new()
  ignore(vfs.mkdir("/workspace"))
  @debug.debug_inspect(vfs.is_dir("/workspace"), content="true")
  @debug.debug_inspect(vfs.is_dir("/missing"), content="false")
}

///|
test "VirtualFs: is_dir with child files" {
  let vfs = @wasi_runner.VirtualFs::new()
  vfs.write("/workspace/file.txt", "content")
  @debug.debug_inspect(vfs.is_dir("/workspace"), content="true")
  @debug.debug_inspect(vfs.is_dir("/work"), content="false")
}

///|
test "WasiContext: new with inputs" {
  let ctx = @wasi_runner.WasiContext::new(inputs={ "message": "hello" })
  @debug.debug_inspect(ctx.env.get("INPUT_MESSAGE"), content="Some(\"hello\")")
  @debug.debug_inspect(ctx.env.get("GITHUB_OUTPUT") is Some(_), content="true")
}

///|
test "WasiContext: collect empty result" {
  let ctx = @wasi_runner.WasiContext::new()
  let result = ctx.collect_result()
  @debug.debug_inspect(
    result.status,
    content=(
      #|"success"
    ),
  )
  @debug.debug_inspect(result.exit_code, content="0")
}
