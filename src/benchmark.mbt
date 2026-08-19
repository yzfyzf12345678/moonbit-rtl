///|
/// A deterministic source fixture used for repeatable parser benchmarks.
pub struct BenchmarkFixture {
  name : String
  source : String
  module_count : Int
  expected_tokens : Int
}

///|
/// Counts collected from a benchmark run. Wall-clock measurement is kept in
/// the CLI so library users can choose their own timer and target backend.
pub struct BenchmarkResult {
  fixture : String
  rounds : Int
  tokens : Int
  diagnostics : Int
  modules : Int
  source_lines : Int
}

///|
/// A comparison between a current run and a stored baseline.
pub struct BenchmarkComparison {
  token_delta : Int
  diagnostic_delta : Int
  source_delta : Int
  improved : Bool
}

///|
fn benchmark_leaf(name : String, width : Int, assignments : Int) -> String {
  let mut out = "module " +
    name +
    " (input [" +
    (width - 1).to_string() +
    ":0] a, output [" +
    (width - 1).to_string() +
    ":0] y);\n"
  out += "  wire [" + (width - 1).to_string() + ":0] n0;\n"
  out += "  assign n0 = a;\n"
  for i in 1..<assignments {
    out += "  wire [" +
      (width - 1).to_string() +
      ":0] n" +
      i.to_string() +
      ";\n"
    out += "  assign n" +
      i.to_string() +
      " = n" +
      (i - 1).to_string() +
      " ^ a;\n"
  }
  out += "  assign y = n" + (assignments - 1).to_string() + ";\nendmodule\n"
  out
}

///|
fn benchmark_top(module_count : Int, width : Int) -> String {
  let mut out = benchmark_leaf("leaf0", width, 4)
  for index in 1..<module_count {
    out += benchmark_leaf("leaf" + index.to_string(), width, 3 + index % 4)
  }
  out += "module top (input [" +
    (width - 1).to_string() +
    ":0] a, output [" +
    (width - 1).to_string() +
    ":0] y);\n"
  out += "  wire [" + (width - 1).to_string() + ":0] stage0;\n"
  for index in 0..<module_count {
    let previous = if index == 0 {
      "a"
    } else {
      "stage" + (index - 1).to_string()
    }
    let current = "stage" + index.to_string()
    out += "  wire [" + (width - 1).to_string() + ":0] " + current + ";\n"
    out += "  leaf" +
      index.to_string() +
      " u" +
      index.to_string() +
      " (.a(" +
      previous +
      "), .y(" +
      current +
      "));\n"
  }
  out += "  assign y = stage" +
    (module_count - 1).to_string() +
    ";\nendmodule\n"
  out
}

///|
/// Build a small, medium, or large deterministic Verilog fixture.
pub fn benchmark_fixture(size : String) -> BenchmarkFixture {
  if size == "small" {
    let source = benchmark_top(2, 8)
    {
      name: "small",
      source,
      module_count: 3,
      expected_tokens: lex(source).length(),
    }
  } else if size == "large" {
    let source = benchmark_top(24, 32)
    {
      name: "large",
      source,
      module_count: 25,
      expected_tokens: lex(source).length(),
    }
  } else {
    let source = benchmark_top(8, 16)
    {
      name: "medium",
      source,
      module_count: 9,
      expected_tokens: lex(source).length(),
    }
  }
}

///|
/// Return the three canonical benchmark fixtures.
pub fn benchmark_fixtures() -> Array[BenchmarkFixture] {
  [
    benchmark_fixture("small"),
    benchmark_fixture("medium"),
    benchmark_fixture("large"),
  ]
}

///|
/// Return the canonical fixture source for CLI and editor adapters.
pub fn benchmark_fixture_source(size : String) -> String {
  benchmark_fixture(size).source
}

///|
/// Run parse and check repeatedly and return aggregate counts.
pub fn run_benchmark(
  fixture : BenchmarkFixture,
  rounds : Int,
) -> BenchmarkResult {
  let count = if rounds < 1 { 1 } else { rounds }
  let mut tokens = 0
  let mut diagnostics = 0
  for _ in 0..<count {
    tokens += lex(fixture.source).length()
    diagnostics += check_source(fixture.source).length()
  }
  let metrics = design_metrics(fixture.source)
  {
    fixture: fixture.name,
    rounds: count,
    tokens,
    diagnostics,
    modules: metrics.module_count,
    source_lines: metrics.source_lines,
  }
}

