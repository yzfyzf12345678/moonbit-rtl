///|

///|
fn signal_width(design_module : Module, name : String) -> Width? {
  for x in design_module.ports {
    if x.name == name {
      return x.width
    }
  }
  for x in design_module.signals {
    if x.name == name {
      return x.width
    }
  }
  None
}

///|
fn has_driver(design_module : Module, name : String) -> Bool {
  for x in design_module.assignments {
    if x.lhs == name {
      return true
    }
  }
  for x in design_module.always_blocks {
    if x.body.contains(name + " =") || x.body.contains(name + " <=") {
      return true
    }
  }
  false
}

///|
fn driver_count(design_module : Module, name : String) -> Int {
  let mut count = 0
  for x in design_module.assignments {
    if x.lhs == name {
      count += 1
    }
  }
  for x in design_module.always_blocks {
    if x.body.contains(name + " =") || x.body.contains(name + " <=") {
      count += 1
    }
  }
  count
}

///|
fn diagnostic(
  code : String,
  severity : Severity,
  message : String,
  span : Span,
  signal : String?,
) -> Diagnostic {
  {
    code,
    severity,
    message,
    line: span.start.line,
    column: span.start.column,
    signal,
  }
}

///|
fn check_duplicates(design_module : Module, result : Array[Diagnostic]) -> Unit {
  let names : Array[String] = []
  for x in design_module.ports {
    if names.contains(x.name) {
      result.push(
        diagnostic(
          "RTL002",
          Error,
          "duplicate signal declaration: " + x.name,
          x.span,
          Some(x.name),
        ),
      )
    } else {
      names.push(x.name)
    }
  }
  for x in design_module.signals {
    if names.contains(x.name) {
      result.push(
        diagnostic(
          "RTL002",
          Error,
          "duplicate signal declaration: " + x.name,
          x.span,
          Some(x.name),
        ),
      )
    } else {
      names.push(x.name)
    }
  }
}

///|
fn check_drivers(design_module : Module, result : Array[Diagnostic]) -> Unit {
  for x in design_module.ports {
    if x.direction == Some(Output) && !has_driver(design_module, x.name) {
      result.push(
        diagnostic(
          "RTL003",
          Warning,
          "output port is not driven: " + x.name,
          x.span,
          Some(x.name),
        ),
      )
    }
  }
  for x in design_module.signals {
    let count = driver_count(design_module, x.name)
    if count == 0 {
      result.push(
        diagnostic(
          "RTL004",
          Info,
          "signal is declared but never driven: " + x.name,
          x.span,
          Some(x.name),
        ),
      )
    } else if count > 1 {
      result.push(
        diagnostic(
          "RTL005",
          Error,
          "signal has multiple drivers: " + x.name,
          x.span,
          Some(x.name),
        ),
      )
    }
  }
}

///|
fn check_references(design_module : Module, result : Array[Diagnostic]) -> Unit {
  for x in design_module.ports {
    let mentioned = has_driver(design_module, x.name)
    if x.direction == Some(Input) && !mentioned {
      let used = design_module.assignments.any(fn(a) { a.rhs.contains(x.name) })
      if !used {
        result.push(
          diagnostic(
            "RTL006",
            Info,
            "input port is not referenced: " + x.name,
            x.span,
            Some(x.name),
          ),
        )
      }
    }
  }
}

///|
fn check_widths(design_module : Module, result : Array[Diagnostic]) -> Unit {
  for assignment in design_module.assignments {
    match
      (
        signal_width(design_module, assignment.lhs),
        signal_width(design_module, assignment.rhs),
      ) {
      (Some(left), Some(right)) => {
        let lw = (left.msb - left.lsb).abs() + 1
        let rw = (right.msb - right.lsb).abs() + 1
        if lw != rw {
          result.push(
            diagnostic(
              "RTL001",
              Warning,
              "assignment width mismatch: " + assignment.lhs,
              assignment.span,
              Some(assignment.lhs),
            ),
          )
        }
      }
      _ => ()
    }
  }
}

///|
/// Run the default RTL rule set over a design.
pub fn check(design : Design) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  for design_module in design.modules {
    check_duplicates(design_module, result)
    check_drivers(design_module, result)
    check_references(design_module, result)
    check_widths(design_module, result)
  }
  result
}

///|
/// Parse and check Verilog source in one call.
pub fn check_source(source : String) -> Array[Diagnostic] {
  check(parse(source))
}

///|
/// Render diagnostics in a stable terminal format.
pub fn diagnostics_text(items : Array[Diagnostic]) -> String {
  let mut out = ""
  for item in items {
    let level = match item.severity {
      Error => "error"
      Warning => "warning"
      Info => "info"
    }
    out += item.line.to_string() +
      ":" +
      item.column.to_string() +
      ": " +
      level +
      "[" +
      item.code +
      "]: " +
      item.message +
      "\n"
  }
  out
}

///|
/// Render diagnostics as a JSON array for CI integrations.
pub fn diagnostics_json(items : Array[Diagnostic]) -> String {
  let mut out = "["
  let mut first = true
  for item in items {
    if !first {
      out += ","
    }
    let level = match item.severity {
      Error => "error"
      Warning => "warning"
      Info => "info"
    }
    out += "{\"code\":\"" +
      item.code +
      "\",\"severity\":\"" +
      level +
      "\",\"line\":" +
      item.line.to_string() +
      ",\"column\":" +
      item.column.to_string() +
      ",\"message\":\"" +
      item.message +
      "\"}"
    first = false
  }
  out + "]"
}
