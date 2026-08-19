///|
/// Output formats accepted by the command-line adapter.
pub enum ReportFormat {
  TextReport
  JsonReport
  SarifReport
  MarkdownReport
  SummaryReport
  GithubReport
}

///|
/// Parse the format names accepted by CI and command-line wrappers.
pub fn report_format_from_text(text : String) -> ReportFormat {
  if text == "json" {
    JsonReport
  } else if text == "sarif" {
    SarifReport
  } else if text == "markdown" {
    MarkdownReport
  } else if text == "summary" {
    SummaryReport
  } else if text == "github" {
    GithubReport
  } else {
    TextReport
  }
}

///|
/// A count of diagnostics for one rule.
pub struct RuleCount {
  code : String
  errors : Int
  warnings : Int
  infos : Int
}

///|
/// Aggregated diagnostic statistics.
pub struct DiagnosticStats {
  total : Int
  errors : Int
  warnings : Int
  infos : Int
  rules : Array[RuleCount]
}

///|
/// A report combining syntax, semantic, and design metrics.
pub struct AnalysisReport {
  source_name : String
  metrics : DesignMetrics
  diagnostics : Array[Diagnostic]
  stats : DiagnosticStats
}

///|
/// Line offsets used to extract source context without reparsing.
pub struct SourceIndex {
  offsets : Array[Int]
  source_length : Int
}

///|
/// Build a line index for a source string.
pub fn SourceIndex::from(source : String) -> SourceIndex {
  let offsets : Array[Int] = [0]
  for i, c in source.to_array() {
    if c == '\n' {
      offsets.push(i + 1)
    }
  }
  { offsets, source_length: source.length() }
}

///|
/// Return the zero-based offset for a one-based line number.
pub fn SourceIndex::line_offset(self : SourceIndex, line : Int) -> Int? {
  if line < 1 || line > self.offsets.length() {
    None
  } else {
    Some(self.offsets[line - 1])
  }
}

///|
/// Return the line containing a zero-based source offset.
pub fn SourceIndex::line_at(self : SourceIndex, offset : Int) -> Int {
  let mut result = 1
  for i, start in self.offsets {
    if start <= offset {
      result = i + 1
    } else {
      break
    }
  }
  result
}

///|
/// Extract one source line for a diagnostic preview.
pub fn source_line(source : String, line : Int) -> String {
  if line < 1 {
    return ""
  }
  let lines : Array[String] = source
    .split("\n")
    .map(fn(value) { value.to_owned() })
    .collect()
  if line > lines.length() {
    ""
  } else {
    lines[line - 1]
  }
}

///|
/// Render a diagnostic with its source line and a caret.
pub fn diagnostic_excerpt(source : String, item : Diagnostic) -> String {
  let line = source_line(source, item.line)
  let mut caret = ""
  let mut index = 1
  while index < item.column {
    caret += " "
    index += 1
  }
  caret += "^"
  item.line.to_string() + " | " + line + "\n" + "  | " + caret
}

///|
/// Build stable counts grouped by rule ID.
pub fn DiagnosticStats::from(items : Array[Diagnostic]) -> DiagnosticStats {
  let mut errors = 0
  let mut warnings = 0
  let mut infos = 0
  let rules : Array[RuleCount] = []
  for item in items {
    match item.severity {
      Error => errors += 1
      Warning => warnings += 1
      Info => infos += 1
    }
    let mut found = false
    for i, rule in rules {
      if rule.code == item.code {
        found = true
        match item.severity {
          Error => rules[i] = { ..rule, errors: rule.errors + 1 }
          Warning => rules[i] = { ..rule, warnings: rule.warnings + 1 }
          Info => rules[i] = { ..rule, infos: rule.infos + 1 }
        }
      }
    }
    if !found {
      rules.push({
        code: item.code,
        errors: if item.severity == Error {
          1
        } else {
          0
        },
        warnings: if item.severity == Warning {
          1
        } else {
          0
        },
        infos: if item.severity == Info {
          1
        } else {
          0
        },
      })
    }
  }
  { total: items.length(), errors, warnings, infos, rules }
}

///|
/// Serialize aggregated stats for CI summaries.
pub fn DiagnosticStats::to_json(self : DiagnosticStats) -> String {
  let rules = self.rules
    .map(fn(rule) {
      "{\"code\":\"" +
      rule.code +
      "\",\"errors\":" +
      rule.errors.to_string() +
      ",\"warnings\":" +
      rule.warnings.to_string() +
      ",\"infos\":" +
      rule.infos.to_string() +
      "}"
    })
    .join(",")
  "{\"total\":" +
  self.total.to_string() +
  ",\"errors\":" +
  self.errors.to_string() +
  ",\"warnings\":" +
  self.warnings.to_string() +
  ",\"infos\":" +
  self.infos.to_string() +
  ",\"rules\":[" +
  rules +
  "]}"
}

///|
/// Return only diagnostics matching an optional rule and module.
pub fn filter_diagnostics(
  items : Array[Diagnostic],
  code : String?,
  module_name : String?,
  severity : Severity?,
) -> Array[Diagnostic] {
  items.filter(fn(item) {
    let code_ok = match code {
      Some(value) => item.code == value
      None => true
    }
    let module_ok = match module_name {
      Some(value) => item.module_name == Some(value)
      None => true
    }
    let severity_ok = match severity {
      Some(value) => item.severity == value
      None => true
    }
    code_ok && module_ok && severity_ok
  })
}

