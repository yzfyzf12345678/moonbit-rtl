///|
/// A searchable index for editor and CI integrations.
pub struct DesignIndex {
  modules : Array[String]
  signals : Array[(String, String)]
  instances : Array[(String, String, String)]
}

///|
/// The kind of symbol returned by an index query.
pub enum SymbolKind {
  ModuleSymbol
  PortSymbol
  SignalSymbol
  InstanceSymbol
} derive(Eq)

///|
/// A source symbol location summary.
pub struct SymbolHit {
  kind : SymbolKind
  name : String
  owner : String
  line : Int
  column : Int
}

///|
/// Construct an index from the parsed design.
pub fn DesignIndex::from(design : Design) -> DesignIndex {
  let modules : Array[String] = []
  let signals : Array[(String, String)] = []
  let instances : Array[(String, String, String)] = []
  for unit in design.modules {
    modules.push(unit.name)
    for port in unit.ports {
      signals.push((unit.name, port.name))
    }
    for signal in unit.signals {
      signals.push((unit.name, signal.name))
    }
    for instance in unit.instances {
      instances.push((unit.name, instance.instance_name, instance.module_name))
    }
  }
  { modules, signals, instances }
}

///|
/// Query a design index by a case-sensitive prefix.
pub fn DesignIndex::symbols_with_prefix(
  self : DesignIndex,
  prefix : String,
) -> Array[String] {
  let result : Array[String] = []
  for name in self.modules {
    if name.has_prefix(prefix) && !result.contains(name) {
      result.push(name)
    }
  }
  for signal in self.signals {
    let (_, name) = signal
    if name.has_prefix(prefix) && !result.contains(name) {
      result.push(name)
    }
  }
  for instance in self.instances {
    let (_, instance_name, _) = instance
    if instance_name.has_prefix(prefix) && !result.contains(instance_name) {
      result.push(instance_name)
    }
  }
  result
}

///|
/// Return all symbols with their owning module and source span.
pub fn index_hits(design : Design) -> Array[SymbolHit] {
  let result : Array[SymbolHit] = []
  for unit in design.modules {
    result.push({
      kind: ModuleSymbol,
      name: unit.name,
      owner: unit.name,
      line: unit.span.start.line,
      column: unit.span.start.column,
    })
    for port in unit.ports {
      result.push({
        kind: PortSymbol,
        name: port.name,
        owner: unit.name,
        line: port.span.start.line,
        column: port.span.start.column,
      })
    }
    for signal in unit.signals {
      result.push({
        kind: SignalSymbol,
        name: signal.name,
        owner: unit.name,
        line: signal.span.start.line,
        column: signal.span.start.column,
      })
    }
    for instance in unit.instances {
      result.push({
        kind: InstanceSymbol,
        name: instance.instance_name,
        owner: unit.name,
        line: instance.span.start.line,
        column: instance.span.start.column,
      })
    }
  }
  result
}

///|
/// Return all symbols with an exact name.
pub fn query_symbols(design : Design, name : String) -> Array[SymbolHit] {
  index_hits(design).filter(fn(hit) { hit.name == name })
}

///|
/// Return a stable hierarchical instance path for a target module.
pub fn hierarchy_paths(design : Design, target : String) -> Array[String] {
  let result : Array[String] = []
  fn walk(
    design : Design,
    current : String,
    path : String,
    target : String,
    result : Array[String],
    stack : Array[String],
  ) -> Unit {
    if stack.contains(current) {
      return
    }
    let next_stack = stack.copy()
    next_stack.push(current)
    if current == target {
      result.push(path)
      return
    }
    match design.find_module(current) {
      Some(unit) =>
        for instance in unit.instances {
          let next_path = if path == "" {
            instance.instance_name
          } else {
            path + "." + instance.instance_name
          }
          walk(
            design,
            instance.module_name,
            next_path,
            target,
            result,
            next_stack,
          )
        }
      None => ()
    }
  }
  for root in design.modules {
    let is_child = design.modules.any(fn(unit) {
      unit.instances.any(fn(instance) { instance.module_name == root.name })
    })
    if !is_child {
      walk(design, root.name, root.name, target, result, [])
    }
  }
  result
}

///|
/// Return the root candidates of a hierarchy.
pub fn hierarchy_roots(design : Design) -> Array[String] {
  design.modules
  .filter(fn(unit) {
    !design.modules.any(fn(candidate) {
      candidate.instances.any(fn(instance) { instance.module_name == unit.name })
    })
  })
  .map(fn(unit) { unit.name })
}

///|
/// A stable summary of one module's public interface.
pub fn module_interface(unit : Module) -> String {
  let mut out = "module " + unit.name + "\n"
  for port in unit.ports {
    let direction = match port.direction {
      Some(Input) => "input"
      Some(Output) => "output"
      Some(Inout) => "inout"
      None => "unknown"
    }
    let width = match port.width {
      Some(value) => value.bits().to_string()
      None => "1"
    }
    out += "  " + direction + " " + port.name + " " + width + " bits\n"
  }
  out
}

