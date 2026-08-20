///|
/// A structural timing node derived from a signal or module port.
pub struct TimingNode {
  id : String
  module_name : String
  signal_name : String
  width : Int
  is_input : Bool
  is_output : Bool
  is_register : Bool
  level : Int
}

///|
/// A directed combinational dependency edge.
pub struct TimingEdge {
  from : String
  to : String
  kind : String
  weight : Int
}

///|
/// One longest-path candidate in a timing report.
pub struct TimingPath {
  start : String
  finish : String
  nodes : Array[String]
  delay : Int
  has_cycle : Bool
}

///|
/// Policy for structural timing analysis.
pub struct TimingConfig {
  gate_delay : Int
  register_delay : Int
  max_path_length : Int
  warn_fanout : Int
}

///|
/// Static timing-like metrics for a parsed RTL design.
pub struct TimingReport {
  nodes : Array[TimingNode]
  edges : Array[TimingEdge]
  paths : Array[TimingPath]
  critical_delay : Int
  max_fanout : Int
  cycles : Array[String]
}

///|
pub fn TimingConfig::default() -> TimingConfig {
  { gate_delay: 1, register_delay: 2, max_path_length: 256, warn_fanout: 8 }
}

///|
pub fn TimingConfig::with_delays(
  self : TimingConfig,
  gate_delay : Int,
  register_delay : Int,
) -> TimingConfig {
  {
    ..self,
    gate_delay: if gate_delay < 1 {
      1
    } else {
      gate_delay
    },
    register_delay: if register_delay < 1 {
      1
    } else {
      register_delay
    },
  }
}

///|
fn timing_node_id(module_name : String, signal_name : String) -> String {
  module_name + ":" + signal_name
}

///|
fn timing_find_node(nodes : Array[TimingNode], id : String) -> TimingNode? {
  nodes.filter(fn(item) { item.id == id }).get(0)
}

///|
fn timing_add_node(
  nodes : Array[TimingNode],
  unit : Module,
  name : String,
  is_input : Bool,
  is_output : Bool,
  is_register : Bool,
) -> String {
  let id = timing_node_id(unit.name, name)
  if timing_find_node(nodes, id) is Some(_) {
    return id
  }
  let signal = match unit.ports.filter(fn(item) { item.name == name }).get(0) {
    Some(item) => Some(item)
    None => unit.signals.filter(fn(item) { item.name == name }).get(0)
  }
  let width = match signal {
    Some(item) =>
      match item.width {
        Some(value) => value.bits()
        None => 1
      }
    None => 1
  }
  nodes.push({
    id,
    module_name: unit.name,
    signal_name: name,
    width,
    is_input,
    is_output,
    is_register,
    level: 0,
  })
  id
}

///|
fn timing_add_edge(
  edges : Array[TimingEdge],
  from : String,
  to : String,
  kind : String,
  weight : Int,
) -> Unit {
  if from == to ||
    !edges.any(fn(item) {
      item.from == from && item.to == to && item.kind == kind
    }) {
    edges.push({ from, to, kind, weight })
  }
}

///|
fn timing_expression_names(expr : Expr?, raw : String) -> Array[String] {
  match expr {
    Some(value) => value.references()
    None =>
      raw
      .to_array()
      .fold(init=[], fn(result, c) {
        if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
          let text = c.to_string()
          if !result.contains(text) {
            result.push(text)
          }
        }
        result
      })
  }
}

///|
fn timing_module_graph(
  unit : Module,
  nodes : Array[TimingNode],
  edges : Array[TimingEdge],
) -> Unit {
  for port in unit.ports {
    ignore(
      timing_add_node(
        nodes,
        unit,
        port.name,
        port.direction == Some(Input),
        port.direction == Some(Output),
        false,
      ),
    )
  }
  for signal in unit.signals {
    ignore(
      timing_add_node(
        nodes,
        unit,
        signal.name,
        false,
        false,
        signal.kind == Reg,
      ),
    )
  }
  for assignment in unit.assignments {
    let target = timing_node_id(unit.name, assignment.lhs)
    ignore(
      timing_add_node(
        nodes,
        unit,
        assignment.lhs,
        false,
        false,
        assignment.procedural,
      ),
    )
    for
      reference in timing_expression_names(assignment.rhs_expr, assignment.rhs) {
      ignore(timing_add_node(nodes, unit, reference, false, false, false))
      timing_add_edge(
        edges,
        timing_node_id(unit.name, reference),
        target,
        assignment.operator,
        1,
      )
    }
  }
  for block in unit.always_blocks {
    for sensitivity in block.sensitivity {
      let clock = timing_node_id(unit.name, sensitivity.signal)
      ignore(
        timing_add_node(nodes, unit, sensitivity.signal, false, false, true),
      )
      for assignment in block.statements {
        timing_add_statement_edges(unit, nodes, edges, clock, assignment)
      }
    }
  }
}

