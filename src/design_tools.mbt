///|
/// A directed dependency edge between two modules.
pub struct ModuleDependency {
  from : String
  to : String
  instance_count : Int
}

///|
/// A design-level dependency graph.
pub struct DesignGraph {
  modules : Array[String]
  edges : Array[ModuleDependency]
}

///|
/// Aggregate design metrics used by the CLI and benchmark reports.
pub struct DesignMetrics {
  module_count : Int
  port_count : Int
  signal_count : Int
  assignment_count : Int
  instance_count : Int
  always_count : Int
  token_count : Int
  source_lines : Int
}

///|
/// Port compatibility result for an instance connection.
pub enum PortCompatibility {
  Compatible
  WidthMismatch(Int, Int)
  DirectionMismatch
  MissingPort
  UndeclaredSignal
} derive(Eq)

///|
/// Find a module definition by name.
pub fn Design::find_module(self : Design, name : String) -> Module? {
  for unit in self.modules {
    if unit.name == name {
      return Some(unit)
    }
  }
  None
}

///|
/// Return all module names in source order.
pub fn Design::module_names(self : Design) -> Array[String] {
  self.modules.map(fn(unit) { unit.name })
}

///|
/// Return the number of declared ports across the design.
pub fn Design::port_count(self : Design) -> Int {
  self.modules.fold(init=0, fn(total, unit) { total + unit.ports.length() })
}

///|
/// Return the number of declared internal signals across the design.
pub fn Design::signal_count(self : Design) -> Int {
  self.modules.fold(init=0, fn(total, unit) { total + unit.signals.length() })
}

///|
/// Return duplicate module definitions in source order.
pub fn Design::duplicate_modules(self : Design) -> Array[String] {
  let seen : Array[String] = []
  let duplicates : Array[String] = []
  for unit in self.modules {
    if seen.contains(unit.name) && !duplicates.contains(unit.name) {
      duplicates.push(unit.name)
    }
    seen.push(unit.name)
  }
  duplicates
}

///|
/// Return names of module inputs.
pub fn Module::input_names(self : Module) -> Array[String] {
  self.ports
  .filter(fn(port) { port.direction == Some(Input) })
  .map(fn(port) { port.name })
}

///|
/// Return names of module outputs.
pub fn Module::output_names(self : Module) -> Array[String] {
  self.ports
  .filter(fn(port) { port.direction == Some(Output) })
  .map(fn(port) { port.name })
}

///|
/// Return names of bidirectional ports.
pub fn Module::inout_names(self : Module) -> Array[String] {
  self.ports
  .filter(fn(port) { port.direction == Some(Inout) })
  .map(fn(port) { port.name })
}

///|
/// Return whether a signal or port is declared.
pub fn Module::has_signal(self : Module, name : String) -> Bool {
  for port in self.ports {
    if port.name == name {
      return true
    }
  }
  for signal in self.signals {
    if signal.name == name {
      return true
    }
  }
  false
}

///|
/// Return a declared signal's width, treating scalar declarations as one bit.
pub fn Module::width_of(self : Module, name : String) -> Int? {
  for port in self.ports {
    if port.name == name {
      return match port.width {
        Some(width) => Some(width.bits())
        None => Some(1)
      }
    }
  }
  for signal in self.signals {
    if signal.name == name {
      return match signal.width {
        Some(width) => Some(width.bits())
        None => Some(1)
      }
    }
  }
  None
}

///|
/// Return names of declarations by signal kind.
pub fn Module::names_of_kind(self : Module, kind : SignalKind) -> Array[String] {
  self.signals
  .filter(fn(signal) { signal.kind == kind })
  .map(fn(signal) { signal.name })
}

///|
/// Return instance names in source order.
pub fn Module::instance_names(self : Module) -> Array[String] {
  self.instances.map(fn(instance) { instance.instance_name })
}

///|
/// Return a compact, deterministic port signature.
pub fn Module::port_signature(self : Module) -> String {
  self.ports
  .map(fn(port) {
    let direction = match port.direction {
      Some(Input) => "in"
      Some(Output) => "out"
      Some(Inout) => "inout"
      None => "internal"
    }
    let width = match port.width {
      Some(value) => value.bits().to_string()
      None => "1"
    }
    direction + " " + port.name + ":" + width
  })
  .join(",")
}

