///|
/// A normalized net endpoint used by exporters and graph consumers.
pub struct NetlistPort {
  name : String
  direction : String
  width : Int
  net : String
}

///|
/// A logical net with optional source and sink metadata.
pub struct NetlistNet {
  name : String
  width : Int
  drivers : Array[String]
  users : Array[String]
  is_port : Bool
}

///|
/// A technology-neutral cell representing a module instance.
pub struct NetlistCell {
  name : String
  kind : String
  ports : Array[NetlistPort]
  parameters : Array[(String, String)]
}

///|
/// A normalized module netlist suitable for graph and export stages.
pub struct NormalizedNetlist {
  name : String
  ports : Array[NetlistPort]
  nets : Array[NetlistNet]
  cells : Array[NetlistCell]
  assigns : Array[(String, String)]
}

///|
/// One netlist consistency finding.
pub struct NetlistIssue {
  code : String
  severity : Severity
  message : String
  object_name : String
}

///|
fn netlist_width(signal : Signal) -> Int {
  match signal.width {
    Some(width) => width.bits()
    None => 1
  }
}

///|
fn netlist_direction(signal : Signal) -> String {
  match signal.direction {
    Some(Input) => "input"
    Some(Output) => "output"
    Some(Inout) => "inout"
    None => "internal"
  }
}

///|
fn netlist_range(width : Int) -> String {
  if width <= 1 {
    ""
  } else {
    "[" + (width - 1).to_string() + ":0] "
  }
}

///|
fn netlist_signal(unit : Module, name : String) -> Signal? {
  for signal in unit.ports {
    if signal.name == name {
      return Some(signal)
    }
  }
  for signal in unit.signals {
    if signal.name == name {
      return Some(signal)
    }
  }
  None
}

///|
fn netlist_add_unique(values : Array[String], value : String) -> Unit {
  if !values.contains(value) {
    values.push(value)
  }
}

///|
fn netlist_expression_names(expr : Expr) -> Array[String] {
  let result : Array[String] = []
  advanced_expr_names(expr, result)
  result
}

///|
fn netlist_driver_map(unit : Module) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = Map([])
  for assignment in unit.assignments {
    let drivers = result.get(assignment.lhs).unwrap_or([])
    netlist_add_unique(drivers, "assign")
    result[assignment.lhs] = drivers
  }
  for block in unit.always_blocks {
    let assignments : Array[Assignment] = []
    advanced_statement_assignments(block.statements, assignments)
    for assignment in assignments {
      let drivers = result.get(assignment.lhs).unwrap_or([])
      netlist_add_unique(drivers, "always@" + block.span.start.line.to_string())
      result[assignment.lhs] = drivers
    }
  }
  result
}

///|
fn netlist_user_map(unit : Module) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = Map([])
  for assignment in unit.assignments {
    match assignment.rhs_expr {
      Some(expr) =>
        for name in netlist_expression_names(expr) {
          let users = result.get(name).unwrap_or([])
          netlist_add_unique(users, assignment.lhs)
          result[name] = users
        }
      None => ()
    }
  }
  for block in unit.always_blocks {
    let assignments : Array[Assignment] = []
    advanced_statement_assignments(block.statements, assignments)
    for assignment in assignments {
      match assignment.rhs_expr {
        Some(expr) =>
          for name in netlist_expression_names(expr) {
            let users = result.get(name).unwrap_or([])
            netlist_add_unique(users, assignment.lhs)
            result[name] = users
          }
        None => ()
      }
    }
  }
  result
}

///|
fn netlist_port(unit : Module, signal : Signal) -> NetlistPort {
  {
    name: signal.name,
    direction: netlist_direction(signal),
    width: netlist_width(signal),
    net: unit.name + "." + signal.name,
  }
}

///|
fn netlist_cell(unit : Module, instance : ModuleInstance) -> NetlistCell {
  let ports : Array[NetlistPort] = []
  for connection in instance.connections {
    let width = match connection.expression {
      Some(expr) => {
        let names = netlist_expression_names(expr)
        match names.get(0) {
          Some(name) =>
            match netlist_signal(unit, name) {
              Some(signal) => netlist_width(signal)
              None => 1
            }
          None => 1
        }
      }
      None => 1
    }
    let net = match connection.expression {
      Some(expr) => expr.to_text()
      None => connection.raw_expression
    }
    ports.push({ name: connection.port, direction: "connection", width, net })
  }
  {
    name: instance.instance_name,
    kind: instance.module_name,
    ports,
    parameters: instance.parameters.map(fn(item) { (item.name, item.value) }),
  }
}

