///|
priv struct ExprChecker {
  ctx : LintContext
  diagnostics : Array[LintDiagnostic]
  job_id : String
  step_index : Int
  field : String
}

///|
fn ExprChecker::new(
  ctx : LintContext,
  job_id : String,
  step_index : Int,
  field : String,
) -> ExprChecker {
  { ctx, diagnostics: [], job_id, step_index, field }
}

///|
fn ExprChecker::add_error(
  self : ExprChecker,
  code : String,
  msg : String,
) -> Unit {
  self.diagnostics.push({
    severity: Error,
    code,
    message: msg,
    job_id: self.job_id,
    step_index: self.step_index,
    field: self.field,
  })
}

///|
fn ExprChecker::add_warning(
  self : ExprChecker,
  code : String,
  msg : String,
) -> Unit {
  self.diagnostics.push({
    severity: Warning,
    code,
    message: msg,
    job_id: self.job_id,
    step_index: self.step_index,
    field: self.field,
  })
}

///|
fn ExprChecker::check(self : ExprChecker, expr : Expr) -> ExprType {
  match expr {
    Literal(lit) => self.check_literal(lit)
    Ident(name) => self.check_ident(name)
    PropertyAccess(obj, prop) => self.check_property(obj, prop)
    IndexAccess(obj, idx) => self.check_index(obj, idx)
    UnaryOp(op, operand) => self.check_unary(op, operand)
    BinaryOp(op, left, right) => self.check_binary(op, left, right)
    FunctionCall(name, args) => self.check_function(name, args)
  }
}

///|
fn ExprChecker::check_literal(
  self : ExprChecker,
  lit : ExprLiteral,
) -> ExprType {
  ignore(self)
  match lit {
    LitString(_) => TyString
    LitNumber(_) => TyNumber
    LitBool(_) => TyBool
    LitNull => TyNull
  }
}

///|
fn ExprChecker::check_ident(self : ExprChecker, name : String) -> ExprType {
  let opt : ExprType? = self.ctx.contexts.get(name)
  match opt {
    Option::Some(ty) => ty
    Option::None => {
      self.add_error("undefined-context", "undefined context '\{name}'")
      TyAny
    }
  }
}

///|
fn ExprChecker::check_property(
  self : ExprChecker,
  obj : Expr,
  prop : String,
) -> ExprType {
  let obj_type = self.check(obj)
  let (result_type, err) = obj_type.property_type(prop)
  match err {
    Some(msg) => {
      self.add_warning("unknown-property", msg)
      result_type
    }
    None => result_type
  }
}

///|
fn ExprChecker::check_index(
  self : ExprChecker,
  obj : Expr,
  idx : Expr,
) -> ExprType {
  let obj_type = self.check(obj)
  let idx_type = self.check(idx)
  ignore(idx_type)
  obj_type.index_type()
}

///|
fn ExprChecker::check_unary(
  self : ExprChecker,
  _op : UnaryOp,
  operand : Expr,
) -> ExprType {
  let _ = self.check(operand)
  TyBool
}

///|
fn ExprChecker::check_binary(
  self : ExprChecker,
  op : BinaryOp,
  left : Expr,
  right : Expr,
) -> ExprType {
  let left_type = self.check(left)
  let right_type = self.check(right)
  match op {
    OpAnd | OpOr => TyBool
    OpEq | OpNeq => {
      // Warn if comparing incompatible types (but allow any)
      if left_type != TyAny &&
        right_type != TyAny &&
        left_type != TyNull &&
        right_type != TyNull &&
        !left_type.is_assignable_to(right_type) &&
        !right_type.is_assignable_to(left_type) {
        self.add_warning(
          "type-mismatch",
          "comparing \{format_type(left_type)} with \{format_type(right_type)}",
        )
      }
      TyBool
    }
    OpLt | OpLe | OpGt | OpGe => {
      // comparison operators work on numbers and strings
      if left_type != TyAny && left_type != TyNumber && left_type != TyString {
        self.add_warning(
          "comparison-type",
          "comparison operator on \{format_type(left_type)}, expected number or string",
        )
      }
      TyBool
    }
  }
}

///|
fn ExprChecker::check_function(
  self : ExprChecker,
  name : String,
  args : Array[Expr],
) -> ExprType {
  let arg_types : Array[ExprType] = []
  for arg in args {
    arg_types.push(self.check(arg))
  }
  match name {
    "contains" => {
      if args.length() != 2 {
        self.add_error(
          "wrong-arity",
          "contains() requires 2 arguments, got \{args.length()}",
        )
      }
      TyBool
    }
    "startsWith" => {
      if args.length() != 2 {
        self.add_error(
          "wrong-arity",
          "startsWith() requires 2 arguments, got \{args.length()}",
        )
      }
      TyBool
    }
    "endsWith" => {
      if args.length() != 2 {
        self.add_error(
          "wrong-arity",
          "endsWith() requires 2 arguments, got \{args.length()}",
        )
      }
      TyBool
    }
    "format" => {
      if args.length() < 1 {
        self.add_error("wrong-arity", "format() requires at least 1 argument")
      }
      TyString
    }
    "join" => {
      if args.length() < 1 || args.length() > 2 {
        self.add_error(
          "wrong-arity",
          "join() requires 1-2 arguments, got \{args.length()}",
        )
      }
      TyString
    }
    "toJSON" => {
      if args.length() != 1 {
        self.add_error(
          "wrong-arity",
          "toJSON() requires 1 argument, got \{args.length()}",
        )
      }
      TyString
    }
    "fromJSON" => {
      if args.length() != 1 {
        self.add_error(
          "wrong-arity",
          "fromJSON() requires 1 argument, got \{args.length()}",
        )
      }
      TyAny
    }
    "hashFiles" => {
      if args.length() < 1 {
        self.add_error(
          "wrong-arity", "hashFiles() requires at least 1 argument",
        )
      }
      for i, at in arg_types {
        if at != TyAny && at != TyString {
          self.add_warning(
            "argument-type",
            "hashFiles() argument \{i} should be string, got \{format_type(at)}",
          )
        }
      }
      TyString
    }
    "success" | "failure" | "always" | "cancelled" => {
      if args.length() != 0 {
        self.add_error(
          "wrong-arity",
          "\{name}() takes no arguments, got \{args.length()}",
        )
      }
      TyBool
    }
    _ => {
      self.add_error("unknown-function", "unknown function '\{name}'")
      TyAny
    }
  }
}

///|
pub fn check_expression(
  source : String,
  ctx : LintContext,
  job_id : String,
  step_index : Int,
  field : String,
) -> Array[LintDiagnostic] {
  let (expr, parse_errors) = parse_expression(source)
  let checker = ExprChecker::new(ctx, job_id, step_index, field)
  // Report parse errors as diagnostics
  for err in parse_errors {
    checker.add_error("expression-syntax", "parse error: \{err}")
  }
  let _ = checker.check(expr)
  checker.diagnostics
}
