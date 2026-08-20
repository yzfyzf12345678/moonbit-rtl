///|
/// A resolved parameter value in an elaborated design.
pub struct ElaboratedParameter {
  name : String
  text : String
  value : Int?
  source : String
}

///|
/// A resolved port binding for one module instance.
pub struct ElaboratedConnection {
  port : String
  expression : String
  expression_width : Int?
  port_width : Int?
  compatible : Bool
}

///|
/// A resolved child instance in the elaborated hierarchy.
pub struct ElaboratedInstance {
  path : String
  instance_name : String
  module_name : String
  parameters : Array[ElaboratedParameter]
  connections : Array[ElaboratedConnection]
  resolved : Bool
}

///|
/// An issue discovered while resolving hierarchy and port contracts.
pub struct ElaborationIssue {
  code : String
  severity : Severity
  path : String
  message : String
  line : Int
}

///|
/// An elaborated module with stable instance paths.
pub struct ElaboratedModule {
  name : String
  path : String
  parameters : Array[ElaboratedParameter]
  instances : Array[ElaboratedInstance]
  port_widths : Array[(String, Int?)]
}

///|
/// The hierarchy-aware result of elaborating a parsed design.
pub struct ElaboratedDesign {
  modules : Array[ElaboratedModule]
  issues : Array[ElaborationIssue]
  roots : Array[String]
  unresolved : Array[String]
  depth : Int
}

///|
fn elaboration_module(design : Design, name : String) -> Module? {
  for unit in design.modules {
    if unit.name == name {
      return Some(unit)
    }
  }
  None
}

///|
fn elaboration_parameter(
  parameter : Parameter,
  inherited : Array[ElaboratedParameter],
) -> ElaboratedParameter {
  let inherited_value = inherited
    .filter(fn(item) { item.name == parameter.name })
    .get(0)
  {
    name: parameter.name,
    text: parameter.value,
    value: inherited_value
    .map(fn(item) { item.value })
    .unwrap_or(evaluate_number(parameter.value)),
    source: inherited_value
    .map(fn(item) { "override:" + item.source })
    .unwrap_or("default"),
  }
}

///|
fn elaboration_parameters(
  unit : Module,
  inherited : Array[ElaboratedParameter],
) -> Array[ElaboratedParameter] {
  unit.parameters.map(fn(item) { elaboration_parameter(item, inherited) })
}

///|
fn elaboration_parameter_overrides(
  instance : ModuleInstance,
  parent_parameters : Array[ElaboratedParameter],
) -> Array[ElaboratedParameter] {
  let result : Array[ElaboratedParameter] = []
  for parameter in instance.parameters {
    let value = evaluate_number(parameter.value)
      .map(fn(item) { item.to_string() })
      .unwrap_or(parameter.value)
    result.push({
      name: parameter.name,
      text: value,
      value: evaluate_number(value),
      source: "instance:" + instance.instance_name,
    })
  }
  for inherited in parent_parameters {
    if !result.any(fn(item) { item.name == inherited.name }) {
      result.push(inherited)
    }
  }
  result
}

///|
fn elaboration_expression_width(
  expression : Expr?,
  raw : String,
  parent : Module,
) -> Int? {
  match expression {
    Some(value) => value.width(parent)
    None => evaluate_number(raw)
  }
}

///|
fn elaboration_connection(
  parent : Module,
  child : Module,
  connection : PortConnection,
) -> ElaboratedConnection {
  let port = child.ports
    .filter(fn(item) { item.name == connection.port })
    .get(0)
  let port_width = match port {
    Some(item) => item.width.map(fn(width) { width.bits() })
    None => None
  }
  let expression_width = elaboration_expression_width(
    connection.expression,
    connection.raw_expression,
    parent,
  )
  let compatible = match (port_width, expression_width) {
    (Some(expected), Some(actual)) =>
      expected == actual || actual == 1 || expected == 1
    _ => true
  }
  {
    port: connection.port,
    expression: connection.raw_expression,
    expression_width,
    port_width,
    compatible,
  }
}

///|
fn elaboration_issue(
  code : String,
  severity : Severity,
  path : String,
  message : String,
  line : Int,
) -> ElaborationIssue {
  { code, severity, path, message, line }
}

///|
fn elaboration_module_ports(unit : Module) -> Array[(String, Int?)] {
  unit.ports.map(fn(signal) { (signal.name, signal.width.map(Width::bits)) })
}

