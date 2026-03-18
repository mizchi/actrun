///|
pub enum Expr {
  Literal(ExprLiteral)
  Ident(String)
  PropertyAccess(Expr, String)
  IndexAccess(Expr, Expr)
  UnaryOp(UnaryOp, Expr)
  BinaryOp(BinaryOp, Expr, Expr)
  FunctionCall(String, Array[Expr])
} derive(Eq, Show)

///|
pub enum ExprLiteral {
  LitString(String)
  LitNumber(String)
  LitBool(Bool)
  LitNull
} derive(Eq, Show)

///|
pub enum UnaryOp {
  OpNot
} derive(Eq, Show)

///|
pub enum BinaryOp {
  OpAnd
  OpOr
  OpEq
  OpNeq
  OpLt
  OpLe
  OpGt
  OpGe
} derive(Eq, Show)
