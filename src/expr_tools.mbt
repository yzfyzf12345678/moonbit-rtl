///|
fn decimal_value(text : String) -> Int? {
  let mut value = 0
  let mut seen = false
  let mut negative = false
  for i, c in text.to_array() {
    if i == 0 && c == '-' {
      negative = true
    } else if c >= '0' && c <= '9' {
      value = value * 10 + c.to_int() - '0'.to_int()
      seen = true
    } else if c == '_' {
      ()
    } else {
      return None
    }
  }
  if seen {
    Some(if negative { -value } else { value })
  } else {
    None
  }
}

///|
fn number_base(text : String) -> Int? {
  match text.split_once("'") {
    Some((_, suffix)) =>
      if suffix.length() == 0 {
        None
      } else if suffix[0] == 'b' || suffix[0] == 'B' {
        Some(2)
      } else if suffix[0] == 'o' || suffix[0] == 'O' {
        Some(8)
      } else if suffix[0] == 'd' || suffix[0] == 'D' {
        Some(10)
      } else if suffix[0] == 'h' || suffix[0] == 'H' {
        Some(16)
      } else {
        None
      }
    None => Some(10)
  }
}

///|
fn digit_value(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn based_number_value(text : String, base : Int) -> Int? {
  match text.split_once("'") {
    Some((_, suffix)) => {
      let digits = if suffix.length() > 1 { suffix[1:] } else { suffix[:] }
      let mut value = 0
      let mut seen = false
      for c in digits {
        match digit_value(c) {
          Some(digit) if digit < base => {
            value = value * base + digit
            seen = true
          }
          Some(_) => return None
          None if c == '_' => ()
          None if c == 'x' || c == 'X' || c == 'z' || c == 'Z' || c == '?' =>
            return None
          None => return None
        }
      }
      if seen {
        Some(value)
      } else {
        None
      }
    }
    None => decimal_value(text)
  }
}

///|
/// Evaluate a Verilog integer literal when it has no unknown digits.
pub fn evaluate_number(text : String) -> Int? {
  match number_base(text) {
    Some(10) =>
      match text.contains("'") {
        true => based_number_value(text, 10)
        false => decimal_value(text)
      }
    Some(base) => based_number_value(text, base)
    None => None
  }
}

///|
/// Evaluate a constant expression. Unknown identifiers and four-state values
/// return `None` rather than being guessed.
pub fn evaluate_constant(expr : Expr) -> Int? {
  match expr {
    Number(value) => evaluate_number(value)
    Unary(op, value) =>
      match evaluate_constant(value) {
        Some(number) =>
          match op {
            "+" => Some(number)
            "-" => Some(-number)
            "!" => Some(if number == 0 { 1 } else { 0 })
            "~" => Some(-number - 1)
            _ => None
          }
        None => None
      }
    Binary(left, op, right) =>
      match (evaluate_constant(left), evaluate_constant(right)) {
        (Some(a), Some(b)) =>
          match op {
            "+" => Some(a + b)
            "-" => Some(a - b)
            "*" => Some(a * b)
            "/" if b != 0 => Some(a / b)
            "%" if b != 0 => Some(a % b)
            "==" | "===" => Some(if a == b { 1 } else { 0 })
            "!=" | "!==" => Some(if a != b { 1 } else { 0 })
            "<" => Some(if a < b { 1 } else { 0 })
            "<=" => Some(if a <= b { 1 } else { 0 })
            ">" => Some(if a > b { 1 } else { 0 })
            ">=" => Some(if a >= b { 1 } else { 0 })
            "&&" => Some(if a != 0 && b != 0 { 1 } else { 0 })
            "||" => Some(if a != 0 || b != 0 { 1 } else { 0 })
            "&" => Some(a & b)
            "|" => Some(a | b)
            "^" => Some(a ^ b)
            "<<" => Some(a << b)
            ">>" => Some(a >> b)
            _ => None
          }
        _ => None
      }
    Conditional(condition, when_true, when_false) =>
      match evaluate_constant(condition) {
        Some(value) if value != 0 => evaluate_constant(when_true)
        Some(_) => evaluate_constant(when_false)
        None => None
      }
    Concatenation(items) => {
      let mut result = 0
      for item in items {
        match evaluate_constant(item) {
          Some(value) => result = result * 2 + value
          None => return None
        }
      }
      Some(result)
    }
    Replication(count, value) =>
      match evaluate_constant(value) {
        Some(number) => {
          let mut result = 0
          for _ in 0..<count {
            result = result * 2 + number
          }
          Some(result)
        }
        None => None
      }
    _ => None
  }
}

///|
/// Replace constant subexpressions with canonical decimal literals.
pub fn Expr::fold_constants(self : Expr) -> Expr {
  match self {
    Unary(op, value) => {
      let folded = value.fold_constants()
      match evaluate_constant(Unary(op, folded)) {
        Some(number) => Number(number.to_string())
        None => Unary(op, folded)
      }
    }
    Binary(left, op, right) => {
      let folded_left = left.fold_constants()
      let folded_right = right.fold_constants()
      match evaluate_constant(Binary(folded_left, op, folded_right)) {
        Some(number) => Number(number.to_string())
        None => Binary(folded_left, op, folded_right)
      }
    }
    Conditional(condition, when_true, when_false) => {
      let folded_condition = condition.fold_constants()
      let folded_true = when_true.fold_constants()
      let folded_false = when_false.fold_constants()
      match evaluate_constant(folded_condition) {
        Some(value) if value != 0 => folded_true
        Some(_) => folded_false
        None => Conditional(folded_condition, folded_true, folded_false)
      }
    }
    Concatenation(items) =>
      Concatenation(items.map(fn(item) { item.fold_constants() }))
    Replication(count, value) => Replication(count, value.fold_constants())
    Index(value, index) => Index(value.fold_constants(), index.fold_constants())
    PartSelect(value, left, right) =>
      PartSelect(
        value.fold_constants(),
        left.fold_constants(),
        right.fold_constants(),
      )
    Call(name, args) => Call(name, args.map(fn(item) { item.fold_constants() }))
    _ => self
  }
}

///|
/// Return the number of AST nodes in an expression.
pub fn Expr::node_count(self : Expr) -> Int {
  match self {
    Name(_) | Number(_) | StringLiteral(_) | Unknown(_) => 1
    Unary(_, value) => 1 + value.node_count()
    Binary(left, _, right) => 1 + left.node_count() + right.node_count()
    Conditional(condition, when_true, when_false) =>
      1 +
      condition.node_count() +
      when_true.node_count() +
      when_false.node_count()
    Concatenation(items) =>
      1 + items.fold(init=0, fn(total, item) { total + item.node_count() })
    Replication(_, value) => 1 + value.node_count()
    Index(value, index) => 1 + value.node_count() + index.node_count()
    PartSelect(value, left, right) =>
      1 + value.node_count() + left.node_count() + right.node_count()
    Call(_, args) =>
      1 + args.fold(init=0, fn(total, item) { total + item.node_count() })
  }
}

///|
fn max_int(left : Int, right : Int) -> Int {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn max_expr_depth(items : Array[Expr]) -> Int {
  let mut result = 0
  for item in items {
    result = max_int(result, item.depth())
  }
  result
}

///|
/// Return the maximum expression nesting depth.
pub fn Expr::depth(self : Expr) -> Int {
  match self {
    Name(_) | Number(_) | StringLiteral(_) | Unknown(_) => 1
    Unary(_, value) => 1 + value.depth()
    Binary(left, _, right) => 1 + max_int(left.depth(), right.depth())
    Conditional(condition, when_true, when_false) => {
      let a = condition.depth()
      let b = max_int(when_true.depth(), when_false.depth())
      1 + max_int(a, b)
    }
    Concatenation(items) => 1 + max_expr_depth(items)
    Replication(_, value) => 1 + value.depth()
    Index(value, index) => 1 + max_int(value.depth(), index.depth())
    PartSelect(value, left, right) =>
      1 + max_int(value.depth(), max_int(left.depth(), right.depth()))
    Call(_, args) => 1 + max_expr_depth(args)
  }
}

///|
/// Return the top-level signal name assigned by an l-value expression.
pub fn Expr::root_name(self : Expr) -> String? {
  match self {
    Name(name) => Some(name)
    Index(Name(name), _) | PartSelect(Name(name), _, _) => Some(name)
    _ => None
  }
}

///|
/// Whether an expression can legally appear on the left-hand side.
pub fn Expr::is_lvalue(self : Expr) -> Bool {
  match self {
    Name(_) | Index(_, _) | PartSelect(_, _, _) => true
    _ => false
  }
}

///|
/// Whether the expression contains a given operator.
pub fn Expr::contains_operator(self : Expr, wanted : String) -> Bool {
  match self {
    Unary(op, value) => op == wanted || value.contains_operator(wanted)
    Binary(left, op, right) =>
      op == wanted ||
      left.contains_operator(wanted) ||
      right.contains_operator(wanted)
    Conditional(condition, when_true, when_false) =>
      condition.contains_operator(wanted) ||
      when_true.contains_operator(wanted) ||
      when_false.contains_operator(wanted)
    Concatenation(items) =>
      items.any(fn(item) { item.contains_operator(wanted) })
    Replication(_, value) => value.contains_operator(wanted)
    Index(value, index) =>
      value.contains_operator(wanted) || index.contains_operator(wanted)
    PartSelect(value, left, right) =>
      value.contains_operator(wanted) ||
      left.contains_operator(wanted) ||
      right.contains_operator(wanted)
    Call(_, args) => args.any(fn(item) { item.contains_operator(wanted) })
    _ => false
  }
}

///|
/// A stable list of names read by an assignment.
pub fn Assignment::read_names(self : Assignment) -> Array[String] {
  match self.rhs_expr {
    Some(expr) => expr.references()
    None => []
  }
}

///|
/// Return the root name written by an assignment.
pub fn Assignment::write_name(self : Assignment) -> String? {
  match self.lhs_expr {
    Some(expr) => expr.root_name()
    None => Some(self.lhs)
  }
}

///|
/// Collect all signal names read in the module, including instance ports.
pub fn Module::read_names(self : Module) -> Array[String] {
  let result : Array[String] = []
  for assignment in self.assignments {
    for name in assignment.read_names() {
      if !result.contains(name) {
        result.push(name)
      }
    }
  }
  for block in self.always_blocks {
    for sensitivity in block.sensitivity {
      if !result.contains(sensitivity.signal) {
        result.push(sensitivity.signal)
      }
    }
  }
  for instance in self.instances {
    for connection in instance.connections {
      match connection.expression {
        Some(expr) =>
          for name in expr.references() {
            if !result.contains(name) {
              result.push(name)
            }
          }
        None => ()
      }
    }
  }
  result
}

///|
/// Collect all signal names written in the module.
pub fn Module::write_names(self : Module) -> Array[String] {
  let result : Array[String] = []
  for assignment in self.assignments {
    match assignment.write_name() {
      Some(name) if !result.contains(name) => result.push(name)
      _ => ()
    }
  }
  result
}

///|
/// A module is combinational when it has no edge-triggered procedural block.
pub fn Module::is_combinational(self : Module) -> Bool {
  for block in self.always_blocks {
    if block.kind == AlwaysPosedge ||
      block.kind == AlwaysNegedge ||
      block.kind == AlwaysFF {
      return false
    }
  }
  true
}

///|
/// Return sensitivity signals that look like clocks.
pub fn Module::clock_names(self : Module) -> Array[String] {
  let result : Array[String] = []
  for block in self.always_blocks {
    if block.kind == AlwaysPosedge ||
      block.kind == AlwaysNegedge ||
      block.kind == AlwaysFF {
      for item in block.sensitivity {
        if !result.contains(item.signal) {
          result.push(item.signal)
        }
      }
    }
  }
  result
}
