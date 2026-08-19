///|
fn is_numeric_token(text : String) -> Bool {
  let chars = text.to_array()
  if chars.length() == 0 {
    false
  } else {
    let first = chars[0]
    (first >= '0' && first <= '9') || first == '\''
  }
}

///|
fn is_string_token(text : String) -> Bool {
  text.length() >= 2 && text[0] == '"'
}

///|
fn is_unary_operator(text : String) -> Bool {
  text == "!" ||
  text == "~" ||
  text == "+" ||
  text == "-" ||
  text == "&" ||
  text == "|" ||
  text == "^"
}

///|
fn operator_precedence(text : String) -> Int {
  if text == "||" {
    1
  } else if text == "&&" {
    2
  } else if text == "|" {
    3
  } else if text == "^" || text == "^~" || text == "~^" {
    4
  } else if text == "&" {
    5
  } else if text == "==" || text == "!=" || text == "===" || text == "!==" {
    6
  } else if text == "<" || text == "<=" || text == ">" || text == ">=" {
    7
  } else if text == "<<" || text == ">>" || text == "<<<" || text == ">>>" {
    8
  } else if text == "+" || text == "-" {
    9
  } else if text == "*" || text == "/" || text == "%" {
    10
  } else {
    0
  }
}

///|
fn find_closing(
  tokens : Array[Token],
  start : Int,
  opening : String,
  closing : String,
  end : Int,
) -> Int {
  let mut depth = 0
  for i in start..<end {
    if token_text(tokens, i) == opening {
      depth += 1
    } else if token_text(tokens, i) == closing {
      depth -= 1
      if depth == 0 {
        return i
      }
    }
  }
  end
}

///|
fn parse_primary(tokens : Array[Token], start : Int, end : Int) -> (Expr, Int) {
  if start >= end {
    return (Unknown(""), start)
  }
  let text = token_text(tokens, start)
  let initial : (Expr, Int) = if is_unary_operator(text) {
    let (value, next) = parse_primary(tokens, start + 1, end)
    (Unary(text, value), next)
  } else if text == "(" {
    let close = find_closing(tokens, start, "(", ")", end)
    let inner = parse_expression_range(tokens, start + 1, close)
    (inner, if close < end { close + 1 } else { close })
  } else if text == "{" {
    let close = find_closing(tokens, start, "{", "}", end)
    let pieces = split_top_level(tokens, start + 1, close, ",")
    let items : Array[Expr] = []
    for piece in pieces {
      let (piece_start, piece_end) = piece
      if piece_start < piece_end {
        items.push(parse_expression_range(tokens, piece_start, piece_end))
      }
    }
    if items.length() == 2 {
      match items[0] {
        Number(value) =>
          (
            Replication(parse_decimal(value), items[1]),
            if close < end {
              close + 1
            } else {
              close
            },
          )
        _ => (Concatenation(items), if close < end { close + 1 } else { close })
      }
    } else {
      (Concatenation(items), if close < end { close + 1 } else { close })
    }
  } else if is_string_token(text) {
    (StringLiteral(text), start + 1)
  } else if is_numeric_token(text) {
    (Number(text), start + 1)
  } else {
    (Name(text), start + 1)
  }
  let (base, next) = initial
  parse_postfix(tokens, base, next, end)
}

