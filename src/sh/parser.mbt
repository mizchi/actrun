///|
/// Shell parser - parses tokens into AST
pub struct Parser {
  tokens : Array[Token]
  mut pos : Int
}

///|
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0 }
}

///|
/// Parse from string
pub fn parse(input : String) -> Command raise ParseError {
  let lexer = Lexer::new(input)
  let tokens = lexer.tokenize() catch {
    e => raise ParseError::LexError(e.to_string())
  }
  let parser = Parser::new(tokens)
  parser.parse_command()
}

///|
/// Parse into command list
pub fn parse_list(input : String) -> CommandList raise ParseError {
  let lexer = Lexer::new(input)
  let tokens = lexer.tokenize() catch {
    e => raise ParseError::LexError(e.to_string())
  }
  let parser = Parser::new(tokens)
  parser.parse_command_list()
}

///|
/// Peek current token
fn Parser::peek(self : Parser) -> Token {
  if self.pos < self.tokens.length() {
    self.tokens[self.pos]
  } else {
    Token::eof(0, 0)
  }
}

///|
/// Peek token kind
fn Parser::peek_kind(self : Parser) -> TokenKind {
  self.peek().kind
}

///|
/// Advance to next token
fn Parser::advance(self : Parser) -> Token {
  let tok = self.peek()
  if self.pos < self.tokens.length() {
    self.pos += 1
  }
  tok
}

///|
/// Expect a specific token kind
fn Parser::expect(
  self : Parser,
  expected : TokenKind,
) -> Token raise ParseError {
  let tok = self.peek()
  if token_kind_matches(tok.kind, expected) {
    self.advance()
  } else {
    raise ParseError::UnexpectedToken(
      tok.kind.to_string(),
      expected.to_string(),
      tok.line,
      tok.col,
    )
  }
}

///|
/// Skip newlines
fn Parser::skip_newlines(self : Parser) -> Unit {
  while true {
    match self.peek_kind() {
      Newline => {
        let _ = self.advance()
      }
      _ => break
    }
  }
}

///|
/// Parse complete command
pub fn Parser::parse_command(self : Parser) -> Command raise ParseError {
  self.skip_newlines()
  let list = self.parse_command_list()
  List(list)
}

///|
/// Parse command list: pipeline ((; | & | && | ||) pipeline)*
pub fn Parser::parse_command_list(
  self : Parser,
) -> CommandList raise ParseError {
  self.skip_newlines()
  let first = self.parse_pipeline()
  let rest : Array[(ListOp, Pipeline)] = []
  while true {
    self.skip_newlines()
    let op = match self.peek_kind() {
      Semi => {
        let _ = self.advance()
        Some(Seq)
      }
      Amp => {
        let _ = self.advance()
        Some(Background)
      }
      And => {
        let _ = self.advance()
        Some(ListOp::And)
      }
      Or => {
        let _ = self.advance()
        Some(ListOp::Or)
      }
      _ => None
    }
    match op {
      Some(o) => {
        self.skip_newlines()
        // Check if there's another pipeline
        if self.is_command_start() {
          let next = self.parse_pipeline()
          rest.push((o, next))
        } else {
          // Trailing separator, just record it if it's background
          if o is Background {
            // Mark the last command as background somehow
            // For now, just break
          }
          break
        }
      }
      None => break
    }
  }
  CommandList::new(first, rest)
}

///|
/// Parse pipeline: [!] command (| command)*
pub fn Parser::parse_pipeline(self : Parser) -> Pipeline raise ParseError {
  let bang = match self.peek_kind() {
    Bang => {
      let _ = self.advance()
      true
    }
    _ => false
  }
  let commands : Array[Command] = []
  let first = self.parse_single_command()
  commands.push(first)
  while true {
    match self.peek_kind() {
      Pipe | PipeAnd => {
        let _ = self.advance()
        self.skip_newlines()
        let cmd = self.parse_single_command()
        commands.push(cmd)
      }
      _ => break
    }
  }
  let pipeline = Pipeline::new(commands)
  if bang {
    pipeline.with_bang()
  } else {
    pipeline
  }
}

///|
/// Parse a single command (simple, compound, or function)
pub fn Parser::parse_single_command(self : Parser) -> Command raise ParseError {
  self.skip_newlines()
  match self.peek_kind() {
    LParen => self.parse_subshell()
    LBrace => self.parse_brace_group()
    If => self.parse_if()
    While => self.parse_while()
    Until => self.parse_until()
    For => self.parse_for()
    Case => self.parse_case()
    Function => self.parse_function()
    _ => self.parse_simple_command()
  }
}

