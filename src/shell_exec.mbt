///|
/// Minimal shell executor for actrun.
/// Uses moonix @sh parser for AST, implements evaluation in-process.
/// No external bash/sh binary needed.

///|
pub struct ShellEnv {
  vars : Map[String, String]
  mut cwd : String
  stdout_buf : Array[String]
  stderr_buf : Array[String]
  mut exit_code : Int
  mut exit_called : Bool
  // File write function — allows MemFs or real FS
  write_file : (String, String, Bool) -> Bool // (path, content, append) -> ok
  read_file : (String) -> String? // path -> content?
  file_exists : (String) -> Bool
  is_dir : (String) -> Bool
  mkdir : (String) -> Bool
  remove : (String) -> Bool
}

///|
pub fn new_shell_env(
  vars : Map[String, String],
  cwd? : String = "/",
  write_file? : (String, String, Bool) -> Bool = fn(_, _, _) { false },
  read_file? : (String) -> String? = fn(_) { None },
  file_exists? : (String) -> Bool = fn(_) { false },
  is_dir? : (String) -> Bool = fn(_) { false },
  mkdir? : (String) -> Bool = fn(_) { false },
  remove? : (String) -> Bool = fn(_) { false },
) -> ShellEnv {
  {
    vars,
    cwd,
    stdout_buf: [],
    stderr_buf: [],
    exit_code: 0,
    exit_called: false,
    write_file,
    read_file,
    mkdir,
    remove,
    file_exists,
    is_dir,
  }
}

///|
pub fn shell_exec(env : ShellEnv, script : String) -> Int {
  let list = @sh.parse_list(script) catch {
    err => {
      env.stderr_buf.push("parse error: " + err.to_string() + "\n")
      return 127
    }
  }
  exec_command_list(env, list)
}

///|
pub fn shell_stdout(env : ShellEnv) -> String {
  env.stdout_buf.join("")
}

///|
pub fn shell_stderr(env : ShellEnv) -> String {
  env.stderr_buf.join("")
}

///|
fn exec_command_list(env : ShellEnv, list : @sh.CommandList) -> Int {
  let mut code = exec_pipeline(env, list.first)
  env.exit_code = code
  for item in list.rest {
    if env.exit_called {
      break
    }
    let (op, pipeline) = item
    match op {
      @sh.Seq => {
        code = exec_pipeline(env, pipeline)
        env.exit_code = code
      }
      @sh.And =>
        if code == 0 {
          code = exec_pipeline(env, pipeline)
          env.exit_code = code
        }
      @sh.Or =>
        if code != 0 {
          code = exec_pipeline(env, pipeline)
          env.exit_code = code
        }
      @sh.Background => {
        // Background not supported in embedded shell, run sequentially
        code = exec_pipeline(env, pipeline)
        env.exit_code = code
      }
    }
  }
  code
}

///|
fn exec_pipeline(env : ShellEnv, pipeline : @sh.Pipeline) -> Int {
  if pipeline.commands.length() == 1 {
    let code = exec_command(env, pipeline.commands[0])
    return if pipeline.bang { if code == 0 { 1 } else { 0 } } else { code }
  }
  // Multi-command pipeline: capture stdout of each, feed to next
  let mut pipe_data = ""
  let mut code = 0
  for cmd in pipeline.commands {
    let saved_stdout = env.stdout_buf.copy()
    env.stdout_buf.clear()
    // TODO: feed pipe_data as stdin to next command
    code = exec_command(env, cmd)
    pipe_data = env.stdout_buf.join("")
    env.stdout_buf.clear()
    for s in saved_stdout {
      env.stdout_buf.push(s)
    }
  }
  // Output final pipe stage result
  env.stdout_buf.push(pipe_data)
  if pipeline.bang {
    if code == 0 {
      1
    } else {
      0
    }
  } else {
    code
  }
}

