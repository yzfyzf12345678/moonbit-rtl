///|
/// A normalized public port contract.
pub struct PortContract {
  name : String
  direction : PortDirection?
  width : Int
  required : Bool
}

///|
/// A normalized module contract used for interface compatibility checks.
pub struct ModuleContract {
  name : String
  ports : Array[PortContract]
  parameter_names : Array[String]
}

///|
/// One contract violation with a stable code.
pub struct ContractIssue {
  code : String
  message : String
  subject : String
}

///|
/// Convert a parsed module into a release-friendly contract.
pub fn Module::contract(self : Module) -> ModuleContract {
  let ports = self.ports.map(fn(port) {
    {
      name: port.name,
      direction: port.direction,
      width: match port.width {
        Some(value) => value.bits()
        None => 1
      },
      required: port.direction == Some(Input),
    }
  })
  {
    name: self.name,
    ports,
    parameter_names: self.parameters.map(fn(parameter) { parameter.name }),
  }
}

///|
/// Return a stable contract signature.
pub fn ModuleContract::signature(self : ModuleContract) -> String {
  self.name +
  "<" +
  self.ports
  .map(fn(port) {
    let direction = match port.direction {
      Some(Input) => "i"
      Some(Output) => "o"
      Some(Inout) => "b"
      None => "?"
    }
    direction + port.name + ":" + port.width.to_string()
  })
  .join(",") +
  ">"
}

///|
/// Find a port contract by name.
pub fn ModuleContract::port(
  self : ModuleContract,
  name : String,
) -> PortContract? {
  for port in self.ports {
    if port.name == name {
      return Some(port)
    }
  }
  None
}

///|
/// Compare two module contracts.
pub fn compare_contracts(
  before : ModuleContract,
  after : ModuleContract,
) -> Array[ContractIssue] {
  let issues : Array[ContractIssue] = []
  for old_port in before.ports {
    match after.port(old_port.name) {
      None =>
        issues.push({
          code: "API001",
          message: "port removed: " + old_port.name,
          subject: old_port.name,
        })
      Some(new_port) => {
        if old_port.direction != new_port.direction {
          issues.push({
            code: "API002",
            message: "port direction changed: " + old_port.name,
            subject: old_port.name,
          })
        }
        if old_port.width != new_port.width {
          issues.push({
            code: "API003",
            message: "port width changed: " + old_port.name,
            subject: old_port.name,
          })
        }
      }
    }
  }
  for new_port in after.ports {
    if before.port(new_port.name) is None {
      issues.push({
        code: "API004",
        message: "port added: " + new_port.name,
        subject: new_port.name,
      })
    }
  }
  issues
}

///|
/// Validate every instance against its target contract.
pub fn contract_issues(design : Design) -> Array[ContractIssue] {
  let issues : Array[ContractIssue] = []
  for unit in design.modules {
    for instance in unit.instances {
      match design.find_module(instance.module_name) {
        None =>
          issues.push({
            code: "API010",
            message: "unknown instance target: " + instance.module_name,
            subject: instance.instance_name,
          })
        Some(target) => {
          let contract = target.contract()
          for connection in instance.connections {
            if connection.port != "" && contract.port(connection.port) is None {
              issues.push({
                code: "API011",
                message: "unknown instance port: " + connection.port,
                subject: instance.instance_name,
              })
            }
          }
          for port in contract.ports {
            if port.required && connection_by_port(instance, port.name) is None {
              issues.push({
                code: "API012",
                message: "required input is not connected: " + port.name,
                subject: instance.instance_name,
              })
            }
          }
        }
      }
    }
  }
  issues
}

///|
/// Render API contract issues as Markdown.
pub fn contract_issues_markdown(issues : Array[ContractIssue]) -> String {
  let mut out = "| Code | Subject | Message |\n| --- | --- | --- |\n"
  for issue in issues {
    out += "| " +
      issue.code +
      " | " +
      issue.subject +
      " | " +
      issue.message +
      " |\n"
  }
  out
}

///|
/// Render all module contracts as JSON lines.
pub fn design_contracts_json(design : Design) -> String {
  design.modules
  .map(fn(unit) {
    let contract = unit.contract()
    "{\"name\":\"" +
    contract.name +
    "\",\"signature\":\"" +
    contract.signature() +
    "\"}"
  })
  .join("\n")
}

///|
/// Turn interface contract violations into common diagnostics.
pub fn check_contracts(
  design : Design,
  config : CheckConfig,
  result : Array[Diagnostic],
) -> Unit {
  for issue in contract_issues(design) {
    add_diagnostic(
      config,
      result,
      diagnostic_for_rule(
        issue.code,
        Error,
        issue.message,
        Span::single(1, 1),
        Some(issue.subject),
        "design",
      ),
    )
  }
}