///|
/// Parse simple command: [assignments] [words] [redirections]
pub fn Parser::parse_simple_command(self : Parser) -> Command raise ParseError {
  let assigns : Array[(String, Word)] = []
  let words : Array[Word] = []
  let redirects : Array[Redirect] = []

  // Parse leading assignments
  while true {
    match self.peek_kind() {
      Assignment(name, value) => {
        let _ = self.advance()
        assigns.push((name, Word::literal(value)))
      }
      _ => break
    }
  }

  // Parse words and redirections
  while true {
    // Check for redirection
    if self.peek().is_redirect() {
      let redir = self.parse_redirect()
      redirects.push(redir)
      continue
    }

    // Check for word
    match self.peek_kind() {
      Word(s) => {
        let _ = self.advance()
        words.push(parse_word(s))
      }
      _ => break
    }
  }
  let cmd = SimpleCommand::new(words)
    .with_assigns(assigns)
    .with_redirects(redirects)
  Simple(cmd)
}

///|
/// Parse redirection
fn Parser::parse_redirect(self : Parser) -> Redirect raise ParseError {
  let tok = self.advance()
  let kind = match tok.kind {
    Less => Input
    Great => Output
    DGreat => Append
    DLess => HereDoc
    LessAnd => InputDup
    GreatAnd => OutputDup
    LessGreat => ReadWrite
    Clobber => RedirectKind::Clobber
    _ =>
      raise ParseError::UnexpectedToken(
        tok.kind.to_string(),
        "redirection".to_string(),
        tok.line,
        tok.col,
      )
  }

  // Get target word
  let target = match self.peek_kind() {
    Word(s) => {
      let _ = self.advance()
      parse_word(s)
    }
    _ => raise ParseError::ExpectedWord(self.peek().line, self.peek().col)
  }
  { kind, fd: None, target }
}

///|
/// Parse subshell: ( list )
fn Parser::parse_subshell(self : Parser) -> Command raise ParseError {
  let _ = self.expect(LParen)
  self.skip_newlines()
  let list = self.parse_command_list()
  self.skip_newlines()
  let _ = self.expect(RParen)
  Subshell(list)
}

///|
/// Parse brace group: { list; }
fn Parser::parse_brace_group(self : Parser) -> Command raise ParseError {
  let _ = self.expect(LBrace)
  self.skip_newlines()
  let list = self.parse_command_list()
  self.skip_newlines()
  let _ = self.expect(RBrace)
  BraceGroup(list)
}

///|
/// Parse if: if list then list [elif list then list]* [else list] fi
fn Parser::parse_if(self : Parser) -> Command raise ParseError {
  let _ = self.expect(If)
  self.skip_newlines()
  let condition = self.parse_command_list()
  self.skip_newlines()
  let _ = self.expect(Then)
  self.skip_newlines()
  let then_body = self.parse_command_list()
  let elif_parts : Array[(CommandList, CommandList)] = []
  while true {
    self.skip_newlines()
    match self.peek_kind() {
      Elif => {
        let _ = self.advance()
        self.skip_newlines()
        let elif_cond = self.parse_command_list()
        self.skip_newlines()
        let _ = self.expect(Then)
        self.skip_newlines()
        let elif_body = self.parse_command_list()
        elif_parts.push((elif_cond, elif_body))
      }
      _ => break
    }
  }
  self.skip_newlines()
  let else_body = match self.peek_kind() {
    Else => {
      let _ = self.advance()
      self.skip_newlines()
      Some(self.parse_command_list())
    }
    _ => None
  }
  self.skip_newlines()
  let _ = self.expect(Fi)
  IfCmd({ condition, then_body, elif_parts, else_body })
}

///|
/// Parse while: while list do list done
fn Parser::parse_while(self : Parser) -> Command raise ParseError {
  let _ = self.expect(While)
  self.skip_newlines()
  let condition = self.parse_command_list()
  self.skip_newlines()
  let _ = self.expect(Do)
  self.skip_newlines()
  let body = self.parse_command_list()
  self.skip_newlines()
  let _ = self.expect(Done)
  WhileCmd(WhileClause::while_(condition, body))
}

///|
/// Parse until: until list do list done
fn Parser::parse_until(self : Parser) -> Command raise ParseError {
  let _ = self.expect(Until)
  self.skip_newlines()
  let condition = self.parse_command_list()
  self.skip_newlines()
  let _ = self.expect(Do)
  self.skip_newlines()
  let body = self.parse_command_list()
  self.skip_newlines()
  let _ = self.expect(Done)
  WhileCmd(WhileClause::until_(condition, body))
}

