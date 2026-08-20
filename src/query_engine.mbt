///|
/// A composable predicate for searching a parsed RTL design.
pub enum QueryPredicate {
  QueryModuleEquals(String)
  QueryModuleContains(String)
  QuerySignalContains(String)
  QuerySignalWidthAtLeast(Int)
  QuerySignalWidthEquals(Int)
  QueryHasPort(String)
  QueryHasAssignment(String)
  QueryHasInstance(String)
  QueryHasAlways(AlwaysKind)
  QueryExpressionContains(String)
  QueryDiagnosticCode(String)
  QueryPortCountAtLeast(Int)
} derive(Eq)

///|
/// A reusable design query.
pub struct DesignQuery {
  predicates : Array[QueryPredicate]
  match_all : Bool
  include_signals : Bool
  include_instances : Bool
  max_results : Int
}

///|
/// One result from a design query.
pub struct QueryMatch {
  module_name : String
  kind : String
  name : String
  detail : String
  line : Int
}

///|
/// Query results retain the original predicates for reproducibility.
pub struct QueryResult {
  matches : Array[QueryMatch]
  predicates : Array[String]
  scanned_modules : Int
  scanned_signals : Int
  truncated : Bool
}

///|
pub fn QueryPredicate::module_equals(name : String) -> QueryPredicate {
  QueryModuleEquals(name)
}

///|
pub fn QueryPredicate::signal_width_at_least(width : Int) -> QueryPredicate {
  QuerySignalWidthAtLeast(width)
}

///|
pub fn DesignQuery::empty() -> DesignQuery {
  {
    predicates: [],
    match_all: true,
    include_signals: true,
    include_instances: true,
    max_results: 1000,
  }
}

///|
pub fn DesignQuery::with_predicate(
  self : DesignQuery,
  predicate : QueryPredicate,
) -> DesignQuery {
  let predicates = self.predicates.copy()
  predicates.push(predicate)
  { ..self, predicates, }
}

///|
pub fn DesignQuery::any_predicate(self : DesignQuery) -> DesignQuery {
  { ..self, match_all: false }
}

///|
pub fn DesignQuery::modules_only(self : DesignQuery) -> DesignQuery {
  { ..self, include_signals: false, include_instances: false }
}

///|
pub fn DesignQuery::limit(self : DesignQuery, value : Int) -> DesignQuery {
  { ..self, max_results: value }
}

///|
fn query_kind_text(kind : QueryPredicate) -> String {
  match kind {
    QueryModuleEquals(_) => "module_equals"
    QueryModuleContains(_) => "module_contains"
    QuerySignalContains(_) => "signal_contains"
    QuerySignalWidthAtLeast(_) => "signal_width_at_least"
    QuerySignalWidthEquals(_) => "signal_width_equals"
    QueryHasPort(_) => "has_port"
    QueryHasAssignment(_) => "has_assignment"
    QueryHasInstance(_) => "has_instance"
    QueryHasAlways(_) => "has_always"
    QueryExpressionContains(_) => "expression_contains"
    QueryDiagnosticCode(_) => "diagnostic_code"
    QueryPortCountAtLeast(_) => "port_count_at_least"
  }
}

///|
fn query_value_text(predicate : QueryPredicate) -> String {
  match predicate {
    QueryModuleEquals(value)
    | QueryModuleContains(value)
    | QuerySignalContains(value)
    | QueryHasPort(value)
    | QueryHasAssignment(value)
    | QueryHasInstance(value)
    | QueryExpressionContains(value)
    | QueryDiagnosticCode(value) => value
    QuerySignalWidthAtLeast(value)
    | QuerySignalWidthEquals(value)
    | QueryPortCountAtLeast(value) => value.to_string()
    QueryHasAlways(value) =>
      match value {
        AlwaysLevel => "level"
        AlwaysPosedge => "posedge"
        AlwaysNegedge => "negedge"
        AlwaysAny => "any"
        AlwaysComb => "comb"
        AlwaysLatch => "latch"
        AlwaysFF => "ff"
      }
  }
}

///|
fn query_predicate_text(predicate : QueryPredicate) -> String {
  query_kind_text(predicate) + "(" + query_value_text(predicate) + ")"
}

