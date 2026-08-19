///|
fn has_arg(args : Array[String], wanted : String) -> Bool {
  args.contains(wanted)
}

///|
fn value_after(args : Array[String], wanted : String) -> String? {
  for i, arg in args {
    if arg == wanted && i + 1 < args.length() {
      return Some(args[i + 1])
    }
    if arg.has_prefix(wanted + "=") {
      return Some(arg[wanted.length() + 1:].to_owned())
    }
  }
  None
}

///|
fn demo_source() -> String {
  (
    #|module demo (
    #|  input  [7:0] a,
    #|  input  [7:0] b,
    #|  output [7:0] y
    #|);
    #|  wire [7:0] sum;
    #|  assign sum = a + b;
    #|  assign y = sum;
    #|endmodule
  )
}

///|
fn read_source(args : Array[String]) -> String {
  match value_after(args, "--benchmark-fixture") {
    Some(size) => @rtl.benchmark_fixture_source(size)
    None =>
      match value_after(args, "--file") {
        Some(path) =>
          @fs.read_file_to_string(path) catch {
            error => {
              ignore(error)
              println("moonbit-rtl: cannot read " + path)
              ""
            }
          }
        None => demo_source()
      }
  }
}

///|
fn config_from_args(args : Array[String]) -> @rtl.CheckConfig {
  let mut config = @rtl.CheckConfig::default()
  if has_arg(args, "--no-info") {
    config = config.without_info()
  }
  match value_after(args, "--max-diagnostics") {
    Some(value) => {
      let mut max = 0
      for c in value.to_array() {
        if c >= '0' && c <= '9' {
          max = max * 10 + c.to_int() - '0'.to_int()
        }
      }
      if max > 0 {
        config = config.with_max_diagnostics(max)
      }
    }
    None => ()
  }
  for arg in args {
    if arg.has_prefix("--disable=") {
      let code = arg[10:].to_owned()
      config = config.without(code)
    }
  }
  config
}

///|
fn run_benchmark(source : String, rounds : Int) -> Unit {
  let count = if rounds < 1 { 1 } else { rounds }
  let started = @env.now()
  let mut token_count = 0
  let mut diagnostic_count = 0
  for _ in 0..<count {
    token_count += @rtl.lex(source).length()
    diagnostic_count += @rtl.check_source(source).length()
  }
  let elapsed = @env.now() - started
  println("benchmark.source_lines=" + source.split("\n").count().to_string())
  println("benchmark.source_bytes=" + source.length().to_string())
  println(
    "benchmark.modules=" + @rtl.parse(source).modules.length().to_string(),
  )
  println("benchmark.rounds=" + count.to_string())
  println("benchmark.tokens=" + token_count.to_string())
  println("benchmark.diagnostics=" + diagnostic_count.to_string())
  println("benchmark.elapsed_ms=" + elapsed.to_string())
  let divisor : UInt64 = if elapsed == 0 { 1 } else { elapsed }
  let rate = token_count.to_uint64() / divisor
  println("benchmark.tokens_per_ms=" + rate.to_string())
}

///|
fn print_help() -> Unit {
  println("moonbit-rtl - Verilog-2001 parser and static checker")
  println("")
  println("Usage: moon run cmd -- [--file path] [--json|--sarif|--markdown]")
  println("       moon run cmd -- --summary | --benchmark[=N]")
  println("")
  println("Options:")
  println("  --file PATH          read a Verilog source file")
  println("  --json               emit a stable JSON diagnostic array")
  println("  --sarif              emit SARIF 2.1.0 for code scanning")
  println("  --markdown           emit a Markdown diagnostic table")
  println("  --summary            print counts and rule IDs")
  println("  --tokens             print lexer tokens with source positions")
  println("  --no-info            suppress informational diagnostics")
  println("  --disable=RTLxxx     disable one rule")
  println("  --max-diagnostics N  cap emitted diagnostics")
  println("  --benchmark-fixture  use small, medium, or large fixture")
  println("  --benchmark[=N]      run a deterministic parse/check benchmark")
}

///|
fn main {
  let args = @env.args()
  if has_arg(args, "--help") || has_arg(args, "-h") {
    print_help()
    return
  }
  let source = read_source(args)
  if has_arg(args, "--tokens") {
    for token in @rtl.lex(source) {
      println(
        token.line.to_string() +
        ":" +
        token.column.to_string() +
        " " +
        token.text,
      )
    }
    return
  }
  let benchmark_value = value_after(args, "--benchmark")
  if has_arg(args, "--benchmark") || benchmark_value is Some(_) {
    let value = benchmark_value.unwrap_or("")
    let mut rounds = 0
    for c in value.to_array() {
      if c >= '0' && c <= '9' {
        rounds = rounds * 10 + c.to_int() - '0'.to_int()
      }
    }
    run_benchmark(source, if rounds < 1 { 100 } else { rounds })
    return
  }
  let config = config_from_args(args)
  let parse_items = @rtl.parse_diagnostics(source)
  let semantic_items = @rtl.check_source_with_config(source, config)
  let diagnostics : Array[@rtl.Diagnostic] = []
  for item in parse_items {
    diagnostics.push(item)
  }
  for item in semantic_items {
    diagnostics.push(item)
  }
  if has_arg(args, "--json") {
    println(@rtl.diagnostics_json(diagnostics))
  } else if has_arg(args, "--sarif") {
    println(@rtl.diagnostics_sarif(diagnostics))
  } else if has_arg(args, "--markdown") {
    println(@rtl.diagnostics_markdown(diagnostics))
  } else if has_arg(args, "--summary") {
    println(@rtl.diagnostics_summary(diagnostics))
    println("rules=" + @rtl.diagnostic_rule_ids(diagnostics).join(","))
  } else {
    println(
      "moonbit-rtl: modules=" + @rtl.parse(source).modules.length().to_string(),
    )
    if diagnostics.length() == 0 {
      println("no diagnostics")
    } else {
      println(@rtl.diagnostics_text(diagnostics))
    }
  }
}
