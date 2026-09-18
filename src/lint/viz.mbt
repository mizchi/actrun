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
  let layout = layout_workflow(workflow)
  render_layout_ascii(layout)
}

///|
/// Render workflow as SVG
pub fn render_workflow_svg(
  workflow : @ar.WorkflowSpec,
  theme? : String = "github-dark",
) -> String {
  let layout = layout_workflow(workflow)
  render_layout_svg(layout, viz_theme(theme))
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
    parts.push(ch.to_owned())
  }
  parts.join("_")
}

///|
fn escape_mermaid(text : String) -> String {
  text.replace_all(old="\"", new="#quot;")
}

///|
fn truncate(text : String, max_len : Int) -> String {
  if text.length() <= max_len {
    text
  } else {
    String::unsafe_substring(text, start=0, end=max_len - 3) + "..."
  }
}

///|
fn first_line(text : String) -> String {
  match text.split("\n").head() {
    Some(line) => line.to_owned()
    None => text
  }
}

// ---------------------------------------------------------------------------
// Layered DAG layout shared by the ASCII and SVG renderers
// ---------------------------------------------------------------------------

///|
/// A node placed in the layered layout. Real nodes carry a job label;
/// virtual nodes are pass-through points for edges spanning several layers.
priv struct VizNode {
  label : String
  is_virtual : Bool
  /// Index of this node within `VizLayout::nodes`.
  index : Int
  /// Layer (row) the node belongs to.
  layer : Int
  /// Character width of the rendered node (ASCII), 1 for virtual nodes.
  width : Int
}

///|
priv struct VizEdge {
  from : Int
  to : Int
}

///|
priv struct VizLayout {
  nodes : Array[VizNode]
  /// Node indices per layer, in display order.
  layers : Array[Array[Int]]
  /// Edges between adjacent layers (virtual nodes inserted as needed).
  edges : Array[VizEdge]
}

///|
fn job_display_name(job : @ar.JobSpec) -> String {
  if job.name.length() > 0 {
    job.name
  } else {
    job.id
  }
}

///|
/// Assign each job a layer equal to the longest chain of `needs`
/// leading to it. Unknown or cyclic dependencies are ignored.
fn compute_job_layers(workflow : @ar.WorkflowSpec) -> Map[String, Int] {
  let jobs_by_id : Map[String, @ar.JobSpec] = Map([])
  for job in workflow.jobs {
    jobs_by_id[job.id] = job
  }
  let layers : Map[String, Int] = Map([])
  let visiting : Map[String, Bool] = Map([])
  fn visit(id : String) -> Int {
    match layers.get(id) {
      Some(layer) => return layer
      None => ()
    }
    guard jobs_by_id.get(id) is Some(job) else { return 0 }
    if visiting.get(id) is Some(true) {
      return 0
    }
    visiting[id] = true
    let mut layer = 0
    for need_id in job.needs {
      if jobs_by_id.contains(need_id) {
        layer = layer.max(visit(need_id) + 1)
      }
    }
    visiting[id] = false
    layers[id] = layer
    layer
  }

  for job in workflow.jobs {
    ignore(visit(job.id))
  }
  layers
}

///|
fn layout_workflow(workflow : @ar.WorkflowSpec) -> VizLayout {
  let job_layers = compute_job_layers(workflow)
  let nodes : Array[VizNode] = []
  let node_index : Map[String, Int] = Map([])
  let mut layer_count = 0
  for job in workflow.jobs {
    let layer = job_layers.get(job.id).unwrap_or(0)
    layer_count = layer_count.max(layer + 1)
    let label = job_display_name(job)
    node_index[job.id] = nodes.length()
    nodes.push({
      label,
      is_virtual: false,
      index: nodes.length(),
      layer,
      width: label.length() + 4,
    })
  }
  let layers : Array[Array[Int]] = []
  for _ in 0..<layer_count {
    layers.push([])
  }
  for node in nodes {
    layers[node.layer].push(node.index)
  }
  let edges : Array[VizEdge] = []
  for job in workflow.jobs {
    guard node_index.get(job.id) is Some(to_index) else { continue }
    for need_id in job.needs {
      guard node_index.get(need_id) is Some(from_index) else { continue }
      let mut current = from_index
      let from_layer = nodes[from_index].layer
      let to_layer = nodes[to_index].layer
      if to_layer <= from_layer {
        // Cycles and unknown ordering: draw a direct edge between rows
        // only when it points downward; otherwise skip.
        continue
      }
      for layer in (from_layer + 1)..<to_layer {
        let virtual_index = nodes.length()
        nodes.push({
          label: "",
          is_virtual: true,
          index: virtual_index,
          layer,
          width: 1,
        })
        layers[layer].push(virtual_index)
        edges.push({ from: current, to: virtual_index, })
        current = virtual_index
      }
      edges.push({ from: current, to: to_index, })
    }
  }
  { nodes, layers, edges, }
}

