///|
test "substitute_matrix_text: simple variable replacement" {
  let values : Map[String, String] = { "os": "ubuntu", "node": "20" }
  let result = substitute_matrix_text(
    "echo ${{ matrix.os }} ${{ matrix.node }}", values,
  )
  @debug.debug_inspect(
    result,
    content=(
      #|"echo ubuntu 20"
    ),
  )
}

///|
test "substitute_matrix_text: value containing single quotes" {
  let values : Map[String, String] = { "msg": "it's alive" }
  let result = substitute_matrix_text("echo '${{ matrix.msg }}'", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo 'it's alive'"
    ),
  )
}

///|
test "substitute_matrix_text: value containing double quotes" {
  let values : Map[String, String] = { "arg": "say \"hello\"" }
  let result = substitute_matrix_text("echo ${{ matrix.arg }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo say \"hello\""
    ),
  )
}

///|
test "substitute_matrix_text: value containing dollar sign" {
  let values : Map[String, String] = { "price": "$100" }
  let result = substitute_matrix_text("echo ${{ matrix.price }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo $100"
    ),
  )
}

///|
test "substitute_matrix_text: value containing braces" {
  let values : Map[String, String] = { "json": "{\"key\":\"val\"}" }
  let result = substitute_matrix_text("echo ${{ matrix.json }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo {\"key\":\"val\"}"
    ),
  )
}

///|
test "substitute_matrix_text: value containing closing braces }}" {
  let values : Map[String, String] = { "tpl": "x}}" }
  let result = substitute_matrix_text("echo ${{ matrix.tpl }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo x}}"
    ),
  )
}

///|
test "substitute_matrix_text: value containing expression syntax ${{" {
  let values : Map[String, String] = { "expr": "${{ env.FOO }}" }
  let result = substitute_matrix_text("echo ${{ matrix.expr }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo ${{ env.FOO }}"
    ),
  )
}

///|
test "substitute_matrix_text: value containing newline" {
  let values : Map[String, String] = { "multi": "line1\nline2" }
  let result = substitute_matrix_text("echo ${{ matrix.multi }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo line1\nline2"
    ),
  )
}

///|
test "substitute_matrix_text: value containing backslash" {
  let values : Map[String, String] = { "path": "C:\\Users\\test" }
  let result = substitute_matrix_text("echo ${{ matrix.path }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo C:\\Users\\test"
    ),
  )
}

///|
test "substitute_matrix_text: empty value" {
  let values : Map[String, String] = { "empty": "" }
  let result = substitute_matrix_text("echo '${{ matrix.empty }}'", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo ''"
    ),
  )
}

///|
test "substitute_matrix_text: missing key returns empty" {
  let values : Map[String, String] = Map([])
  let result = substitute_matrix_text("echo ${{ matrix.missing }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo "
    ),
  )
}

///|
test "substitute_matrix_text: complex expression preserves ${{ }}" {
  let values : Map[String, String] = { "os": "ubuntu" }
  let result = substitute_matrix_text(
    "echo ${{ matrix.os == 'ubuntu' }}", values,
  )
  @debug.debug_inspect(
    result,
    content=(
      #|"echo ${{ 'ubuntu' == 'ubuntu' }}"
    ),
  )
}

///|
test "substitute_matrix_text: multiple matrix refs in one expression" {
  let values : Map[String, String] = { "a": "x", "b": "y" }
  let result = substitute_matrix_text("${{ matrix.a == matrix.b }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"${{ 'x' == 'y' }}"
    ),
  )
}

///|
test "substitute_matrix_text: non-matrix expression is preserved" {
  let values : Map[String, String] = { "os": "ubuntu" }
  let result = substitute_matrix_text("${{ github.ref }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"${{ github.ref }}"
    ),
  )
}

///|
test "substitute_matrix_text: adjacent expressions" {
  let values : Map[String, String] = { "a": "1", "b": "2" }
  let result = substitute_matrix_text("${{ matrix.a }}-${{ matrix.b }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"1-2"
    ),
  )
}

///|
test "substitute_matrix_text: unclosed expression" {
  let values : Map[String, String] = { "x": "val" }
  let result = substitute_matrix_text("echo ${{ matrix.x", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo ${{ matrix.x"
    ),
  )
}

///|
test "substitute_matrix_text: key with hyphen" {
  let values : Map[String, String] = { "node-version": "20" }
  let result = substitute_matrix_text("echo ${{ matrix.node-version }}", values)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo 20"
    ),
  )
}

///|
test "substitute_inputs_text: simple replacement" {
  let inputs : Map[String, String] = { "name": "world" }
  let result = substitute_inputs_text("echo ${{ inputs.name }}", inputs)
  @debug.debug_inspect(
    result,
    content=(
      #|"echo world"
    ),
  )
}

