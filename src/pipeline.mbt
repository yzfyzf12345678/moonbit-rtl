///|
/// A deterministic stage in the reusable lint pipeline.
pub enum PipelineStage {
  NormalizeSource
  ParseDesign
  ValidateSyntax
  CheckSemantics
  BuildReports
} derive(Eq)

///|
/// Options shared by the CLI, editor adapters, and CI integrations.
pub struct PipelineOptions {
  config : CheckConfig
  include_parse_diagnostics : Bool
  compute_metrics : Bool
  compute_graph : Bool
  enable_suppressions : Bool
  warnings_as_errors : Bool
  file_name : String
}

///|
/// A deterministic phase event; no clock is required for tracing or testing.
pub struct PipelineEvent {
  stage : PipelineStage
  input_size : Int
  output_size : Int
  note : String
}

///|
/// Complete output of one source analysis.
pub struct PipelineResult {
  source_hash : String
  source_lines : Int
  design : Design
  diagnostics : Array[Diagnostic]
  summary : CheckSummary
  metrics : DesignMetrics?
  graph : DesignGraph?
  suppressions : Array[Suppression]
  events : Array[PipelineEvent]
}

///|
/// A suppression resolved to its target source line.
pub struct Suppression {
  target_line : Int
  code : String
  reason : String
}

///|
/// One source file in a workspace check.
pub struct SourceUnit {
  path : String
  source : String
}

///|
/// Construct a source unit for workspace analysis.
pub fn SourceUnit::new(path : String, source : String) -> SourceUnit {
  { path, source }
}

///|
/// A finding tied to its source path.
pub struct WorkspaceFinding {
  path : String
  diagnostic : Diagnostic
}

///|
/// Aggregated result of a multi-file analysis.
pub struct WorkspaceResult {
  files : Int
  findings : Array[WorkspaceFinding]
  summaries : Array[SourceSummary]
  errors : Int
  warnings : Int
}

///|
/// Compact source metrics suitable for CI dashboards.
pub struct SourceSummary {
  path : String
  hash : String
  lines : Int
  modules : Int
  tokens : Int
  diagnostics : Int
  errors : Int
  warnings : Int
  suppressed : Int
}

///|
/// A baseline entry identifies a finding without depending on its prose.
pub struct BaselineEntry {
  code : String
  line : Int
  column : Int
  signal : String?
}

///|
/// A review baseline used to distinguish new findings from known debt.
pub struct DiagnosticBaseline {
  entries : Array[BaselineEntry]
  version : Int
}

///|
/// A change between a baseline and the current result.
pub enum BaselineChange {
  NewFinding(Diagnostic)
  ResolvedFinding(BaselineEntry)
}

///|
/// A safe, offset-based source edit.
pub struct SourceEdit {
  start_offset : Int
  end_offset : Int
  replacement : String
  description : String
}

///|
/// Construct an offset-based edit for editor integrations.
pub fn SourceEdit::new(
  start_offset : Int,
  end_offset : Int,
  replacement : String,
  description : String,
) -> SourceEdit {
  { start_offset, end_offset, replacement, description }
}

///|
/// A validated set of non-overlapping edits.
pub struct EditSet {
  edits : Array[SourceEdit]
  source_hash : String
}

///|
/// Default options are appropriate for local checks and CI.
pub fn PipelineOptions::default() -> PipelineOptions {
  {
    config: CheckConfig::default(),
    include_parse_diagnostics: true,
    compute_metrics: true,
    compute_graph: true,
    enable_suppressions: true,
    warnings_as_errors: false,
    file_name: "source.v",
  }
}

///|
/// Configure the displayed file name.
pub fn PipelineOptions::with_file_name(
  self : PipelineOptions,
  file_name : String,
) -> PipelineOptions {
  { ..self, file_name, }
}

///|
/// Replace checker configuration while retaining pipeline behavior.
pub fn PipelineOptions::with_config(
  self : PipelineOptions,
  config : CheckConfig,
) -> PipelineOptions {
  { ..self, config, }
}

