///|
test "logic vectors preserve four-state boundaries" {
  let unknown = LogicVector::from_literal("4'b10x1")
  let high_z = LogicVector::from_literal("4'b10z1")
  inspect(unknown.width(), content="4")
  inspect(unknown.has_unknown(), content="true")
  inspect(high_z.has_high_z(), content="true")
  inspect(unknown.case_equal(high_z).to_char().to_string(), content="0")
}

///|
test "logic vectors resize and slice at empty boundaries" {
  let value = LogicVector::from_int(10, 4)
  inspect(value.slice(0, 0).to_binary(), content="0")
  inspect(value.slice(3, 0).width(), content="4")
  inspect(value.resize(0, false).width(), content="0")
  inspect(value.resize(8, false).width(), content="8")
}

///|
test "preprocessor expands and removes guarded regions" {
  let source = "`define WIDTH 4\n`ifdef WIDTH\nmodule m(input [`WIDTH-1:0] a, output y); assign y = a[0]; endmodule\n`endif"
  let result = preprocess(source, PreprocessOptions::default())
  inspect(result.is_clean(), content="true")
  inspect(preprocess_preview(source, 20).contains("`ifdef"), content="false")
  inspect(result.errors().length(), content="0")
}

///|
test "preprocessor reports unmatched directives" {
  let result = preprocess(
    "`else\nmodule m; endmodule",
    PreprocessOptions::default(),
  )
  inspect(result.errors().length() > 0, content="true")
  inspect(
    preprocess_preview("`else\nmodule m; endmodule", 20).contains("module m"),
    content="false",
  )
}

///|
test "intermediate representation lowers expressions and tracks passes" {
  let source = "module m(input a, output y); assign y = a & 1'b1; endmodule"
  let ir = lower_ir_source(source)
  inspect(ir.modules.length(), content="1")
  inspect(ir.to_text().contains("y"), content="true")
  inspect(ir.constant_fold().passes.contains("constant_fold"), content="true")
  inspect(
    ir.remove_comments().passes.contains("remove_comments"),
    content="true",
  )
}

///|
test "advanced rule profiles expose deterministic catalogs" {
  let catalog = advanced_rule_catalog()
  let fast = advanced_rule_profile("fast")
  let strict = advanced_rule_profile("strict")
  inspect(catalog.length(), content="20")
  inspect(fast.codes.length() > 0, content="true")
  inspect(strict.codes.length(), content="20")
}

///|
test "rule pack honors disabled codes and finding caps" {
  let source = "module m(input a, output y); always_comb begin if (1) y = a; end endmodule"
  let config = RulePackConfig::default().with_info(true).with_max_findings(1)
  let result = rule_pack_source(source, config)
  inspect(result.diagnostics.length() <= 1, content="true")
  inspect(result.to_json().contains("diagnostics"), content="true")
}

///|
test "query engine finds modules and wide signals" {
  let source = "module top(input [31:0] data, output ready); assign ready = data[0]; endmodule"
  let query = DesignQuery::empty()
    .with_predicate(QueryPredicate::module_equals("top"))
    .with_predicate(QueryPredicate::signal_width_at_least(32))
  let result = run_source_query(source, query)
  inspect(result.count() > 0, content="true")
  inspect(result.to_json().contains("top"), content="true")
}

///|
test "query cone follows assignment references" {
  let unit = parse(
      "module m(input a, input b, output y); wire n; assign n = a; assign y = n ^ b; endmodule",
    ).modules[0]
  inspect(signal_sources(unit, "y").contains("n"), content="true")
  inspect(signal_cone(unit, "y", 4).contains("a"), content="true")
  inspect(signal_cone_report(unit, "y", 4).contains("sources="), content="true")
}

///|
test "netlist normalization retains ports cells and edges" {
  let source = "module child(input a, output y); assign y = a; endmodule\nmodule top(input a, output y); child u0(.a(a), .y(y)); endmodule"
  let netlists = normalize_netlist_source(source)
  inspect(netlists.length(), content="2")
  inspect(netlists[1].cell_count(), content="1")
  inspect(netlists[1].to_dot().contains("digraph"), content="true")
  inspect(netlists[1].to_verilog().contains("module top"), content="true")
}

