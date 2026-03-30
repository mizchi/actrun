///| Shell Abstract Syntax Tree

///|
/// Word - a single shell word (may contain expansions)
pub enum WordPart {
  Literal(String) // Plain text
  SingleQuoted(String) // 'text' - no expansion
  DoubleQuoted(Array[WordPart]) // "text" - variable expansion
  Variable(String) // $VAR or ${VAR}
  SpecialVar(Char) // $?, $$, $!, $0-$9, $@, $*, $#
  CommandSub(Command) // $(command)
  ArithSub(String) // $((expr))
  Glob(String) // pattern with *, ?, [...]
}

///|
pub struct Word {
  parts : Array[WordPart]
}

///|
pub fn Word::literal(s : String) -> Word {
  { parts: [Literal(s)] }
}

///|
pub fn Word::new(parts : Array[WordPart]) -> Word {
  { parts, }
}

///|
pub fn Word::is_simple(self : Word) -> Bool {
  if self.parts.length() != 1 {
    return false
  }
  match self.parts[0] {
    Literal(_) => true
    _ => false
  }
}

///|
pub fn Word::get_literal(self : Word) -> String? {
  if self.parts.length() == 1 {
    match self.parts[0] {
      Literal(s) => Some(s)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Redirection
pub enum RedirectKind {
  Input // <
  Output // >
  Append // >>
  HereDoc // <<
  HereString // <<<
  InputDup // <&
  OutputDup // >&
  ReadWrite // <>
  Clobber // >|
}

///|
pub struct Redirect {
  kind : RedirectKind
  fd : Int? // file descriptor (default: 0 for input, 1 for output)
  target : Word // file or fd number
}

///|
pub fn Redirect::input(target : Word) -> Redirect {
  { kind: Input, fd: None, target }
}

///|
pub fn Redirect::output(target : Word) -> Redirect {
  { kind: Output, fd: None, target }
}

///|
pub fn Redirect::append(target : Word) -> Redirect {
  { kind: Append, fd: None, target }
}

///|
pub fn Redirect::with_fd(self : Redirect, fd : Int) -> Redirect {
  { kind: self.kind, fd: Some(fd), target: self.target }
}

///|
/// Simple command: cmd arg1 arg2 ...
pub struct SimpleCommand {
  assigns : Array[(String, Word)] // VAR=value before command
  words : Array[Word] // command and arguments
  redirects : Array[Redirect]
}

///|
pub fn SimpleCommand::new(words : Array[Word]) -> SimpleCommand {
  { assigns: [], words, redirects: [] }
}

///|
pub fn SimpleCommand::with_assigns(
  self : SimpleCommand,
  assigns : Array[(String, Word)],
) -> SimpleCommand {
  { assigns, words: self.words, redirects: self.redirects }
}

///|
pub fn SimpleCommand::with_redirects(
  self : SimpleCommand,
  redirects : Array[Redirect],
) -> SimpleCommand {
  { assigns: self.assigns, words: self.words, redirects }
}

///|
/// Pipeline: cmd1 | cmd2 | cmd3
pub struct Pipeline {
  commands : Array[Command]
  bang : Bool // ! prefix (negate exit status)
}

///|
pub fn Pipeline::new(commands : Array[Command]) -> Pipeline {
  { commands, bang: false }
}

///|
pub fn Pipeline::with_bang(self : Pipeline) -> Pipeline {
  { commands: self.commands, bang: true }
}

///|
/// List operators
pub enum ListOp {
  Seq // ; or newline
  And // &&
  Or // ||
  Background // &
}

///|
/// Command list: cmd1 && cmd2 || cmd3
pub struct CommandList {
  first : Pipeline
  rest : Array[(ListOp, Pipeline)]
}

///|
pub fn CommandList::single(pipeline : Pipeline) -> CommandList {
  { first: pipeline, rest: [] }
}

///|
pub fn CommandList::new(
  first : Pipeline,
  rest : Array[(ListOp, Pipeline)],
) -> CommandList {
  { first, rest }
}

///|
/// If statement
pub struct IfClause {
  condition : CommandList
  then_body : CommandList
  elif_parts : Array[(CommandList, CommandList)] // (condition, body)
  else_body : CommandList?
}

///|
pub fn IfClause::new(
  condition : CommandList,
  then_body : CommandList,
) -> IfClause {
  { condition, then_body, elif_parts: [], else_body: None }
}

///|
/// While/Until loop
pub struct WhileClause {
  condition : CommandList
  body : CommandList
  is_until : Bool
}

///|
pub fn WhileClause::while_(
  condition : CommandList,
  body : CommandList,
) -> WhileClause {
  { condition, body, is_until: false }
}

///|
pub fn WhileClause::until_(
  condition : CommandList,
  body : CommandList,
) -> WhileClause {
  { condition, body, is_until: true }
}

///|
/// For loop
pub struct ForClause {
  varname : String
  words : Array[Word]? // None means "$@"
  body : CommandList
}

///|
pub fn ForClause::new(
  varname : String,
  words : Array[Word]?,
  body : CommandList,
) -> ForClause {
  { varname, words, body }
}

///|
/// Case clause
pub struct CaseItem {
  patterns : Array[Word]
  body : CommandList?
}

///|
pub struct CaseClause {
  word : Word
  items : Array[CaseItem]
}

///|
pub fn CaseClause::new(word : Word, items : Array[CaseItem]) -> CaseClause {
  { word, items }
}

///|
/// Function definition
pub struct FunctionDef {
  name : String
  body : Command
}

///|
pub fn FunctionDef::new(name : String, body : Command) -> FunctionDef {
  { name, body }
}

///|
/// Command - the main AST node
pub enum Command {
  Simple(SimpleCommand)
  Pipeline(Pipeline)
  List(CommandList)
  Subshell(CommandList) // ( list )
  BraceGroup(CommandList) // { list; }
  IfCmd(IfClause)
  WhileCmd(WhileClause)
  ForCmd(ForClause)
  CaseCmd(CaseClause)
  FuncDef(FunctionDef)
}

///|
pub fn Command::simple(words : Array[Word]) -> Command {
  Simple(SimpleCommand::new(words))
}

///|
pub fn Command::simple_str(words : Array[String]) -> Command {
  let w : Array[Word] = []
  for s in words {
    w.push(Word::literal(s))
  }
  Simple(SimpleCommand::new(w))
}
