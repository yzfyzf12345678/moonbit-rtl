///|
/// A token from the Verilog-2001 subset lexer.
pub struct Token {
  text : String
  line : Int
  column : Int
  kind : TokenKind
  offset : Int
  end_offset : Int
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f'
}

///|
fn is_word_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$'
}

///|
fn is_word(c : Char) -> Bool {
  is_word_start(c) || (c >= '0' && c <= '9')
}

///|
fn is_decimal_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
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
fn starts_with(chars : Array[Char], start : Int, text : String) -> Bool {
  let wanted = text.to_array()
  if start + wanted.length() > chars.length() {
    false
  } else {
    for i in 0..<wanted.length() {
      if chars[start + i] != wanted[i] {
        return false
      }
    }
    true
  }
}

///|
fn token(
  chars : Array[Char],
  start : Int,
  end : Int,
  line : Int,
  column : Int,
  kind : TokenKind,
) -> Token {
  {
    text: chars_to_string(chars, start, end),
    line,
    column,
    kind,
    offset: start,
    end_offset: end,
  }
}

///|
fn operator_length(chars : Array[Char], start : Int) -> Int {
  let candidates : Array[String] = [
    "<<<", ">>>", "===", "!==", "==?", "!=?", "&&", "||", "<=", ">=", "==", "!=",
    "<<", ">>", "+:", "-:", "=>", "->", "**", "^~", "~^", "(*", "*)",
  ]
  for candidate in candidates {
    if starts_with(chars, start, candidate) {
      return candidate.length()
    }
  }
  1
}

///|
fn read_number_end(chars : Array[Char], start : Int) -> Int {
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if is_word(c) || c == '\'' || c == '?' {
      i += 1
    } else {
      break
    }
  }
  i
}

///|
fn read_quoted_end(chars : Array[Char], start : Int) -> Int {
  let mut i = start + 1
  while i < chars.length() {
    if chars[i] == '\\' && i + 1 < chars.length() {
      i += 2
    } else if chars[i] == '"' {
      return i + 1
    } else {
      i += 1
    }
  }
  i
}

///|
fn read_escaped_identifier_end(chars : Array[Char], start : Int) -> Int {
  let mut i = start + 1
  while i < chars.length() && !is_space(chars[i]) {
    i += 1
  }
  i
}

///|
fn advance_position(
  chars : Array[Char],
  start : Int,
  end : Int,
  line : Int,
  column : Int,
) -> (Int, Int) {
  let mut next_line = line
  let mut next_column = column
  for i in start..<end {
    if chars[i] == '\n' {
      next_line += 1
      next_column = 1
    } else {
      next_column += 1
    }
  }
  (next_line, next_column)
}

///|
/// Tokenize comments, identifiers, literals, multi-character operators and
/// punctuation while preserving exact source offsets.
pub fn lex(source : String) -> Array[Token] {
  let chars = source.to_array()
  let out : Array[Token] = []
  let mut i = 0
  let mut line = 1
  let mut column = 1
  while i < chars.length() {
    let c = chars[i]
    if c == '\n' {
      i += 1
      line += 1
      column = 1
    } else if is_space(c) {
      i += 1
      column += 1
    } else if c == '/' && i + 1 < chars.length() && chars[i + 1] == '/' {
      let mut end = i + 2
      while end < chars.length() && chars[end] != '\n' {
        end += 1
      }
      let next = advance_position(chars, i, end, line, column)
      line = next.0
      column = next.1
      i = end
    } else if c == '/' && i + 1 < chars.length() && chars[i + 1] == '*' {
      let mut end = i + 2
      while end + 1 < chars.length() &&
            !(chars[end] == '*' && chars[end + 1] == '/') {
        end += 1
      }
      if end + 1 < chars.length() {
        end += 2
      } else {
        end = chars.length()
      }
      let next = advance_position(chars, i, end, line, column)
      line = next.0
      column = next.1
      i = end
    } else if c == '`' {
      let start_column = column
      let end = read_escaped_identifier_end(chars, i)
      out.push(token(chars, i, end, line, start_column, DirectiveToken))
      column += end - i
      i = end
    } else if c == '"' {
      let start_column = column
      let end = read_quoted_end(chars, i)
      out.push(token(chars, i, end, line, start_column, StringToken))
      let next = advance_position(chars, i, end, line, column)
      line = next.0
      column = next.1
      i = end
    } else if is_decimal_digit(c) {
      let start_column = column
      let end = read_number_end(chars, i)
      out.push(token(chars, i, end, line, start_column, NumberToken))
      column += end - i
      i = end
    } else if is_word_start(c) {
      let start_column = column
      let mut end = i + 1
      while end < chars.length() && is_word(chars[end]) {
        end += 1
      }
      out.push(token(chars, i, end, line, start_column, IdentifierToken))
      column += end - i
      i = end
    } else if c == '\\' {
      let start_column = column
      let end = read_escaped_identifier_end(chars, i)
      out.push(token(chars, i, end, line, start_column, IdentifierToken))
      column += end - i
      i = end
    } else {
      let start_column = column
      let length = operator_length(chars, i)
      let kind = if is_punctuation(c) {
        PunctuationToken
      } else {
        OperatorToken
      }
      out.push(token(chars, i, i + length, line, start_column, kind))
      column += length
      i += length
    }
  }
  out
}

///|
fn is_punctuation(c : Char) -> Bool {
  c == '(' ||
  c == ')' ||
  c == '[' ||
  c == ']' ||
  c == '{' ||
  c == '}' ||
  c == ',' ||
  c == ';' ||
  c == ':' ||
  c == '.'
}
