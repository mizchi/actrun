///|
pub struct MemFs {
  files : Map[String, String]
}

///|
pub fn MemFs::new() -> MemFs {
  { files: {} }
}

///|
pub impl Fs for MemFs with write(self, path, content, append) {
  if append {
    self.files[path] = self.files.get(path).unwrap_or("") + content
  } else {
    self.files[path] = content
  }
}

///|
pub impl Fs for MemFs with read(self, path) {
  self.files.get(path)
}

///|
pub impl Fs for MemFs with exists(self, path) {
  self.files.get(path) is Some(_)
}

///|
pub impl Fs for MemFs with is_dir(self, path) {
  let prefix = if path.has_suffix("/") { path } else { path + "/" }
  if self.files.get(prefix) is Some(_) {
    return true
  }
  for key, _ in self.files {
    if key.has_prefix(prefix) {
      return true
    }
  }
  false
}

///|
pub impl Fs for MemFs with mkdir(self, path) {
  let dir_key = if path.has_suffix("/") { path } else { path + "/" }
  self.files[dir_key] = ""
  true
}

///|
pub impl Fs for MemFs with remove(self, path) {
  let had = self.files.get(path) is Some(_)
  self.files.remove(path)
  had
}
