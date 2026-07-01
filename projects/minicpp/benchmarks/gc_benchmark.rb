# frozen_string_literal: true

require_relative "../lexer"
require_relative "../parser"
require_relative "../compiler"
require_relative "../virtual_machine"

ITERATIONS = Integer(ARGV[0] || 2_000)
THRESHOLD = Integer(ARGV[1] || 128)
STRATEGIES = [:sweep, :compact].freeze

def compile_source(source)
  MiniCpp.compile(MiniCpp.parse(MiniCpp.tokenize(source)))
end

def short_lived_source(count)
  <<~MINICPP
    int main() {
      int i = 0;
      int sum = 0;
      while (i < #{count}) {
        int[] values = new int[1];
        values[0] = i;
        sum = sum + values[0];
        i = i + 1;
      }
      return sum;
    }
  MINICPP
end

def survival_source(count, live_count)
  <<~MINICPP
    int main() {
      int[][] keep = new int[#{live_count}];
      int i = 0;
      while (i < #{count}) {
        int[] values = new int[1];
        values[0] = i;
        if (i < #{live_count}) {
          keep[i] = values;
        }
        i = i + 1;
      }
      return i;
    }
  MINICPP
end

def cyclic_source(count)
  <<~MINICPP
    int main() {
      int i = 0;
      while (i < #{count}) {
        int[][] left = new int[1];
        int[][] right = new int[1];
        left[0] = right;
        right[0] = left;

        left = new int[1];
        right = new int[1];
        i = i + 1;
      }
      return i;
    }
  MINICPP
end

def run_benchmark(name, source, strategy)
  functions = compile_source(source)
  vm = MiniCpp::VM.new(functions, gc_strategy: strategy, gc_threshold: THRESHOLD)

  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = vm.run
  total_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0
  stats = vm.gc_stats
  slots = vm.heap.slots
  live = vm.heap.size
  fragmentation = slots.zero? ? 0.0 : (slots - live).fdiv(slots)

  {
    case_name: name,
    strategy: strategy,
    result: result,
    total_ms: total_ms,
    gc_time_ms: stats.fetch(:gc_time_ms),
    gc_count: stats.fetch(:gc_count),
    allocated: stats.fetch(:allocated_objects),
    collected: stats.fetch(:collected_objects),
    moved: stats.fetch(:moved_objects),
    updated_refs: stats.fetch(:updated_references),
    heap_slots: slots,
    live_objects: live,
    fragmentation: fragmentation
  }
end

def print_row(row)
  puts [
    row.fetch(:case_name),
    row.fetch(:strategy),
    row.fetch(:result),
    format("%.3f", row.fetch(:total_ms)),
    format("%.3f", row.fetch(:gc_time_ms)),
    row.fetch(:gc_count),
    row.fetch(:allocated),
    row.fetch(:collected),
    row.fetch(:moved),
    row.fetch(:updated_refs),
    row.fetch(:heap_slots),
    row.fetch(:live_objects),
    format("%.3f", row.fetch(:fragmentation))
  ].join(",")
end

cases = [
  ["short_lived", short_lived_source(ITERATIONS)],
  ["survival_10_percent", survival_source(ITERATIONS, ITERATIONS / 10)],
  ["cyclic_references", cyclic_source(ITERATIONS / 2)]
]

puts "# iterations=#{ITERATIONS}, threshold=#{THRESHOLD}"
puts "case,strategy,result,total_ms,gc_time_ms,gc_count,allocated,collected,moved,updated_refs,heap_slots,live_objects,fragmentation"

cases.each do |name, source|
  STRATEGIES.each do |strategy|
    print_row(run_benchmark(name, source, strategy))
  end
end
