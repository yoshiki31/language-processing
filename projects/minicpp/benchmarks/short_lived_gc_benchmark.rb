# frozen_string_literal: true

require_relative "../lexer"
require_relative "../parser"
require_relative "../compiler"
require_relative "../virtual_machine"

ITERATIONS = Integer(ARGV[0] || 1_000)
THRESHOLD = Integer(ARGV[1] || 128)
RUNS = Integer(ARGV[2] || 5)
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

def run_once(functions, strategy)
  vm = MiniCpp::VM.new(functions, gc_strategy: strategy, gc_threshold: THRESHOLD)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = vm.run
  total_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0
  stats = vm.gc_stats
  slots = vm.heap.slots
  live = vm.heap.size
  fragmentation = slots.zero? ? 0.0 : (slots - live).fdiv(slots)

  {
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

def average(rows, key)
  rows.sum { |row| row.fetch(key) }.fdiv(rows.size)
end

def min_value(rows, key)
  rows.map { |row| row.fetch(key) }.min
end

def max_value(rows, key)
  rows.map { |row| row.fetch(key) }.max
end

def print_run_row(strategy, run_number, row)
  puts [
    "run",
    strategy,
    run_number,
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

def print_summary_row(strategy, rows)
  puts [
    "summary",
    strategy,
    RUNS,
    rows.first.fetch(:result),
    format("%.3f", average(rows, :total_ms)),
    format("%.3f", average(rows, :gc_time_ms)),
    rows.first.fetch(:gc_count),
    rows.first.fetch(:allocated),
    rows.first.fetch(:collected),
    rows.first.fetch(:moved),
    rows.first.fetch(:updated_refs),
    rows.first.fetch(:heap_slots),
    rows.first.fetch(:live_objects),
    format("%.3f", average(rows, :fragmentation)),
    format("%.3f", min_value(rows, :total_ms)),
    format("%.3f", max_value(rows, :total_ms)),
    format("%.3f", min_value(rows, :gc_time_ms)),
    format("%.3f", max_value(rows, :gc_time_ms))
  ].join(",")
end

functions = compile_source(short_lived_source(ITERATIONS))

puts "# short_lived benchmark"
puts "# iterations=#{ITERATIONS}, threshold=#{THRESHOLD}, runs=#{RUNS}"
puts "kind,strategy,run_or_runs,result,total_ms,gc_time_ms,gc_count,allocated,collected,moved,updated_refs,heap_slots,live_objects,fragmentation,total_min_ms,total_max_ms,gc_min_ms,gc_max_ms"

STRATEGIES.each do |strategy|
  rows = []
  RUNS.times do |index|
    row = run_once(functions, strategy)
    rows << row
    print_run_row(strategy, index + 1, row)
  end
  print_summary_row(strategy, rows)
end
