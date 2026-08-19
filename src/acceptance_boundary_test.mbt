///|
test "lexer handles empty and whitespace-only inputs" {
  inspect(lex("").length(), content="0")
  inspect(lex(" \t\r\n ").length(), content="0")
  inspect(
    lex("module\nname").map(fn(item) { item.text }).join("|"),
    content="module|name",
  )
}

///|
test "lexer retains source coordinates and offsets" {
  let tokens = lex("module a;\n  wire b;\nendmodule")
  inspect(tokens[0].line, content="1")
  inspect(tokens[0].column, content="1")
  inspect(tokens[0].offset, content="0")
  inspect(tokens[3].line, content="2")
  inspect(tokens[3].column, content="3")
  inspect(tokens[3].text, content="wire")
}

///|
test "lexer recognizes comments and strings" {
  let source = "// comment\nmodule m;\nstring s = \"a b\";\nendmodule"
  let tokens = lex(source)
  inspect(tokens.any(fn(item) { item.text == "comment" }), content="false")
  inspect(tokens.any(fn(item) { item.text.contains("a b") }), content="true")
}

///|
test "lexer recognizes longest operators" {
  let tokens = lex("a <= b; c === d; e && f; g << 2;")
  inspect(
    tokens
    .map(fn(item) { item.text })
    .filter(fn(item) {
      item == "<=" || item == "===" || item == "&&" || item == "<<"
    })
    .join("|"),
    content="<=|===|&&|<<",
  )
}

///|
test "lexer preserves unknown characters instead of dropping them" {
  let tokens = lex("module m; @ # $ endmodule")
  inspect(tokens.any(fn(item) { item.text == "@" }), content="true")
  inspect(tokens.any(fn(item) { item.text == "#" }), content="true")
}

///|
test "parser reads ANSI port widths" {
  let design = parse(
    "module bus(input [7:0] a, output [0:0] y); assign y = a[0]; endmodule",
  )
  let unit = design.modules[0]
  inspect(unit.name, content="bus")
  inspect(unit.ports.length(), content="2")
  inspect(
    unit.ports[0].width.map(fn(item) { item.bits() }).unwrap_or(0),
    content="8",
  )
  inspect(
    unit.ports[1].width.map(fn(item) { item.bits() }).unwrap_or(0),
    content="1",
  )
}

///|
test "parser handles parameters and net types" {
  let design = parse(
    "module param #(parameter WIDTH = 8) (input logic a, output wire y); endmodule",
  )
  let unit = design.modules[0]
  inspect(unit.parameters.length(), content="1")
  inspect(unit.parameters[0].name, content="WIDTH")
  inspect(unit.signals.length(), content="0")
  inspect(unit.ports[0].name, content="a")
}

///|
test "parser retains expression structure" {
  let design = parse(
    "module expr(input a, input b, output y); assign y = (a & b) ? a : b; endmodule",
  )
  let assignment = design.modules[0].assignments[0]
  inspect(assignment.lhs, content="y")
  inspect(assignment.operator, content="=")
  inspect(
    assignment.rhs_expr.map(fn(item) { item.to_text() }).unwrap_or(""),
    content="((a & b) ? a : b)",
  )
  inspect(
    assignment.rhs_expr
    .map(fn(item) { item.references().join(",") })
    .unwrap_or(""),
    content="a,b",
  )
}

///|
test "parser reads instances and named connections" {
  let source = "module child(input a, output y); assign y = a; endmodule\nmodule top(input a, output y); child u0(.a(a), .y(y)); endmodule"
  let design = parse(source)
  inspect(design.modules.length(), content="2")
  inspect(design.modules[1].instances.length(), content="1")
  inspect(design.modules[1].instances[0].module_name, content="child")
  inspect(design.modules[1].instances[0].instance_name, content="u0")
  inspect(design.modules[1].instances[0].connections.length(), content="2")
}

