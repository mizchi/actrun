///|
pub enum Expr {
  Literal(ExprLiteral)
  Ident(String)
  PropertyAccess(Expr, String)
  IndexAccess(Expr, Expr)
  UnaryOp(UnaryOp, Expr)
  BinaryOp(BinaryOp, Expr, Expr)
  FunctionCall(String, Array[Expr])
} derive(Eq, Debug)

///|
pub enum ExprLiteral {
  LitString(String)
  LitNumber(String)
  LitBool(Bool)
  LitNull
} derive(Eq, Debug)

///|
pub enum UnaryOp {
  OpNot
} derive(Eq, Debug)

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
} derive(Eq, Debug)

///|
pub impl Show for Expr with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for ExprLiteral with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for UnaryOp with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for BinaryOp with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend BinaryOp with @debug.Debug::{to_repr}

///|
pub extend BinaryOp with Eq::{not_equal, equal}

///|
pub extend BinaryOp with Show::{to_string, output}

///|
pub extend Expr with @debug.Debug::{to_repr}

///|
pub extend Expr with Eq::{not_equal, equal}

///|
pub extend Expr with Show::{to_string, output}

///|
pub extend ExprLiteral with @debug.Debug::{to_repr}

///|
pub extend ExprLiteral with Eq::{not_equal, equal}

///|
pub extend ExprLiteral with Show::{to_string, output}

///|
pub extend UnaryOp with @debug.Debug::{to_repr}

///|
pub extend UnaryOp with Eq::{not_equal, equal}

///|
pub extend UnaryOp with Show::{to_string, output}
