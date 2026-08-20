///|
/// Event categories retained by the deterministic simulation trace.
pub enum TraceEventKind {
  TraceInput
  TraceOutput
  TraceInternal
  TraceState
  TraceUnknown
} derive(Eq)

///|
/// One signal observation at a fixed simulation iteration.
pub struct TraceEvent {
  cycle : Int
  signal : String
  value : LogicVector
  kind : TraceEventKind
  source : String
}

///|
/// A complete trace for one module and one input vector.
pub struct SimulationTrace {
  module_name : String
  events : Array[TraceEvent]
  inputs : Array[(String, LogicVector)]
  cycles : Int
  stable : Bool
  oscillating : Bool
}

///|
/// Replay policy for comparing a trace with a new simulation.
pub struct TracePolicy {
  max_cycles : Int
  include_internal : Bool
  stop_on_stable : Bool
  unknown_is_error : Bool
  compare_inputs : Bool
}

///|
/// One mismatch between a recorded trace and a replay.
pub struct TraceDifference {
  cycle : Int
  signal : String
  expected : LogicVector?
  actual : LogicVector?
  reason : String
}

///|
/// Replay result with stable counters for CI.
pub struct TraceReplayResult {
  module_name : String
  compared_events : Int
  differences : Array[TraceDifference]
  passed : Bool
  expected_cycles : Int
  actual_cycles : Int
}

///|
/// A named trace collection used for regression suites.
pub struct TraceArchive {
  name : String
  traces : Array[SimulationTrace]
  metadata : Array[(String, String)]
}

///|
/// A bounded event selector for debugging long traces.
pub struct TraceSelector {
  signal_contains : String
  kind : TraceEventKind?
  first_cycle : Int
  last_cycle : Int
  include_unknown : Bool
}

///|
/// Stable counters used to compare trace shape across runs.
pub struct TraceStatistics {
  event_count : Int
  input_count : Int
  output_count : Int
  internal_count : Int
  unknown_count : Int
  cycle_count : Int
  unique_signals : Int
}

///|
pub fn TraceSelector::all() -> TraceSelector {
  {
    signal_contains: "",
    kind: None,
    first_cycle: 0,
    last_cycle: -1,
    include_unknown: true,
  }
}

///|
pub fn TraceSelector::signal(
  self : TraceSelector,
  text : String,
) -> TraceSelector {
  { ..self, signal_contains: text }
}

///|
pub fn TraceSelector::kind(
  self : TraceSelector,
  value : TraceEventKind,
) -> TraceSelector {
  { ..self, kind: Some(value) }
}

///|
pub fn TraceSelector::cycles(
  self : TraceSelector,
  first : Int,
  last : Int,
) -> TraceSelector {
  { ..self, first_cycle: if first < 0 { 0 } else { first }, last_cycle: last }
}

///|
fn trace_selector_accepts(selector : TraceSelector, event : TraceEvent) -> Bool {
  let cycle_ok = event.cycle >= selector.first_cycle &&
    (selector.last_cycle < 0 || event.cycle <= selector.last_cycle)
  let signal_ok = selector.signal_contains == "" ||
    event.signal.contains(selector.signal_contains)
  let kind_ok = match selector.kind {
    Some(kind) => event.kind == kind
    None => true
  }
  let unknown_ok = selector.include_unknown || event.kind != TraceUnknown
  cycle_ok && signal_ok && kind_ok && unknown_ok
}

///|
pub fn SimulationTrace::select(
  self : SimulationTrace,
  selector : TraceSelector,
) -> Array[TraceEvent] {
  self.events.filter(fn(item) { trace_selector_accepts(selector, item) })
}

