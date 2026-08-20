///|
/// Four-state logic used by the lightweight RTL evaluator.
pub enum LogicBit {
  LogicZero
  LogicOne
  LogicUnknown
  LogicHighZ
} derive(Eq)

///|
/// A packed vector stored least-significant bit first.
pub struct LogicVector {
  bits : Array[LogicBit]
}

///|
fn logic_bit_from_char(c : Char) -> LogicBit {
  match c {
    '0' => LogicZero
    '1' => LogicOne
    'x' | 'X' => LogicUnknown
    'z' | 'Z' | '?' => LogicHighZ
    _ => LogicUnknown
  }
}

///|
pub fn LogicBit::from_char(c : Char) -> LogicBit {
  logic_bit_from_char(c)
}

///|
pub fn LogicBit::to_char(self : LogicBit) -> Char {
  match self {
    LogicZero => '0'
    LogicOne => '1'
    LogicUnknown => 'x'
    LogicHighZ => 'z'
  }
}

///|
pub fn LogicBit::is_known(self : LogicBit) -> Bool {
  self == LogicZero || self == LogicOne
}

///|
pub fn LogicBit::is_high_z(self : LogicBit) -> Bool {
  self == LogicHighZ
}

///|
pub fn LogicBit::not(self : LogicBit) -> LogicBit {
  match self {
    LogicZero => LogicOne
    LogicOne => LogicZero
    LogicUnknown | LogicHighZ => LogicUnknown
  }
}

///|
pub fn LogicBit::and_bit(self : LogicBit, other : LogicBit) -> LogicBit {
  match (self, other) {
    (LogicZero, _) | (_, LogicZero) => LogicZero
    (LogicOne, LogicOne) => LogicOne
    (LogicHighZ, LogicOne) | (LogicOne, LogicHighZ) => LogicUnknown
    _ => LogicUnknown
  }
}

///|
pub fn LogicBit::or_bit(self : LogicBit, other : LogicBit) -> LogicBit {
  match (self, other) {
    (LogicOne, _) | (_, LogicOne) => LogicOne
    (LogicZero, LogicZero) => LogicZero
    (LogicHighZ, LogicZero) | (LogicZero, LogicHighZ) => LogicUnknown
    _ => LogicUnknown
  }
}

///|
pub fn LogicBit::xor_bit(self : LogicBit, other : LogicBit) -> LogicBit {
  match (self, other) {
    (LogicZero, LogicZero) | (LogicOne, LogicOne) => LogicZero
    (LogicZero, LogicOne) | (LogicOne, LogicZero) => LogicOne
    _ => LogicUnknown
  }
}

///|
pub fn LogicBit::merge(self : LogicBit, other : LogicBit) -> LogicBit {
  if self == other {
    self
  } else {
    LogicUnknown
  }
}

///|
fn logic_bit_to_int(bit : LogicBit) -> Int? {
  match bit {
    LogicZero => Some(0)
    LogicOne => Some(1)
    _ => None
  }
}

///|
fn logic_digit_value(c : Char, base : Int) -> Int? {
  let value = if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    10 + c.to_int() - 'a'.to_int()
  } else if c >= 'A' && c <= 'F' {
    10 + c.to_int() - 'A'.to_int()
  } else {
    -1
  }
  if value >= 0 && value < base {
    Some(value)
  } else {
    None
  }
}

///|
fn logic_pow2(exponent : Int) -> Int {
  let mut result = 1
  let count = if exponent < 0 { 0 } else { exponent }
  for _ in 0..<count {
    result *= 2
  }
  result
}

///|
fn logic_hex_digit(value : Int) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    15 => "f"
    _ => "x"
  }
}

///|
fn logic_bits_for_digit(value : Int, base : Int) -> Array[LogicBit] {
  let width = if base == 2 { 1 } else if base == 8 { 3 } else { 4 }
  let result : Array[LogicBit] = []
  let mut current = value
  for _ in 0..<width {
    result.push(if current % 2 == 0 { LogicZero } else { LogicOne })
    current /= 2
  }
  result
}