///|
test "parser reports recoverable missing endmodule" {
  let result = parse_with_diagnostics(
    "module broken(input a); assign a = missing;",
  )
  inspect(result.design.modules.length(), content="1")
  inspect(result.diagnostics.length() > 0, content="true")
  inspect(
    parse_diagnostics("module broken(input a);").length() > 0,
    content="true",
  )
}

///|
test "expression utilities cover constants and nesting" {
  inspect(evaluate_number("8'hff").unwrap_or(0), content="255")
  inspect(evaluate_number("4'b1010").unwrap_or(0), content="10")
  inspect(evaluate_number("12").unwrap_or(0), content="12")
  let expression = expr_binary(
    expr_number("2"),
    "+",
    expr_binary(expr_number("3"), "*", expr_number("4")),
  )
  inspect(evaluate_constant(expression).unwrap_or(0), content="14")
  inspect(expression.node_count(), content="5")
  inspect(expression.depth(), content="3")
  inspect(expression.fold_constants().to_text(), content="14")
}

///|
test "expression utilities distinguish lvalues and references" {
  let left = expr_index(expr_name("bus"), expr_number("1"))
  let right = expr_binary(expr_name("a"), "+", expr_name("b"))
  inspect(left.is_lvalue(), content="true")
  inspect(right.is_lvalue(), content="false")
  inspect(right.references().join(","), content="a,b")
  inspect(right.contains_operator("+"), content="true")
  inspect(right.root_name() is None, content="true")
}

///|
test "width analysis handles literals and concatenations" {
  inspect(literal_width("8'hff").unwrap_or(0), content="8")
  inspect(literal_width("1'bx").unwrap_or(0), content="1")
  inspect(literal_has_unknown("4'b10x1"), content="true")
  inspect(literal_has_unknown("4'b1011"), content="false")
  let unit = parse(
      "module w(input [3:0] a, output [7:0] y); assign y = {a, a}; endmodule",
    ).modules[0]
  let expression = unit.assignments[0].rhs_expr.unwrap()
  inspect(expression.width(unit).unwrap_or(0), content="8")
  inspect(unit.width_report().facts.length(), content="1")
}

///|
test "checker configuration can disable rules and cap output" {
  let source = "module noisy(input a, output y); wire tmp; assign y = unknown; endmodule"
  let defaults = check_source_with_config(source, CheckConfig::default())
  let disabled = check_source_with_config(
    source,
    CheckConfig::default().without("RTL014"),
  )
  inspect(defaults.any(fn(item) { item.code == "RTL014" }), content="true")
  inspect(disabled.any(fn(item) { item.code == "RTL014" }), content="false")
  inspect(
    check_source_with_config(
      source,
      CheckConfig::default().with_max_diagnostics(1),
    ).length(),
    content="1",
  )
}

///|
test "checker reports summaries and stable exit codes" {
  let source = "module broken(input a, output y); assign y = missing; endmodule"
  let items = check_source(source)
  inspect(diagnostics_exit_code(items), content="1")
  inspect(diagnostics_summary(items).contains("errors="), content="true")
  inspect(diagnostic_rule_ids(items).length() > 0, content="true")
  inspect(diagnostics_json(items).has_prefix("["), content="true")
  inspect(diagnostics_sarif(items).contains("2.1.0"), content="true")
}

///|
test "diagnostic severity overrides are applied" {
  let source = "module bad(output y); endmodule"
  let config = CheckConfig::default()
    .with_severity("RTL003", severity_from_text("error").unwrap())
    .without_info()
  let items = check_source_with_config(source, config)
  inspect(
    items.any(fn(item) {
      item.code == "RTL003" &&
      item.severity == severity_from_text("error").unwrap()
    }),
    content="true",
  )
  inspect(
    items.any(fn(item) { item.severity == severity_from_text("info").unwrap() }),
    content="false",
  )
}

