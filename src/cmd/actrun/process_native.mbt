///|
#cfg(target="native")
async fn run_command(
  cmd : String,
  args : Array[String],
  cwd? : String = ".",
) -> (Int, String, String) {
  let (code, stdout, stderr) = @process.collect_output(cmd, args, cwd~)
  (code, stdout.text(), stderr.text())
}
