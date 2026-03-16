///|
#cfg(target="native")
async fn run_command(
  cmd : String,
  args : Array[String],
  cwd~ : String = ".",
) -> (Int, String, String) {
  let (code, stdout, stderr) = @process.collect_output(cmd, args, cwd~)
  (code, stdout.text(), stderr.text())
}

///|
#cfg(target="native")
async fn run_command_with_stdin(
  cmd : String,
  args : Array[String],
  stdin_text : String,
  cwd~ : String = ".",
) -> (Int, String, String) {
  // Pipe stdin via printf to avoid write_to_process API complexity
  let quoted_args = args.map(fn(a) { shell_quote(a) })
  let shell_cmd = "printf '%s' " +
    shell_quote(stdin_text) +
    " | " +
    shell_quote(cmd) +
    " " +
    quoted_args.join(" ")
  let (code, stdout, stderr) = @process.collect_output(
    "sh", ["-c", shell_cmd], cwd~,
  )
  (code, stdout.text(), stderr.text())
}

///|
#cfg(target="native")
fn shell_quote(s : String) -> String {
  "'" + s.replace_all(old="'", new="'\"'\"'") + "'"
}