///|
test "design graph detects dependencies and cycles" {
  let acyclic = parse(
    "module leaf(input a, output y); assign y = a; endmodule\nmodule top(input a, output y); leaf u(.a(a), .y(y)); endmodule",
  )
  let graph = acyclic.dependency_graph()
  inspect(graph.modules.join(","), content="leaf,top")
  inspect(graph.dependencies_of("top").join(","), content="leaf")
  inspect(graph.dependents_of("leaf").join(","), content="top")
  inspect(graph.has_cycle(), content="false")
  inspect(graph.to_dot().contains("\"top\" -> \"leaf\""), content="true")
  inspect(graph.topological_order().length(), content="2")
}

///|
test "design metrics count source structure" {
  let source = "module m(input [3:0] a, output [3:0] y); wire [3:0] t; assign t = a; assign y = t; endmodule"
  let metrics = design_metrics(source)
  inspect(metrics.module_count, content="1")
  inspect(metrics.port_count, content="2")
  inspect(metrics.signal_count, content="1")
  inspect(metrics.assignment_count, content="2")
  inspect(metrics.source_lines, content="1")
  inspect(metrics.to_json().contains("\"tokens\":"), content="true")
}

///|
test "reporting sorts and deduplicates findings" {
  let source = "module bad(input a, output y); wire z; assign y = missing; assign y = missing; endmodule"
  let items = check_source(source)
  let sorted = sort_diagnostics(items)
  let unique = deduplicate_diagnostics(items)
  inspect(sorted.length() >= unique.length(), content="true")
  inspect(status_label(items).length() > 0, content="true")
  inspect(
    render_report(items, report_format_from_text("summary")).contains("errors="),
    content="true",
  )
  inspect(diagnostics_json_lines(items).length() > 0, content="true")
}

///|
test "source index maps offsets and excerpts" {
  let source = "alpha\nbeta\ngamma"
  let index = SourceIndex::from(source)
  inspect(index.line_offset(1).unwrap_or(-1), content="0")
  inspect(index.line_offset(2).unwrap_or(-1), content="6")
  inspect(index.line_at(7), content="2")
  inspect(source_line(source, 3), content="gamma")
  let item = Diagnostic::new(
    "T",
    severity_from_text("error").unwrap(),
    "bad",
    2,
    2,
  )
  inspect(diagnostic_excerpt(source, item).contains("^"), content="true")
}

///|
test "formatting produces stable outlines and token dumps" {
  let source = "module m(input a, output y); assign y = a; endmodule"
  let design = parse(source)
  inspect(format_expr(expr_name("a")), content="a")
  inspect(
    format_design(design, FormatOptions::default()).contains("module m"),
    content="true",
  )
  inspect(design_outline(source).contains("m"), content="true")
  inspect(token_dump(source).contains("module"), content="true")
  inspect(normalize_tokens(source, false).contains("module"), content="true")
}

///|
test "source mapping handles coordinates and token lookup" {
  let source = "module m;\nwire a;\nendmodule"
  let coordinate = coordinate(source, 2, 1)
  inspect(coordinate.offset, content="10")
  inspect(coordinate_text(coordinate), content="2:1")
  inspect(
    token_at(source, 2, 1).map(fn(item) { item.text }).unwrap_or(""),
    content="wire",
  )
  inspect(token_occurrences(source, "a").length(), content="1")
}

///|
test "syntax validation catches delimiter and module issues" {
  let report = validate_syntax("module m(input a; assign a = a; endmodule")
  inspect(report.issues.length() > 0, content="true")
  inspect(syntax_is_safe("module m; endmodule"), content="true")
  inspect(syntax_is_safe("module m;"), content="false")
  inspect(delimiter_fingerprint("()[]{}").length() > 0, content="true")
}

///|
test "dataflow reports reads writes and cycles" {
  let unit = parse(
      "module m(input a, output y); wire t; assign t = a; assign y = t; endmodule",
    ).modules[0]
  let report = unit.dataflow()
  inspect(report.facts.length() >= 3, content="true")
  inspect(report.to_json().contains("\"facts\":"), content="true")
  inspect(unit.read_names().contains("a"), content="true")
  inspect(unit.write_names().contains("y"), content="true")
  inspect(unit.is_combinational(), content="true")
  inspect(explain_rule("RTL030").length() > 0, content="true")
}

