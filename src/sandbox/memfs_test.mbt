///|
test "MemFs: write and read" {
  let fs = MemFs::new()
  fs.write("/test.txt", "hello", false)
  inspect(fs.read("/test.txt"), content="Some(\"hello\")")
}

///|
test "MemFs: append" {
  let fs = MemFs::new()
  fs.write("/test.txt", "a", false)
  fs.write("/test.txt", "b", true)
  inspect(fs.read("/test.txt"), content="Some(\"ab\")")
}

///|
test "MemFs: read non-existent" {
  let fs = MemFs::new()
  inspect(fs.read("/missing"), content="None")
}

///|
test "MemFs: exists" {
  let fs = MemFs::new()
  fs.write("/test.txt", "x", false)
  inspect(fs.exists("/test.txt"), content="true")
  inspect(fs.exists("/missing"), content="false")
}

///|
test "MemFs: remove existing" {
  let fs = MemFs::new()
  fs.write("/test.txt", "x", false)
  inspect(fs.remove("/test.txt"), content="true")
  inspect(fs.exists("/test.txt"), content="false")
}

///|
test "MemFs: remove non-existent" {
  let fs = MemFs::new()
  inspect(fs.remove("/missing"), content="false")
}

///|
test "MemFs: mkdir creates dir marker" {
  let fs = MemFs::new()
  ignore(fs.mkdir("/workspace"))
  inspect(fs.is_dir("/workspace"), content="true")
}

///|
test "MemFs: mkdir idempotent" {
  let fs = MemFs::new()
  ignore(fs.mkdir("/dir"))
  ignore(fs.mkdir("/dir"))
  inspect(fs.is_dir("/dir"), content="true")
}

///|
test "MemFs: is_dir from child files" {
  let fs = MemFs::new()
  fs.write("/parent/child.txt", "c", false)
  inspect(fs.is_dir("/parent"), content="true")
  inspect(fs.is_dir("/par"), content="false")
}

///|
test "MemFs: is_dir with trailing slash" {
  let fs = MemFs::new()
  ignore(fs.mkdir("/dir/"))
  inspect(fs.is_dir("/dir"), content="true")
  inspect(fs.is_dir("/dir/"), content="true")
}

///|
test "MemFs: is_dir non-existent" {
  let fs = MemFs::new()
  inspect(fs.is_dir("/nope"), content="false")
}

///|
test "parse_key_values: basic" {
  let fs = MemFs::new()
  fs.write("/out", "key1=value1\nkey2=value2\n", false)
  let kv = parse_key_values(fs, "/out")
  inspect(kv.get("key1"), content="Some(\"value1\")")
  inspect(kv.get("key2"), content="Some(\"value2\")")
}

///|
test "parse_key_values: empty file" {
  let fs = MemFs::new()
  fs.write("/out", "", false)
  let kv = parse_key_values(fs, "/out")
  inspect(kv.length(), content="0")
}

///|
test "parse_key_values: missing file" {
  let fs = MemFs::new()
  let kv = parse_key_values(fs, "/missing")
  inspect(kv.length(), content="0")
}

///|
test "parse_key_values: value contains equals" {
  let fs = MemFs::new()
  fs.write("/out", "url=https://example.com?a=1&b=2\n", false)
  let kv = parse_key_values(fs, "/out")
  inspect(kv.get("url"), content="Some(\"https://example.com?a=1&b=2\")")
}

///|
test "parse_key_values: lines without equals are skipped" {
  let fs = MemFs::new()
  fs.write("/out", "good=yes\nbadline\n=nope\n", false)
  let kv = parse_key_values(fs, "/out")
  inspect(kv.get("good"), content="Some(\"yes\")")
  inspect(kv.length(), content="1")
}
