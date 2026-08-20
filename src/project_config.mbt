///|
/// A source selection entry in a project manifest.
pub struct ProjectSource {
  path : String
  source : String
  enabled : Bool
  language : String
}

///|
/// A rule policy entry parsed from `rtl.conf`.
pub struct ProjectRulePolicy {
  code : String
  enabled : Bool
  severity : Severity?
  reason : String
}

///|
/// Configuration for a repeatable RTL workspace audit.
pub struct ProjectConfig {
  mut name : String
  mut profile : String
  defines : Array[String]
  include_paths : Array[String]
  source_paths : Array[String]
  exclude_paths : Array[String]
  rules : Array[ProjectRulePolicy]
  mut max_diagnostics : Int
  mut deny_warnings : Bool
  mut run_preprocessor : Bool
  mut run_hierarchy : Bool
  mut run_timing : Bool
  mut run_coverage : Bool
}

///|
/// Aggregated metrics for a project source set.
pub struct ProjectMetrics {
  files : Int
  enabled_files : Int
  source_lines : Int
  modules : Int
  signals : Int
  assignments : Int
  instances : Int
  errors : Int
  warnings : Int
  critical_delay : Int
  hierarchy_depth : Int
}

///|
/// Result of applying project configuration to a source set.
pub struct ProjectAudit {
  config : ProjectConfig
  sources : Array[ProjectSource]
  diagnostics : Array[Diagnostic]
  metrics : ProjectMetrics
  elaborated : ElaboratedDesign?
  timing : TimingReport?
  coverage : CoverageReport?
}

///|
pub fn ProjectConfig::default() -> ProjectConfig {
  {
    name: "rtl-project",
    profile: "default",
    defines: [],
    include_paths: [],
    source_paths: [],
    exclude_paths: [],
    rules: [],
    max_diagnostics: 1000,
    deny_warnings: false,
    run_preprocessor: true,
    run_hierarchy: true,
    run_timing: true,
    run_coverage: true,
  }
}

///|
fn project_bool(text : String, fallback : Bool) -> Bool {
  match text.trim().to_owned() {
    "1" | "true" | "yes" | "on" => true
    "0" | "false" | "no" | "off" => false
    _ => fallback
  }
}

///|
fn project_int(text : String, fallback : Int) -> Int {
  let mut value = 0
  let mut found = false
  for c in text.to_array() {
    if c >= '0' && c <= '9' {
      value = value * 10 + c.to_int() - '0'.to_int()
      found = true
    }
  }
  if found {
    value
  } else {
    fallback
  }
}

///|
fn project_append_unique(values : Array[String], value : String) -> Unit {
  if value != "" && !values.contains(value) {
    values.push(value)
  }
}

///|
fn project_rule(
  rules : Array[ProjectRulePolicy],
  code : String,
  enabled : Bool,
  severity : Severity?,
  reason : String,
) -> Unit {
  rules.push({ code, enabled, severity, reason })
}

///|
/// Parse a deliberately small, reviewable `key=value` project manifest.
pub fn parse_project_config(text : String) -> ProjectConfig {
  let config = ProjectConfig::default()
  for raw_line in text.split("\n") {
    let line = raw_line.trim().to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    match line.split_once("=") {
      Some((raw_key, raw_value)) => {
        let key = raw_key.trim().to_owned()
        let value = raw_value.trim().to_owned()
        if key == "name" {
          config.name = value
        } else if key == "profile" {
          config.profile = value
        } else if key == "define" {
          project_append_unique(config.defines, value)
        } else if key == "include" {
          project_append_unique(config.include_paths, value)
        } else if key == "source" {
          project_append_unique(config.source_paths, value)
        } else if key == "exclude" {
          project_append_unique(config.exclude_paths, value)
        } else if key == "max_diagnostics" {
          config.max_diagnostics = project_int(value, config.max_diagnostics)
        } else if key == "deny_warnings" {
          config.deny_warnings = project_bool(value, config.deny_warnings)
        } else if key == "preprocess" {
          config.run_preprocessor = project_bool(value, config.run_preprocessor)
        } else if key == "hierarchy" {
          config.run_hierarchy = project_bool(value, config.run_hierarchy)
        } else if key == "timing" {
          config.run_timing = project_bool(value, config.run_timing)
        } else if key == "coverage" {
          config.run_coverage = project_bool(value, config.run_coverage)
        } else if key.has_prefix("rule.") {
          let code = key[5:].to_owned()
          let disabled = value == "off" ||
            value == "false" ||
            value == "disable"
          let severity = severity_from_text(value)
          project_rule(
            config.rules,
            code,
            !disabled,
            severity,
            "project manifest",
          )
        }
      }
      None => ()
    }
  }
  config
}