///|
pub fn SimulationTrace::statistics(self : SimulationTrace) -> TraceStatistics {
  let signals : Array[String] = []
  let mut inputs = 0
  let mut outputs = 0
  let mut internal = 0
  let mut unknown = 0
  for event in self.events {
    if !signals.contains(event.signal) {
      signals.push(event.signal)
    }
    match event.kind {
      TraceInput => inputs += 1
      TraceOutput => outputs += 1
      TraceInternal | TraceState => internal += 1
      TraceUnknown => unknown += 1
    }
  }
  {
    event_count: self.events.length(),
    input_count: inputs,
    output_count: outputs,
    internal_count: internal,
    unknown_count: unknown,
    cycle_count: self.cycles,
    unique_signals: signals.length(),
  }
}

///|
pub fn SimulationTrace::signal_values(
  self : SimulationTrace,
  signal : String,
) -> Array[LogicVector] {
  self.events
  .filter(fn(item) { item.signal == signal })
  .map(fn(item) { item.value })
}

///|
pub fn SimulationTrace::last_value(
  self : SimulationTrace,
  signal : String,
) -> LogicVector? {
  self.events
  .filter(fn(item) { item.signal == signal })
  .get(self.events.filter(fn(item) { item.signal == signal }).length() - 1)
  .map(fn(item) { item.value })
}

///|
pub fn SimulationTrace::changed_signals(
  self : SimulationTrace,
) -> Array[String] {
  let result : Array[String] = []
  let previous : Array[(String, LogicVector)] = []
  for event in self.events {
    match previous.filter(fn(item) { item.0 == event.signal }).get(0) {
      Some(item) =>
        if item.1.case_equal(event.value) != LogicOne &&
          !result.contains(event.signal) {
          result.push(event.signal)
        }
      None => previous.push((event.signal, event.value))
    }
    for index, item in previous {
      if item.0 == event.signal {
        previous[index] = (event.signal, event.value)
      }
    }
  }
  result
}

///|
pub fn TraceArchive::statistics(self : TraceArchive) -> TraceStatistics {
  let mut total = {
    event_count: 0,
    input_count: 0,
    output_count: 0,
    internal_count: 0,
    unknown_count: 0,
    cycle_count: 0,
    unique_signals: 0,
  }
  let names : Array[String] = []
  for trace in self.traces {
    let stats = trace.statistics()
    total = {
      event_count: total.event_count + stats.event_count,
      input_count: total.input_count + stats.input_count,
      output_count: total.output_count + stats.output_count,
      internal_count: total.internal_count + stats.internal_count,
      unknown_count: total.unknown_count + stats.unknown_count,
      cycle_count: total.cycle_count + stats.cycle_count,
      unique_signals: 0,
    }
    for event in trace.events {
      if !names.contains(event.signal) {
        names.push(event.signal)
      }
    }
  }
  { ..total, unique_signals: names.length() }
}

///|
pub fn TraceArchive::validate(self : TraceArchive) -> Array[String] {
  let errors : Array[String] = []
  for trace in self.traces {
    if trace.module_name == "" {
      errors.push("trace has an empty module name")
    }
    if trace.cycles < 0 {
      errors.push(trace.module_name + ": negative cycle count")
    }
    let mut previous_cycle = -1
    for event in trace.events {
      if event.cycle < 0 {
        errors.push(trace.module_name + ": event has a negative cycle")
      }
      if event.cycle < previous_cycle {
        errors.push(trace.module_name + ": event cycles are not monotonic")
      }
      previous_cycle = event.cycle
    }
  }
  errors
}

///|
pub fn TraceReplayResult::difference_count(self : TraceReplayResult) -> Int {
  self.differences.length()
}

///|
pub fn TraceReplayResult::is_clean(self : TraceReplayResult) -> Bool {
  self.passed && self.difference_count() == 0
}

///|
pub fn TraceReplayResult::difference_signals(
  self : TraceReplayResult,
) -> Array[String] {
  let result : Array[String] = []
  for item in self.differences {
    if !result.contains(item.signal) {
      result.push(item.signal)
    }
  }
  result
}