// ---------------------------------------------------------------------------
// ASCII rendering
// ---------------------------------------------------------------------------

///|
priv struct AsciiCanvas {
  rows : Array[Array[Char]]
  width : Int
}

///|
fn AsciiCanvas::new(width : Int, height : Int) -> AsciiCanvas {
  let rows : Array[Array[Char]] = []
  for _ in 0..<height {
    rows.push(Array::make(width, ' '))
  }
  { rows, width, }
}

///|
fn AsciiCanvas::put(self : AsciiCanvas, x : Int, y : Int, ch : Char) -> Unit {
  if y < 0 || y >= self.rows.length() || x < 0 || x >= self.width {
    return
  }
  self.rows[y][x] = ch
}

///|
fn AsciiCanvas::get(self : AsciiCanvas, x : Int, y : Int) -> Char {
  if y < 0 || y >= self.rows.length() || x < 0 || x >= self.width {
    return ' '
  }
  self.rows[y][x]
}

///|
fn AsciiCanvas::put_text(
  self : AsciiCanvas,
  x : Int,
  y : Int,
  text : String,
) -> Unit {
  let mut cursor = x
  for ch in text {
    self.put(cursor, y, ch)
    cursor += 1
  }
}

///|
/// Merge a box-drawing character into the canvas so crossing lines join.
fn AsciiCanvas::merge_line(
  self : AsciiCanvas,
  x : Int,
  y : Int,
  ch : Char,
) -> Unit {
  let existing = self.get(x, y)
  let merged = merge_box_chars(existing, ch)
  self.put(x, y, merged)
}

///|
fn AsciiCanvas::to_string(self : AsciiCanvas) -> String {
  let lines : Array[String] = []
  for row in self.rows {
    let text = String::from_array(row)
    lines.push(text.trim_end().to_owned())
  }
  // Drop trailing blank rows
  while lines.length() > 0 && lines[lines.length() - 1].length() == 0 {
    ignore(lines.pop())
  }
  lines.join("\n")
}

///|
/// Connection bits: 1 = up, 2 = down, 4 = left, 8 = right
fn box_char_bits(ch : Char) -> Int {
  match ch {
    '│' => 3
    '─' => 12
    '┌' => 10
    '┐' => 6
    '└' => 9
    '┘' => 5
    '├' => 11
    '┤' => 7
    '┬' => 14
    '┴' => 13
    '┼' => 15
    _ => 0
  }
}

///|
fn bits_box_char(bits : Int) -> Char {
  match bits {
    1 | 2 | 3 => '│'
    4 | 8 | 12 => '─'
    10 => '┌'
    6 => '┐'
    9 => '└'
    5 => '┘'
    11 => '├'
    7 => '┤'
    14 => '┬'
    13 => '┴'
    15 => '┼'
    _ => ' '
  }
}

///|
fn merge_box_chars(existing : Char, incoming : Char) -> Char {
  let a = box_char_bits(existing)
  let b = box_char_bits(incoming)
  if a == 0 {
    return incoming
  }
  if b == 0 {
    return existing
  }
  bits_box_char(a | b)
}

///|
/// Horizontal gap between nodes in the same layer.
const ASCII_NODE_GAP = 4

///|
/// Rows used by a node box.
const ASCII_NODE_HEIGHT = 3

///|
/// Rows used by the connector area between layers.
const ASCII_GAP_HEIGHT = 3

///|
fn layer_width(layout : VizLayout, layer : Array[Int]) -> Int {
  let mut width = 0
  for i, index in layer {
    if i > 0 {
      width += ASCII_NODE_GAP
    }
    width += layout.nodes[index].width
  }
  width
}

///|
/// Compute the left x offset for each node so every layer is centered.
fn compute_node_x(layout : VizLayout) -> (Array[Int], Int) {
  let mut canvas_width = 0
  for layer in layout.layers {
    canvas_width = canvas_width.max(layer_width(layout, layer))
  }
  let xs : Array[Int] = Array::make(layout.nodes.length(), 0)
  for layer in layout.layers {
    let total = layer_width(layout, layer)
    // Align integer centers so a lone child sits under a lone parent even
    // when box widths differ in parity.
    let mut cursor = canvas_width / 2 - total / 2
    for index in layer {
      xs[index] = cursor
      cursor += layout.nodes[index].width + ASCII_NODE_GAP
    }
  }
  (xs, canvas_width)
}

