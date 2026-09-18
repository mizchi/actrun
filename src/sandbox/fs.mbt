///|
pub(open) trait Fs {
  fn write(Self, String, String, Bool) -> Unit // path, content, append
  fn read(Self, String) -> String?
  fn exists(Self, String) -> Bool
  fn is_dir(Self, String) -> Bool
  fn mkdir(Self, String) -> Bool
  fn remove(Self, String) -> Bool
}

///|
/// Parse KEY=VALUE entries from a file (GITHUB_OUTPUT / GITHUB_ENV format).
pub fn parse_key_values(fs : &Fs, path : String) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  let content = match fs.read(path) {
    Some(s) => s
    None => return result
  }
  let lines = content.split("\n")
  for line_view in lines {
    let line = line_view.to_owned()
    if line.length() == 0 {
      continue
    }
    let eq = find_eq_index(line)
    if eq > 0 {
      result[line[:eq].to_owned()] = line[eq + 1:].to_owned()
    }
  }
  result
}

///|
fn find_eq_index(s : String) -> Int {
  let eq_code = '='.to_int().to_uint16()
  for i in 0..<s.length() {
    if s.unsafe_get(i) == eq_code {
      return i
    }
  }
  -1
}
