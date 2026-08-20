///|
/// A zero-based LSP document position.
pub struct LspPosition {
  line : Int
  character : Int
}

///|
/// A half-open LSP range.
pub struct LspRange {
  start : LspPosition
  end : LspPosition
}

///|
/// A document location used by definitions and references.
pub struct LspLocation {
  uri : String
  range : LspRange
}

///|
/// LSP severity values use the protocol's 1-based numbering.
pub enum LspSeverity {
  LspError
  LspWarning
  LspInformation
} derive(Eq)

///|
/// A protocol diagnostic mapped from the RTL rule engine.
pub struct LspDiagnostic {
  range : LspRange
  severity : LspSeverity
  code : String
  message : String
  source : String
}

///|
/// A document symbol exposed to an editor outline.
pub enum LspSymbolKind {
  LspModule
  LspPort
  LspSignal
  LspInstance
  LspAssignment
} derive(Eq)

///|
pub struct LspSymbol {
  name : String
  detail : String
  kind : LspSymbolKind
  range : LspRange
  selection_range : LspRange
  children : Array[LspSymbol]
}

///|
/// A versioned in-memory source document.
pub struct LspDocument {
  uri : String
  version : Int
  source : String
  design : Design
  diagnostics : Array[LspDiagnostic]
}

///|
pub struct LspWorkspaceEdit {
  uri : String
  range : LspRange
  replacement : String
}

///|
fn lsp_position(line : Int, column : Int) -> LspPosition {
  {
    line: if line < 1 {
      0
    } else {
      line - 1
    },
    character: if column < 1 {
      0
    } else {
      column - 1
    },
  }
}

///|
fn lsp_range(
  line : Int,
  column : Int,
  end_line : Int,
  end_column : Int,
) -> LspRange {
  { start: lsp_position(line, column), end: lsp_position(end_line, end_column) }
}

///|
fn lsp_severity(severity : Severity) -> LspSeverity {
  match severity {
    Error => LspError
    Warning => LspWarning
    Info => LspInformation
  }
}

///|
fn lsp_severity_number(severity : LspSeverity) -> Int {
  match severity {
    LspError => 1
    LspWarning => 2
    LspInformation => 3
  }
}

///|
fn lsp_symbol_kind_text(kind : LspSymbolKind) -> String {
  match kind {
    LspModule => "module"
    LspPort => "port"
    LspSignal => "signal"
    LspInstance => "instance"
    LspAssignment => "assignment"
  }
}

///|
pub fn LspLocation::new(uri : String, range : LspRange) -> LspLocation {
  { uri, range }
}

///|
pub fn LspWorkspaceEdit::new(
  uri : String,
  range : LspRange,
  replacement : String,
) -> LspWorkspaceEdit {
  { uri, range, replacement }
}

///|
fn lsp_symbol_kind_number(kind : LspSymbolKind) -> Int {
  match kind {
    LspModule => 2
    LspPort => 13
    LspSignal => 8
    LspInstance => 7
    LspAssignment => 12
  }
}

///|
fn lsp_position_json(position : LspPosition) -> String {
  "{\"line\":" +
  position.line.to_string() +
  ",\"character\":" +
  position.character.to_string() +
  "}"
}

///|
fn lsp_range_json(range : LspRange) -> String {
  "{\"start\":" +
  lsp_position_json(range.start) +
  ",\"end\":" +
  lsp_position_json(range.end) +
  "}"
}

///|
fn lsp_range_for_span(span : Span) -> LspRange {
  lsp_range(span.start.line, span.start.column, span.end.line, span.end.column)
}

///|
fn lsp_diagnostic_json(item : LspDiagnostic) -> String {
  "{\"range\":" +
  lsp_range_json(item.range) +
  ",\"severity\":" +
  lsp_severity_number(item.severity).to_string() +
  ",\"code\":\"" +
  json_escape(item.code) +
  "\",\"source\":\"" +
  json_escape(item.source) +
  "\",\"message\":\"" +
  json_escape(item.message) +
  "\"}"
}

///|
fn lsp_symbol_json(symbol : LspSymbol) -> String {
  "{\"name\":\"" +
  json_escape(symbol.name) +
  "\",\"detail\":\"" +
  json_escape(symbol.detail) +
  "\",\"kind\":" +
  lsp_symbol_kind_number(symbol.kind).to_string() +
  ",\"range\":" +
  lsp_range_json(symbol.range) +
  ",\"selectionRange\":" +
  lsp_range_json(symbol.selection_range) +
  ",\"children\":[" +
  symbol.children.map(lsp_symbol_json).join(",") +
  "]}"
}