///|
fn timing_add_statement_edges(
  unit : Module,
  nodes : Array[TimingNode],
  edges : Array[TimingEdge],
  clock : String,
  statement : Statement,
) -> Unit {
  match statement {
    ProceduralAssignment(assignment) => {
      let target = timing_node_id(unit.name, assignment.lhs)
      ignore(timing_add_node(nodes, unit, assignment.lhs, false, false, true))
      timing_add_edge(edges, clock, target, "clock", 2)
      for
        reference in timing_expression_names(
          assignment.rhs_expr,
          assignment.rhs,
        ) {
        ignore(timing_add_node(nodes, unit, reference, false, false, false))
        timing_add_edge(
          edges,
          timing_node_id(unit.name, reference),
          target,
          assignment.operator,
          1,
        )
      }
    }
    ConditionalStatement(condition, when_true, when_false) => {
      for reference in condition.references() {
        ignore(timing_add_node(nodes, unit, reference, false, false, false))
        timing_add_edge(
          edges,
          timing_node_id(unit.name, reference),
          clock,
          "condition",
          1,
        )
      }
      for nested in when_true {
        timing_add_statement_edges(unit, nodes, edges, clock, nested)
      }
      for nested in when_false {
        timing_add_statement_edges(unit, nodes, edges, clock, nested)
      }
    }
    CaseStatement(expression, items) => {
      for reference in expression.references() {
        ignore(timing_add_node(nodes, unit, reference, false, false, false))
        timing_add_edge(
          edges,
          timing_node_id(unit.name, reference),
          clock,
          "case",
          1,
        )
      }
      for item in items {
        for nested in item.statements {
          timing_add_statement_edges(unit, nodes, edges, clock, nested)
        }
      }
    }
    BlockStatement(items) =>
      for nested in items {
        timing_add_statement_edges(unit, nodes, edges, clock, nested)
      }
    _ => ()
  }
}

///|
fn timing_outgoing(edges : Array[TimingEdge], id : String) -> Array[TimingEdge] {
  edges.filter(fn(item) { item.from == id })
}

///|
fn timing_incoming(edges : Array[TimingEdge], id : String) -> Array[TimingEdge] {
  edges.filter(fn(item) { item.to == id })
}

///|
fn timing_cycle_from(
  edges : Array[TimingEdge],
  current : String,
  active : Array[String],
  visited : Array[String],
) -> String? {
  if active.contains(current) {
    return Some(active.join(" -> ") + " -> " + current)
  }
  if visited.contains(current) {
    return None
  }
  visited.push(current)
  active.push(current)
  for edge in timing_outgoing(edges, current) {
    match timing_cycle_from(edges, edge.to, active, visited) {
      Some(cycle) => return Some(cycle)
      None => ()
    }
  }
  ignore(active.pop())
  None
}

///|
fn timing_find_cycles(
  edges : Array[TimingEdge],
  nodes : Array[TimingNode],
) -> Array[String] {
  let result : Array[String] = []
  for node in nodes {
    match timing_cycle_from(edges, node.id, [], []) {
      Some(cycle) if !result.contains(cycle) => result.push(cycle)
      _ => ()
    }
  }
  result
}

///|
fn timing_path_from(
  edges : Array[TimingEdge],
  current : String,
  path : Array[String],
  remaining : Int,
) -> TimingPath {
  let next_path = path.copy()
  next_path.push(current)
  if remaining <= 0 {
    return {
      start: path.get(0).unwrap_or(current),
      finish: current,
      nodes: next_path,
      delay: 0,
      has_cycle: true,
    }
  }
  let outgoing = timing_outgoing(edges, current)
  if outgoing.length() == 0 {
    return {
      start: path.get(0).unwrap_or(current),
      finish: current,
      nodes: next_path,
      delay: next_path.length(),
      has_cycle: false,
    }
  }
  let mut best : TimingPath? = None
  for edge in outgoing {
    if next_path.contains(edge.to) {
      continue
    }
    let candidate = timing_path_from(edges, edge.to, next_path, remaining - 1)
    match best {
      Some(previous) if previous.delay >= candidate.delay => ()
      _ => best = Some(candidate)
    }
  }
  best.unwrap_or({
    start: path.get(0).unwrap_or(current),
    finish: current,
    nodes: next_path,
    delay: 0,
    has_cycle: false,
  })
}

///|
fn timing_longest_paths(
  nodes : Array[TimingNode],
  edges : Array[TimingEdge],
  max_length : Int,
) -> Array[TimingPath] {
  let result : Array[TimingPath] = []
  for node in nodes {
    if timing_incoming(edges, node.id).length() == 0 {
      result.push(timing_path_from(edges, node.id, [], max_length))
    }
  }
  result.sort_by(fn(a, b) { b.delay - a.delay })
  result
}