///|
pub fn trace_statistics_text(stats : TraceStatistics) -> String {
  "events=" +
  stats.event_count.to_string() +
  "; inputs=" +
  stats.input_count.to_string() +
  "; outputs=" +
  stats.output_count.to_string() +
  "; internal=" +
  stats.internal_count.to_string() +
  "; unknown=" +
  stats.unknown_count.to_string() +
  "; cycles=" +
  stats.cycle_count.to_string() +
  "; unique_signals=" +
  stats.unique_signals.to_string()
}

///|
pub fn trace_statistics_json(stats : TraceStatistics) -> String {
  "{\"events\":" +
  stats.event_count.to_string() +
  ",\"inputs\":" +
  stats.input_count.to_string() +
  ",\"outputs\":" +
  stats.output_count.to_string() +
  ",\"internal\":" +
  stats.internal_count.to_string() +
  ",\"unknown\":" +
  stats.unknown_count.to_string() +
  ",\"cycles\":" +
  stats.cycle_count.to_string() +
  ",\"unique_signals\":" +
  stats.unique_signals.to_string() +
  "}"
}

///|
fn trace_kind_text(kind : TraceEventKind) -> String {
  match kind {
    TraceInput => "input"
    TraceOutput => "output"
    TraceInternal => "internal"
    TraceState => "state"
    TraceUnknown => "unknown"
  }
}

///|
fn trace_kind_catalog() -> Array[String] {
  [TraceInput, TraceOutput, TraceInternal, TraceState, TraceUnknown].map(
    trace_kind_text,
  )
}

///|
pub fn TracePolicy::default() -> TracePolicy {
  {
    max_cycles: 32,
    include_internal: true,
    stop_on_stable: true,
    unknown_is_error: false,
    compare_inputs: true,
  }
}

///|
pub fn TracePolicy::bounded(self : TracePolicy, cycles : Int) -> TracePolicy {
  { ..self, max_cycles: if cycles < 1 { 1 } else { cycles } }
}

///|
pub fn TracePolicy::strict(self : TracePolicy) -> TracePolicy {
  { ..self, unknown_is_error: true, compare_inputs: true }
}

///|
fn trace_signal_kind(
  unit : Module,
  name : String,
  source : String,
) -> TraceEventKind {
  match source {
    "input" | "port:input" => TraceInput
    "output" | "port:output" => TraceOutput
    "state" | "procedural" => TraceState
    _ =>
      match advanced_signal(unit, name) {
        Some(signal) =>
          match signal.direction {
            Some(Output) => TraceOutput
            Some(Input) => TraceInput
            _ => TraceInternal
          }
        None => TraceUnknown
      }
  }
}

///|
fn trace_event(
  unit : Module,
  cycle : Int,
  binding : SimulationBinding,
) -> TraceEvent {
  {
    cycle,
    signal: binding.name,
    value: binding.value,
    kind: trace_signal_kind(unit, binding.name, binding.source),
    source: binding.source,
  }
}

///|
fn trace_event_is_allowed(event : TraceEvent, policy : TracePolicy) -> Bool {
  if event.kind == TraceInternal && !policy.include_internal {
    false
  } else {
    true
  }
}

///|
/// Capture every committed simulator binding as an explicit trace event.
pub fn capture_simulation_trace(
  unit : Module,
  inputs : Array[(String, LogicVector)],
  policy : TracePolicy,
) -> SimulationTrace {
  let result = simulate_module(unit, inputs, policy.max_cycles)
  let events : Array[TraceEvent] = []
  for step in result.steps {
    for binding in step.values {
      let event = trace_event(unit, step.iteration, binding)
      if trace_event_is_allowed(event, policy) {
        events.push(event)
      }
    }
    if policy.stop_on_stable && step.stable {
      break
    }
  }
  {
    module_name: unit.name,
    events,
    inputs,
    cycles: result.steps.length(),
    stable: result.stable,
    oscillating: result.oscillating,
  }
}

