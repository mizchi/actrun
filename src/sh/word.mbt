///| Word parsing - converts raw word strings into WordPart structures

///|
/// Parse a word string into Word with parts
pub fn parse_word_parts(s : String) -> Word {
  let parts : Array[WordPart] = []
  let chars = string_to_chars(s)
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\'' {
      // Single-quoted string - find closing quote
      let start = i + 1
      i += 1
      while i < chars.length() && chars[i] != '\'' {
        i += 1
      }
      let content = chars_to_string(chars, start, i)
      parts.push(SingleQuoted(content))
      i += 1 // skip closing quote
    } else if c == '"' {
      // Double-quoted string - parse with expansion
      let inner_parts = parse_double_quoted(chars, i + 1)
      for p in inner_parts.0 {
        parts.push(p)
      }
      i = inner_parts.1 + 1 // skip past closing quote
    } else if c == '$' {
      // Variable or special
      let var_result = parse_variable(chars, i)
      parts.push(var_result.0)
      i = var_result.1
    } else if c == '\\' && i + 1 < chars.length() {
      // Escape sequence
      i += 1
      let buf = StringBuilder::new()
      buf.write_char(chars[i])
      parts.push(Literal(buf.to_string()))
      i += 1
    } else {
      // Regular literal - collect consecutive literal chars
      let start = i
      while i < chars.length() {
        let ch = chars[i]
        if ch == '\'' || ch == '"' || ch == '$' || ch == '\\' {
          break
        }
        i += 1
      }
      if i > start {
        parts.push(Literal(chars_to_string(chars, start, i)))
      }
    }
  }
  if parts.is_empty() {
    Word::literal("")
  } else {
    Word::new(parts)
  }
}

///|
/// Parse inside double quotes, returns (parts, end_position)
fn parse_double_quoted(
  chars : Array[Char],
  start : Int,
) -> (Array[WordPart], Int) {
  let parts : Array[WordPart] = []
  let mut i = start
  let buf = StringBuilder::new()
  fn flush_literal() -> Unit {
    if buf.to_string().length() > 0 {
      parts.push(Literal(buf.to_string()))
      buf.reset()
    }
  }

  while i < chars.length() && chars[i] != '"' {
    let c = chars[i]
    if c == '$' {
      flush_literal()
      let var_result = parse_variable(chars, i)
      parts.push(var_result.0)
      i = var_result.1
    } else if c == '\\' && i + 1 < chars.length() {
      let next = chars[i + 1]
      // In double quotes, only these escapes are special
      match next {
        '$' | '`' | '"' | '\\' | '\n' => {
          buf.write_char(next)
          i += 2
        }
        _ => {
          buf.write_char('\\')
          buf.write_char(next)
          i += 2
        }
      }
    } else if c == '`' {
      // Backtick command substitution - for now, treat as literal
      flush_literal()
      let end_pos = find_char_from(chars, '`', i + 1)
      match end_pos {
        Some(e) => {
          let cmd_str = chars_to_string(chars, i + 1, e)
          // Parse the command inside backticks
          // For now, just store as literal with backticks
          parts.push(Literal("`" + cmd_str + "`"))
          i = e + 1
        }
        None => {
          buf.write_char(c)
          i += 1
        }
      }
    } else {
      buf.write_char(c)
      i += 1
    }
  }
  flush_literal()
  (parts, i)
}

///|
/// Parse a variable starting at position i (which is $)
fn parse_variable(chars : Array[Char], start : Int) -> (WordPart, Int) {
  let mut i = start + 1 // skip $
  if i >= chars.length() {
    // Just a bare $ at end
    return (Literal("$"), i)
  }
  let c = chars[i]

  // Special single-character variables
  match c {
    '?'
    | '$'
    | '!'
    | '@'
    | '*'
    | '#'
    | '-'
    | '0'
    | '1'
    | '2'
    | '3'
    | '4'
    | '5'
    | '6'
    | '7'
    | '8'
    | '9' => return (SpecialVar(c), i + 1)
    _ => ()
  }

  // ${...} form
  if c == '{' {
    i += 1
    let name_start = i
    // Find closing }
    while i < chars.length() && chars[i] != '}' {
      // TODO: Handle ${var:-default}, ${var:+alt}, etc.
      i += 1
    }
    let name = chars_to_string(chars, name_start, i)
    if i < chars.length() {
      i += 1 // skip }
    }
    return (Variable(name), i)
  }

  // $(...) command substitution
  if c == '(' {
    i += 1
    // Check for $(( )) arithmetic
    if i < chars.length() && chars[i] == '(' {
      // Arithmetic expansion $((expr))
      i += 1
      let expr_start = i
      let mut depth = 1
      while i < chars.length() && depth > 0 {
        if i + 1 < chars.length() && chars[i] == ')' && chars[i + 1] == ')' {
          depth -= 1
          if depth == 0 {
            break
          }
        }
        i += 1
      }
      let expr = chars_to_string(chars, expr_start, i)
      i += 2 // skip ))
      return (ArithSub(expr), i)
    } else {
      // Command substitution $(cmd)
      let cmd_start = i
      let mut depth = 1
      while i < chars.length() && depth > 0 {
        if chars[i] == '(' {
          depth += 1
        } else if chars[i] == ')' {
          depth -= 1
        }
        if depth > 0 {
          i += 1
        }
      }
      let cmd_str = chars_to_string(chars, cmd_start, i)
      if i < chars.length() {
        i += 1 // skip )
      }
      // TODO: Actually parse the command
      // For now, store as literal placeholder
      return (Literal("$(" + cmd_str + ")"), i)
    }
  }

  // Regular variable name: $NAME
  if is_alpha(c) || c == '_' {
    let name_start = i
    while i < chars.length() {
      let ch = chars[i]
      if is_alnum(ch) || ch == '_' {
        i += 1
      } else {
        break
      }
    }
    let name = chars_to_string(chars, name_start, i)
    return (Variable(name), i)
  }

  // Just a bare $ followed by something else
  (Literal("$"), start + 1)
}

// Helper functions

///|
fn string_to_chars(s : String) -> Array[Char] {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  chars
}

///|
fn chars_to_string(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end && i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn find_char_from(chars : Array[Char], target : Char, start : Int) -> Int? {
  for i = start; i < chars.length(); i = i + 1 {
    if chars[i] == target {
      return Some(i)
    }
  }
  None
}
