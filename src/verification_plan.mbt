///|
/// Deterministic vector generation modes used by verification planning.
pub enum VectorMode {
  ZeroVector
  OnesVector
  WalkingOneVector
  WalkingZeroVector
  AlternatingVector
  BoundaryVector
} derive(Eq)

///|
/// A reviewable verification requirement.
pub struct VerificationRequirement {
  id : String
  target : String
  description : String
  priority : Int
  covered : Bool
}

///|
/// One input vector with optional exact output expectations.
pub struct VerificationVector {
  name : String
  mode : VectorMode
  inputs : Array[(String, LogicVector)]
  expected : Array[(String, LogicVector)]
  tags : Array[String]
}

///|
/// A generated verification plan for one module.
pub struct VerificationPlan {
  module_name : String
  requirements : Array[VerificationRequirement]
  vectors : Array[VerificationVector]
  max_iterations : Int
}

///|
/// The result of running one planned vector.
pub struct VerificationObservation {
  vector_name : String
  status : String
  checked_outputs : Int
  mismatches : Array[String]
  stable : Bool
  iterations : Int
}

///|
/// A complete verification run report.
pub struct VerificationReport {
  module_name : String
  observations : Array[VerificationObservation]
  requirements : Array[VerificationRequirement]
  passed : Int
  failed : Int
  unknown : Int
}

///|
fn vector_mode_text(mode : VectorMode) -> String {
  match mode {
    ZeroVector => "zero"
    OnesVector => "ones"
    WalkingOneVector => "walking_one"
    WalkingZeroVector => "walking_zero"
    AlternatingVector => "alternating"
    BoundaryVector => "boundary"
  }
}

///|
fn verification_width(signal : Signal) -> Int {
  match signal.width {
    Some(width) => width.bits()
    None => 1
  }
}

///|
fn verification_inputs(unit : Module) -> Array[Signal] {
  unit.ports.filter(fn(signal) {
    match signal.direction {
      Some(Input) | Some(Inout) => true
      _ => false
    }
  })
}

///|
fn verification_outputs(unit : Module) -> Array[Signal] {
  unit.ports.filter(fn(signal) {
    match signal.direction {
      Some(Output) | Some(Inout) => true
      _ => false
    }
  })
}

///|
fn verification_pattern(
  mode : VectorMode,
  width : Int,
  index : Int,
) -> LogicVector {
  let safe_width = if width < 1 { 1 } else { width }
  match mode {
    ZeroVector => LogicVector::zero(safe_width)
    OnesVector => LogicVector::ones(safe_width)
    WalkingOneVector => {
      let position = if safe_width == 0 { 0 } else { index % safe_width }
      LogicVector::from_int(logic_pow2(position), safe_width)
    }
    WalkingZeroVector => {
      let position = if safe_width == 0 { 0 } else { index % safe_width }
      LogicVector::ones(safe_width).with_bit(position, LogicZero)
    }
    AlternatingVector => {
      let bits : Array[LogicBit] = []
      for bit_index in 0..<safe_width {
        bits.push(
          if (bit_index + index) % 2 == 0 {
            LogicZero
          } else {
            LogicOne
          },
        )
      }
      LogicVector::from_bits(bits)
    }
    BoundaryVector =>
      if index % 2 == 0 {
        LogicVector::zero(safe_width)
      } else {
        LogicVector::from_int(logic_pow2(safe_width) - 1, safe_width)
      }
  }
}

///|
fn verification_vector(
  unit : Module,
  mode : VectorMode,
  index : Int,
) -> VerificationVector {
  let inputs : Array[(String, LogicVector)] = []
  for signal in verification_inputs(unit) {
    inputs.push(
      (
        signal.name,
        verification_pattern(mode, verification_width(signal), index),
      ),
    )
  }
  {
    name: vector_mode_text(mode) + "_" + index.to_string(),
    mode,
    inputs,
    expected: [],
    tags: ["generated", vector_mode_text(mode)],
  }
}

///|
fn verification_modes() -> Array[VectorMode] {
  [
    ZeroVector,
    OnesVector,
    WalkingOneVector,
    WalkingZeroVector,
    AlternatingVector,
    BoundaryVector,
  ]
}

///|
pub fn VerificationPlan::empty(module_name : String) -> VerificationPlan {
  { module_name, requirements: [], vectors: [], max_iterations: 16 }
}

///|
pub fn VerificationPlan::add_requirement(
  self : VerificationPlan,
  id : String,
  target : String,
  description : String,
  priority : Int,
) -> VerificationPlan {
  let requirements = self.requirements.copy()
  requirements.push({ id, target, description, priority, covered: false })
  { ..self, requirements, }
}

///|
pub fn VerificationPlan::add_vector(
  self : VerificationPlan,
  vector : VerificationVector,
) -> VerificationPlan {
  let vectors = self.vectors.copy()
  vectors.push(vector)
  { ..self, vectors, }
}

///|
/// Build a small but broad deterministic plan for a parsed module.
pub fn generate_verification_plan(
  unit : Module,
  cycles : Int,
) -> VerificationPlan {
  let output_count = verification_outputs(unit).length()
  let plan = VerificationPlan::empty(unit.name)
    .add_requirement(
      "V001", "ports", "all input and output boundaries are exercised", 1,
    )
    .add_requirement(
      "V002", "unknowns", "four-state unknown propagation is observable", 2,
    )
    .add_requirement(
      "V003", "reset", "boundary values are accepted without instability", 1,
    )
    .add_requirement(
      "V004", "widths", "narrow and wide vectors preserve declared widths", 2,
    )
    .add_requirement(
      "V005",
      "outputs",
      "declared output count is tracked by the plan: " +
      output_count.to_string(),
      1,
    )
  let mut result = {
    ..plan,
    max_iterations: if cycles < 1 {
      1
    } else {
      cycles
    },
  }
  let mut index = 0
  for mode in verification_modes() {
    result = result.add_vector(verification_vector(unit, mode, index))
    index += 1
  }
  result
}