///|
/// Configure warning escalation.
pub fn PipelineOptions::with_warnings_as_errors(
  self : PipelineOptions,
  enabled : Bool,
) -> PipelineOptions {
  { ..self, warnings_as_errors: enabled }
}

///|
/// Configure source suppressions.
pub fn PipelineOptions::with_suppressions(
  self : PipelineOptions,
  enabled : Bool,
) -> PipelineOptions {
  { ..self, enable_suppressions: enabled }
}

///|
/// Configure optional design reports.
pub fn PipelineOptions::with_reports(
  self : PipelineOptions,
  metrics : Bool,
  graph : Bool,
) -> PipelineOptions {
  { ..self, compute_metrics: metrics, compute_graph: graph }
}

///|
/// Return a stable stage label for logs.
pub fn PipelineStage::to_text(self : PipelineStage) -> String {
  match self {
    NormalizeSource => "normalize"
    ParseDesign => "parse"
    ValidateSyntax => "syntax"
    CheckSemantics => "semantic"
    BuildReports => "report"
  }
}

///|
/// Parse comma-separated rule IDs from a suppression marker.
fn suppression_codes(text : String) -> Array[String] {
  let result : Array[String] = []
  for part in text.split(",") {
    let code = part.trim().to_owned()
    if code != "" {
      result.push(code)
    }
  }
  result
}

///|
/// Read rtl-disable-line and rtl-disable-next-line comments.
pub fn parse_suppressions(source : String) -> Array[Suppression] {
  let result : Array[Suppression] = []
  for line_number, raw_line in source.split("\n") {
    let line = raw_line.to_owned()
    let (marker, target_line) = if line.contains("rtl-disable-next-line") {
      (Some("rtl-disable-next-line"), line_number + 2)
    } else if line.contains("rtl-disable-line") {
      (Some("rtl-disable-line"), line_number + 1)
    } else {
      (None, line_number + 1)
    }
    match marker {
      None => ()
      Some(value) =>
        match line.split_once(value) {
          None => ()
          Some(pair) => {
            let payload = pair.1.to_owned().trim()
            let code_text = payload
              .split_once("|")
              .map(fn(item) { item.0.to_owned() })
              .unwrap_or(payload.to_owned())
            let reason = payload
              .split_once("|")
              .map(fn(item) { item.1.trim().to_owned() })
              .unwrap_or("")
            for code in suppression_codes(code_text) {
              result.push({ target_line, code, reason })
            }
          }
        }
    }
  }
  result
}

///|
/// Test whether one diagnostic is covered by a suppression.
pub fn is_suppressed(
  item : Diagnostic,
  suppressions : Array[Suppression],
) -> Bool {
  for suppression in suppressions {
    if suppression.target_line == item.line &&
      (suppression.code == "all" || suppression.code == item.code) {
      return true
    }
  }
  false
}

///|
/// Remove suppressed findings without mutating the input array.
pub fn apply_suppressions(
  items : Array[Diagnostic],
  suppressions : Array[Suppression],
) -> Array[Diagnostic] {
  items.filter(fn(item) { !is_suppressed(item, suppressions) })
}

///|
/// Count findings hidden by a suppression set.
pub fn suppressed_count(
  items : Array[Diagnostic],
  suppressions : Array[Suppression],
) -> Int {
  let mut count = 0
  for item in items {
    if is_suppressed(item, suppressions) {
      count += 1
    }
  }
  count
}

///|
/// Normalize line endings and trim trailing spaces for stable cache keys.
pub fn normalize_source(source : String) -> String {
  source
  .split("\n")
  .map(fn(line) { line.to_owned().trim_end() })
  .collect()
  .join("\n")
}

///|
/// Compute a dependency-free FNV-1a style source fingerprint.
pub fn source_hash(source : String) -> String {
  let mut hash = 17
  for c in normalize_source(source).to_array() {
    hash = (hash * 33 + c.to_int()) % 1000000007
  }
  "fnv1a-" + hash.to_string()
}

