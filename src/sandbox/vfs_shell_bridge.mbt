///|
/// Bridge VirtualFs to ShellEnv DI callbacks.
/// All filesystem operations route through the in-memory VFS.

///|
pub fn new_vfs_shell_env(
  vfs : @wr.VirtualFs,
  vars : Map[String, String],
  cwd~ : String = "/workspace",
) -> @actrun.ShellEnv {
  @actrun.new_shell_env(
    vars,
    cwd~,
    write_file=fn(path, content, append) {
      vfs.write(path, content, append~)
      true
    },
    read_file=fn(path) { vfs.read(path) },
    file_exists=fn(path) { vfs.exists(path) },
    is_dir=fn(path) { vfs.is_dir(path) },
    mkdir=fn(path) {
      vfs.mkdir(path)
    },
    remove=fn(path) { vfs.remove(path) },
  )
}