///|
fn logic_unknown_bits(width : Int) -> Array[LogicBit] {
  let result : Array[LogicBit] = []
  let count = if width < 0 { 0 } else { width }
  for _ in 0..<count {
    result.push(LogicUnknown)
  }
  result
}

///|
pub fn LogicVector::from_bits(bits : Array[LogicBit]) -> LogicVector {
  { bits: bits.copy() }
}

///|
pub fn LogicVector::zero(width : Int) -> LogicVector {
  let result : Array[LogicBit] = []
  let count = if width < 0 { 0 } else { width }
  for _ in 0..<count {
    result.push(LogicZero)
  }
  { bits: result }
}

///|
pub fn LogicVector::ones(width : Int) -> LogicVector {
  let result : Array[LogicBit] = []
  let count = if width < 0 { 0 } else { width }
  for _ in 0..<count {
    result.push(LogicOne)
  }
  { bits: result }
}

///|
pub fn LogicVector::unknown(width : Int) -> LogicVector {
  { bits: logic_unknown_bits(width) }
}

///|
pub fn LogicVector::high_z(width : Int) -> LogicVector {
  let result : Array[LogicBit] = []
  let count = if width < 0 { 0 } else { width }
  for _ in 0..<count {
    result.push(LogicHighZ)
  }
  { bits: result }
}

///|
pub fn LogicVector::from_int(value : Int, width : Int) -> LogicVector {
  let result : Array[LogicBit] = []
  let mut current = value
  let count = if width < 0 { 0 } else { width }
  for _ in 0..<count {
    let bit = current % 2
    result.push(if bit < 0 || bit == 0 { LogicZero } else { LogicOne })
    current /= 2
  }
  { bits: result }
}

///|
fn logic_vector_digits(
  text : String,
  start : Int,
  base : Int,
) -> Array[LogicBit] {
  let result : Array[LogicBit] = []
  let chars = text.to_array()
  let mut i = chars.length()
  while i > start {
    i -= 1
    let c = chars[i]
    if c == '_' {
      continue
    }
    if c == 'x' || c == 'X' || c == 'z' || c == 'Z' || c == '?' {
      let width = if base == 2 { 1 } else if base == 8 { 3 } else { 4 }
      for _ in 0..<width {
        result.push(logic_bit_from_char(c))
      }
    } else {
      match logic_digit_value(c, base) {
        Some(value) =>
          for bit in logic_bits_for_digit(value, base) {
            result.push(bit)
          }
        None => ()
      }
    }
  }
  result
}

///|
/// Parse a Verilog literal such as `8'hA5`, `4'b10x1`, or a decimal integer.
pub fn LogicVector::from_literal(text : String) -> LogicVector {
  let trimmed = text.trim().to_owned()
  match trimmed.split_once("'") {
    Some((width_text, suffix)) => {
      let width = if width_text == "" {
        32
      } else {
        let mut value = 0
        for c in width_text.to_array() {
          if c >= '0' && c <= '9' {
            value = value * 10 + c.to_int() - '0'.to_int()
          }
        }
        if value < 1 {
          1
        } else {
          value
        }
      }
      let suffix_chars = suffix.to_array()
      let base = if suffix_chars.length() > 0 {
        match suffix_chars[0] {
          'b' | 'B' => 2
          'o' | 'O' => 8
          'd' | 'D' => 10
          'h' | 'H' => 16
          _ => 10
        }
      } else {
        10
      }
      let start = if suffix_chars.length() > 0 { 1 } else { 0 }
      let parsed = logic_vector_digits(suffix.to_owned(), start, base)
      let result = LogicVector::zero(width)
      for i in 0..<width {
        if i < parsed.length() {
          result.bits[i] = parsed[i]
        }
      }
      result
    }
    None => {
      let mut value = 0
      for c in trimmed.to_array() {
        if c >= '0' && c <= '9' {
          value = value * 10 + c.to_int() - '0'.to_int()
        }
      }
      LogicVector::from_int(value, 32)
    }
  }
}