///|
pub fn capture_source_trace(
  source : String,
  module_name : String,
  inputs : Array[(String, LogicVector)],
  policy : TracePolicy,
) -> SimulationTrace? {
  let design = parse(source)
  for unit in design.modules {
    if unit.name == module_name {
      return Some(capture_simulation_trace(unit, inputs, policy))
    }
  }
  None
}

///|
fn trace_find_event(
  events : Array[TraceEvent],
  cycle : Int,
  signal : String,
) -> TraceEvent? {
  for event in events {
    if event.cycle == cycle && event.signal == signal {
      return Some(event)
    }
  }
  None
}

///|
fn trace_input_map(inputs : Array[(String, LogicVector)]) -> Array[TraceEvent] {
  inputs.map(fn(item) {
    {
      cycle: 0,
      signal: item.0,
      value: item.1,
      kind: TraceInput,
      source: "input",
    }
  })
}

///|
fn trace_difference(
  cycle : Int,
  signal : String,
  expected : LogicVector?,
  actual : LogicVector?,
  reason : String,
) -> TraceDifference {
  { cycle, signal, expected, actual, reason }
}

///|
fn trace_values_equal(
  left : LogicVector?,
  right : LogicVector?,
  unknown_is_error : Bool,
) -> Bool {
  match (left, right) {
    (Some(a), Some(b)) =>
      if unknown_is_error && (a.has_unknown() || b.has_unknown()) {
        false
      } else {
        a.case_equal(b) == LogicOne
      }
    (None, None) => true
    _ => false
  }
}

///|
/// Compare a recorded trace with a fresh replay under an explicit policy.
pub fn replay_trace(
  unit : Module,
  expected : SimulationTrace,
  policy : TracePolicy,
) -> TraceReplayResult {
  let actual = capture_simulation_trace(unit, expected.inputs, policy)
  let differences : Array[TraceDifference] = []
  let mut compared = 0
  for event in expected.events {
    match trace_find_event(actual.events, event.cycle, event.signal) {
      Some(observed) => {
        compared += 1
        if !trace_values_equal(
            Some(event.value),
            Some(observed.value),
            policy.unknown_is_error,
          ) {
          differences.push(
            trace_difference(
              event.cycle,
              event.signal,
              Some(event.value),
              Some(observed.value),
              "value changed during replay",
            ),
          )
        }
      }
      None =>
        differences.push(
          trace_difference(
            event.cycle,
            event.signal,
            Some(event.value),
            None,
            "recorded event is missing from replay",
          ),
        )
    }
  }
  if policy.compare_inputs {
    for input in trace_input_map(expected.inputs) {
      match trace_find_event(actual.events, 0, input.signal) {
        Some(observed) =>
          if !trace_values_equal(
              Some(input.value),
              Some(observed.value),
              policy.unknown_is_error,
            ) {
            differences.push(
              trace_difference(
                0,
                input.signal,
                Some(input.value),
                Some(observed.value),
                "input differs",
              ),
            )
          }
        None =>
          differences.push(
            trace_difference(
              0,
              input.signal,
              Some(input.value),
              None,
              "input event is missing",
            ),
          )
      }
    }
  }
  {
    module_name: expected.module_name,
    compared_events: compared,
    differences,
    passed: differences.length() == 0,
    expected_cycles: expected.cycles,
    actual_cycles: actual.cycles,
  }
}

///|
pub fn replay_source_trace(
  source : String,
  expected : SimulationTrace,
  policy : TracePolicy,
) -> TraceReplayResult? {
  let design = parse(source)
  for unit in design.modules {
    if unit.name == expected.module_name {
      return Some(replay_trace(unit, expected, policy))
    }
  }
  None
}

///|
pub fn TraceArchive::empty(name : String) -> TraceArchive {
  { name, traces: [], metadata: [] }
}