///|
pub fn ProjectConfig::with_profile(
  self : ProjectConfig,
  profile : String,
) -> ProjectConfig {
  let config = { ..self, profile, }
  match profile {
    "strict" => {
      config.deny_warnings = true
      config.max_diagnostics = 5000
    }
    "fast" => {
      config.run_timing = false
      config.run_coverage = false
      config.max_diagnostics = 200
    }
    "syntax" => {
      config.run_hierarchy = false
      config.run_timing = false
      config.run_coverage = false
    }
    _ => ()
  }
  config
}

///|
pub fn ProjectConfig::to_check_config(self : ProjectConfig) -> CheckConfig {
  let config = CheckConfig::default().with_max_diagnostics(self.max_diagnostics)
  let mut result = if self.deny_warnings {
    config.with_severity("*", Error)
  } else {
    config
  }
  for rule in self.rules {
    result = if rule.enabled {
      match rule.severity {
        Some(severity) => result.with_severity(rule.code, severity)
        None => result
      }
    } else {
      result.without(rule.code)
    }
  }
  result
}

///|
pub fn ProjectConfig::accepts_path(self : ProjectConfig, path : String) -> Bool {
  if self.exclude_paths.any(fn(item) { path.has_prefix(item) }) {
    return false
  }
  if self.source_paths.length() == 0 {
    return true
  }
  self.source_paths.any(fn(item) { path.has_prefix(item) })
}

///|
pub fn ProjectConfig::to_text(self : ProjectConfig) -> String {
  "name=" +
  self.name +
  "\n" +
  "profile=" +
  self.profile +
  "\n" +
  "define=" +
  self.defines.join(",") +
  "\n" +
  "include=" +
  self.include_paths.join(",") +
  "\n" +
  "source=" +
  self.source_paths.join(",") +
  "\n" +
  "exclude=" +
  self.exclude_paths.join(",") +
  "\n" +
  "max_diagnostics=" +
  self.max_diagnostics.to_string() +
  "\n" +
  "deny_warnings=" +
  (if self.deny_warnings { "true" } else { "false" }) +
  "\n" +
  "preprocess=" +
  (if self.run_preprocessor { "true" } else { "false" }) +
  "\n" +
  "hierarchy=" +
  (if self.run_hierarchy { "true" } else { "false" }) +
  "\n" +
  "timing=" +
  (if self.run_timing { "true" } else { "false" }) +
  "\n" +
  "coverage=" +
  (if self.run_coverage { "true" } else { "false" })
}

///|
pub fn ProjectConfig::to_json(self : ProjectConfig) -> String {
  "{\"name\":\"" +
  json_escape(self.name) +
  "\",\"profile\":\"" +
  json_escape(self.profile) +
  "\",\"defines\":[" +
  self.defines.map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "],\"source_paths\":[" +
  self.source_paths.map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "],\"exclude_paths\":[" +
  self.exclude_paths.map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "],\"max_diagnostics\":" +
  self.max_diagnostics.to_string() +
  ",\"deny_warnings\":" +
  (if self.deny_warnings { "true" } else { "false" }) +
  "}"
}

///|
fn project_source_enabled(
  config : ProjectConfig,
  source : ProjectSource,
) -> Bool {
  source.enabled && config.accepts_path(source.path)
}

///|
fn project_module_count(sources : Array[ProjectSource]) -> Int {
  let mut count = 0
  for source in sources {
    if source.enabled {
      count += parse(source.source).modules.length()
    }
  }
  count
}

///|
fn project_design(sources : Array[ProjectSource]) -> Design {
  let design = Design::empty()
  for source in sources {
    if source.enabled {
      for unit in parse(source.source).modules {
        design.modules.push(unit)
      }
    }
  }
  design
}

///|
fn project_metrics(
  sources : Array[ProjectSource],
  diagnostics : Array[Diagnostic],
  elaborated : ElaboratedDesign?,
  timing : TimingReport?,
) -> ProjectMetrics {
  let design = project_design(sources)
  let mut lines = 0
  let mut enabled = 0
  for source in sources {
    if source.enabled {
      enabled += 1
      lines += source_line_count(source.source)
    }
  }
  let signals = design.modules.fold(init=0, fn(total, unit) {
    total + unit.ports.length() + unit.signals.length()
  })
  let assignments = design.modules.fold(init=0, fn(total, unit) {
    total + unit.assignments.length()
  })
  let instances = design.modules.fold(init=0, fn(total, unit) {
    total + unit.instances.length()
  })
  {
    files: sources.length(),
    enabled_files: enabled,
    source_lines: lines,
    modules: project_module_count(sources),
    signals,
    assignments,
    instances,
    errors: diagnostics.filter(fn(item) { item.severity == Error }).length(),
    warnings: diagnostics.filter(fn(item) { item.severity == Warning }).length(),
    critical_delay: timing.map(fn(item) { item.critical_delay }).unwrap_or(0),
    hierarchy_depth: elaborated.map(fn(item) { item.depth }).unwrap_or(0),
  }
}

