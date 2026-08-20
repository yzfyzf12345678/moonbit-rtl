///|
/// A normalized expression used by downstream analysis and code generation.
pub enum IrExpr {
  IrConstant(String)
  IrSignal(String)
  IrUnary(String, IrExpr)
  IrBinary(IrExpr, String, IrExpr)
  IrMux(IrExpr, IrExpr, IrExpr)
  IrConcat(Array[IrExpr])
  IrRepeat(Int, IrExpr)
  IrSelect(IrExpr, IrExpr, IrExpr?)
  IrCall(String, Array[IrExpr])
  IrUnknown(String)
} derive(Eq)

///|
/// One normalized assignment or control instruction.
pub enum IrInstruction {
  IrAssign(String, IrExpr, Bool)
  IrAssume(IrExpr)
  IrAssert(IrExpr)
  IrBranch(IrExpr, Array[IrInstruction], Array[IrInstruction])
  IrInstance(String, String, Array[(String, IrExpr)])
  IrComment(String)
} derive(Eq)

///|
/// A normalized module-level intermediate representation.
pub struct IrModule {
  name : String
  parameters : Array[Parameter]
  ports : Array[Signal]
  signals : Array[Signal]
  instructions : Array[IrInstruction]
  dependencies : Array[String]
}

///|
/// A complete IR design suitable for analysis passes.
pub struct IrDesign {
  modules : Array[IrModule]
  source_hash : String
  optimized : Bool
  passes : Array[String]
}

///|
fn ir_expr_text(expr : IrExpr) -> String {
  match expr {
    IrConstant(value) => value
    IrSignal(name) => name
    IrUnary(operator, value) => operator + value.ir_text()
    IrBinary(left, operator, right) =>
      "(" + left.ir_text() + " " + operator + " " + right.ir_text() + ")"
    IrMux(condition, yes, no) =>
      "(" +
      condition.ir_text() +
      " ? " +
      yes.ir_text() +
      " : " +
      no.ir_text() +
      ")"
    IrConcat(items) =>
      "{" + items.map(fn(item) { item.ir_text() }).join(",") + "}"
    IrRepeat(count, value) =>
      "{" + count.to_string() + "{" + value.ir_text() + "}}"
    IrSelect(value, left, right) => {
      let suffix = match right {
        Some(item) => ":" + item.ir_text()
        None => ""
      }
      value.ir_text() + "[" + left.ir_text() + suffix + "]"
    }
    IrCall(name, args) =>
      name + "(" + args.map(fn(item) { item.ir_text() }).join(",") + ")"
    IrUnknown(value) => "?" + value
  }
}

///|
pub fn IrExpr::ir_text(self : IrExpr) -> String {
  ir_expr_text(self)
}

///|
fn ir_instruction_text(instruction : IrInstruction, indent : Int) -> String {
  let prefix = "  ".repeat(indent)
  match instruction {
    IrAssign(target, value, procedural) =>
      prefix +
      (if procedural { "reg " } else { "wire " }) +
      target +
      " = " +
      value.ir_text() +
      ";"
    IrAssume(value) => prefix + "assume " + value.ir_text() + ";"
    IrAssert(value) => prefix + "assert " + value.ir_text() + ";"
    IrBranch(condition, yes, no) =>
      prefix +
      "if (" +
      condition.ir_text() +
      ") {\n" +
      yes.map(fn(item) { ir_instruction_text(item, indent + 1) }).join("\n") +
      "\n" +
      prefix +
      "} else {\n" +
      no.map(fn(item) { ir_instruction_text(item, indent + 1) }).join("\n") +
      "\n" +
      prefix +
      "}"
    IrInstance(module_name, instance_name, connections) =>
      prefix +
      module_name +
      " " +
      instance_name +
      "(" +
      connections
      .map(fn(item) { "." + item.0 + "(" + item.1.ir_text() + ")" })
      .join(", ") +
      ");"
    IrComment(text) => prefix + "// " + text
  }
}

///|
fn ir_lower_expr(expr : Expr) -> IrExpr {
  match expr {
    Name(name) => IrSignal(name)
    Number(value) => IrConstant(value)
    StringLiteral(value) => IrConstant("\"" + value + "\"")
    Unary(operator, value) => IrUnary(operator, ir_lower_expr(value))
    Binary(left, operator, right) =>
      IrBinary(ir_lower_expr(left), operator, ir_lower_expr(right))
    Conditional(condition, yes, no) =>
      IrMux(ir_lower_expr(condition), ir_lower_expr(yes), ir_lower_expr(no))
    Concatenation(items) => IrConcat(items.map(ir_lower_expr))
    Replication(count, value) => IrRepeat(count, ir_lower_expr(value))
    Index(value, index) =>
      IrSelect(ir_lower_expr(value), ir_lower_expr(index), None)
    PartSelect(value, left, right) =>
      IrSelect(
        ir_lower_expr(value),
        ir_lower_expr(left),
        Some(ir_lower_expr(right)),
      )
    Call(name, args) => IrCall(name, args.map(ir_lower_expr))
    Unknown(value) => IrUnknown(value)
  }
}