///|
fn exec_command(env : ShellEnv, cmd : @sh.Command) -> Int {
  if env.exit_called {
    return env.exit_code
  }
  match cmd {
    @sh.Simple(simple) => exec_simple(env, simple)
    @sh.List(list) => exec_command_list(env, list)
    @sh.IfCmd(clause) => exec_if(env, clause)
    @sh.WhileCmd(clause) => exec_while(env, clause)
    @sh.ForCmd(clause) => exec_for(env, clause)
    @sh.Subshell(list) | @sh.BraceGroup(list) => exec_command_list(env, list)
    @sh.Pipeline(pipeline) => exec_pipeline(env, pipeline)
    @sh.CaseCmd(_) | @sh.FuncDef(_) => 0
  }
}

///|
fn exec_simple(env : ShellEnv, cmd : @sh.SimpleCommand) -> Int {
  // Handle variable assignments
  for assign in cmd.assigns {
    let (name, word) = assign
    env.vars[name] = expand_word(env, word)
  }
  if cmd.words.is_empty() {
    return 0
  }
  let expanded : Array[String] = []
  for word in cmd.words {
    expanded.push(expand_word(env, word))
  }
  let name = expanded[0]
  let args = shell_array_slice(expanded, 1)
  // Handle redirects: capture output path for > and >>
  let mut redirect_path = ""
  let mut redirect_append = false
  for redir in cmd.redirects {
    match redir.kind {
      @sh.Output => {
        redirect_path = expand_word(env, redir.target)
        redirect_append = false
      }
      @sh.Append => {
        redirect_path = expand_word(env, redir.target)
        redirect_append = true
      }
      _ => ()
    }
  }
  let saved_stdout = if redirect_path.length() > 0 {
    let saved = env.stdout_buf.copy()
    env.stdout_buf.clear()
    saved
  } else {
    []
  }
  let code = exec_builtin(env, name, args)
  if redirect_path.length() > 0 {
    let output = env.stdout_buf.join("")
    env.stdout_buf.clear()
    for s in saved_stdout {
      env.stdout_buf.push(s)
    }
    let resolved = resolve_path(env.cwd, redirect_path)
    ignore((env.write_file)(resolved, output, redirect_append))
  }
  code
}

///|
fn exec_if(env : ShellEnv, clause : @sh.IfClause) -> Int {
  if exec_command_list(env, clause.condition) == 0 {
    return exec_command_list(env, clause.then_body)
  }
  for elif in clause.elif_parts {
    let (cond, body) = elif
    if exec_command_list(env, cond) == 0 {
      return exec_command_list(env, body)
    }
  }
  match clause.else_body {
    Some(body) => exec_command_list(env, body)
    None => 0
  }
}

///|
fn exec_while(env : ShellEnv, clause : @sh.WhileClause) -> Int {
  let mut code = 0
  if clause.is_until {
    while exec_command_list(env, clause.condition) != 0 && not(env.exit_called) {
      code = exec_command_list(env, clause.body)
    }
  } else {
    while exec_command_list(env, clause.condition) == 0 && not(env.exit_called) {
      code = exec_command_list(env, clause.body)
    }
  }
  code
}

///|
fn exec_for(env : ShellEnv, clause : @sh.ForClause) -> Int {
  let words = match clause.words {
    Some(ws) => {
      let result : Array[String] = []
      for w in ws {
        result.push(expand_word(env, w))
      }
      result
    }
    None => [] // TODO: iterate over positional params
  }
  let mut code = 0
  for word in words {
    if env.exit_called {
      break
    }
    env.vars[clause.varname] = word
    code = exec_command_list(env, clause.body)
  }
  code
}

///|
fn exec_builtin(env : ShellEnv, name : String, args : Array[String]) -> Int {
  match name {
    "echo" => builtin_echo(env, args)
    "printf" => builtin_printf(env, args)
    "cat" => builtin_cat(env, args)
    "mkdir" => builtin_mkdir(env, args)
    "cd" => builtin_cd(env, args)
    "pwd" => builtin_pwd(env)
    "test" | "[" => builtin_test(env, args)
    "true" => 0
    "false" => 1
    "exit" => {
      env.exit_called = true
      env.exit_code = if args.length() > 0 {
        @strconv.parse_int(args[0]) catch {
          _ => 1
        }
      } else {
        env.exit_code
      }
      env.exit_code
    }
    "export" => {
      for arg in args {
        match shell_find_char(arg, '=') {
          Some(eq) => {
            let key = shell_text_slice(arg, 0, eq)
            let val = shell_text_slice(arg, eq + 1, arg.length())
            env.vars[key] = val
          }
          None => () // export existing var
        }
      }
      0
    }
    "set" => 0 // TODO: handle -e, -o pipefail
    ":" => 0 // no-op
    "rm" => builtin_rm(env, args)
    "cp" => builtin_cp(env, args)
    "chmod" => 0 // no-op in embedded shell (no permission model)
    _ => {
      env.stderr_buf.push(name + ": command not found\n")
      127
    }
  }
}

