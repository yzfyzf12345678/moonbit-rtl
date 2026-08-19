///|
/// A source position used by diagnostics.
pub struct Position {
  line : Int
  column : Int
}

///|
/// A half-open source span.
pub struct Span {
  start : Position
  end : Position
}

///|
/// A Verilog signal direction.
pub enum PortDirection {
  Input
  Output
  Inout
} derive(Eq)

///|
/// A signal declaration kind.
pub enum SignalKind {
  Wire
  Reg
  Port
} derive(Eq)

///|
/// A width expression in the supported Verilog subset.
pub struct Width {
  msb : Int
  lsb : Int
}

///|
/// A normalized net or variable kind from a Verilog declaration.
pub enum NetType {
  NetWire
  NetTri
  NetWand
  NetWor
  NetSupply0
  NetSupply1
  VariableReg
  VariableLogic
  VariableInteger
  VariableTime
  GenerateVariable
  UnknownNet(String)
} derive(Eq)

///|
/// A named module parameter.
pub struct Parameter {
  name : String
  value : String
  width : Width?
  span : Span
}

///|
/// Verilog expressions retained by the lightweight AST.
pub enum Expr {
  Name(String)
  Number(String)
  StringLiteral(String)
  Unary(String, Expr)
  Binary(Expr, String, Expr)
  Conditional(Expr, Expr, Expr)
  Concatenation(Array[Expr])
  Replication(Int, Expr)
  Index(Expr, Expr)
  PartSelect(Expr, Expr, Expr)
  Call(String, Array[Expr])
  Unknown(String)
}

///|
/// Public constructors keep editor and integration tests independent of the
/// package's read-only generated interface.
pub fn expr_name(name : String) -> Expr {
  Name(name)
}

///|
/// Construct a numeric expression.
pub fn expr_number(value : String) -> Expr {
  Number(value)
}

///|
/// Construct a binary expression.
pub fn expr_binary(left : Expr, operator : String, right : Expr) -> Expr {
  Binary(left, operator, right)
}

///|
/// Construct an indexed lvalue expression.
pub fn expr_index(value : Expr, index : Expr) -> Expr {
  Index(value, index)
}

///|
/// A connection from an instance port to a parent expression.
pub struct PortConnection {
  port : String
  expression : Expr?
  raw_expression : String
  span : Span
}

///|
/// A module instance and its named or positional connections.
pub struct ModuleInstance {
  module_name : String
  instance_name : String
  parameters : Array[Parameter]
  connections : Array[PortConnection]
  span : Span
}

///|
/// A parsed case item.
pub struct CaseItem {
  labels : Array[Expr]
  is_default : Bool
  statements : Array[Statement]
  span : Span
}

///|
/// The procedural construct kind used by an always block.
pub enum AlwaysKind {
  AlwaysLevel
  AlwaysPosedge
  AlwaysNegedge
  AlwaysAny
  AlwaysComb
  AlwaysLatch
  AlwaysFF
} derive(Eq)

///|
/// A structured procedural statement.
pub enum Statement {
  EmptyStatement
  ProceduralAssignment(Assignment)
  ConditionalStatement(Expr, Array[Statement], Array[Statement])
  CaseStatement(Expr, Array[CaseItem])
  BlockStatement(Array[Statement])
  InstanceStatement(ModuleInstance)
  ExpressionStatement(Expr)
  UnknownStatement(String)
}

///|
/// A named rule setting. The default checker remains compatible with the
/// original rule set while callers can suppress or downgrade individual IDs.
pub struct RuleSetting {
  code : String
  severity : Severity?
  enabled : Bool
}

///|
/// Configuration for the static checker.
pub struct CheckConfig {
  rules : Array[RuleSetting]
  include_info : Bool
  max_diagnostics : Int
  check_instances : Bool
  check_procedural : Bool
}

///|
/// A compact summary suitable for a CI status line.
pub struct CheckSummary {
  errors : Int
  warnings : Int
  infos : Int
  modules : Int
  signals : Int
  assignments : Int
  instances : Int
}

///|
/// A parse diagnostic is kept separate from semantic rule diagnostics.
pub struct ParseDiagnostic {
  code : String
  message : String
  line : Int
  column : Int
  severity : Severity
}

///|
/// A parse result that preserves recoverable syntax problems.
pub struct ParseResult {
  design : Design
  diagnostics : Array[ParseDiagnostic]
}

///|
/// Lexical category used by editor integrations and the parser.
pub enum TokenKind {
  IdentifierToken
  NumberToken
  StringToken
  OperatorToken
  PunctuationToken
  DirectiveToken
} derive(Eq)

///|
/// A named signal in a module.
pub struct Signal {
  name : String
  kind : SignalKind
  direction : PortDirection?
  width : Width?
  span : Span
}