///|
pub fn TraceArchive::add_trace(
  self : TraceArchive,
  trace : SimulationTrace,
) -> TraceArchive {
  let traces = self.traces.copy()
  traces.push(trace)
  { ..self, traces, }
}

///|
pub fn TraceArchive::with_metadata(
  self : TraceArchive,
  key : String,
  value : String,
) -> TraceArchive {
  let metadata = self.metadata.copy()
  metadata.push((key, value))
  { ..self, metadata, }
}

///|
pub fn TraceArchive::find_module(
  self : TraceArchive,
  module_name : String,
) -> Array[SimulationTrace] {
  self.traces.filter(fn(item) { item.module_name == module_name })
}

///|
pub fn TraceArchive::event_count(self : TraceArchive) -> Int {
  self.traces.fold(init=0, fn(total, trace) { total + trace.events.length() })
}

///|
pub fn TraceArchive::cycle_count(self : TraceArchive) -> Int {
  self.traces.fold(init=0, fn(total, trace) { total + trace.cycles })
}

///|
pub fn TraceArchive::is_stable(self : TraceArchive) -> Bool {
  self.traces.all(fn(item) { item.stable && !item.oscillating })
}

///|
pub fn TraceArchive::merge(
  self : TraceArchive,
  other : TraceArchive,
) -> TraceArchive {
  let traces = self.traces.copy()
  for trace in other.traces {
    traces.push(trace)
  }
  let metadata = self.metadata.copy()
  for item in other.metadata {
    metadata.push(item)
  }
  { ..self, traces, metadata }
}

///|
fn trace_value_json(value : LogicVector) -> String {
  value.to_json()
}

///|
fn trace_event_json(event : TraceEvent) -> String {
  "{\"cycle\":" +
  event.cycle.to_string() +
  ",\"signal\":\"" +
  json_escape(event.signal) +
  "\",\"kind\":\"" +
  trace_kind_text(event.kind) +
  "\",\"source\":\"" +
  json_escape(event.source) +
  "\",\"value\":" +
  trace_value_json(event.value) +
  "}"
}

///|
pub fn SimulationTrace::to_json(self : SimulationTrace) -> String {
  "{\"module\":\"" +
  json_escape(self.module_name) +
  "\",\"cycles\":" +
  self.cycles.to_string() +
  ",\"stable\":" +
  (if self.stable { "true" } else { "false" }) +
  ",\"oscillating\":" +
  (if self.oscillating { "true" } else { "false" }) +
  ",\"inputs\":[" +
  self.inputs
  .map(fn(item) {
    "{\"name\":\"" +
    json_escape(item.0) +
    "\",\"value\":" +
    item.1.to_json() +
    "}"
  })
  .join(",") +
  "]" +
  ",\"events\":[" +
  self.events.map(trace_event_json).join(",") +
  "]}"
}

///|
pub fn SimulationTrace::to_text(self : SimulationTrace) -> String {
  let rows = self.events
    .map(fn(item) {
      item.cycle.to_string() +
      "\t" +
      trace_kind_text(item.kind) +
      "\t" +
      item.signal +
      "\t" +
      item.value.to_text()
    })
    .join("\n")
  "module=" +
  self.module_name +
  " cycles=" +
  self.cycles.to_string() +
  "\n" +
  rows
}

///|
pub fn SimulationTrace::to_vcd_like(self : SimulationTrace) -> String {
  let output : Array[String] = [
    "$date generated by moonbit-rtl $end", "$version deterministic trace $end", "$timescale 1ns $end",
  ]
  let names : Array[String] = []
  for event in self.events {
    if !names.contains(event.signal) {
      names.push(event.signal)
    }
  }
  let mut symbol = 33
  for name in names {
    output.push("$var wire 1 " + symbol.to_string() + " " + name + " $end")
    symbol += 1
  }
  output.push("$enddefinitions $end")
  let mut current_cycle = -1
  for event in self.events {
    if event.cycle != current_cycle {
      current_cycle = event.cycle
      output.push("#" + current_cycle.to_string())
    }
    output.push("b" + event.value.to_binary() + " " + event.signal)
  }
  output.join("\n")
}