///|
test "contract analysis compares public ports" {
  let before = parse("module m(input a, output y); endmodule").modules[0].contract()
  let after = parse("module m(input [3:0] a, output y); endmodule").modules[0].contract()
  let issues = compare_contracts(before, after)
  inspect(before.signature().contains("a"), content="true")
  inspect(issues.length() > 0, content="true")
  inspect(contract_issues_markdown(issues).contains("API003"), content="true")
}

///|
test "pipeline normalizes and emits deterministic traces" {
  let source = "module m;  \r\nendmodule"
  let result = run_default_pipeline(source)
  inspect(source_line_count(source), content="2")
  inspect(normalize_source(source), content="module m;\nendmodule")
  inspect(result.events.length(), content="5")
  inspect(result.is_well_formed(), content="true")
  inspect(result.event_trace().contains("normalize"), content="true")
  inspect(result.status_line().contains("modules=1"), content="true")
}

///|
test "pipeline options switch reports and warning policy" {
  let source = "module m(input a, output y); always_comb if (a) y = a; endmodule"
  let options = PipelineOptions::default()
    .with_reports(false, false)
    .with_warnings_as_errors(true)
    .with_file_name("fixture.v")
  let result = run_pipeline(source, options)
  inspect(result.metrics is None, content="true")
  inspect(result.graph is None, content="true")
  inspect(result.exit_code(true) == 1, content="true")
  inspect(result.to_json().contains("\"source_hash\":"), content="true")
}

///|
test "pipeline suppressions remove only targeted diagnostics" {
  let item = Diagnostic::new(
    "RTL014",
    severity_from_text("error").unwrap(),
    "missing",
    2,
    1,
  )
  let suppressions = parse_suppressions(
    "// rtl-disable-next-line RTL014\nassign y = missing;",
  )
  inspect(suppressions.length(), content="1")
  inspect(is_suppressed(item, suppressions), content="true")
  inspect(apply_suppressions([item], suppressions).length(), content="0")
}

///|
test "workspace pipeline retains file ownership" {
  let units = [
    SourceUnit::new("a.v", "module a; endmodule"),
    SourceUnit::new(
      "b.v", "module b(input x, output y); assign y = missing; endmodule",
    ),
  ]
  let result = run_workspace(units, PipelineOptions::default())
  inspect(result.status_line().contains("files=2"), content="true")
  inspect(result.findings.any(fn(item) { item.path == "b.v" }), content="true")
  inspect(result.to_json().contains("\"summaries\":"), content="true")
  inspect(result.exit_code(), content="1")
}

///|
test "baselines distinguish new and resolved findings" {
  let item = Diagnostic::new(
    "RTL001",
    severity_from_text("warning").unwrap(),
    "width",
    4,
    2,
  )
  let baseline = baseline_from_diagnostics([item])
  inspect(parse_baseline(baseline.to_text()).entries.length(), content="1")
  inspect(compare_baseline(baseline, [item]).length(), content="0")
  let changes = compare_baseline(baseline, [])
  inspect(resolved_baseline_count(changes), content="1")
  inspect(baseline_changes_text(changes).contains("resolved"), content="true")
}

///|
test "edit sets reject overlap and preserve source hashes" {
  let source = "module m; endmodule"
  let overlap = EditSet::from_edits(source, [
    SourceEdit::new(0, 4, "unit", "one"),
    SourceEdit::new(3, 6, "x", "two"),
  ])
  inspect(overlap is None, content="true")
  let edits = EditSet::from_edits(source, [
    SourceEdit::new(0, 6, "module x", "rename"),
  ]).unwrap()
  inspect(edits.apply(source).unwrap().contains("module x"), content="true")
  inspect(edits.apply("changed") is None, content="true")
}

