# frozen_string_literal: true

require "minitest/autorun"
require_relative "lexer"
require_relative "parser"

class ParserTest < Minitest::Test
  def parse(source)
    MiniCpp.parse(MiniCpp.tokenize(source))
  end

  def test_operator_precedence_and_function_call
    ast = parse("int main() { print(1 + 2 * 3); return 0; }")

    assert_equal(
      [:program, [
        [:function, "main", [], [:block, [
          [:expr_stmt, [:call, "print", [
            [:add, [:int, 1], [:mul, [:int, 2], [:int, 3]]]
          ]]],
          [:return, [:int, 0]]
        ]]]
      ]],
      ast
    )
  end

  def test_declaration_assignment_and_comparison
    ast = parse("int main() { int x = 1; x = x + 2; if (x == 3) { print(x); } else { print(0); } return x; }")
    statements = ast[1][0][3][1]

    assert_equal [:var_decl, "x", [:int, 1]], statements[0]
    assert_equal [:expr_stmt, [:assign, "x", [:add, [:var, "x"], [:int, 2]]]], statements[1]
    assert_equal :if, statements[2][0]
    assert_equal [:eq, [:var, "x"], [:int, 3]], statements[2][1]
    assert_equal [:return, [:var, "x"]], statements[3]
  end

  def test_parses_all_examples
    Dir[File.join(__dir__, "examples", "*.mcpp")].each do |path|
      assert_equal :program, parse(File.read(path))[0], path
    end
  end

  def test_rejects_invalid_assignment_target
    error = assert_raises(RuntimeError) { parse("int main() { 1 = 2; }") }

    assert_match(/左辺には変数/, error.message)
  end
end