///|
/// Construct every predicate family for documentation and capability probes.
pub fn query_predicate_catalog() -> Array[String] {
  [
    QueryModuleEquals("top"),
    QueryModuleContains("core"),
    QuerySignalContains("data"),
    QuerySignalWidthAtLeast(32),
    QuerySignalWidthEquals(1),
    QueryHasPort("clk"),
    QueryHasAssignment("ready"),
    QueryHasInstance("alu"),
    QueryHasAlways(AlwaysComb),
    QueryExpressionContains("valid"),
    QueryDiagnosticCode("RTL001"),
    QueryPortCountAtLeast(2),
  ].map(query_predicate_text)
}

///|
fn query_signal_width(signal : Signal) -> Int {
  match signal.width {
    Some(width) => width.bits()
    None => 1
  }
}

///|
fn query_signal_direction(signal : Signal) -> String {
  match signal.direction {
    Some(Input) => "input"
    Some(Output) => "output"
    Some(Inout) => "inout"
    None => "internal"
  }
}

///|
fn query_module_text(unit : Module) -> String {
  unit.name +
  " " +
  unit.ports.map(fn(item) { item.name }).join(" ") +
  " " +
  unit.signals.map(fn(item) { item.name }).join(" ") +
  " " +
  unit.assignments.map(fn(item) { item.rhs }).join(" ") +
  " " +
  unit.always_blocks.map(fn(item) { item.body }).join(" ") +
  " " +
  unit.instances
  .map(fn(item) { item.module_name + " " + item.instance_name })
  .join(" ")
}

///|
fn query_has_assignment(unit : Module, name : String) -> Bool {
  for assignment in unit.assignments {
    if assignment.lhs == name {
      return true
    }
  }
  for block in unit.always_blocks {
    let assignments : Array[Assignment] = []
    advanced_statement_assignments(block.statements, assignments)
    for assignment in assignments {
      if assignment.lhs == name {
        return true
      }
    }
  }
  false
}

///|
fn query_has_port(unit : Module, name : String) -> Bool {
  unit.ports.any(fn(item) { item.name == name })
}

///|
fn query_has_instance(unit : Module, name : String) -> Bool {
  unit.instances.any(fn(item) {
    item.module_name == name || item.instance_name == name
  })
}

///|
fn query_has_always(unit : Module, kind : AlwaysKind) -> Bool {
  unit.always_blocks.any(fn(item) { item.kind == kind })
}

///|
fn query_predicate_matches_module(
  unit : Module,
  predicate : QueryPredicate,
  diagnostics : Array[Diagnostic],
) -> Bool {
  match predicate {
    QueryModuleEquals(value) => unit.name == value
    QueryModuleContains(value) => unit.name.contains(value)
    QuerySignalContains(value) =>
      (unit.ports + unit.signals).any(fn(item) { item.name.contains(value) })
    QuerySignalWidthAtLeast(value) =>
      (unit.ports + unit.signals).any(fn(item) {
        query_signal_width(item) >= value
      })
    QuerySignalWidthEquals(value) =>
      (unit.ports + unit.signals).any(fn(item) {
        query_signal_width(item) == value
      })
    QueryHasPort(value) => query_has_port(unit, value)
    QueryHasAssignment(value) => query_has_assignment(unit, value)
    QueryHasInstance(value) => query_has_instance(unit, value)
    QueryHasAlways(value) => query_has_always(unit, value)
    QueryExpressionContains(value) => query_module_text(unit).contains(value)
    QueryDiagnosticCode(value) =>
      diagnostics.any(fn(item) {
        item.code == value && item.module_name == Some(unit.name)
      })
    QueryPortCountAtLeast(value) => unit.ports.length() >= value
  }
}

///|
fn query_match_module(unit : Module) -> QueryMatch {
  {
    module_name: unit.name,
    kind: "module",
    name: unit.name,
    detail: unit.ports.length().to_string() +
    " ports, " +
    unit.signals.length().to_string() +
    " signals",
    line: unit.span.start.line,
  }
}

