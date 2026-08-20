///|
/// A small assertion property understood by the RTL review engine.
pub enum PropertyKind {
  PropertyAlways
  PropertyNever
  PropertyImplies
  PropertyEventually
  PropertyStable
  PropertyUnknown
} derive(Eq)

///|
/// A parsed assertion or an inferred structural invariant.
pub struct FormalProperty {
  name : String
  kind : PropertyKind
  clock : String?
  antecedent : String
  consequent : String
  source_line : Int
  explicit : Bool
}

///|
/// A concrete failing observation from a bounded trace.
pub struct FormalViolation {
  property_name : String
  iteration : Int
  message : String
  signal : String?
}

///|
/// A formal-style bounded analysis result.
pub struct FormalReport {
  properties : Array[FormalProperty]
  proven : Array[String]
  violated : Array[FormalViolation]
  unknown : Array[String]
  bound : Int
}

///|
fn formal_kind_text(kind : PropertyKind) -> String {
  match kind {
    PropertyAlways => "always"
    PropertyNever => "never"
    PropertyImplies => "implies"
    PropertyEventually => "eventually"
    PropertyStable => "stable"
    PropertyUnknown => "unknown"
  }
}

///|
fn formal_property_kind(text : String) -> PropertyKind {
  match text.trim().to_owned() {
    "always" | "assert" => PropertyAlways
    "never" | "assume_not" => PropertyNever
    "implies" | "|->" => PropertyImplies
    "eventually" | "##" => PropertyEventually
    "stable" => PropertyStable
    _ => PropertyUnknown
  }
}

///|
fn formal_trim_wrappers(text : String) -> String {
  let mut result = text.trim().to_owned()
  while result.has_prefix("(") && result.has_suffix(")") && result.length() > 1 {
    result = result[1:result.length() - 1].to_owned().trim().to_owned()
  }
  result
}

///|
fn formal_remove_prefix(text : String, prefix : String) -> String {
  if text.has_prefix(prefix) {
    text[prefix.length():].to_owned()
  } else {
    text
  }
}

///|
fn formal_remove_suffix(text : String, suffix : String) -> String {
  if text.has_suffix(suffix) {
    text[:text.length() - suffix.length()].to_owned()
  } else {
    text
  }
}

///|
fn formal_split_operator(text : String, operator : String) -> (String, String)? {
  let chars = text.to_array()
  let wanted = operator.to_array()
  if wanted.length() == 0 {
    return None
  }
  let mut depth = 0
  let mut i = 0
  while i + wanted.length() <= chars.length() {
    if chars[i] == '(' || chars[i] == '[' || chars[i] == '{' {
      depth += 1
    } else if chars[i] == ')' || chars[i] == ']' || chars[i] == '}' {
      depth -= 1
    }
    if depth == 0 {
      let mut equal = true
      for j in 0..<wanted.length() {
        if chars[i + j] != wanted[j] {
          equal = false
          break
        }
      }
      if equal {
        return Some(
          (
            text[:i].to_owned().trim().to_owned(),
            text[i + wanted.length():].to_owned().trim().to_owned(),
          ),
        )
      }
    }
    i += 1
  }
  None
}

///|
fn formal_clock_from_text(text : String) -> String? {
  match text.split_once("@(") {
    Some((_, rest)) =>
      match rest.split_once(")") {
        Some((clock, _)) => {
          let value = clock.trim().to_owned()
          Some(
            formal_remove_prefix(
              formal_remove_prefix(value, "posedge "),
              "negedge ",
            ),
          )
        }
        None => None
      }
    None => None
  }
}

///|
fn formal_property_from_text(
  text : String,
  line : Int,
  index : Int,
) -> FormalProperty {
  let normalized = text.trim().to_owned()
  let body = formal_remove_prefix(
      formal_remove_prefix(
        formal_remove_prefix(normalized, "assert property"),
        "assume property",
      ),
      "cover property",
    )
    .trim()
    .to_owned()
  let clock = formal_clock_from_text(body)
  let after_clock = match body.split_once(")") {
    Some((_, rest)) => rest.to_owned()
    None => body
  }
  let expression = formal_trim_wrappers(
    formal_remove_suffix(after_clock.trim().to_owned(), ";"),
  )
  match formal_split_operator(expression, "|->") {
    Some((antecedent, consequent)) =>
      {
        name: "property_" + index.to_string(),
        kind: PropertyImplies,
        clock,
        antecedent,
        consequent,
        source_line: line,
        explicit: true,
      }
    None => {
      let kind = if normalized.contains("never") {
        PropertyNever
      } else {
        formal_property_kind("always")
      }
      {
        name: "property_" + index.to_string(),
        kind,
        clock,
        antecedent: expression,
        consequent: "",
        source_line: line,
        explicit: true,
      }
    }
  }
}

