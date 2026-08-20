///|
/// A production rule profile for projects that need a stricter RTL review.
pub struct AdvancedRuleProfile {
  name : String
  description : String
  codes : Array[String]
  default_severity : Severity
  checks_latches : Bool
  checks_clocking : Bool
  checks_interfaces : Bool
}

///|
/// Options for one deterministic rule-pack run.
pub struct RulePackConfig {
  profile : String
  enabled_codes : Array[String]
  disabled_codes : Array[String]
  max_findings : Int
  include_info : Bool
}

///|
/// Aggregated result used by CI and editor integrations.
pub struct RulePackResult {
  diagnostics : Array[Diagnostic]
  rules_run : Array[String]
  suppressed : Int
  modules : Int
}

///|
fn advanced_codes() -> Array[String] {
  [
    "A001", "A002", "A003", "A004", "A005", "A006", "A007", "A008", "A009", "A010",
    "A011", "A012", "A013", "A014", "A015", "A016", "A017", "A018", "A019", "A020",
  ]
}

///|
/// Return the stable list of checks exposed by the advanced pack.
pub fn advanced_rule_catalog() -> Array[String] {
  advanced_codes()
}

///|
pub fn advanced_rule_profile(name : String) -> AdvancedRuleProfile {
  let normalized = name.trim().to_lower()
  if normalized == "fast" {
    {
      name: "fast",
      description: "Low-noise checks for pre-commit feedback",
      codes: ["A001", "A003", "A005", "A009", "A010"],
      default_severity: Warning,
      checks_latches: false,
      checks_clocking: false,
      checks_interfaces: true,
    }
  } else if normalized == "interface" {
    {
      name: "interface",
      description: "Port, instance, width and reset boundary checks",
      codes: ["A004", "A005", "A006", "A007", "A009", "A013", "A014"],
      default_severity: Error,
      checks_latches: false,
      checks_clocking: true,
      checks_interfaces: true,
    }
  } else if normalized == "strict" {
    {
      name: "strict",
      description: "Complete structural and sequential RTL review",
      codes: advanced_codes(),
      default_severity: Error,
      checks_latches: true,
      checks_clocking: true,
      checks_interfaces: true,
    }
  } else {
    {
      name: "default",
      description: "Balanced checks for local development and CI",
      codes: [
        "A001", "A002", "A003", "A004", "A005", "A007", "A009", "A010", "A011", "A015",
      ],
      default_severity: Warning,
      checks_latches: true,
      checks_clocking: true,
      checks_interfaces: true,
    }
  }
}

///|
pub fn RulePackConfig::default() -> RulePackConfig {
  {
    profile: "default",
    enabled_codes: [],
    disabled_codes: [],
    max_findings: 1000,
    include_info: false,
  }
}

///|
pub fn RulePackConfig::with_max_findings(
  self : RulePackConfig,
  value : Int,
) -> RulePackConfig {
  { ..self, max_findings: value }
}

///|
pub fn RulePackConfig::with_info(
  self : RulePackConfig,
  enabled : Bool,
) -> RulePackConfig {
  { ..self, include_info: enabled }
}

///|
fn advanced_enabled(
  config : RulePackConfig,
  code : String,
  profile : AdvancedRuleProfile,
) -> Bool {
  if config.disabled_codes.contains(code) {
    false
  } else if config.enabled_codes.length() > 0 {
    config.enabled_codes.contains(code)
  } else {
    profile.codes.contains(code)
  }
}

///|
fn advanced_position(span : Span) -> (Int, Int) {
  (span.start.line, span.start.column)
}

///|
fn advanced_diag(
  code : String,
  severity : Severity,
  message : String,
  unit : Module,
  span : Span,
  signal : String?,
) -> Diagnostic {
  let position = advanced_position(span)
  let base = Diagnostic::new(code, severity, message, position.0, position.1)
  {
    ..base,
    signal,
    module_name: Some(unit.name),
    end_line: span.end.line,
    end_column: span.end.column,
  }
}

