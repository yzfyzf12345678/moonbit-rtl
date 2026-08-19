///|
/// A coarse signal state used for fast lint explanations.
pub enum SignalState {
  UnknownState
  InputState
  ConstantState
  DrivenState
  MaybeDrivenState
  UnusedState
} derive(Eq)

///|
/// One signal fact with read/write counts.
pub struct DataflowFact {
  name : String
  state : SignalState
  reads : Int
  writes : Int
  first_write_line : Int?
}

///|
/// A module-level dataflow report.
pub struct DataflowReport {
  facts : Array[DataflowFact]
  cycles : Array[String]
  order : Array[String]
}

///|
fn count_name(names : Array[String], wanted : String) -> Int {
  let mut count = 0
  for name in names {
    if name == wanted {
      count += 1
    }
  }
  count
}

///|
fn assignment_reads(unit : Module, name : String) -> Int {
  let mut count = 0
  for assignment in unit.assignments {
    count += count_name(assignment.read_names(), name)
  }
  count
}

///|
fn assignment_writes(unit : Module, name : String) -> Int {
  let mut count = 0
  for assignment in unit.assignments {
    match assignment.write_name() {
      Some(value) if value == name => count += 1
      _ => ()
    }
  }
  count
}

///|
fn signal_state(
  unit : Module,
  signal : Signal,
  reads : Int,
  writes : Int,
) -> SignalState {
  if signal.direction == Some(Input) {
    InputState
  } else if writes > 0 &&
    reads > 0 &&
    unit.assignments.all(fn(assignment) {
      match assignment.write_name() {
        Some(name) if name == signal.name =>
          match assignment.rhs_expr {
            Some(expr) => evaluate_constant(expr) is Some(_)
            None => false
          }
        _ => true
      }
    }) {
    ConstantState
  } else if writes == 0 && reads == 0 {
    UnusedState
  } else if writes == 0 {
    UnknownState
  } else if reads == 0 {
    MaybeDrivenState
  } else {
    DrivenState
  }
}

///|
/// Compute a deterministic signal dataflow summary.
pub fn Module::dataflow(self : Module) -> DataflowReport {
  let facts : Array[DataflowFact] = []
  for signal in self.ports {
    let reads = assignment_reads(self, signal.name)
    let writes = assignment_writes(self, signal.name)
    let first_write_line = first_write_line(self, signal.name)
    facts.push({
      name: signal.name,
      state: signal_state(self, signal, reads, writes),
      reads,
      writes,
      first_write_line,
    })
  }
  for signal in self.signals {
    let reads = assignment_reads(self, signal.name)
    let writes = assignment_writes(self, signal.name)
    let first_write_line = first_write_line(self, signal.name)
    facts.push({
      name: signal.name,
      state: signal_state(self, signal, reads, writes),
      reads,
      writes,
      first_write_line,
    })
  }
  let order = signal_order(self)
  let cycles = signal_cycles(self)
  { facts, cycles, order }
}

///|
fn first_write_line(unit : Module, name : String) -> Int? {
  for assignment in unit.assignments {
    if assignment.write_name() == Some(name) {
      return Some(assignment.span.start.line)
    }
  }
  None
}

///|
fn signal_dependencies(unit : Module, name : String) -> Array[String] {
  let result : Array[String] = []
  for assignment in unit.assignments {
    match assignment.write_name() {
      Some(target) if target == name =>
        for source in assignment.read_names() {
          if !result.contains(source) {
            result.push(source)
          }
        }
      _ => ()
    }
  }
  result
}

///|
fn signal_order(unit : Module) -> Array[String] {
  let names = unit.ports.map(fn(signal) { signal.name }) +
    unit.signals.map(fn(signal) { signal.name })
  let remaining = names.copy()
  let result : Array[String] = []
  while remaining.length() > 0 {
    let mut selected = ""
    for name in remaining {
      if signal_dependencies(unit, name).all(fn(dependency) {
          !remaining.contains(dependency)
        }) {
        selected = name
        break
      }
    }
    if selected == "" {
      selected = remaining[0]
    }
    result.push(selected)
    let mut index = 0
    for i, name in remaining {
      if name == selected {
        index = i
        break
      }
    }
    ignore(remaining.remove(index))
  }
  result
}

///|
fn signal_cycles(unit : Module) -> Array[String] {
  let result : Array[String] = []
  fn visit(
    unit : Module,
    name : String,
    stack : Array[String],
    finished : Array[String],
    result : Array[String],
  ) -> Unit {
    if stack.contains(name) {
      let mut start = 0
      for i, value in stack {
        if value == name {
          start = i
          break
        }
      }
      let cycle = stack[start:].join(" -> ") + " -> " + name
      if !result.contains(cycle) {
        result.push(cycle)
      }
      return
    }
    if finished.contains(name) {
      return
    }
    let next_stack = stack.copy()
    next_stack.push(name)
    for dependency in signal_dependencies(unit, name) {
      visit(unit, dependency, next_stack, finished, result)
    }
    finished.push(name)
  }
  let finished : Array[String] = []
  for name in unit.write_names() {
    visit(unit, name, [], finished, result)
  }
  result
}

