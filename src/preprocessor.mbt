///|
/// A source-level macro used by the Verilog preprocessor.
pub struct MacroDefinition {
  name : String
  parameters : Array[String]
  body : String
  defined_line : Int
}

///|
/// A virtual include supplied by an editor, build system, or test harness.
pub struct PreprocessInclude {
  path : String
  source : String
}

///|
/// A preprocessor diagnostic that keeps the original line location.
pub struct PreprocessMessage {
  code : String
  message : String
  line : Int
  column : Int
  is_error : Bool
}

///|
/// A mapping from an emitted line back to the source file and line.
pub struct PreprocessOrigin {
  generated_line : Int
  source_path : String
  source_line : Int
}

///|
/// Options for deterministic, in-memory preprocessing.
pub struct PreprocessOptions {
  defines : Array[String]
  includes : Array[PreprocessInclude]
  include_paths : Array[String]
  preserve_directives : Bool
  emit_line_markers : Bool
  max_expansions : Int
  max_include_depth : Int
}

///|
/// The complete output of preprocessing.
pub struct PreprocessResult {
  source : String
  macros : Array[MacroDefinition]
  messages : Array[PreprocessMessage]
  origins : Array[PreprocessOrigin]
  included_paths : Array[String]
  emitted_lines : Int
  skipped_lines : Int
  expansion_count : Int
}

///|
priv struct PreprocessState {
  macros : Array[MacroDefinition]
  messages : Array[PreprocessMessage]
  origins : Array[PreprocessOrigin]
  included_paths : Array[String]
  output_lines : Array[String]
  output_origins : Array[PreprocessOrigin]
  active_stack : Array[Bool]
  branch_stack : Array[Bool]
  include_stack : Array[String]
  mut expansion_count : Int
  mut skipped_lines : Int
}

///|
fn preprocessor_word_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '$'
}

///|
fn preprocessor_is_active(state : PreprocessState) -> Bool {
  for active in state.active_stack.rev() {
    if !active {
      return false
    }
  }
  true
}

///|
fn preprocessor_parent_active(state : PreprocessState) -> Bool {
  if state.active_stack.length() <= 1 {
    return true
  }
  for i in 0..<(state.active_stack.length() - 1) {
    if !state.active_stack[i] {
      return false
    }
  }
  true
}

///|
fn preprocessor_find_macro(
  macros : Array[MacroDefinition],
  name : String,
) -> MacroDefinition? {
  for item in macros.rev() {
    if item.name == name {
      return Some(item)
    }
  }
  None
}

///|
fn preprocessor_define_names(options : PreprocessOptions) -> Array[String] {
  options.defines.map(fn(item) {
    let trimmed = item.trim().to_owned()
    match trimmed.split_once("=") {
      Some((name, _)) => name.trim().to_owned()
      None => trimmed
    }
  })
}

///|
/// Create conservative defaults suitable for CI and editor integrations.
pub fn PreprocessOptions::default() -> PreprocessOptions {
  {
    defines: [],
    includes: [],
    include_paths: [],
    preserve_directives: false,
    emit_line_markers: false,
    max_expansions: 10000,
    max_include_depth: 32,
  }
}

///|
pub fn PreprocessOptions::with_define(
  self : PreprocessOptions,
  definition : String,
) -> PreprocessOptions {
  let defines = self.defines.copy()
  defines.push(definition)
  { ..self, defines, }
}

///|
pub fn PreprocessOptions::with_include(
  self : PreprocessOptions,
  path : String,
  source : String,
) -> PreprocessOptions {
  let includes = self.includes.copy()
  includes.push({ path, source })
  { ..self, includes, }
}

///|
pub fn PreprocessOptions::with_include_path(
  self : PreprocessOptions,
  path : String,
) -> PreprocessOptions {
  let include_paths = self.include_paths.copy()
  include_paths.push(path)
  { ..self, include_paths, }
}

///|
pub fn PreprocessOptions::with_directive_markers(
  self : PreprocessOptions,
  preserve : Bool,
  emit_line_markers : Bool,
) -> PreprocessOptions {
  { ..self, preserve_directives: preserve, emit_line_markers }
}

///|
pub fn PreprocessOptions::with_limits(
  self : PreprocessOptions,
  max_expansions : Int,
  max_include_depth : Int,
) -> PreprocessOptions {
  {
    ..self,
    max_expansions: if max_expansions < 1 {
      1
    } else {
      max_expansions
    },
    max_include_depth: if max_include_depth < 1 {
      1
    } else {
      max_include_depth
    },
  }
}

