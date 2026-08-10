///|
fn token_text(tokens : Array[Token], i : Int) -> String {
  if i >= 0 && i < tokens.length() {
    tokens[i].text
  } else {
    ""
  }
}

///|
fn token_line(tokens : Array[Token], i : Int) -> Int {
  if i >= 0 && i < tokens.length() {
    tokens[i].line
  } else {
    1
  }
}

///|
fn find_token(tokens : Array[Token], start : Int, wanted : String) -> Int? {
  for i in start..<tokens.length() {
    if tokens[i].text == wanted {
      return Some(i)
    }
  }
  None
}

///|
fn parse_decimal(text : String) -> Int {
  let digits = text.to_array()
  let mut result = 0
  for c in digits {
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    }
  }
  result
}

///|
fn tokens_to_text(tokens : Array[Token], start : Int, end : Int) -> String {
  let mut out = ""
  let mut first = true
  for i in start..<end {
    if !first {
      out += " "
    }
    out += tokens[i].text
    first = false
  }
  out
}

///|
fn parse_width(tokens : Array[Token], start : Int) -> (Width, Int)? {
  if token_text(tokens, start) != "[" {
    return None
  }
  Some(
    (
      {
        msb: parse_decimal(token_text(tokens, start + 1)),
        lsb: parse_decimal(token_text(tokens, start + 3)),
      },
      start + 5,
    ),
  )
}

///|
fn make_signal(
  tokens : Array[Token],
  kind : SignalKind,
  direction : PortDirection?,
  i : Int,
  name : String,
  width : Width?,
) -> Signal {
  {
    name,
    kind,
    direction,
    width,
    span: Span::single(token_line(tokens, i), tokens[i].column),
  }
}

///|
fn split_names(
  tokens : Array[Token],
  start : Int,
  end : Int,
  kind : SignalKind,
  direction : PortDirection?,
) -> Array[Signal] {
  let result : Array[Signal] = []
  let mut i = start
  let mut width : Width? = None
  let mut active_direction = direction
  if token_text(tokens, i) == "[" {
    match parse_width(tokens, i) {
      Some((w, next)) => {
        width = Some(w)
        i = next
      }
      None => ()
    }
  }
  while i < end {
    let text = token_text(tokens, i)
    if text == "input" {
      active_direction = Some(Input)
    } else if text == "output" {
      active_direction = Some(Output)
    } else if text == "inout" {
      active_direction = Some(Inout)
    } else if text != "," && text != ";" && text != "(" && text != ")" {
      result.push(make_signal(tokens, kind, active_direction, i, text, width))
    }
    i += 1
  }
  result
}

///|
/// Parse the supported module, port, wire, reg, assign and always forms.
pub fn parse(source : String) -> Design {
  let tokens = lex(source)
  let design = Design::empty()
  let mut i = 0
  while i < tokens.length() {
    if token_text(tokens, i) == "module" {
      let name = token_text(tokens, i + 1)
      let parsed_module = {
        name,
        ports: [],
        signals: [],
        assignments: [],
        always_blocks: [],
        span: Span::single(token_line(tokens, i), tokens[i].column),
      }
      let end = find_token(tokens, i + 2, "endmodule").unwrap_or(
        tokens.length(),
      )
      let mut j = i + 2
      while j < end {
        let word = token_text(tokens, j)
        if word == "input" || word == "output" || word == "inout" {
          let direction = if word == "input" {
            Input
          } else if word == "output" {
            Output
          } else {
            Inout
          }
          let statement_end = find_token(tokens, j, ";").unwrap_or(end)
          let xs = split_names(
            tokens,
            j + 1,
            statement_end,
            Port,
            Some(direction),
          )
          for x in xs {
            parsed_module.ports.push(x)
          }
          j = statement_end + 1
        } else if word == "wire" || word == "reg" {
          let kind = if word == "wire" { Wire } else { Reg }
          let statement_end = find_token(tokens, j, ";").unwrap_or(end)
          let xs = split_names(tokens, j + 1, statement_end, kind, None)
          for x in xs {
            parsed_module.signals.push(x)
          }
          j = statement_end + 1
        } else if word == "assign" {
          let statement_end = find_token(tokens, j, ";").unwrap_or(end)
          let eq = find_token(tokens, j, "=").unwrap_or(j + 1)
          let lhs = token_text(tokens, eq - 1)
          let rhs = tokens_to_text(tokens, eq + 1, statement_end)
          parsed_module.assignments.push({
            lhs,
            rhs,
            span: Span::single(token_line(tokens, j), tokens[j].column),
          })
          j = statement_end + 1
        } else if word == "always" {
          let statement_end = find_token(tokens, j, "end").unwrap_or(end)
          let at = find_token(tokens, j, "@").unwrap_or(j)
          let sensitivity : Array[Sensitivity] = []
          if at < statement_end {
            for k in (at + 1)..<statement_end {
              let t = token_text(tokens, k)
              if t != "(" &&
                t != ")" &&
                t != "*" &&
                t != "or" &&
                t != "begin" &&
                t != "end" &&
                t != "posedge" &&
                t != "negedge" {
                sensitivity.push({ signal: t, edge: None })
              }
            }
          }
          parsed_module.always_blocks.push({
            sensitivity,
            body: tokens_to_text(tokens, j, statement_end),
            span: Span::single(token_line(tokens, j), tokens[j].column),
          })
          j = statement_end + 1
        } else {
          j += 1
        }
      }
      design.modules.push(parsed_module)
      i = end + 1
    } else {
      i += 1
    }
  }
  design
}