///|
fn node_center_x(layout : VizLayout, xs : Array[Int], index : Int) -> Int {
  let node = layout.nodes[index]
  if node.is_virtual {
    xs[index]
  } else {
    xs[index] + node.width / 2
  }
}

///|
fn layer_top_y(layer : Int) -> Int {
  layer * (ASCII_NODE_HEIGHT + ASCII_GAP_HEIGHT)
}

///|
fn draw_ascii_node(
  canvas : AsciiCanvas,
  node : VizNode,
  x : Int,
  y : Int,
) -> Unit {
  if node.is_virtual {
    for dy in 0..<ASCII_NODE_HEIGHT {
      canvas.merge_line(x, y + dy, '│')
    }
    return
  }
  let inner = node.width - 2
  canvas.put(x, y, '┌')
  canvas.put_text(x + 1, y, "─".repeat(inner))
  canvas.put(x + node.width - 1, y, '┐')
  canvas.put(x, y + 1, '│')
  canvas.put_text(x + 1, y + 1, " " + node.label + " ")
  canvas.put(x + node.width - 1, y + 1, '│')
  canvas.put(x, y + 2, '└')
  canvas.put_text(x + 1, y + 2, "─".repeat(inner))
  canvas.put(x + node.width - 1, y + 2, '┘')
}

///|
/// Draw an edge between two adjacent layers as an orthogonal polyline:
/// down from the parent, horizontally along the middle connector row,
/// then down into the child.
fn draw_ascii_edge(
  canvas : AsciiCanvas,
  from_x : Int,
  to_x : Int,
  gap_top : Int,
) -> Unit {
  let bus_y = gap_top + 1
  canvas.merge_line(from_x, gap_top, '│')
  canvas.merge_line(to_x, gap_top + 2, '│')
  if from_x == to_x {
    canvas.merge_line(from_x, bus_y, '│')
    return
  }
  let (left, right) = if from_x < to_x {
    (from_x, to_x)
  } else {
    (to_x, from_x)
  }
  for x in (left + 1)..<right {
    canvas.merge_line(x, bus_y, '─')
  }
  // Corner at the parent side (line comes from above) and at the child side
  // (line continues below).
  let from_corner = if from_x < to_x { '└' } else { '┘' }
  let to_corner = if from_x < to_x { '┐' } else { '┌' }
  canvas.merge_line(from_x, bus_y, from_corner)
  canvas.merge_line(to_x, bus_y, to_corner)
}

///|
fn render_layout_ascii(layout : VizLayout) -> String {
  if layout.layers.length() == 0 {
    return ""
  }
  let (xs, canvas_width) = compute_node_x(layout)
  let height = layout.layers.length() * ASCII_NODE_HEIGHT +
    (layout.layers.length() - 1) * ASCII_GAP_HEIGHT
  let canvas = AsciiCanvas::new(canvas_width.max(1), height)
  for node in layout.nodes {
    draw_ascii_node(canvas, node, xs[node.index], layer_top_y(node.layer))
  }
  for edge in layout.edges {
    let from_layer = layout.nodes[edge.from].layer
    let gap_top = layer_top_y(from_layer) + ASCII_NODE_HEIGHT
    draw_ascii_edge(
      canvas,
      node_center_x(layout, xs, edge.from),
      node_center_x(layout, xs, edge.to),
      gap_top,
    )
  }
  canvas.to_string()
}

// ---------------------------------------------------------------------------
// SVG rendering
// ---------------------------------------------------------------------------

///|
priv struct VizTheme {
  background : String
  node_fill : String
  node_stroke : String
  text : String
  edge : String
}

///|
fn viz_theme(name : String) -> VizTheme {
  match name {
    "github-light" | "light" | "default" =>
      {
        background: "#ffffff",
        node_fill: "#f6f8fa",
        node_stroke: "#d0d7de",
        text: "#1f2328",
        edge: "#57606a",
      }
    "neutral" =>
      {
        background: "#fafafa",
        node_fill: "#ffffff",
        node_stroke: "#333333",
        text: "#111111",
        edge: "#333333",
      }
    "forest" =>
      {
        background: "#f1f8f1",
        node_fill: "#cde498",
        node_stroke: "#13540c",
        text: "#13540c",
        edge: "#13540c",
      }
    _ =>
      {
        background: "#0d1117",
        node_fill: "#161b22",
        node_stroke: "#30363d",
        text: "#e6edf3",
        edge: "#8b949e",
      }
  }
}