///|
pub fn LogicVector::from_text(text : String) -> LogicVector {
  let chars = text.trim().to_array()
  let result : Array[LogicBit] = []
  for c in chars.rev() {
    result.push(logic_bit_from_char(c))
  }
  { bits: result }
}

///|
pub fn LogicVector::width(self : LogicVector) -> Int {
  self.bits.length()
}

///|
pub fn LogicVector::is_empty(self : LogicVector) -> Bool {
  self.bits.length() == 0
}

///|
pub fn LogicVector::bit(self : LogicVector, index : Int) -> LogicBit? {
  self.bits.get(index)
}

///|
pub fn LogicVector::with_bit(
  self : LogicVector,
  index : Int,
  value : LogicBit,
) -> LogicVector {
  let result = self.bits.copy()
  if index >= 0 && index < result.length() {
    result[index] = value
  }
  { bits: result }
}

///|
pub fn LogicVector::slice(
  self : LogicVector,
  msb : Int,
  lsb : Int,
) -> LogicVector {
  let high = if msb > lsb { msb } else { lsb }
  let low = if msb > lsb { lsb } else { msb }
  let result : Array[LogicBit] = []
  for i in low..<(high + 1) {
    result.push(self.bits.get(i).unwrap_or(LogicUnknown))
  }
  { bits: result }
}

///|
pub fn LogicVector::concat(values : Array[LogicVector]) -> LogicVector {
  let result : Array[LogicBit] = []
  for value in values.rev() {
    for bit in value.bits.rev() {
      result.push(bit)
    }
  }
  { bits: result }
}

///|
pub fn LogicVector::repeat(self : LogicVector, count : Int) -> LogicVector {
  let result : Array[LogicBit] = []
  let repeats = if count < 0 { 0 } else { count }
  for _ in 0..<repeats {
    for bit in self.bits {
      result.push(bit)
    }
  }
  { bits: result }
}

///|
pub fn LogicVector::resize(
  self : LogicVector,
  width : Int,
  signed : Bool,
) -> LogicVector {
  let target = if width < 0 { 0 } else { width }
  let result : Array[LogicBit] = []
  for i in 0..<target {
    if i < self.bits.length() {
      result.push(self.bits[i])
    } else if signed && self.bits.length() > 0 {
      result.push(self.bits[self.bits.length() - 1])
    } else {
      result.push(LogicZero)
    }
  }
  { bits: result }
}

///|
pub fn LogicVector::to_text(self : LogicVector) -> String {
  self.bits.rev().map(fn(item) { item.to_char().to_string() }).join("")
}

///|
pub fn LogicVector::to_binary(self : LogicVector) -> String {
  self.to_text()
}

///|
pub fn LogicVector::to_hex(self : LogicVector) -> String {
  let mut output = ""
  let mut index = self.bits.length()
  while index > 0 {
    let low = if index >= 4 { index - 4 } else { 0 }
    let group = self.slice(index - 1, low)
    let mut value = 0
    let mut unknown = false
    for i, bit in group.bits {
      match logic_bit_to_int(bit) {
        Some(v) => value += v * logic_pow2(i)
        None => unknown = true
      }
    }
    output += if unknown {
      "x"
    } else if value < 10 {
      value.to_string()
    } else {
      logic_hex_digit(value)
    }
    index = low
  }
  if output == "" {
    "0"
  } else {
    output
  }
}

///|
pub fn LogicVector::is_known(self : LogicVector) -> Bool {
  self.bits.all(fn(item) { item.is_known() })
}

///|
pub fn LogicVector::has_unknown(self : LogicVector) -> Bool {
  self.bits.any(fn(item) { !item.is_known() })
}

///|
pub fn LogicVector::has_high_z(self : LogicVector) -> Bool {
  self.bits.any(fn(item) { item.is_high_z() })
}

