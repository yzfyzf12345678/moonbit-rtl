///|
/// A structural coverage point derived from the RTL syntax tree.
pub struct CoveragePoint {
  id : String
  kind : String
  module_name : String
  line : Int
  label : String
  hit_count : Int
  goal : Int
}

///|
/// Coverage thresholds used by CI and review tooling.
pub struct CoverageConfig {
  line_goal : Int
  branch_goal : Int
  toggle_goal : Int
  include_info : Bool
}

///|
/// Aggregated structural coverage for a design or simulation trace.
pub struct CoverageReport {
  points : Array[CoveragePoint]
  source_lines : Int
  covered_lines : Int
  covered_branches : Int
  total_branches : Int
  covered_toggles : Int
  total_toggles : Int
}

///|
fn coverage_point(
  id : String,
  kind : String,
  unit : String,
  line : Int,
  label : String,
  goal : Int,
) -> CoveragePoint {
  { id, kind, module_name: unit, line, label, hit_count: 0, goal }
}

///|
fn coverage_always_kind_text(kind : AlwaysKind) -> String {
  match kind {
    AlwaysLevel => "always"
    AlwaysPosedge => "posedge"
    AlwaysNegedge => "negedge"
    AlwaysAny => "any"
    AlwaysComb => "comb"
    AlwaysLatch => "latch"
    AlwaysFF => "ff"
  }
}

///|
pub fn CoverageConfig::default() -> CoverageConfig {
  { line_goal: 80, branch_goal: 80, toggle_goal: 70, include_info: true }
}

///|
pub fn CoverageConfig::with_goals(
  self : CoverageConfig,
  line_goal : Int,
  branch_goal : Int,
  toggle_goal : Int,
) -> CoverageConfig {
  {
    ..self,
    line_goal: if line_goal < 0 {
      0
    } else {
      line_goal
    },
    branch_goal: if branch_goal < 0 {
      0
    } else {
      branch_goal
    },
    toggle_goal: if toggle_goal < 0 {
      0
    } else {
      toggle_goal
    },
  }
}

///|
fn coverage_add_module_points(
  points : Array[CoveragePoint],
  unit : Module,
) -> Unit {
  points.push(
    coverage_point(
      "module:" + unit.name,
      "module",
      unit.name,
      unit.span.start.line,
      unit.name,
      1,
    ),
  )
  for port in unit.ports {
    points.push(
      coverage_point(
        "port:" + unit.name + ":" + port.name,
        "port",
        unit.name,
        port.span.start.line,
        port.name,
        1,
      ),
    )
  }
  for signal in unit.signals {
    points.push(
      coverage_point(
        "signal:" + unit.name + ":" + signal.name,
        "signal",
        unit.name,
        signal.span.start.line,
        signal.name,
        1,
      ),
    )
  }
  for index, assignment in unit.assignments {
    points.push(
      coverage_point(
        "assign:" + unit.name + ":" + index.to_string(),
        "assignment",
        unit.name,
        assignment.span.start.line,
        assignment.lhs,
        1,
      ),
    )
  }
  for index, block in unit.always_blocks {
    points.push(
      coverage_point(
        "always:" + unit.name + ":" + index.to_string(),
        "always",
        unit.name,
        block.span.start.line,
        coverage_always_kind_text(block.kind),
        1,
      ),
    )
  }
  for index, instance in unit.instances {
    points.push(
      coverage_point(
        "instance:" + unit.name + ":" + index.to_string(),
        "instance",
        unit.name,
        instance.span.start.line,
        instance.instance_name,
        1,
      ),
    )
  }
  for statement_index, statement in unit.statements {
    coverage_add_statement_points(
      points,
      unit.name,
      statement_index,
      unit.span.start.line,
      statement,
    )
  }
  for block_index, block in unit.always_blocks {
    for statement_index, statement in block.statements {
      coverage_add_statement_points(
        points,
        unit.name,
        block_index * 10000 + statement_index,
        block.span.start.line,
        statement,
      )
    }
  }
}