///|
fn parse_postfix(
  tokens : Array[Token],
  base : Expr,
  start : Int,
  end : Int,
) -> (Expr, Int) {
  if start >= end {
    return (base, start)
  }
  let text = token_text(tokens, start)
  if text == "[" {
    let close = find_closing(tokens, start, "[", "]", end)
    let colon = find_top_level_token(tokens, start + 1, close, ":")
    let next = if close < end { close + 1 } else { close }
    match colon {
      Some(position) => {
        let left = parse_expression_range(tokens, start + 1, position)
        let right = parse_expression_range(tokens, position + 1, close)
        parse_postfix(tokens, PartSelect(base, left, right), next, end)
      }
      None => {
        let index = parse_expression_range(tokens, start + 1, close)
        parse_postfix(tokens, Index(base, index), next, end)
      }
    }
  } else if text == "(" {
    let close = find_closing(tokens, start, "(", ")", end)
    let args : Array[Expr] = []
    for piece in split_top_level(tokens, start + 1, close, ",") {
      let (piece_start, piece_end) = piece
      if piece_start < piece_end {
        args.push(parse_expression_range(tokens, piece_start, piece_end))
      }
    }
    let call_name = match base {
      Name(name) => name
      _ => base.to_text()
    }
    parse_postfix(
      tokens,
      Call(call_name, args),
      if close < end {
        close + 1
      } else {
        close
      },
      end,
    )
  } else {
    (base, start)
  }
}

///|
fn parse_expression_precedence(
  tokens : Array[Token],
  start : Int,
  end : Int,
  minimum : Int,
) -> (Expr, Int) {
  let initial = parse_primary(tokens, start, end)
  let mut left = initial.0
  let mut position = initial.1
  while position < end {
    let operator = token_text(tokens, position)
    let precedence = operator_precedence(operator)
    if precedence < minimum || precedence == 0 {
      break
    }
    let (right, next) = parse_expression_precedence(
      tokens,
      position + 1,
      end,
      precedence + 1,
    )
    left = Binary(left, operator, right)
    position = next
  }
  if position < end && token_text(tokens, position) == "?" && minimum <= 1 {
    let colon = find_top_level_token(tokens, position + 1, end, ":")
    match colon {
      Some(colon_position) => {
        let when_true = parse_expression_range(
          tokens,
          position + 1,
          colon_position,
        )
        let when_false = parse_expression_range(tokens, colon_position + 1, end)
        (Conditional(left, when_true, when_false), end)
      }
      None => (left, position)
    }
  } else {
    (left, position)
  }
}

///|
fn parse_expression_range(
  tokens : Array[Token],
  start : Int,
  end : Int,
) -> Expr {
  let (value, _) = parse_expression_precedence(tokens, start, end, 1)
  value
}

///|
fn split_top_level(
  tokens : Array[Token],
  start : Int,
  end : Int,
  separator : String,
) -> Array[(Int, Int)] {
  let result : Array[(Int, Int)] = []
  let mut piece_start = start
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  for i in start..<end {
    let text = token_text(tokens, i)
    if text == "(" {
      paren += 1
    }
    if text == ")" {
      paren -= 1
    }
    if text == "[" {
      bracket += 1
    }
    if text == "]" {
      bracket -= 1
    }
    if text == "{" {
      brace += 1
    }
    if text == "}" {
      brace -= 1
    }
    if text == separator && paren == 0 && bracket == 0 && brace == 0 {
      result.push((piece_start, i))
      piece_start = i + 1
    }
  }
  result.push((piece_start, end))
  result
}

///|
fn find_top_level_token(
  tokens : Array[Token],
  start : Int,
  end : Int,
  wanted : String,
) -> Int? {
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  for i in start..<end {
    let text = token_text(tokens, i)
    if text == "(" {
      paren += 1
    }
    if text == ")" {
      paren -= 1
    }
    if text == "[" {
      bracket += 1
    }
    if text == "]" {
      bracket -= 1
    }
    if text == "{" {
      brace += 1
    }
    if text == "}" {
      brace -= 1
    }
    if text == wanted && paren == 0 && bracket == 0 && brace == 0 {
      return Some(i)
    }
  }
  None
}

///|
fn parse_net_type(text : String) -> NetType {
  if text == "wire" {
    NetWire
  } else if text == "tri" {
    NetTri
  } else if text == "wand" {
    NetWand
  } else if text == "wor" {
    NetWor
  } else if text == "supply0" {
    NetSupply0
  } else if text == "supply1" {
    NetSupply1
  } else if text == "reg" {
    VariableReg
  } else if text == "logic" {
    VariableLogic
  } else if text == "integer" {
    VariableInteger
  } else if text == "time" {
    VariableTime
  } else if text == "genvar" {
    GenerateVariable
  } else {
    UnknownNet(text)
  }
}

