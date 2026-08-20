///|
/// The release gate applied to an analyzable RTL source tree.
pub struct ReleaseGate {
  name : String
  threshold : Int
  actual : Int
  passed : Bool
  detail : String
}

///|
/// A named evidence artifact emitted by the release analysis.
pub struct ReleaseArtifact {
  name : String
  format : String
  status : String
  summary : String
  payload : String
}

///|
/// A single, deterministic acceptance report assembled from library analyses.
pub struct ReleaseReport {
  project : String
  source_hash : String
  source_lines : Int
  modules : Int
  gates : Array[ReleaseGate]
  artifacts : Array[ReleaseArtifact]
  diagnostics : Array[Diagnostic]
  netlist_issues : Int
  benchmark : BenchmarkResult
}

///|
pub fn ReleaseGate::is_passed(self : ReleaseGate) -> Bool {
  self.passed
}

///|
fn release_gate(
  name : String,
  threshold : Int,
  actual : Int,
  detail : String,
) -> ReleaseGate {
  { name, threshold, actual, passed: actual >= threshold, detail }
}

///|
fn release_artifact(
  name : String,
  format : String,
  status : String,
  summary : String,
  payload : String,
) -> ReleaseArtifact {
  { name, format, status, summary, payload }
}

///|
fn release_line_goal() -> Int {
  20000
}

///|
fn release_source_diagnostics(
  design : Design,
  source : String,
) -> Array[Diagnostic] {
  let result = check(design)
  let parsed = parse_with_diagnostics(source)
  for item in parsed.diagnostics {
    result.push(
      Diagnostic::new(
        item.code,
        item.severity,
        item.message,
        item.line,
        item.column,
      ),
    )
  }
  result
}

///|
fn release_error_count(items : Array[Diagnostic]) -> Int {
  items.fold(init=0, fn(total, item) {
    if item.severity == Severity::Error {
      total + 1
    } else {
      total
    }
  })
}

///|
fn release_warning_count(items : Array[Diagnostic]) -> Int {
  items.fold(init=0, fn(total, item) {
    if item.severity == Severity::Warning {
      total + 1
    } else {
      total
    }
  })
}

///|
fn release_signal_count(design : Design) -> Int {
  design.modules.fold(init=0, fn(total, unit) {
    total + unit.ports.length() + unit.signals.length()
  })
}

///|
fn release_instance_count(design : Design) -> Int {
  design.modules.fold(init=0, fn(total, unit) {
    total + unit.instances.length()
  })
}

///|
fn release_assignment_count(design : Design) -> Int {
  design.modules.fold(init=0, fn(total, unit) {
    let procedural = unit.always_blocks.fold(init=0, fn(count, block) {
      let items : Array[Assignment] = []
      advanced_statement_assignments(block.statements, items)
      count + items.length()
    })
    total + unit.assignments.length() + procedural
  })
}

///|
fn release_benchmark(source : String) -> BenchmarkResult {
  let fixture = {
    name: "release-input",
    source,
    module_count: parse(source).modules.length(),
    expected_tokens: lex(source).length(),
  }
  run_benchmark(fixture, 1)
}

///|
fn release_design_metrics_artifact(design : Design) -> ReleaseArtifact {
  let modules = design.modules.length()
  let signals = release_signal_count(design)
  let assignments = release_assignment_count(design)
  let instances = release_instance_count(design)
  let summary = "modules=" +
    modules.to_string() +
    "; signals=" +
    signals.to_string() +
    "; assignments=" +
    assignments.to_string() +
    "; instances=" +
    instances.to_string()
  release_artifact("design-metrics", "text", "available", summary, summary)
}

///|
fn release_coverage_artifact(
  design : Design,
  source : String,
) -> ReleaseArtifact {
  let report = coverage_structure(design, source_line_count(source))
  let observed : Array[String] = []
  for unit in design.modules {
    observed.push(unit.name)
    for signal in unit.ports {
      observed.push(signal.name)
    }
  }
  let marked = report.mark(observed)
  let summary = "line=" +
    marked.line_percent().to_string() +
    "%; branch=" +
    marked.branch_percent().to_string() +
    "%; toggle=" +
    marked.toggle_percent().to_string() +
    "%"
  release_artifact("coverage", "json", "available", summary, marked.to_json())
}

///|
fn release_timing_artifact(design : Design) -> ReleaseArtifact {
  let report = timing_analyze(design, TimingConfig::default())
  let status = if report.is_acyclic() { "available" } else { "review" }
  let summary = "critical_delay=" +
    report.critical_delay.to_string() +
    "; max_fanout=" +
    report.max_fanout.to_string() +
    "; cycles=" +
    report.cycles.length().to_string()
  release_artifact("timing", "json", status, summary, report.to_json())
}

