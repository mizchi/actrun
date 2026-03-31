///|
/// Shell lexer - tokenizes shell input
pub struct Lexer {
  input : String
  chars : Array[Char]
  mut pos : Int
  mut line : Int
  mut col : Int
}

///|
pub fn Lexer::new(input : String) -> Lexer {
  let chars : Array[Char] = []
  for c in input {
    chars.push(c)
  }
  { input, chars, pos: 0, line: 1, col: 1 }
}

///|
/// Peek current character
fn Lexer::peek(self : Lexer) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
/// Advance and return current character
fn Lexer::advance(self : Lexer) -> Char? {
  match self.peek() {
    Some(c) => {
      self.pos += 1
      if c == '\n' {
        self.line += 1
        self.col = 1
      } else {
        self.col += 1
      }
      Some(c)
    }
    None => None
  }
}

///|
/// Skip whitespace (but not newlines - they're significant)
fn Lexer::skip_whitespace(self : Lexer) -> Unit {
  while true {
    match self.peek() {
      Some(' ') | Some('\t') => {
        let _ = self.advance()
      }
      _ => break
    }
  }
}

///|
/// Skip comment (from # to end of line)
fn Lexer::skip_comment(self : Lexer) -> Unit {
  while true {
    match self.peek() {
      Some('\n') | None => break
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
/// Check if character is a word character
fn is_word_char(c : Char) -> Bool {
  not(is_meta_char(c)) && c != '\'' && c != '"' && c != '`'
}

///|
/// Check if character is a metacharacter
fn is_meta_char(c : Char) -> Bool {
  match c {
    '|'
    | '&'
    | ';'
    | '<'
    | '>'
    | '('
    | ')'
    | '{'
    | '}'
    | ' '
    | '\t'
    | '\n'
    | '#' => true
    _ => false
  }
}

///|
/// Read a single-quoted string
fn Lexer::read_single_quoted(self : Lexer) -> String raise LexError {
  let _ = self.advance() // consume opening '
  let buf = StringBuilder::new()
  while true {
    match self.advance() {
      Some('\'') => break
      Some(c) => buf.write_char(c)
      None => raise LexError::UnterminatedString(self.line, self.col)
    }
  }
  buf.to_string()
}

///|
/// Read a double-quoted string (returns raw content, expansion done later)
fn Lexer::read_double_quoted(self : Lexer) -> String raise LexError {
  let _ = self.advance() // consume opening "
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      Some('"') => {
        let _ = self.advance()
        break
      }
      Some('\\') => {
        let _ = self.advance()
        match self.advance() {
          Some(c) =>
            // In double quotes, only these escapes are special
            match c {
              '$' | '`' | '"' | '\\' | '\n' => buf.write_char(c)
              _ => {
                buf.write_char('\\')
                buf.write_char(c)
              }
            }
          None => raise LexError::UnterminatedString(self.line, self.col)
        }
      }
      Some(c) => {
        buf.write_char(c)
        let _ = self.advance()
      }
      None => raise LexError::UnterminatedString(self.line, self.col)
    }
  }
  buf.to_string()
}

///|
/// Read digits only
fn Lexer::read_digits(self : Lexer) -> String {
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      Some(c) if is_digit(c) => {
        buf.write_char(c)
        let _ = self.advance()
      }
      _ => break
    }
  }
  buf.to_string()
}

///|
/// Read a word (unquoted)
fn Lexer::read_word(self : Lexer) -> String {
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      Some('\\') => {
        let _ = self.advance()
        match self.advance() {
          Some('\n') => () // line continuation
          Some(c) => buf.write_char(c)
          None => ()
        }
      }
      Some(c) if is_word_char(c) => {
        buf.write_char(c)
        let _ = self.advance()
      }
      _ => break
    }
  }
  buf.to_string()
}