///|
fn verification_expected(
  result : SimulationResult,
  expected : Array[(String, LogicVector)],
) -> Array[String] {
  let mismatches : Array[String] = []
  for item in expected {
    match result.value(item.0) {
      Some(actual) =>
        if actual.case_equal(item.1) != LogicOne {
          mismatches.push(
            item.0 +
            ": expected=" +
            item.1.to_text() +
            ", actual=" +
            actual.to_text(),
          )
        }
      None => mismatches.push(item.0 + ": output is missing")
    }
  }
  mismatches
}

///|
fn verification_observe(
  unit : Module,
  vector : VerificationVector,
  iterations : Int,
) -> VerificationObservation {
  let simulation = simulate_module(unit, vector.inputs, iterations)
  let mismatches = verification_expected(simulation, vector.expected)
  let status = if mismatches.length() > 0 {
    "failed"
  } else if !simulation.stable {
    "unknown"
  } else {
    "passed"
  }
  {
    vector_name: vector.name,
    status,
    checked_outputs: vector.expected.length(),
    mismatches,
    stable: simulation.stable,
    iterations: simulation.steps.length(),
  }
}

///|
/// Run a plan against the package's four-state fixed-point simulator.
pub fn run_verification_plan(
  unit : Module,
  plan : VerificationPlan,
) -> VerificationReport {
  let observations : Array[VerificationObservation] = []
  let mut passed = 0
  let mut failed = 0
  let mut unknown = 0
  for vector in plan.vectors {
    let observation = verification_observe(unit, vector, plan.max_iterations)
    observations.push(observation)
    if observation.status == "passed" {
      passed += 1
    } else if observation.status == "failed" {
      failed += 1
    } else {
      unknown += 1
    }
  }
  {
    module_name: plan.module_name,
    observations,
    requirements: plan.requirements,
    passed,
    failed,
    unknown,
  }
}

///|
pub fn run_source_verification(
  source : String,
  module_name : String,
  cycles : Int,
) -> VerificationReport? {
  let design = parse(source)
  for unit in design.modules {
    if unit.name == module_name {
      let plan = generate_verification_plan(unit, cycles)
      return Some(run_verification_plan(unit, plan))
    }
  }
  None
}

///|
pub fn VerificationReport::total(self : VerificationReport) -> Int {
  self.passed + self.failed + self.unknown
}

///|
pub fn VerificationReport::is_healthy(self : VerificationReport) -> Bool {
  self.failed == 0 && self.unknown == 0
}

///|
pub fn VerificationReport::coverage_percent(self : VerificationReport) -> Int {
  let total = self.total()
  if total == 0 {
    0
  } else {
    self.passed * 100 / total
  }
}

///|
pub fn VerificationReport::to_json(self : VerificationReport) -> String {
  let observations = self.observations
    .map(fn(item) {
      "{\"vector\":\"" +
      json_escape(item.vector_name) +
      "\",\"status\":\"" +
      item.status +
      "\",\"checked_outputs\":" +
      item.checked_outputs.to_string() +
      ",\"stable\":" +
      (if item.stable { "true" } else { "false" }) +
      ",\"iterations\":" +
      item.iterations.to_string() +
      ",\"mismatches\":[" +
      item.mismatches
      .map(fn(value) { "\"" + json_escape(value) + "\"" })
      .join(",") +
      "]}"
    })
    .join(",")
  "{\"module\":\"" +
  json_escape(self.module_name) +
  "\",\"passed\":" +
  self.passed.to_string() +
  ",\"failed\":" +
  self.failed.to_string() +
  ",\"unknown\":" +
  self.unknown.to_string() +
  ",\"coverage_percent\":" +
  self.coverage_percent().to_string() +
  ",\"observations\":[" +
  observations +
  "]}"
}

///|
pub fn VerificationReport::to_markdown(self : VerificationReport) -> String {
  let rows = self.observations
    .map(fn(item) {
      "| " +
      item.vector_name +
      " | " +
      item.status +
      " | " +
      item.checked_outputs.to_string() +
      " | " +
      item.iterations.to_string() +
      " |"
    })
    .join("\n")
  "## Verification report: " +
  self.module_name +
  "\n\n" +
  "Passed: " +
  self.passed.to_string() +
  "  Failed: " +
  self.failed.to_string() +
  "  Unknown: " +
  self.unknown.to_string() +
  "\n\n" +
  "| Vector | Status | Outputs | Iterations |\n|---|---|---:|---:|\n" +
  rows
}

///|
pub fn verification_plan_text(plan : VerificationPlan) -> String {
  let requirements = plan.requirements
    .map(fn(item) {
      item.id +
      " [P" +
      item.priority.to_string() +
      "] " +
      item.target +
      ": " +
      item.description
    })
    .join("\n")
  let vectors = plan.vectors
    .map(fn(item) {
      item.name +
      " (" +
      vector_mode_text(item.mode) +
      ", inputs=" +
      item.inputs.length().to_string() +
      ")"
    })
    .join("\n")
  "module=" +
  plan.module_name +
  "\nrequirements:\n" +
  requirements +
  "\nvectors:\n" +
  vectors
}

///|
pub fn verification_contract() -> String {
  "vectors=modes:zero,ones,walking_one,walking_zero,alternating,boundary; runner=four_state_fixed_point; report=json,markdown"
}