///|
/// A useful complexity estimate for dashboards, not a quality score.
pub fn Module::complexity_score(self : Module) -> Int {
  let mut score = self.ports.length() + self.signals.length()
  score += self.assignments.length() * 2
  score += self.always_blocks.length() * 4
  score += self.instances.length() * 3
  for block in self.always_blocks {
    if block.body.contains("if") {
      score += 2
    }
    if block.body.contains("case") {
      score += 3
    }
    if block.body.contains("for") {
      score += 3
    }
  }
  score
}

///|
fn dependency_index(
  edges : Array[ModuleDependency],
  from : String,
  to : String,
) -> Int? {
  for i, edge in edges {
    if edge.from == from && edge.to == to {
      return Some(i)
    }
  }
  None
}

///|
/// Construct the module dependency graph from instance declarations.
pub fn Design::dependency_graph(self : Design) -> DesignGraph {
  let modules = self.module_names()
  let edges : Array[ModuleDependency] = []
  for unit in self.modules {
    for instance in unit.instances {
      let existing = dependency_index(edges, unit.name, instance.module_name)
      match existing {
        Some(index) =>
          edges[index] = {
            ..edges[index],
            instance_count: edges[index].instance_count + 1,
          }
        None =>
          edges.push({
            from: unit.name,
            to: instance.module_name,
            instance_count: 1,
          })
      }
    }
  }
  { modules, edges }
}

///|
/// Return direct dependencies of one module.
pub fn DesignGraph::dependencies_of(
  self : DesignGraph,
  name : String,
) -> Array[String] {
  self.edges.filter(fn(edge) { edge.from == name }).map(fn(edge) { edge.to })
}

///|
/// Return modules that directly depend on a module.
pub fn DesignGraph::dependents_of(
  self : DesignGraph,
  name : String,
) -> Array[String] {
  self.edges.filter(fn(edge) { edge.to == name }).map(fn(edge) { edge.from })
}

///|
/// Detect a cycle with a bounded depth-first walk.
pub fn DesignGraph::has_cycle(self : DesignGraph) -> Bool {
  fn visit(
    graph : DesignGraph,
    name : String,
    visiting : Array[String],
    visited : Array[String],
  ) -> Bool {
    if visiting.contains(name) {
      return true
    }
    if visited.contains(name) {
      return false
    }
    let next_visiting = visiting.copy()
    next_visiting.push(name)
    for dependency in graph.dependencies_of(name) {
      if visit(graph, dependency, next_visiting, visited) {
        return true
      }
    }
    visited.push(name)
    false
  }
  let visited : Array[String] = []
  for name in self.modules {
    if visit(self, name, [], visited) {
      return true
    }
  }
  false
}

///|
/// Produce a stable topological order. Cyclic leftovers are appended in source order.
pub fn DesignGraph::topological_order(self : DesignGraph) -> Array[String] {
  let remaining = self.modules.copy()
  let result : Array[String] = []
  while remaining.length() > 0 {
    let mut selected = ""
    for name in remaining {
      let ready = self
        .dependencies_of(name)
        .all(fn(dependency) { !remaining.contains(dependency) })
      if ready {
        selected = name
        break
      }
    }
    if selected == "" {
      selected = remaining[0]
    }
    result.push(selected)
    let mut selected_index = 0
    for i, name in remaining {
      if name == selected {
        selected_index = i
        break
      }
    }
    ignore(remaining.remove(selected_index))
  }
  result
}

///|
/// Render a dependency graph as Graphviz DOT.
pub fn DesignGraph::to_dot(self : DesignGraph) -> String {
  let mut out = "digraph rtl {\n"
  for name in self.modules {
    out += "  \"" + name + "\";\n"
  }
  for edge in self.edges {
    out += "  \"" +
      edge.from +
      "\" -> \"" +
      edge.to +
      "\" [label=\"" +
      edge.instance_count.to_string() +
      "\"];\n"
  }
  out + "}\n"
}

///|
/// Calculate source-level metrics from tokens and line breaks.
pub fn design_metrics(source : String) -> DesignMetrics {
  let design = parse(source)
  let tokens = lex(source)
  let mut assignments = 0
  let mut instances = 0
  let mut always_count = 0
  for unit in design.modules {
    assignments += unit.assignments.length()
    instances += unit.instances.length()
    always_count += unit.always_blocks.length()
  }
  let mut source_lines = 0
  if source.length() > 0 {
    source_lines = source.split("\n").count()
  }
  {
    module_count: design.modules.length(),
    port_count: design.port_count(),
    signal_count: design.signal_count(),
    assignment_count: assignments,
    instance_count: instances,
    always_count,
    token_count: tokens.length(),
    source_lines,
  }
}