///|
/// Count source lines, including a final empty line only when it is explicit.
pub fn source_line_count(source : String) -> Int {
  if source == "" {
    0
  } else {
    source.split("\n").count()
  }
}

///|
/// Merge parser and semantic findings in their production order.
fn collect_pipeline_diagnostics(
  source : String,
  design : Design,
  options : PipelineOptions,
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  if options.include_parse_diagnostics {
    for item in parse_diagnostics(source) {
      result.push(item)
    }
  }
  for item in check_with_config(design, options.config) {
    result.push(item)
  }
  result
}

///|
/// Escalate warnings after suppression has been applied.
fn escalate_warnings(
  items : Array[Diagnostic],
  enabled : Bool,
) -> Array[Diagnostic] {
  if !enabled {
    return items
  }
  items.map(fn(item) {
    if item.severity == Warning {
      { ..item, severity: Error }
    } else {
      item
    }
  })
}

///|
/// Record a deterministic phase event.
fn event(
  events : Array[PipelineEvent],
  stage : PipelineStage,
  input_size : Int,
  output_size : Int,
  note : String,
) -> Unit {
  events.push({ stage, input_size, output_size, note })
}

///|
/// Run normalization, parsing, syntax checks, semantic checks, and reports.
pub fn run_pipeline(
  source : String,
  options : PipelineOptions,
) -> PipelineResult {
  let events : Array[PipelineEvent] = []
  let normalized = normalize_source(source)
  event(
    events,
    NormalizeSource,
    source.length(),
    normalized.length(),
    "line endings",
  )
  let design = parse(normalized)
  event(
    events,
    ParseDesign,
    normalized.length(),
    design.modules.length(),
    "modules",
  )
  let suppressions = if options.enable_suppressions {
    parse_suppressions(normalized)
  } else {
    []
  }
  let raw = collect_pipeline_diagnostics(normalized, design, options)
  event(
    events,
    ValidateSyntax,
    design.modules.length(),
    raw.length(),
    "diagnostics",
  )
  let filtered = apply_suppressions(raw, suppressions)
  let diagnostics = escalate_warnings(filtered, options.warnings_as_errors)
  event(
    events,
    CheckSemantics,
    raw.length(),
    diagnostics.length(),
    "suppressed",
  )
  let metrics = if options.compute_metrics {
    Some(design_metrics(normalized))
  } else {
    None
  }
  let graph = if options.compute_graph {
    Some(design.dependency_graph())
  } else {
    None
  }
  event(
    events,
    BuildReports,
    diagnostics.length(),
    design.modules.length(),
    "reports",
  )
  {
    source_hash: source_hash(normalized),
    source_lines: source_line_count(normalized),
    design,
    diagnostics,
    summary: CheckSummary::from(design, diagnostics),
    metrics,
    graph,
    suppressions,
    events,
  }
}

///|
/// Run the default pipeline.
pub fn run_default_pipeline(source : String) -> PipelineResult {
  run_pipeline(source, PipelineOptions::default())
}

///|
/// Return a one-line shell status.
pub fn PipelineResult::status_line(self : PipelineResult) -> String {
  "hash=" +
  self.source_hash +
  " lines=" +
  self.source_lines.to_string() +
  " modules=" +
  self.summary.modules.to_string() +
  " diagnostics=" +
  self.diagnostics.length().to_string() +
  " errors=" +
  self.summary.errors.to_string() +
  " warnings=" +
  self.summary.warnings.to_string()
}

///|
/// Return the process exit code under a warning policy.
pub fn PipelineResult::exit_code(
  self : PipelineResult,
  warnings_as_errors : Bool,
) -> Int {
  if self.summary.errors > 0 ||
    (warnings_as_errors && self.summary.warnings > 0) {
    1
  } else {
    0
  }
}

