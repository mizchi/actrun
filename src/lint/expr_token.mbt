///|
priv enum TokenKind {
  StringLit(String)
  NumberLit(String)
  BoolLit(Bool)
  NullLit
  And
  Or
  Not
  Eq
  Neq
  Lt
  Le
  Gt
  Ge
  LParen
  RParen
  Dot
  LBracket
  RBracket
  Comma
  Star
  Ident(String)
  Eof
} derive(Eq, Show)

///|
priv struct Token {
  kind : TokenKind
  // offset and length are stored for future diagnostic use
  offset : Int
  length : Int
}

///|
priv struct Tokenizer {
  source : String
  mut pos : Int
  tokens : Array[Token]
  errors : Array[String]
}

///|
fn Tokenizer::new(source : String) -> Tokenizer {
  { source, pos: 0, tokens: [], errors: [] }
}

///|
fn Tokenizer::advance(self : Tokenizer) -> Unit {
  self.pos += 1
}

///|
fn Tokenizer::ch(self : Tokenizer) -> UInt16 {
  self.source.unsafe_get(self.pos)
}

///|
fn Tokenizer::ch_at(self : Tokenizer, idx : Int) -> UInt16 {
  self.source.unsafe_get(idx)
}

///|
fn Tokenizer::next_ch(self : Tokenizer) -> UInt16 {
  if self.pos < self.source.length() {
    self.source.unsafe_get(self.pos)
  } else {
    0
  }
}

///|
fn Tokenizer::emit(self : Tokenizer, kind : TokenKind, start : Int) -> Unit {
  self.tokens.push({ kind, offset: start, length: self.pos - start })
}

///|
fn is_digit(ch : UInt16) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn is_alpha(ch : UInt16) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}

///|
fn Tokenizer::skip_whitespace(self : Tokenizer) -> Unit {
  while self.pos < self.source.length() {
    let c = self.ch()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      self.pos += 1
    } else {
      break
    }
  }
}

///|
fn Tokenizer::read_string(self : Tokenizer) -> Unit {
  let start = self.pos
  self.advance() // skip opening quote
  let parts : Array[String] = []
  let mut seg_start = self.pos
  while self.pos < self.source.length() {
    let c = self.ch()
    if c == '\'' {
      if self.pos + 1 < self.source.length() && self.ch_at(self.pos + 1) == '\'' {
        parts.push(
          String::unsafe_substring(self.source, start=seg_start, end=self.pos),
        )
        parts.push("'")
        self.pos += 2
        seg_start = self.pos
      } else {
        parts.push(
          String::unsafe_substring(self.source, start=seg_start, end=self.pos),
        )
        self.advance()
        self.emit(StringLit(parts.join("")), start)
        return
      }
    } else {
      self.advance()
    }
  }
  parts.push(
    String::unsafe_substring(self.source, start=seg_start, end=self.pos),
  )
  self.errors.push("unterminated string literal at offset \{start}")
  self.emit(StringLit(parts.join("")), start)
}

///|
fn Tokenizer::read_number(self : Tokenizer) -> Unit {
  let start = self.pos
  let mut has_dot = false
  if self.pos < self.source.length() && self.ch() == '-' {
    self.advance()
  }
  while self.pos < self.source.length() {
    let c = self.ch()
    if is_digit(c) {
      self.advance()
    } else if c == '.' && not(has_dot) {
      if self.pos + 1 < self.source.length() &&
        is_digit(self.ch_at(self.pos + 1)) {
        has_dot = true
        self.advance()
      } else {
        break
      }
    } else {
      break
    }
  }
  let text = String::unsafe_substring(self.source, start~, end=self.pos)
  self.emit(NumberLit(text), start)
}

///|
fn Tokenizer::read_ident_or_keyword(self : Tokenizer) -> Unit {
  let start = self.pos
  while self.pos < self.source.length() {
    let c = self.ch()
    if is_alpha(c) || is_digit(c) || c == '_' || c == '-' {
      self.advance()
    } else {
      break
    }
  }
  let text = String::unsafe_substring(self.source, start~, end=self.pos)
  let kind : TokenKind = if text == "true" {
    BoolLit(true)
  } else if text == "false" {
    BoolLit(false)
  } else if text == "null" {
    NullLit
  } else {
    Ident(text)
  }
  self.emit(kind, start)
}

///|
fn Tokenizer::tokenize(self : Tokenizer) -> Unit {
  while self.pos < self.source.length() {
    self.skip_whitespace()
    if self.pos >= self.source.length() {
      break
    }
    let start = self.pos
    let c = self.ch()
    if c == '\'' {
      self.read_string()
    } else if c == '(' {
      self.advance()
      self.emit(LParen, start)
    } else if c == ')' {
      self.advance()
      self.emit(RParen, start)
    } else if c == '[' {
      self.advance()
      self.emit(LBracket, start)
    } else if c == ']' {
      self.advance()
      self.emit(RBracket, start)
    } else if c == '.' {
      self.advance()
      self.emit(Dot, start)
    } else if c == ',' {
      self.advance()
      self.emit(Comma, start)
    } else if c == '*' {
      self.advance()
      self.emit(Star, start)
    } else if c == '!' {
      self.advance()
      if self.next_ch() == '=' {
        self.advance()
        self.emit(Neq, start)
      } else {
        self.emit(Not, start)
      }
    } else if c == '=' {
      self.advance()
      if self.next_ch() == '=' {
        self.advance()
        self.emit(Eq, start)
      } else {
        self.errors.push("unexpected '=' at offset \{start}, expected '=='")
      }
    } else if c == '<' {
      self.advance()
      if self.next_ch() == '=' {
        self.advance()
        self.emit(Le, start)
      } else {
        self.emit(Lt, start)
      }
    } else if c == '>' {
      self.advance()
      if self.next_ch() == '=' {
        self.advance()
        self.emit(Ge, start)
      } else {
        self.emit(Gt, start)
      }
    } else if c == '&' {
      self.advance()
      if self.next_ch() == '&' {
        self.advance()
        self.emit(And, start)
      } else {
        self.errors.push("unexpected '&' at offset \{start}, expected '&&'")
      }
    } else if c == '|' {
      self.advance()
      if self.next_ch() == '|' {
        self.advance()
        self.emit(Or, start)
      } else {
        self.errors.push("unexpected '|' at offset \{start}, expected '||'")
      }
    } else if is_digit(c) ||
      (
        c == '-' &&
        self.pos + 1 < self.source.length() &&
        is_digit(self.ch_at(self.pos + 1))
      ) {
      self.read_number()
    } else if is_alpha(c) || c == '_' {
      self.read_ident_or_keyword()
    } else {
      self.errors.push("unexpected character at offset \{start}")
      self.advance()
    }
  }
  self.emit(Eof, self.pos)
}

///|
fn tokenize(source : String) -> (Array[Token], Array[String]) {
  let t = Tokenizer::new(source)
  t.tokenize()
  (t.tokens, t.errors)
}