///|
const SVG_CHAR_WIDTH = 8

///|
const SVG_NODE_HEIGHT = 36

///|
const SVG_NODE_GAP = 32

///|
const SVG_LAYER_GAP = 48

///|
const SVG_PADDING = 24

///|
fn svg_node_width(node : VizNode) -> Int {
  if node.is_virtual {
    0
  } else {
    node.label.length() * SVG_CHAR_WIDTH + 24
  }
}

///|
fn svg_layer_width(layout : VizLayout, layer : Array[Int]) -> Int {
  let mut width = 0
  for i, index in layer {
    if i > 0 {
      width += SVG_NODE_GAP
    }
    width += svg_node_width(layout.nodes[index])
  }
  width
}

///|
fn escape_xml(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
fn render_layout_svg(layout : VizLayout, theme : VizTheme) -> String {
  let mut content_width = 0
  for layer in layout.layers {
    content_width = content_width.max(svg_layer_width(layout, layer))
  }
  let layer_count = layout.layers.length()
  let content_height = if layer_count == 0 {
    0
  } else {
    layer_count * SVG_NODE_HEIGHT + (layer_count - 1) * SVG_LAYER_GAP
  }
  let width = content_width + SVG_PADDING * 2
  let height = content_height + SVG_PADDING * 2
  let xs : Array[Int] = Array::make(layout.nodes.length(), 0)
  let ys : Array[Int] = Array::make(layout.nodes.length(), 0)
  for layer_index, layer in layout.layers {
    let total = svg_layer_width(layout, layer)
    let mut cursor = SVG_PADDING + content_width / 2 - total / 2
    for index in layer {
      xs[index] = cursor
      ys[index] = SVG_PADDING + layer_index * (SVG_NODE_HEIGHT + SVG_LAYER_GAP)
      cursor += svg_node_width(layout.nodes[index]) + SVG_NODE_GAP
    }
  }
  fn center_x(index : Int) -> Int {
    xs[index] + svg_node_width(layout.nodes[index]) / 2
  }

  let lines : Array[String] = []
  lines.push(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\" viewBox=\"0 0 " +
    width.to_string() +
    " " +
    height.to_string() +
    "\" font-family=\"ui-monospace, SFMono-Regular, Menlo, monospace\" font-size=\"13\">",
  )
  lines.push(
    "  <rect width=\"100%\" height=\"100%\" fill=\"" + theme.background + "\"/>",
  )
  for edge in layout.edges {
    let from_node = layout.nodes[edge.from]
    let to_node = layout.nodes[edge.to]
    let x1 = center_x(edge.from)
    let y1 = if from_node.is_virtual {
      ys[edge.from]
    } else {
      ys[edge.from] + SVG_NODE_HEIGHT
    }
    let x2 = center_x(edge.to)
    let y2 = ys[edge.to]
    let mid_y = ys[edge.to] - SVG_LAYER_GAP / 2
    let y_end = if to_node.is_virtual { y2 + SVG_NODE_HEIGHT } else { y2 }
    let points = x1.to_string() +
      "," +
      y1.to_string() +
      " " +
      x1.to_string() +
      "," +
      mid_y.to_string() +
      " " +
      x2.to_string() +
      "," +
      mid_y.to_string() +
      " " +
      x2.to_string() +
      "," +
      y_end.to_string()
    lines.push(
      "  <polyline points=\"" +
      points +
      "\" fill=\"none\" stroke=\"" +
      theme.edge +
      "\" stroke-width=\"1.5\"/>",
    )
  }
  for node in layout.nodes {
    if node.is_virtual {
      continue
    }
    let w = svg_node_width(node)
    lines.push(
      "  <rect x=\"" +
      xs[node.index].to_string() +
      "\" y=\"" +
      ys[node.index].to_string() +
      "\" width=\"" +
      w.to_string() +
      "\" height=\"" +
      SVG_NODE_HEIGHT.to_string() +
      "\" rx=\"6\" fill=\"" +
      theme.node_fill +
      "\" stroke=\"" +
      theme.node_stroke +
      "\"/>",
    )
    lines.push(
      "  <text x=\"" +
      center_x(node.index).to_string() +
      "\" y=\"" +
      (ys[node.index] + SVG_NODE_HEIGHT / 2).to_string() +
      "\" text-anchor=\"middle\" dominant-baseline=\"central\" fill=\"" +
      theme.text +
      "\">" +
      escape_xml(node.label) +
      "</text>",
    )
  }
  lines.push("</svg>")
  lines.join("\n")
}