///|
/// Render a dataflow report as a compact Markdown table.
pub fn DataflowReport::to_markdown(self : DataflowReport) -> String {
  let mut out = "| Signal | State | Reads | Writes | First write |\n| --- | --- | ---: | ---: | ---: |\n"
  for fact in self.facts {
    let state = match fact.state {
      UnknownState => "unknown"
      InputState => "input"
      ConstantState => "constant"
      DrivenState => "driven"
      MaybeDrivenState => "maybe-driven"
      UnusedState => "unused"
    }
    let first = match fact.first_write_line {
      Some(line) => line.to_string()
      None => "-"
    }
    out += "| " +
      fact.name +
      " | " +
      state +
      " | " +
      fact.reads.to_string() +
      " | " +
      fact.writes.to_string() +
      " | " +
      first +
      " |\n"
  }
  if self.cycles.length() > 0 {
    out += "\nCycles:\n" + self.cycles.join("\n") + "\n"
  }
  out
}

///|
/// Render a dataflow report as JSON.
pub fn DataflowReport::to_json(self : DataflowReport) -> String {
  let facts = self.facts
    .map(fn(fact) {
      let state = match fact.state {
        UnknownState => "unknown"
        InputState => "input"
        ConstantState => "constant"
        DrivenState => "driven"
        MaybeDrivenState => "maybe-driven"
        UnusedState => "unused"
      }
      "{\"name\":\"" +
      fact.name +
      "\",\"state\":\"" +
      state +
      "\",\"reads\":" +
      fact.reads.to_string() +
      ",\"writes\":" +
      fact.writes.to_string() +
      "}"
    })
    .join(",")
  "{\"facts\":[" +
  facts +
  "],\"cycles\":[" +
  self.cycles.map(fn(cycle) { "\"" + cycle + "\"" }).join(",") +
  "],\"order\":[" +
  self.order.map(fn(name) { "\"" + name + "\"" }).join(",") +
  "]}"
}

///|
/// Emit dataflow diagnostics for combinational cycles and dead signals.
fn check_dataflow(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  let report = unit.dataflow()
  for cycle in report.cycles {
    add_diagnostic(
      config,
      result,
      diagnostic_for_rule(
        "RTL040",
        Error,
        "combinational dependency cycle: " + cycle,
        unit.span,
        None,
        unit.name,
      ),
    )
  }
  for fact in report.facts {
    if fact.state == UnusedState && fact.name != "" {
      add_diagnostic(
        config,
        result,
        diagnostic_for_rule(
          "RTL041",
          Info,
          "signal is neither read nor driven: " + fact.name,
          signal_span(unit, fact.name),
          Some(fact.name),
          unit.name,
        ),
      )
    }
    if fact.state == MaybeDrivenState && fact.reads == 0 {
      add_diagnostic(
        config,
        result,
        diagnostic_for_rule(
          "RTL042",
          Info,
          "driven signal is never observed inside this module: " + fact.name,
          signal_span(unit, fact.name),
          Some(fact.name),
          unit.name,
        ),
      )
    }
  }
}

///|
/// Explain a rule ID in a form suitable for documentation links.
pub fn explain_rule(code : String) -> String {
  match code {
    "RTL001" => "assignment width mismatch"
    "RTL002" => "duplicate signal declaration"
    "RTL003" => "output port is not driven"
    "RTL004" => "internal signal has no driver"
    "RTL005" => "multiple signal drivers"
    "RTL006" => "input port is unused"
    "RTL008" => "instance port connection is invalid"
    "RTL009" => "procedural assignment targets a wire"
    "RTL010" => "combinational block may infer a latch"
    "RTL011" => "clocked block uses blocking assignment"
    "RTL012" => "case statement has no default"
    "RTL014" => "undeclared signal reference"
    "RTL017" => "unresolved instance module"
    "RTL019" => "unconnected instance input"
    "RTL025" => "instance connection width mismatch"
    "RTL040" => "combinational dependency cycle"
    "RTL041" => "unused signal"
    "RTL042" => "unobserved driven signal"
    _ => "unknown RTL rule"
  }
}

///|
/// Return a rule catalog in stable Markdown form.
pub fn rule_catalog() -> String {
  let codes = [
    "RTL001", "RTL002", "RTL003", "RTL004", "RTL005", "RTL006", "RTL008", "RTL009",
    "RTL010", "RTL011", "RTL012", "RTL014", "RTL017", "RTL019", "RTL025", "RTL040",
    "RTL041", "RTL042",
  ]
  let mut out = "| Rule | Meaning |\n| --- | --- |\n"
  for code in codes {
    out += "| " + code + " | " + explain_rule(code) + " |\n"
  }
  out
}
