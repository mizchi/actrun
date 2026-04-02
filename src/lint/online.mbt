///|
/// Action reference to be resolved online
pub struct ActionRefToResolve {
  uses : String // e.g. "actions/checkout@v4"
  owner : String
  repo : String
  ref_str : String // e.g. "v4"
  subpath : String // e.g. "" or "/some/path"
  job_id : String
  step_index : Int
  is_sha_pinned : Bool
} derive(Show)

///|
/// Result of online action resolution
pub struct ActionResolution {
  uses : String
  sha : String // resolved SHA, empty if failed
  exists : Bool
  error : String // error message, empty if success
} derive(Show)

///|
pub fn new_action_resolution(
  uses : String,
  sha? : String = "",
  exists? : Bool = false,
  error? : String = "",
) -> ActionResolution {
  { uses, sha, exists, error }
}

///|
/// Collect all GitHub action refs from a workflow for online resolution
pub fn collect_action_refs(
  workflow : @ar.WorkflowSpec,
) -> Array[ActionRefToResolve] {
  let refs : Array[ActionRefToResolve] = []
  for job in workflow.jobs {
    for i, step in job.steps {
      match step.uses {
        Option::Some(uses) => {
          // Skip local paths, docker://, and expressions
          if uses.has_prefix("./") ||
            uses.has_prefix("docker://") ||
            uses.contains("$\u007b\u007b") {
            continue
          }
          match parse_action_uses(uses) {
            Option::Some(parsed) =>
              refs.push({
                uses,
                owner: parsed.0,
                repo: parsed.1,
                ref_str: parsed.2,
                subpath: parsed.3,
                job_id: job.id,
                step_index: i,
                is_sha_pinned: is_sha_ref(parsed.2),
              })
            Option::None => ()
          }
        }
        Option::None => ()
      }
    }
  }
  refs
}

///|
/// Parse "owner/repo@ref" or "owner/repo/path@ref" into (owner, repo, ref, subpath)
fn parse_action_uses(uses : String) -> (String, String, String, String)? {
  // Find @
  match uses.find("@") {
    Option::None => Option::None
    Option::Some(at_idx) => {
      let path = String::unsafe_substring(uses, start=0, end=at_idx)
      let ref_str = String::unsafe_substring(
        uses,
        start=at_idx + 1,
        end=uses.length(),
      )
      // Split path into owner/repo[/subpath]
      let parts : Array[String] = []
      for p in path.split("/") {
        parts.push(p.to_string())
      }
      if parts.length() < 2 {
        return Option::None
      }
      let owner = parts[0]
      let repo = parts[1]
      let subpath = if parts.length() > 2 {
        let sub_parts : Array[String] = []
        let mut j = 2
        while j < parts.length() {
          sub_parts.push(parts[j])
          j += 1
        }
        "/" + sub_parts.join("/")
      } else {
        ""
      }
      Option::Some((owner, repo, ref_str, subpath))
    }
  }
}

///|
/// Check if a ref looks like a full SHA (40 hex chars)
fn is_sha_ref(ref_str : String) -> Bool {
  if ref_str.length() != 40 {
    return false
  }
  for ch in ref_str {
    if !((ch >= '0' && ch <= '9') ||
      (ch >= 'a' && ch <= 'f') ||
      (ch >= 'A' && ch <= 'F')) {
      return false
    }
  }
  true
}

///|
/// Check version consistency across multiple workflow files.
/// Detects if the same action (owner/repo) is referenced with different versions.
pub fn check_version_consistency(
  file_refs : Array[(String, Array[ActionRefToResolve])],
) -> Array[LintDiagnostic] {
  let diagnostics : Array[LintDiagnostic] = []
  // Build map: "owner/repo" -> Array[(file_path, ref_str, uses)]
  let action_map : Map[String, Array[(String, String, String)]] = {}
  for pair in file_refs {
    let file_path = pair.0
    let refs = pair.1
    for r in refs {
      let key = r.owner + "/" + r.repo
      match action_map.get(key) {
        Option::Some(arr) => arr.push((file_path, r.ref_str, r.uses))
        Option::None => action_map[key] = [(file_path, r.ref_str, r.uses)]
      }
    }
  }
  // For each action, check if there are multiple distinct ref_str values
  for key, entries in action_map {
    let unique_refs : Map[String, String] = {} // ref_str -> first file_path
    for entry in entries {
      let ref_str = entry.1
      let file_path = entry.0
      match unique_refs.get(ref_str) {
        Option::Some(_) => () // already seen this ref
        Option::None => unique_refs[ref_str] = file_path
      }
    }
    if unique_refs.length() < 2 {
      continue
    }
    // Build description of versions found
    let parts : Array[String] = []
    for ref_str, file_path in unique_refs {
      parts.push("@" + ref_str + " in " + file_path)
    }
    let version_desc = parts.join(", ")
    // Emit a warning for each occurrence
    for entry in entries {
      let file_path = entry.0
      let uses = entry.2
      diagnostics.push({
        severity: Warning,
        code: "inconsistent-action-version",
        message: "action '" +
        key +
        "' has inconsistent versions: " +
        version_desc,
        job_id: file_path,
        step_index: -1,
        field: "uses",
      })
      ignore(uses)
    }
  }
  diagnostics
}

///|
/// Generate diagnostics from online resolution results
pub fn diagnostics_from_resolutions(
  refs : Array[ActionRefToResolve],
  resolutions : Array[ActionResolution],
) -> Array[LintDiagnostic] {
  let diagnostics : Array[LintDiagnostic] = []
  for i, action_ref in refs {
    if i >= resolutions.length() {
      break
    }
    let resolution = resolutions[i]
    if !resolution.exists {
      diagnostics.push({
        severity: Error,
        code: "action-not-found",
        message: "action '\{action_ref.uses}' could not be resolved: \{resolution.error}",
        job_id: action_ref.job_id,
        step_index: action_ref.step_index,
        field: "uses",
      })
      continue
    }
    if !action_ref.is_sha_pinned && resolution.sha.length() > 0 {
      let suggested = action_ref.owner +
        "/" +
        action_ref.repo +
        action_ref.subpath +
        "@" +
        resolution.sha
      diagnostics.push({
        severity: Warning,
        code: "mutable-action-ref",
        message: "action '\{action_ref.uses}' uses a mutable ref. Pin to SHA: \{suggested}",
        job_id: action_ref.job_id,
        step_index: action_ref.step_index,
        field: "uses",
      })
    }
  }
  diagnostics
}
