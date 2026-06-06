# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "virtual_machine"

class CompilerTest < Minitest::Test
  def test_compiles_integer
    compiler = Compiler.new

    compiler.compile_expr([:int, 42])

    assert_equal [[:push, 42]], compiler.code
  end

  def test_compiles_nested_arithmetic_in_stack_order
    compiler = Compiler.new
    ast = [:add, [:int, 1], [:mul, [:int, 2], [:int, 3]]]

    compiler.compile_expr(ast)

    assert_equal [
      [:push, 1],
      [:push, 2],
      [:push, 3],
      [:mul],
      [:add]
    ], compiler.code
  end

  def test_compiles_variable_and_comparison
    compiler = Compiler.new

    compiler.compile_expr([:lt, [:var, "x"], [:int, 10]])

    assert_equal [[:get_local, 0], [:push, 10], [:lt]], compiler.code
    assert_equal ["x"], compiler.locals
  end

  def test_assigns_stable_local_indexes
    compiler = Compiler.new

    assert_equal 0, compiler.local_index("x")
    assert_equal 1, compiler.local_index("y")
    assert_equal 0, compiler.local_index("x")
    assert_equal 2, compiler.local_count
  end

  def test_compiles_if_with_backpatched_jumps
    compiler = Compiler.new
    node = [
      :if,
      [:var, "condition"],
      [[:assign, "result", [:int, 1]]],
      [[:assign, "result", [:int, 2]]]
    ]

    compiler.compile_stmt(node)

    assert_equal [
      [:get_local, 0],
      [:jump_if_false, 5],
      [:push, 1],
      [:set_local, 1],
      [:jump, 7],
      [:push, 2],
      [:set_local, 1]
    ], compiler.code
  end

  def test_compiles_while_with_backward_jump
    compiler = Compiler.new
    node = [
      :while,
      [:lt, [:var, "i"], [:int, 3]],
      [[:assign, "i", [:add, [:var, "i"], [:int, 1]]]]
    ]

    compiler.compile_stmt(node)

    assert_equal [
      [:get_local, 0],
      [:push, 3],
      [:lt],
      [:jump_if_false, 9],
      [:get_local, 0],
      [:push, 1],
      [:add],
      [:set_local, 0],
      [:jump, 0]
    ], compiler.code
  end

  def test_expression_statement_discards_its_value
    compiler = Compiler.new

    compiler.compile_stmt([:add, [:int, 1], [:int, 2]])

    assert_equal [[:push, 1], [:push, 2], [:add], [:pop]], compiler.code
  end

  def test_compiles_call_and_return
    compiler = Compiler.new

    compiler.compile_stmt([:return, [:call, "add", [[:int, 1], [:int, 2]]]])

    assert_equal [
      [:push, 1],
      [:push, 2],
      [:call, "add", 2],
      [:ret]
    ], compiler.code
  end

  def test_compile_function_assigns_parameters_first
    function = compile_function(["a", "b"], [[:return, [:add, [:var, "a"], [:var, "b"]]]])

    assert_equal 2, function[:nparams]
    assert_equal 2, function[:nlocals]
    assert_equal [:get_local, 0], function[:code][0]
    assert_equal [:get_local, 1], function[:code][1]
  end

  def test_compile_program_builds_function_table
    program = {
      defs: [["identity", ["value"], [[:return, [:var, "value"]]]]],
      main: [[:return, [:call, "identity", [[:int, 3]]]]]
    }

    functions = compile_program(program)

    assert_equal ["identity", "main"], functions.keys
    assert_equal 1, functions["identity"][:nparams]
    assert_equal 0, functions["main"][:nparams]
  end

  def test_rejects_unknown_expression
    error = assert_raises(ArgumentError) do
      Compiler.new.compile_expr([:def, "function", [], []])
    end

    assert_match(/unknown expression/, error.message)
  end
end

