///|
/// A named value visible to the four-state RTL evaluator.
pub struct SimulationBinding {
  name : String
  value : LogicVector
  source : String
}

///|
/// One committed combinational simulation step.
pub struct SimulationStep {
  iteration : Int
  changed_signals : Array[String]
  values : Array[SimulationBinding]
  stable : Bool
}

///|
/// A deterministic simulation result for a single module.
pub struct SimulationResult {
  module_name : String
  bindings : Array[SimulationBinding]
  steps : Array[SimulationStep]
  stable : Bool
  oscillating : Bool
  max_iterations : Int
}

///|
priv struct SimulationState {
  bindings : Array[SimulationBinding]
  changed : Array[String]
}

///|
fn simulation_binding(
  bindings : Array[SimulationBinding],
  name : String,
) -> SimulationBinding? {
  for item in bindings {
    if item.name == name {
      return Some(item)
    }
  }
  None
}

///|
fn simulation_value(
  bindings : Array[SimulationBinding],
  name : String,
) -> LogicVector {
  simulation_binding(bindings, name)
  .map(fn(item) { item.value })
  .unwrap_or(LogicVector::unknown(1))
}

///|
fn simulation_store(
  state : SimulationState,
  name : String,
  value : LogicVector,
  source : String,
) -> Unit {
  for i, item in state.bindings {
    if item.name == name {
      if item.value.case_equal(value) != LogicOne {
        state.bindings[i] = { name, value, source }
        if !state.changed.contains(name) {
          state.changed.push(name)
        }
      }
      return
    }
  }
  state.bindings.push({ name, value, source })
  state.changed.push(name)
}

///|
fn simulation_unknown_for(expr : Expr, unit : Module) -> LogicVector {
  expr.width(unit).map(LogicVector::unknown).unwrap_or(LogicVector::unknown(1))
}

///|
fn simulation_compare(
  left : LogicVector,
  right : LogicVector,
  equal : Bool,
) -> LogicVector {
  let result = if equal {
    left.equal(right)
  } else {
    match left.equal(right) {
      LogicOne => LogicZero
      LogicZero => LogicOne
      _ => LogicUnknown
    }
  }
  LogicVector::from_bits([result])
}

///|
fn simulation_binary(
  operator : String,
  left : LogicVector,
  right : LogicVector,
) -> LogicVector {
  match operator {
    "+" => left.add(right)
    "-" => left.sub(right)
    "&" => left.and_bits(right)
    "|" => left.or_bits(right)
    "^" => left.xor_bits(right)
    "^~" | "~^" => left.xor_bits(right).not()
    "&&" => LogicVector::from_bits([left.truthy().and_bit(right.truthy())])
    "||" => LogicVector::from_bits([left.truthy().or_bit(right.truthy())])
    "==" => simulation_compare(left, right, true)
    "!=" => simulation_compare(left, right, false)
    "===" => LogicVector::from_bits([left.case_equal(right)])
    "!==" =>
      LogicVector::from_bits([
        match left.case_equal(right) {
          LogicOne => LogicZero
          _ => LogicOne
        },
      ])
    "<<" =>
      right
      .to_uint()
      .map(fn(value) { left.shift_left(value) })
      .unwrap_or(LogicVector::unknown(left.width()))
    ">>" =>
      right
      .to_uint()
      .map(fn(value) { left.shift_right(value, false) })
      .unwrap_or(LogicVector::unknown(left.width()))
    ">>>" =>
      right
      .to_uint()
      .map(fn(value) { left.shift_right(value, true) })
      .unwrap_or(LogicVector::unknown(left.width()))
    ">" | ">=" | "<" | "<=" => simulation_order(operator, left, right)
    _ =>
      LogicVector::unknown(
        if left.width() > right.width() {
          left.width()
        } else {
          right.width()
        },
      )
  }
}

///|
fn simulation_order(
  operator : String,
  left : LogicVector,
  right : LogicVector,
) -> LogicVector {
  match (left.to_signed(), right.to_signed()) {
    (Some(a), Some(b)) => {
      let result = match operator {
        ">" => a > b
        ">=" => a >= b
        "<" => a < b
        "<=" => a <= b
        _ => false
      }
      LogicVector::from_int(if result { 1 } else { 0 }, 1)
    }
    _ => LogicVector::unknown(1)
  }
}

///|
fn simulation_call(name : String, args : Array[LogicVector]) -> LogicVector {
  match name {
    "$clog2" =>
      match args.get(0) {
        Some(item) =>
          match item.to_uint() {
            Some(value) => {
              let mut result = 0
              let mut threshold = 1
              while threshold < value {
                threshold *= 2
                result += 1
              }
              LogicVector::from_int(result, 32)
            }
            None => LogicVector::unknown(32)
          }
        None => LogicVector::unknown(32)
      }
    "$unsigned" | "$signed" => args.get(0).unwrap_or(LogicVector::unknown(1))
    _ => LogicVector::unknown(1)
  }
}