///|
/// Analyze a configured in-memory source set with all enabled project stages.
pub fn audit_project(
  config : ProjectConfig,
  sources : Array[ProjectSource],
) -> ProjectAudit {
  let selected = sources.map(fn(source) {
    { ..source, enabled: project_source_enabled(config, source) }
  })
  let diagnostics : Array[Diagnostic] = []
  let design = project_design(selected)
  for source in selected {
    if source.enabled {
      let parse_result = parse_with_diagnostics(source.source)
      for item in parse_result.diagnostics {
        diagnostics.push(
          Diagnostic::new(
            item.code,
            item.severity,
            item.message,
            item.line,
            item.column,
          ),
        )
      }
      for
        item in check_source_with_config(
          source.source,
          config.to_check_config(),
        ) {
        diagnostics.push(item)
      }
    }
  }
  let elaborated = if config.run_hierarchy {
    Some(elaborate_design(design))
  } else {
    None
  }
  match elaborated {
    Some(result) =>
      for item in elaboration_diagnostics(result) {
        diagnostics.push(item)
      }
    None => ()
  }
  let timing = if config.run_timing {
    Some(timing_analyze(design, TimingConfig::default()))
  } else {
    None
  }
  match timing {
    Some(result) =>
      for item in timing_diagnostics(result, TimingConfig::default()) {
        diagnostics.push(item)
      }
    None => ()
  }
  let metrics = project_metrics(selected, diagnostics, elaborated, timing)
  {
    config,
    sources: selected,
    diagnostics,
    metrics,
    elaborated,
    timing,
    coverage: if config.run_coverage {
      Some(coverage_structure(design, metrics.source_lines))
    } else {
      None
    },
  }
}

///|
pub fn project_source(path : String, source : String) -> ProjectSource {
  {
    path,
    source,
    enabled: true,
    language: if path.has_suffix(".sv") {
      "systemverilog"
    } else {
      "verilog"
    },
  }
}

///|
pub fn ProjectAudit::is_clean(self : ProjectAudit) -> Bool {
  !self.diagnostics.any(fn(item) { item.severity == Error })
}

///|
pub fn ProjectAudit::status_line(self : ProjectAudit) -> String {
  "files=" +
  self.metrics.files.to_string() +
  " enabled=" +
  self.metrics.enabled_files.to_string() +
  " modules=" +
  self.metrics.modules.to_string() +
  " lines=" +
  self.metrics.source_lines.to_string() +
  " errors=" +
  self.metrics.errors.to_string() +
  " warnings=" +
  self.metrics.warnings.to_string()
}

///|
pub fn ProjectAudit::failed_paths(self : ProjectAudit) -> Array[String] {
  self.sources
  .filter(fn(source) {
    source.enabled &&
    self.diagnostics.any(fn(item) {
      item.line > 0 && item.message.contains(source.path)
    })
  })
  .map(fn(source) { source.path })
}

///|
pub fn ProjectAudit::to_json(self : ProjectAudit) -> String {
  "{\"status\":\"" +
  (if self.is_clean() { "clean" } else { "failed" }) +
  "\",\"metrics\":{" +
  "\"files\":" +
  self.metrics.files.to_string() +
  ",\"enabled_files\":" +
  self.metrics.enabled_files.to_string() +
  ",\"lines\":" +
  self.metrics.source_lines.to_string() +
  ",\"modules\":" +
  self.metrics.modules.to_string() +
  ",\"signals\":" +
  self.metrics.signals.to_string() +
  ",\"assignments\":" +
  self.metrics.assignments.to_string() +
  ",\"instances\":" +
  self.metrics.instances.to_string() +
  ",\"errors\":" +
  self.metrics.errors.to_string() +
  ",\"warnings\":" +
  self.metrics.warnings.to_string() +
  "}," +
  "\"diagnostics\":[" +
  self.diagnostics
  .map(fn(item) {
    "{\"code\":\"" +
    item.code +
    "\",\"message\":\"" +
    json_escape(item.message) +
    "\"}"
  })
  .join(",") +
  "]}"
}

///|
pub fn ProjectAudit::to_markdown(self : ProjectAudit) -> String {
  "# Project audit\n\n" +
  self.status_line() +
  "\n\n" +
  "| Code | Severity | Message |\n| --- | --- | --- |\n" +
  self.diagnostics
  .map(fn(item) {
    "| " +
    item.code +
    " | " +
    severity_text(item.severity) +
    " | " +
    item.message +
    " |"
  })
  .join("\n") +
  "\n"
}

///|
pub fn project_config_contract() -> String {
  "manifest=key_value; profiles=default,strict,fast,syntax; stages=preprocess,hierarchy,timing,coverage; " +
  "sources=in_memory_and_path_metadata"
}
