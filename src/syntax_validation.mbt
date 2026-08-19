///|
/// A recoverable syntax issue found before semantic rules run.
pub struct SyntaxIssue {
  code : String
  message : String
  line : Int
  column : Int
  token : String
}

///|
/// Delimiter and top-level structure validation report.
pub struct SyntaxReport {
  issues : Array[SyntaxIssue]
  module_count : Int
  endmodule_count : Int
  balanced : Bool
}

///|
fn matching_delimiter(opening : String) -> String {
  if opening == "(" {
    ")"
  } else if opening == "[" {
    "]"
  } else {
    "}"
  }
}

///|
/// Validate delimiters, module boundaries, and top-level terminators.
pub fn validate_syntax(source : String) -> SyntaxReport {
  let tokens = lex(source)
  let issues : Array[SyntaxIssue] = []
  let stack : Array[Token] = []
  let mut module_count = 0
  let mut endmodule_count = 0
  for token in tokens {
    if token.text == "module" {
      module_count += 1
    }
    if token.text == "endmodule" {
      endmodule_count += 1
    }
    if token.text == "(" || token.text == "[" || token.text == "{" {
      stack.push(token)
    } else if token.text == ")" || token.text == "]" || token.text == "}" {
      match stack.pop() {
        Some(opening) if matching_delimiter(opening.text) == token.text => ()
        Some(opening) =>
          issues.push({
            code: "SYN001",
            message: "closing delimiter does not match " + opening.text,
            line: token.line,
            column: token.column,
            token: token.text,
          })
        None =>
          issues.push({
            code: "SYN002",
            message: "closing delimiter has no opening delimiter",
            line: token.line,
            column: token.column,
            token: token.text,
          })
      }
    }
  }
  for opening in stack {
    issues.push({
      code: "SYN003",
      message: "opening delimiter is not closed: " + opening.text,
      line: opening.line,
      column: opening.column,
      token: opening.text,
    })
  }
  if endmodule_count < module_count {
    issues.push({
      code: "SYN004",
      message: "module declaration is missing endmodule",
      line: 1,
      column: 1,
      token: "module",
    })
  } else if endmodule_count > module_count {
    issues.push({
      code: "SYN005",
      message: "endmodule appears without a module declaration",
      line: 1,
      column: 1,
      token: "endmodule",
    })
  }
  {
    issues,
    module_count,
    endmodule_count,
    balanced: stack.length() == 0 && module_count == endmodule_count,
  }
}

///|
/// Check names and declaration spans in a parsed design.
pub fn validate_design(design : Design) -> Array[SyntaxIssue] {
  let issues : Array[SyntaxIssue] = []
  if design.modules.length() == 0 {
    issues.push({
      code: "SYN010",
      message: "source does not contain a module",
      line: 1,
      column: 1,
      token: "",
    })
  }
  for unit in design.modules {
    if unit.name == "" {
      issues.push({
        code: "SYN011",
        message: "module name is empty",
        line: unit.span.start.line,
        column: unit.span.start.column,
        token: "module",
      })
    }
    for port in unit.ports {
      if port.name == "" {
        issues.push({
          code: "SYN012",
          message: "port name is empty",
          line: port.span.start.line,
          column: port.span.start.column,
          token: "",
        })
      }
    }
    for signal in unit.signals {
      if signal.name == "" {
        issues.push({
          code: "SYN013",
          message: "signal name is empty",
          line: signal.span.start.line,
          column: signal.span.start.column,
          token: "",
        })
      }
    }
  }
  issues
}

///|
/// Render syntax issues as a stable text list.
pub fn SyntaxReport::to_text(self : SyntaxReport) -> String {
  let mut out = "modules=" +
    self.module_count.to_string() +
    " endmodules=" +
    self.endmodule_count.to_string() +
    " balanced=" +
    self.balanced.to_string() +
    "\n"
  for issue in self.issues {
    out += issue.line.to_string() +
      ":" +
      issue.column.to_string() +
      " [" +
      issue.code +
      "] " +
      issue.message +
      "\n"
  }
  out
}

///|
/// Render syntax issues as JSON lines.
pub fn SyntaxReport::to_json(self : SyntaxReport) -> String {
  let issues = self.issues
    .map(fn(issue) {
      "{\"code\":\"" +
      issue.code +
      "\",\"message\":\"" +
      issue.message +
      "\",\"line\":" +
      issue.line.to_string() +
      ",\"column\":" +
      issue.column.to_string() +
      ",\"token\":\"" +
      issue.token +
      "\"}"
    })
    .join(",")
  "{\"modules\":" +
  self.module_count.to_string() +
  ",\"endmodules\":" +
  self.endmodule_count.to_string() +
  ",\"balanced\":" +
  self.balanced.to_string() +
  ",\"issues\":[" +
  issues +
  "]}"
}

///|
/// Turn syntax issues into common diagnostics for one pipeline.
pub fn syntax_diagnostics(source : String) -> Array[Diagnostic] {
  let report = validate_syntax(source)
  let result : Array[Diagnostic] = []
  for issue in report.issues {
    result.push({
      code: issue.code,
      severity: Error,
      message: issue.message,
      line: issue.line,
      column: issue.column,
      signal: None,
      end_line: issue.line,
      end_column: issue.column,
      module_name: None,
      related: [],
    })
  }
  result
}

///|
/// Return whether a source is safe to pass into semantic analysis.
pub fn syntax_is_safe(source : String) -> Bool {
  validate_syntax(source).balanced
}

///|
/// Return a compact delimiter fingerprint for a source regression test.
pub fn delimiter_fingerprint(source : String) -> String {
  let report = validate_syntax(source)
  report.module_count.to_string() +
  "/" +
  report.endmodule_count.to_string() +
  "/" +
  report.issues.length().to_string()
}

///|
/// Emit diagnostics for syntax defects that are not already covered by parse.
fn check_syntax_rules(
  source : String,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for item in syntax_diagnostics(source) {
    add_diagnostic(config, result, item)
  }
}