///|
/// Serialize metrics for scripts without requiring a JSON package.
pub fn DesignMetrics::to_json(self : DesignMetrics) -> String {
  "{\"modules\":" +
  self.module_count.to_string() +
  ",\"ports\":" +
  self.port_count.to_string() +
  ",\"signals\":" +
  self.signal_count.to_string() +
  ",\"assignments\":" +
  self.assignment_count.to_string() +
  ",\"instances\":" +
  self.instance_count.to_string() +
  ",\"always_blocks\":" +
  self.always_count.to_string() +
  ",\"tokens\":" +
  self.token_count.to_string() +
  ",\"source_lines\":" +
  self.source_lines.to_string() +
  "}"
}

///|
/// Compare a connection with a target port and source signal.
pub fn check_port_compatibility(
  parent : Module,
  target : Module,
  connection : PortConnection,
) -> PortCompatibility {
  let mut port : Signal? = None
  for item in target.ports {
    if item.name == connection.port {
      port = Some(item)
      break
    }
  }
  match port {
    None => MissingPort
    Some(target_port) =>
      match connection.expression {
        None => Compatible
        Some(expr) =>
          match expr.root_name() {
            None => Compatible
            Some(signal_name) =>
              match parent.width_of(signal_name) {
                None => UndeclaredSignal
                Some(source_width) => {
                  let target_width = match target_port.width {
                    Some(width) => width.bits()
                    None => 1
                  }
                  if source_width != target_width {
                    WidthMismatch(source_width, target_width)
                  } else {
                    let source = parent.ports.filter(fn(item) {
                      item.name == signal_name
                    })
                    if target_port.direction == Some(Output) &&
                      source.length() > 0 &&
                      source[0].direction == Some(Input) {
                      DirectionMismatch
                    } else {
                      Compatible
                    }
                  }
                }
              }
          }
      }
  }
}

///|
pub fn severity_from_text(text : String) -> Severity? {
  if text == "error" {
    Some(Error)
  } else if text == "warning" {
    Some(Warning)
  } else if text == "info" {
    Some(Info)
  } else {
    None
  }
}

///|
/// Parse a small line-oriented configuration format used by CI scripts.
/// Supported forms are `no-info`, `max-diagnostics=100`,
/// `disable=RTL008`, and `severity=RTL001:warning`.
pub fn parse_check_config(text : String) -> CheckConfig {
  let mut config = CheckConfig::default()
  for raw_line in text.split("\n") {
    let line = raw_line.trim().to_owned()
    if line == "no-info" {
      config = config.without_info()
    } else if line.has_prefix("max-diagnostics=") {
      let value = line.split_once("=").unwrap().1.to_owned()
      let mut number = 0
      for c in value.to_array() {
        if c >= '0' && c <= '9' {
          number = number * 10 + c.to_int() - '0'.to_int()
        }
      }
      config = config.with_max_diagnostics(number)
    } else if line.has_prefix("disable=") {
      config = config.without(line.split_once("=").unwrap().1.to_owned())
    } else if line.has_prefix("severity=") {
      let value = line.split_once("=").unwrap().1.to_owned()
      match value.split_once(":") {
        Some((code, level)) =>
          match severity_from_text(level.to_owned()) {
            Some(severity) =>
              config = config.with_severity(code.to_owned(), severity)
            None => ()
          }
        None => ()
      }
    }
  }
  config
}

///|
/// Return whether a module has a reset-like input by conventional name.
pub fn Module::has_reset_input(self : Module) -> Bool {
  for name in self.input_names() {
    if name.contains("rst") || name.contains("reset") {
      return true
    }
  }
  false
}

///|
/// Return a source-order report for every module.
pub fn design_module_report(source : String) -> String {
  let design = parse(source)
  let mut out = "| Module | Ports | Signals | Assignments | Instances | Complexity |\n| --- | ---: | ---: | ---: | ---: | ---: |\n"
  for unit in design.modules {
    out += "| " +
      unit.name +
      " | " +
      unit.ports.length().to_string() +
      " | " +
      unit.signals.length().to_string() +
      " | " +
      unit.assignments.length().to_string() +
      " | " +
      unit.instances.length().to_string() +
      " | " +
      unit.complexity_score().to_string() +
      " |\n"
  }
  out
}