///|
fn builtin_echo(env : ShellEnv, args : Array[String]) -> Int {
  let mut newline = true
  let mut start = 0
  if args.length() > 0 && args[0] == "-n" {
    newline = false
    start = 1
  }
  let parts : Array[String] = []
  for i in start..<args.length() {
    parts.push(args[i])
  }
  env.stdout_buf.push(parts.join(" "))
  if newline {
    env.stdout_buf.push("\n")
  }
  0
}

///|
fn builtin_printf(env : ShellEnv, args : Array[String]) -> Int {
  if args.length() == 0 {
    return 0
  }
  let fmt = args[0]
  if args.length() == 1 {
    env.stdout_buf.push(shell_printf_expand(fmt, []))
  } else {
    env.stdout_buf.push(shell_printf_expand(fmt, shell_array_slice(args, 1)))
  }
  0
}

///|
fn shell_printf_expand(fmt : String, args : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut idx = 0
  let mut arg_idx = 0
  while idx < fmt.length() {
    let ch = shell_char_at(fmt, idx)
    if ch == '%' && idx + 1 < fmt.length() {
      let next = shell_char_at(fmt, idx + 1)
      match next {
        's' => {
          buf.write_string(
            if arg_idx < args.length() {
              args[arg_idx]
            } else {
              ""
            },
          )
          arg_idx += 1
          idx += 2
        }
        'd' => {
          buf.write_string(
            if arg_idx < args.length() {
              args[arg_idx]
            } else {
              "0"
            },
          )
          arg_idx += 1
          idx += 2
        }
        '%' => {
          buf.write_char('%')
          idx += 2
        }
        _ => {
          buf.write_char('%')
          idx += 1
        }
      }
    } else if ch == '\\' && idx + 1 < fmt.length() {
      let next = shell_char_at(fmt, idx + 1)
      match next {
        'n' => {
          buf.write_char('\n')
          idx += 2
        }
        't' => {
          buf.write_char('\t')
          idx += 2
        }
        '\\' => {
          buf.write_char('\\')
          idx += 2
        }
        _ => {
          buf.write_char('\\')
          idx += 1
        }
      }
    } else {
      buf.write_char(ch)
      idx += 1
    }
  }
  buf.to_string()
}

///|
fn builtin_cat(env : ShellEnv, args : Array[String]) -> Int {
  for arg in args {
    let path = resolve_path(env.cwd, arg)
    match (env.read_file)(path) {
      Some(content) => env.stdout_buf.push(content)
      None => {
        env.stderr_buf.push("cat: " + arg + ": No such file or directory\n")
        return 1
      }
    }
  }
  0
}

///|
fn builtin_mkdir(env : ShellEnv, args : Array[String]) -> Int {
  for arg in args {
    if arg == "-p" {
      continue
    }
    let path = resolve_path(env.cwd, arg)
    ignore((env.mkdir)(path))
  }
  0
}

///|
fn builtin_cd(env : ShellEnv, args : Array[String]) -> Int {
  if args.length() == 0 {
    return 0
  }
  let target = resolve_path(env.cwd, args[0])
  if (env.is_dir)(target) {
    env.cwd = target
    0
  } else {
    env.stderr_buf.push("cd: " + args[0] + ": No such file or directory\n")
    1
  }
}

///|
fn builtin_pwd(env : ShellEnv) -> Int {
  env.stdout_buf.push(env.cwd + "\n")
  0
}

