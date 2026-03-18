///|
/// Generate Mermaid flowchart text from a WorkflowSpec
pub fn workflow_to_mermaid(workflow : @ar.WorkflowSpec) -> String {
  let lines : Array[String] = []
  lines.push("graph TD")
  for job in workflow.jobs {
    let name = if job.name.length() > 0 { job.name } else { job.id }
    let label = escape_mermaid(name) +
      " (" +
      job.steps.length().to_string() +
      " steps)"
    lines.push("  " + escape_id(job.id) + "[\"" + label + "\"]")
  }
  for job in workflow.jobs {
    for need_id in job.needs {
      lines.push("  " + escape_id(need_id) + " --> " + escape_id(job.id))
    }
  }
  lines.join("\n")
}

///|
/// Generate detailed Mermaid with step-level subgraphs
pub fn workflow_to_mermaid_detail(workflow : @ar.WorkflowSpec) -> String {
  let lines : Array[String] = []
  lines.push("graph TD")
  for job in workflow.jobs {
    let jid = escape_id(job.id)
    let name = if job.name.length() > 0 { job.name } else { job.id }
    lines.push("  subgraph " + jid + " [\"" + escape_mermaid(name) + "\"]")
    let mut prev_sid = ""
    for i, step in job.steps {
      let sid = jid + "_s" + i.to_string()
      let label = step_label(step)
      lines.push("    " + sid + "([\"" + escape_mermaid(label) + "\"])")
      if prev_sid.length() > 0 {
        lines.push("    " + prev_sid + " --> " + sid)
      }
      prev_sid = sid
    }
    lines.push("  end")
  }
  // job-level edges via needs
  for job in workflow.jobs {
    for need_id in job.needs {
      lines.push("  " + escape_id(need_id) + " --> " + escape_id(job.id))
    }
  }
  lines.join("\n")
}

///|
/// Render workflow as ASCII art
pub fn render_workflow_ascii(workflow : @ar.WorkflowSpec) -> String {
  let mermaid_text = workflow_to_mermaid(workflow)
  @mermaid.render_to_string(mermaid_text)
}

///|
/// Render workflow as SVG
pub fn render_workflow_svg(
  workflow : @ar.WorkflowSpec,
  theme? : String = "github-dark",
) -> String {
  let mermaid_text = workflow_to_mermaid(workflow)
  match @mermaid.svg_options_from_theme(theme) {
    Option::Some(opts) =>
      @mermaid.experimental_render_to_svg(mermaid_text, options=opts)
    Option::None => @mermaid.experimental_render_to_svg(mermaid_text)
  }
}

///|
fn step_label(step : @ar.StepSpec) -> String {
  if step.name.length() > 0 {
    return step.name
  }
  if step.id.length() > 0 {
    return step.id
  }
  match step.uses {
    Option::Some(uses) => truncate(uses, 30)
    Option::None =>
      match step.run {
        Option::Some(run) => truncate(first_line(run), 30)
        Option::None => "step"
      }
  }
}

///|
fn escape_id(id : String) -> String {
  let parts : Array[String] = []
  for ch in id.split("-") {
    parts.push(ch.to_string())
  }
  parts.join("_")
}

///|
fn escape_mermaid(text : String) -> String {
  let parts : Array[String] = []
  for ch in text.split("\"") {
    parts.push(ch.to_string())
  }
  parts.join("#quot;")
}

///|
fn first_line(text : String) -> String {
  for line in text.split("\n") {
    let trimmed = line.trim(chars=" \t\r").to_string()
    if trimmed.length() > 0 {
      return trimmed
    }
  }
  text
}

///|
fn truncate(text : String, max : Int) -> String {
  if text.length() <= max {
    text
  } else {
    String::unsafe_substring(text, start=0, end=max - 3) + "..."
  }
}