///|
test "project snapshots detect added modified and removed files" {
  let options = PipelineOptions::default().with_reports(false, false)
  let before = ProjectSnapshot::from_sources(
    "demo",
    [
      SourceUnit::new("a.v", "module a; endmodule"),
      SourceUnit::new("old.v", "module old; endmodule"),
    ],
    options,
  )
  let after = ProjectSnapshot::from_sources(
    "demo",
    [
      SourceUnit::new("a.v", "module a(input x); endmodule"),
      SourceUnit::new("new.v", "module new; endmodule"),
    ],
    options,
  )
  let changes = compare_snapshots(before, after)
  inspect(changes.length(), content="3")
  inspect(changed_paths(changes).length(), content="3")
  inspect(after.status().files, content="2")
  inspect(after.inventory().contains("new.v"), content="true")
}

///|
test "project cache keys include source and options" {
  let options = PipelineOptions::default()
  let left = analysis_cache_key("module a; endmodule", options)
  let right = analysis_cache_key("module b; endmodule", options)
  inspect(left == right, content="false")
  inspect(pipeline_options_stamp(options).contains("metrics=1"), content="true")
  inspect(snapshot_is_clean(ProjectSnapshot::empty("x")), content="true")
}

///|
test "benchmarks expose valid deterministic fixtures" {
  let fixtures = benchmark_fixtures()
  inspect(fixtures.length(), content="3")
  inspect(
    fixtures.all(fn(item) { benchmark_fixture_is_valid(item) }),
    content="true",
  )
  let result = run_benchmark(benchmark_fixture("small"), 2)
  inspect(result.rounds, content="2")
  inspect(result.source_lines > 0, content="true")
  inspect(
    benchmark_preview("small", 3).split("\n").count() <= 4,
    content="true",
  )
}

///|
test "benchmark stress source and lexer categories are bounded" {
  let source = lexer_stress_source(12)
  inspect(source.contains("module stress"), content="true")
  inspect(lex(source).length() > 12, content="true")
  inspect(
    lexer_category_counts(source).contains("identifiers="),
    content="true",
  )
  inspect(benchmark_source_bytes() > 0, content="true")
}

///|
test "project utilities expose indexes and profiles" {
  let design = parse("module m(input a, output y); assign y = a; endmodule")
  inspect(query_symbols(design, "a").length() > 0, content="true")
  inspect(profile_names().contains("strict"), content="true")
  inspect(design_interfaces(design).contains("| m |"), content="true")
  inspect(unreachable_modules(design).length(), content="0")
  inspect(
    query_symbols_text(design, "missing").contains("kind\tname"),
    content="true",
  )
}

///|
test "path mapping and line filters handle invalid bounds" {
  let source = "one\ntwo\nthree"
  let item = Diagnostic::new(
    "RTL001",
    severity_from_text("info").unwrap(),
    "note",
    2,
    1,
  )
  inspect(filter_diagnostics_by_lines([item], 3, 1).length(), content="0")
  inspect(filter_diagnostics_by_lines([item], 1, 2).length(), content="1")
  inspect(diagnostic_context(source, item, 1).contains("two"), content="true")
  inspect(parse_outline("module x; endmodule").length(), content="1")
}

///|
test "public report formats cover every adapter" {
  let items : Array[Diagnostic] = []
  inspect(render_report(items, report_format_from_text("text")), content="")
  inspect(render_report(items, report_format_from_text("json")), content="[]")
  inspect(
    render_report(items, report_format_from_text("sarif")).contains(
      "\"results\":[]",
    ),
    content="true",
  )
  inspect(
    render_report(items, report_format_from_text("markdown")).contains(
      "Location",
    ),
    content="true",
  )
  inspect(
    render_report(items, report_format_from_text("summary")).contains(
      "errors=0",
    ),
    content="true",
  )
  inspect(render_report(items, report_format_from_text("github")), content="")
}

///|
test "source repair handles trailing whitespace and empty edit sets" {
  let source = "module m;  \nendmodule"
  let fixes = trailing_whitespace_fixes(source).unwrap()
  inspect(fixes.apply(source).unwrap(), content="module m;\nendmodule")
  let empty = EditSet::from_edits(source, []).unwrap()
  inspect(empty.apply(source).unwrap(), content=source)
}
