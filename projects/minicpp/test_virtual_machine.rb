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

  def test_value_distinguishes_ints_from_objects
    object = Object.new

    int_value = MiniCpp::Value.int(42)
    object_value = MiniCpp::Value.object(object)

    assert int_value.int?
    refute int_value.object?
    assert_equal 42, int_value.as_int

    assert object_value.object?
    refute object_value.int?
    assert_same object, object_value.as_object
  end

  def test_compiles_int_array_operations
    functions = compile("int main() { int[] a = new int[2]; a[1] = 9; return a[1]; }")

    assert_equal(
      [
        [:push, 2], [:new_int_array], [:set_local, 0], [:pop],
        [:get_local, 0], [:push, 1], [:push, 9], [:array_set], [:pop],
        [:get_local, 0], [:push, 1], [:array_get], [:ret],
        [:ret]
      ],
      functions.fetch("main").fetch(:code)
    )
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

  def test_executes_int_array_creation_access_and_assignment
    source = <<~MINICPP
      int main() {
        int[] values = new int[3];
        values[0] = 10;
        values[1] = values[0] + 5;
        puts(values[2]);
        return values[0] + values[1];
      }
    MINICPP

    assert_equal [25, "0\n"], execute(source)
  end

  def test_allocates_int_arrays_on_vm_heap
    functions = compile("int main() { int[] values = new int[2]; values[0] = 7; return values[0]; }")
    vm = MiniCpp::VM.new(functions)

    assert_equal 7, vm.run
    assert_equal 1, vm.heap.size
  end

  def test_collects_unreferenced_int_arrays
    source = <<~MINICPP
      int main() {
        int[] first = new int[1];
        first[0] = 1;
        int[] second = new int[1];
        second[0] = 2;
        first = second;
        gc();
        return first[0];
      }
    MINICPP
    vm = MiniCpp::VM.new(compile(source))

    assert_equal 2, vm.run
    assert_equal 1, vm.heap.size
  end

  def test_gc_after_program_finish_collects_arrays_without_roots
    vm = MiniCpp::VM.new(compile("int main() { int[] values = new int[1]; return 0; }"))

    assert_equal 0, vm.run
    assert_equal 1, vm.heap.size
    assert_equal 1, vm.gc
    assert_equal 0, vm.heap.size
  end

  def test_passes_int_array_to_user_function
    source = <<~MINICPP
      int second(int[] values) {
        return values[1];
      }

      int main() {
        int[] values = new int[2];
        values[1] = 8;
        return second(values);
      }
    MINICPP

    assert_equal [8, ""], execute(source)
  end

  def test_stores_array_references_inside_arrays
    source = <<~MINICPP
      int main() {
        int[][] arrays = new int[1];
        int[] values = new int[1];
        values[0] = 42;
        arrays[0] = values;
        return arrays[0][0];
      }
    MINICPP

    assert_equal [42, ""], execute(source)
  end

  def test_gc_marks_array_references_stored_inside_arrays
    source = <<~MINICPP
      int main() {
        int[][] arrays = new int[1];
        int[] old_values = new int[1];
        old_values[0] = 42;
        arrays[0] = old_values;
        old_values = new int[1];
        old_values[0] = 7;
        gc();
        return arrays[0][0] + old_values[0];
      }
    MINICPP
    vm = MiniCpp::VM.new(compile(source))

    assert_equal 49, vm.run
    assert_equal 3, vm.heap.size
  end

  def test_rejects_array_index_out_of_bounds
    error = assert_raises(RuntimeError) do
      execute("int main() { int[] values = new int[1]; return values[1]; }")
    end

    assert_match(/範囲外/, error.message)
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
