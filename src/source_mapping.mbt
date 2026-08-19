///|
/// A source edit used by future auto-fix adapters.
pub struct TextEdit {
  start : Int
  end : Int
  replacement : String
  reason : String
}

///|
/// A source position converted to a byte-like character offset.
pub struct SourceCoordinate {
  line : Int
  column : Int
  offset : Int
}

///|
/// Convert a line/column pair into a source coordinate.
pub fn coordinate(
  source : String,
  line : Int,
  column : Int,
) -> SourceCoordinate {
  let index = SourceIndex::from(source)
  let column_offset = if column < 1 { 0 } else { column - 1 }
  let offset = index.line_offset(line).unwrap_or(0) + column_offset
  { line, column, offset }
}

///|
/// Return the exact text covered by a span.
pub fn span_text(source : String, span : Span) -> String {
  let start = coordinate(source, span.start.line, span.start.column).offset
  let end = coordinate(source, span.end.line, span.end.column).offset
  if start < 0 || end < start || start >= source.length() {
    ""
  } else {
    source[start:end].to_owned()
  }
}

///|
/// Find the token at a source coordinate.
pub fn token_at(source : String, line : Int, column : Int) -> Token? {
  let offset = coordinate(source, line, column).offset
  for item in lex(source) {
    if item.offset <= offset && offset < item.end_offset {
      return Some(item)
    }
  }
  None
}

///|
/// Find all spans whose token text matches a name.
pub fn token_occurrences(source : String, name : String) -> Array[Span] {
  let result : Array[Span] = []
  for item in lex(source) {
    if item.text == name {
      result.push(
        Span::range(
          Position::new(item.line, item.column),
          Position::new(item.line, item.column + item.end_offset - item.offset),
        ),
      )
    }
  }
  result
}

///|
/// Apply non-overlapping edits from right to left.
pub fn apply_edits(source : String, edits : Array[TextEdit]) -> String {
  let ordered = edits.copy()
  ordered.sort_by(fn(left, right) { right.start - left.start })
  let mut out = source
  for edit in ordered {
    if edit.start >= 0 && edit.end >= edit.start && edit.end <= out.length() {
      out = out[:edit.start].to_owned() +
        edit.replacement +
        out[edit.end:].to_owned()
    }
  }
  out
}

///|
/// Suggest a safe replacement for an uppercase port name.
pub fn uppercase_port_edit(port : Signal, source : String) -> TextEdit? {
  let chars = port.name.to_array()
  match chars.get(0) {
    Some(first) if first >= 'A' && first <= 'Z' => {
      let replacement = first.to_string().to_lower() + port.name[1:].to_owned()
      let start = coordinate(
          source,
          port.span.start.line,
          port.span.start.column,
        ).offset
      Some({
        start,
        end: start + port.name.length(),
        replacement,
        reason: "normalize port naming",
      })
    }
    _ => None
  }
}

///|
/// Collect safe naming edits without changing source semantics.
pub fn naming_edits(design : Design, source : String) -> Array[TextEdit] {
  let result : Array[TextEdit] = []
  for unit in design.modules {
    for port in unit.ports {
      match uppercase_port_edit(port, source) {
        Some(edit) => result.push(edit)
        None => ()
      }
    }
  }
  result
}

///|
/// Format a location in the conventional `line:column` form.
pub fn coordinate_text(coordinate : SourceCoordinate) -> String {
  coordinate.line.to_string() + ":" + coordinate.column.to_string()
}

///|
/// Return the first module span containing a line.
pub fn module_at_line(design : Design, line : Int) -> Module? {
  for unit in design.modules {
    if unit.span.start.line <= line && line <= unit.span.end.line {
      return Some(unit)
    }
  }
  None
}

///|
/// Return a source map report suitable for debugging parser regressions.
pub fn source_map_report(source : String) -> String {
  let index = SourceIndex::from(source)
  let mut out = "lines=" +
    index.offsets.length().to_string() +
    " length=" +
    index.source_length.to_string() +
    "\n"
  for line in 1..<=index.offsets.length() {
    out += line.to_string() +
      "=" +
      index.line_offset(line).unwrap_or(0).to_string() +
      "\n"
  }
  out
}

///|
/// Return all source coordinates where a design symbol occurs.
pub fn symbol_coordinates(
  source : String,
  design : Design,
  name : String,
) -> Array[SourceCoordinate] {
  let result : Array[SourceCoordinate] = []
  for hit in query_symbols(design, name) {
    result.push(coordinate(source, hit.line, hit.column))
  }
  result
}

///|
/// Turn a diagnostic into a minimal edit preview.
pub fn diagnostic_preview(source : String, item : Diagnostic) -> String {
  let token = token_at(source, item.line, item.column)
  match token {
    Some(value) =>
      item.code +
      " at " +
      item.line.to_string() +
      ":" +
      item.column.to_string() +
      " -> " +
      value.text
    None =>
      item.code + " at " + item.line.to_string() + ":" + item.column.to_string()
  }
}

///|
/// Verify that applying edits preserves the number of parsed modules.
pub fn edits_preserve_module_count(
  source : String,
  edits : Array[TextEdit],
) -> Bool {
  parse(source).modules.length() ==
  parse(apply_edits(source, edits)).modules.length()
}

///|
/// Compute a source delta suitable for changelog entries.
pub fn source_delta(before : String, after : String) -> String {
  let before_tokens = lex(before).length()
  let after_tokens = lex(after).length()
  let before_lines = before.split("\n").count()
  let after_lines = after.split("\n").count()
  "lines=" +
  (after_lines - before_lines).to_string() +
  " tokens=" +
  (after_tokens - before_tokens).to_string() +
  " bytes=" +
  (after.length() - before.length()).to_string()
}