///|
fn parse_parameter_list(
  tokens : Array[Token],
  start : Int,
  end : Int,
) -> Array[Parameter] {
  let result : Array[Parameter] = []
  let mut i = start
  while i < end {
    let word = token_text(tokens, i)
    if word == "parameter" || word == "localparam" {
      let statement_end = find_top_level_token(tokens, i + 1, end, ";").unwrap_or(
        end,
      )
      let equals = find_top_level_token(tokens, i + 1, statement_end, "=")
      let name_position = i + 1
      if name_position < statement_end {
        let name = token_text(tokens, name_position)
        let value = match equals {
          Some(eq) => tokens_to_text(tokens, eq + 1, statement_end)
          None => ""
        }
        result.push({
          name,
          value,
          width: None,
          span: Span::single(token_line(tokens, i), tokens[i].column),
        })
      }
      i = statement_end + 1
    } else {
      i += 1
    }
  }
  result
}

///|
fn parse_connection_piece(
  tokens : Array[Token],
  start : Int,
  end : Int,
) -> PortConnection {
  let dot = if start < end && token_text(tokens, start) == "." {
    start + 1
  } else {
    start
  }
  let named = dot < end && dot + 1 < end && token_text(tokens, dot + 1) == "("
  if named {
    let close = find_closing(tokens, dot + 1, "(", ")", end)
    let raw = tokens_to_text(tokens, dot + 2, close)
    {
      port: token_text(tokens, dot),
      expression: if dot + 2 < close {
        Some(parse_expression_range(tokens, dot + 2, close))
      } else {
        None
      },
      raw_expression: raw,
      span: Span::single(token_line(tokens, dot), tokens[dot].column),
    }
  } else {
    let raw = tokens_to_text(tokens, start, end)
    {
      port: "",
      expression: if start < end {
        Some(parse_expression_range(tokens, start, end))
      } else {
        None
      },
      raw_expression: raw,
      span: Span::single(token_line(tokens, start), tokens[start].column),
    }
  }
}

///|
fn parse_instance_at(
  tokens : Array[Token],
  start : Int,
  end : Int,
) -> ModuleInstance? {
  if start + 2 >= end {
    return None
  }
  let module_name = token_text(tokens, start)
  let mut name_position = start + 1
  if token_text(tokens, name_position) == "#" {
    let open = find_top_level_token(tokens, name_position, end, "(")
    name_position = match open {
      Some(open_position) =>
        find_closing(tokens, open_position, "(", ")", end) + 1
      None => name_position + 1
    }
  }
  if name_position >= end || token_text(tokens, name_position + 1) != "(" {
    return None
  }
  let open = name_position + 1
  let close = find_closing(tokens, open, "(", ")", end)
  let connections : Array[PortConnection] = []
  for piece in split_top_level(tokens, open + 1, close, ",") {
    let (piece_start, piece_end) = piece
    if piece_start < piece_end {
      connections.push(parse_connection_piece(tokens, piece_start, piece_end))
    }
  }
  Some({
    module_name,
    instance_name: token_text(tokens, name_position),
    parameters: [],
    connections,
    span: Span::single(token_line(tokens, start), tokens[start].column),
  })
}

///|
fn assignment_from_old(assignment : Assignment) -> Assignment {
  let left_tokens = lex(assignment.lhs)
  let right_tokens = lex(assignment.rhs)
  {
    ..assignment,
    lhs_expr: Some(parse_expression_range(left_tokens, 0, left_tokens.length())),
    rhs_expr: Some(
      parse_expression_range(right_tokens, 0, right_tokens.length()),
    ),
  }
}