///|
fn release_rule_artifact(design : Design) -> ReleaseArtifact {
  let config = RulePackConfig::default()
  let result = run_rule_pack(design, config)
  let status = if result.has_blocking_errors() { "review" } else { "available" }
  let summary = "errors=" +
    result.error_count().to_string() +
    "; warnings=" +
    result.warning_count().to_string()
  release_artifact("advanced-rules", "json", status, summary, result.to_json())
}

///|
fn release_netlist_artifact(design : Design) -> (ReleaseArtifact, Int) {
  let netlists = normalize_design(design)
  let issues : Array[NetlistIssue] = []
  let summaries : Array[String] = []
  for netlist in netlists {
    for item in check_netlist(netlist) {
      issues.push(item)
    }
    summaries.push(netlist_summary(netlist))
  }
  let payload = "[" + netlists.map(NormalizedNetlist::to_json).join(",") + "]"
  let status = if issues.any(fn(item) { item.severity == Severity::Error }) {
    "review"
  } else {
    "available"
  }
  (
    release_artifact(
      "netlist",
      "json",
      status,
      summaries.join("; ") + "; issues=" + issues.length().to_string(),
      payload,
    ),
    issues.length(),
  )
}

///|
fn release_ir_artifact(design : Design, source : String) -> ReleaseArtifact {
  let ir = lower_ir(design, source).constant_fold().remove_comments()
  let diagnostics = ir_diagnostics(ir)
  let status = if diagnostics.length() == 0 { "available" } else { "review" }
  release_artifact(
    "intermediate-ir",
    "json",
    status,
    "modules=" +
    ir.modules.length().to_string() +
    "; passes=" +
    ir.passes.join(",") +
    "; dead_signals=" +
    ir.ir_dead_signal_names().length().to_string(),
    ir.to_json(),
  )
}

///|
fn release_query_artifact(design : Design) -> ReleaseArtifact {
  let query = DesignQuery::empty().with_predicate(QueryPortCountAtLeast(1))
  let result = run_design_query(design, query)
  release_artifact(
    "query-index",
    "json",
    "available",
    "matches=" + result.count().to_string(),
    result.to_json(),
  )
}

///|
fn release_verification_artifact(design : Design) -> ReleaseArtifact {
  let reports : Array[String] = []
  let mut failed = 0
  for unit in design.modules {
    let plan = generate_verification_plan(unit, 8)
    let report = run_verification_plan(unit, plan)
    if !report.is_healthy() {
      failed += 1
    }
    reports.push(report.to_json())
  }
  release_artifact(
    "verification",
    "json",
    if failed == 0 {
      "available"
    } else {
      "review"
    },
    "modules_with_failures=" + failed.to_string(),
    "[" + reports.join(",") + "]",
  )
}

///|
/// Assemble all non-mutating analyses into one reproducible evidence object.
pub fn build_release_report(project : String, source : String) -> ReleaseReport {
  let design = parse(source)
  let diagnostics = release_source_diagnostics(design, source)
  let design_metrics = release_design_metrics_artifact(design)
  let rules = release_rule_artifact(design)
  let timing = release_timing_artifact(design)
  let coverage = release_coverage_artifact(design, source)
  let netlist_pair = release_netlist_artifact(design)
  let netlist = netlist_pair.0
  let ir = release_ir_artifact(design, source)
  let query = release_query_artifact(design)
  let verification = release_verification_artifact(design)
  let benchmark = release_benchmark(source)
  let source_lines = source_line_count(source)
  let modules = design.modules.length()
  let errors = release_error_count(diagnostics)
  let coverage_report = coverage_structure(design, source_lines)
  let gates = [
    release_gate(
      "source-lines",
      release_line_goal(),
      source_lines,
      "counted from the supplied source string",
    ),
    release_gate("modules", 1, modules, "at least one analyzable module"),
    release_gate(
      "diagnostic-errors",
      0,
      0 - errors,
      "no blocking parser or checker errors",
    ),
    release_gate(
      "timing-acyclic",
      1,
      if timing.status == "available" {
        1
      } else {
        0
      },
      "dependency graph has no cycle",
    ),
    release_gate(
      "coverage-points",
      1,
      coverage_report.total_points(),
      "structural points were generated",
    ),
    release_gate(
      "netlist-issues",
      0,
      0 - netlist_pair.1,
      "normalized netlist has no consistency errors",
    ),
    release_gate(
      "benchmark-tokens",
      1,
      benchmark.tokens,
      "lexer produced a repeatable token count",
    ),
  ]
  {
    project,
    source_hash: source_hash(source),
    source_lines,
    modules,
    gates,
    artifacts: [
      design_metrics, rules, timing, coverage, netlist, ir, query, verification,
    ],
    diagnostics,
    netlist_issues: netlist_pair.1,
    benchmark,
  }
}

///|
pub fn release_report_source(
  project : String,
  source : String,
) -> ReleaseReport {
  build_release_report(project, source)
}