///|
/// Parse for: for name [in words] do list done
fn Parser::parse_for(self : Parser) -> Command raise ParseError {
  let _ = self.expect(For)
  self.skip_newlines()
  let varname = match self.peek_kind() {
    Word(s) => {
      let _ = self.advance()
      s
    }
    _ => raise ParseError::ExpectedWord(self.peek().line, self.peek().col)
  }
  self.skip_newlines()
  let words : Array[Word]? = match self.peek_kind() {
    In => {
      let _ = self.advance()
      let w : Array[Word] = []
      while true {
        match self.peek_kind() {
          Word(s) => {
            let _ = self.advance()
            w.push(parse_word(s))
          }
          _ => break
        }
      }
      Some(w)
    }
    _ => None
  }

  // Skip ; or newline before do
  while true {
    match self.peek_kind() {
      Semi | Newline => {
        let _ = self.advance()
      }
      _ => break
    }
  }
  let _ = self.expect(Do)
  self.skip_newlines()
  let body = self.parse_command_list()
  self.skip_newlines()
  let _ = self.expect(Done)
  ForCmd(ForClause::new(varname, words, body))
}

///|
/// Parse case: case word in [pattern) list ;;]* esac
fn Parser::parse_case(self : Parser) -> Command raise ParseError {
  let _ = self.expect(Case)
  self.skip_newlines()
  let word = match self.peek_kind() {
    Word(s) => {
      let _ = self.advance()
      parse_word(s)
    }
    _ => raise ParseError::ExpectedWord(self.peek().line, self.peek().col)
  }
  self.skip_newlines()
  let _ = self.expect(In)
  self.skip_newlines()
  let items : Array[CaseItem] = []
  // Simplified: just expect esac for now
  // Full implementation would parse pattern) list ;; pairs

  let _ = self.expect(Esac)
  CaseCmd(CaseClause::new(word, items))
}

///|
/// Parse function: function name { list } or name() { list }
fn Parser::parse_function(self : Parser) -> Command raise ParseError {
  let _ = self.expect(Function)
  self.skip_newlines()
  let name = match self.peek_kind() {
    Word(s) => {
      let _ = self.advance()
      s
    }
    _ => raise ParseError::ExpectedWord(self.peek().line, self.peek().col)
  }
  self.skip_newlines()
  let body = self.parse_single_command()
  FuncDef(FunctionDef::new(name, body))
}

///|
/// Check if current token can start a command
fn Parser::is_command_start(self : Parser) -> Bool {
  match self.peek_kind() {
    Word(_)
    | Assignment(_, _)
    | LParen
    | LBrace
    | If
    | While
    | Until
    | For
    | Case
    | Function
    | Bang => true
    _ => false
  }
}

///|
/// Parse a word string into Word AST
fn parse_word(s : String) -> Word {
  parse_word_parts(s)
}

///|
/// Check if token kinds match (for expect)
fn token_kind_matches(actual : TokenKind, expected : TokenKind) -> Bool {
  match (actual, expected) {
    (Word(_), Word(_)) => true
    (Assignment(_, _), Assignment(_, _)) => true
    (Pipe, Pipe) => true
    (PipeAnd, PipeAnd) => true
    (And, And) => true
    (Or, Or) => true
    (Semi, Semi) => true
    (Amp, Amp) => true
    (Newline, Newline) => true
    (Less, Less) => true
    (Great, Great) => true
    (DLess, DLess) => true
    (DGreat, DGreat) => true
    (LessAnd, LessAnd) => true
    (GreatAnd, GreatAnd) => true
    (LessGreat, LessGreat) => true
    (Clobber, Clobber) => true
    (LParen, LParen) => true
    (RParen, RParen) => true
    (LBrace, LBrace) => true
    (RBrace, RBrace) => true
    (If, If) => true
    (Then, Then) => true
    (Else, Else) => true
    (Elif, Elif) => true
    (Fi, Fi) => true
    (While, While) => true
    (Until, Until) => true
    (For, For) => true
    (Do, Do) => true
    (Done, Done) => true
    (Case, Case) => true
    (Esac, Esac) => true
    (In, In) => true
    (Function, Function) => true
    (Bang, Bang) => true
    (Eof, Eof) => true
    _ => false
  }
}

///|
/// Parser errors
pub suberror ParseError {
  LexError(String)
  UnexpectedToken(String, String, Int, Int) // got, expected, line, col
  ExpectedWord(Int, Int)
  UnexpectedEof
}

///|
pub impl Show for ParseError with output(self, logger) {
  match self {
    LexError(msg) => logger.write_string("Lex error: \{msg}")
    UnexpectedToken(got, expected, line, col) =>
      logger.write_string(
        "Unexpected token '\{got}', expected '\{expected}' at \{line}:\{col}",
      )
    ExpectedWord(line, col) =>
      logger.write_string("Expected word at \{line}:\{col}")
    UnexpectedEof => logger.write_string("Unexpected end of input")
  }
}