///|
/// Parse common assertion property lines from Verilog/SystemVerilog text.
pub fn parse_formal_properties(source : String) -> Array[FormalProperty] {
  let result : Array[FormalProperty] = []
  let mut index = 0
  for line, raw_line in source.split("\n") {
    let text = raw_line.trim().to_owned()
    if text.contains("assert property") ||
      text.contains("assume property") ||
      text.contains("cover property") {
      result.push(formal_property_from_text(text, line + 1, index))
      index += 1
    }
  }
  result
}

///|
fn formal_infer_properties(design : Design) -> Array[FormalProperty] {
  let result : Array[FormalProperty] = []
  let mut index = 1000
  for unit in design.modules {
    for port in unit.ports {
      if port.direction == Some(Output) {
        result.push({
          name: "inferred_output_defined_" + unit.name + "_" + port.name,
          kind: PropertyStable,
          clock: None,
          antecedent: port.name,
          consequent: "defined",
          source_line: port.span.start.line,
          explicit: false,
        })
        index += 1
      }
    }
    for assignment in unit.assignments {
      if assignment.rhs_expr is Some(expr) && expr.references().length() > 0 {
        result.push({
          name: "inferred_assignment_reachable_" + index.to_string(),
          kind: PropertyImplies,
          clock: None,
          antecedent: expr.references().join(" && "),
          consequent: assignment.lhs,
          source_line: assignment.span.start.line,
          explicit: false,
        })
        index += 1
      }
    }
  }
  result
}

///|
fn formal_binding_truth(
  bindings : Array[SimulationBinding],
  name : String,
) -> LogicBit {
  match simulation_binding(bindings, name) {
    Some(item) => item.value.truthy()
    None => LogicUnknown
  }
}

///|
fn formal_expression_truth(
  expression : String,
  unit : Module,
  bindings : Array[SimulationBinding],
) -> LogicBit {
  let parsed = parse(
    "module formal_expr; assign _formal = " + expression + "; endmodule",
  )
  match parsed.modules.get(0) {
    Some(parsed_unit) =>
      match parsed_unit.assignments.get(0) {
        Some(assignment) =>
          assignment.rhs_expr
          .map(fn(expr) { evaluate_logic_expr(expr, unit, bindings).truthy() })
          .unwrap_or(LogicUnknown)
        None => formal_binding_truth(bindings, expression)
      }
    None => formal_binding_truth(bindings, expression)
  }
}

///|
fn formal_find_violation(
  property : FormalProperty,
  unit : Module,
  trace : SimulationResult,
) -> FormalViolation? {
  for step in trace.steps {
    let antecedent = formal_expression_truth(
      property.antecedent,
      unit,
      step.values,
    )
    match property.kind {
      PropertyAlways | PropertyStable =>
        if antecedent == LogicZero || antecedent == LogicUnknown {
          return Some({
            property_name: property.name,
            iteration: step.iteration,
            message: "property is not proven on the bounded trace",
            signal: Some(property.antecedent),
          })
        }
      PropertyNever =>
        if antecedent == LogicOne {
          return Some({
            property_name: property.name,
            iteration: step.iteration,
            message: "forbidden condition became true",
            signal: Some(property.antecedent),
          })
        }
      PropertyImplies =>
        if antecedent == LogicOne {
          let consequent = formal_expression_truth(
            property.consequent,
            unit,
            step.values,
          )
          if consequent != LogicOne {
            return Some({
              property_name: property.name,
              iteration: step.iteration,
              message: "implication consequent is false or unknown",
              signal: Some(property.consequent),
            })
          }
        }
      PropertyEventually => if antecedent == LogicOne { return None }
      PropertyUnknown =>
        return Some({
          property_name: property.name,
          iteration: step.iteration,
          message: "unsupported property form",
          signal: None,
        })
    }
  }
  if property.kind == PropertyEventually {
    Some({
      property_name: property.name,
      iteration: trace.steps.length(),
      message: "eventual condition was not observed",
      signal: Some(property.antecedent),
    })
  } else {
    None
  }
}

