///|
test "parser collects module declarations" {
  inspect(lex("module adder").length(), content="2")
  inspect(
    lex("module adder").map(fn(x) { x.text }).join("|"),
    content="module|adder",
  )
  let design = parse(
    "module adder (input a, input b, output y); wire carry; assign y = a; endmodule",
  )
  inspect(design.modules.length(), content="1")
  inspect(design.modules[0].ports.length(), content="3")
  inspect(design.modules[0].signals.length(), content="1")
  inspect(design.modules[0].assignments.length(), content="1")
}

///|
test "checker reports duplicate and undriven signals" {
  let source = "module broken (input clk, output out); wire tmp; wire tmp; endmodule"
  let diagnostics = check_source(source)
  inspect(
    diagnostics.map(fn(x) { x.code }).join(","),
    content="RTL002,RTL003,RTL004,RTL004,RTL006",
  )
  inspect(diagnostics[0].code, content="RTL002")
  inspect(diagnostics[1].code, content="RTL003")
  inspect(diagnostics[2].code, content="RTL004")
}

///|
test "comments are ignored by the lexer" {
  let source = "// header\nmodule clean (input a, output y); /* net */ assign y = a; endmodule"
  let design = parse(source)
  inspect(design.modules[0].name, content="clean")
  inspect(check_source(source).map(fn(x) { x.code }).join(","), content="")
}
