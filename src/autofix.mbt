///|
/// The category of a source repair suggestion.
pub enum FixKind {
  FixWhitespace
  FixSignalName
  FixMissingDefault
  FixWidthAnnotation
  FixSensitivity
  FixUnknown
} derive(Eq)

///|
/// A reviewable, deterministic source edit.
pub struct FixSuggestion {
  id : String
  code : String
  kind : FixKind
  message : String
  edits : Array[SourceEdit]
  confidence : Int
  safe : Bool
}

///|
/// A complete fix plan generated from a source snapshot.
pub struct FixPlan {
  source_hash : String
  suggestions : Array[FixSuggestion]
  applicable : Int
  rejected : Int
}

///|
fn fix_kind_text(kind : FixKind) -> String {
  match kind {
    FixWhitespace => "whitespace"
    FixSignalName => "signal_name"
    FixMissingDefault => "missing_default"
    FixWidthAnnotation => "width_annotation"
    FixSensitivity => "sensitivity"
    FixUnknown => "unknown"
  }
}

///|
fn autofix_kind_for_code(code : String) -> FixKind {
  match code {
    "RTL001" => FixWhitespace
    "RTL020" | "RTL021" => FixSensitivity
    "RTL003" | "RTL004" => FixMissingDefault
    "RTL014" | "RTL015" => FixWidthAnnotation
    "STYLE001" => FixSignalName
    _ => FixUnknown
  }
}

///|
fn autofix_line_offset(source : String, line : Int, column : Int) -> Int {
  if line < 1 || column < 1 {
    return 0
  }
  let mut offset = 0
  for current, text in source.split("\n") {
    if current + 1 == line {
      return offset + column - 1
    }
    offset += text.length() + 1
  }
  offset
}

///|
fn autofix_edit_for_diagnostic(
  source : String,
  item : Diagnostic,
) -> FixSuggestion? {
  match item.code {
    "RTL001" => {
      let start = autofix_line_offset(source, item.line, item.column)
      let line = source_line(source, item.line)
      let replacement = line.trim_end().to_owned()
      if replacement != line {
        Some({
          id: "fix-" + item.code + "-" + item.line.to_string(),
          code: item.code,
          kind: FixWhitespace,
          message: "remove trailing whitespace",
          edits: [
            SourceEdit::new(
              start,
              start + line.length(),
              replacement,
              "trim trailing whitespace",
            ),
          ],
          confidence: 100,
          safe: true,
        })
      } else {
        None
      }
    }
    "RTL020" | "RTL021" => {
      let start = autofix_line_offset(source, item.line, item.column)
      Some({
        id: "review-" + item.code + "-" + item.line.to_string(),
        code: item.code,
        kind: FixSensitivity,
        message: "review procedural sensitivity list",
        edits: [SourceEdit::new(start, start, "", "manual sensitivity review")],
        confidence: 40,
        safe: false,
      })
    }
    _ => {
      ignore(autofix_kind_for_code(item.code))
      None
    }
  }
}

///|
fn autofix_naming_suggestions(
  source : String,
  design : Design,
) -> Array[FixSuggestion] {
  let suggestions : Array[FixSuggestion] = []
  for edit in naming_edits(design, source) {
    suggestions.push({
      id: "name-" + edit.start.to_string(),
      code: "STYLE001",
      kind: FixSignalName,
      message: edit.reason,
      edits: [
        SourceEdit::new(edit.start, edit.end, edit.replacement, edit.reason),
      ],
      confidence: 90,
      safe: true,
    })
  }
  suggestions
}

///|
fn autofix_deduplicate(
  suggestions : Array[FixSuggestion],
) -> Array[FixSuggestion] {
  let result : Array[FixSuggestion] = []
  for suggestion in suggestions {
    if !result.any(fn(item) { item.id == suggestion.id }) {
      result.push(suggestion)
    }
  }
  result
}

///|
/// Produce safe and review-only fixes from the current diagnostics.
pub fn suggest_fixes(
  source : String,
  diagnostics : Array[Diagnostic],
) -> FixPlan {
  let suggestions : Array[FixSuggestion] = []
  for item in diagnostics {
    match autofix_edit_for_diagnostic(source, item) {
      Some(suggestion) => suggestions.push(suggestion)
      None => ()
    }
  }
  let design = parse(source)
  for suggestion in autofix_naming_suggestions(source, design) {
    suggestions.push(suggestion)
  }
  let unique = autofix_deduplicate(suggestions)
  {
    source_hash: source_hash(source),
    suggestions: unique,
    applicable: unique.filter(fn(item) { item.edits.length() > 0 }).length(),
    rejected: unique.filter(fn(item) { !item.safe }).length(),
  }
}

