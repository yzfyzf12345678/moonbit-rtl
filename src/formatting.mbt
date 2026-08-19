///|
/// Formatting options for source and AST output.
pub struct FormatOptions {
  indent : Int
  spaces_inside_ranges : Bool
  include_comments : Bool
  trailing_newline : Bool
}

///|
/// Default stable formatting options.
pub fn FormatOptions::default() -> FormatOptions {
  {
    indent: 2,
    spaces_inside_ranges: false,
    include_comments: false,
    trailing_newline: true,
  }
}

///|
fn indentation(level : Int, width : Int) -> String {
  let mut out = ""
  let count = level * width
  for _ in 0..<count {
    out += " "
  }
  out
}

///|
/// Format a packed width range.
pub fn format_width(width : Width, options : FormatOptions) -> String {
  let space = if options.spaces_inside_ranges { " " } else { "" }
  "[" +
  space +
  width.msb.to_string() +
  ":" +
  width.lsb.to_string() +
  space +
  "]"
}

///|
/// Format an expression using deterministic Verilog precedence.
pub fn format_expr(expr : Expr) -> String {
  match expr {
    Name(name) => name
    Number(value) => value
    StringLiteral(value) => value
    Unary(op, value) => op + format_expr(value)
    Binary(left, op, right) =>
      "(" + format_expr(left) + " " + op + " " + format_expr(right) + ")"
    Conditional(condition, when_true, when_false) =>
      "(" +
      format_expr(condition) +
      " ? " +
      format_expr(when_true) +
      " : " +
      format_expr(when_false) +
      ")"
    Concatenation(items) =>
      "{" + items.map(fn(item) { format_expr(item) }).join(", ") + "}"
    Replication(count, value) =>
      "{" + count.to_string() + "{" + format_expr(value) + "}}"
    Index(value, index) => format_expr(value) + "[" + format_expr(index) + "]"
    PartSelect(value, left, right) =>
      format_expr(value) +
      "[" +
      format_expr(left) +
      ":" +
      format_expr(right) +
      "]"
    Call(name, args) =>
      name + "(" + args.map(fn(item) { format_expr(item) }).join(", ") + ")"
    Unknown(value) => value
  }
}

///|
fn format_direction(direction : PortDirection?) -> String {
  match direction {
    Some(Input) => "input"
    Some(Output) => "output"
    Some(Inout) => "inout"
    None => ""
  }
}

///|
fn format_signal(
  signal : Signal,
  options : FormatOptions,
  include_direction : Bool,
) -> String {
  let direction = if include_direction {
    format_direction(signal.direction) + " "
  } else {
    ""
  }
  let width = match signal.width {
    Some(value) => format_width(value, options) + " "
    None => ""
  }
  direction + width + signal.name
}

///|
/// Format one assignment statement.
pub fn format_assignment(
  assignment : Assignment,
  options : FormatOptions,
  level : Int,
) -> String {
  let left = match assignment.lhs_expr {
    Some(expr) => format_expr(expr)
    None => assignment.lhs
  }
  let right = match assignment.rhs_expr {
    Some(expr) => format_expr(expr)
    None => assignment.rhs
  }
  indentation(level, options.indent) +
  left +
  " " +
  assignment.operator +
  " " +
  right +
  ";"
}

///|
fn format_case_item(
  item : CaseItem,
  options : FormatOptions,
  level : Int,
) -> String {
  let label = if item.is_default {
    "default"
  } else {
    item.labels.map(fn(expr) { format_expr(expr) }).join(", ")
  }
  let mut out = indentation(level, options.indent) + label + ":\n"
  for statement in item.statements {
    out += format_statement(statement, options, level + 1) + "\n"
  }
  out
}

///|
fn format_statement(
  statement : Statement,
  options : FormatOptions,
  level : Int,
) -> String {
  match statement {
    EmptyStatement => indentation(level, options.indent) + ";"
    ProceduralAssignment(assignment) =>
      format_assignment(assignment, options, level)
    ConditionalStatement(condition, when_true, when_false) => {
      let mut out = indentation(level, options.indent) +
        "if (" +
        format_expr(condition) +
        ") begin\n"
      for item in when_true {
        out += format_statement(item, options, level + 1) + "\n"
      }
      out += indentation(level, options.indent) + "end"
      if when_false.length() > 0 {
        out += " else begin\n"
        for item in when_false {
          out += format_statement(item, options, level + 1) + "\n"
        }
        out += indentation(level, options.indent) + "end"
      }
      out
    }
    CaseStatement(condition, items) => {
      let mut out = indentation(level, options.indent) +
        "case (" +
        format_expr(condition) +
        ")\n"
      for item in items {
        out += format_case_item(item, options, level + 1)
      }
      out + indentation(level, options.indent) + "endcase"
    }
    BlockStatement(items) => {
      let mut out = indentation(level, options.indent) + "begin\n"
      for item in items {
        out += format_statement(item, options, level + 1) + "\n"
      }
      out + indentation(level, options.indent) + "end"
    }
    InstanceStatement(instance) => format_instance(instance, options, level)
    ExpressionStatement(expr) =>
      indentation(level, options.indent) + format_expr(expr) + ";"
    UnknownStatement(text) => indentation(level, options.indent) + text
  }
}