///|
fn coverage_add_statement_points(
  points : Array[CoveragePoint],
  module_name : String,
  index : Int,
  line : Int,
  statement : Statement,
) -> Unit {
  match statement {
    ConditionalStatement(_, when_true, when_false) => {
      points.push(
        coverage_point(
          "branch:" + module_name + ":" + index.to_string() + ":true",
          "branch_true",
          module_name,
          line,
          "true",
          1,
        ),
      )
      points.push(
        coverage_point(
          "branch:" + module_name + ":" + index.to_string() + ":false",
          "branch_false",
          module_name,
          line,
          "false",
          1,
        ),
      )
      for nested_index, nested in when_true {
        coverage_add_statement_points(
          points,
          module_name,
          index * 10 + nested_index + 1,
          line,
          nested,
        )
      }
      for nested_index, nested in when_false {
        coverage_add_statement_points(
          points,
          module_name,
          index * 10 + nested_index + 101,
          line,
          nested,
        )
      }
    }
    CaseStatement(_, items) =>
      for case_index, item in items {
        points.push(
          coverage_point(
            "case:" +
            module_name +
            ":" +
            index.to_string() +
            ":" +
            case_index.to_string(),
            if item.is_default {
              "case_default"
            } else {
              "case_item"
            },
            module_name,
            line,
            if item.is_default {
              "default"
            } else {
              "item" + case_index.to_string()
            },
            1,
          ),
        )
        for nested_index, nested in item.statements {
          coverage_add_statement_points(
            points,
            module_name,
            index * 10 + nested_index + 1,
            line,
            nested,
          )
        }
      }
    BlockStatement(items) =>
      for nested_index, nested in items {
        coverage_add_statement_points(
          points,
          module_name,
          index * 10 + nested_index + 1,
          line,
          nested,
        )
      }
    ProceduralAssignment(assignment) =>
      points.push(
        coverage_point(
          "procedural:" + module_name + ":" + index.to_string(),
          "procedural",
          module_name,
          assignment.span.start.line,
          assignment.lhs,
          1,
        ),
      )
    ExpressionStatement(_) =>
      points.push(
        coverage_point(
          "expression:" + module_name + ":" + index.to_string(),
          "expression",
          module_name,
          line,
          "expression",
          1,
        ),
      )
    InstanceStatement(instance) =>
      points.push(
        coverage_point(
          "nested_instance:" + module_name + ":" + index.to_string(),
          "instance",
          module_name,
          instance.span.start.line,
          instance.instance_name,
          1,
        ),
      )
    EmptyStatement | UnknownStatement(_) => ()
  }
}

///|
/// Build structural coverage points without requiring a simulator.
pub fn coverage_structure(
  design : Design,
  source_lines : Int,
) -> CoverageReport {
  let points : Array[CoveragePoint] = []
  for unit in design.modules {
    coverage_add_module_points(points, unit)
  }
  let branches = points
    .filter(fn(item) {
      item.kind == "branch_true" ||
      item.kind == "branch_false" ||
      item.kind == "case_item" ||
      item.kind == "case_default"
    })
    .length()
  let toggles = points
    .filter(fn(item) { item.kind == "signal" || item.kind == "port" })
    .length()
  {
    points,
    source_lines,
    covered_lines: 0,
    covered_branches: 0,
    total_branches: branches,
    covered_toggles: 0,
    total_toggles: toggles,
  }
}

///|
pub fn coverage_source(source : String) -> CoverageReport {
  coverage_structure(parse(source), source_line_count(source))
}

///|
fn coverage_mark_point(
  points : Array[CoveragePoint],
  id : String,
  amount : Int,
) -> Bool {
  for i, point in points {
    if point.id == id {
      points[i] = { ..point, hit_count: point.hit_count + amount }
      return true
    }
  }
  false
}

///|
fn coverage_point_name_matches(point : CoveragePoint, name : String) -> Bool {
  point.label == name || point.id.contains(name) || point.module_name == name
}

///|
/// Mark points using simulator activity, signal names, and optional path IDs.
pub fn CoverageReport::mark(
  self : CoverageReport,
  observed : Array[String],
) -> CoverageReport {
  let points = self.points.copy()
  for name in observed {
    for point in points {
      if coverage_point_name_matches(point, name) {
        ignore(coverage_mark_point(points, point.id, 1))
      }
    }
  }
  coverage_recompute({ ..self, points, })
}

///|
pub fn CoverageReport::mark_all(self : CoverageReport) -> CoverageReport {
  let points = self.points.map(fn(point) { { ..point, hit_count: point.goal } })
  coverage_recompute({ ..self, points, })
}

///|
fn coverage_recompute(report : CoverageReport) -> CoverageReport {
  let lines = report.points
    .filter(fn(item) { item.kind != "signal" && item.kind != "port" })
    .filter(fn(item) { item.hit_count >= item.goal })
  let branch_points = report.points.filter(fn(item) {
    item.kind == "branch_true" ||
    item.kind == "branch_false" ||
    item.kind == "case_item" ||
    item.kind == "case_default"
  })
  let toggles = report.points.filter(fn(item) {
    item.kind == "signal" || item.kind == "port"
  })
  {
    ..report,
    covered_lines: lines.length(),
    covered_branches: branch_points
    .filter(fn(item) { item.hit_count >= item.goal })
    .length(),
    covered_toggles: toggles
    .filter(fn(item) { item.hit_count >= item.goal })
    .length(),
  }
}

///|
pub fn CoverageReport::uncovered(self : CoverageReport) -> Array[CoveragePoint] {
  self.points.filter(fn(item) { item.hit_count < item.goal })
}

///|
pub fn CoverageReport::covered_points(self : CoverageReport) -> Int {
  self.points.filter(fn(item) { item.hit_count >= item.goal }).length()
}

