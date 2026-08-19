///|
/// A persisted summary for one analyzed source file.
pub struct SourceArtifact {
  path : String
  hash : String
  lines : Int
  modules : Array[String]
  diagnostics : Int
  errors : Int
  warnings : Int
}

///|
/// A project-level snapshot suitable for incremental checks.
pub struct ProjectSnapshot {
  name : String
  artifacts : Array[SourceArtifact]
  total_lines : Int
  total_modules : Int
  total_diagnostics : Int
  errors : Int
  warnings : Int
}

///|
/// A file-level change between two project snapshots.
pub enum ChangeKind {
  Added
  Modified
  Removed
  Unchanged
} derive(Eq)

///|
/// One changed path and its old/new hashes.
pub struct FileChange {
  path : String
  kind : ChangeKind
  previous_hash : String?
  current_hash : String?
}

///|
/// A stable API for project status consumers.
pub struct ProjectStatus {
  name : String
  files : Int
  lines : Int
  modules : Int
  diagnostics : Int
  errors : Int
  warnings : Int
  clean : Bool
}

///|
/// Create an artifact from a completed pipeline result.
pub fn SourceArtifact::from_result(
  path : String,
  result : PipelineResult,
) -> SourceArtifact {
  {
    path,
    hash: result.source_hash,
    lines: result.source_lines,
    modules: result.design.module_names(),
    diagnostics: result.diagnostics.length(),
    errors: result.summary.errors,
    warnings: result.summary.warnings,
  }
}

///|
/// Construct an empty snapshot.
pub fn ProjectSnapshot::empty(name : String) -> ProjectSnapshot {
  {
    name,
    artifacts: [],
    total_lines: 0,
    total_modules: 0,
    total_diagnostics: 0,
    errors: 0,
    warnings: 0,
  }
}

///|
/// Build a snapshot from files in caller-provided order.
pub fn ProjectSnapshot::from_sources(
  name : String,
  units : Array[SourceUnit],
  options : PipelineOptions,
) -> ProjectSnapshot {
  let snapshot = ProjectSnapshot::empty(name)
  let artifacts : Array[SourceArtifact] = []
  let mut lines = 0
  let mut modules = 0
  let mut diagnostics = 0
  let mut errors = 0
  let mut warnings = 0
  for unit in units {
    let result = run_pipeline(unit.source, options)
    let artifact = SourceArtifact::from_result(unit.path, result)
    lines += artifact.lines
    modules += artifact.modules.length()
    diagnostics += artifact.diagnostics
    errors += artifact.errors
    warnings += artifact.warnings
    artifacts.push(artifact)
  }
  {
    ..snapshot,
    artifacts,
    total_lines: lines,
    total_modules: modules,
    total_diagnostics: diagnostics,
    errors,
    warnings,
  }
}

///|
/// Return a project status without retaining parser trees.
pub fn ProjectSnapshot::status(self : ProjectSnapshot) -> ProjectStatus {
  {
    name: self.name,
    files: self.artifacts.length(),
    lines: self.total_lines,
    modules: self.total_modules,
    diagnostics: self.total_diagnostics,
    errors: self.errors,
    warnings: self.warnings,
    clean: self.errors == 0,
  }
}

///|
/// Find an artifact by its normalized path.
pub fn ProjectSnapshot::find(
  self : ProjectSnapshot,
  path : String,
) -> SourceArtifact? {
  for artifact in self.artifacts {
    if artifact.path == path {
      return Some(artifact)
    }
  }
  None
}

///|
/// Return artifacts sorted by path, preserving their values.
pub fn ProjectSnapshot::sorted_artifacts(
  self : ProjectSnapshot,
) -> Array[SourceArtifact] {
  let result = self.artifacts.copy()
  result.sort_by(fn(left, right) { left.path.compare(right.path) })
  result
}

