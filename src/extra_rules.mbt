///|
fn add_extra(
  config : CheckConfig,
  result : Array[Diagnostic],
  code : String,
  severity : Severity,
  message : String,
  span : Span,
  signal : String?,
  module_name : String,
) -> Unit {
  add_diagnostic(
    config,
    result,
    diagnostic_for_rule(code, severity, message, span, signal, module_name),
  )
}

///|
fn signal_span(unit : Module, name : String) -> Span {
  match signal_by_name(unit, name) {
    Some(signal) => signal.span
    None => unit.span
  }
}

///|
fn check_module_declarations(
  design : Design,
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  if unit.ports.length() + unit.signals.length() == 0 {
    add_extra(
      config,
      result,
      "RTL028",
      Info,
      "module has no ports or internal signals",
      unit.span,
      None,
      unit.name,
    )
  }
  for duplicate in design.duplicate_modules() {
    if duplicate == unit.name {
      add_extra(
        config,
        result,
        "RTL020",
        Error,
        "module is defined more than once: " + unit.name,
        unit.span,
        Some(unit.name),
        unit.name,
      )
    }
  }
  for port in unit.ports {
    if port.name == "" {
      add_extra(
        config,
        result,
        "RTL021",
        Error,
        "port declaration has an empty name",
        port.span,
        None,
        unit.name,
      )
    }
    match port.width {
      Some(width) if width.bits() <= 0 =>
        add_extra(
          config,
          result,
          "RTL022",
          Error,
          "packed port range has no bits: " + port.name,
          port.span,
          Some(port.name),
          unit.name,
        )
      _ => ()
    }
  }
  for signal in unit.signals {
    if signal.name == "" {
      add_extra(
        config,
        result,
        "RTL021",
        Error,
        "signal declaration has an empty name",
        signal.span,
        None,
        unit.name,
      )
    }
  }
}

///|
fn check_input_drivers(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for input in unit.ports {
    if input.direction == Some(Input) {
      for assignment in unit.assignments {
        match assignment.write_name() {
          Some(name) if name == input.name =>
            add_extra(
              config,
              result,
              "RTL023",
              Error,
              "input port is driven inside the module: " + input.name,
              assignment.span,
              Some(input.name),
              unit.name,
            )
          _ => ()
        }
      }
    }
  }
}

///|
fn check_multiple_kinds_of_driver(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for signal in unit.ports {
    let mut continuous = false
    let mut procedural = false
    for assignment in unit.assignments {
      match assignment.write_name() {
        Some(name) if name == signal.name =>
          if assignment.procedural {
            procedural = true
          } else {
            continuous = true
          }
        _ => ()
      }
    }
    if continuous && procedural {
      add_extra(
        config,
        result,
        "RTL024",
        Error,
        "signal has both continuous and procedural drivers: " + signal.name,
        signal.span,
        Some(signal.name),
        unit.name,
      )
    }
  }
}

///|
fn check_instance_widths(
  design : Design,
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for instance in unit.instances {
    match design.find_module(instance.module_name) {
      Some(target) =>
        for connection in instance.connections {
          match check_port_compatibility(unit, target, connection) {
            WidthMismatch(source, target_width) =>
              add_extra(
                config,
                result,
                "RTL025",
                Warning,
                "instance connection width mismatch: " +
                source.to_string() +
                " to " +
                target_width.to_string() +
                " bits",
                connection.span,
                Some(instance.instance_name),
                unit.name,
              )
            DirectionMismatch =>
              add_extra(
                config,
                result,
                "RTL026",
                Error,
                "instance connection direction is incompatible with the target port",
                connection.span,
                Some(connection.port),
                unit.name,
              )
            UndeclaredSignal =>
              add_extra(
                config,
                result,
                "RTL014",
                Error,
                "instance connection uses an undeclared parent signal",
                connection.span,
                Some(instance.instance_name),
                unit.name,
              )
            MissingPort | Compatible => ()
          }
        }
      None => ()
    }
  }
}