///|
pub fn ReleaseReport::passed_gates(self : ReleaseReport) -> Int {
  self.gates.fold(init=0, fn(total, gate) {
    if gate.passed {
      total + 1
    } else {
      total
    }
  })
}

///|
pub fn ReleaseReport::failed_gates(self : ReleaseReport) -> Int {
  self.gates.length() - self.passed_gates()
}

///|
pub fn ReleaseReport::is_ready(self : ReleaseReport) -> Bool {
  self.failed_gates() == 0
}

///|
pub fn ReleaseReport::error_count(self : ReleaseReport) -> Int {
  release_error_count(self.diagnostics)
}

///|
pub fn ReleaseReport::warning_count(self : ReleaseReport) -> Int {
  release_warning_count(self.diagnostics)
}

///|
fn release_gate_json(gate : ReleaseGate) -> String {
  "{\"name\":\"" +
  json_escape(gate.name) +
  "\",\"threshold\":" +
  gate.threshold.to_string() +
  ",\"actual\":" +
  gate.actual.to_string() +
  ",\"passed\":" +
  (if gate.passed { "true" } else { "false" }) +
  ",\"detail\":\"" +
  json_escape(gate.detail) +
  "\"}"
}

///|
fn release_artifact_json(artifact : ReleaseArtifact) -> String {
  "{\"name\":\"" +
  json_escape(artifact.name) +
  "\",\"format\":\"" +
  artifact.format +
  "\",\"status\":\"" +
  artifact.status +
  "\",\"summary\":\"" +
  json_escape(artifact.summary) +
  "\",\"payload\":" +
  artifact.payload +
  "}"
}

///|
pub fn ReleaseReport::to_json(self : ReleaseReport) -> String {
  "{\"project\":\"" +
  json_escape(self.project) +
  "\",\"source_hash\":\"" +
  self.source_hash +
  "\",\"source_lines\":" +
  self.source_lines.to_string() +
  ",\"modules\":" +
  self.modules.to_string() +
  ",\"ready\":" +
  (if self.is_ready() { "true" } else { "false" }) +
  ",\"passed_gates\":" +
  self.passed_gates().to_string() +
  ",\"failed_gates\":" +
  self.failed_gates().to_string() +
  ",\"gates\":[" +
  self.gates.map(release_gate_json).join(",") +
  "]" +
  ",\"artifacts\":[" +
  self.artifacts.map(release_artifact_json).join(",") +
  "]" +
  ",\"diagnostics\":" +
  diagnostics_json(self.diagnostics) +
  ",\"benchmark\":" +
  benchmark_json([self.benchmark]) +
  "}"
}

///|
pub fn ReleaseReport::to_markdown(self : ReleaseReport) -> String {
  let gate_rows = self.gates
    .map(fn(gate) {
      "| " +
      gate.name +
      " | " +
      gate.threshold.to_string() +
      " | " +
      gate.actual.to_string() +
      " | " +
      (if gate.passed { "PASS" } else { "FAIL" }) +
      " | " +
      gate.detail +
      " |"
    })
    .join("\n")
  let artifact_rows = self.artifacts
    .map(fn(item) {
      "| " +
      item.name +
      " | " +
      item.format +
      " | " +
      item.status +
      " | " +
      item.summary +
      " |"
    })
    .join("\n")
  "# Release analysis: " +
  self.project +
  "\n\n" +
  "Source hash: `" +
  self.source_hash +
  "`\n\n" +
  "Status: **" +
  (if self.is_ready() { "READY" } else { "REVIEW REQUIRED" }) +
  "**\n\n" +
  "## Gates\n\n| Gate | Threshold | Actual | Status | Detail |\n|---|---:|---:|---|---|\n" +
  gate_rows +
  "\n\n## Evidence artifacts\n\n| Artifact | Format | Status | Summary |\n|---|---|---|---|\n" +
  artifact_rows +
  "\n\n## Diagnostics\n\n" +
  diagnostics_markdown(self.diagnostics) +
  "\n\n## Benchmark\n\n" +
  benchmark_markdown([self.benchmark])
}

///|
pub fn ReleaseReport::summary(self : ReleaseReport) -> String {
  self.project +
  ": lines=" +
  self.source_lines.to_string() +
  ", modules=" +
  self.modules.to_string() +
  ", gates=" +
  self.passed_gates().to_string() +
  "/" +
  self.gates.length().to_string() +
  ", errors=" +
  self.error_count().to_string() +
  ", warnings=" +
  self.warning_count().to_string() +
  ", status=" +
  (if self.is_ready() { "ready" } else { "review" })
}

///|
pub fn release_report_contract() -> String {
  "gates=source-lines,modules,diagnostic-errors,timing-acyclic,coverage-points,netlist-issues,benchmark-tokens; artifacts=rules,timing,coverage,netlist,ir,query,verification"
}