///|
fn always_kind(text : String) -> AlwaysKind {
  if text == "always_ff" {
    AlwaysFF
  } else if text == "always_comb" {
    AlwaysComb
  } else if text == "always_latch" {
    AlwaysLatch
  } else if text.contains("posedge") {
    AlwaysPosedge
  } else if text.contains("negedge") {
    AlwaysNegedge
  } else if text.contains("@*") || text.contains("@ *") {
    AlwaysAny
  } else {
    AlwaysLevel
  }
}

///|
fn statement_from_tokens(
  tokens : Array[Token],
  start : Int,
  end : Int,
) -> Statement {
  if start >= end {
    EmptyStatement
  } else {
    let first = token_text(tokens, start)
    if first == "if" {
      let open = find_top_level_token(tokens, start, end, "(")
      let close = match open {
        Some(position) => find_closing(tokens, position, "(", ")", end)
        None => start
      }
      let condition = if close > start {
        parse_expression_range(tokens, open.unwrap_or(start) + 1, close)
      } else {
        Unknown("")
      }
      ConditionalStatement(condition, [], [])
    } else if first == "case" || first == "casez" || first == "casex" {
      let open = find_top_level_token(tokens, start, end, "(")
      let close = match open {
        Some(position) => find_closing(tokens, position, "(", ")", end)
        None => start
      }
      let condition = if close > start {
        parse_expression_range(tokens, open.unwrap_or(start) + 1, close)
      } else {
        Unknown("")
      }
      CaseStatement(condition, [parse_case_item(tokens, close + 1, end)])
    } else if first == "begin" {
      BlockStatement([])
    } else {
      let nonblocking = find_top_level_token(tokens, start, end, "<=")
      let blocking = find_top_level_token(tokens, start, end, "=")
      match (nonblocking, blocking) {
        (Some(eq), _) | (_, Some(eq)) => {
          let lhs = tokens_to_text(tokens, start, eq)
          let rhs = tokens_to_text(tokens, eq + 1, end)
          ProceduralAssignment({
            lhs,
            rhs,
            span: Span::single(token_line(tokens, start), tokens[start].column),
            operator: match nonblocking {
              Some(_) => "<="
              None => "="
            },
            lhs_expr: Some(parse_expression_range(tokens, start, eq)),
            rhs_expr: Some(parse_expression_range(tokens, eq + 1, end)),
            procedural: true,
          })
        }
        _ =>
          if first == "endmodule" {
            EmptyStatement
          } else if first == "assign" {
            ExpressionStatement(Name(first))
          } else if parse_instance_at(tokens, start, end) is Some(instance) {
            InstanceStatement(instance)
          } else if is_numeric_token(first) {
            ExpressionStatement(Number(first))
          } else {
            UnknownStatement(tokens_to_text(tokens, start, end))
          }
      }
    }
  }
}

///|
fn parse_case_item(tokens : Array[Token], start : Int, end : Int) -> CaseItem {
  let colon = find_top_level_token(tokens, start, end, ":")
  let label_end = colon.unwrap_or(start)
  let labels : Array[Expr] = []
  if token_text(tokens, start) == "default" {
    {
      labels,
      is_default: true,
      statements: [],
      span: Span::single(token_line(tokens, start), tokens[start].column),
    }
  } else {
    for piece in split_top_level(tokens, start, label_end, ",") {
      let (piece_start, piece_end) = piece
      if piece_start < piece_end {
        labels.push(parse_expression_range(tokens, piece_start, piece_end))
      }
    }
    {
      labels,
      is_default: false,
      statements: if label_end < end {
        [statement_from_tokens(tokens, label_end + 1, end)]
      } else {
        []
      },
      span: Span::single(token_line(tokens, start), tokens[start].column),
    }
  }
}

