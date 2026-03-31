///|
/// In-memory filesystem backed by a flat Map.
pub struct MemFs {
  files : Map[String, String]
}

///|
pub fn MemFs::new() -> MemFs {
  { files: {} }
}

///|
pub impl Fs for MemFs with fs_write(self, path, content, append) {
  if append {
    self.files[path] = self.files.get(path).unwrap_or("") + content
  } else {
    self.files[path] = content
  }
}

///|
pub impl Fs for MemFs with fs_read(self, path) {
  self.files.get(path)
}

///|
pub impl Fs for MemFs with fs_exists(self, path) {
  self.files.get(path) is Some(_)
}

///|
pub impl Fs for MemFs with fs_is_dir(self, path) {
  let dir_key = if path.has_suffix("/") { path } else { path + "/" }
  if self.files.get(dir_key) is Some(_) {
    return true
  }
  let prefix = if path.has_suffix("/") { path } else { path + "/" }
  for key, _ in self.files {
    if key.has_prefix(prefix) {
      return true
    }
  }
  false
}

///|
pub impl Fs for MemFs with fs_mkdir(self, path) {
  let dir_key = if path.has_suffix("/") { path } else { path + "/" }
  self.files[dir_key] = ""
  true
}

///|
pub impl Fs for MemFs with fs_remove(self, path) {
  if self.files.get(path) is Some(_) {
    self.files.remove(path)
    true
  } else {
    false
  }
}