class VMTest < Minitest::Test
  def setup
    @output = StringIO.new
  end

  def test_runs_compiled_expression
    compiler = Compiler.new
    compiler.compile_expr([:add, [:int, 1], [:mul, [:int, 2], [:int, 3]]])

    assert_equal 7, VM.new(compiler.code, output: @output).run
  end

  def test_preserves_operand_order_for_subtraction_and_division
    code = [
      [:push, 10], [:push, 3], [:sub],
      [:push, 2], [:div]
    ]

    assert_equal 3, VM.new(code, output: @output).run
  end

  def test_runs_comparisons
    assert_equal 1, VM.new([[:push, 1], [:push, 2], [:lt]], output: @output).run
    assert_equal 1, VM.new([[:push, 2], [:push, 1], [:gt]], output: @output).run
    assert_equal 1, VM.new([[:push, 2], [:push, 2], [:eq]], output: @output).run
  end

  def test_gets_and_sets_local_variables
    vm = VM.new([[:push, 42], [:set_local, 0], [:pop], [:get_local, 0]], 1, output: @output)

    assert_equal 42, vm.run
    assert_equal [42], vm.locals
  end

  def test_runs_if_control_flow
    code = [
      [:push, 0],
      [:jump_if_false, 4],
      [:push, 1],
      [:jump, 5],
      [:push, 2]
    ]

    assert_equal 2, VM.new(code, output: @output).run
  end

  def test_compiles_and_runs_factorial_loop
    program = [
      [:assign, "i", [:int, 1]],
      [:assign, "result", [:int, 1]],
      [:while, [:lt, [:var, "i"], [:int, 6]], [
        [:assign, "result", [:mul, [:var, "result"], [:var, "i"]]],
        [:assign, "i", [:add, [:var, "i"], [:int, 1]]]
      ]]
    ]
    compiler = Compiler.new
    program.each { |statement| compiler.compile_stmt(statement) }

    vm = VM.new(compiler.code, compiler.local_count, output: @output)
    vm.run

    assert_equal 120, vm.locals[compiler.local_index("result")]
  end

  def test_calls_user_defined_function
    functions = {
      "main" => {
        code: [[:push, 2], [:push, 3], [:call, "add", 2], [:ret]],
        nparams: 0,
        nlocals: 0
      },
      "add" => {
        code: [[:get_local, 0], [:get_local, 1], [:add], [:ret]],
        nparams: 2,
        nlocals: 2
      }
    }

    assert_equal 5, VM.new(functions, output: @output).run
  end

  def test_recursive_fibonacci_uses_call_frames
    program = {
      defs: [
        ["fib", ["n"], [
          [:if, [:lt, [:var, "n"], [:int, 2]],
            [[:return, [:var, "n"]]],
            [[:return, [:add,
              [:call, "fib", [[:sub, [:var, "n"], [:int, 1]]]],
              [:call, "fib", [[:sub, [:var, "n"], [:int, 2]]]]]]]]
        ]]
      ],
      main: [[:return, [:call, "fib", [[:int, 10]]]]]
    }
    vm = VM.new(compile_program(program), output: @output)

    assert_equal 55, vm.run
    assert_operator vm.max_frame_depth, :>, 2
  end

  def test_builtin_puts_prints_and_returns_value
    program = {
      defs: [],
      main: [[:return, [:call, "puts", [[:int, 42]]]]]
    }

    assert_equal 42, VM.new(compile_program(program), output: @output).run
    assert_equal "42\n", @output.string
  end

  def test_rejects_undefined_function
    functions = {
      "main" => { code: [[:call, "missing", 0], [:ret]], nparams: 0, nlocals: 0 }
    }

    assert_raises(NameError) { VM.new(functions, output: @output).run }
  end

  def test_rejects_wrong_number_of_arguments
    functions = {
      "main" => { code: [[:call, "one", 0], [:ret]], nparams: 0, nlocals: 0 },
      "one" => { code: [[:push, 0], [:ret]], nparams: 1, nlocals: 1 }
    }

    assert_raises(ArgumentError) { VM.new(functions, output: @output).run }
  end

  def test_print_removes_and_displays_top_value
    result = VM.new([[:push, 7], [:print]], output: @output).run

    assert_nil result
    assert_equal "7\n", @output.string
  end

  def test_pop_discards_top_value
    code = [[:push, 1], [:push, 2], [:pop]]

    assert_equal 1, VM.new(code, output: @output).run
  end

  def test_rejects_unknown_instruction
    error = assert_raises(ArgumentError) do
      VM.new([[:unknown]], output: @output).run
    end

    assert_match(/unknown instruction/, error.message)
  end

  def test_rejects_stack_underflow
    assert_raises(RuntimeError) do
      VM.new([[:add]], output: @output).run
    end
  end
end