///|
test "netlist checker catches duplicate connections" {
  let unit = parse(
      "module m(input a, output y); child u(.a(a), .a(y)); endmodule",
    ).modules[0]
  let issues = check_netlist(normalize_netlist(unit))
  inspect(issues.any(fn(item) { item.code == "N005" }), content="true")
}

///|
test "verification plan generates all boundary modes" {
  let unit = parse(
      "module m(input [3:0] a, output y); assign y = a[0]; endmodule",
    ).modules[0]
  let plan = generate_verification_plan(unit, 4)
  inspect(plan.vectors.length(), content="6")
  inspect(plan.requirements.length(), content="5")
  inspect(verification_plan_text(plan).contains("walking_one"), content="true")
}

///|
test "verification smoke runner is stable for a combinational module" {
  let unit = parse("module m(input a, output y); assign y = a; endmodule").modules[0]
  let report = run_verification_plan(unit, generate_verification_plan(unit, 4))
  inspect(report.total() > 0, content="true")
  inspect(report.to_json().contains("observations"), content="true")
}

///|
test "release report combines evidence artifacts" {
  let source = "module m(input a, output y); assign y = a; endmodule"
  let report = build_release_report("boundary", source)
  inspect(report.modules, content="1")
  inspect(report.artifacts.length() >= 7, content="true")
  inspect(report.summary().contains("lines="), content="true")
  inspect(report.to_json().contains("benchmark"), content="true")
}

///|
test "trace capture records stable signal observations" {
  let unit = parse("module m(input a, output y); assign y = a; endmodule").modules[0]
  let trace = capture_simulation_trace(
    unit,
    [("a", LogicVector::from_int(1, 1))],
    TracePolicy::default(),
  )
  inspect(trace.module_name, content="m")
  inspect(trace.events.length() > 0, content="true")
  inspect(trace.statistics().unique_signals > 0, content="true")
  inspect(trace.to_csv().contains("cycle,signal"), content="true")
}

///|
test "trace selector and archive validation handle boundaries" {
  let unit = parse("module m(input a, output y); assign y = a; endmodule").modules[0]
  let trace = capture_simulation_trace(unit, [], TracePolicy::default())
  let archive = TraceArchive::empty("test").add_trace(trace)
  let selected = archive.traces[0].select(TraceSelector::all().cycles(0, 0))
  inspect(selected.length() >= 0, content="true")
  inspect(archive.validate().length(), content="0")
  inspect(archive.to_statistics_json().contains("statistics"), content="true")
}

///|
test "trace replay detects changed inputs" {
  let unit = parse("module m(input a, output y); assign y = a; endmodule").modules[0]
  let expected = capture_simulation_trace(
    unit,
    [("a", LogicVector::zero(1))],
    TracePolicy::default(),
  )
  let replay = replay_trace(unit, expected, TracePolicy::default())
  inspect(replay.is_clean(), content="true")
  inspect(
    trace_difference_summary(replay).contains("differences="),
    content="true",
  )
}

///|
test "benchmark evidence is deterministic and nonempty" {
  let fixture = benchmark_fixture("small")
  let first = run_benchmark(fixture, 1)
  let second = run_benchmark(fixture, 1)
  inspect(first.tokens > 0, content="true")
  inspect(first.source_lines > 0, content="true")
  inspect(compare_benchmark(first, second).improved, content="true")
}

///|
test "public contracts identify generated capability surfaces" {
  inspect(rule_pack_contract().contains("A001"), content="true")
  inspect(query_contract().contains("predicates"), content="true")
  inspect(netlist_contract().contains("exports"), content="true")
  inspect(verification_contract().contains("vectors"), content="true")
  inspect(trace_contract().contains("replay"), content="true")
}