///|
/// Check if a word is a reserved word and return appropriate token
fn word_to_token(word : String, line : Int, col : Int) -> Token {
  let kind = match word {
    "if" => If
    "then" => Then
    "else" => Else
    "elif" => Elif
    "fi" => Fi
    "while" => While
    "until" => Until
    "for" => For
    "do" => Do
    "done" => Done
    "case" => Case
    "esac" => Esac
    "in" => In
    "function" => Function
    "{" => LBrace
    "}" => RBrace
    "!" => Bang
    _ => Word(word)
  }
  Token::new(kind, line, col)
}

///|
/// Get next token
pub fn Lexer::next_token(self : Lexer) -> Token raise LexError {
  self.skip_whitespace()
  let start_line = self.line
  let start_col = self.col
  match self.peek() {
    None => Token::eof(start_line, start_col)
    Some('#') => {
      self.skip_comment()
      self.next_token()
    }
    Some('\n') => {
      let _ = self.advance()
      Token::new(Newline, start_line, start_col)
    }
    Some('|') => {
      let _ = self.advance()
      match self.peek() {
        Some('|') => {
          let _ = self.advance()
          Token::new(Or, start_line, start_col)
        }
        Some('&') => {
          let _ = self.advance()
          Token::new(PipeAnd, start_line, start_col)
        }
        _ => Token::new(Pipe, start_line, start_col)
      }
    }
    Some('&') => {
      let _ = self.advance()
      match self.peek() {
        Some('&') => {
          let _ = self.advance()
          Token::new(And, start_line, start_col)
        }
        _ => Token::new(Amp, start_line, start_col)
      }
    }
    Some(';') => {
      let _ = self.advance()
      Token::new(Semi, start_line, start_col)
    }
    Some('<') => {
      let _ = self.advance()
      match self.peek() {
        Some('<') => {
          let _ = self.advance()
          Token::new(DLess, start_line, start_col)
        }
        Some('&') => {
          let _ = self.advance()
          Token::new(LessAnd, start_line, start_col)
        }
        Some('>') => {
          let _ = self.advance()
          Token::new(LessGreat, start_line, start_col)
        }
        _ => Token::new(Less, start_line, start_col)
      }
    }
    Some('>') => {
      let _ = self.advance()
      match self.peek() {
        Some('>') => {
          let _ = self.advance()
          Token::new(DGreat, start_line, start_col)
        }
        Some('&') => {
          let _ = self.advance()
          Token::new(GreatAnd, start_line, start_col)
        }
        Some('|') => {
          let _ = self.advance()
          Token::new(Clobber, start_line, start_col)
        }
        _ => Token::new(Great, start_line, start_col)
      }
    }
    Some('(') => {
      let _ = self.advance()
      Token::new(LParen, start_line, start_col)
    }
    Some(')') => {
      let _ = self.advance()
      Token::new(RParen, start_line, start_col)
    }
    Some('\'') => {
      let s = self.read_single_quoted()
      // Single-quoted strings become a word with the content
      Token::word("'" + s + "'", start_line, start_col)
    }
    Some('"') => {
      let s = self.read_double_quoted()
      // Double-quoted strings become a word with the content (marked)
      Token::word("\"" + s + "\"", start_line, start_col)
    }
    Some(c) if is_digit(c) => {
      // Check if this is an IO number (digit followed by < or >)
      let saved_pos = self.pos
      let saved_line = self.line
      let saved_col = self.col

      // Read all digits
      let num_str = self.read_digits()

      // Check if followed by redirection
      match self.peek() {
        Some('<') | Some('>') =>
          // This is an IO number
          match parse_int_str(num_str) {
            Some(n) => Token::new(IoNumber(n), start_line, start_col)
            None => {
              // Shouldn't happen but fall back to word
              self.pos = saved_pos
              self.line = saved_line
              self.col = saved_col
              let word = self.read_word()
              word_to_token(word, start_line, start_col)
            }
          }
        _ => {
          // Not an IO number, restore and read as word
          self.pos = saved_pos
          self.line = saved_line
          self.col = saved_col
          let word = self.read_word()
          if word.is_empty() {
            match self.advance() {
              Some(ch) =>
                raise LexError::UnexpectedChar(ch, start_line, start_col)
              None => Token::eof(start_line, start_col)
            }
          } else {
            match find_unquoted_equals(word) {
              Some(pos) if pos > 0 && is_valid_name(substring_str(word, 0, pos)) => {
                let name = substring_str(word, 0, pos)
                let value = substring_str(word, pos + 1, word.length())
                Token::new(Assignment(name, value), start_line, start_col)
              }
              _ => word_to_token(word, start_line, start_col)
            }
          }
        }
      }
    }
    Some(_) => {
      let word = self.read_word()
      if word.is_empty() {
        // Might be a character we don't handle
        match self.advance() {
          Some(c) => raise LexError::UnexpectedChar(c, start_line, start_col)
          None => Token::eof(start_line, start_col)
        }
      } else {
        // Check for assignment: NAME=VALUE
        match find_unquoted_equals(word) {
          Some(pos) if pos > 0 && is_valid_name(substring_str(word, 0, pos)) => {
            let name = substring_str(word, 0, pos)
            let value = substring_str(word, pos + 1, word.length())
            Token::new(Assignment(name, value), start_line, start_col)
          }
          _ => word_to_token(word, start_line, start_col)
        }
      }
    }
  }
}