///|
test "substitute_inputs_text: value with special shell chars" {
  let inputs : Map[String, String] = { "cmd": "echo $(whoami)" }
  let result = substitute_inputs_text("run: ${{ inputs.cmd }}", inputs)
  @debug.debug_inspect(
    result,
    content=(
      #|"run: echo $(whoami)"
    ),
  )
}

///|
test "resolve_composite_output_expression: standard pattern" {
  let result = resolve_composite_output_expression(
    "${{ steps.write.outputs.value }}", "emit",
  )
  @debug.debug_inspect(
    result,
    content=(
      #|"emit__write:value"
    ),
  )
}

///|
test "resolve_composite_output_expression: non-steps expression" {
  let result = resolve_composite_output_expression("${{ env.FOO }}", "emit")
  @debug.debug_inspect(
    result,
    content=(
      #|"${{ env.FOO }}"
    ),
  )
}

///|
test "resolve_composite_output_expression: plain text" {
  let result = resolve_composite_output_expression("hello", "emit")
  @debug.debug_inspect(
    result,
    content=(
      #|"hello"
    ),
  )
}

///|
test "resolve_composite_output_expression: steps without outputs" {
  let result = resolve_composite_output_expression(
    "${{ steps.write.outcome }}", "emit",
  )
  @debug.debug_inspect(
    result,
    content=(
      #|"${{ steps.write.outcome }}"
    ),
  )
}

///|
test "matrix_expr_name: simple key" {
  @debug.debug_inspect(matrix_expr_name(" matrix.os "), content="Some(\"os\")")
}

///|
test "matrix_expr_name: key with hyphen" {
  @debug.debug_inspect(
    matrix_expr_name(" matrix.node-version "),
    content="Some(\"node-version\")",
  )
}

///|
test "matrix_expr_name: rejects complex expression" {
  @debug.debug_inspect(
    matrix_expr_name(" matrix.os == 'ubuntu' "),
    content="None",
  )
}

///|
test "matrix_expr_name: rejects expression with spaces in key" {
  @debug.debug_inspect(matrix_expr_name(" matrix.os name "), content="None")
}

///|
test "matrix_expr_name: non-matrix prefix" {
  @debug.debug_inspect(matrix_expr_name(" github.ref "), content="None")
}

///|
test "substitute_matrix_refs_in_expr: injection attempt is quoted" {
  let values : Map[String, String] = { "name": "'true' || always()" }
  let result = substitute_matrix_refs_in_expr(" matrix.name == 'safe' ", values)
  // The injected value is wrapped in quotes, preventing expression injection
  @debug.debug_inspect(
    result,
    content=(
      #|" '''true'' || always()' == 'safe' "
    ),
  )
}

///|
test "substitute_matrix_refs_in_expr: value with single quotes is escaped" {
  let values : Map[String, String] = { "msg": "it's" }
  let result = substitute_matrix_refs_in_expr(" matrix.msg ", values)
  @debug.debug_inspect(
    result,
    content=(
      #|" 'it''s' "
    ),
  )
}

///|
test "quote_expr_string_literal: simple value" {
  @debug.debug_inspect(
    quote_expr_string_literal("hello"),
    content=(
      #|"'hello'"
    ),
  )
}

///|
test "quote_expr_string_literal: empty string" {
  @debug.debug_inspect(
    quote_expr_string_literal(""),
    content=(
      #|"''"
    ),
  )
}

///|
test "quote_expr_string_literal: contains single quote" {
  @debug.debug_inspect(
    quote_expr_string_literal("it's"),
    content=(
      #|"'it''s'"
    ),
  )
}

///|
test "quote_expr_string_literal: contains double quote" {
  @debug.debug_inspect(
    quote_expr_string_literal("say \"hi\""),
    content=(
      #|"'say \"hi\"'"
    ),
  )
}

///|
test "is_path_traversal: safe relative path" {
  @debug.debug_inspect(
    is_path_traversal("./.github/actions/emit"),
    content="false",
  )
}

///|
test "is_path_traversal: safe nested path" {
  @debug.debug_inspect(
    is_path_traversal(".github/actions/emit"),
    content="false",
  )
}

///|
test "is_path_traversal: parent escape" {
  @debug.debug_inspect(is_path_traversal("../../outside"), content="true")
}

///|
test "is_path_traversal: hidden parent escape" {
  @debug.debug_inspect(is_path_traversal("./foo/../../.."), content="true")
}

///|
test "is_path_traversal: absolute path" {
  @debug.debug_inspect(is_path_traversal("/etc/passwd"), content="true")
}

///|
test "is_path_traversal: dot-dot at end" {
  @debug.debug_inspect(is_path_traversal("actions/.."), content="false")
}

///|
test "is_path_traversal: single dot" {
  @debug.debug_inspect(is_path_traversal("."), content="false")
}