///|
/// Return changed paths between two snapshots.
pub fn compare_snapshots(
  previous : ProjectSnapshot,
  current : ProjectSnapshot,
) -> Array[FileChange] {
  let result : Array[FileChange] = []
  for artifact in current.artifacts {
    match previous.find(artifact.path) {
      None =>
        result.push({
          path: artifact.path,
          kind: Added,
          previous_hash: None,
          current_hash: Some(artifact.hash),
        })
      Some(old) if old.hash == artifact.hash =>
        result.push({
          path: artifact.path,
          kind: Unchanged,
          previous_hash: Some(old.hash),
          current_hash: Some(artifact.hash),
        })
      Some(old) =>
        result.push({
          path: artifact.path,
          kind: Modified,
          previous_hash: Some(old.hash),
          current_hash: Some(artifact.hash),
        })
    }
  }
  for old in previous.artifacts {
    if current.find(old.path) is None {
      result.push({
        path: old.path,
        kind: Removed,
        previous_hash: Some(old.hash),
        current_hash: None,
      })
    }
  }
  result
}

///|
/// Return only paths requiring re-analysis.
pub fn changed_paths(changes : Array[FileChange]) -> Array[String] {
  changes
  .filter(fn(change) {
    match change.kind {
      Added | Modified | Removed => true
      Unchanged => false
    }
  })
  .map(fn(change) { change.path })
}

///|
/// Return a stable change label for logs.
pub fn ChangeKind::to_text(self : ChangeKind) -> String {
  match self {
    Added => "added"
    Modified => "modified"
    Removed => "removed"
    Unchanged => "unchanged"
  }
}

///|
/// Render a change list as a review table.
pub fn changes_markdown(changes : Array[FileChange]) -> String {
  let mut out = "| Path | Change | Previous | Current |\n| --- | --- | --- | --- |\n"
  for change in changes {
    out += "| " +
      change.path +
      " | " +
      change.kind.to_text() +
      " | " +
      change.previous_hash.unwrap_or("-") +
      " | " +
      change.current_hash.unwrap_or("-") +
      " |\n"
  }
  out
}

///|
/// Render a compact project status line.
pub fn ProjectStatus::to_text(self : ProjectStatus) -> String {
  "project=" +
  self.name +
  " files=" +
  self.files.to_string() +
  " lines=" +
  self.lines.to_string() +
  " modules=" +
  self.modules.to_string() +
  " diagnostics=" +
  self.diagnostics.to_string() +
  " errors=" +
  self.errors.to_string() +
  " warnings=" +
  self.warnings.to_string()
}

///|
/// Render project status as JSON.
pub fn ProjectStatus::to_json(self : ProjectStatus) -> String {
  let clean = if self.clean { "true" } else { "false" }
  "{\"name\":\"" +
  self.name +
  "\",\"files\":" +
  self.files.to_string() +
  ",\"lines\":" +
  self.lines.to_string() +
  ",\"modules\":" +
  self.modules.to_string() +
  ",\"diagnostics\":" +
  self.diagnostics.to_string() +
  ",\"errors\":" +
  self.errors.to_string() +
  ",\"warnings\":" +
  self.warnings.to_string() +
  ",\"clean\":" +
  clean +
  "}"
}

///|
/// Render every artifact as a source inventory.
pub fn ProjectSnapshot::inventory(self : ProjectSnapshot) -> String {
  let mut out = "| Path | Hash | Lines | Modules | Diagnostics |\n| --- | --- | ---: | ---: | ---: |\n"
  for artifact in self.sorted_artifacts() {
    out += "| " +
      artifact.path +
      " | " +
      artifact.hash +
      " | " +
      artifact.lines.to_string() +
      " | " +
      artifact.modules.length().to_string() +
      " | " +
      artifact.diagnostics.to_string() +
      " |\n"
  }
  out
}

///|
/// Serialize a snapshot for a local cache or CI artifact.
pub fn ProjectSnapshot::to_json(self : ProjectSnapshot) -> String {
  let artifacts = self.artifacts
    .map(fn(item) {
      let modules = item.modules.map(fn(name) { "\"" + name + "\"" }).join(",")
      "{\"path\":\"" +
      item.path +
      "\",\"hash\":\"" +
      item.hash +
      "\",\"lines\":" +
      item.lines.to_string() +
      ",\"modules\":[" +
      modules +
      "],\"diagnostics\":" +
      item.diagnostics.to_string() +
      ",\"errors\":" +
      item.errors.to_string() +
      ",\"warnings\":" +
      item.warnings.to_string() +
      "}"
    })
    .join(",")
  "{\"name\":\"" +
  self.name +
  "\",\"total_lines\":" +
  self.total_lines.to_string() +
  ",\"total_modules\":" +
  self.total_modules.to_string() +
  ",\"total_diagnostics\":" +
  self.total_diagnostics.to_string() +
  ",\"errors\":" +
  self.errors.to_string() +
  ",\"warnings\":" +
  self.warnings.to_string() +
  ",\"artifacts\":[" +
  artifacts +
  "]}"
}