///|
pub fn LogicVector::count_known(self : LogicVector) -> Int {
  self.bits.filter(fn(item) { item.is_known() }).length()
}

///|
pub fn LogicVector::count_ones(self : LogicVector) -> Int {
  self.bits.filter(fn(item) { item == LogicOne }).length()
}

///|
pub fn LogicVector::not(self : LogicVector) -> LogicVector {
  { bits: self.bits.map(fn(item) { item.not() }) }
}

///|
fn logic_vector_zip(
  left : LogicVector,
  right : LogicVector,
  operation : (LogicBit, LogicBit) -> LogicBit,
) -> LogicVector {
  let width = if left.width() > right.width() {
    left.width()
  } else {
    right.width()
  }
  let result : Array[LogicBit] = []
  for i in 0..<width {
    result.push(
      operation(
        left.bits.get(i).unwrap_or(LogicZero),
        right.bits.get(i).unwrap_or(LogicZero),
      ),
    )
  }
  { bits: result }
}

///|
pub fn LogicVector::and_bits(
  self : LogicVector,
  other : LogicVector,
) -> LogicVector {
  logic_vector_zip(self, other, fn(a, b) { a.and_bit(b) })
}

///|
pub fn LogicVector::or_bits(
  self : LogicVector,
  other : LogicVector,
) -> LogicVector {
  logic_vector_zip(self, other, fn(a, b) { a.or_bit(b) })
}

///|
pub fn LogicVector::xor_bits(
  self : LogicVector,
  other : LogicVector,
) -> LogicVector {
  logic_vector_zip(self, other, fn(a, b) { a.xor_bit(b) })
}

///|
pub fn LogicVector::add(self : LogicVector, other : LogicVector) -> LogicVector {
  let width = if self.width() > other.width() {
    self.width()
  } else {
    other.width()
  }
  let result : Array[LogicBit] = []
  let mut carry = LogicZero
  for i in 0..<width {
    let a = self.bits.get(i).unwrap_or(LogicZero)
    let b = other.bits.get(i).unwrap_or(LogicZero)
    if !a.is_known() || !b.is_known() || !carry.is_known() {
      result.push(LogicUnknown)
      carry = LogicUnknown
    } else {
      let sum = (a == LogicOne && b == LogicOne) ||
        (a == LogicOne && carry == LogicOne) ||
        (b == LogicOne && carry == LogicOne)
      let parity = (if a == LogicOne { 1 } else { 0 }) +
        (if b == LogicOne { 1 } else { 0 }) +
        (if carry == LogicOne { 1 } else { 0 })
      result.push(if parity % 2 == 1 { LogicOne } else { LogicZero })
      carry = if sum { LogicOne } else { LogicZero }
    }
  }
  { bits: result }
}

///|
pub fn LogicVector::sub(self : LogicVector, other : LogicVector) -> LogicVector {
  let inverted = other.not()
  self.add(inverted).add(LogicVector::from_int(1, self.width()))
}

///|
pub fn LogicVector::shift_left(self : LogicVector, amount : Int) -> LogicVector {
  let result : Array[LogicBit] = []
  for i in 0..<self.width() {
    if i < amount {
      result.push(LogicZero)
    } else {
      result.push(self.bits[i - amount])
    }
  }
  { bits: result }
}

///|
pub fn LogicVector::shift_right(
  self : LogicVector,
  amount : Int,
  arithmetic : Bool,
) -> LogicVector {
  let result : Array[LogicBit] = []
  let fill = if arithmetic && self.width() > 0 {
    self.bits[self.width() - 1]
  } else {
    LogicZero
  }
  for i in 0..<self.width() {
    let source = i + amount
    result.push(if source < self.width() { self.bits[source] } else { fill })
  }
  { bits: result }
}

///|
pub fn LogicVector::reduce_and(self : LogicVector) -> LogicBit {
  let mut result = LogicOne
  for bit in self.bits {
    result = result.and_bit(bit)
    if result == LogicZero {
      return LogicZero
    }
  }
  result
}