///|
fn lsp_symbol_for_signal(signal : Signal) -> LspSymbol {
  let kind = match signal.direction {
    Some(_) => LspPort
    None => LspSignal
  }
  let detail = match signal.width {
    Some(width) => "width=" + width.bits().to_string()
    None => "scalar"
  }
  {
    name: signal.name,
    detail,
    kind,
    range: lsp_range_for_span(signal.span),
    selection_range: lsp_range_for_span(signal.span),
    children: [],
  }
}

///|
fn lsp_symbol_for_assignment(assignment : Assignment) -> LspSymbol {
  {
    name: assignment.lhs,
    detail: assignment.operator + " " + assignment.rhs,
    kind: LspAssignment,
    range: lsp_range_for_span(assignment.span),
    selection_range: lsp_range_for_span(assignment.span),
    children: [],
  }
}

///|
fn lsp_symbol_for_instance(instance : ModuleInstance) -> LspSymbol {
  {
    name: instance.instance_name,
    detail: instance.module_name,
    kind: LspInstance,
    range: lsp_range_for_span(instance.span),
    selection_range: lsp_range_for_span(instance.span),
    children: [],
  }
}

///|
fn lsp_symbol_for_module(unit : Module) -> LspSymbol {
  let children : Array[LspSymbol] = []
  for signal in unit.ports {
    children.push(lsp_symbol_for_signal(signal))
  }
  for signal in unit.signals {
    children.push(lsp_symbol_for_signal(signal))
  }
  for assignment in unit.assignments {
    children.push(lsp_symbol_for_assignment(assignment))
  }
  for instance in unit.instances {
    children.push(lsp_symbol_for_instance(instance))
  }
  {
    name: unit.name,
    detail: lsp_symbol_kind_text(LspModule),
    kind: LspModule,
    range: lsp_range_for_span(unit.span),
    selection_range: lsp_range_for_span(unit.span),
    children,
  }
}

///|
fn lsp_convert_diagnostics(items : Array[Diagnostic]) -> Array[LspDiagnostic] {
  items.map(fn(item) {
    {
      range: lsp_range(item.line, item.column, item.end_line, item.end_column),
      severity: lsp_severity(item.severity),
      code: item.code,
      message: item.message,
      source: "moonbit-rtl",
    }
  })
}

///|
/// Open or replace an in-memory document and compute diagnostics immediately.
pub fn LspDocument::open(
  uri : String,
  version : Int,
  source : String,
) -> LspDocument {
  let design = parse(source)
  {
    uri,
    version,
    source,
    design,
    diagnostics: lsp_convert_diagnostics(check_source(source)),
  }
}

///|
pub fn LspDocument::refresh(
  self : LspDocument,
  source : String,
  version : Int,
) -> LspDocument {
  LspDocument::open(self.uri, version, source)
}

///|
pub fn LspDocument::diagnostic_json(self : LspDocument) -> String {
  "[" + self.diagnostics.map(lsp_diagnostic_json).join(",") + "]"
}

///|
pub fn LspDocument::symbols(self : LspDocument) -> Array[LspSymbol] {
  self.design.modules.map(lsp_symbol_for_module)
}

///|
pub fn LspDocument::symbols_json(self : LspDocument) -> String {
  "[" + self.symbols().map(lsp_symbol_json).join(",") + "]"
}

///|
fn lsp_token_name(document : LspDocument, position : LspPosition) -> String? {
  token_at(document.source, position.line + 1, position.character + 1).map(fn(
    item,
  ) {
    item.text
  })
}

///|
fn lsp_find_signal(document : LspDocument, name : String) -> (Module, Signal)? {
  for unit in document.design.modules {
    for signal in unit.ports {
      if signal.name == name {
        return Some((unit, signal))
      }
    }
    for signal in unit.signals {
      if signal.name == name {
        return Some((unit, signal))
      }
    }
  }
  None
}

///|
/// Return a Markdown hover payload for the token at a document position.
pub fn lsp_hover(document : LspDocument, position : LspPosition) -> String? {
  match lsp_token_name(document, position) {
    Some(name) =>
      match lsp_find_signal(document, name) {
        Some((unit, signal)) =>
          Some(
            "```verilog\n" +
            (match signal.direction {
              Some(Input) => "input "
              Some(Output) => "output "
              Some(Inout) => "inout "
              None => "signal "
            }) +
            name +
            "\n```\n\nmodule: `" +
            unit.name +
            "`",
          )
        None =>
          match
            document.design.modules
            .filter(fn(item) { item.name == name })
            .get(0) {
            Some(unit) =>
              Some(
                "```verilog\nmodule " +
                unit.name +
                "\n```\n\nports: " +
                unit.ports.length().to_string(),
              )
            None => None
          }
      }
    None => None
  }
}