///|
/// Return whether the result is clean under a warning policy.
pub fn PipelineResult::is_success(
  self : PipelineResult,
  warnings_as_errors : Bool,
) -> Bool {
  self.exit_code(warnings_as_errors) == 0
}

///|
/// Serialize a complete result for automation.
pub fn PipelineResult::to_json(self : PipelineResult) -> String {
  let metrics = match self.metrics {
    Some(value) => value.to_json()
    None => "null"
  }
  let modules = self.design
    .module_names()
    .map(fn(name) { "\"" + name + "\"" })
    .join(",")
  "{\"source_hash\":\"" +
  self.source_hash +
  "\",\"source_lines\":" +
  self.source_lines.to_string() +
  ",\"summary\":" +
  self.summary.to_json() +
  ",\"metrics\":" +
  metrics +
  ",\"modules\":[" +
  modules +
  "],\"diagnostics\":" +
  diagnostics_json(self.diagnostics) +
  "}"
}

///|
/// Render a result using the package report adapters.
pub fn PipelineResult::render(
  self : PipelineResult,
  format : ReportFormat,
) -> String {
  match format {
    TextReport => diagnostics_text(self.diagnostics)
    JsonReport => self.to_json()
    SarifReport => diagnostics_sarif(self.diagnostics)
    MarkdownReport => diagnostics_markdown(self.diagnostics)
    SummaryReport => diagnostics_summary(self.diagnostics)
    GithubReport => diagnostics_github(self.diagnostics)
  }
}

///|
/// Return the expected phase labels.
pub fn pipeline_stage_names() -> Array[String] {
  [NormalizeSource, ParseDesign, ValidateSyntax, CheckSemantics, BuildReports].map(fn(
      stage,
    ) {
      stage.to_text()
    },
  )
}

///|
/// Return a deterministic phase trace.
pub fn PipelineResult::event_trace(self : PipelineResult) -> String {
  self.events
  .map(fn(item) {
    item.stage.to_text() +
    ":" +
    item.input_size.to_string() +
    ">" +
    item.output_size.to_string() +
    ":" +
    item.note
  })
  .join("\n")
}

///|
/// Check that phase order and cardinalities are valid.
pub fn PipelineResult::is_well_formed(self : PipelineResult) -> Bool {
  let actual = self.events.map(fn(item) { item.stage.to_text() })
  if actual != pipeline_stage_names() {
    return false
  }
  for item in self.events {
    if item.input_size < 0 || item.output_size < 0 {
      return false
    }
  }
  true
}

///|
/// Produce a compact source summary.
pub fn PipelineResult::source_summary(
  self : PipelineResult,
  path : String,
) -> SourceSummary {
  let tokens = match self.metrics {
    Some(value) => value.token_count
    None => 0
  }
  {
    path,
    hash: self.source_hash,
    lines: self.source_lines,
    modules: self.summary.modules,
    tokens,
    diagnostics: self.diagnostics.length(),
    errors: self.summary.errors,
    warnings: self.summary.warnings,
    suppressed: self.suppressions.length(),
  }
}

///|
/// Analyze multiple files while retaining path ownership of every finding.
pub fn run_workspace(
  units : Array[SourceUnit],
  options : PipelineOptions,
) -> WorkspaceResult {
  let file_count = units.length()
  let findings : Array[WorkspaceFinding] = []
  let summaries : Array[SourceSummary] = []
  let mut errors = 0
  let mut warnings = 0
  for unit in units {
    let result = run_pipeline(unit.source, options)
    for item in result.diagnostics {
      if item.severity == Error {
        errors += 1
      } else if item.severity == Warning {
        warnings += 1
      }
      findings.push({ path: unit.path, diagnostic: item })
    }
    summaries.push(result.source_summary(unit.path))
  }
  { files: file_count, findings, summaries, errors, warnings }
}