///|
fn trace_difference_json(item : TraceDifference) -> String {
  "{\"cycle\":" +
  item.cycle.to_string() +
  ",\"signal\":\"" +
  json_escape(item.signal) +
  "\",\"expected\":" +
  item.expected.map(trace_value_json).unwrap_or("null") +
  ",\"actual\":" +
  item.actual.map(trace_value_json).unwrap_or("null") +
  ",\"reason\":\"" +
  json_escape(item.reason) +
  "\"}"
}

///|
pub fn TraceReplayResult::to_json(self : TraceReplayResult) -> String {
  "{\"module\":\"" +
  json_escape(self.module_name) +
  "\",\"passed\":" +
  (if self.passed { "true" } else { "false" }) +
  ",\"compared_events\":" +
  self.compared_events.to_string() +
  ",\"expected_cycles\":" +
  self.expected_cycles.to_string() +
  ",\"actual_cycles\":" +
  self.actual_cycles.to_string() +
  ",\"differences\":[" +
  self.differences.map(trace_difference_json).join(",") +
  "]}"
}

///|
pub fn TraceReplayResult::to_markdown(self : TraceReplayResult) -> String {
  let rows = self.differences
    .map(fn(item) {
      "| " +
      item.cycle.to_string() +
      " | " +
      item.signal +
      " | " +
      item.reason +
      " |"
    })
    .join("\n")
  "## Trace replay: " +
  self.module_name +
  "\n\n" +
  "Status: **" +
  (if self.passed { "PASS" } else { "FAIL" }) +
  "**\n\n" +
  "Compared events: " +
  self.compared_events.to_string() +
  "; expected cycles: " +
  self.expected_cycles.to_string() +
  "; actual cycles: " +
  self.actual_cycles.to_string() +
  "\n\n" +
  "| Cycle | Signal | Reason |\n|---:|---|---|\n" +
  rows
}

///|
pub fn TraceArchive::to_json(self : TraceArchive) -> String {
  "{\"name\":\"" +
  json_escape(self.name) +
  "\",\"metadata\":[" +
  self.metadata
  .map(fn(item) {
    "{\"key\":\"" +
    json_escape(item.0) +
    "\",\"value\":\"" +
    json_escape(item.1) +
    "\"}"
  })
  .join(",") +
  "]" +
  ",\"trace_count\":" +
  self.traces.length().to_string() +
  ",\"event_count\":" +
  self.event_count().to_string() +
  ",\"stable\":" +
  (if self.is_stable() { "true" } else { "false" }) +
  ",\"traces\":[" +
  self.traces.map(SimulationTrace::to_json).join(",") +
  "]}"
}

///|
pub fn TraceArchive::to_markdown(self : TraceArchive) -> String {
  let rows = self.traces
    .map(fn(item) {
      "| " +
      item.module_name +
      " | " +
      item.cycles.to_string() +
      " | " +
      item.events.length().to_string() +
      " | " +
      (if item.stable { "stable" } else { "unstable" }) +
      " |"
    })
    .join("\n")
  "## Trace archive: " +
  self.name +
  "\n\n" +
  "Traces: " +
  self.traces.length().to_string() +
  "; events: " +
  self.event_count().to_string() +
  "\n\n" +
  "| Module | Cycles | Events | Status |\n|---|---:|---:|---|\n" +
  rows
}

///|
fn trace_inputs_equal(
  left : Array[(String, LogicVector)],
  right : Array[(String, LogicVector)],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for item in left {
    match right.filter(fn(other) { other.0 == item.0 }).get(0) {
      Some(other) => if other.1.case_equal(item.1) != LogicOne { return false }
      None => return false
    }
  }
  true
}