///|
fn timing_update_levels(
  nodes : Array[TimingNode],
  edges : Array[TimingEdge],
) -> Unit {
  let mut changed = true
  let mut rounds = 0
  while changed && rounds < nodes.length() + 1 {
    changed = false
    rounds += 1
    for i, node in nodes {
      let incoming = timing_incoming(edges, node.id)
      for edge in incoming {
        match timing_find_node(nodes, edge.from) {
          Some(parent) if parent.level + edge.weight > node.level => {
            nodes[i] = { ..node, level: parent.level + edge.weight }
            changed = true
          }
          _ => ()
        }
      }
    }
  }
}

///|
/// Build a dependency graph and estimate longest structural paths.
pub fn timing_analyze(design : Design, config : TimingConfig) -> TimingReport {
  let nodes : Array[TimingNode] = []
  let edges : Array[TimingEdge] = []
  for unit in design.modules {
    timing_module_graph(unit, nodes, edges)
  }
  timing_update_levels(nodes, edges)
  let paths = timing_longest_paths(nodes, edges, config.max_path_length)
  let cycles = timing_find_cycles(edges, nodes)
  let mut max_fanout = 0
  for node in nodes {
    let fanout = timing_outgoing(edges, node.id).length()
    if fanout > max_fanout {
      max_fanout = fanout
    }
  }
  {
    nodes,
    edges,
    paths,
    critical_delay: paths.get(0).map(fn(item) { item.delay }).unwrap_or(0),
    max_fanout,
    cycles,
  }
}

///|
pub fn timing_source(source : String, config : TimingConfig) -> TimingReport {
  timing_analyze(parse(source), config)
}

///|
pub fn TimingReport::critical_path(self : TimingReport) -> TimingPath? {
  self.paths.get(0)
}

///|
pub fn TimingReport::node(self : TimingReport, id : String) -> TimingNode? {
  timing_find_node(self.nodes, id)
}

///|
pub fn TimingReport::fanout(self : TimingReport, id : String) -> Int {
  timing_outgoing(self.edges, id).length()
}

///|
pub fn TimingReport::is_acyclic(self : TimingReport) -> Bool {
  self.cycles.length() == 0
}

///|
pub fn TimingReport::to_json(self : TimingReport) -> String {
  let nodes = self.nodes
    .map(fn(item) {
      "{\"id\":\"" +
      json_escape(item.id) +
      "\",\"level\":" +
      item.level.to_string() +
      ",\"width\":" +
      item.width.to_string() +
      "}"
    })
    .join(",")
  let edges = self.edges
    .map(fn(item) {
      "{\"from\":\"" +
      json_escape(item.from) +
      "\",\"to\":\"" +
      json_escape(item.to) +
      "\",\"kind\":\"" +
      item.kind +
      "\",\"weight\":" +
      item.weight.to_string() +
      "}"
    })
    .join(",")
  let paths = self.paths
    .map(fn(item) {
      "{\"start\":\"" +
      json_escape(item.start) +
      "\",\"finish\":\"" +
      json_escape(item.finish) +
      "\",\"delay\":" +
      item.delay.to_string() +
      "\",\"nodes\":[" +
      item.nodes.map(fn(name) { "\"" + json_escape(name) + "\"" }).join(",") +
      "]}"
    })
    .join(",")
  "{\"critical_delay\":" +
  self.critical_delay.to_string() +
  ",\"max_fanout\":" +
  self.max_fanout.to_string() +
  ",\"cycles\":[" +
  self.cycles.map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "],\"nodes\":[" +
  nodes +
  "],\"edges\":[" +
  edges +
  "],\"paths\":[" +
  paths +
  "]}"
}

///|
pub fn TimingReport::to_markdown(self : TimingReport) -> String {
  let path_text = self.paths
    .map(fn(item) {
      "| " +
      item.start +
      " | " +
      item.finish +
      " | " +
      item.delay.to_string() +
      " | " +
      item.nodes.join(" → ") +
      " |"
    })
    .join("\n")
  let cycles = if self.cycles.length() == 0 {
    "None"
  } else {
    self.cycles.join("; ")
  }
  "# Timing report\n\n" +
  "- critical delay: `" +
  self.critical_delay.to_string() +
  "`\n" +
  "- maximum fanout: `" +
  self.max_fanout.to_string() +
  "`\n" +
  "- cycles: `" +
  cycles +
  "`\n\n" +
  "| Start | Finish | Delay | Path |\n| --- | --- | ---: | --- |\n" +
  path_text +
  "\n"
}

///|
pub fn timing_diagnostics(
  report : TimingReport,
  config : TimingConfig,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  if report.cycles.length() > 0 {
    result.push(
      Diagnostic::new(
        "TIM001",
        Error,
        "combinational dependency cycle detected",
        1,
        1,
      ),
    )
  }
  if report.max_fanout > config.warn_fanout {
    result.push(
      Diagnostic::new("TIM002", Warning, "signal fanout exceeds policy", 1, 1),
    )
  }
  result
}

///|
pub fn timing_contract() -> String {
  "graph=signal_dependency; path=longest_dag_path; cycle=error; " +
  "delay=unit_gate_plus_register_weight; fanout=outgoing_edge_count"
}