///|
fn query_match_signal(unit : Module, signal : Signal) -> QueryMatch {
  {
    module_name: unit.name,
    kind: "signal:" + query_signal_direction(signal),
    name: signal.name,
    detail: query_signal_width(signal).to_string() + " bits",
    line: signal.span.start.line,
  }
}

///|
fn query_match_assignment(unit : Module, assignment : Assignment) -> QueryMatch {
  {
    module_name: unit.name,
    kind: "assignment",
    name: assignment.lhs,
    detail: assignment.operator + " " + assignment.rhs,
    line: assignment.span.start.line,
  }
}

///|
fn query_match_instance(unit : Module, instance : ModuleInstance) -> QueryMatch {
  {
    module_name: unit.name,
    kind: "instance",
    name: instance.instance_name,
    detail: instance.module_name +
    " with " +
    instance.connections.length().to_string() +
    " connections",
    line: instance.span.start.line,
  }
}

///|
fn query_signal_predicate_matches(
  signal : Signal,
  predicates : Array[QueryPredicate],
) -> Bool {
  for predicate in predicates {
    match predicate {
      QuerySignalContains(value) =>
        if !signal.name.contains(value) {
          return false
        }
      QuerySignalWidthAtLeast(value) =>
        if query_signal_width(signal) < value {
          return false
        }
      QuerySignalWidthEquals(value) =>
        if query_signal_width(signal) != value {
          return false
        }
      _ => ()
    }
  }
  true
}

///|
fn query_signal_by_name(unit : Module, name : String) -> Signal? {
  for signal in unit.ports {
    if signal.name == name {
      return Some(signal)
    }
  }
  for signal in unit.signals {
    if signal.name == name {
      return Some(signal)
    }
  }
  None
}

///|
fn query_predicates_match(
  unit : Module,
  query : DesignQuery,
  diagnostics : Array[Diagnostic],
) -> Bool {
  if query.predicates.length() == 0 {
    true
  } else if query.match_all {
    query.predicates.all(fn(item) {
      query_predicate_matches_module(unit, item, diagnostics)
    })
  } else {
    query.predicates.any(fn(item) {
      query_predicate_matches_module(unit, item, diagnostics)
    })
  }
}

///|
fn query_matches_name_scope(
  unit : Module,
  query : DesignQuery,
  found_item : QueryMatch,
) -> Bool {
  if query.predicates.length() == 0 {
    true
  } else if found_item.kind.has_prefix("signal:") {
    match query_signal_by_name(unit, found_item.name) {
      Some(signal) => query_signal_predicate_matches(signal, query.predicates)
      None => false
    }
  } else {
    true
  }
}

///|
fn query_append(
  result : Array[QueryMatch],
  query : DesignQuery,
  item : QueryMatch,
) -> Bool {
  if query.max_results > 0 && result.length() >= query.max_results {
    false
  } else {
    result.push(item)
    true
  }
}

///|
fn query_module_matches(
  unit : Module,
  query : DesignQuery,
  diagnostics : Array[Diagnostic],
  result : Array[QueryMatch],
) -> Unit {
  if !query_predicates_match(unit, query, diagnostics) {
    return
  }
  if !query_append(result, query, query_match_module(unit)) {
    return
  }
  if query.include_signals {
    for signal in unit.ports + unit.signals {
      let item = query_match_signal(unit, signal)
      if query_matches_name_scope(unit, query, item) {
        if !query_append(result, query, item) {
          return
        }
      }
    }
  }
  if query.include_instances {
    for instance in unit.instances {
      if !query_append(result, query, query_match_instance(unit, instance)) {
        return
      }
    }
  }
  for assignment in unit.assignments {
    if query.predicates.any(fn(item) {
        match item {
          QueryHasAssignment(name) => name == assignment.lhs
          QueryExpressionContains(value) => assignment.rhs.contains(value)
          _ => false
        }
      }) {
      if !query_append(result, query, query_match_assignment(unit, assignment)) {
        return
      }
    }
  }
}