///|
/// Check explicit and inferred properties against a bounded four-state trace.
pub fn formal_check(
  source : String,
  module_name : String,
  inputs : Array[(String, LogicVector)],
  bound : Int,
  include_inferred : Bool,
) -> FormalReport {
  let design = parse(source)
  let unit = design.modules.filter(fn(item) { item.name == module_name }).get(0)
  let properties = parse_formal_properties(source)
  let all_properties = if include_inferred {
    properties + formal_infer_properties(design)
  } else {
    properties
  }
  match unit {
    Some(target_unit) => {
      let trace = simulate_module(target_unit, inputs, bound)
      let proven : Array[String] = []
      let violated : Array[FormalViolation] = []
      let unknown : Array[String] = []
      for property in all_properties {
        match formal_find_violation(property, target_unit, trace) {
          Some(violation) =>
            if violation.message.contains("unsupported") ||
              violation.message.contains("unknown") {
              unknown.push(property.name)
            } else {
              violated.push(violation)
            }
          None => proven.push(property.name)
        }
      }
      {
        properties: all_properties,
        proven,
        violated,
        unknown,
        bound: if bound < 1 {
          1
        } else {
          bound
        },
      }
    }
    None =>
      {
        properties: all_properties,
        proven: [],
        violated: [],
        unknown: [module_name],
        bound,
      }
  }
}

///|
pub fn FormalReport::is_proven(self : FormalReport) -> Bool {
  self.violated.length() == 0 && self.unknown.length() == 0
}

///|
pub fn FormalReport::property(
  self : FormalReport,
  name : String,
) -> FormalProperty? {
  self.properties.filter(fn(item) { item.name == name }).get(0)
}

///|
pub fn FormalReport::diagnostics(self : FormalReport) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  for item in self.violated {
    result.push(
      Diagnostic::new("FORMAL001", Error, item.message, item.iteration + 1, 1),
    )
  }
  for name in self.unknown {
    result.push(
      Diagnostic::new(
        "FORMAL002",
        Warning,
        "property could not be evaluated: " + name,
        1,
        1,
      ),
    )
  }
  result
}

///|
pub fn FormalReport::to_json(self : FormalReport) -> String {
  let properties = self.properties
    .map(fn(item) {
      "{\"name\":\"" +
      json_escape(item.name) +
      "\",\"kind\":\"" +
      formal_kind_text(item.kind) +
      "\",\"line\":" +
      item.source_line.to_string() +
      "\",\"explicit\":" +
      (if item.explicit { "true" } else { "false" }) +
      "}"
    })
    .join(",")
  let violations = self.violated
    .map(fn(item) {
      "{\"property\":\"" +
      json_escape(item.property_name) +
      "\",\"iteration\":" +
      item.iteration.to_string() +
      ",\"message\":\"" +
      json_escape(item.message) +
      "\"}"
    })
    .join(",")
  "{\"proven\":[" +
  self.proven.map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "],\"unknown\":[" +
  self.unknown.map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "],\"violations\":[" +
  violations +
  "],\"properties\":[" +
  properties +
  "]}"
}

///|
pub fn FormalReport::to_markdown(self : FormalReport) -> String {
  let rows = self.properties
    .map(fn(item) {
      let status = if self.proven.contains(item.name) {
        "proven"
      } else if self.violated.any(fn(violation) {
          violation.property_name == item.name
        }) {
        "violated"
      } else {
        "unknown"
      }
      "| " +
      item.name +
      " | " +
      formal_kind_text(item.kind) +
      " | " +
      status +
      " | " +
      item.source_line.to_string() +
      " |"
    })
    .join("\n")
  "# Formal bounded report\n\n" +
  "- proven: `" +
  self.proven.length().to_string() +
  "`\n" +
  "- violated: `" +
  self.violated.length().to_string() +
  "`\n" +
  "- unknown: `" +
  self.unknown.length().to_string() +
  "`\n" +
  "- bound: `" +
  self.bound.to_string() +
  "`\n\n" +
  "| Property | Kind | Status | Line |\n| --- | --- | --- | ---: |\n" +
  rows +
  "\n"
}

///|
pub fn formal_contract() -> String {
  "properties=always,never,implies,eventually,stable; engine=bounded_four_state_trace; " +
  "unknown=x_or_unsupported; inferred=output_reachability_and_assignment_dependencies"
}
