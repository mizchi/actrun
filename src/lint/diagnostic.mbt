///|
pub enum Severity {
  Error
  Warning
} derive(Eq, Show)

///|
pub struct LintDiagnostic {
  severity : Severity
  code : String
  message : String
  job_id : String
  step_index : Int
  field : String
} derive(Eq, Show)

///|
pub fn LintDiagnostic::format(self : LintDiagnostic) -> String {
  let sev = match self.severity {
    Error => "error"
    Warning => "warning"
  }
  "[\{self.job_id}/step\{self.step_index}] \{self.field}: \{sev}[\{self.code}]: \{self.message}"
}