///|
pub fn LogicVector::reduce_or(self : LogicVector) -> LogicBit {
  let mut result = LogicZero
  for bit in self.bits {
    result = result.or_bit(bit)
    if result == LogicOne {
      return LogicOne
    }
  }
  result
}

///|
pub fn LogicVector::reduce_xor(self : LogicVector) -> LogicBit {
  let mut result = LogicZero
  for bit in self.bits {
    result = result.xor_bit(bit)
  }
  result
}

///|
pub fn LogicVector::equal(self : LogicVector, other : LogicVector) -> LogicBit {
  let width = if self.width() > other.width() {
    self.width()
  } else {
    other.width()
  }
  let mut result = LogicOne
  for i in 0..<width {
    let left = self.bits.get(i).unwrap_or(LogicZero)
    let right = other.bits.get(i).unwrap_or(LogicZero)
    if left == LogicUnknown ||
      right == LogicUnknown ||
      left == LogicHighZ ||
      right == LogicHighZ {
      result = LogicUnknown
    } else if left != right {
      return LogicZero
    }
  }
  result
}

///|
pub fn LogicVector::case_equal(
  self : LogicVector,
  other : LogicVector,
) -> LogicBit {
  if self.width() != other.width() {
    return LogicZero
  }
  for i in 0..<self.width() {
    if self.bits[i] != other.bits[i] {
      return LogicZero
    }
  }
  LogicOne
}

///|
pub fn LogicVector::mux(
  condition : LogicBit,
  when_true : LogicVector,
  when_false : LogicVector,
) -> LogicVector {
  match condition {
    LogicOne => when_true
    LogicZero => when_false
    _ => {
      let width = if when_true.width() > when_false.width() {
        when_true.width()
      } else {
        when_false.width()
      }
      let result : Array[LogicBit] = []
      for i in 0..<width {
        result.push(
          when_true.bits
          .get(i)
          .unwrap_or(LogicUnknown)
          .merge(when_false.bits.get(i).unwrap_or(LogicUnknown)),
        )
      }
      { bits: result }
    }
  }
}

///|
pub fn LogicVector::to_uint(self : LogicVector) -> Int? {
  if !self.is_known() {
    return None
  }
  let mut value = 0
  for i, bit in self.bits {
    if bit == LogicOne {
      value += logic_pow2(i)
    }
  }
  Some(value)
}

///|
pub fn LogicVector::to_signed(self : LogicVector) -> Int? {
  match self.to_uint() {
    Some(value) if self.width() > 0 && self.bits[self.width() - 1] == LogicOne =>
      Some(value - logic_pow2(self.width()))
    Some(value) => Some(value)
    None => None
  }
}

///|
pub fn LogicVector::hamming_distance(
  self : LogicVector,
  other : LogicVector,
) -> Int {
  let width = if self.width() > other.width() {
    self.width()
  } else {
    other.width()
  }
  let mut distance = 0
  for i in 0..<width {
    if self.bits.get(i).unwrap_or(LogicUnknown) !=
      other.bits.get(i).unwrap_or(LogicUnknown) {
      distance += 1
    }
  }
  distance
}

///|
pub fn LogicVector::to_json(self : LogicVector) -> String {
  "{\"width\":" +
  self.width().to_string() +
  ",\"binary\":\"" +
  self.to_binary() +
  "\",\"known\":" +
  (if self.is_known() { "true" } else { "false" }) +
  ",\"ones\":" +
  self.count_ones().to_string() +
  "}"
}

///|
pub fn LogicVector::truthy(self : LogicVector) -> LogicBit {
  self.reduce_or()
}

///|
pub fn LogicVector::mask(self : LogicVector, mask : LogicVector) -> LogicVector {
  self.and_bits(mask)
}

///|
pub fn logic_vector_contract() -> String {
  "four_state=0,1,x,z; storage=lsb_first; arithmetic=conservative_unknown; " +
  "literal_bases=bin,oct,dec,hex"
}