///|
fn ir_lower_statement(statement : Statement) -> IrInstruction {
  match statement {
    ProceduralAssignment(assignment) =>
      IrAssign(
        assignment.lhs,
        assignment.rhs_expr
        .map(ir_lower_expr)
        .unwrap_or(IrUnknown(assignment.rhs)),
        true,
      )
    ConditionalStatement(condition, yes, no) =>
      IrBranch(
        ir_lower_expr(condition),
        yes.map(ir_lower_statement),
        no.map(ir_lower_statement),
      )
    CaseStatement(expression, items) => {
      let mut chain : IrInstruction = IrComment(
        "case " + ir_lower_expr(expression).ir_text(),
      )
      for item in items.rev() {
        let body = item.statements.map(ir_lower_statement)
        let condition = if item.is_default {
          IrConstant("1")
        } else {
          IrConcat(item.labels.map(ir_lower_expr))
        }
        chain = IrBranch(condition, body, [chain])
      }
      chain
    }
    BlockStatement(items) =>
      IrComment(
        items.map(fn(item) { ir_lower_statement(item).ir_text() }).join("\n"),
      )
    InstanceStatement(instance) =>
      IrInstance(
        instance.module_name,
        instance.instance_name,
        instance.connections.map(fn(item) {
          (
            item.port,
            item.expression
            .map(ir_lower_expr)
            .unwrap_or(IrUnknown(item.raw_expression)),
          )
        }),
      )
    ExpressionStatement(expr) => IrAssume(ir_lower_expr(expr))
    EmptyStatement => IrComment("empty")
    UnknownStatement(text) => IrComment(text)
  }
}

///|
fn IrInstruction::ir_text(self : IrInstruction) -> String {
  ir_instruction_text(self, 0)
}

///|
fn ir_module_dependencies(unit : Module) -> Array[String] {
  let result : Array[String] = []
  for instance in unit.instances {
    if !result.contains(instance.module_name) {
      result.push(instance.module_name)
    }
  }
  result
}

///|
fn ir_lower_module(unit : Module) -> IrModule {
  let instructions : Array[IrInstruction] = []
  for assignment in unit.assignments {
    instructions.push(
      IrAssign(
        assignment.lhs,
        assignment.rhs_expr
        .map(ir_lower_expr)
        .unwrap_or(IrUnknown(assignment.rhs)),
        assignment.procedural,
      ),
    )
  }
  for block in unit.always_blocks {
    for statement in block.statements {
      instructions.push(ir_lower_statement(statement))
    }
  }
  for instance in unit.instances {
    instructions.push(
      IrInstance(
        instance.module_name,
        instance.instance_name,
        instance.connections.map(fn(item) {
          (
            item.port,
            item.expression
            .map(ir_lower_expr)
            .unwrap_or(IrUnknown(item.raw_expression)),
          )
        }),
      ),
    )
  }
  {
    name: unit.name,
    parameters: unit.parameters,
    ports: unit.ports,
    signals: unit.signals,
    instructions,
    dependencies: ir_module_dependencies(unit),
  }
}

///|
/// Lower a parsed design to a stable package-local IR.
pub fn lower_ir(design : Design, source : String) -> IrDesign {
  {
    modules: design.modules.map(ir_lower_module),
    source_hash: source_hash(source),
    optimized: false,
    passes: [],
  }
}

///|
pub fn lower_ir_source(source : String) -> IrDesign {
  lower_ir(parse(source), source)
}

///|
fn ir_expr_constant(expr : IrExpr) -> String? {
  match expr {
    IrConstant(value) => Some(value)
    IrUnary(operator, value) =>
      ir_expr_constant(value).map(fn(text) { operator + text })
    IrBinary(left, operator, right) =>
      match (ir_expr_constant(left), ir_expr_constant(right)) {
        (Some(a), Some(b)) =>
          evaluate_number(a + operator + b).map(fn(value) { value.to_string() })
        _ => None
      }
    _ => None
  }
}

///|
fn ir_optimize_expr(expr : IrExpr) -> IrExpr {
  match expr {
    IrUnary(operator, value) => {
      let optimized = ir_optimize_expr(value)
      match ir_expr_constant(IrUnary(operator, optimized)) {
        Some(value) => IrConstant(value)
        None => IrUnary(operator, optimized)
      }
    }
    IrBinary(left, operator, right) => {
      let optimized = IrBinary(
        ir_optimize_expr(left),
        operator,
        ir_optimize_expr(right),
      )
      match ir_expr_constant(optimized) {
        Some(value) => IrConstant(value)
        None => optimized
      }
    }
    IrMux(condition, yes, no) =>
      IrMux(
        ir_optimize_expr(condition),
        ir_optimize_expr(yes),
        ir_optimize_expr(no),
      )
    IrConcat(items) => IrConcat(items.map(ir_optimize_expr))
    IrRepeat(count, value) => IrRepeat(count, ir_optimize_expr(value))
    IrSelect(value, left, right) =>
      IrSelect(
        ir_optimize_expr(value),
        ir_optimize_expr(left),
        right.map(ir_optimize_expr),
      )
    IrCall(name, args) => IrCall(name, args.map(ir_optimize_expr))
    value => value
  }
}

