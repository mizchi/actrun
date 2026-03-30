///|
test "shell_exec: echo" {
  let env = new_shell_env({})
  let code = shell_exec(env, "echo hello world")
  inspect(code, content="0")
  inspect(shell_stdout(env), content="hello world\n")
}

///|
test "shell_exec: variable expansion" {
  let env = new_shell_env({ "NAME": "actrun" })
  ignore(shell_exec(env, "echo hello $NAME"))
  inspect(shell_stdout(env), content="hello actrun\n")
}

///|
test "shell_exec: printf" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "printf '%s|%s' foo bar"))
  inspect(shell_stdout(env), content="foo|bar")
}

///|
test "shell_exec: variable assignment" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "X=hello; echo $X"))
  inspect(shell_stdout(env), content="hello\n")
}

///|
test "shell_exec: if true" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "if true; then echo yes; else echo no; fi"))
  inspect(shell_stdout(env), content="yes\n")
}

///|
test "shell_exec: if false" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "if false; then echo yes; else echo no; fi"))
  inspect(shell_stdout(env), content="no\n")
}

///|
test "shell_exec: for loop" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "for x in a b c; do echo $x; done"))
  inspect(shell_stdout(env), content="a\nb\nc\n")
}

///|
test "shell_exec: && operator" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "true && echo yes"))
  inspect(shell_stdout(env), content="yes\n")
}

///|
test "shell_exec: || operator" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "false || echo fallback"))
  inspect(shell_stdout(env), content="fallback\n")
}

///|
test "shell_exec: && short-circuit" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "false && echo no"))
  inspect(shell_stdout(env), content="")
}

///|
test "shell_exec: exit code" {
  let env = new_shell_env({})
  let code = shell_exec(env, "exit 42")
  inspect(code, content="42")
}

///|
test "shell_exec: test -z empty" {
  let env = new_shell_env({})
  let code = shell_exec(env, "test -z ''")
  inspect(code, content="0")
}

///|
test "shell_exec: test -z non-empty" {
  let env = new_shell_env({})
  let code = shell_exec(env, "test -z 'hello'")
  inspect(code, content="1")
}

///|
test "shell_exec: test string equality" {
  let env = new_shell_env({})
  let code = shell_exec(env, "test hello = hello")
  inspect(code, content="0")
}

///|
test "shell_exec: export sets variable" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "FOO=bar; export FOO; echo $FOO"))
  inspect(shell_stdout(env), content="bar\n")
}

///|
test "shell_exec: redirect to file" {
  let files : Map[String, String] = {}
  let env = new_shell_env({}, write_file=fn(path, content, append) {
    if append {
      files[path] = files.get(path).unwrap_or("") + content
    } else {
      files[path] = content
    }
    true
  })
  ignore(shell_exec(env, "echo hello > /tmp/out.txt"))
  inspect(files.get("/tmp/out.txt").unwrap_or(""), content="hello\n")
}

///|
test "shell_exec: append redirect" {
  let files : Map[String, String] = {}
  let env = new_shell_env({}, write_file=fn(path, content, append) {
    if append {
      files[path] = files.get(path).unwrap_or("") + content
    } else {
      files[path] = content
    }
    true
  })
  ignore(
    shell_exec(env, "echo line1 >> /tmp/out.txt; echo line2 >> /tmp/out.txt"),
  )
  inspect(files.get("/tmp/out.txt").unwrap_or(""), content="line1\nline2\n")
}

///|
test "shell_exec: cat reads file" {
  let env = new_shell_env({}, read_file=fn(path) {
    if path == "/data.txt" {
      Some("content")
    } else {
      None
    }
  })
  ignore(shell_exec(env, "cat /data.txt"))
  inspect(shell_stdout(env), content="content")
}

///|
test "shell_exec: github output pattern" {
  let files : Map[String, String] = {}
  let env = new_shell_env({ "GITHUB_OUTPUT": "/tmp/output" }, write_file=fn(
    path,
    content,
    append,
  ) {
    if append {
      files[path] = files.get(path).unwrap_or("") + content
    } else {
      files[path] = content
    }
    true
  })
  ignore(shell_exec(env, "echo 'result=hello' >> \"$GITHUB_OUTPUT\""))
  inspect(files.get("/tmp/output").unwrap_or(""), content="result=hello\n")
}

///|
test "shell_exec: command not found" {
  let env = new_shell_env({})
  let code = shell_exec(env, "nonexistent_command")
  inspect(code, content="127")
  inspect(shell_stderr(env).contains("command not found"), content="true")
}

///|
test "shell_exec: while loop" {
  let env = new_shell_env({})
  ignore(shell_exec(env, "X=0; while test $X = 0; do echo loop; X=1; done"))
  inspect(shell_stdout(env), content="loop\n")
}
