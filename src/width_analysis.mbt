///|
/// A width expectation attached to an expression location.
pub struct WidthFact {
  expression : String
  actual : Int?
  expected : Int?
  source_line : Int
  source_column : Int
}

///|
/// Width information for every assignment in a module.
pub struct WidthReport {
  facts : Array[WidthFact]
  unknown : Int
  mismatches : Int
}

///|
fn assignment_width_fact(unit : Module, assignment : Assignment) -> WidthFact {
  let actual = match assignment.rhs_expr {
    Some(expr) => expr.width(unit)
    None => None
  }
  let expected = match assignment.lhs_expr {
    Some(expr) => expr.width(unit)
    None => unit.width_of(assignment.lhs)
  }
  {
    expression: assignment.lhs + " = " + assignment.rhs,
    actual,
    expected,
    source_line: assignment.span.start.line,
    source_column: assignment.span.start.column,
  }
}

///|
/// Analyze assignment widths without emitting diagnostics.
pub fn Module::width_report(self : Module) -> WidthReport {
  let facts : Array[WidthFact] = []
  let mut unknown = 0
  let mut mismatches = 0
  for assignment in self.assignments {
    let fact = assignment_width_fact(self, assignment)
    match (fact.actual, fact.expected) {
      (Some(actual), Some(expected)) if actual != expected => mismatches += 1
      (None, _) | (_, None) => unknown += 1
      _ => ()
    }
    facts.push(fact)
  }
  { facts, unknown, mismatches }
}

///|
/// Serialize width facts for an editor panel.
pub fn WidthReport::to_json(self : WidthReport) -> String {
  let facts = self.facts
    .map(fn(fact) {
      let actual = match fact.actual {
        Some(value) => value.to_string()
        None => "null"
      }
      let expected = match fact.expected {
        Some(value) => value.to_string()
        None => "null"
      }
      "{\"expression\":\"" +
      fact.expression +
      "\",\"actual\":" +
      actual +
      ",\"expected\":" +
      expected +
      ",\"line\":" +
      fact.source_line.to_string() +
      ",\"column\":" +
      fact.source_column.to_string() +
      "}"
    })
    .join(",")
  "{\"unknown\":" +
  self.unknown.to_string() +
  ",\"mismatches\":" +
  self.mismatches.to_string() +
  ",\"facts\":[" +
  facts +
  "]}"
}

///|
/// Return a report for all modules in a design.
pub fn design_width_reports(design : Design) -> String {
  let mut out = ""
  for unit in design.modules {
    out += unit.name + "\t" + unit.width_report().to_json() + "\n"
  }
  out
}

///|
/// Check whether an expression is a scalar condition.
pub fn expression_is_scalar(expr : Expr, unit : Module) -> Bool {
  match expr.width(unit) {
    Some(width) => width == 1
    None => false
  }
}

///|
/// Return a conservative width for a Verilog literal.
pub fn literal_width(text : String) -> Int? {
  match text.split_once("'") {
    Some((prefix, suffix)) => {
      let width = evaluate_number(prefix.to_owned())
      match width {
        Some(value) if value > 0 => Some(value)
        _ => if suffix.length() > 0 { Some(1) } else { None }
      }
    }
    None => evaluate_number(text).map(fn(_) { 32 })
  }
}

///|
/// Determine whether a number contains unknown four-state digits.
pub fn literal_has_unknown(text : String) -> Bool {
  text.contains("x") ||
  text.contains("X") ||
  text.contains("z") ||
  text.contains("Z") ||
  text.contains("?")
}

///|
/// Return the number of bits contributed by a concatenation.
pub fn concatenation_width(items : Array[Expr], unit : Module) -> Int? {
  let mut total = 0
  for item in items {
    match item.width(unit) {
      Some(width) => total += width
      None => return None
    }
  }
  Some(total)
}

///|
/// Return all assignment expressions whose right-hand side is wider than the l-value.
pub fn widening_assignments(unit : Module) -> Array[Assignment] {
  unit.assignments.filter(fn(assignment) {
    match (assignment.lhs_expr, assignment.rhs_expr) {
      (Some(left), Some(right)) =>
        match (left.width(unit), right.width(unit)) {
          (Some(l), Some(r)) => r > l
          _ => false
        }
      _ => false
    }
  })
}

///|
/// Return all assignments that narrow a value.
pub fn narrowing_assignments(unit : Module) -> Array[Assignment] {
  unit.assignments.filter(fn(assignment) {
    match (assignment.lhs_expr, assignment.rhs_expr) {
      (Some(left), Some(right)) =>
        match (left.width(unit), right.width(unit)) {
          (Some(l), Some(r)) => l > r
          _ => false
        }
      _ => false
    }
  })
}

///|
/// Emit explicit diagnostics for widening and narrowing assignments.
pub fn check_width_policy(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for assignment in widening_assignments(unit) {
    add_diagnostic(
      config,
      result,
      diagnostic_for_rule(
        "RTL050",
        Warning,
        "right-hand side is wider than the assignment target",
        assignment.span,
        Some(assignment.lhs),
        unit.name,
      ),
    )
  }
  for assignment in narrowing_assignments(unit) {
    add_diagnostic(
      config,
      result,
      diagnostic_for_rule(
        "RTL051",
        Info,
        "assignment narrows the right-hand side value",
        assignment.span,
        Some(assignment.lhs),
        unit.name,
      ),
    )
  }
}

///|
/// Return a compact width policy summary.
pub fn width_policy_summary(unit : Module) -> String {
  let widening = widening_assignments(unit).length()
  let narrowing = narrowing_assignments(unit).length()
  "widening=" +
  widening.to_string() +
  " narrowing=" +
  narrowing.to_string() +
  " unknown=" +
  unit.width_report().unknown.to_string()
}
