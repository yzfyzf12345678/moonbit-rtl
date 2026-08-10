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
}

///|
/// A width expression in the supported Verilog subset.
pub struct Width {
  msb : Int
  lsb : Int
}

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
}

///|
/// A machine-readable rule diagnostic.
pub struct Diagnostic {
  code : String
  severity : Severity
  message : String
  line : Int
  column : Int
  signal : String?
}

///|
pub fn Position::new(line : Int, column : Int) -> Position {
  { line, column }
}

///|
pub fn Span::single(line : Int, column : Int) -> Span {
  let p = Position::new(line, column)
  { start: p, end: p }
}

///|
pub fn Design::empty() -> Design {
  { modules: [] }
}