///|
/// Render all module interfaces as a Markdown artifact.
pub fn design_interfaces(design : Design) -> String {
  let mut out = "| Module | Port | Direction | Width |\n| --- | --- | --- | ---: |\n"
  for unit in design.modules {
    for port in unit.ports {
      let direction = match port.direction {
        Some(Input) => "input"
        Some(Output) => "output"
        Some(Inout) => "inout"
        None => "unknown"
      }
      let width = match port.width {
        Some(value) => value.bits().to_string()
        None => "1"
      }
      out += "| " +
        unit.name +
        " | " +
        port.name +
        " | " +
        direction +
        " | " +
        width +
        " |\n"
    }
  }
  out
}

///|
/// Return a rule profile tuned for a teaching or production workflow.
pub fn profile_config(profile : String) -> CheckConfig {
  if profile == "teaching" {
    CheckConfig::default()
    .with_severity("RTL006", Info)
    .with_severity("RTL035", Info)
  } else if profile == "strict" {
    CheckConfig::default()
    .with_severity("RTL003", Error)
    .with_severity("RTL004", Warning)
    .with_severity("RTL006", Warning)
  } else if profile == "quiet" {
    CheckConfig::default().without_info()
  } else {
    CheckConfig::default()
  }
}

///|
/// Return a profile name understood by a configuration UI.
pub fn profile_names() -> Array[String] {
  ["default", "teaching", "strict", "quiet"]
}

///|
/// Select diagnostics by code and render a small rule dashboard.
pub fn rule_dashboard(items : Array[Diagnostic]) -> String {
  let stats = DiagnosticStats::from(items)
  let mut out = "| Rule | Errors | Warnings | Infos |\n| --- | ---: | ---: | ---: |\n"
  for rule in stats.rules {
    out += "| " +
      rule.code +
      " | " +
      rule.errors.to_string() +
      " | " +
      rule.warnings.to_string() +
      " | " +
      rule.infos.to_string() +
      " |\n"
  }
  out
}

///|
/// Return a stable API signature suitable for package release notes.
pub fn public_api_signature(design : Design) -> String {
  let signatures = design.modules.map(fn(unit) {
    unit.name + "(" + unit.port_signature() + ")"
  })
  signatures.join("\n")
}

///|
/// Compare two designs by public module interfaces.
pub fn interface_changes(before : Design, after : Design) -> Array[String] {
  let changes : Array[String] = []
  for name in before.module_names() {
    match (before.find_module(name), after.find_module(name)) {
      (Some(old_unit), Some(new_unit)) if old_unit.port_signature() !=
        new_unit.port_signature() => changes.push("changed " + name)
      (Some(_), None) => changes.push("removed " + name)
      _ => ()
    }
  }
  for name in after.module_names() {
    if before.find_module(name) is None {
      changes.push("added " + name)
    }
  }
  changes
}

///|
/// Return the symbols that are not reachable from any root module.
pub fn unreachable_modules(design : Design) -> Array[String] {
  let reachable : Array[String] = []
  fn mark(design : Design, name : String, reachable : Array[String]) -> Unit {
    if reachable.contains(name) {
      return
    }
    reachable.push(name)
    match design.find_module(name) {
      Some(unit) =>
        for instance in unit.instances {
          mark(design, instance.module_name, reachable)
        }
      None => ()
    }
  }
  for root in hierarchy_roots(design) {
    mark(design, root, reachable)
  }
  design.module_names().filter(fn(name) { !reachable.contains(name) })
}

///|
/// Return a compact hierarchy tree.
pub fn hierarchy_tree(design : Design) -> String {
  fn render(
    design : Design,
    name : String,
    level : Int,
    stack : Array[String],
  ) -> String {
    let mut out = ""
    for _ in 0..<level {
      out += "  "
    }
    out += name + "\n"
    if stack.contains(name) {
      return out
    }
    let next_stack = stack.copy()
    next_stack.push(name)
    match design.find_module(name) {
      Some(unit) =>
        for instance in unit.instances {
          out += render(design, instance.module_name, level + 1, next_stack)
        }
      None => ()
    }
    out
  }
  let mut output = ""
  for root in hierarchy_roots(design) {
    output += render(design, root, 0, [])
  }
  output
}

///|
/// Return a deterministic query result as tab-separated text.
pub fn query_symbols_text(design : Design, name : String) -> String {
  let mut out = "kind\tname\towner\tline\tcolumn\n"
  for hit in query_symbols(design, name) {
    let kind = match hit.kind {
      ModuleSymbol => "module"
      PortSymbol => "port"
      SignalSymbol => "signal"
      InstanceSymbol => "instance"
    }
    out += kind +
      "\t" +
      hit.name +
      "\t" +
      hit.owner +
      "\t" +
      hit.line.to_string() +
      "\t" +
      hit.column.to_string() +
      "\n"
  }
  out
}
