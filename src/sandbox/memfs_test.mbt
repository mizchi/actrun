///|
test "MemFs: write and read" {
  let fs = @sandbox.MemFs::new()
  fs.write("/test.txt", "hello", false)
  @debug.debug_inspect(fs.read("/test.txt"), content="Some(\"hello\")")
}

///|
test "MemFs: append" {
  let fs = @sandbox.MemFs::new()
  fs.write("/test.txt", "a", false)
  fs.write("/test.txt", "b", true)
  @debug.debug_inspect(fs.read("/test.txt"), content="Some(\"ab\")")
}

///|
test "MemFs: read non-existent" {
  let fs = @sandbox.MemFs::new()
  @debug.debug_inspect(fs.read("/missing"), content="None")
}

///|
test "MemFs: exists" {
  let fs = @sandbox.MemFs::new()
  fs.write("/test.txt", "x", false)
  @debug.debug_inspect(fs.exists("/test.txt"), content="true")
  @debug.debug_inspect(fs.exists("/missing"), content="false")
}

///|
test "MemFs: remove existing" {
  let fs = @sandbox.MemFs::new()
  fs.write("/test.txt", "x", false)
  @debug.debug_inspect(fs.remove("/test.txt"), content="true")
  @debug.debug_inspect(fs.exists("/test.txt"), content="false")
}

///|
test "MemFs: remove non-existent" {
  let fs = @sandbox.MemFs::new()
  @debug.debug_inspect(fs.remove("/missing"), content="false")
}

///|
test "MemFs: mkdir creates dir marker" {
  let fs = @sandbox.MemFs::new()
  ignore(fs.mkdir("/workspace"))
  @debug.debug_inspect(fs.is_dir("/workspace"), content="true")
}

///|
test "MemFs: mkdir idempotent" {
  let fs = @sandbox.MemFs::new()
  ignore(fs.mkdir("/dir"))
  ignore(fs.mkdir("/dir"))
  @debug.debug_inspect(fs.is_dir("/dir"), content="true")
}

///|
test "MemFs: is_dir from child files" {
  let fs = @sandbox.MemFs::new()
  fs.write("/parent/child.txt", "c", false)
  @debug.debug_inspect(fs.is_dir("/parent"), content="true")
  @debug.debug_inspect(fs.is_dir("/par"), content="false")
}

///|
test "MemFs: is_dir with trailing slash" {
  let fs = @sandbox.MemFs::new()
  ignore(fs.mkdir("/dir/"))
  @debug.debug_inspect(fs.is_dir("/dir"), content="true")
  @debug.debug_inspect(fs.is_dir("/dir/"), content="true")
}

///|
test "MemFs: is_dir non-existent" {
  let fs = @sandbox.MemFs::new()
  @debug.debug_inspect(fs.is_dir("/nope"), content="false")
}

///|
test "parse_key_values: basic" {
  let fs = @sandbox.MemFs::new()
  fs.write("/out", "key1=value1\nkey2=value2\n", false)
  let kv = @sandbox.parse_key_values(fs, "/out")
  @debug.debug_inspect(kv.get("key1"), content="Some(\"value1\")")
  @debug.debug_inspect(kv.get("key2"), content="Some(\"value2\")")
}

///|
test "parse_key_values: empty file" {
  let fs = @sandbox.MemFs::new()
  fs.write("/out", "", false)
  let kv = @sandbox.parse_key_values(fs, "/out")
  @debug.debug_inspect(kv.length(), content="0")
}

///|
test "parse_key_values: missing file" {
  let fs = @sandbox.MemFs::new()
  let kv = @sandbox.parse_key_values(fs, "/missing")
  @debug.debug_inspect(kv.length(), content="0")
}

///|
test "parse_key_values: value contains equals" {
  let fs = @sandbox.MemFs::new()
  fs.write("/out", "url=https://example.com?a=1&b=2\n", false)
  let kv = @sandbox.parse_key_values(fs, "/out")
  @debug.debug_inspect(
    kv.get("url"),
    content="Some(\"https://example.com?a=1&b=2\")",
  )
}

///|
test "parse_key_values: lines without equals are skipped" {
  let fs = @sandbox.MemFs::new()
  fs.write("/out", "good=yes\nbadline\n=nope\n", false)
  let kv = @sandbox.parse_key_values(fs, "/out")
  @debug.debug_inspect(kv.get("good"), content="Some(\"yes\")")
  @debug.debug_inspect(kv.length(), content="1")
}
