///|
pub enum ExprType {
  TyAny
  TyNull
  TyNumber
  TyBool
  TyString
  TyArray(ExprType)
  TyObject(ObjectKind)
} derive(Eq, Show)

///|
pub enum ObjectKind {
  Strict(Map[String, ExprType])
  Loose(Map[String, ExprType], ExprType)
  MapObj(ExprType)
} derive(Eq, Show)

///|
fn ExprType::is_assignable_to(self : ExprType, target : ExprType) -> Bool {
  if self == target || target == TyAny || self == TyAny {
    return true
  }
  match (self, target) {
    (TyNull, _) => true
    (TyArray(a), TyArray(b)) => a.is_assignable_to(b)
    (TyObject(_), TyObject(_)) => true
    _ => false
  }
}

///|
fn ExprType::property_type(
  self : ExprType,
  name : String,
) -> (ExprType, String?) {
  match self {
    TyObject(Strict(fields)) => {
      let opt : ExprType? = fields.get(name)
      match opt {
        Option::Some(t) => (t, Option::None)
        Option::None => {
          let known = fields.keys().collect()
          (TyAny, Option::Some("unknown property '\{name}', known: \{known}"))
        }
      }
    }
    TyObject(Loose(fields, default_type)) => {
      let opt : ExprType? = fields.get(name)
      match opt {
        Option::Some(t) => (t, Option::None)
        Option::None => (default_type, Option::None)
      }
    }
    TyObject(MapObj(value_type)) => (value_type, Option::None)
    TyAny => (TyAny, Option::None)
    _ => (TyAny, Option::Some("cannot access property '\{name}' on \{self}"))
  }
}

///|
fn ExprType::index_type(self : ExprType) -> ExprType {
  match self {
    TyArray(elem) => elem
    TyObject(MapObj(v)) => v
    TyObject(Strict(_)) => TyAny
    TyObject(Loose(_, default_type)) => default_type
    TyAny => TyAny
    _ => TyAny
  }
}

///|
fn format_type(ty : ExprType) -> String {
  match ty {
    TyAny => "any"
    TyNull => "null"
    TyNumber => "number"
    TyBool => "bool"
    TyString => "string"
    TyArray(elem) => "array<\{format_type(elem)}>"
    TyObject(_) => "object"
  }
}