///|
pub fn trace_regression_summary(
  expected : TraceArchive,
  actual : TraceArchive,
  policy : TracePolicy,
) -> String {
  let modules : Array[String] = []
  let failures : Array[String] = []
  for trace in expected.traces {
    if !modules.contains(trace.module_name) {
      modules.push(trace.module_name)
    }
    match
      actual.traces
      .filter(fn(item) {
        item.module_name == trace.module_name &&
        trace_inputs_equal(item.inputs, trace.inputs)
      })
      .get(0) {
      Some(observed) =>
        if !trace_values_equal(
            Some(LogicVector::from_int(trace.cycles, 32)),
            Some(LogicVector::from_int(observed.cycles, 32)),
            policy.unknown_is_error,
          ) {
          failures.push(trace.module_name + ": cycle count changed")
        }
      None => failures.push(trace.module_name + ": trace missing")
    }
  }
  "modules=" +
  modules.length().to_string() +
  "; failures=" +
  failures.length().to_string() +
  "; details=" +
  failures.join(",")
}

///|
pub fn trace_contract() -> String {
  "capture=simulation-steps; kinds=" +
  trace_kind_catalog().join(",") +
  "; replay=four-state-case-equality; archive=json,markdown; export=vcd-like; regression=cycle-and-event-diff"
}

///|
pub fn SimulationTrace::first_event(self : SimulationTrace) -> TraceEvent? {
  self.events.get(0)
}

///|
pub fn SimulationTrace::event_at(
  self : SimulationTrace,
  cycle : Int,
  signal : String,
) -> TraceEvent? {
  trace_find_event(self.events, cycle, signal)
}

///|
pub fn SimulationTrace::events_of_kind(
  self : SimulationTrace,
  kind : TraceEventKind,
) -> Array[TraceEvent] {
  self.events.filter(fn(item) { item.kind == kind })
}

///|
pub fn SimulationTrace::has_unknown(self : SimulationTrace) -> Bool {
  self.events.any(fn(item) {
    item.kind == TraceUnknown || item.value.has_unknown()
  })
}

///|
pub fn SimulationTrace::cycle_events(
  self : SimulationTrace,
  cycle : Int,
) -> Array[TraceEvent] {
  self.events.filter(fn(item) { item.cycle == cycle })
}

///|
pub fn SimulationTrace::signal_activity(self : SimulationTrace) -> String {
  self.changed_signals().join(",")
}

///|
pub fn SimulationTrace::to_csv(self : SimulationTrace) -> String {
  let rows = self.events
    .map(fn(item) {
      item.cycle.to_string() +
      "," +
      item.signal +
      "," +
      trace_kind_text(item.kind) +
      "," +
      item.value.to_text()
    })
    .join("\n")
  "cycle,signal,kind,value\n" + rows
}

///|
pub fn TraceArchive::module_names(self : TraceArchive) -> Array[String] {
  let result : Array[String] = []
  for trace in self.traces {
    if !result.contains(trace.module_name) {
      result.push(trace.module_name)
    }
  }
  result
}

///|
pub fn TraceArchive::unknown_trace_count(self : TraceArchive) -> Int {
  self.traces.fold(init=0, fn(total, trace) {
    if trace.has_unknown() {
      total + 1
    } else {
      total
    }
  })
}

///|
pub fn TraceArchive::event_rows(
  self : TraceArchive,
  selector : TraceSelector,
) -> Array[String] {
  let rows : Array[String] = []
  for trace in self.traces {
    for event in trace.select(selector) {
      rows.push(
        trace.module_name +
        "," +
        event.cycle.to_string() +
        "," +
        event.signal +
        "," +
        event.value.to_text(),
      )
    }
  }
  rows
}

///|
pub fn trace_archive_summary(archive : TraceArchive) -> String {
  let stats = archive.statistics()
  "name=" +
  archive.name +
  "; traces=" +
  archive.traces.length().to_string() +
  "; modules=" +
  archive.module_names().length().to_string() +
  "; " +
  trace_statistics_text(stats) +
  "; invalid=" +
  archive.validate().length().to_string()
}