///|
fn format_instance(
  instance : ModuleInstance,
  options : FormatOptions,
  level : Int,
) -> String {
  let connections = instance.connections
    .map(fn(connection) {
      if connection.port == "" {
        match connection.expression {
          Some(expr) => format_expr(expr)
          None => ""
        }
      } else {
        let value = match connection.expression {
          Some(expr) => format_expr(expr)
          None => ""
        }
        "." + connection.port + "(" + value + ")"
      }
    })
    .join(", ")
  indentation(level, options.indent) +
  instance.module_name +
  " " +
  instance.instance_name +
  " (" +
  connections +
  ");"
}

///|
/// Format a complete module without claiming to be a lossless source printer.
pub fn format_module(unit : Module, options : FormatOptions) -> String {
  let mut out = "module " + unit.name + " (\n"
  for i, port in unit.ports {
    out += indentation(1, options.indent) + format_signal(port, options, true)
    if i + 1 < unit.ports.length() {
      out += ","
    }
    out += "\n"
  }
  out += ");\n"
  for parameter in unit.parameters {
    out += indentation(1, options.indent) +
      "parameter " +
      parameter.name +
      " = " +
      parameter.value +
      ";\n"
  }
  for signal in unit.signals {
    let keyword = match signal.kind {
      Wire => "wire"
      Reg => "reg"
      Port => "wire"
    }
    out += indentation(1, options.indent) +
      keyword +
      " " +
      format_signal(signal, options, false) +
      ";\n"
  }
  for assignment in unit.assignments {
    out += format_assignment(assignment, options, 1) + "\n"
  }
  for instance in unit.instances {
    out += format_instance(instance, options, 1) + "\n"
  }
  for statement in unit.statements {
    out += format_statement(statement, options, 1) + "\n"
  }
  out + "endmodule\n"
}

///|
/// Format all modules in source order.
pub fn format_design(design : Design, options : FormatOptions) -> String {
  let mut out = ""
  for unit in design.modules {
    out += format_module(unit, options) + "\n"
  }
  if options.trailing_newline {
    out
  } else if out.has_suffix("\n") {
    out[:out.length() - 1].to_owned()
  } else {
    out
  }
}

///|
/// Produce a compact outline useful in editors and code review.
pub fn design_outline(source : String) -> String {
  let design = parse(source)
  let mut out = ""
  for unit in design.modules {
    out += unit.name +
      " ports=" +
      unit.ports.length().to_string() +
      " signals=" +
      unit.signals.length().to_string() +
      " assigns=" +
      unit.assignments.length().to_string() +
      " instances=" +
      unit.instances.length().to_string() +
      "\n"
    for port in unit.ports {
      out += "  port " +
        format_signal(port, FormatOptions::default(), true) +
        "\n"
    }
    for instance in unit.instances {
      out += "  instance " +
        instance.module_name +
        " " +
        instance.instance_name +
        "\n"
    }
  }
  out
}

///|
/// Render token spans as a stable debugging table.
pub fn token_dump(source : String) -> String {
  let mut out = "offset\tline\tcolumn\tkind\ttext\n"
  for item in lex(source) {
    let kind = match item.kind {
      IdentifierToken => "identifier"
      NumberToken => "number"
      StringToken => "string"
      OperatorToken => "operator"
      PunctuationToken => "punctuation"
      DirectiveToken => "directive"
    }
    out += item.offset.to_string() +
      "\t" +
      item.line.to_string() +
      "\t" +
      item.column.to_string() +
      "\t" +
      kind +
      "\t" +
      item.text +
      "\n"
  }
  out
}

///|
/// Normalize whitespace between tokens while retaining comments only when requested.
pub fn normalize_tokens(source : String, include_comments : Bool) -> String {
  let tokens = lex(source)
  let mut out = ""
  let mut previous = ""
  for item in tokens {
    let needs_space = previous != "" &&
      (
        (
          previous[previous.length() - 1] >= 'a' &&
          previous[previous.length() - 1] <= 'z'
        ) ||
        (
          previous[previous.length() - 1] >= 'A' &&
          previous[previous.length() - 1] <= 'Z'
        ) ||
        (item.text[0] >= 'a' && item.text[0] <= 'z') ||
        (item.text[0] >= 'A' && item.text[0] <= 'Z')
      )
    if needs_space {
      out += " "
    }
    out += item.text
    if item.kind == DirectiveToken && include_comments {
      out += " "
    }
    previous = item.text
  }
  out
}

///|
/// Return a rough lexical density report for a source file.
pub fn lexical_report(source : String) -> String {
  let tokens = lex(source)
  let mut identifiers = 0
  let mut literals = 0
  let mut operators = 0
  for item in tokens {
    match item.kind {
      IdentifierToken | DirectiveToken => identifiers += 1
      NumberToken | StringToken => literals += 1
      OperatorToken => operators += 1
      PunctuationToken => ()
    }
  }
  "identifiers=" +
  identifiers.to_string() +
  " literals=" +
  literals.to_string() +
  " operators=" +
  operators.to_string()
}

///|
/// Return a simple source fingerprint for cache keys and regression reports.
pub fn source_fingerprint(source : String) -> String {
  let mut hash : UInt64 = 1469598103934665603
  for c in source.to_array() {
    hash = (hash ^ c.to_int().to_uint64()) * 1099511628211
  }
  hash.to_string()
}

///|
/// Render a diagnostic list with source excerpts.
pub fn diagnostics_with_excerpts(
  source : String,
  items : Array[Diagnostic],
) -> String {
  let mut out = ""
  for item in items {
    out += diagnostics_text([item]) +
      "\n" +
      diagnostic_excerpt(source, item) +
      "\n"
  }
  out
}