///|
fn elaboration_instance(
  design : Design,
  parent : Module,
  instance : ModuleInstance,
  path : String,
  inherited : Array[ElaboratedParameter],
  issues : Array[ElaborationIssue],
) -> ElaboratedInstance {
  match elaboration_module(design, instance.module_name) {
    Some(child) => {
      let parameters = elaboration_parameter_overrides(instance, inherited)
      let connections = instance.connections.map(fn(item) {
        elaboration_connection(parent, child, item)
      })
      for connection in connections {
        if !connection.compatible {
          issues.push(
            elaboration_issue(
              "ELAB002",
              Warning,
              path,
              "width mismatch at port " +
              connection.port +
              ": expected " +
              connection.port_width
              .map(fn(value) { value.to_string() })
              .unwrap_or("?") +
              ", got " +
              connection.expression_width
              .map(fn(value) { value.to_string() })
              .unwrap_or("?"),
              instance.span.start.line,
            ),
          )
        }
      }
      {
        path,
        instance_name: instance.instance_name,
        module_name: instance.module_name,
        parameters,
        connections,
        resolved: true,
      }
    }
    None => {
      issues.push(
        elaboration_issue(
          "ELAB001",
          Error,
          path,
          "unresolved module " + instance.module_name,
          instance.span.start.line,
        ),
      )
      {
        path,
        instance_name: instance.instance_name,
        module_name: instance.module_name,
        parameters: [],
        connections: [],
        resolved: false,
      }
    }
  }
}

///|
fn elaboration_visit(
  design : Design,
  unit : Module,
  path : String,
  inherited : Array[ElaboratedParameter],
  active : Array[String],
  modules : Array[ElaboratedModule],
  issues : Array[ElaborationIssue],
  unresolved : Array[String],
  depth : Int,
) -> Int {
  let parameters = elaboration_parameters(unit, inherited)
  let instances : Array[ElaboratedInstance] = []
  let mut max_depth = depth
  for instance in unit.instances {
    let child_path = path + "." + instance.instance_name
    let resolved = elaboration_instance(
      design, unit, instance, child_path, parameters, issues,
    )
    instances.push(resolved)
    if !resolved.resolved {
      unresolved.push(child_path)
      continue
    }
    if active.contains(instance.module_name) {
      issues.push(
        elaboration_issue(
          "ELAB003",
          Error,
          child_path,
          "hierarchy cycle through " + instance.module_name,
          instance.span.start.line,
        ),
      )
      continue
    }
    match elaboration_module(design, instance.module_name) {
      Some(child) => {
        let next_active = active.copy()
        next_active.push(instance.module_name)
        let child_depth = elaboration_visit(
          design,
          child,
          child_path,
          resolved.parameters,
          next_active,
          modules,
          issues,
          unresolved,
          depth + 1,
        )
        if child_depth > max_depth {
          max_depth = child_depth
        }
      }
      None => ()
    }
  }
  modules.push({
    name: unit.name,
    path,
    parameters,
    instances,
    port_widths: elaboration_module_ports(unit),
  })
  max_depth
}

///|
fn elaboration_duplicate_instances(
  unit : Module,
  issues : Array[ElaborationIssue],
) -> Unit {
  let names : Array[String] = []
  for instance in unit.instances {
    if names.contains(instance.instance_name) {
      issues.push(
        elaboration_issue(
          "ELAB004",
          Error,
          unit.name,
          "duplicate instance name " + instance.instance_name,
          instance.span.start.line,
        ),
      )
    } else {
      names.push(instance.instance_name)
    }
  }
}

///|
fn elaboration_root_names(design : Design) -> Array[String] {
  let referenced : Array[String] = []
  for unit in design.modules {
    for instance in unit.instances {
      if !referenced.contains(instance.module_name) {
        referenced.push(instance.module_name)
      }
    }
  }
  design.modules
  .filter(fn(unit) { !referenced.contains(unit.name) })
  .map(fn(unit) { unit.name })
}

///|
/// Resolve instances, parameters, port widths, roots, and hierarchy cycles.
pub fn elaborate_design(design : Design) -> ElaboratedDesign {
  let modules : Array[ElaboratedModule] = []
  let issues : Array[ElaborationIssue] = []
  let unresolved : Array[String] = []
  for unit in design.modules {
    elaboration_duplicate_instances(unit, issues)
  }
  let roots = elaboration_root_names(design)
  let actual_roots = if roots.length() == 0 && design.modules.length() > 0 {
    [design.modules[0].name]
  } else {
    roots
  }
  let mut depth = 0
  for root in actual_roots {
    match elaboration_module(design, root) {
      Some(unit) => {
        let child_depth = elaboration_visit(
          design,
          unit,
          root,
          [],
          [root],
          modules,
          issues,
          unresolved,
          1,
        )
        if child_depth > depth {
          depth = child_depth
        }
      }
      None => ()
    }
  }
  for unit in design.modules {
    if !modules.any(fn(item) { item.name == unit.name }) {
      modules.push({
        name: unit.name,
        path: unit.name,
        parameters: elaboration_parameters(unit, []),
        instances: [],
        port_widths: elaboration_module_ports(unit),
      })
    }
  }
  { modules, issues, roots: actual_roots, unresolved, depth }
}