///|
fn advanced_expr_names(expr : Expr, result : Array[String]) -> Unit {
  match expr {
    Name(name) => if !result.contains(name) { result.push(name) }
    Unary(_, value) => advanced_expr_names(value, result)
    Binary(left, _, right) => {
      advanced_expr_names(left, result)
      advanced_expr_names(right, result)
    }
    Conditional(condition, yes, no) => {
      advanced_expr_names(condition, result)
      advanced_expr_names(yes, result)
      advanced_expr_names(no, result)
    }
    Concatenation(items) =>
      for item in items {
        advanced_expr_names(item, result)
      }
    Replication(_, value) => advanced_expr_names(value, result)
    Index(value, index) => {
      advanced_expr_names(value, result)
      advanced_expr_names(index, result)
    }
    PartSelect(value, left, right) => {
      advanced_expr_names(value, result)
      advanced_expr_names(left, result)
      advanced_expr_names(right, result)
    }
    Call(_, args) =>
      for item in args {
        advanced_expr_names(item, result)
      }
    Number(_) | StringLiteral(_) | Unknown(_) => ()
  }
}

///|
fn advanced_expr_is_constant(expr : Expr) -> Bool {
  match expr {
    Number(_) | StringLiteral(_) => true
    Unary(_, value) => advanced_expr_is_constant(value)
    Binary(left, _, right) =>
      advanced_expr_is_constant(left) && advanced_expr_is_constant(right)
    Conditional(condition, yes, no) =>
      advanced_expr_is_constant(condition) &&
      advanced_expr_is_constant(yes) &&
      advanced_expr_is_constant(no)
    Concatenation(items) => items.all(advanced_expr_is_constant)
    Replication(_, value) => advanced_expr_is_constant(value)
    Index(value, index) =>
      advanced_expr_is_constant(value) && advanced_expr_is_constant(index)
    PartSelect(value, left, right) =>
      advanced_expr_is_constant(value) &&
      advanced_expr_is_constant(left) &&
      advanced_expr_is_constant(right)
    Call(_, args) => args.all(advanced_expr_is_constant)
    Name(_) | Unknown(_) => false
  }
}

///|
fn advanced_statement_assignments(
  statements : Array[Statement],
  result : Array[Assignment],
) -> Unit {
  for statement in statements {
    match statement {
      ProceduralAssignment(assignment) => result.push(assignment)
      ConditionalStatement(_, yes, no) => {
        advanced_statement_assignments(yes, result)
        advanced_statement_assignments(no, result)
      }
      CaseStatement(_, items) =>
        for item in items {
          advanced_statement_assignments(item.statements, result)
        }
      BlockStatement(items) => advanced_statement_assignments(items, result)
      _ => ()
    }
  }
}