///|
fn netlist_net(unit : Module, signal : Signal) -> NetlistNet {
  let drivers = netlist_driver_map(unit).get(signal.name).unwrap_or([])
  let users = netlist_user_map(unit).get(signal.name).unwrap_or([])
  {
    name: unit.name + "." + signal.name,
    width: netlist_width(signal),
    drivers,
    users,
    is_port: signal.direction is Some(_),
  }
}

///|
/// Lower one parsed module into a stable, flat netlist view.
pub fn normalize_netlist(unit : Module) -> NormalizedNetlist {
  let ports = unit.ports.map(fn(item) { netlist_port(unit, item) })
  let nets = (unit.ports + unit.signals).map(fn(item) {
    netlist_net(unit, item)
  })
  let cells = unit.instances.map(fn(item) { netlist_cell(unit, item) })
  let assigns = unit.assignments.map(fn(item) { (item.lhs, item.rhs) })
  { name: unit.name, ports, nets, cells, assigns }
}

///|
pub fn normalize_design(design : Design) -> Array[NormalizedNetlist] {
  design.modules.map(normalize_netlist)
}

///|
pub fn normalize_netlist_source(source : String) -> Array[NormalizedNetlist] {
  normalize_design(parse(source))
}

///|
pub fn NormalizedNetlist::net(
  self : NormalizedNetlist,
  name : String,
) -> NetlistNet? {
  for item in self.nets {
    if item.name == name || item.name == self.name + "." + name {
      return Some(item)
    }
  }
  None
}

///|
pub fn NormalizedNetlist::cell(
  self : NormalizedNetlist,
  name : String,
) -> NetlistCell? {
  for item in self.cells {
    if item.name == name {
      return Some(item)
    }
  }
  None
}

///|
pub fn NormalizedNetlist::signal_count(self : NormalizedNetlist) -> Int {
  self.nets.length()
}

///|
pub fn NormalizedNetlist::cell_count(self : NormalizedNetlist) -> Int {
  self.cells.length()
}

///|
pub fn NormalizedNetlist::edge_count(self : NormalizedNetlist) -> Int {
  self.nets.fold(init=0, fn(total, item) { total + item.users.length() })
}

///|
fn netlist_issue(
  code : String,
  severity : Severity,
  message : String,
  name : String,
) -> NetlistIssue {
  { code, severity, message, object_name: name }
}

///|
pub fn check_netlist(netlist : NormalizedNetlist) -> Array[NetlistIssue] {
  let result : Array[NetlistIssue] = []
  for net in netlist.nets {
    if net.width <= 0 {
      result.push(
        netlist_issue("N001", Error, "net width is not positive", net.name),
      )
    }
    if net.drivers.length() > 1 {
      result.push(
        netlist_issue(
          "N002",
          Warning,
          "net has multiple normalized drivers",
          net.name,
        ),
      )
    }
    if net.is_port && net.users.length() == 0 && net.drivers.length() == 0 {
      result.push(
        netlist_issue("N003", Info, "port net is unconnected", net.name),
      )
    }
  }
  let cell_names : Array[String] = []
  for cell in netlist.cells {
    if cell_names.contains(cell.name) {
      result.push(
        netlist_issue(
          "N004",
          Error,
          "cell instance name is duplicated",
          cell.name,
        ),
      )
    }
    cell_names.push(cell.name)
    let port_names : Array[String] = []
    for port in cell.ports {
      if port_names.contains(port.name) {
        result.push(
          netlist_issue(
            "N005",
            Error,
            "cell port is connected twice",
            cell.name + "." + port.name,
          ),
        )
      }
      port_names.push(port.name)
    }
  }
  result
}

///|
pub fn netlist_issues_markdown(items : Array[NetlistIssue]) -> String {
  items
  .map(fn(item) {
    "- [" + item.code + "] " + item.object_name + ": " + item.message
  })
  .join("\n")
}

///|
pub fn netlist_issues_json(items : Array[NetlistIssue]) -> String {
  "[" +
  items
  .map(fn(item) {
    "{\"code\":\"" +
    item.code +
    "\",\"severity\":\"" +
    severity_text(item.severity) +
    "\",\"object\":\"" +
    json_escape(item.object_name) +
    "\",\"message\":\"" +
    json_escape(item.message) +
    "\"}"
  })
  .join(",") +
  "]"
}

///|
fn netlist_port_verilog(port : NetlistPort) -> String {
  port.direction + " " + netlist_range(port.width) + port.name
}

///|
fn netlist_cell_verilog(cell : NetlistCell) -> String {
  let parameters = if cell.parameters.length() == 0 {
    ""
  } else {
    " #(" +
    cell.parameters
    .map(fn(item) { "." + item.0 + "(" + item.1 + ")" })
    .join(", ") +
    ")"
  }
  let ports = cell.ports
    .map(fn(item) { "." + item.name + "(" + item.net + ")" })
    .join(", ")
  "  " + cell.kind + parameters + " " + cell.name + " (" + ports + ");"
}

