# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "interpreter"

class InterpreterTest < Minitest::Test
  def setup
    @output = StringIO.new
    @interpreter = Interpreter.new(output: @output)
  end

  def test_evaluates_integer
    assert_equal 42, @interpreter.eval([:int, 42])
  end

  def test_evaluates_arithmetic
    assert_equal 5, @interpreter.eval([:add, [:int, 2], [:int, 3]])
    assert_equal(-1, @interpreter.eval([:sub, [:int, 2], [:int, 3]]))
    assert_equal 6, @interpreter.eval([:mul, [:int, 2], [:int, 3]])
    assert_equal 3, @interpreter.eval([:div, [:int, 7], [:int, 2]])
  end

  def test_evaluates_nested_ast
    ast = [:add, [:int, 1], [:mul, [:int, 2], [:int, 3]]]

    assert_equal 7, @interpreter.eval(ast)
  end

  def test_assigns_and_reads_variable
    env = {}

    assert_equal 10, @interpreter.eval([:assign, "x", [:int, 10]], env)
    assert_equal 11, @interpreter.eval([:add, [:var, "x"], [:int, 1]], env)
  end

  def test_rejects_undefined_variable
    error = assert_raises(NameError) do
      @interpreter.eval([:var, "missing"], {})
    end

    assert_match(/undefined variable: missing/, error.message)
  end

  def test_comparisons_return_integer_booleans
    assert_equal 1, @interpreter.eval([:lt, [:int, 1], [:int, 2]])
    assert_equal 0, @interpreter.eval([:lt, [:int, 2], [:int, 1]])
    assert_equal 1, @interpreter.eval([:gt, [:int, 2], [:int, 1]])
    assert_equal 0, @interpreter.eval([:gt, [:int, 1], [:int, 2]])
    assert_equal 1, @interpreter.eval([:eq, [:int, 2], [:int, 2]])
    assert_equal 0, @interpreter.eval([:eq, [:int, 2], [:int, 3]])
  end

  def test_if_evaluates_only_selected_branch
    env = {}
    node = [
      :if,
      [:int, 1],
      [[:assign, "result", [:int, 10]]],
      [[:assign, "result", [:var, "undefined"]]]
    ]

    assert_equal 10, @interpreter.eval(node, env)
    assert_equal 10, env["result"]
  end

  def test_if_without_else_returns_nil_when_condition_is_false
    assert_nil @interpreter.eval([:if, [:int, 0], [[:int, 1]], nil], {})
  end

  def test_while_calculates_factorial
    program = [
      [:assign, "i", [:int, 1]],
      [:assign, "result", [:int, 1]],
      [:while, [:lt, [:var, "i"], [:int, 6]], [
        [:assign, "result", [:mul, [:var, "result"], [:var, "i"]]],
        [:assign, "i", [:add, [:var, "i"], [:int, 1]]]
      ]],
      [:call, "puts", [[:var, "result"]]]
    ]

    @interpreter.run(program)

    assert_equal "120\n", @output.string
  end

  def test_eval_exprs_returns_last_value
    env = {}
    expressions = [[:assign, "x", [:int, 4]], [:mul, [:var, "x"], [:int, 3]]]

    assert_equal 12, @interpreter.eval_exprs(expressions, env)
  end

  def test_def_registers_function_without_running_body
    definition = [:def, "unused", [], [[:var, "undefined"]]]

    assert_nil @interpreter.eval(definition)
  end

  def test_calls_user_defined_function
    program = [
      [:def, "add", ["a", "b"], [[:add, [:var, "a"], [:var, "b"]]]],
      [:call, "add", [[:int, 2], [:int, 3]]]
    ]

    assert_equal 5, @interpreter.run(program)
  end

  def test_function_arguments_are_evaluated_in_callers_environment
    program = [
      [:def, "double", ["value"], [[:mul, [:var, "value"], [:int, 2]]]],
      [:assign, "x", [:int, 4]],
      [:call, "double", [[:add, [:var, "x"], [:int, 1]]]]
    ]

    assert_equal 10, @interpreter.run(program)
  end

  def test_function_has_an_independent_local_environment
    program = [
      [:def, "change_x", [], [[:assign, "x", [:int, 99]]]],
      [:assign, "x", [:int, 1]],
      [:call, "change_x", []],
      [:var, "x"]
    ]

    assert_equal 1, @interpreter.run(program)
  end

  def test_recursive_fibonacci
    program = [
      [:def, "fib", ["n"], [
        [:if, [:lt, [:var, "n"], [:int, 2]],
          [[:var, "n"]],
          [[:add,
            [:call, "fib", [[:sub, [:var, "n"], [:int, 1]]]],
            [:call, "fib", [[:sub, [:var, "n"], [:int, 2]]]]]]]
      ]],
      [:call, "fib", [[:int, 10]]]
    ]

    assert_equal 55, @interpreter.run(program)
  end

  def test_puts_returns_and_prints_its_argument
    result = @interpreter.eval([:call, "puts", [[:int, 42]]])

    assert_equal 42, result
    assert_equal "42\n", @output.string
  end

  def test_rejects_undefined_function
    error = assert_raises(NameError) do
      @interpreter.eval([:call, "missing", []])
    end

    assert_match(/undefined function: missing/, error.message)
  end

  def test_rejects_wrong_number_of_arguments
    @interpreter.eval([:def, "identity", ["value"], [[:var, "value"]]])

    error = assert_raises(ArgumentError) do
      @interpreter.eval([:call, "identity", []])
    end

    assert_match(/wrong number of arguments: identity/, error.message)
  end

  def test_run_calls_puts_in_order
    program = [
      [:call, "puts", [[:add, [:int, 1], [:int, 2]]]],
      [:call, "puts", [[:div, [:int, 8], [:int, 2]]]]
    ]

    @interpreter.run(program)

    assert_equal "3\n4\n", @output.string
  end

  def test_print_is_not_a_final_node
    error = assert_raises(ArgumentError) do
      @interpreter.eval([:print, [:int, 1]])
    end

    assert_match(/unknown node/, error.message)
  end

  def test_rejects_unknown_node
    error = assert_raises(ArgumentError) do
      @interpreter.eval([:unknown, [:int, 1], [:int, 2]])
    end

    assert_match(/unknown node/, error.message)
  end

  def test_rejects_malformed_node
    assert_raises(ArgumentError) { @interpreter.eval([:add, [:int, 1]]) }
  end
end