///|
/// Sort findings for stable editor and CI output.
pub fn WorkspaceResult::sorted_findings(
  self : WorkspaceResult,
) -> Array[WorkspaceFinding] {
  let result = self.findings.copy()
  result.sort_by(fn(left, right) {
    if left.path < right.path {
      -1
    } else if left.path > right.path {
      1
    } else if left.diagnostic.line < right.diagnostic.line {
      -1
    } else if left.diagnostic.line > right.diagnostic.line {
      1
    } else {
      left.diagnostic.column.compare(right.diagnostic.column)
    }
  })
  result
}

///|
/// Render a workspace result as a Markdown table.
pub fn WorkspaceResult::to_markdown(self : WorkspaceResult) -> String {
  let mut out = "| File | Location | Rule | Severity | Message |\n| --- | --- | --- | --- | --- |\n"
  for finding in self.sorted_findings() {
    out += "| " +
      finding.path +
      " | " +
      finding.diagnostic.line.to_string() +
      ":" +
      finding.diagnostic.column.to_string() +
      " | " +
      finding.diagnostic.code +
      " | " +
      severity_text(finding.diagnostic.severity) +
      " | " +
      finding.diagnostic.message +
      " |\n"
  }
  out
}

///|
/// Return a compact workspace status.
pub fn WorkspaceResult::status_line(self : WorkspaceResult) -> String {
  "files=" +
  self.files.to_string() +
  " findings=" +
  self.findings.length().to_string() +
  " errors=" +
  self.errors.to_string() +
  " warnings=" +
  self.warnings.to_string()
}

///|
/// Return the workspace process status.
pub fn WorkspaceResult::exit_code(self : WorkspaceResult) -> Int {
  if self.errors > 0 {
    1
  } else {
    0
  }
}

///|
/// Parse a simple baseline format: version|1 and rule|line|column|signal.
pub fn parse_baseline(text : String) -> DiagnosticBaseline {
  let entries : Array[BaselineEntry] = []
  let mut version = 1
  for raw_line in text.split("\n") {
    let line = raw_line.to_owned().trim()
    if line == "" || line.has_prefix("#") {
      continue
    }
    let fields : Array[String] = line
      .split("|")
      .map(fn(item) { item.to_owned() })
      .collect()
    if fields.length() >= 2 && fields[0] == "version" {
      version = parse_integer(fields[1])
    } else if fields.length() >= 4 {
      let signal = if fields.length() > 4 && fields[4] != "" {
        Some(fields[4])
      } else {
        None
      }
      entries.push({
        code: fields[0],
        line: parse_integer(fields[1]),
        column: parse_integer(fields[2]),
        signal,
      })
    }
  }
  { entries, version }
}

///|
/// Serialize a baseline in a review-friendly stable order.
pub fn DiagnosticBaseline::to_text(self : DiagnosticBaseline) -> String {
  let mut out = "# moonbit-rtl baseline\nversion|" +
    self.version.to_string() +
    "\n"
  for entry in self.entries {
    out += entry.code +
      "|" +
      entry.line.to_string() +
      "|" +
      entry.column.to_string() +
      "|" +
      entry.signal.unwrap_or("") +
      "\n"
  }
  out
}

///|
/// Match a current diagnostic against one baseline entry.
pub fn BaselineEntry::matches(self : BaselineEntry, item : Diagnostic) -> Bool {
  self.code == item.code &&
  self.line == item.line &&
  self.column == item.column &&
  (match (self.signal, item.signal) {
    (None, _) => true
    (Some(left), Some(right)) => left == right
    _ => false
  })
}

///|
/// Compare current diagnostics with a baseline.
pub fn compare_baseline(
  baseline : DiagnosticBaseline,
  current : Array[Diagnostic],
) -> Array[BaselineChange] {
  let result : Array[BaselineChange] = []
  for item in current {
    if !baseline.entries.any(fn(entry) { entry.matches(item) }) {
      result.push(NewFinding(item))
    }
  }
  for entry in baseline.entries {
    if !current.any(fn(item) { entry.matches(item) }) {
      result.push(ResolvedFinding(entry))
    }
  }
  result
}