///|
/// Return a snapshot report with aggregate and per-file rows.
pub fn ProjectSnapshot::snapshot_report(self : ProjectSnapshot) -> String {
  let status = self.status()
  "# Project snapshot: " +
  status.name +
  "\n\n" +
  status.to_text() +
  "\n\n" +
  self.inventory()
}

///|
/// Return module names that are present in exactly one artifact.
pub fn module_owners(
  snapshot : ProjectSnapshot,
  module_name : String,
) -> Array[String] {
  snapshot.artifacts
  .filter(fn(item) { item.modules.contains(module_name) })
  .map(fn(item) { item.path })
}

///|
/// Return duplicate module definitions across a snapshot.
pub fn duplicate_module_owners(snapshot : ProjectSnapshot) -> Array[String] {
  let seen : Array[String] = []
  let duplicates : Array[String] = []
  for artifact in snapshot.artifacts {
    for module_name in artifact.modules {
      if seen.contains(module_name) && !duplicates.contains(module_name) {
        duplicates.push(module_name)
      }
      seen.push(module_name)
    }
  }
  duplicates
}

///|
/// Return files whose source hash differs from a supplied hash.
pub fn artifacts_with_hash(
  snapshot : ProjectSnapshot,
  hash : String,
) -> Array[SourceArtifact] {
  snapshot.artifacts.filter(fn(item) { item.hash == hash })
}

///|
/// Create source units from paths and source strings supplied by an adapter.
pub fn source_units(
  paths : Array[String],
  sources : Array[String],
) -> Array[SourceUnit] {
  let result : Array[SourceUnit] = []
  let count = if paths.length() < sources.length() {
    paths.length()
  } else {
    sources.length()
  }
  for index in 0..<=count {
    result.push(SourceUnit::new(paths[index], sources[index]))
  }
  result
}

///|
/// Return a stable configuration stamp for a pipeline option set.
pub fn pipeline_options_stamp(options : PipelineOptions) -> String {
  let metric = if options.compute_metrics { "1" } else { "0" }
  let graph = if options.compute_graph { "1" } else { "0" }
  let suppressions = if options.enable_suppressions { "1" } else { "0" }
  let escalated = if options.warnings_as_errors { "1" } else { "0" }
  "file=" +
  options.file_name +
  ";metrics=" +
  metric +
  ";graph=" +
  graph +
  ";suppressions=" +
  suppressions +
  ";warnings-as-errors=" +
  escalated
}

///|
/// Combine source and option fingerprints into a cache key.
pub fn analysis_cache_key(source : String, options : PipelineOptions) -> String {
  source_hash(source) + "::" + source_hash(pipeline_options_stamp(options))
}

///|
/// Return whether a workspace contains no errors.
pub fn snapshot_is_clean(snapshot : ProjectSnapshot) -> Bool {
  snapshot.errors == 0
}

///|
/// Return all source artifacts with errors.
pub fn failing_artifacts(snapshot : ProjectSnapshot) -> Array[SourceArtifact] {
  snapshot.artifacts.filter(fn(item) { item.errors > 0 })
}

///|
/// Return all source artifacts with warnings but no errors.
pub fn warning_artifacts(snapshot : ProjectSnapshot) -> Array[SourceArtifact] {
  snapshot.artifacts.filter(fn(item) { item.errors == 0 && item.warnings > 0 })
}

///|
/// Return a sorted list of paths with any finding.
pub fn paths_with_findings(snapshot : ProjectSnapshot) -> Array[String] {
  let result = snapshot.artifacts
    .filter(fn(item) { item.diagnostics > 0 })
    .map(fn(item) { item.path })
  result.sort()
  result
}

///|
/// Return a release-note-sized project acceptance line.
pub fn acceptance_project_line(snapshot : ProjectSnapshot) -> String {
  let status = snapshot.status()
  status.name +
  ": " +
  status.files.to_string() +
  " files, " +
  status.lines.to_string() +
  " lines, " +
  status.modules.to_string() +
  " modules, " +
  status.errors.to_string() +
  " errors"
}
