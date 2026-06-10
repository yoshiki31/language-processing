# frozen_string_literal: true

require "minitest/autorun"
require_relative "lexer"

class LexerTest < Minitest::Test
  def test_tokenizes_minicpp_source
    source = "int main() { int abc = 12; return abc; }"

    assert_equal(
      [
        [:ident, "int"],
        [:ident, "main"],
        [:op, "("],
        [:op, ")"],
        [:op, "{"],
        [:ident, "int"],
        [:ident, "abc"],
        [:op, "="],
        [:int, 12],
        [:op, ";"],
        [:ident, "return"],
        [:ident, "abc"],
        [:op, ";"],
        [:op, "}"],
        [:eof, nil]
      ],
      MiniCpp.tokenize(source)
    )
  end

  def test_uses_longest_match_for_equal_operator
    assert_equal(
      [[:ident, "a"], [:op, "=="], [:ident, "b"], [:eof, nil]],
      MiniCpp.tokenize("a == b")
    )
  end

  def test_skips_whitespace_and_line_comments
    source = "int x; // comment\nreturn x;"

    assert_equal(
      [
        [:ident, "int"], [:ident, "x"], [:op, ";"],
        [:ident, "return"], [:ident, "x"], [:op, ";"],
        [:eof, nil]
      ],
      MiniCpp.tokenize(source)
    )
  end

  def test_rejects_unknown_characters
    error = assert_raises(RuntimeError) { MiniCpp.tokenize("int x = @;") }

    assert_match(/字句解析エラー/, error.message)
  end
end
