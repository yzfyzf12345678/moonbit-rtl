///|
fn signal_by_name(unit : Module, name : String) -> Signal? {
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
fn module_by_name(design : Design, name : String) -> Module? {
  for candidate in design.modules {
    if candidate.name == name {
      return Some(candidate)
    }
  }
  None
}

///|
fn port_by_name(unit : Module, name : String) -> Signal? {
  for port in unit.ports {
    if port.name == name {
      return Some(port)
    }
  }
  None
}

///|
fn connection_by_port(
  instance : ModuleInstance,
  name : String,
) -> PortConnection? {
  for connection in instance.connections {
    if connection.port == name {
      return Some(connection)
    }
  }
  None
}

///|
fn is_builtin_reference(name : String) -> Bool {
  name == "$signed" ||
  name == "$unsigned" ||
  name == "$clog2" ||
  name == "$bits" ||
  name == "$itor" ||
  name == "$rtoi" ||
  name == "and" ||
  name == "or" ||
  name == "xor" ||
  name == "not"
}

///|
fn has_setting(config : CheckConfig, code : String) -> RuleSetting? {
  for setting in config.rules {
    if setting.code == code {
      return Some(setting)
    }
  }
  None
}

///|
fn configured_diagnostic(
  config : CheckConfig,
  item : Diagnostic,
) -> Diagnostic? {
  if item.severity == Info && !config.include_info {
    return None
  }
  match has_setting(config, item.code) {
    Some(setting) if !setting.enabled => None
    Some(setting) =>
      match setting.severity {
        Some(severity) => Some({ ..item, severity, })
        None => Some(item)
      }
    None => Some(item)
  }
}

///|
fn add_diagnostic(
  config : CheckConfig,
  result : Array[Diagnostic],
  item : Diagnostic,
) -> Unit {
  if result.length() >= config.max_diagnostics {
    return
  }
  match configured_diagnostic(config, item) {
    Some(value) => result.push(value)
    None => ()
  }
}

///|
fn module_diagnostic(item : Diagnostic, name : String) -> Diagnostic {
  { ..item, module_name: Some(name) }
}

///|
fn diagnostic_for_rule(
  code : String,
  severity : Severity,
  message : String,
  span : Span,
  signal : String?,
  module_name : String,
) -> Diagnostic {
  module_diagnostic(
    diagnostic(code, severity, message, span, signal),
    module_name,
  )
}

///|
fn collect_expression_references(unit : Module) -> Array[String] {
  let result : Array[String] = []
  fn add_expression(expr : Expr?, result : Array[String]) -> Unit {
    match expr {
      Some(value) =>
        for name in value.references() {
          if !result.contains(name) {
            result.push(name)
          }
        }
      None => ()
    }
  }
  for assignment in unit.assignments {
    add_expression(assignment.rhs_expr, result)
  }
  for instance in unit.instances {
    for connection in instance.connections {
      add_expression(connection.expression, result)
    }
  }
  result
}

///|
fn collect_expression_writes(unit : Module) -> Array[String] {
  let result : Array[String] = []
  for assignment in unit.assignments {
    match assignment.lhs_expr {
      Some(Name(name)) => if !result.contains(name) { result.push(name) }
      Some(Index(Name(name), _)) | Some(PartSelect(Name(name), _, _)) =>
        if !result.contains(name) {
          result.push(name)
        }
      _ => if !result.contains(assignment.lhs) { result.push(assignment.lhs) }
    }
  }
  result
}

///|
fn check_expression_widths(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for assignment in unit.assignments {
    match (assignment.lhs_expr, assignment.rhs_expr) {
      (Some(left), Some(right)) =>
        match (left.width(unit), right.width(unit)) {
          (Some(left_width), Some(right_width)) if left_width != right_width =>
            add_diagnostic(
              config,
              result,
              diagnostic_for_rule(
                "RTL001",
                Warning,
                "assignment width mismatch: " +
                assignment.lhs +
                " receives " +
                right_width.to_string() +
                " bits but declares " +
                left_width.to_string(),
                assignment.span,
                Some(assignment.lhs),
                unit.name,
              ),
            )
          _ => ()
        }
      _ => ()
    }
  }
}

///|
fn check_unknown_references(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  let references = collect_expression_references(unit)
  for name in collect_expression_writes(unit) {
    if !references.contains(name) {
      references.push(name)
    }
  }
  for name in references {
    if signal_by_name(unit, name) is None && !is_builtin_reference(name) {
      add_diagnostic(
        config,
        result,
        diagnostic_for_rule(
          "RTL014",
          Error,
          "reference is not declared in module: " + name,
          unit.span,
          Some(name),
          unit.name,
        ),
      )
    }
  }
}

///|
fn check_procedural_assignments(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for block in unit.always_blocks {
    let body = block.body
    if body.contains("always_comb") &&
      body.contains("if") &&
      !body.contains("else") {
      add_diagnostic(
        config,
        result,
        diagnostic_for_rule(
          "RTL010",
          Warning,
          "always_comb block may infer a latch because an if branch has no else",
          block.span,
          None,
          unit.name,
        ),
      )
    }
    if (
        block.kind == AlwaysPosedge ||
        block.kind == AlwaysNegedge ||
        block.kind == AlwaysFF
      ) &&
      body.contains(" = ") &&
      !body.contains(" <= ") {
      add_diagnostic(
        config,
        result,
        diagnostic_for_rule(
          "RTL011",
          Warning,
          "clocked procedural block uses blocking assignment",
          block.span,
          None,
          unit.name,
        ),
      )
    }
    if body.contains("case") && !body.contains("default") {
      add_diagnostic(
        config,
        result,
        diagnostic_for_rule(
          "RTL012",
          Warning,
          "case statement has no default branch",
          block.span,
          None,
          unit.name,
        ),
      )
    }
    for assignment in unit.assignments {
      if assignment.procedural {
        match signal_by_name(unit, assignment.lhs) {
          Some(signal) if signal.kind == Wire =>
            add_diagnostic(
              config,
              result,
              diagnostic_for_rule(
                "RTL009",
                Error,
                "procedural assignment targets a wire: " + assignment.lhs,
                assignment.span,
                Some(assignment.lhs),
                unit.name,
              ),
            )
          _ => ()
        }
      }
    }
  }
}

///|
fn check_instance_ports(
  design : Design,
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  if !config.check_instances {
    return
  }
  for instance in unit.instances {
    let target = module_by_name(design, instance.module_name)
    match target {
      None =>
        add_diagnostic(
          config,
          result,
          diagnostic_for_rule(
            "RTL017",
            Warning,
            "instance refers to an unresolved module: " + instance.module_name,
            instance.span,
            Some(instance.instance_name),
            unit.name,
          ),
        )
      Some(target_unit) => {
        let named_ports : Array[String] = []
        let mut positional = 0
        for connection in instance.connections {
          if connection.port == "" {
            if positional >= target_unit.ports.length() {
              add_diagnostic(
                config,
                result,
                diagnostic_for_rule(
                  "RTL008",
                  Error,
                  "instance has more positional connections than target ports",
                  connection.span,
                  Some(instance.instance_name),
                  unit.name,
                ),
              )
            }
            positional += 1
          } else {
            if named_ports.contains(connection.port) {
              add_diagnostic(
                config,
                result,
                diagnostic_for_rule(
                  "RTL018",
                  Error,
                  "instance connects the same named port more than once: " +
                  connection.port,
                  connection.span,
                  Some(connection.port),
                  unit.name,
                ),
              )
            }
            named_ports.push(connection.port)
            if port_by_name(target_unit, connection.port) is None {
              add_diagnostic(
                config,
                result,
                diagnostic_for_rule(
                  "RTL008",
                  Error,
                  "instance connects an unknown target port: " + connection.port,
                  connection.span,
                  Some(connection.port),
                  unit.name,
                ),
              )
            }
          }
        }
        for port in target_unit.ports {
          if port.direction == Some(Input) &&
            connection_by_port(instance, port.name) is None {
            add_diagnostic(
              config,
              result,
              diagnostic_for_rule(
                "RTL019",
                Warning,
                "instance input port is not connected: " + port.name,
                instance.span,
                Some(port.name),
                unit.name,
              ),
            )
          }
        }
      }
    }
  }
}

///|
fn check_instance_drivers(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for instance in unit.instances {
    for connection in instance.connections {
      match connection.expression {
        Some(Name(name)) =>
          if signal_by_name(unit, name) is None {
            add_diagnostic(
              config,
              result,
              diagnostic_for_rule(
                "RTL014",
                Error,
                "instance connection references an undeclared signal: " + name,
                connection.span,
                Some(name),
                unit.name,
              ),
            )
          }
        _ => ()
      }
    }
  }
}

///|
fn check_combinational_sensitivity(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for block in unit.always_blocks {
    if block.kind == AlwaysLevel &&
      block.sensitivity.length() > 0 &&
      block.body.contains("assign") {
      add_diagnostic(
        config,
        result,
        diagnostic_for_rule(
          "RTL013",
          Info,
          "level-sensitive block contains a continuous assignment; review sensitivity intent",
          block.span,
          None,
          unit.name,
        ),
      )
    }
  }
}

///|
fn check_semantic_extensions(
  design : Design,
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  check_expression_widths(unit, config, result)
  check_unknown_references(unit, config, result)
  if config.check_procedural {
    check_procedural_assignments(unit, config, result)
    check_combinational_sensitivity(unit, config, result)
  }
  check_instance_ports(design, unit, config, result)
  check_instance_drivers(unit, config, result)
  check_extended_rules(design, unit, config, result)
  check_dataflow(unit, config, result)
  check_width_policy(unit, config, result)
}

///|
/// Run the default and extended rule set with configurable severities.
pub fn check_with_config(
  design : Design,
  config : CheckConfig,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  for unit in design.modules {
    let legacy : Array[Diagnostic] = []
    check_duplicates(unit, legacy)
    check_drivers(unit, legacy)
    check_references(unit, legacy)
    check_widths(unit, legacy)
    for item in legacy {
      add_diagnostic(config, result, module_diagnostic(item, unit.name))
    }
    check_semantic_extensions(design, unit, config, result)
  }
  if config.check_instances {
    check_contracts(design, config, result)
  }
  result
}

///|
/// Parse and check source using the configurable rule set.
pub fn check_source_with_config(
  source : String,
  config : CheckConfig,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  check_syntax_rules(source, config, result)
  for item in check_with_config(parse(source), config) {
    result.push(item)
  }
  result
}

///|
/// Return a stable process exit code: errors fail, warnings remain successful.
pub fn diagnostics_exit_code(items : Array[Diagnostic]) -> Int {
  for item in items {
    if item.severity == Error {
      return 1
    }
  }
  0
}

///|
/// Count diagnostics and return a concise CI summary.
pub fn diagnostics_summary(items : Array[Diagnostic]) -> String {
  let mut errors = 0
  let mut warnings = 0
  let mut infos = 0
  for item in items {
    match item.severity {
      Error => errors += 1
      Warning => warnings += 1
      Info => infos += 1
    }
  }
  "errors=" +
  errors.to_string() +
  " warnings=" +
  warnings.to_string() +
  " infos=" +
  infos.to_string()
}

///|
/// Return a Markdown table for release notes and pull-request comments.
pub fn diagnostics_markdown(items : Array[Diagnostic]) -> String {
  let mut out = "| Location | Severity | Rule | Message |\n| --- | --- | --- | --- |\n"
  for item in items {
    let severity = match item.severity {
      Error => "error"
      Warning => "warning"
      Info => "info"
    }
    let location = item.line.to_string() + ":" + item.column.to_string()
    out += "| " +
      location +
      " | " +
      severity +
      " | " +
      item.code +
      " | " +
      item.message +
      " |\n"
  }
  out
}

///|
fn json_escape(value : String) -> String {
  let mut out = ""
  for c in value.to_array() {
    if c == '"' {
      out += "\\\""
    } else if c == '\\' {
      out += "\\\\"
    } else if c == '\n' {
      out += "\\n"
    } else if c == '\r' {
      out += "\\r"
    } else if c == '\t' {
      out += "\\t"
    } else {
      out += c.to_string()
    }
  }
  out
}

///|
fn severity_text(severity : Severity) -> String {
  match severity {
    Error => "error"
    Warning => "warning"
    Info => "info"
  }
}

///|
/// Render diagnostics as SARIF 2.1.0 for GitHub code scanning.
pub fn diagnostics_sarif(items : Array[Diagnostic]) -> String {
  let rules : Array[String] = []
  for item in items {
    if !rules.contains(item.code) {
      rules.push(item.code)
    }
  }
  let rules_json = rules
    .map(fn(code) { "{\"id\":\"" + json_escape(code) + "\"}" })
    .join(",")
  let results = items
    .map(fn(item) {
      "{\"ruleId\":\"" +
      json_escape(item.code) +
      "\",\"level\":\"" +
      severity_text(item.severity) +
      "\",\"message\":{\"text\":\"" +
      json_escape(item.message) +
      "\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"source.v\"},\"region\":{\"startLine\":" +
      item.line.to_string() +
      ",\"startColumn\":" +
      item.column.to_string() +
      "}}}]}"
    })
    .join(",")
  "{\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"moonbit-rtl\",\"rules\":[" +
  rules_json +
  "]}},\"results\":[" +
  results +
  "]}]}"
}

///|
/// Serialize a check summary without requiring a JSON dependency.
pub fn CheckSummary::to_json(self : CheckSummary) -> String {
  "{\"errors\":" +
  self.errors.to_string() +
  ",\"warnings\":" +
  self.warnings.to_string() +
  ",\"infos\":" +
  self.infos.to_string() +
  ",\"modules\":" +
  self.modules.to_string() +
  ",\"signals\":" +
  self.signals.to_string() +
  ",\"assignments\":" +
  self.assignments.to_string() +
  ",\"instances\":" +
  self.instances.to_string() +
  "}"
}

///|
/// Return the names of rules emitted by a diagnostic array in first-seen order.
pub fn diagnostic_rule_ids(items : Array[Diagnostic]) -> Array[String] {
  let result : Array[String] = []
  for item in items {
    if !result.contains(item.code) {
      result.push(item.code)
    }
  }
  result
}

///|
/// Convert recoverable parser diagnostics into the common reporting format.
pub fn parse_diagnostics(source : String) -> Array[Diagnostic] {
  let parsed = parse_with_diagnostics(source)
  let result : Array[Diagnostic] = []
  for item in parsed.diagnostics {
    result.push({
      code: item.code,
      severity: item.severity,
      message: item.message,
      line: item.line,
      column: item.column,
      signal: None,
      end_line: item.line,
      end_column: item.column,
      module_name: None,
      related: [],
    })
  }
  result
}