///|
/// Evaluate an expression using conservative four-state semantics.
pub fn evaluate_logic_expr(
  expr : Expr,
  unit : Module,
  bindings : Array[SimulationBinding],
) -> LogicVector {
  match expr {
    Name(name) => simulation_value(bindings, name)
    Number(value) => LogicVector::from_literal(value)
    StringLiteral(_) => LogicVector::unknown(1)
    Unknown(value) => LogicVector::from_literal(value)
    Unary(operator, value) => {
      let evaluated = evaluate_logic_expr(value, unit, bindings)
      match operator {
        "~" => evaluated.not()
        "!" => LogicVector::from_bits([evaluated.truthy().not()])
        "-" => LogicVector::zero(evaluated.width()).sub(evaluated)
        "+" => evaluated
        "&" => LogicVector::from_bits([evaluated.reduce_and()])
        "|" => LogicVector::from_bits([evaluated.reduce_or()])
        "^" => LogicVector::from_bits([evaluated.reduce_xor()])
        _ => simulation_unknown_for(expr, unit)
      }
    }
    Binary(left, operator, right) =>
      simulation_binary(
        operator,
        evaluate_logic_expr(left, unit, bindings),
        evaluate_logic_expr(right, unit, bindings),
      )
    Conditional(condition, when_true, when_false) =>
      LogicVector::mux(
        evaluate_logic_expr(condition, unit, bindings).truthy(),
        evaluate_logic_expr(when_true, unit, bindings),
        evaluate_logic_expr(when_false, unit, bindings),
      )
    Concatenation(items) =>
      LogicVector::concat(
        items.map(fn(item) { evaluate_logic_expr(item, unit, bindings) }),
      )
    Replication(count, value) =>
      evaluate_logic_expr(value, unit, bindings).repeat(count)
    Index(value, index) => {
      let vector = evaluate_logic_expr(value, unit, bindings)
      match evaluate_logic_expr(index, unit, bindings).to_uint() {
        Some(position) =>
          LogicVector::from_bits([vector.bit(position).unwrap_or(LogicUnknown)])
        None => LogicVector::unknown(1)
      }
    }
    PartSelect(value, left, right) => {
      let vector = evaluate_logic_expr(value, unit, bindings)
      match
        (
          evaluate_logic_expr(left, unit, bindings).to_uint(),
          evaluate_logic_expr(right, unit, bindings).to_uint(),
        ) {
        (Some(msb), Some(lsb)) => vector.slice(msb, lsb)
        _ =>
          LogicVector::unknown(
            if vector.width() == 0 {
              1
            } else {
              vector.width()
            },
          )
      }
    }
    Call(name, args) =>
      simulation_call(
        name,
        args.map(fn(item) { evaluate_logic_expr(item, unit, bindings) }),
      )
  }
}

///|
fn simulation_initial_bindings(unit : Module) -> Array[SimulationBinding] {
  let result : Array[SimulationBinding] = []
  for signal in unit.ports {
    let source = "port" +
      (match signal.direction {
        Some(Input) => ":input"
        Some(Output) => ":output"
        Some(Inout) => ":inout"
        None => ""
      })
    result.push({
      name: signal.name,
      value: LogicVector::unknown(
        signal.width.map(fn(item) { item.bits() }).unwrap_or(1),
      ),
      source,
    })
  }
  for signal in unit.signals {
    result.push({
      name: signal.name,
      value: LogicVector::unknown(
        signal.width.map(fn(item) { item.bits() }).unwrap_or(1),
      ),
      source: "signal",
    })
  }
  result
}

///|
fn simulation_apply_inputs(
  state : SimulationState,
  inputs : Array[(String, LogicVector)],
) -> Unit {
  for item in inputs {
    simulation_store(state, item.0, item.1, "input")
  }
  state.changed.clear()
}

///|
fn simulation_apply_assignments(state : SimulationState, unit : Module) -> Unit {
  for assignment in unit.assignments {
    match assignment.rhs_expr {
      Some(expr) => {
        let value = evaluate_logic_expr(expr, unit, state.bindings)
        simulation_store(state, assignment.lhs, value, assignment.operator)
      }
      None =>
        simulation_store(
          state,
          assignment.lhs,
          LogicVector::unknown(1),
          assignment.operator,
        )
    }
  }
}

///|
fn simulation_apply_statements(
  state : SimulationState,
  unit : Module,
  statements : Array[Statement],
) -> Unit {
  for statement in statements {
    match statement {
      ProceduralAssignment(assignment) =>
        match assignment.rhs_expr {
          Some(expr) =>
            simulation_store(
              state,
              assignment.lhs,
              evaluate_logic_expr(expr, unit, state.bindings),
              assignment.operator,
            )
          None => ()
        }
      ConditionalStatement(condition, when_true, when_false) => {
        let branch = if evaluate_logic_expr(condition, unit, state.bindings).truthy() ==
          LogicOne {
          when_true
        } else {
          when_false
        }
        simulation_apply_statements(state, unit, branch)
      }
      CaseStatement(expression, items) => {
        let wanted = evaluate_logic_expr(expression, unit, state.bindings)
        let mut selected : Array[Statement] = []
        let mut default_items : Array[Statement] = []
        for item in items {
          if item.is_default {
            default_items = item.statements
          } else if item.labels.any(fn(label) {
              evaluate_logic_expr(label, unit, state.bindings).case_equal(
                wanted,
              ) ==
              LogicOne
            }) {
            selected = item.statements
            break
          }
        }
        simulation_apply_statements(
          state,
          unit,
          if selected.length() > 0 {
            selected
          } else {
            default_items
          },
        )
      }
      BlockStatement(nested) => simulation_apply_statements(state, unit, nested)
      _ => ()
    }
  }
}