///|
pub fn CoverageReport::total_points(self : CoverageReport) -> Int {
  self.points.length()
}

///|
fn coverage_percent(covered : Int, total : Int) -> Int {
  if total <= 0 {
    100
  } else {
    covered * 100 / total
  }
}

///|
pub fn CoverageReport::line_percent(self : CoverageReport) -> Int {
  coverage_percent(self.covered_lines, self.points.length())
}

///|
pub fn CoverageReport::branch_percent(self : CoverageReport) -> Int {
  coverage_percent(self.covered_branches, self.total_branches)
}

///|
pub fn CoverageReport::toggle_percent(self : CoverageReport) -> Int {
  coverage_percent(self.covered_toggles, self.total_toggles)
}

///|
pub fn CoverageReport::meets(
  self : CoverageReport,
  config : CoverageConfig,
) -> Bool {
  self.line_percent() >= config.line_goal &&
  self.branch_percent() >= config.branch_goal &&
  self.toggle_percent() >= config.toggle_goal
}

///|
pub fn coverage_from_simulation(
  source : String,
  result : SimulationResult,
) -> CoverageReport {
  let observed : Array[String] = []
  for binding in result.bindings {
    observed.push(binding.name)
  }
  for step in result.steps {
    for changed in step.changed_signals {
      observed.push(changed)
    }
  }
  coverage_source(source).mark(observed)
}

///|
fn coverage_point_json(point : CoveragePoint) -> String {
  "{\"id\":\"" +
  json_escape(point.id) +
  "\",\"kind\":\"" +
  point.kind +
  "\",\"module\":\"" +
  json_escape(point.module_name) +
  "\",\"line\":" +
  point.line.to_string() +
  ",\"label\":\"" +
  json_escape(point.label) +
  "\",\"hit\":" +
  point.hit_count.to_string() +
  ",\"goal\":" +
  point.goal.to_string() +
  "}"
}

///|
pub fn CoverageReport::to_json(self : CoverageReport) -> String {
  "{\"source_lines\":" +
  self.source_lines.to_string() +
  ",\"covered_lines\":" +
  self.covered_lines.to_string() +
  ",\"covered_branches\":" +
  self.covered_branches.to_string() +
  ",\"total_branches\":" +
  self.total_branches.to_string() +
  ",\"covered_toggles\":" +
  self.covered_toggles.to_string() +
  ",\"total_toggles\":" +
  self.total_toggles.to_string() +
  ",\"points\":[" +
  self.points.map(coverage_point_json).join(",") +
  "]}"
}

///|
pub fn CoverageReport::to_markdown(self : CoverageReport) -> String {
  let rows = self
    .uncovered()
    .map(fn(item) {
      "| " +
      item.kind +
      " | " +
      item.module_name +
      " | " +
      item.line.to_string() +
      " | " +
      item.label +
      " | " +
      item.hit_count.to_string() +
      " |"
    })
    .join("\n")
  let tail = if rows == "" {
    "No uncovered structural points.\n"
  } else {
    "## Uncovered points\n\n| Kind | Module | Line | Label | Hits |\n| --- | --- | ---: | --- | ---: |\n" +
    rows +
    "\n"
  }
  "# Coverage report\n\n" +
  "| Metric | Covered | Total | Percent |\n| --- | ---: | ---: | ---: |\n" +
  "| structural | " +
  self.covered_points().to_string() +
  " | " +
  self.total_points().to_string() +
  " | " +
  coverage_percent(self.covered_points(), self.total_points()).to_string() +
  "% |\n" +
  "| branches | " +
  self.covered_branches.to_string() +
  " | " +
  self.total_branches.to_string() +
  " | " +
  self.branch_percent().to_string() +
  "% |\n" +
  "| toggles | " +
  self.covered_toggles.to_string() +
  " | " +
  self.total_toggles.to_string() +
  " | " +
  self.toggle_percent().to_string() +
  "% |\n\n" +
  tail
}

///|
pub fn coverage_diagnostics(
  report : CoverageReport,
  config : CoverageConfig,
) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  if report.line_percent() < config.line_goal {
    diagnostics.push(
      Diagnostic::new(
        "COV001",
        Error,
        "structural coverage is below the configured goal",
        1,
        1,
      ),
    )
  }
  if report.branch_percent() < config.branch_goal {
    diagnostics.push(
      Diagnostic::new(
        "COV002",
        Warning,
        "branch coverage is below the configured goal",
        1,
        1,
      ),
    )
  }
  if report.toggle_percent() < config.toggle_goal {
    diagnostics.push(
      Diagnostic::new(
        "COV003",
        Warning,
        "signal toggle coverage is below the configured goal",
        1,
        1,
      ),
    )
  }
  diagnostics
}

///|
pub fn coverage_contract() -> String {
  "points=module,port,signal,assignment,branch,case,instance; " +
  "observation=simulation_bindings_and_changes; thresholds=ci_configurable"
}
