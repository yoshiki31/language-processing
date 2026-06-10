# frozen_string_literal: true

require "minitest/autorun"
require_relative "lexer"
require_relative "parser"
require_relative "compiler"
require_relative "virtual_machine"

class VirtualMachineTest < Minitest::Test
  def compile(source)
    ast = MiniCpp.parse(MiniCpp.tokenize(source))
    MiniCpp.compile(ast)
  end

  def execute(source)
    ast = MiniCpp.parse(MiniCpp.tokenize(source))
    result = nil
    output, = capture_io { result = MiniCpp.execute(ast) }
    [result, output]
  end

  def test_compiles_expression_to_stack_machine_instructions
    functions = compile("int main() { puts(1 + 2 * 3); return 0; }")

    assert_equal(
      [
        [:push, 1], [:push, 2], [:push, 3], [:mul], [:add],
        [:call, "puts", 1], [:pop], [:push, 0], [:ret],
        [:ret]
      ],
      functions.fetch("main").fetch(:code)
    )
  end

  def test_compiler_can_compile_an_expression_directly
    compiler = MiniCpp::Compiler.new

    compiler.compile_expr([:add, [:int, 1], [:int, 2]])

    assert_equal [[:push, 1], [:push, 2], [:add]], compiler.code
  end

  def test_empty_expression_sequence_has_value_zero
    compiler = MiniCpp::Compiler.new

    compiler.compile_exprs([])

    assert_equal [[:push, 0]], compiler.code
  end

  def test_executes_arithmetic_variables_and_control_flow
    source = <<~MINICPP
      int main() {
        int i = 1;
        int result = 1;
        while (i < 6) {
          result = result * i;
          i = i + 1;
        }
        if (result == 120) {
          puts(result);
        } else {
          puts(0);
        }
        return result;
      }
    MINICPP

    assert_equal [120, "120\n"], execute(source)
  end

  def test_executes_user_function_and_recursion
    source = <<~MINICPP
      int factorial(int n) {
        if (n == 0) {
          return 1;
        }
        return n * factorial(n - 1);
      }

      int main() {
        puts(factorial(5));
        return 0;
      }
    MINICPP

    assert_equal [0, "120\n"], execute(source)
  end

  def test_assignment_introduces_a_local_variable
    functions = compile("int main() { x = 1; return x; }")

    assert_equal 1, functions.fetch("main").fetch(:nlocals)
  end

  def test_rejects_wrong_number_of_arguments
    error = assert_raises(RuntimeError) do
      execute("int main() { puts(1, 2); return 0; }")
    end

    assert_match(/引数の個数/, error.message)
  end
end
