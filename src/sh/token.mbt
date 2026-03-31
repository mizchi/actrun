///| Shell token types

///|
/// Token types for shell lexer
pub enum TokenKind {
  // Literals
  Word(String) // command name, argument, etc.
  IoNumber(Int) // file descriptor number before redirection

  // Operators
  Pipe // |
  PipeAnd // |&  (pipe stdout and stderr)
  And // &&
  Or // ||
  Semi // ;
  Amp // &
  Newline // \n (significant in shell)

  // Redirections
  Less // <
  Great // >
  DLess // <<  (here-doc)
  DGreat // >>  (append)
  LessAnd // <&
  GreatAnd // >&
  LessGreat // <>  (open for read/write)
  Clobber // >|  (force overwrite)

  // Grouping
  LParen // (
  RParen // )
  LBrace // {
  RBrace // }

  // Reserved words
  If
  Then
  Else
  Elif
  Fi
  While
  Until
  For
  Do
  Done
  Case
  Esac
  In
  Function

  // Special
  Bang // ! (negation)

  // Assignment
  Assignment(String, String) // name=value

  // End of input
  Eof
}

///|
/// Token with position information
pub struct Token {
  kind : TokenKind
  line : Int
  col : Int
}

///|
pub fn Token::new(kind : TokenKind, line : Int, col : Int) -> Token {
  { kind, line, col }
}

///|
pub fn Token::word(s : String, line : Int, col : Int) -> Token {
  { kind: Word(s), line, col }
}

///|
pub fn Token::eof(line : Int, col : Int) -> Token {
  { kind: Eof, line, col }
}

///|
/// Check if token is a word
pub fn Token::is_word(self : Token) -> Bool {
  match self.kind {
    Word(_) => true
    _ => false
  }
}

///|
/// Get word value if token is a word
pub fn Token::get_word(self : Token) -> String? {
  match self.kind {
    Word(s) => Some(s)
    _ => None
  }
}

///|
/// Check if token is a reserved word
pub fn Token::is_reserved(self : Token) -> Bool {
  match self.kind {
    If
    | Then
    | Else
    | Elif
    | Fi
    | While
    | Until
    | For
    | Do
    | Done
    | Case
    | Esac
    | In
    | Function => true
    _ => false
  }
}

///|
/// Check if token is a separator
pub fn Token::is_separator(self : Token) -> Bool {
  match self.kind {
    Semi | Amp | Newline | Eof => true
    _ => false
  }
}

///|
/// Check if token starts a redirection
pub fn Token::is_redirect(self : Token) -> Bool {
  match self.kind {
    Less | Great | DLess | DGreat | LessAnd | GreatAnd | LessGreat | Clobber =>
      true
    _ => false
  }
}

///|
pub impl Show for TokenKind with output(self, logger) {
  match self {
    Word(s) => logger.write_string("Word(\{s})")
    IoNumber(n) => logger.write_string("IoNumber(\{n})")
    Pipe => logger.write_string("Pipe")
    PipeAnd => logger.write_string("PipeAnd")
    And => logger.write_string("And")
    Or => logger.write_string("Or")
    Semi => logger.write_string("Semi")
    Amp => logger.write_string("Amp")
    Newline => logger.write_string("Newline")
    Less => logger.write_string("Less")
    Great => logger.write_string("Great")
    DLess => logger.write_string("DLess")
    DGreat => logger.write_string("DGreat")
    LessAnd => logger.write_string("LessAnd")
    GreatAnd => logger.write_string("GreatAnd")
    LessGreat => logger.write_string("LessGreat")
    Clobber => logger.write_string("Clobber")
    LParen => logger.write_string("LParen")
    RParen => logger.write_string("RParen")
    LBrace => logger.write_string("LBrace")
    RBrace => logger.write_string("RBrace")
    If => logger.write_string("If")
    Then => logger.write_string("Then")
    Else => logger.write_string("Else")
    Elif => logger.write_string("Elif")
    Fi => logger.write_string("Fi")
    While => logger.write_string("While")
    Until => logger.write_string("Until")
    For => logger.write_string("For")
    Do => logger.write_string("Do")
    Done => logger.write_string("Done")
    Case => logger.write_string("Case")
    Esac => logger.write_string("Esac")
    In => logger.write_string("In")
    Function => logger.write_string("Function")
    Bang => logger.write_string("Bang")
    Assignment(n, v) => logger.write_string("Assignment(\{n}=\{v})")
    Eof => logger.write_string("Eof")
  }
}
