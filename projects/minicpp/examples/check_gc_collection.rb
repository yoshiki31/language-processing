# frozen_string_literal: true

require_relative "../lexer"
require_relative "../parser"
require_relative "../compiler"
require_relative "../virtual_machine"

CASES = [
  {
    file: "04_gc.mcpp",
    description: "未参照になった配列1個を回収する",
    expected_result: 2,
    expected_heap_size: 1
  },
  {
    file: "05_gc_collect_two_arrays.mcpp",
    description: "未参照になった配列2個を回収する",
    expected_result: 21,
    expected_heap_size: 1
  },
  {
    file: "06_gc_keeps_referenced_arrays.mcpp",
    description: "参照中の配列は回収しない",
    expected_result: 7,
    expected_heap_size: 2
  },
  {
    file: "07_gc_collects_after_function_return.mcpp",
    description: "関数終了後にローカル配列を回収する",
    expected_result: 9,
    expected_heap_size: 0
  },
  {
    file: "08_gc_not_run_automatically.mcpp",
    description: "gc()を呼ばない場合は未参照配列も残る",
    expected_result: 2,
    expected_heap_size: 2
  },
  {
    file: "09_nested_arrays.mcpp",
    description: "配列内の配列参照をGCが辿る",
    expected_result: 49,
    expected_heap_size: 3
  }
].freeze

def compile_source(source)
  tokens = MiniCpp.tokenize(source)
  ast = MiniCpp.parse(tokens)
  MiniCpp.compile(ast)
end

def run_case(test_case)
  path = File.join(__dir__, test_case.fetch(:file))
  vm = MiniCpp::VM.new(compile_source(File.read(path)))
  result = vm.run
  heap_size = vm.heap.size

  result_ok = result == test_case.fetch(:expected_result)
  heap_ok = heap_size == test_case.fetch(:expected_heap_size)

  [result_ok && heap_ok, result, heap_size, heap_snapshot(vm)]
end

def heap_snapshot(vm)
  objects = vm.heap.instance_variable_get(:@objects)
  return ["   heap: empty"] if objects.empty?

  objects.each_with_index.map do |entry, index|
    if entry.nil?
      "   heap[#{index}]: collected"
    else
      object = entry.object
      elements = object.instance_variable_get(:@elements)
      values = elements.map { |value| format_value(value) }.join(", ")
      "   heap[#{index}]: #{object.class.name.split('::').last} [#{values}]"
    end
  end
end

def format_value(value)
  return "ref(#{value.as_object.address})" if value.object?

  value.to_ruby.to_s
end

failed = false

CASES.each_with_index do |test_case, index|
  ok, result, heap_size, heap_lines = run_case(test_case)
  failed ||= !ok

  puts "#{index + 1}. #{test_case.fetch(:description)}"
  puts "   file: #{test_case.fetch(:file)}"
  puts "   result: #{result} / expected: #{test_case.fetch(:expected_result)}"
  puts "   heap.size: #{heap_size} / expected: #{test_case.fetch(:expected_heap_size)}"
  puts "   heap contents:"
  puts heap_lines
  puts "   #{ok ? "OK" : "NG"}"
end

exit(failed ? 1 : 0)