///|
/// Emit a conservative structural Verilog representation for review and tools.
pub fn NormalizedNetlist::to_verilog(self : NormalizedNetlist) -> String {
  let header = "module " +
    self.name +
    " (" +
    self.ports.map(fn(item) { item.name }).join(", ") +
    ");\n"
  let port_lines = self.ports
    .map(fn(item) { "  " + netlist_port_verilog(item) + ";" })
    .join("\n")
  let internal = self.nets
    .filter(fn(item) { !item.is_port })
    .map(fn(item) { "  wire " + netlist_range(item.width) + item.name + ";" })
    .join("\n")
  let cells = self.cells.map(netlist_cell_verilog).join("\n")
  let assigns = self.assigns
    .map(fn(item) { "  assign " + item.0 + " = " + item.1 + ";" })
    .join("\n")
  header +
  port_lines +
  "\n" +
  internal +
  "\n" +
  cells +
  "\n" +
  assigns +
  "\nendmodule\n"
}

///|
fn netlist_dot_id(value : String) -> String {
  "n_" +
  value
  .replace(old=".", new="_")
  .replace(old="[", new="_")
  .replace(old="]", new="_")
}

///|
/// Emit a graph view where nets are boxes and cells are rounded nodes.
pub fn NormalizedNetlist::to_dot(self : NormalizedNetlist) -> String {
  let lines : Array[String] = [
    "digraph \"" + self.name + "\" {",
    "  rankdir=LR;",
    "  node [fontname=\"sans\"];",
  ]
  for net in self.nets {
    lines.push(
      "  " +
      netlist_dot_id(net.name) +
      " [shape=box,label=\"" +
      net.name +
      "\\n" +
      net.width.to_string() +
      "b\"];",
    )
    for driver in net.drivers {
      lines.push("  \"" + driver + "\" -> " + netlist_dot_id(net.name) + ";")
    }
    for user in net.users {
      lines.push(netlist_dot_id(net.name) + " -> \"" + user + "\";")
    }
  }
  for cell in self.cells {
    lines.push(
      "  \"" +
      cell.name +
      "\" [shape=record,label=\"" +
      cell.kind +
      "\\n" +
      cell.name +
      "\"];",
    )
  }
  lines.push("}")
  lines.join("\n")
}

///|
pub fn NormalizedNetlist::to_json(self : NormalizedNetlist) -> String {
  let ports = self.ports
    .map(fn(item) {
      "{\"name\":\"" +
      json_escape(item.name) +
      "\",\"direction\":\"" +
      item.direction +
      "\",\"width\":" +
      item.width.to_string() +
      ",\"net\":\"" +
      json_escape(item.net) +
      "\"}"
    })
    .join(",")
  let nets = self.nets
    .map(fn(item) {
      "{\"name\":\"" +
      json_escape(item.name) +
      "\",\"width\":" +
      item.width.to_string() +
      ",\"drivers\":[" +
      item.drivers.map(fn(name) { "\"" + json_escape(name) + "\"" }).join(",") +
      "],\"users\":[" +
      item.users.map(fn(name) { "\"" + json_escape(name) + "\"" }).join(",") +
      "]}"
    })
    .join(",")
  let cells = self.cells
    .map(fn(item) {
      "{\"name\":\"" +
      json_escape(item.name) +
      "\",\"kind\":\"" +
      json_escape(item.kind) +
      "\",\"ports\":[" +
      item.ports
      .map(fn(port) {
        "{\"name\":\"" +
        json_escape(port.name) +
        "\",\"net\":\"" +
        json_escape(port.net) +
        "\"}"
      })
      .join(",") +
      "]}"
    })
    .join(",")
  "{\"name\":\"" +
  json_escape(self.name) +
  "\",\"ports\":[" +
  ports +
  "]" +
  ",\"nets\":[" +
  nets +
  "]" +
  ",\"cells\":[" +
  cells +
  "]}"
}

///|
pub fn netlist_summary(netlist : NormalizedNetlist) -> String {
  netlist.name +
  ": ports=" +
  netlist.ports.length().to_string() +
  ", nets=" +
  netlist.signal_count().to_string() +
  ", cells=" +
  netlist.cell_count().to_string() +
  ", edges=" +
  netlist.edge_count().to_string()
}

///|
pub fn netlist_contract() -> String {
  "format=normalized; exports=verilog,dot,json; checks=N001..N005; graph=driver-user"
}
