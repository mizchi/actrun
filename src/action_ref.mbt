///|
pub enum ActionRef {
  GitHubRepo(String, String, String, String?)
  LocalPath(String)
  DockerImage(String)
  Registry(String, String, String)
}

///|
pub struct ActionRefParseResult {
  action : ActionRef?
  errors : Array[String]
}

///|
pub struct ResolvedAction {
  uses : String
  action_ref : ActionRef
  kind : String
  backend : String
  action_path : String?
  entrypoint : String?
  image : String?
  args : Array[String]
}

///|
pub struct ActionResolutionResult {
  action : ResolvedAction?
  errors : Array[String]
}

///|
fn substring(text : String, start : Int, end_ : Int) -> String {
  String::unsafe_substring(text, start~, end=end_)
}

///|
fn split_action_version(text : String) -> (String, String) {
  let mut idx = text.length()
  while idx > 0 {
    idx -= 1
    if text.unsafe_get(idx) == '@' {
      return (substring(text, 0, idx), substring(text, idx + 1, text.length()))
    }
  }
  (text, "")
}

///|
fn split_path_segments(text : String) -> Array[String] {
  let parts : Array[String] = []
  for part in text.split("/") {
    parts.push(part.to_string())
  }
  parts
}

///|
fn action_ref_text(action : ActionRef) -> String {
  match action {
    GitHubRepo(owner, repo, version, subpath) => {
      let path = match subpath {
        Some(path) if path.length() > 0 => "/" + path
        _ => ""
      }
      if version.length() > 0 {
        owner + "/" + repo + path + "@" + version
      } else {
        owner + "/" + repo + path
      }
    }
    LocalPath(path) => path
    DockerImage(image) => "docker://" + image
    Registry(scheme, name, version) =>
      if version.length() > 0 {
        scheme + "://" + name + "@" + version
      } else {
        scheme + "://" + name
      }
  }
}

///|
fn action_parse_error(text : String, msg : String) -> ActionRefParseResult {
  { action: None, errors: ["action ref '\{text}' " + msg] }
}

///|
pub fn parse_action_ref(text : String) -> ActionRefParseResult {
  let uses = text.trim(chars=" ").to_string()
  if uses.length() == 0 {
    return { action: None, errors: ["action ref is empty"] }
  }
  if uses.has_prefix("./") || uses.has_prefix("../") {
    return { action: Some(LocalPath(uses)), errors: [] }
  }
  if uses.has_prefix("docker://") {
    let image = substring(uses, 9, uses.length())
    if image.length() == 0 {
      return action_parse_error(uses, "must include an image name")
    }
    return { action: Some(DockerImage(image)), errors: [] }
  }
  match uses.find("://") {
    Some(idx) => {
      let scheme = substring(uses, 0, idx)
      let remainder = substring(uses, idx + 3, uses.length())
      if scheme.length() == 0 {
        return action_parse_error(uses, "has an empty scheme")
      }
      let (name, version) = split_action_version(remainder)
      if name.length() == 0 {
        return action_parse_error(uses, "must include an action name")
      }
      { action: Some(Registry(scheme, name, version)), errors: [] }
    }
    None => {
      let (path, version) = split_action_version(uses)
      let parts = split_path_segments(path)
      if parts.length() < 2 {
        return action_parse_error(
          uses, "must be owner/repo@ref, docker://image, ./path, or scheme://name@version",
        )
      }
      let owner = parts[0]
      let repo = parts[1]
      if owner.length() == 0 || repo.length() == 0 {
        return action_parse_error(uses, "must include owner and repo")
      }
      let sub_parts : Array[String] = []
      for idx in 2..<parts.length() {
        let part = parts[idx]
        if part.length() > 0 {
          sub_parts.push(part)
        }
      }
      let subpath = if sub_parts.length() > 0 {
        Some(sub_parts.join("/"))
      } else {
        None
      }
      { action: Some(GitHubRepo(owner, repo, version, subpath)), errors: [] }
    }
  }
}

///|
pub fn resolve_action_ref(action : ActionRef) -> ActionResolutionResult {
  match action {
    GitHubRepo(owner, repo, _, None) if owner == "actions" && repo == "checkout" =>
      {
        action: Some({
          uses: action_ref_text(action),
          action_ref: action,
          kind: "checkout",
          backend: "builtin",
          action_path: None,
          entrypoint: None,
          image: None,
          args: [],
        }),
        errors: [],
      }
    GitHubRepo("actions", "upload-artifact", _, None) =>
      {
        action: Some({
          uses: action_ref_text(action),
          action_ref: action,
          kind: "upload-artifact",
          backend: "builtin",
          action_path: None,
          entrypoint: None,
          image: None,
          args: [],
        }),
        errors: [],
      }
    GitHubRepo("actions", "download-artifact", _, None) =>
      {
        action: Some({
          uses: action_ref_text(action),
          action_ref: action,
          kind: "download-artifact",
          backend: "builtin",
          action_path: None,
          entrypoint: None,
          image: None,
          args: [],
        }),
        errors: [],
      }
    GitHubRepo("actions", "setup-node", _, None) =>
      {
        action: Some({
          uses: action_ref_text(action),
          action_ref: action,
          kind: "setup-node",
          backend: "builtin",
          action_path: None,
          entrypoint: None,
          image: None,
          args: [],
        }),
        errors: [],
      }
    GitHubRepo("actions", "cache", _, None) =>
      {
        action: Some({
          uses: action_ref_text(action),
          action_ref: action,
          kind: "cache",
          backend: "builtin",
          action_path: None,
          entrypoint: None,
          image: None,
          args: [],
        }),
        errors: [],
      }
    GitHubRepo("actions", "cache", _, Some("restore")) =>
      {
        action: Some({
          uses: action_ref_text(action),
          action_ref: action,
          kind: "cache-restore",
          backend: "builtin",
          action_path: None,
          entrypoint: None,
          image: None,
          args: [],
        }),
        errors: [],
      }
    GitHubRepo("actions", "cache", _, Some("save")) =>
      {
        action: Some({
          uses: action_ref_text(action),
          action_ref: action,
          kind: "cache-save",
          backend: "builtin",
          action_path: None,
          entrypoint: None,
          image: None,
          args: [],
        }),
        errors: [],
      }
    Registry(scheme, name, _) if scheme == "builtin" && name == "checkout" =>
      {
        action: Some({
          uses: action_ref_text(action),
          action_ref: action,
          kind: "checkout",
          backend: "builtin",
          action_path: None,
          entrypoint: None,
          image: None,
          args: [],
        }),
        errors: [],
      }
    DockerImage(image) =>
      {
        action: Some({
          uses: action_ref_text(action),
          action_ref: action,
          kind: "docker-image",
          backend: "docker",
          action_path: None,
          entrypoint: None,
          image: Some(image),
          args: [],
        }),
        errors: [],
      }
    _ =>
      {
        action: None,
        errors: ["action '\{action_ref_text(action)}' is not supported in MVP"],
      }
  }
}

///|
pub fn resolve_action_uses(text : String) -> ActionResolutionResult {
  let parsed = parse_action_ref(text)
  match parsed.action {
    Some(action) =>
      if parsed.errors.length() > 0 {
        { action: None, errors: parsed.errors }
      } else {
        resolve_action_ref(action)
      }
    None => { action: None, errors: parsed.errors }
  }
}