///|
/// Compare results using token and diagnostic counts as stable signals.
pub fn compare_benchmark(
  current : BenchmarkResult,
  baseline : BenchmarkResult,
) -> BenchmarkComparison {
  let token_delta = current.tokens - baseline.tokens
  let diagnostic_delta = current.diagnostics - baseline.diagnostics
  let source_delta = current.source_lines - baseline.source_lines
  {
    token_delta,
    diagnostic_delta,
    source_delta,
    improved: current.diagnostics <= baseline.diagnostics,
  }
}

///|
/// Render benchmark results as a Markdown table.
pub fn benchmark_markdown(results : Array[BenchmarkResult]) -> String {
  let mut out = "| Fixture | Rounds | Modules | Source lines | Tokens | Diagnostics |\n| --- | ---: | ---: | ---: | ---: | ---: |\n"
  for result in results {
    out += "| " +
      result.fixture +
      " | " +
      result.rounds.to_string() +
      " | " +
      result.modules.to_string() +
      " | " +
      result.source_lines.to_string() +
      " | " +
      result.tokens.to_string() +
      " | " +
      result.diagnostics.to_string() +
      " |\n"
  }
  out
}

///|
/// Render machine-readable benchmark counts.
pub fn benchmark_json(results : Array[BenchmarkResult]) -> String {
  results
  .map(fn(result) {
    "{\"fixture\":\"" +
    result.fixture +
    "\",\"rounds\":" +
    result.rounds.to_string() +
    ",\"modules\":" +
    result.modules.to_string() +
    ",\"source_lines\":" +
    result.source_lines.to_string() +
    ",\"tokens\":" +
    result.tokens.to_string() +
    ",\"diagnostics\":" +
    result.diagnostics.to_string() +
    "}"
  })
  .join("\n")
}

///|
/// Return a bounded source sample for smoke tests and documentation.
pub fn benchmark_preview(size : String, max_lines : Int) -> String {
  let fixture = benchmark_fixture(size)
  let lines = fixture.source
    .split("\n")
    .map(fn(line) { line.to_owned() })
    .collect()
  let limit = if max_lines < 0 {
    0
  } else if max_lines > lines.length() {
    lines.length()
  } else {
    max_lines
  }
  lines[:limit].join("\n")
}

///|
/// Estimate the total number of source bytes in benchmark fixtures.
pub fn benchmark_source_bytes() -> Int {
  benchmark_fixtures().fold(init=0, fn(total, fixture) {
    total + fixture.source.length()
  })
}

///|
/// Verify fixture invariants used by regression tests.
pub fn benchmark_fixture_is_valid(fixture : BenchmarkFixture) -> Bool {
  fixture.module_count == parse(fixture.source).modules.length() &&
  fixture.expected_tokens == lex(fixture.source).length() &&
  fixture.source.contains("endmodule")
}

///|
/// Create a larger flat module for lexer-only stress tests.
pub fn lexer_stress_source(identifier_count : Int) -> String {
  let count = if identifier_count < 1 { 1 } else { identifier_count }
  let mut out = "module stress (input a, output y);\n"
  for i in 0..<count {
    out += "  wire n" + i.to_string() + ";\n"
  }
  if count > 0 {
    out += "  assign n0 = a;\n"
    for i in 1..<count {
      out += "  assign n" + i.to_string() + " = n" + (i - 1).to_string() + ";\n"
    }
    out += "  assign y = n" + (count - 1).to_string() + ";\n"
  }
  out + "endmodule\n"
}

///|
/// Count words and operators separately for lexer profiling.
pub fn lexer_category_counts(source : String) -> String {
  let mut identifiers = 0
  let mut numbers = 0
  let mut operators = 0
  let mut punctuation = 0
  for token in lex(source) {
    match token.kind {
      IdentifierToken | DirectiveToken => identifiers += 1
      NumberToken | StringToken => numbers += 1
      OperatorToken => operators += 1
      PunctuationToken => punctuation += 1
    }
  }
  "identifiers=" +
  identifiers.to_string() +
  " numbers=" +
  numbers.to_string() +
  " operators=" +
  operators.to_string() +
  " punctuation=" +
  punctuation.to_string()
}