///|
pub fn trace_replay_contract(policy : TracePolicy) -> String {
  "max_cycles=" +
  policy.max_cycles.to_string() +
  "; include_internal=" +
  (if policy.include_internal { "true" } else { "false" }) +
  "; stop_on_stable=" +
  (if policy.stop_on_stable { "true" } else { "false" }) +
  "; unknown_is_error=" +
  (if policy.unknown_is_error { "true" } else { "false" })
}

///|
pub fn TraceArchive::to_csv(
  self : TraceArchive,
  selector : TraceSelector,
) -> String {
  "module,cycle,signal,value\n" + self.event_rows(selector).join("\n")
}

///|
pub fn TraceArchive::to_statistics_json(self : TraceArchive) -> String {
  "{\"archive\":\"" +
  json_escape(self.name) +
  "\",\"trace_count\":" +
  self.traces.length().to_string() +
  ",\"modules\":[" +
  self
  .module_names()
  .map(fn(item) { "\"" + json_escape(item) + "\"" })
  .join(",") +
  "]" +
  ",\"statistics\":" +
  trace_statistics_json(self.statistics()) +
  ",\"invalid\":[" +
  self.validate().map(fn(item) { "\"" + json_escape(item) + "\"" }).join(",") +
  "]}"
}

///|
pub fn trace_difference_summary(result : TraceReplayResult) -> String {
  "module=" +
  result.module_name +
  "; passed=" +
  (if result.passed { "true" } else { "false" }) +
  "; differences=" +
  result.difference_count().to_string() +
  "; signals=" +
  result.difference_signals().join(",")
}

///|
pub fn trace_event_text(event : TraceEvent) -> String {
  "cycle=" +
  event.cycle.to_string() +
  "; kind=" +
  trace_kind_text(event.kind) +
  "; signal=" +
  event.signal +
  "; value=" +
  event.value.to_text() +
  "; source=" +
  event.source
}

///|
pub fn TraceSelector::without_unknown(self : TraceSelector) -> TraceSelector {
  { ..self, include_unknown: false }
}

///|
pub fn TraceSelector::from_kind_text(text : String) -> TraceSelector {
  let selector = TraceSelector::all()
  match text.trim().to_lower() {
    "input" => selector.kind(TraceInput)
    "output" => selector.kind(TraceOutput)
    "internal" => selector.kind(TraceInternal)
    "state" => selector.kind(TraceState)
    "unknown" => selector.kind(TraceUnknown)
    _ => selector
  }
}

///|
pub fn trace_archive_is_compatible(
  left : TraceArchive,
  right : TraceArchive,
) -> Bool {
  let left_names = left.module_names()
  let right_names = right.module_names()
  left_names.length() == right_names.length() &&
  left_names.all(fn(item) { right_names.contains(item) })
}

///|
pub fn trace_archive_difference(
  left : TraceArchive,
  right : TraceArchive,
) -> Array[String] {
  let result : Array[String] = []
  for name in left.module_names() {
    if !right.module_names().contains(name) {
      result.push("missing:" + name)
    }
  }
  for name in right.module_names() {
    if !left.module_names().contains(name) {
      result.push("added:" + name)
    }
  }
  result
}

///|
pub fn trace_event_count_for_signal(
  trace : SimulationTrace,
  signal : String,
) -> Int {
  trace.events.fold(init=0, fn(total, event) {
    if event.signal == signal {
      total + 1
    } else {
      total
    }
  })
}

///|
pub fn trace_cycle_span(trace : SimulationTrace) -> (Int, Int) {
  match trace.events.get(0) {
    Some(first) =>
      match trace.events.get(trace.events.length() - 1) {
        Some(last) => (first.cycle, last.cycle)
        None => (first.cycle, first.cycle)
      }
    None => (0, 0)
  }
}