///|
fn preprocessor_message(
  state : PreprocessState,
  code : String,
  message : String,
  line : Int,
  column : Int,
  is_error : Bool,
) -> Unit {
  state.messages.push({ code, message, line, column, is_error })
}

///|
fn preprocessor_first_word(text : String) -> String {
  let trimmed = text.trim().to_owned()
  let chars = trimmed.to_array()
  let mut end = 0
  while end < chars.length() && preprocessor_word_char(chars[end]) {
    end += 1
  }
  trimmed[:end].to_owned()
}

///|
fn preprocessor_rest_after_word(text : String) -> String {
  let trimmed = text.trim().to_owned()
  let chars = trimmed.to_array()
  let mut start = 0
  while start < chars.length() && preprocessor_word_char(chars[start]) {
    start += 1
  }
  trimmed[start:].to_owned().trim().to_owned()
}

///|
fn preprocessor_parse_macro(payload : String, line : Int) -> MacroDefinition? {
  let trimmed = payload.trim().to_owned()
  if trimmed == "" {
    return None
  }
  let chars = trimmed.to_array()
  let mut name_end = 0
  while name_end < chars.length() && preprocessor_word_char(chars[name_end]) {
    name_end += 1
  }
  if name_end == 0 {
    return None
  }
  let name = trimmed[:name_end].to_owned()
  let parameters : Array[String] = []
  let mut body_start = name_end
  if name_end < chars.length() && chars[name_end] == '(' {
    let mut close = name_end + 1
    while close < chars.length() && chars[close] != ')' {
      close += 1
    }
    if close >= chars.length() {
      return None
    }
    let parameter_text = trimmed[name_end + 1:close].to_owned()
    for item in parameter_text.split(",") {
      let parameter = item.trim().to_owned()
      if parameter != "" {
        parameters.push(parameter)
      }
    }
    body_start = close + 1
  }
  Some({
    name,
    parameters,
    body: trimmed[body_start:].to_owned().trim().to_owned(),
    defined_line: line,
  })
}

///|
fn preprocessor_macro_arguments(
  text : String,
  open : Int,
) -> (Array[String], Int)? {
  let chars = text.to_array()
  if open < 0 || open >= chars.length() || chars[open] != '(' {
    return None
  }
  let args : Array[String] = []
  let mut depth = 1
  let mut start = open + 1
  let mut i = open + 1
  while i < chars.length() {
    if chars[i] == '(' {
      depth += 1
    } else if chars[i] == ')' {
      depth -= 1
      if depth == 0 {
        let piece = text[start:i].to_owned().trim().to_owned()
        if piece != "" || args.length() > 0 {
          args.push(piece)
        }
        return Some((args, i + 1))
      }
    } else if chars[i] == ',' && depth == 1 {
      args.push(text[start:i].to_owned().trim().to_owned())
      start = i + 1
    }
    i += 1
  }
  None
}

///|
fn preprocessor_replace_word(
  text : String,
  name : String,
  replacement : String,
) -> (String, Int) {
  let chars = text.to_array()
  let mut out = ""
  let mut index = 0
  let mut count = 0
  while index < chars.length() {
    if preprocessor_word_char(chars[index]) {
      let start = index
      while index < chars.length() && preprocessor_word_char(chars[index]) {
        index += 1
      }
      let word = text[start:index].to_owned()
      if word == name {
        out += replacement
        count += 1
      } else {
        out += word
      }
    } else {
      out += chars[index].to_string()
      index += 1
    }
  }
  (out, count)
}