///|
fn advanced_statement_has_else(statements : Array[Statement]) -> Bool {
  for statement in statements {
    match statement {
      ConditionalStatement(_, _, no) => if no.length() > 0 { return true }
      CaseStatement(_, items) =>
        for item in items {
          if item.is_default {
            return true
          }
        }
      BlockStatement(items) =>
        if advanced_statement_has_else(items) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn advanced_statement_has_conditional(statements : Array[Statement]) -> Bool {
  for statement in statements {
    match statement {
      ConditionalStatement(_, _, _) | CaseStatement(_, _) => return true
      BlockStatement(items) =>
        if advanced_statement_has_conditional(items) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn advanced_signal(unit : Module, name : String) -> Signal? {
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
fn advanced_signal_width(signal : Signal) -> Int {
  match signal.width {
    Some(width) => width.bits()
    None => 1
  }
}

///|
fn advanced_rule_incomplete(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  if !profile.checks_latches {
    return result
  }
  for block in unit.always_blocks {
    if block.kind == AlwaysComb || block.kind == AlwaysLatch {
      let assignments : Array[Assignment] = []
      advanced_statement_assignments(block.statements, assignments)
      if assignments.length() > 0 &&
        advanced_statement_has_conditional(block.statements) &&
        !advanced_statement_has_else(block.statements) {
        result.push(
          advanced_diag(
            "A001",
            profile.default_severity,
            "combinational process has a conditional path without a default assignment",
            unit,
            block.span,
            None,
          ),
        )
      }
    }
  }
  result
}

///|
fn advanced_rule_latch_targets(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  if !profile.checks_latches {
    return result
  }
  for block in unit.always_blocks {
    if block.kind == AlwaysComb {
      let assignments : Array[Assignment] = []
      advanced_statement_assignments(block.statements, assignments)
      let targets : Array[String] = []
      for assignment in assignments {
        if !targets.contains(assignment.lhs) {
          targets.push(assignment.lhs)
        }
      }
      for target in targets {
        if !advanced_statement_has_else(block.statements) {
          result.push(
            advanced_diag(
              "A002",
              Warning,
              "output may infer a latch because all control paths are not assigned: " +
              target,
              unit,
              block.span,
              Some(target),
            ),
          )
        }
      }
    }
  }
  result
}

///|
fn advanced_rule_assignment_style(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  for block in unit.always_blocks {
    if block.kind == AlwaysPosedge ||
      block.kind == AlwaysNegedge ||
      block.kind == AlwaysFF {
      let assignments : Array[Assignment] = []
      advanced_statement_assignments(block.statements, assignments)
      for assignment in assignments {
        if assignment.operator == "=" {
          result.push(
            advanced_diag(
              "A003",
              profile.default_severity,
              "clocked process uses blocking assignment; use nonblocking assignment for state",
              unit,
              assignment.span,
              Some(assignment.lhs),
            ),
          )
        }
      }
    }
  }
  result
}

///|
fn advanced_rule_case_defaults(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for block in unit.always_blocks {
    let stack : Array[Statement] = block.statements.copy()
    while stack.length() > 0 {
      match stack.pop() {
        None => ()
        Some(statement) =>
          match statement {
            CaseStatement(_, items) => {
              let has_default = items.any(fn(item) { item.is_default })
              if !has_default {
                result.push(
                  advanced_diag(
                    "A004",
                    Error,
                    "case statement has no default branch",
                    unit,
                    block.span,
                    None,
                  ),
                )
              }
              for item in items {
                for child in item.statements {
                  stack.push(child)
                }
              }
            }
            ConditionalStatement(_, yes, no) =>
              for child in yes + no {
                stack.push(child)
              }
            BlockStatement(items) =>
              for child in items {
                stack.push(child)
              }
            _ => ()
          }
      }
    }
  }
  result
}

///|
fn advanced_rule_reset_names(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  if !profile.checks_clocking {
    return result
  }
  for block in unit.always_blocks {
    if block.kind == AlwaysPosedge ||
      block.kind == AlwaysNegedge ||
      block.kind == AlwaysFF {
      for sensitivity in block.sensitivity {
        let name = sensitivity.signal.to_lower()
        if (name.contains("reset") || name.has_prefix("rst")) &&
          sensitivity.edge is None {
          result.push(
            advanced_diag(
              "A005",
              Warning,
              "reset-like signal is used without an explicit edge qualifier",
              unit,
              block.span,
              Some(sensitivity.signal),
            ),
          )
        }
      }
    }
  }
  result
}

///|
fn advanced_rule_input_read(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  let reads : Array[String] = []
  for assignment in unit.assignments {
    match assignment.rhs_expr {
      Some(expr) => advanced_expr_names(expr, reads)
      None => ()
    }
  }
  for block in unit.always_blocks {
    for assignment in block.statements {
      match assignment {
        ProceduralAssignment(item) =>
          match item.rhs_expr {
            Some(expr) => advanced_expr_names(expr, reads)
            None => ()
          }
        _ => ()
      }
    }
  }
  for signal in unit.ports {
    match signal.direction {
      Some(Input) =>
        if !reads.contains(signal.name) {
          result.push(
            advanced_diag(
              "A006",
              Info,
              "input port is declared but never read by a known assignment",
              unit,
              signal.span,
              Some(signal.name),
            ),
          )
        }
      _ => ()
    }
  }
  result
}

///|
fn advanced_rule_fanout(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for signal in unit.ports + unit.signals {
    let uses = unit.assignments.fold(init=0, fn(total, assignment) {
      if assignment.rhs.contains(signal.name) {
        total + 1
      } else {
        total
      }
    })
    let block_uses = unit.always_blocks.fold(init=0, fn(total, block) {
      if block.body.contains(signal.name) {
        total + 1
      } else {
        total
      }
    })
    let total = uses + block_uses
    if total >= 8 {
      result.push(
        advanced_diag(
          "A007",
          Warning,
          "signal fanout exceeds the default review threshold: " +
          total.to_string(),
          unit,
          signal.span,
          Some(signal.name),
        ),
      )
    }
  }
  result
}

///|
fn advanced_rule_constant_conditions(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for block in unit.always_blocks {
    advanced_visit_constant_statements(unit, block.statements, result)
  }
  result
}

///|
fn advanced_visit_constant_statements(
  unit : Module,
  statements : Array[Statement],
  result : Array[Diagnostic],
) -> Unit {
  for statement in statements {
    match statement {
      ConditionalStatement(condition, yes, no) => {
        if advanced_expr_is_constant(condition) {
          result.push(
            advanced_diag(
              "A008",
              Info,
              "conditional expression is constant and can be simplified",
              unit,
              unit.span,
              None,
            ),
          )
        }
        advanced_visit_constant_statements(unit, yes, result)
        advanced_visit_constant_statements(unit, no, result)
      }
      CaseStatement(expression, items) => {
        if advanced_expr_is_constant(expression) {
          result.push(
            advanced_diag(
              "A008",
              Info,
              "case selector is constant",
              unit,
              unit.span,
              None,
            ),
          )
        }
        for item in items {
          advanced_visit_constant_statements(unit, item.statements, result)
        }
      }
      BlockStatement(items) =>
        advanced_visit_constant_statements(unit, items, result)
      _ => ()
    }
  }
}

///|
fn advanced_rule_instance_ports(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  if !profile.checks_interfaces {
    return result
  }
  for instance in unit.instances {
    if instance.connections.length() == 0 {
      result.push(
        advanced_diag(
          "A009",
          Error,
          "instance has no explicit port connections",
          unit,
          instance.span,
          Some(instance.instance_name),
        ),
      )
    }
    let names : Array[String] = []
    for connection in instance.connections {
      if names.contains(connection.port) {
        result.push(
          advanced_diag(
            "A009",
            Error,
            "instance connects the same port more than once: " + connection.port,
            unit,
            connection.span,
            Some(instance.instance_name),
          ),
        )
      } else {
        names.push(connection.port)
      }
    }
  }
  result
}

///|
fn advanced_rule_names(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for signal in unit.ports + unit.signals {
    if signal.name.length() == 0 {
      result.push(
        advanced_diag(
          "A010",
          Error,
          "signal has an empty name",
          unit,
          signal.span,
          None,
        ),
      )
    } else if signal.name.contains(" ") || signal.name.contains("-") {
      result.push(
        advanced_diag(
          "A010",
          Warning,
          "signal name contains a separator that complicates tooling: " +
          signal.name,
          unit,
          signal.span,
          Some(signal.name),
        ),
      )
    }
  }
  result
}

///|
fn advanced_rule_sensitivity(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for block in unit.always_blocks {
    if block.kind == AlwaysLevel &&
      block.sensitivity.length() == 0 &&
      block.body.contains("if") {
      result.push(
        advanced_diag(
          "A011",
          Warning,
          "level-sensitive process has no parsed sensitivity item",
          unit,
          block.span,
          None,
        ),
      )
    }
  }
  result
}

///|
fn advanced_rule_multiple_drivers(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  let counts : Map[String, Int] = Map([])
  for assignment in unit.assignments {
    counts[assignment.lhs] = counts.get(assignment.lhs).unwrap_or(0) + 1
  }
  for block in unit.always_blocks {
    let assignments : Array[Assignment] = []
    advanced_statement_assignments(block.statements, assignments)
    for assignment in assignments {
      counts[assignment.lhs] = counts.get(assignment.lhs).unwrap_or(0) + 1
    }
  }
  for item in counts.keys() {
    match counts.get(item) {
      Some(count) =>
        if count > 1 {
          match advanced_signal(unit, item) {
            Some(signal) =>
              result.push(
                advanced_diag(
                  "A012",
                  Error,
                  "signal has multiple assignment drivers: " + count.to_string(),
                  unit,
                  signal.span,
                  Some(item),
                ),
              )
            None => ()
          }
        }
      None => ()
    }
  }
  result
}

///|
fn advanced_rule_widths(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for assignment in unit.assignments {
    match advanced_signal(unit, assignment.lhs) {
      Some(target) =>
        match assignment.rhs_expr {
          Some(expr) => {
            let names : Array[String] = []
            advanced_expr_names(expr, names)
            for name in names {
              match advanced_signal(unit, name) {
                Some(source) => {
                  let target_width = advanced_signal_width(target)
                  let source_width = advanced_signal_width(source)
                  if target_width != source_width &&
                    !assignment.rhs.contains("{") {
                    result.push(
                      advanced_diag(
                        "A013",
                        Warning,
                        "assignment crosses signal widths without an explicit resize: " +
                        source_width.to_string() +
                        " -> " +
                        target_width.to_string(),
                        unit,
                        assignment.span,
                        Some(assignment.lhs),
                      ),
                    )
                  }
                }
                None => ()
              }
            }
          }
          None => ()
        }
      None => ()
    }
  }
  result
}

///|
fn advanced_rule_output_drivers(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  let driven : Array[String] = []
  for assignment in unit.assignments {
    if !driven.contains(assignment.lhs) {
      driven.push(assignment.lhs)
    }
  }
  for block in unit.always_blocks {
    let assignments : Array[Assignment] = []
    advanced_statement_assignments(block.statements, assignments)
    for assignment in assignments {
      if !driven.contains(assignment.lhs) {
        driven.push(assignment.lhs)
      }
    }
  }
  for signal in unit.ports {
    match signal.direction {
      Some(Output) =>
        if !driven.contains(signal.name) {
          result.push(
            advanced_diag(
              "A014",
              Error,
              "output port has no assignment driver",
              unit,
              signal.span,
              Some(signal.name),
            ),
          )
        }
      _ => ()
    }
  }
  result
}

///|
fn advanced_rule_clock_signal(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for block in unit.always_blocks {
    if block.kind == AlwaysPosedge ||
      block.kind == AlwaysNegedge ||
      block.kind == AlwaysFF {
      for sensitivity in block.sensitivity {
        let lower = sensitivity.signal.to_lower()
        if lower.contains("clk") || lower.contains("clock") {
          if sensitivity.edge is None {
            result.push(
              advanced_diag(
                "A015",
                Warning,
                "clock-like sensitivity item has no edge qualifier",
                unit,
                block.span,
                Some(sensitivity.signal),
              ),
            )
          }
        }
      }
    }
  }
  result
}

///|
fn advanced_rule_parameter_ranges(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for parameter in unit.parameters {
    match parameter.width {
      Some(width) =>
        if width.bits() <= 0 {
          result.push(
            advanced_diag(
              "A016",
              Error,
              "parameter width must contain at least one bit",
              unit,
              parameter.span,
              Some(parameter.name),
            ),
          )
        }
      None => ()
    }
    if parameter.value.trim().length() == 0 {
      result.push(
        advanced_diag(
          "A016",
          Warning,
          "parameter has an empty default expression",
          unit,
          parameter.span,
          Some(parameter.name),
        ),
      )
    }
  }
  result
}

///|
fn advanced_rule_instance_names(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  let names : Array[String] = []
  for instance in unit.instances {
    if names.contains(instance.instance_name) {
      result.push(
        advanced_diag(
          "A017",
          Error,
          "instance name is duplicated: " + instance.instance_name,
          unit,
          instance.span,
          Some(instance.instance_name),
        ),
      )
    }
    names.push(instance.instance_name)
    if instance.instance_name.to_lower().has_prefix("u_") == false {
      result.push(
        advanced_diag(
          "A017",
          Info,
          "instance name does not use the conventional u_ prefix",
          unit,
          instance.span,
          Some(instance.instance_name),
        ),
      )
    }
  }
  result
}

///|
fn advanced_rule_blocking_mix(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for block in unit.always_blocks {
    let assignments : Array[Assignment] = []
    advanced_statement_assignments(block.statements, assignments)
    let saw_blocking = assignments.any(fn(item) { item.operator == "=" })
    let saw_nonblocking = assignments.any(fn(item) { item.operator == "<=" })
    if saw_blocking && saw_nonblocking {
      result.push(
        advanced_diag(
          "A018",
          Warning,
          "one process mixes blocking and nonblocking assignments",
          unit,
          block.span,
          None,
        ),
      )
    }
  }
  result
}

///|
fn advanced_rule_signal_kind(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for signal in unit.signals {
    if signal.kind == Reg {
      match signal.direction {
        Some(Input) =>
          result.push(
            advanced_diag(
              "A019",
              Warning,
              "input is declared as reg; use a net or explicit variable intent",
              unit,
              signal.span,
              Some(signal.name),
            ),
          )
        _ => ()
      }
    }
  }
  result
}

///|
fn advanced_rule_comment_markers(
  unit : Module,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  ignore(profile)
  for block in unit.always_blocks {
    if block.body.contains("TODO") || block.body.contains("FIXME") {
      result.push(
        advanced_diag(
          "A020",
          Info,
          "process contains an unresolved implementation marker",
          unit,
          block.span,
          None,
        ),
      )
    }
  }
  result
}

///|
fn advanced_run_module(
  unit : Module,
  config : RulePackConfig,
  profile : AdvancedRuleProfile,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  let append = fn(code : String, items : Array[Diagnostic]) -> Unit {
    if advanced_enabled(config, code, profile) {
      for item in items {
        if item.severity != Info || config.include_info {
          result.push(item)
        }
      }
    }
  }
  append("A001", advanced_rule_incomplete(unit, profile))
  append("A002", advanced_rule_latch_targets(unit, profile))
  append("A003", advanced_rule_assignment_style(unit, profile))
  append("A004", advanced_rule_case_defaults(unit, profile))
  append("A005", advanced_rule_reset_names(unit, profile))
  append("A006", advanced_rule_input_read(unit, profile))
  append("A007", advanced_rule_fanout(unit, profile))
  append("A008", advanced_rule_constant_conditions(unit, profile))
  append("A009", advanced_rule_instance_ports(unit, profile))
  append("A010", advanced_rule_names(unit, profile))
  append("A011", advanced_rule_sensitivity(unit, profile))
  append("A012", advanced_rule_multiple_drivers(unit, profile))
  append("A013", advanced_rule_widths(unit, profile))
  append("A014", advanced_rule_output_drivers(unit, profile))
  append("A015", advanced_rule_clock_signal(unit, profile))
  append("A016", advanced_rule_parameter_ranges(unit, profile))
  append("A017", advanced_rule_instance_names(unit, profile))
  append("A018", advanced_rule_blocking_mix(unit, profile))
  append("A019", advanced_rule_signal_kind(unit, profile))
  append("A020", advanced_rule_comment_markers(unit, profile))
  result
}

///|
pub fn run_rule_pack(
  design : Design,
  config : RulePackConfig,
) -> RulePackResult {
  let profile = advanced_rule_profile(config.profile)
  let diagnostics : Array[Diagnostic] = []
  let suppressed = 0
  for unit in design.modules {
    let module_items = advanced_run_module(unit, config, profile)
    for item in module_items {
      if config.max_findings <= 0 || diagnostics.length() < config.max_findings {
        diagnostics.push(item)
      }
    }
  }
  {
    diagnostics,
    rules_run: profile.codes,
    suppressed,
    modules: design.modules.length(),
  }
}

///|
pub fn rule_pack_source(
  source : String,
  config : RulePackConfig,
) -> RulePackResult {
  run_rule_pack(parse(source), config)
}

///|
pub fn RulePackResult::error_count(self : RulePackResult) -> Int {
  self.diagnostics.fold(init=0, fn(total, item) {
    if item.severity == Error {
      total + 1
    } else {
      total
    }
  })
}

///|
pub fn RulePackResult::warning_count(self : RulePackResult) -> Int {
  self.diagnostics.fold(init=0, fn(total, item) {
    if item.severity == Warning {
      total + 1
    } else {
      total
    }
  })
}

///|
pub fn RulePackResult::has_blocking_errors(self : RulePackResult) -> Bool {
  self.error_count() > 0
}

///|
pub fn RulePackResult::to_json(self : RulePackResult) -> String {
  "{\"modules\":" +
  self.modules.to_string() +
  ",\"rules_run\":[" +
  self.rules_run.map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "],\"suppressed\":" +
  self.suppressed.to_string() +
  ",\"errors\":" +
  self.error_count().to_string() +
  ",\"warnings\":" +
  self.warning_count().to_string() +
  ",\"diagnostics\":" +
  diagnostics_json(self.diagnostics) +
  "}"
}

///|
pub fn RulePackResult::to_markdown(self : RulePackResult) -> String {
  let output = "## Advanced RTL rule pack\n\n" +
    "- modules: " +
    self.modules.to_string() +
    "\n" +
    "- errors: " +
    self.error_count().to_string() +
    "\n" +
    "- warnings: " +
    self.warning_count().to_string() +
    "\n" +
    "- suppressed: " +
    self.suppressed.to_string() +
    "\n\n"
  output + diagnostics_markdown(self.diagnostics)
}

///|
pub fn rule_pack_contract() -> String {
  "rules=A001..A020; profiles=fast,default,interface,strict; output=diagnostic,json,markdown"
}
