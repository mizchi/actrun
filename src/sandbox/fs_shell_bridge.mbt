///|
pub fn new_fs_shell_env(
  fs : &Fs,
  vars : Map[String, String],
  cwd~ : String = "/workspace",
) -> @actrun.ShellEnv {
  @actrun.new_shell_env(
    vars,
    cwd~,
    write_file=fn(path, content, append) {
      fs.write(path, content, append)
      true
    },
    read_file=fn(path) { fs.read(path) },
    file_exists=fn(path) { fs.exists(path) },
    is_dir=fn(path) { fs.is_dir(path) },
    mkdir=fn(path) { fs.mkdir(path) },
    remove=fn(path) { fs.remove(path) },
  )
}