///|
pub fn lsp_hover_json(document : LspDocument, position : LspPosition) -> String {
  match lsp_hover(document, position) {
    Some(value) =>
      "{\"contents\":{\"kind\":\"markdown\",\"value\":\"" +
      json_escape(value) +
      "\"}}"
    None => "null"
  }
}

///|
pub fn lsp_document_symbols(document : LspDocument) -> String {
  document.symbols_json()
}

///|
fn lsp_all_names(document : LspDocument) -> Array[String] {
  let result : Array[String] = []
  for unit in document.design.modules {
    if !result.contains(unit.name) {
      result.push(unit.name)
    }
    for signal in unit.ports + unit.signals {
      if !result.contains(signal.name) {
        result.push(signal.name)
      }
    }
  }
  result
}

///|
pub fn lsp_completion(document : LspDocument, prefix : String) -> String {
  let items = lsp_all_names(document)
    .filter(fn(item) { item.has_prefix(prefix) })
    .map(fn(item) {
      "{\"label\":\"" +
      json_escape(item) +
      "\",\"kind\":6,\"detail\":\"RTL symbol\"}"
    })
    .join(",")
  "{\"isIncomplete\":false,\"items\":[" + items + "]}"
}

///|
pub fn lsp_definition(document : LspDocument, name : String) -> String {
  match lsp_find_signal(document, name) {
    Some((_, signal)) =>
      "[{\"uri\":\"" +
      json_escape(document.uri) +
      "\",\"range\":" +
      lsp_range_json(lsp_range_for_span(signal.span)) +
      "}]"
    None => "[]"
  }
}

///|
pub fn lsp_references(document : LspDocument, name : String) -> String {
  let locations : Array[String] = []
  for token in lex(document.source) {
    if token.text == name {
      let range = lsp_range(
        token.line,
        token.column,
        token.line,
        token.column + token.end_offset - token.offset,
      )
      locations.push(
        "{\"uri\":\"" +
        json_escape(document.uri) +
        "\",\"range\":" +
        lsp_range_json(range) +
        "}",
      )
    }
  }
  "[" + locations.join(",") + "]"
}

///|
pub fn lsp_code_actions(document : LspDocument) -> String {
  let plan = suggest_fixes(document.source, check_source(document.source))
  "[" +
  plan.suggestions
  .map(fn(item) {
    "{\"title\":\"" +
    json_escape(item.message) +
    "\",\"kind\":\"quickfix\",\"isPreferred\":" +
    (if item.safe { "true" } else { "false" }) +
    "}"
  })
  .join(",") +
  "]"
}

///|
pub fn lsp_apply_change(
  document : LspDocument,
  edit : LspWorkspaceEdit,
) -> LspDocument {
  let start = coordinate(
      document.source,
      edit.range.start.line + 1,
      edit.range.start.character + 1,
    ).offset
  let finish = coordinate(
      document.source,
      edit.range.end.line + 1,
      edit.range.end.character + 1,
    ).offset
  let source = if start <= finish &&
    start >= 0 &&
    finish <= document.source.length() {
    document.source[:start].to_owned() +
    edit.replacement +
    document.source[finish:].to_owned()
  } else {
    document.source
  }
  document.refresh(source, document.version + 1)
}

///|
pub fn lsp_jsonrpc_response(id : String, result : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  json_escape(id) +
  "\",\"result\":" +
  result +
  "}"
}

///|
pub fn lsp_jsonrpc_error(id : String, code : Int, message : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  json_escape(id) +
  "\",\"error\":{\"code\":" +
  code.to_string() +
  ",\"message\":\"" +
  json_escape(message) +
  "\"}}"
}

///|
pub fn lsp_initialize_result(server_name : String, version : String) -> String {
  "{\"capabilities\":{\"textDocumentSync\":1,\"hoverProvider\":true,\"definitionProvider\":true,\"referencesProvider\":true,\"documentSymbolProvider\":true,\"completionProvider\":{\"triggerCharacters\":[\".\",\"_\"]},\"codeActionProvider\":true},\"serverInfo\":{\"name\":\"" +
  json_escape(server_name) +
  "\",\"version\":\"" +
  json_escape(version) +
  "\"}}"
}

///|
pub fn lsp_publish_diagnostics(document : LspDocument) -> String {
  "{\"uri\":\"" +
  json_escape(document.uri) +
  "\",\"version\":" +
  document.version.to_string() +
  ",\"diagnostics\":" +
  document.diagnostic_json() +
  "}"
}

///|
pub fn lsp_content_length(message : String) -> Int {
  message.length()
}

///|
pub fn lsp_contract() -> String {
  "protocol=jsonrpc2; documents=in_memory_versioned; features=diagnostics,hover,definition,references,symbols,completion,code_actions"
}
