///|
test "nix_wrap_command: NixNone passes through" {
  let (cmd, args) = nix_wrap_command(NixNone, "bash", ["--norc", "script.sh"])
  inspect(cmd, content="bash")
  inspect(
    args,
    content=(
      #|["--norc", "script.sh"]
    ),
  )
}

///|
test "nix_wrap_command: Flake wraps with nix develop" {
  let (cmd, args) = nix_wrap_command(Flake, "bash", ["--norc", "script.sh"])
  inspect(cmd, content="nix")
  inspect(
    args,
    content=(
      #|["develop", "--command", "bash", "--norc", "script.sh"]
    ),
  )
}

///|
test "nix_wrap_command: Shell wraps with nix-shell --run" {
  let (cmd, args) = nix_wrap_command(Shell, "bash", ["--norc", "script.sh"])
  inspect(cmd, content="nix-shell")
  inspect(args[0], content="--run")
}

///|
test "nix_wrap_command: Packages wraps with nix-shell -p" {
  let (cmd, args) = nix_wrap_command(
    Packages(["python312", "nodejs"]),
    "bash",
    ["script.sh"],
  )
  inspect(cmd, content="nix-shell")
  inspect(
    args,
    content=(
      #|["-p", "python312", "-p", "nodejs", "--run", "'bash' 'script.sh'"]
    ),
  )
}