///|
/// An assignment statement.
pub struct Assignment {
  lhs : String
  rhs : String
  span : Span
  operator : String
  lhs_expr : Expr?
  rhs_expr : Expr?
  procedural : Bool
}

///|
/// A sensitivity item in an always block.
pub struct Sensitivity {
  signal : String
  edge : String?
}

///|
/// A simplified always block.
pub struct AlwaysBlock {
  sensitivity : Array[Sensitivity]
  body : String
  span : Span
  kind : AlwaysKind
  statements : Array[Statement]
}

///|
/// A parsed Verilog module.
pub struct Module {
  name : String
  ports : Array[Signal]
  signals : Array[Signal]
  assignments : Array[Assignment]
  always_blocks : Array[AlwaysBlock]
  span : Span
  parameters : Array[Parameter]
  instances : Array[ModuleInstance]
  statements : Array[Statement]
}

///|
/// The root syntax tree.
pub struct Design {
  modules : Array[Module]
}

///|
/// Diagnostic severity.
pub enum Severity {
  Error
  Warning
  Info
} derive(Eq)

///|
/// A machine-readable rule diagnostic.
pub struct Diagnostic {
  code : String
  severity : Severity
  message : String
  line : Int
  column : Int
  signal : String?
  end_line : Int
  end_column : Int
  module_name : String?
  related : Array[String]
}

///|
/// Construct a diagnostic for adapters and black-box integration tests.
pub fn Diagnostic::new(
  code : String,
  severity : Severity,
  message : String,
  line : Int,
  column : Int,
) -> Diagnostic {
  {
    code,
    severity,
    message,
    line,
    column,
    signal: None,
    end_line: line,
    end_column: column,
    module_name: None,
    related: [],
  }
}

///|
pub fn Position::new(line : Int, column : Int) -> Position {
  { line, column }
}

///|
/// Return the number of bits described by a packed range.
pub fn Width::bits(self : Width) -> Int {
  (self.msb - self.lsb).abs() + 1
}

///|
/// Whether a packed range is descending, as is conventional in Verilog.
pub fn Width::is_descending(self : Width) -> Bool {
  self.msb >= self.lsb
}

///|
/// Construct a one-bit width.
pub fn Width::single() -> Width {
  { msb: 0, lsb: 0 }
}

///|
/// Return a stable human-readable expression representation.
pub fn Expr::to_text(self : Expr) -> String {
  match self {
    Name(name) => name
    Number(value) => value
    StringLiteral(value) => "\"" + value + "\""
    Unary(op, value) => op + value.to_text()
    Binary(left, op, right) =>
      "(" + left.to_text() + " " + op + " " + right.to_text() + ")"
    Conditional(condition, when_true, when_false) =>
      "(" +
      condition.to_text() +
      " ? " +
      when_true.to_text() +
      " : " +
      when_false.to_text() +
      ")"
    Concatenation(items) =>
      "{" + items.map(fn(item) { item.to_text() }).join(", ") + "}"
    Replication(count, value) =>
      "{" + count.to_string() + "{" + value.to_text() + "}}"
    Index(value, index) => value.to_text() + "[" + index.to_text() + "]"
    PartSelect(value, left, right) =>
      value.to_text() + "[" + left.to_text() + ":" + right.to_text() + "]"
    Call(name, args) =>
      name + "(" + args.map(fn(item) { item.to_text() }).join(", ") + ")"
    Unknown(value) => value
  }
}

///|
/// Collect identifier names referenced by an expression.
pub fn Expr::references(self : Expr) -> Array[String] {
  let result : Array[String] = []
  fn visit(expr : Expr, result : Array[String]) -> Unit {
    match expr {
      Name(name) => if !result.contains(name) { result.push(name) }
      Number(_) | StringLiteral(_) | Unknown(_) => ()
      Unary(_, value) => visit(value, result)
      Binary(left, _, right) => {
        visit(left, result)
        visit(right, result)
      }
      Conditional(condition, when_true, when_false) => {
        visit(condition, result)
        visit(when_true, result)
        visit(when_false, result)
      }
      Concatenation(items) =>
        for item in items {
          visit(item, result)
        }
      Replication(_, value) => visit(value, result)
      Index(value, index) => {
        visit(value, result)
        visit(index, result)
      }
      PartSelect(value, left, right) => {
        visit(value, result)
        visit(left, result)
        visit(right, result)
      }
      Call(name, args) => {
        if !result.contains(name) {
          result.push(name)
        }
        for item in args {
          visit(item, result)
        }
      }
    }
  }
  visit(self, result)
  result
}

