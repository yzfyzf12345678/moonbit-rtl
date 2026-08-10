///|
fn main {
  let args = @env.args()
  let source = "module demo (input a); wire b; assign b = a; endmodule"
  let diagnostics = @rtl.check_source(source)
  if args.contains("--json") {
    println(@rtl.diagnostics_json(diagnostics))
  } else {
    println("moonbit-rtl: parsed demo module")
    if diagnostics.length() == 0 {
      println("no diagnostics")
    } else {
      println(@rtl.diagnostics_text(diagnostics))
    }
  }
}
