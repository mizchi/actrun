///|
/// Bridge Fs trait to ShellEnv DI callbacks.
/// All filesystem operations route through the injected Fs implementation.

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
      fs.fs_write(path, content, append)
      true
    },
    read_file=fn(path) { fs.fs_read(path) },
    file_exists=fn(path) { fs.fs_exists(path) },
    is_dir=fn(path) { fs.fs_is_dir(path) },
    mkdir=fn(path) { fs.fs_mkdir(path) },
    remove=fn(path) { fs.fs_remove(path) },
  )
}