///|
/// Simulate a module until assignments reach a fixed point or the iteration cap.
pub fn simulate_module(
  unit : Module,
  inputs : Array[(String, LogicVector)],
  max_iterations : Int,
) -> SimulationResult {
  let state = { bindings: simulation_initial_bindings(unit), changed: [] }
  simulation_apply_inputs(state, inputs)
  let steps : Array[SimulationStep] = []
  let limit = if max_iterations < 1 { 1 } else { max_iterations }
  let mut stable = false
  let mut iteration = 0
  while iteration < limit && !stable {
    state.changed.clear()
    simulation_apply_assignments(state, unit)
    for block in unit.always_blocks {
      simulation_apply_statements(state, unit, block.statements)
    }
    stable = state.changed.length() == 0
    steps.push({
      iteration,
      changed_signals: state.changed.copy(),
      values: state.bindings.copy(),
      stable,
    })
    iteration += 1
  }
  {
    module_name: unit.name,
    bindings: state.bindings,
    steps,
    stable,
    oscillating: !stable,
    max_iterations: limit,
  }
}

///|
pub fn simulate_source(
  source : String,
  module_name : String,
  inputs : Array[(String, LogicVector)],
  max_iterations : Int,
) -> SimulationResult? {
  let design = parse(source)
  for unit in design.modules {
    if unit.name == module_name {
      return Some(simulate_module(unit, inputs, max_iterations))
    }
  }
  None
}

///|
pub fn SimulationResult::value(
  self : SimulationResult,
  name : String,
) -> LogicVector? {
  simulation_binding(self.bindings, name).map(fn(item) { item.value })
}

///|
pub fn SimulationResult::output_values(
  self : SimulationResult,
) -> Array[SimulationBinding] {
  self.bindings.filter(fn(item) {
    item.source == "output" || item.source == "port:output"
  })
}

///|
pub fn SimulationResult::changed_over_time(
  self : SimulationResult,
  name : String,
) -> Int {
  self.steps.filter(fn(step) { step.changed_signals.contains(name) }).length()
}

///|
pub fn SimulationResult::status_line(self : SimulationResult) -> String {
  "module=" +
  self.module_name +
  " stable=" +
  (if self.stable { "true" } else { "false" }) +
  " oscillating=" +
  (if self.oscillating { "true" } else { "false" }) +
  " iterations=" +
  self.steps.length().to_string()
}

///|
fn simulation_binding_json(item : SimulationBinding) -> String {
  "{\"name\":\"" +
  json_escape(item.name) +
  "\",\"value\":\"" +
  item.value.to_binary() +
  "\",\"source\":\"" +
  json_escape(item.source) +
  "\"}"
}

///|
pub fn SimulationResult::to_json(self : SimulationResult) -> String {
  let steps = self.steps
    .map(fn(item) {
      "{\"iteration\":" +
      item.iteration.to_string() +
      ",\"stable\":" +
      (if item.stable { "true" } else { "false" }) +
      ",\"changed\":[" +
      item.changed_signals
      .map(fn(name) { "\"" + json_escape(name) + "\"" })
      .join(",") +
      "]}"
    })
    .join(",")
  "{\"module\":\"" +
  json_escape(self.module_name) +
  "\",\"stable\":" +
  (if self.stable { "true" } else { "false" }) +
  ",\"oscillating\":" +
  (if self.oscillating { "true" } else { "false" }) +
  ",\"bindings\":[" +
  self.bindings.map(simulation_binding_json).join(",") +
  "],\"steps\":[" +
  steps +
  "]}"
}

///|
pub fn SimulationResult::to_markdown(self : SimulationResult) -> String {
  let rows = self.bindings
    .map(fn(item) {
      "| " +
      item.name +
      " | " +
      item.value.to_binary() +
      " | " +
      item.source +
      " |"
    })
    .join("\n")
  "# Simulation: " +
  self.module_name +
  "\n\n" +
  "- stable: `" +
  (if self.stable { "true" } else { "false" }) +
  "`\n" +
  "- iterations: `" +
  self.steps.length().to_string() +
  "`\n\n" +
  "| Signal | Value | Source |\n| --- | --- | --- |\n" +
  rows +
  "\n"
}

///|
pub fn simulation_vector_table() -> String {
  "bitwise=conservative; arithmetic=two_complement; condition=x_merges_branches; " +
  "termination=fixed_point_or_cap"
}