///|
fn builtin_rm(env : ShellEnv, args : Array[String]) -> Int {
  for arg in args {
    if arg.has_prefix("-") {
      continue
    }
    let path = resolve_path(env.cwd, arg)
    ignore((env.remove)(path))
  }
  0
}

///|
fn builtin_cp(env : ShellEnv, args : Array[String]) -> Int {
  let files : Array[String] = []
  for arg in args {
    if not(arg.has_prefix("-")) {
      files.push(arg)
    }
  }
  if files.length() < 2 {
    return 1
  }
  let src = resolve_path(env.cwd, files[0])
  let dst = resolve_path(env.cwd, files[1])
  match (env.read_file)(src) {
    Some(content) => {
      ignore((env.write_file)(dst, content, false))
      0
    }
    None => 1
  }
}

///|
fn builtin_test(env : ShellEnv, args : Array[String]) -> Int {
  ignore(env)
  let args : Array[String] = if args.length() > 0 &&
    args[args.length() - 1] == "]" {
    let a : Array[String] = []
    for i in 0..<(args.length() - 1) {
      a.push(args[i])
    }
    a
  } else {
    args
  }
  if args.length() == 0 {
    return 1
  }
  if args.length() == 1 {
    // test STRING — true if non-empty
    return if args[0].length() > 0 { 0 } else { 1 }
  }
  if args.length() == 2 {
    match args[0] {
      "-z" => return if args[1].length() == 0 { 0 } else { 1 }
      "-n" => return if args[1].length() > 0 { 0 } else { 1 }
      "!" =>
        return if builtin_test(env, shell_array_slice(args, 1)) != 0 {
          0
        } else {
          1
        }
      _ => return 1
    }
  }
  if args.length() == 3 {
    match args[1] {
      "=" | "==" => return if args[0] == args[2] { 0 } else { 1 }
      "!=" => return if args[0] != args[2] { 0 } else { 1 }
      _ => return 1
    }
  }
  1
}

///|
fn expand_word(env : ShellEnv, word : @sh.Word) -> String {
  let buf = StringBuilder::new()
  for part in word.parts {
    match part {
      @sh.Literal(s) => buf.write_string(s)
      @sh.SingleQuoted(s) => buf.write_string(s)
      @sh.DoubleQuoted(parts) =>
        for p in parts {
          match p {
            @sh.Literal(s) => buf.write_string(s)
            @sh.Variable(name) =>
              buf.write_string(env.vars.get(name).unwrap_or(""))
            @sh.SpecialVar(ch) =>
              match ch {
                '?' => buf.write_string(env.exit_code.to_string())
                _ => ()
              }
            _ => ()
          }
        }
      @sh.Variable(name) => buf.write_string(env.vars.get(name).unwrap_or(""))
      @sh.SpecialVar(ch) =>
        match ch {
          '?' => buf.write_string(env.exit_code.to_string())
          _ => ()
        }
      _ => ()
    }
  }
  buf.to_string()
}

///|
fn resolve_path(cwd : String, path : String) -> String {
  if path.has_prefix("/") {
    path
  } else if cwd == "/" {
    "/" + path
  } else {
    cwd + "/" + path
  }
}

///|
fn shell_find_char(s : String, target : Char) -> Int? {
  let target_code = target.to_int().to_uint16()
  let mut idx = 0
  while idx < s.length() {
    if s.unsafe_get(idx) == target_code {
      return Some(idx)
    }
    idx += 1
  }
  None
}

///|
fn shell_text_slice(s : String, start : Int, end_ : Int) -> String {
  let buf = StringBuilder::new()
  let mut idx = start
  while idx < end_ && idx < s.length() {
    buf.write_char(Char::from_int(s.unsafe_get(idx).to_int()))
    idx += 1
  }
  buf.to_string()
}

///|
fn shell_array_slice(arr : Array[String], start : Int) -> Array[String] {
  let result : Array[String] = []
  let mut idx = start
  while idx < arr.length() {
    result.push(arr[idx])
    idx += 1
  }
  result
}

///|
fn shell_char_at(s : String, idx : Int) -> Char {
  Char::from_int(s.unsafe_get(idx).to_int())
}