///|
/// Build a baseline directly from current diagnostics.
pub fn baseline_from_diagnostics(
  items : Array[Diagnostic],
) -> DiagnosticBaseline {
  let entries : Array[BaselineEntry] = []
  for item in items {
    entries.push({
      code: item.code,
      line: item.line,
      column: item.column,
      signal: item.signal,
    })
  }
  { entries, version: 1 }
}

///|
/// Return newly introduced diagnostics.
pub fn new_baseline_findings(
  changes : Array[BaselineChange],
) -> Array[Diagnostic] {
  let result : Array[Diagnostic] = []
  for change in changes {
    match change {
      NewFinding(item) => result.push(item)
      ResolvedFinding(_) => ()
    }
  }
  result
}

///|
/// Return the number of resolved entries.
pub fn resolved_baseline_count(changes : Array[BaselineChange]) -> Int {
  let mut count = 0
  for change in changes {
    match change {
      NewFinding(_) => ()
      ResolvedFinding(_) => count += 1
    }
  }
  count
}

///|
/// Remove duplicate entries while retaining first-seen order.
pub fn DiagnosticBaseline::deduplicated(
  self : DiagnosticBaseline,
) -> DiagnosticBaseline {
  let entries : Array[BaselineEntry] = []
  for entry in self.entries {
    let duplicate = entries.any(fn(other) {
      other.code == entry.code &&
      other.line == entry.line &&
      other.column == entry.column &&
      other.signal == entry.signal
    })
    if !duplicate {
      entries.push(entry)
    }
  }
  { ..self, entries, }
}

///|
fn parse_integer(text : String) -> Int {
  let mut value = 0
  for c in text.to_array() {
    if c >= '0' && c <= '9' {
      value = value * 10 + c.to_int() - '0'.to_int()
    }
  }
  value
}

///|
/// Validate edits and reject negative, out-of-range, or overlapping spans.
pub fn EditSet::from_edits(
  source : String,
  edits : Array[SourceEdit],
) -> EditSet? {
  let ordered = edits.copy()
  ordered.sort_by(fn(left, right) {
    left.start_offset.compare(right.start_offset)
  })
  for index, edit in ordered {
    if edit.start_offset < 0 ||
      edit.end_offset < edit.start_offset ||
      edit.end_offset > source.length() {
      return None
    }
    if index > 0 && edit.start_offset < ordered[index - 1].end_offset {
      return None
    }
  }
  Some({ edits: ordered, source_hash: source_hash(source) })
}

///|
/// Apply validated edits from right to left.
pub fn EditSet::apply(self : EditSet, source : String) -> String? {
  if source_hash(source) != self.source_hash {
    return None
  }
  let mut result = source
  let mut index = self.edits.length()
  while index > 0 {
    index -= 1
    let edit = self.edits[index]
    let prefix = result.sub(end?=Some(edit.start_offset)).to_owned()
    let suffix = result.sub(start?=Some(edit.end_offset)).to_owned()
    result = prefix + edit.replacement + suffix
  }
  Some(result)
}

///|
/// Build safe edits for trailing whitespace.
pub fn trailing_whitespace_fixes(source : String) -> EditSet? {
  let edits : Array[SourceEdit] = []
  let mut offset = 0
  for raw_line in source.split("\n") {
    let line = raw_line.to_owned()
    let trimmed = line.trim_end()
    if trimmed.length() < line.length() {
      edits.push({
        start_offset: offset + trimmed.length(),
        end_offset: offset + line.length(),
        replacement: "",
        description: "remove trailing whitespace",
      })
    }
    offset += line.length() + 1
  }
  EditSet::from_edits(source, edits)
}

///|
/// Return a short contract for integrations and acceptance examples.
pub fn pipeline_contract() -> String {
  "moonbit-rtl/pipeline-v1\n" +
  "stages=normalize,parse,syntax,semantic,report\n" +
  "reports=text,json,sarif,markdown,summary,github\n" +
  "suppressions=rtl-disable-line,rtl-disable-next-line\n" +
  "baseline=version|rule|line|column|signal"
}

