///|
priv struct Parser {
  tokens : Array[Token]
  mut pos : Int
  errors : Array[String]
}

///|
fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0, errors: [] }
}

///|
fn Parser::peek(self : Parser) -> TokenKind {
  if self.pos >= self.tokens.length() {
    Eof
  } else {
    self.tokens[self.pos].kind
  }
}

///|
fn Parser::advance(self : Parser) -> Token {
  let tok = self.tokens[self.pos]
  self.pos += 1
  tok
}

///|
fn Parser::expect(self : Parser, expected : TokenKind) -> Bool {
  if self.peek() == expected {
    self.pos += 1
    true
  } else {
    self.errors.push("expected \{expected}, got \{self.peek()}")
    false
  }
}

///|
/// Parse entry: expression
fn Parser::parse_expr(self : Parser) -> Expr {
  self.parse_or()
}

///|
/// Lowest precedence: ||
fn Parser::parse_or(self : Parser) -> Expr {
  let mut left = self.parse_and()
  while self.peek() == Or {
    ignore(self.advance())
    let right = self.parse_and()
    left = BinaryOp(OpOr, left, right)
  }
  left
}

///|
/// &&
fn Parser::parse_and(self : Parser) -> Expr {
  let mut left = self.parse_comparison()
  while self.peek() == And {
    ignore(self.advance())
    let right = self.parse_comparison()
    left = BinaryOp(OpAnd, left, right)
  }
  left
}

///|
/// == != < <= > >=
fn Parser::parse_comparison(self : Parser) -> Expr {
  let mut left = self.parse_unary()
  while true {
    let op : BinaryOp? = match self.peek() {
      Eq => Some(OpEq)
      Neq => Some(OpNeq)
      Lt => Some(OpLt)
      Le => Some(OpLe)
      Gt => Some(OpGt)
      Ge => Some(OpGe)
      _ => None
    }
    match op {
      Some(op) => {
        ignore(self.advance())
        let right = self.parse_unary()
        left = BinaryOp(op, left, right)
      }
      None => break
    }
  }
  left
}

///|
/// ! (unary not)
fn Parser::parse_unary(self : Parser) -> Expr {
  if self.peek() == Not {
    ignore(self.advance())
    let operand = self.parse_unary()
    UnaryOp(OpNot, operand)
  } else {
    self.parse_postfix()
  }
}

///|
/// Postfix: . [] ()
fn Parser::parse_postfix(self : Parser) -> Expr {
  let mut expr = self.parse_primary()
  while true {
    match self.peek() {
      Dot => {
        ignore(self.advance())
        match self.peek() {
          Ident(name) => {
            ignore(self.advance())
            expr = PropertyAccess(expr, name)
          }
          Star => {
            ignore(self.advance())
            expr = PropertyAccess(expr, "*")
          }
          _ => {
            self.errors.push("expected property name after '.'")
            break
          }
        }
      }
      LBracket => {
        ignore(self.advance())
        let index = self.parse_expr()
        let _ = self.expect(RBracket)
        expr = IndexAccess(expr, index)
      }
      _ => break
    }
  }
  expr
}

///|
/// Primary: literals, idents, function calls, grouped expressions
fn Parser::parse_primary(self : Parser) -> Expr {
  match self.peek() {
    StringLit(s) => {
      ignore(self.advance())
      Literal(LitString(s))
    }
    NumberLit(n) => {
      ignore(self.advance())
      Literal(LitNumber(n))
    }
    BoolLit(b) => {
      ignore(self.advance())
      Literal(LitBool(b))
    }
    NullLit => {
      ignore(self.advance())
      Literal(LitNull)
    }
    Ident(name) => {
      ignore(self.advance())
      if self.peek() == LParen {
        ignore(self.advance())
        let args : Array[Expr] = []
        if self.peek() != RParen {
          args.push(self.parse_expr())
          while self.peek() == Comma {
            ignore(self.advance())
            args.push(self.parse_expr())
          }
        }
        let _ = self.expect(RParen)
        FunctionCall(name, args)
      } else {
        Ident(name)
      }
    }
    LParen => {
      ignore(self.advance())
      let inner = self.parse_expr()
      let _ = self.expect(RParen)
      inner
    }
    _ => {
      let tok = self.peek()
      self.errors.push("unexpected token: \{tok}")
      if self.pos < self.tokens.length() {
        ignore(self.advance())
      }
      Literal(LitNull)
    }
  }
}

///|
pub fn parse_expression(source : String) -> (Expr, Array[String]) {
  let (tokens, tok_errors) = tokenize(source)
  let parser = Parser::new(tokens)
  let expr = parser.parse_expr()
  // check for trailing tokens
  if parser.peek() != Eof {
    parser.errors.push("unexpected trailing tokens")
  }
  let all_errors : Array[String] = []
  for e in tok_errors {
    all_errors.push(e)
  }
  for e in parser.errors {
    all_errors.push(e)
  }
  (expr, all_errors)
}