///|
pub fn suggest_fixes_for_source(source : String) -> FixPlan {
  suggest_fixes(source, check_source(source))
}

///|
pub fn FixPlan::safe(self : FixPlan) -> Array[FixSuggestion] {
  self.suggestions.filter(fn(item) { item.safe })
}

///|
pub fn FixPlan::review_required(self : FixPlan) -> Array[FixSuggestion] {
  self.suggestions.filter(fn(item) { !item.safe })
}

///|
fn autofix_all_edits(suggestions : Array[FixSuggestion]) -> Array[SourceEdit] {
  let result : Array[SourceEdit] = []
  for suggestion in suggestions {
    for edit in suggestion.edits {
      result.push(edit)
    }
  }
  result
}

///|
/// Apply all safe suggestions as one overlap-checked edit set.
pub fn apply_safe_fixes(source : String, plan : FixPlan) -> String? {
  let edits = autofix_all_edits(plan.safe())
  match EditSet::from_edits(source, edits) {
    Some(set) => set.apply(source)
    None => None
  }
}

///|
pub fn apply_safe_fixes_for_source(source : String) -> String? {
  apply_safe_fixes(source, suggest_fixes_for_source(source))
}

///|
pub fn validate_fix(source : String, fixed : String) -> Bool {
  let before = check_source(source)
  let after = check_source(fixed)
  let before_errors = before
    .filter(fn(item) { item.severity == Error })
    .length()
  let after_errors = after.filter(fn(item) { item.severity == Error }).length()
  after_errors <= before_errors && syntax_is_safe(fixed)
}

///|
pub fn FixPlan::apply_and_validate(self : FixPlan, source : String) -> String? {
  match apply_safe_fixes(source, self) {
    Some(fixed) if validate_fix(source, fixed) => Some(fixed)
    _ => None
  }
}

///|
pub fn FixPlan::summary(self : FixPlan) -> String {
  "fixes=" +
  self.suggestions.length().to_string() +
  " applicable=" +
  self.applicable.to_string() +
  " review_required=" +
  self.rejected.to_string() +
  " source_hash=" +
  self.source_hash
}

///|
fn fix_suggestion_json(item : FixSuggestion) -> String {
  "{\"id\":\"" +
  json_escape(item.id) +
  "\",\"code\":\"" +
  item.code +
  "\",\"kind\":\"" +
  fix_kind_text(item.kind) +
  "\",\"message\":\"" +
  json_escape(item.message) +
  "\",\"confidence\":" +
  item.confidence.to_string() +
  ",\"safe\":" +
  (if item.safe { "true" } else { "false" }) +
  ",\"edits\":[" +
  item.edits
  .map(fn(edit) {
    "{\"start\":" +
    edit.start_offset.to_string() +
    ",\"end\":" +
    edit.end_offset.to_string() +
    ",\"replacement\":\"" +
    json_escape(edit.replacement) +
    "\"}"
  })
  .join(",") +
  "]}"
}

///|
pub fn FixPlan::to_json(self : FixPlan) -> String {
  "{\"source_hash\":\"" +
  self.source_hash +
  "\",\"applicable\":" +
  self.applicable.to_string() +
  ",\"rejected\":" +
  self.rejected.to_string() +
  ",\"suggestions\":[" +
  self.suggestions.map(fix_suggestion_json).join(",") +
  "]}"
}

///|
pub fn FixPlan::to_markdown(self : FixPlan) -> String {
  let rows = self.suggestions
    .map(fn(item) {
      "| " +
      item.code +
      " | " +
      fix_kind_text(item.kind) +
      " | " +
      (if item.safe { "safe" } else { "review" }) +
      " | " +
      item.confidence.to_string() +
      "% | " +
      item.message +
      " |"
    })
    .join("\n")
  "# Autofix plan\n\n" +
  self.summary() +
  "\n\n" +
  "| Code | Kind | Policy | Confidence | Message |\n| --- | --- | --- | ---: | --- |\n" +
  rows +
  "\n"
}

///|
pub fn autofix_diagnostics(plan : FixPlan) -> Array[Diagnostic] {
  plan
  .review_required()
  .map(fn(item) {
    Diagnostic::new(
      "FIX001",
      Info,
      "manual review required for " + item.code + ": " + item.message,
      1,
      1,
    )
  })
}

///|
pub fn autofix_contract() -> String {
  "policy=safe_edits_only; overlap=reject; validation=syntax_and_error_count; " +
  "review_fixes=retained_as_metadata"
}
