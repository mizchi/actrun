///|
test "VirtualFs: write and read" {
  let vfs = VirtualFs::new()
  vfs.write("/test.txt", "hello")
  inspect(vfs.read("/test.txt"), content="Some(\"hello\")")
}

///|
test "VirtualFs: append" {
  let vfs = VirtualFs::new()
  vfs.write("/test.txt", "a")
  vfs.write("/test.txt", "b", append=true)
  inspect(vfs.read("/test.txt"), content="Some(\"ab\")")
}

///|
test "VirtualFs: overwrite" {
  let vfs = VirtualFs::new()
  vfs.write("/test.txt", "old")
  vfs.write("/test.txt", "new")
  inspect(vfs.read("/test.txt"), content="Some(\"new\")")
}

///|
test "VirtualFs: read non-existent" {
  let vfs = VirtualFs::new()
  inspect(vfs.read("/missing.txt"), content="None")
}

///|
test "VirtualFs: exists" {
  let vfs = VirtualFs::new()
  vfs.write("/test.txt", "x")
  inspect(vfs.exists("/test.txt"), content="true")
  inspect(vfs.exists("/missing.txt"), content="false")
}

///|
test "VirtualFs: parse_key_values" {
  let vfs = VirtualFs::new()
  vfs.write("/out", "key1=value1\nkey2=value2\n")
  let kv = vfs.parse_key_values("/out")
  inspect(kv.get("key1"), content="Some(\"value1\")")
  inspect(kv.get("key2"), content="Some(\"value2\")")
}

///|
test "VirtualFs: parse_key_values empty" {
  let vfs = VirtualFs::new()
  vfs.write("/out", "")
  let kv = vfs.parse_key_values("/out")
  inspect(kv.length(), content="0")
}

///|
test "WasiContext: new with inputs" {
  let ctx = WasiContext::new(inputs={ "message": "hello" })
  inspect(ctx.env.get("INPUT_MESSAGE"), content="Some(\"hello\")")
  inspect(ctx.env.get("GITHUB_OUTPUT") is Some(_), content="true")
}

///|
test "WasiContext: collect empty result" {
  let ctx = WasiContext::new()
  let result = ctx.collect_result()
  inspect(result.status, content="success")
  inspect(result.exit_code, content="0")
}