///|
fn ir_optimize_instruction(instruction : IrInstruction) -> IrInstruction {
  match instruction {
    IrAssign(target, value, procedural) =>
      IrAssign(target, ir_optimize_expr(value), procedural)
    IrAssume(value) => IrAssume(ir_optimize_expr(value))
    IrAssert(value) => IrAssert(ir_optimize_expr(value))
    IrBranch(condition, yes, no) =>
      IrBranch(
        ir_optimize_expr(condition),
        yes.map(ir_optimize_instruction),
        no.map(ir_optimize_instruction),
      )
    IrInstance(module_name, instance_name, connections) =>
      IrInstance(
        module_name,
        instance_name,
        connections.map(fn(item) { (item.0, ir_optimize_expr(item.1)) }),
      )
    value => value
  }
}

///|
pub fn IrDesign::constant_fold(self : IrDesign) -> IrDesign {
  let modules = self.modules.map(fn(unit) {
    { ..unit, instructions: unit.instructions.map(ir_optimize_instruction) }
  })
  let passes = self.passes.copy()
  passes.push("constant_fold")
  { ..self, modules, optimized: true, passes }
}

///|
fn ir_keep_instruction(item : IrInstruction) -> Bool {
  match item {
    IrComment(_) => false
    _ => true
  }
}

///|
pub fn IrDesign::remove_comments(self : IrDesign) -> IrDesign {
  let modules = self.modules.map(fn(unit) {
    { ..unit, instructions: unit.instructions.filter(ir_keep_instruction) }
  })
  let passes = self.passes.copy()
  passes.push("remove_comments")
  { ..self, modules, passes }
}

///|
pub fn IrDesign::find_module(self : IrDesign, name : String) -> IrModule? {
  self.modules.filter(fn(item) { item.name == name }).get(0)
}

///|
pub fn IrModule::instruction_count(self : IrModule) -> Int {
  self.instructions.length()
}

///|
pub fn IrModule::signal_names(self : IrModule) -> Array[String] {
  self.ports.map(fn(item) { item.name }) +
  self.signals.map(fn(item) { item.name })
}

///|
pub fn IrModule::uses(self : IrModule, name : String) -> Bool {
  self.instructions.any(fn(item) { item.ir_text().contains(name) })
}

///|
pub fn IrModule::to_text(self : IrModule) -> String {
  "module " +
  self.name +
  "\n" +
  self.instructions.map(IrInstruction::ir_text).join("\n")
}

///|
pub fn IrDesign::to_text(self : IrDesign) -> String {
  self.modules.map(IrModule::to_text).join("\n\n")
}

///|
pub fn IrDesign::to_json(self : IrDesign) -> String {
  let modules = self.modules
    .map(fn(unit) {
      "{\"name\":\"" +
      json_escape(unit.name) +
      "\",\"dependencies\":[" +
      unit.dependencies
      .map(fn(item) { "\"" + json_escape(item) + "\"" })
      .join(",") +
      "],\"instructions\":[" +
      unit.instructions
      .map(fn(item) { "\"" + json_escape(item.ir_text()) + "\"" })
      .join(",") +
      "]}"
    })
    .join(",")
  "{\"source_hash\":\"" +
  self.source_hash +
  "\",\"optimized\":" +
  (if self.optimized { "true" } else { "false" }) +
  ",\"passes\":[" +
  self.passes.map(fn(item) { "\"" + item + "\"" }).join(",") +
  "],\"modules\":[" +
  modules +
  "]}"
}

///|
pub fn IrDesign::ir_dead_signal_names(self : IrDesign) -> Array[String] {
  let result : Array[String] = []
  for unit in self.modules {
    for signal in unit.signal_names() {
      if !unit.uses(signal) {
        result.push(unit.name + ":" + signal)
      }
    }
  }
  result
}

///|
pub fn ir_diagnostics(ir : IrDesign) -> Array[Diagnostic] {
  ir
  .ir_dead_signal_names()
  .map(fn(name) {
    Diagnostic::new("IR001", Info, "IR signal is not read: " + name, 1, 1)
  })
}

///|
pub fn ir_contract() -> String {
  "representation=normalized_module_instruction; passes=constant_fold,remove_comments; " +
  "source_hash=tracked; consumers=timing,coverage,formal,codegen"
}