///|
fn check_clocking(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for block in unit.always_blocks {
    let clocks = block.sensitivity.filter(fn(item) { item.edge is Some(_) })
    if clocks.length() > 1 {
      add_extra(
        config,
        result,
        "RTL027",
        Warning,
        "always block has multiple edge-triggered sensitivity signals",
        block.span,
        None,
        unit.name,
      )
    }
    if (
        block.kind == AlwaysPosedge ||
        block.kind == AlwaysNegedge ||
        block.kind == AlwaysFF
      ) &&
      block.sensitivity.length() == 0 {
      add_extra(
        config,
        result,
        "RTL029",
        Error,
        "clocked always block has an empty sensitivity list",
        block.span,
        None,
        unit.name,
      )
    }
    if block.kind == AlwaysComb && block.sensitivity.length() > 0 {
      add_extra(
        config,
        result,
        "RTL030",
        Info,
        "always_comb should not carry an explicit sensitivity list",
        block.span,
        None,
        unit.name,
      )
    }
  }
}

///|
fn check_reset_conventions(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  if !unit.has_reset_input() {
    return
  }
  let reset_names = unit
    .input_names()
    .filter(fn(name) { name.contains("rst") || name.contains("reset") })
  for block in unit.always_blocks {
    if block.kind == AlwaysPosedge ||
      block.kind == AlwaysNegedge ||
      block.kind == AlwaysFF {
      for reset in reset_names {
        if block.body.contains(reset) &&
          !block.sensitivity.any(fn(item) { item.signal == reset }) {
          add_extra(
            config,
            result,
            "RTL031",
            Warning,
            "reset is read in a clocked block but is absent from sensitivity",
            block.span,
            Some(reset),
            unit.name,
          )
        }
      }
    }
  }
}

///|
fn check_constant_conditions(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for block in unit.always_blocks {
    let tokens = lex(block.body)
    for i in 0..<tokens.length() {
      if tokens[i].text == "if" &&
        i + 2 < tokens.length() &&
        tokens[i + 1].text == "(" {
        let close = find_closing(tokens, i + 1, "(", ")", tokens.length())
        let condition = parse_expression_range(tokens, i + 2, close)
        match evaluate_constant(condition) {
          Some(value) =>
            add_extra(
              config,
              result,
              "RTL032",
              Info,
              "if condition is constant and evaluates to " + value.to_string(),
              block.span,
              None,
              unit.name,
            )
          None => ()
        }
      }
    }
  }
}

///|
fn check_complexity(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  if unit.complexity_score() > 80 {
    add_extra(
      config,
      result,
      "RTL033",
      Info,
      "module complexity exceeds the review threshold",
      unit.span,
      Some(unit.name),
      unit.name,
    )
  }
  for assignment in unit.assignments {
    match assignment.rhs_expr {
      Some(expr) if expr.depth() > 8 =>
        add_extra(
          config,
          result,
          "RTL034",
          Info,
          "expression nesting is deeper than eight levels",
          signal_span(unit, assignment.lhs),
          Some(assignment.lhs),
          unit.name,
        )
      _ => ()
    }
  }
}

///|
fn check_port_naming(
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for port in unit.ports {
    let first = port.name.to_array().get(0)
    match first {
      Some(c) if c >= 'A' && c <= 'Z' =>
        add_extra(
          config,
          result,
          "RTL035",
          Info,
          "port name uses an uppercase initial; lower_snake_case is easier to integrate",
          port.span,
          Some(port.name),
          unit.name,
        )
      _ => ()
    }
  }
}

///|
fn check_unconnected_outputs(
  design : Design,
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for instance in unit.instances {
    match design.find_module(instance.module_name) {
      Some(target) =>
        for port in target.ports {
          if port.direction == Some(Output) &&
            connection_by_port(instance, port.name) is None {
            add_extra(
              config,
              result,
              "RTL036",
              Warning,
              "instance output port is not connected: " + port.name,
              instance.span,
              Some(port.name),
              unit.name,
            )
          }
        }
      None => ()
    }
  }
}

///|
fn check_extended_rules(
  design : Design,
  unit : Module,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  check_module_declarations(design, unit, config, result)
  check_input_drivers(unit, config, result)
  check_multiple_kinds_of_driver(unit, config, result)
  check_instance_widths(design, unit, config, result)
  check_clocking(unit, config, result)
  check_reset_conventions(unit, config, result)
  check_constant_conditions(unit, config, result)
  check_complexity(unit, config, result)
  check_port_naming(unit, config, result)
  check_unconnected_outputs(design, unit, config, result)
}