///|
/// Sort diagnostics by source location while keeping source order for ties.
pub fn sort_diagnostics(items : Array[Diagnostic]) -> Array[Diagnostic] {
  let result = items.copy()
  result.sort_by(fn(left, right) {
    if left.line != right.line {
      left.line - right.line
    } else if left.column != right.column {
      left.column - right.column
    } else {
      left.code.compare(right.code)
    }
  })
  result
}

///|
/// Render one diagnostic per line for log collectors.
pub fn diagnostics_json_lines(items : Array[Diagnostic]) -> String {
  items.map(fn(item) { diagnostics_json([item]) }).join("\n")
}

///|
/// Render GitHub Actions workflow annotations.
pub fn diagnostics_github(items : Array[Diagnostic]) -> String {
  let mut out = ""
  for item in items {
    let command = match item.severity {
      Error => "error"
      Warning => "warning"
      Info => "notice"
    }
    let title = item.code + " " + severity_text(item.severity)
    out += "::" +
      command +
      " file=source.v,line=" +
      item.line.to_string() +
      ",col=" +
      item.column.to_string() +
      ",title=" +
      title +
      "::" +
      item.message +
      "\n"
  }
  out
}

///|
/// Render an arbitrary format through one stable public entry point.
pub fn render_report(
  items : Array[Diagnostic],
  format : ReportFormat,
) -> String {
  match format {
    TextReport => diagnostics_text(items)
    JsonReport => diagnostics_json(items)
    SarifReport => diagnostics_sarif(items)
    MarkdownReport => diagnostics_markdown(items)
    SummaryReport => diagnostics_summary(items)
    GithubReport => diagnostics_github(items)
  }
}

///|
/// Analyze a source document into one reusable report value.
pub fn analyze_source(
  source_name : String,
  source : String,
  config : CheckConfig,
) -> AnalysisReport {
  let syntax = parse_diagnostics(source)
  let semantic = check_source_with_config(source, config)
  let items : Array[Diagnostic] = []
  for item in syntax {
    items.push(item)
  }
  for item in semantic {
    items.push(item)
  }
  let ordered = sort_diagnostics(items)
  {
    source_name,
    metrics: design_metrics(source),
    diagnostics: ordered,
    stats: DiagnosticStats::from(ordered),
  }
}

///|
/// A stable human-readable report with metrics and diagnostics.
pub fn AnalysisReport::to_text(self : AnalysisReport) -> String {
  let mut out = "Source: " + self.source_name + "\n"
  out += "Modules: " +
    self.metrics.module_count.to_string() +
    ", ports: " +
    self.metrics.port_count.to_string() +
    ", signals: " +
    self.metrics.signal_count.to_string() +
    ", tokens: " +
    self.metrics.token_count.to_string() +
    "\n"
  out += "Diagnostics: " +
    self.stats.total.to_string() +
    " (errors=" +
    self.stats.errors.to_string() +
    ", warnings=" +
    self.stats.warnings.to_string() +
    ", infos=" +
    self.stats.infos.to_string() +
    ")\n"
  if self.diagnostics.length() > 0 {
    out += diagnostics_text(self.diagnostics)
  } else {
    out += "No diagnostics.\n"
  }
  out
}

///|
/// Serialize an analysis report for artifact upload.
pub fn AnalysisReport::to_json(self : AnalysisReport) -> String {
  "{\"source\":\"" +
  self.source_name +
  "\",\"metrics\":" +
  self.metrics.to_json() +
  ",\"stats\":" +
  self.stats.to_json() +
  ",\"diagnostics\":" +
  diagnostics_json(self.diagnostics) +
  "}"
}

///|
/// Return the first error, if any, for simple editor integrations.
pub fn first_error(items : Array[Diagnostic]) -> Diagnostic? {
  for item in items {
    if item.severity == Error {
      return Some(item)
    }
  }
  None
}

///|
/// Return the first warning, if any.
pub fn first_warning(items : Array[Diagnostic]) -> Diagnostic? {
  for item in items {
    if item.severity == Warning {
      return Some(item)
    }
  }
  None
}

///|
/// Deduplicate diagnostics by rule, position, and message.
pub fn deduplicate_diagnostics(items : Array[Diagnostic]) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  for item in items {
    let duplicate = result.any(fn(existing) {
      existing.code == item.code &&
      existing.line == item.line &&
      existing.column == item.column &&
      existing.message == item.message
    })
    if !duplicate {
      result.push(item)
    }
  }
  result
}

///|
/// Return a compact status label used in badges and release scripts.
pub fn status_label(items : Array[Diagnostic]) -> String {
  if first_error(items) is Some(_) {
    "fail"
  } else if first_warning(items) is Some(_) {
    "warn"
  } else {
    "pass"
  }
}

///|
/// Return an exit code that optionally treats warnings as failures.
pub fn diagnostics_exit_code_with_policy(
  items : Array[Diagnostic],
  deny_warnings : Bool,
) -> Int {
  for item in items {
    if item.severity == Error || (deny_warnings && item.severity == Warning) {
      return 1
    }
  }
  0
}
