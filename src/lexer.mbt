///|
/// A token from the Verilog-2001 subset lexer.
pub struct Token {
  text : String
  line : Int
  column : Int
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
fn is_word(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '$'
}

///|
fn chars_to_string(chars : Array[Char], start : Int, end : Int) -> String {
  let mut out = ""
  for i in start..<end {
    out += chars[i].to_string()
  }
  out
}

///|
/// Tokenize comments, identifiers, numbers and punctuation.
pub fn lex(source : String) -> Array[Token] {
  let chars = source.to_array()
  let out : Array[Token] = []
  let mut i = 0
  let mut line = 1
  let mut column = 1
  while i < chars.length() {
    let c = chars[i]
    if c == '\n' {
      line += 1
      column = 1
      i += 1
    } else if is_space(c) {
      column += 1
      i += 1
    } else if c == '/' && i + 1 < chars.length() && chars[i + 1] == '/' {
      while i < chars.length() && chars[i] != '\n' {
        i += 1
        column += 1
      }
    } else if c == '/' && i + 1 < chars.length() && chars[i + 1] == '*' {
      i += 2
      column += 2
      while i + 1 < chars.length() && !(chars[i] == '*' && chars[i + 1] == '/') {
        if chars[i] == '\n' {
          line += 1
          column = 1
        } else {
          column += 1
        }
        i += 1
      }
      if i + 1 < chars.length() {
        i += 2
        column += 2
      }
    } else if is_word(c) {
      let start = i
      let start_column = column
      while i < chars.length() && is_word(chars[i]) {
        i += 1
        column += 1
      }
      out.push({
        text: chars_to_string(chars, start, i),
        line,
        column: start_column,
      })
    } else if c == '\'' {
      let start = i
      let start_column = column
      i += 1
      column += 1
      while i < chars.length() && is_word(chars[i]) {
        i += 1
        column += 1
      }
      out.push({
        text: chars_to_string(chars, start, i),
        line,
        column: start_column,
      })
    } else {
      out.push({ text: c.to_string(), line, column })
      i += 1
      column += 1
    }
  }
  out
}