///|
pub fn elaborate_source(source : String) -> ElaboratedDesign {
  elaborate_design(parse(source))
}

///|
pub fn ElaboratedDesign::is_clean(self : ElaboratedDesign) -> Bool {
  !self.issues.any(fn(item) { item.severity == Error })
}

///|
pub fn ElaboratedDesign::module_paths(self : ElaboratedDesign) -> Array[String] {
  self.modules.map(fn(item) { item.path })
}

///|
pub fn ElaboratedDesign::find_path(
  self : ElaboratedDesign,
  path : String,
) -> ElaboratedModule? {
  self.modules.filter(fn(item) { item.path == path }).get(0)
}

///|
pub fn ElaboratedDesign::instances_of(
  self : ElaboratedDesign,
  module_name : String,
) -> Array[ElaboratedInstance] {
  let result : Array[ElaboratedInstance] = []
  for unit in self.modules {
    for instance in unit.instances {
      if instance.module_name == module_name {
        result.push(instance)
      }
    }
  }
  result
}

///|
pub fn ElaboratedDesign::error_count(self : ElaboratedDesign) -> Int {
  self.issues.filter(fn(item) { item.severity == Error }).length()
}

///|
pub fn ElaboratedDesign::warning_count(self : ElaboratedDesign) -> Int {
  self.issues.filter(fn(item) { item.severity == Warning }).length()
}

///|
pub fn ElaboratedDesign::to_json(self : ElaboratedDesign) -> String {
  let modules = self.modules
    .map(fn(unit) {
      let instances = unit.instances
        .map(fn(item) {
          "{\"path\":\"" +
          json_escape(item.path) +
          "\",\"module\":\"" +
          json_escape(item.module_name) +
          "\",\"resolved\":" +
          (if item.resolved { "true" } else { "false" }) +
          "}"
        })
        .join(",")
      "{\"name\":\"" +
      json_escape(unit.name) +
      "\",\"path\":\"" +
      json_escape(unit.path) +
      "\",\"instances\":[" +
      instances +
      "]}"
    })
    .join(",")
  let issues = self.issues
    .map(fn(item) {
      "{\"code\":\"" +
      item.code +
      "\",\"path\":\"" +
      json_escape(item.path) +
      "\",\"line\":" +
      item.line.to_string() +
      ",\"message\":\"" +
      json_escape(item.message) +
      "\"}"
    })
    .join(",")
  "{\"roots\":[" +
  self.roots.map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "],\"depth\":" +
  self.depth.to_string() +
  ",\"modules\":[" +
  modules +
  "],\"issues\":[" +
  issues +
  "]}"
}

///|
pub fn ElaboratedDesign::to_markdown(self : ElaboratedDesign) -> String {
  let header = "# Elaborated hierarchy\n\n" +
    "- roots: `" +
    self.roots.join(", ") +
    "`\n" +
    "- depth: `" +
    self.depth.to_string() +
    "`\n" +
    "- errors: `" +
    self.error_count().to_string() +
    "`\n" +
    "- warnings: `" +
    self.warning_count().to_string() +
    "`\n\n"
  let rows : Array[String] = []
  for unit in self.modules {
    rows.push(
      "| " +
      unit.path +
      " | " +
      unit.name +
      " | " +
      unit.instances.length().to_string() +
      " |",
    )
    for instance in unit.instances {
      rows.push(
        "| &nbsp;↳ " +
        instance.path +
        " | " +
        instance.module_name +
        " | " +
        (if instance.resolved { "resolved" } else { "unresolved" }) +
        " |",
      )
    }
  }
  header +
  "| Path | Module | Instances |\n| --- | --- | --- |\n" +
  rows.join("\n") +
  "\n"
}

///|
pub fn elaboration_diagnostics(result : ElaboratedDesign) -> Array[Diagnostic] {
  result.issues.map(fn(item) {
    let diagnostic = Diagnostic::new(
      item.code,
      item.severity,
      item.message,
      item.line,
      1,
    )
    { ..diagnostic, module_name: Some(item.path) }
  })
}

///|
pub fn elaboration_contract() -> String {
  "resolution=module_instance_and_port_contract; roots=unreferenced_modules; " +
  "cycles=error; width_policy=scalar_or_exact"
}