///|
/// Return a conservative static width for an expression.
pub fn Expr::width(self : Expr, design_module : Module) -> Int? {
  match self {
    Number(value) =>
      if value.contains("'") {
        match value.split_once("'") {
          Some((prefix, _)) => Some(parse_decimal_text(prefix.to_owned()))
          None => Some(1)
        }
      } else {
        Some(32)
      }
    Name(name) => {
      for signal in design_module.ports {
        if signal.name == name {
          match signal.width {
            Some(width) => return Some(width.bits())
            None => return Some(1)
          }
        }
      }
      for signal in design_module.signals {
        if signal.name == name {
          match signal.width {
            Some(width) => return Some(width.bits())
            None => return Some(1)
          }
        }
      }
      None
    }
    StringLiteral(_) => None
    Unary(_, value) => value.width(design_module)
    Binary(left, _, right) =>
      match (left.width(design_module), right.width(design_module)) {
        (Some(a), Some(b)) => Some(if a > b { a } else { b })
        (Some(a), None) => Some(a)
        (None, Some(b)) => Some(b)
        _ => None
      }
    Conditional(_, yes, no) =>
      match (yes.width(design_module), no.width(design_module)) {
        (Some(a), Some(b)) => Some(if a > b { a } else { b })
        (Some(a), None) => Some(a)
        (None, Some(b)) => Some(b)
        _ => None
      }
    Concatenation(items) => {
      let mut total = 0
      for item in items {
        match item.width(design_module) {
          Some(width) => total += width
          None => return None
        }
      }
      Some(total)
    }
    Replication(count, value) =>
      value.width(design_module).map(fn(width) { count * width })
    Index(_, _) => Some(1)
    PartSelect(_, left, right) =>
      match (constant_int(left), constant_int(right)) {
        (Some(a), Some(b)) => Some((a - b).abs() + 1)
        _ => None
      }
    Call(_, _) | Unknown(_) => None
  }
}

///|
fn parse_decimal_text(text : String) -> Int {
  let mut value = 0
  for c in text.to_array() {
    if c >= '0' && c <= '9' {
      value = value * 10 + c.to_int() - '0'.to_int()
    }
  }
  value
}

///|
fn constant_int(expr : Expr) -> Int? {
  match expr {
    Number(value) => Some(parse_decimal_text(value))
    Unary(op, value) if op == "-" => constant_int(value).map(fn(x) { -x })
    Binary(left, op, right) =>
      match (constant_int(left), constant_int(right)) {
        (Some(a), Some(b)) =>
          match op {
            "+" => Some(a + b)
            "-" => Some(a - b)
            "*" => Some(a * b)
            "/" if b != 0 => Some(a / b)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
pub fn Span::single(line : Int, column : Int) -> Span {
  let p = Position::new(line, column)
  { start: p, end: p }
}

///|
/// Return a span with an explicit end position.
pub fn Span::range(start : Position, end : Position) -> Span {
  { start, end }
}

///|
pub fn Design::empty() -> Design {
  { modules: [] }
}

///|
/// Default checker settings for editor and CI integrations.
pub fn CheckConfig::default() -> CheckConfig {
  {
    rules: [],
    include_info: true,
    max_diagnostics: 1000,
    check_instances: true,
    check_procedural: true,
  }
}

///|
/// Disable one rule in a copy of a configuration.
pub fn CheckConfig::without(self : CheckConfig, code : String) -> CheckConfig {
  let rules = self.rules.copy()
  rules.push({ code, severity: None, enabled: false })
  { ..self, rules, }
}

///|
/// Override a rule's severity in a copy of a configuration.
pub fn CheckConfig::with_severity(
  self : CheckConfig,
  code : String,
  severity : Severity,
) -> CheckConfig {
  let rules = self.rules.copy()
  rules.push({ code, severity: Some(severity), enabled: true })
  { ..self, rules, }
}

///|
/// Suppress informational diagnostics in a copy of a configuration.
pub fn CheckConfig::without_info(self : CheckConfig) -> CheckConfig {
  { ..self, include_info: false }
}

///|
/// Cap the number of emitted diagnostics in a copy of a configuration.
pub fn CheckConfig::with_max_diagnostics(
  self : CheckConfig,
  max : Int,
) -> CheckConfig {
  { ..self, max_diagnostics: if max < 1 { 1 } else { max } }
}

///|
/// Count diagnostics by severity and collect basic design metrics.
pub fn CheckSummary::from(
  design : Design,
  diagnostics : Array[Diagnostic],
) -> CheckSummary {
  let mut errors = 0
  let mut warnings = 0
  let mut infos = 0
  for item in diagnostics {
    match item.severity {
      Error => errors += 1
      Warning => warnings += 1
      Info => infos += 1
    }
  }
  let mut signals = 0
  let mut assignments = 0
  let mut instances = 0
  for unit in design.modules {
    signals += unit.ports.length() + unit.signals.length()
    assignments += unit.assignments.length()
    instances += unit.instances.length()
  }
  {
    errors,
    warnings,
    infos,
    modules: design.modules.length(),
    signals,
    assignments,
    instances,
  }
}