///|
fn enrich_module(
  tokens : Array[Token],
  unit : Module,
  module_start : Int,
  module_end : Int,
) -> Module {
  let parameters = parse_parameter_list(tokens, module_start, module_end)
  let assignments = unit.assignments.map(fn(item) { assignment_from_old(item) })
  let always_blocks = unit.always_blocks.map(fn(item) {
    {
      ..item,
      kind: always_kind(item.body),
      statements: if item.body != "" {
        let body_tokens = lex(item.body)
        [statement_from_tokens(body_tokens, 0, body_tokens.length())]
      } else {
        []
      },
    }
  })
  let instances : Array[ModuleInstance] = []
  let mut i = module_start + 2
  while i < module_end {
    let first = token_text(tokens, i)
    let ignored = first == "input" ||
      first == "output" ||
      first == "inout" ||
      first == "wire" ||
      first == "reg" ||
      first == "logic" ||
      first == "assign" ||
      first == "always" ||
      first == "always_ff" ||
      first == "always_comb" ||
      first == "always_latch" ||
      first == "parameter" ||
      first == "localparam" ||
      first == "if" ||
      first == "case" ||
      first == "begin"
    if first == "wire" ||
      first == "tri" ||
      first == "wand" ||
      first == "wor" ||
      first == "supply0" ||
      first == "supply1" ||
      first == "reg" ||
      first == "logic" ||
      first == "integer" ||
      first == "time" ||
      first == "genvar" {
      ignore(parse_net_type(first))
    }
    if !ignored && i + 2 < module_end && token_text(tokens, i + 2) == "(" {
      let statement_end = find_top_level_token(tokens, i + 2, module_end, ";").unwrap_or(
        module_end,
      )
      match parse_instance_at(tokens, i, statement_end) {
        Some(instance) => {
          instances.push(instance)
          i = statement_end + 1
        }
        None => i += 1
      }
    } else {
      i += 1
    }
  }
  let statements : Array[Statement] = []
  for assignment in assignments {
    statements.push(ProceduralAssignment(assignment))
  }
  for instance in instances {
    statements.push(InstanceStatement(instance))
  }
  { ..unit, parameters, assignments, always_blocks, instances, statements }
}

///|
/// Parse the practical Verilog subset and enrich the legacy-compatible AST
/// with expression and procedural structure.
pub fn parse(source : String) -> Design {
  let legacy = parse_legacy(source)
  let tokens = lex(source)
  let result = legacy
  for unit in result.modules {
    let module_start = find_module_token(tokens, unit.name, 0)
    match module_start {
      Some(start) => {
        let end = find_token(tokens, start + 2, "endmodule").unwrap_or(
          tokens.length(),
        )
        let enriched = enrich_module(tokens, unit, start, end)
        replace_module(result, enriched)
      }
      None => ()
    }
  }
  result
}

///|
fn find_module_token(tokens : Array[Token], name : String, start : Int) -> Int? {
  for i in start..<(tokens.length() - 1) {
    if token_text(tokens, i) == "module" && token_text(tokens, i + 1) == name {
      return Some(i)
    }
  }
  None
}

///|
fn replace_module(design : Design, replacement : Module) -> Unit {
  for i, unit in design.modules {
    if unit.name == replacement.name {
      design.modules[i] = replacement
      return
    }
  }
}

///|
/// Parse while preserving recoverable syntax diagnostics for editor clients.
pub fn parse_with_diagnostics(source : String) -> ParseResult {
  let design = parse(source)
  let tokens = lex(source)
  let diagnostics : Array[ParseDiagnostic] = []
  let mut module_count = 0
  let mut endmodule_count = 0
  for token in tokens {
    if token.text == "module" {
      module_count += 1
    }
    if token.text == "endmodule" {
      endmodule_count += 1
    }
  }
  if endmodule_count < module_count {
    diagnostics.push({
      code: "PARSE001",
      message: "module is missing endmodule",
      line: if tokens.length() == 0 {
        1
      } else {
        tokens[tokens.length() - 1].line
      },
      column: if tokens.length() == 0 {
        1
      } else {
        tokens[tokens.length() - 1].column
      },
      severity: Error,
    })
  }
  { design, diagnostics }
}