///|
fn preprocessor_find_text(text : String, wanted : String, start : Int) -> Int? {
  let chars = text.to_array()
  let target = wanted.to_array()
  if target.length() == 0 {
    return Some(start)
  }
  let mut i = if start < 0 { 0 } else { start }
  while i + target.length() <= chars.length() {
    let mut equal = true
    for j in 0..<target.length() {
      if chars[i + j] != target[j] {
        equal = false
        break
      }
    }
    if equal {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn preprocessor_expand_parameter_macro(
  text : String,
  definition : MacroDefinition,
) -> (String, Int) {
  if definition.parameters.length() == 0 {
    return preprocessor_replace_word(text, definition.name, definition.body)
  }
  let mut output = text
  let mut replacements = 0
  let mut search = 0
  while search < output.length() {
    match preprocessor_find_text(output, definition.name, search) {
      Some(absolute) => {
        let after_name = absolute + definition.name.length()
        let mut open = after_name
        while open < output.length() &&
              (output[open] == ' ' || output[open] == '\t') {
          open += 1
        }
        match preprocessor_macro_arguments(output, open) {
          Some((args, end)) if args.length() == definition.parameters.length() => {
            let mut body = definition.body
            for i, parameter in definition.parameters {
              let argument = args[i]
              body = preprocessor_replace_word(body, parameter, argument).0
            }
            output = output[:absolute].to_owned() +
              body +
              output[end:].to_owned()
            replacements += 1
            search = absolute + body.length()
          }
          _ => search = after_name
        }
      }
      None => break
    }
  }
  (output, replacements)
}

///|
fn preprocessor_expand_line(
  state : PreprocessState,
  line : String,
  options : PreprocessOptions,
  line_number : Int,
) -> String {
  let mut output = line
  let mut changed = true
  let mut rounds = 0
  while changed && rounds < 32 && state.expansion_count < options.max_expansions {
    changed = false
    rounds += 1
    for definition in state.macros {
      let before = output
      let expanded = preprocessor_expand_parameter_macro(output, definition)
      output = expanded.0
      if expanded.1 > 0 {
        changed = true
        state.expansion_count += expanded.1
      } else {
        output = before
      }
      if state.expansion_count >= options.max_expansions {
        preprocessor_message(
          state, "PP002", "macro expansion limit reached", line_number, 1, true,
        )
        break
      }
    }
  }
  if rounds >= 32 && changed {
    preprocessor_message(
      state, "PP003", "macro expansion did not converge", line_number, 1, true,
    )
  }
  output
}

///|
fn preprocessor_include_source(
  options : PreprocessOptions,
  path : String,
) -> String? {
  for item in options.includes {
    if item.path == path {
      return Some(item.source)
    }
  }
  for prefix in options.include_paths {
    let candidate = prefix + "/" + path
    for item in options.includes {
      if item.path == candidate {
        return Some(item.source)
      }
    }
  }
  None
}

///|
fn preprocessor_unquote_path(text : String) -> String {
  let trimmed = text.trim().to_owned()
  if trimmed.length() >= 2 {
    let first = trimmed[0]
    let last = trimmed[trimmed.length() - 1]
    if (first == '"' && last == '"') || (first == '<' && last == '>') {
      return trimmed[1:trimmed.length() - 1].to_owned()
    }
  }
  trimmed
}

///|
fn preprocessor_push_condition(
  state : PreprocessState,
  condition : Bool,
) -> Unit {
  let parent = preprocessor_is_active(state)
  state.active_stack.push(parent && condition)
  state.branch_stack.push(condition)
}

///|
fn preprocessor_else_condition(state : PreprocessState, line : Int) -> Unit {
  if state.active_stack.length() == 0 || state.branch_stack.length() == 0 {
    preprocessor_message(state, "PP010", "unexpected `else`", line, 1, true)
    return
  }
  let was_taken = state.branch_stack[state.branch_stack.length() - 1]
  state.branch_stack[state.branch_stack.length() - 1] = true
  state.active_stack[state.active_stack.length() - 1] = preprocessor_parent_active(
      state,
    ) &&
    !was_taken
}

///|
fn preprocessor_pop_condition(state : PreprocessState, line : Int) -> Unit {
  if state.active_stack.length() == 0 || state.branch_stack.length() == 0 {
    preprocessor_message(state, "PP011", "unexpected `endif`", line, 1, true)
    return
  }
  ignore(state.active_stack.pop())
  ignore(state.branch_stack.pop())
}

///|
fn preprocessor_record_line(
  state : PreprocessState,
  text : String,
  path : String,
  source_line : Int,
  options : PreprocessOptions,
) -> Unit {
  let generated_line = state.output_lines.length() + 1
  state.output_lines.push(text)
  let origin = { generated_line, source_path: path, source_line }
  state.origins.push(origin)
  state.output_origins.push(origin)
  if options.emit_line_markers {
    ignore(options)
  }
}

///|
fn preprocessor_handle_directive(
  state : PreprocessState,
  directive : String,
  path : String,
  line_number : Int,
  options : PreprocessOptions,
  depth : Int,
) -> Bool {
  let name = preprocessor_first_word(directive)
  let payload = preprocessor_rest_after_word(directive)
  if name == "ifdef" || name == "ifndef" {
    let wanted = preprocessor_first_word(payload)
    let exists = preprocessor_find_macro(state.macros, wanted) is Some(_) ||
      preprocessor_define_names(options).contains(wanted)
    preprocessor_push_condition(
      state,
      if name == "ifdef" {
        exists
      } else {
        !exists
      },
    )
    return true
  }
  if name == "if" {
    let condition = payload.trim() == "1" ||
      (
        payload.has_prefix("defined(") &&
        payload.contains(")") &&
        preprocessor_find_macro(
          state.macros,
          payload[8:payload.length() - 1].to_owned(),
        )
        is Some(_)
      )
    preprocessor_push_condition(state, condition)
    return true
  }
  if name == "else" {
    preprocessor_else_condition(state, line_number)
    return true
  }
  if name == "endif" {
    preprocessor_pop_condition(state, line_number)
    return true
  }
  if !preprocessor_is_active(state) {
    return true
  }
  if name == "define" {
    match preprocessor_parse_macro(payload, line_number) {
      Some(definition) => state.macros.push(definition)
      None =>
        preprocessor_message(
          state, "PP001", "invalid macro definition", line_number, 1, true,
        )
    }
    return true
  }
  if name == "undef" {
    let wanted = preprocessor_first_word(payload)
    if wanted == "" {
      preprocessor_message(
        state, "PP004", "missing macro name", line_number, 1, true,
      )
    } else {
      let kept = state.macros.filter(fn(item) { item.name != wanted })
      state.macros.clear()
      for item in kept {
        state.macros.push(item)
      }
    }
    return true
  }
  if name == "include" {
    let include_path = preprocessor_unquote_path(payload)
    if include_path == "" {
      preprocessor_message(
        state, "PP005", "missing include path", line_number, 1, true,
      )
      return true
    }
    if depth >= options.max_include_depth {
      preprocessor_message(
        state, "PP006", "include depth limit reached", line_number, 1, true,
      )
      return true
    }
    if state.include_stack.contains(include_path) {
      preprocessor_message(
        state,
        "PP007",
        "recursive include skipped: " + include_path,
        line_number,
        1,
        true,
      )
      return true
    }
    match preprocessor_include_source(options, include_path) {
      Some(included) => {
        state.included_paths.push(include_path)
        state.include_stack.push(include_path)
        preprocessor_process_source(
          state,
          included,
          include_path,
          options,
          depth + 1,
        )
        ignore(state.include_stack.pop())
      }
      None =>
        preprocessor_message(
          state,
          "PP008",
          "include source unavailable: " + include_path,
          line_number,
          1,
          true,
        )
    }
    return true
  }
  if name == "line" {
    if options.preserve_directives {
      preprocessor_record_line(
        state,
        "`" + directive,
        path,
        line_number,
        options,
      )
    }
    return true
  }
  if options.preserve_directives {
    preprocessor_record_line(state, "`" + directive, path, line_number, options)
  }
  false
}

///|
fn preprocessor_process_source(
  state : PreprocessState,
  source : String,
  path : String,
  options : PreprocessOptions,
  depth : Int,
) -> Unit {
  for line_number, raw_line in source.split("\n") {
    let line = raw_line.to_owned()
    let trimmed = line.trim().to_owned()
    let is_directive = trimmed.has_prefix("`")
    if is_directive {
      let handled = preprocessor_handle_directive(
        state,
        trimmed[1:].to_owned(),
        path,
        line_number + 1,
        options,
        depth,
      )
      if handled {
        continue
      }
    }
    if !preprocessor_is_active(state) {
      state.skipped_lines += 1
      continue
    }
    let expanded = preprocessor_expand_line(
      state,
      line,
      options,
      line_number + 1,
    )
    preprocessor_record_line(state, expanded, path, line_number + 1, options)
  }
}

///|
/// Preprocess a Verilog source string using only supplied in-memory includes.
pub fn preprocess(
  source : String,
  options : PreprocessOptions,
) -> PreprocessResult {
  let state = {
    macros: [],
    messages: [],
    origins: [],
    included_paths: [],
    output_lines: [],
    output_origins: [],
    active_stack: [],
    branch_stack: [],
    include_stack: [],
    expansion_count: 0,
    skipped_lines: 0,
  }
  for item in options.defines {
    match preprocessor_parse_macro(item, 0) {
      Some(definition) => state.macros.push(definition)
      None => ()
    }
  }
  preprocessor_process_source(state, source, "<input>", options, 0)
  if state.active_stack.length() > 0 {
    preprocessor_message(
      state,
      "PP012",
      "unterminated conditional directive",
      state.output_lines.length() + 1,
      1,
      true,
    )
  }
  {
    source: state.output_lines.join("\n"),
    macros: state.macros,
    messages: state.messages,
    origins: state.output_origins,
    included_paths: state.included_paths,
    emitted_lines: state.output_lines.length(),
    skipped_lines: state.skipped_lines,
    expansion_count: state.expansion_count,
  }
}

///|
pub fn preprocess_default(source : String) -> PreprocessResult {
  preprocess(source, PreprocessOptions::default())
}

///|
pub fn PreprocessResult::is_clean(self : PreprocessResult) -> Bool {
  !self.messages.any(fn(item) { item.is_error })
}

///|
pub fn PreprocessResult::errors(
  self : PreprocessResult,
) -> Array[PreprocessMessage] {
  self.messages.filter(fn(item) { item.is_error })
}

///|
pub fn PreprocessResult::warnings(
  self : PreprocessResult,
) -> Array[PreprocessMessage] {
  self.messages.filter(fn(item) { !item.is_error })
}

///|
pub fn PreprocessResult::origin_for_line(
  self : PreprocessResult,
  generated_line : Int,
) -> PreprocessOrigin? {
  for item in self.origins {
    if item.generated_line == generated_line {
      return Some(item)
    }
  }
  None
}

///|
fn preprocess_message_json(item : PreprocessMessage) -> String {
  "{\"code\":\"" +
  json_escape(item.code) +
  "\",\"message\":\"" +
  json_escape(item.message) +
  "\",\"line\":" +
  item.line.to_string() +
  ",\"column\":" +
  item.column.to_string() +
  ",\"severity\":\"" +
  (if item.is_error { "error" } else { "warning" }) +
  "\"}"
}

///|
pub fn PreprocessResult::to_json(self : PreprocessResult) -> String {
  let messages = self.messages.map(preprocess_message_json).join(",")
  let includes = self.included_paths
    .map(fn(item) { "\"" + json_escape(item) + "\"" })
    .join(",")
  "{\"clean\":" +
  (if self.is_clean() { "true" } else { "false" }) +
  ",\"emitted_lines\":" +
  self.emitted_lines.to_string() +
  ",\"skipped_lines\":" +
  self.skipped_lines.to_string() +
  ",\"expansions\":" +
  self.expansion_count.to_string() +
  ",\"includes\":[" +
  includes +
  "]" +
  ",\"messages\":[" +
  messages +
  "]}"
}

///|
pub fn PreprocessResult::to_markdown(self : PreprocessResult) -> String {
  let out = "# Preprocessor report\n\n" +
    "- clean: `" +
    (if self.is_clean() { "true" } else { "false" }) +
    "`\n" +
    "- emitted lines: `" +
    self.emitted_lines.to_string() +
    "`\n" +
    "- skipped lines: `" +
    self.skipped_lines.to_string() +
    "`\n" +
    "- macro expansions: `" +
    self.expansion_count.to_string() +
    "`\n\n"
  if self.messages.length() == 0 {
    return out + "No preprocessor diagnostics.\n"
  }
  out +
  "| Code | Severity | Location | Message |\n| --- | --- | --- | --- |\n" +
  self.messages
  .map(fn(item) {
    "| " +
    item.code +
    " | " +
    (if item.is_error { "error" } else { "warning" }) +
    " | " +
    item.line.to_string() +
    ":" +
    item.column.to_string() +
    " | " +
    item.message +
    " |"
  })
  .join("\n") +
  "\n"
}

///|
pub fn preprocess_diagnostics(result : PreprocessResult) -> Array[Diagnostic] {
  result.messages.map(fn(item) {
    Diagnostic::new(
      item.code,
      if item.is_error {
        Error
      } else {
        Warning
      },
      item.message,
      item.line,
      item.column,
    )
  })
}

///|
pub fn preprocess_and_parse(
  source : String,
  options : PreprocessOptions,
) -> ParseResult {
  let result = preprocess(source, options)
  let parsed = parse_with_diagnostics(result.source)
  let diagnostics = parsed.diagnostics.copy()
  for item in preprocess_diagnostics(result) {
    diagnostics.push({
      code: item.code,
      message: item.message,
      line: item.line,
      column: item.column,
      severity: item.severity,
    })
  }
  { ..parsed, diagnostics, }
}

///|
pub fn preprocess_preview(source : String, max_lines : Int) -> String {
  let result = preprocess_default(source)
  let lines = result.source.split("\n")
  let limit = if max_lines < 0 { 0 } else { max_lines }
  lines[:if lines.length() > limit { limit } else { lines.length() }].join("\n")
}

///|
pub fn preprocess_macro_names(result : PreprocessResult) -> Array[String] {
  result.macros.map(fn(item) { item.name })
}

///|
pub fn preprocess_origin_text(result : PreprocessResult) -> String {
  result.origins
  .map(fn(item) {
    item.generated_line.to_string() +
    " <- " +
    item.source_path +
    ":" +
    item.source_line.to_string()
  })
  .join("\n")
}

///|
pub fn preprocess_contract() -> String {
  "directives=define,undef,ifdef,ifndef,if,else,endif,include,line; " +
  "origin_tracking=true; include_io=in_memory; deterministic=true"
}