///|
/// Tokenize entire input
pub fn Lexer::tokenize(self : Lexer) -> Array[Token] raise LexError {
  let tokens : Array[Token] = []
  while true {
    let tok = self.next_token()
    let is_eof = match tok.kind {
      Eof => true
      _ => false
    }
    tokens.push(tok)
    if is_eof {
      break
    }
  }
  tokens
}

///|
/// Lexer errors
pub suberror LexError {
  UnterminatedString(Int, Int)
  UnexpectedChar(Char, Int, Int)
  InvalidEscape(Char, Int, Int)
}

///|
pub impl Show for LexError with output(self, logger) {
  match self {
    UnterminatedString(line, col) =>
      logger.write_string("Unterminated string at \{line}:\{col}")
    UnexpectedChar(c, line, col) =>
      logger.write_string("Unexpected character '\{c}' at \{line}:\{col}")
    InvalidEscape(c, line, col) => {
      let escaped = c.to_string()
      logger.write_string("Invalid escape '\\")
      logger.write_string(escaped)
      logger.write_string("' at \{line}:\{col}")
    }
  }
}

// Helper functions

///|
fn find_unquoted_equals(s : String) -> Int? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  for i in 0..<chars.length() {
    if chars[i] == '=' {
      return Some(i)
    }
  }
  None
}

///|
fn is_valid_name(s : String) -> Bool {
  if s.is_empty() {
    return false
  }
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  // First char must be letter or underscore
  let first = chars[0]
  if not(is_alpha(first)) && first != '_' {
    return false
  }
  // Rest must be alphanumeric or underscore
  for i in 1..<chars.length() {
    let c = chars[i]
    if not(is_alnum(c)) && c != '_' {
      return false
    }
  }
  true
}

///|
fn is_alpha(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
}

///|
fn is_alnum(c : Char) -> Bool {
  is_alpha(c) || is_digit(c)
}

///|
fn is_digit(c : Char) -> Bool {
  let code = c.to_int()
  code >= 48 && code <= 57
}

///|
fn parse_int_str(s : String) -> Int? {
  if s.is_empty() {
    return None
  }
  let mut result = 0
  for c in s {
    let code = c.to_int()
    if code >= 48 && code <= 57 {
      result = result * 10 + (code - 48)
    } else {
      return None
    }
  }
  Some(result)
}

///|
fn substring_str(s : String, start : Int, end : Int) -> String {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let buf = StringBuilder::new()
  for i = start; i < end && i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}
