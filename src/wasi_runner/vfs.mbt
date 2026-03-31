///|
/// In-memory virtual filesystem for WASI runner.
/// Files are stored as strings. No directories, no permissions.

///|
pub struct VirtualFs {
  files : Map[String, String]
}

///|
pub fn VirtualFs::new() -> VirtualFs {
  { files: {} }
}

///|
pub fn VirtualFs::write(
  self : VirtualFs,
  path : String,
  content : String,
  append? : Bool = false,
) -> Unit {
  if append {
    self.files[path] = self.files.get(path).unwrap_or("") + content
  } else {
    self.files[path] = content
  }
}

///|
pub fn VirtualFs::read(self : VirtualFs, path : String) -> String? {
  self.files.get(path)
}

///|
pub fn VirtualFs::exists(self : VirtualFs, path : String) -> Bool {
  self.files.get(path) is Some(_)
}

///|
/// Parse key=value entries from a file (GITHUB_OUTPUT / GITHUB_ENV format).
pub fn VirtualFs::parse_key_values(
  self : VirtualFs,
  path : String,
) -> Map[String, String] {
  let result : Map[String, String] = {}
  let content = self.files.get(path).unwrap_or("")
  let lines = split_lines(content)
  for line in lines {
    if line.length() == 0 {
      continue
    }
    let eq = find_char_index(line, '=')
    if eq > 0 {
      result[String::unsafe_substring(line, start=0, end=eq)] = String::unsafe_substring(
        line,
        start=eq + 1,
        end=line.length(),
      )
    }
  }
  result
}

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for ch in s {
    if ch == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    lines.push(last)
  }
  lines
}

///|
pub fn VirtualFs::remove(self : VirtualFs, path : String) -> Bool {
  if self.files.get(path) is Some(_) {
    self.files.remove(path)
    true
  } else {
    false
  }
}

///|
pub fn VirtualFs::mkdir(self : VirtualFs, path : String) -> Bool {
  let dir_key = if path.has_suffix("/") { path } else { path + "/" }
  self.files[dir_key] = ""
  true
}

///|
pub fn VirtualFs::is_dir(self : VirtualFs, path : String) -> Bool {
  let dir_key = if path.has_suffix("/") { path } else { path + "/" }
  if self.files.get(dir_key) is Some(_) {
    return true
  }
  // Check if any file exists under this path prefix
  let prefix = if path.has_suffix("/") { path } else { path + "/" }
  for key, _ in self.files {
    if key.has_prefix(prefix) {
      return true
    }
  }
  false
}

///|
fn find_char_index(s : String, target : Char) -> Int {
  let code = target.to_int().to_uint16()
  let mut idx = 0
  while idx < s.length() {
    if s.unsafe_get(idx) == code {
      return idx
    }
    idx += 1
  }
  -1
}