///|
/// Return a JSON summary for workspace automation.
pub fn WorkspaceResult::to_json(self : WorkspaceResult) -> String {
  let summaries = self.summaries
    .map(fn(item) {
      "{\"path\":\"" +
      item.path +
      "\",\"hash\":\"" +
      item.hash +
      "\",\"lines\":" +
      item.lines.to_string() +
      ",\"modules\":" +
      item.modules.to_string() +
      ",\"tokens\":" +
      item.tokens.to_string() +
      ",\"diagnostics\":" +
      item.diagnostics.to_string() +
      "}"
    })
    .join(",")
  "{\"files\":" +
  self.files.to_string() +
  ",\"errors\":" +
  self.errors.to_string() +
  ",\"warnings\":" +
  self.warnings.to_string() +
  ",\"summaries\":[" +
  summaries +
  "]}"
}

///|
/// Filter findings to one rule.
pub fn filter_diagnostics_by_code(
  items : Array[Diagnostic],
  code : String,
) -> Array[Diagnostic] {
  items.filter(fn(item) { item.code == code })
}

///|
/// Filter findings to an inclusive source-line range.
pub fn filter_diagnostics_by_lines(
  items : Array[Diagnostic],
  first_line : Int,
  last_line : Int,
) -> Array[Diagnostic] {
  items.filter(fn(item) { item.line >= first_line && item.line <= last_line })
}

///|
/// Return the most severe level present.
pub fn diagnostic_max_severity(items : Array[Diagnostic]) -> Severity? {
  let mut result : Severity? = None
  for item in items {
    match (result, item.severity) {
      (None, severity) => result = Some(severity)
      (Some(Error), _) => ()
      (Some(Warning), Error) => result = Some(Error)
      (Some(Warning), _) => ()
      (Some(Info), severity) => result = Some(severity)
    }
  }
  result
}

///|
/// Return a compact baseline change log.
pub fn baseline_changes_text(changes : Array[BaselineChange]) -> String {
  let mut out = ""
  for change in changes {
    match change {
      NewFinding(item) =>
        out += "new " + item.code + "@" + item.line.to_string() + "\n"
      ResolvedFinding(item) =>
        out += "resolved " + item.code + "@" + item.line.to_string() + "\n"
    }
  }
  out
}

///|
/// Build a module outline without running semantic rules.
pub fn parse_outline(source : String) -> Array[String] {
  parse(source).modules.map(fn(unit) {
    unit.name + "(" + unit.port_signature() + ")"
  })
}

///|
/// Extract a bounded source context for a diagnostic.
pub fn diagnostic_context(
  source : String,
  item : Diagnostic,
  radius : Int,
) -> String {
  let lines : Array[String] = source
    .split("\n")
    .map(fn(value) { value.to_owned() })
    .collect()
  let first = if item.line - radius < 1 { 1 } else { item.line - radius }
  let last = if item.line + radius > lines.length() {
    lines.length()
  } else {
    item.line + radius
  }
  let end_line = last + 1
  let mut out = ""
  for line_number in first..<=end_line {
    if line_number >= 1 && line_number <= lines.length() {
      out += line_number.to_string() + ": " + lines[line_number - 1] + "\n"
    }
  }
  out
}

///|
/// Return a stable acceptance summary for a single result.
pub fn acceptance_summary(result : PipelineResult) -> String {
  let edge_count = match result.graph {
    Some(value) => value.edges.length()
    None => 0
  }
  "hash=" +
  result.source_hash +
  " lines=" +
  result.source_lines.to_string() +
  " modules=" +
  result.summary.modules.to_string() +
  " signals=" +
  result.summary.signals.to_string() +
  " assignments=" +
  result.summary.assignments.to_string() +
  " edges=" +
  edge_count.to_string() +
  " errors=" +
  result.summary.errors.to_string() +
  " warnings=" +
  result.summary.warnings.to_string()
}