///|
pub fn run_design_query(design : Design, query : DesignQuery) -> QueryResult {
  let diagnostics = check(design)
  let matches : Array[QueryMatch] = []
  let mut scanned_signals = 0
  for unit in design.modules {
    scanned_signals = scanned_signals +
      unit.ports.length() +
      unit.signals.length()
    query_module_matches(unit, query, diagnostics, matches)
    if query.max_results > 0 && matches.length() >= query.max_results {
      break
    }
  }
  {
    matches,
    predicates: query.predicates.map(query_predicate_text),
    scanned_modules: design.modules.length(),
    scanned_signals,
    truncated: query.max_results > 0 && matches.length() >= query.max_results,
  }
}

///|
pub fn run_source_query(source : String, query : DesignQuery) -> QueryResult {
  run_design_query(parse(source), query)
}

///|
pub fn QueryResult::count(self : QueryResult) -> Int {
  self.matches.length()
}

///|
pub fn QueryResult::to_text(self : QueryResult) -> String {
  self.matches
  .map(fn(item) {
    item.module_name + "\t" + item.kind + "\t" + item.name + "\t" + item.detail
  })
  .join("\n")
}

///|
pub fn QueryResult::to_json(self : QueryResult) -> String {
  let items = self.matches
    .map(fn(item) {
      "{\"module\":\"" +
      json_escape(item.module_name) +
      "\",\"kind\":\"" +
      json_escape(item.kind) +
      "\",\"name\":\"" +
      json_escape(item.name) +
      "\",\"detail\":\"" +
      json_escape(item.detail) +
      "\",\"line\":" +
      item.line.to_string() +
      "}"
    })
    .join(",")
  "{\"count\":" +
  self.count().to_string() +
  ",\"scanned_modules\":" +
  self.scanned_modules.to_string() +
  ",\"scanned_signals\":" +
  self.scanned_signals.to_string() +
  ",\"truncated\":" +
  (if self.truncated { "true" } else { "false" }) +
  ",\"predicates\":[" +
  self.predicates.map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "]" +
  ",\"matches\":[" +
  items +
  "]}"
}

///|
pub fn QueryResult::to_markdown(self : QueryResult) -> String {
  let rows = self.matches
    .map(fn(item) {
      "| " +
      item.module_name +
      " | " +
      item.kind +
      " | " +
      item.name +
      " | " +
      item.detail +
      " | " +
      item.line.to_string() +
      " |"
    })
    .join("\n")
  "## Design query\n\n" +
  "Matches: " +
  self.count().to_string() +
  "\n\n" +
  "| Module | Kind | Name | Detail | Line |\n|---|---|---|---|---|\n" +
  rows
}

///|
/// Find the immediate expression sources of a named signal.
pub fn signal_sources(unit : Module, target : String) -> Array[String] {
  let result : Array[String] = []
  for assignment in unit.assignments {
    if assignment.lhs == target {
      match assignment.rhs_expr {
        Some(expr) => advanced_expr_names(expr, result)
        None => ()
      }
    }
  }
  for block in unit.always_blocks {
    let assignments : Array[Assignment] = []
    advanced_statement_assignments(block.statements, assignments)
    for assignment in assignments {
      if assignment.lhs == target {
        match assignment.rhs_expr {
          Some(expr) => advanced_expr_names(expr, result)
          None => ()
        }
      }
    }
  }
  result
}

///|
/// Find the transitive input cone of influence for a signal.
pub fn signal_cone(
  unit : Module,
  target : String,
  max_depth : Int,
) -> Array[String] {
  let result : Array[String] = []
  let frontier : Array[String] = [target]
  let mut depth = 0
  while frontier.length() > 0 && (max_depth <= 0 || depth < max_depth) {
    let next : Array[String] = []
    for item in frontier {
      for source in signal_sources(unit, item) {
        if !result.contains(source) && source != target {
          result.push(source)
          next.push(source)
        }
      }
    }
    frontier.clear()
    for item in next {
      frontier.push(item)
    }
    depth = depth + 1
  }
  result
}

///|
pub fn signal_cone_report(
  unit : Module,
  target : String,
  max_depth : Int,
) -> String {
  let cone = signal_cone(unit, target, max_depth)
  "target=" +
  target +
  "; depth=" +
  max_depth.to_string() +
  "; sources=" +
  cone.join(",")
}

///|
pub fn query_contract() -> String {
  "predicates=12; scopes=module,signal,instance,assignment; outputs=text,json,markdown; graph=cone"
}
