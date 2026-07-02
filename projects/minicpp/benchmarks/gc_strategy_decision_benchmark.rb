# frozen_string_literal: true

require_relative "../lexer"
require_relative "../parser"
require_relative "../compiler"
require_relative "../virtual_machine"

ITERATIONS = Integer(ARGV[0] || 1_000)
THRESHOLD = Integer(ARGV[1] || 256)
SURVIVAL_RATES = (ARGV[2] || "0,10,20,30,40,50").split(",").map { |value| Integer(value) }
STRATEGIES = [:sweep, :compact].freeze

def compile_source(source)
  MiniCpp.compile(MiniCpp.parse(MiniCpp.tokenize(source)))
end

def survival_source(count, live_count)
  <<~MINICPP
    int main() {
      int[][] keep = new int[#{live_count}];
      int i = 0;
      int sum = 0;
      while (i < #{count}) {
        int[] values = new int[1];
        values[0] = i;
        if (i < #{live_count}) {
          keep[i] = values;
        }
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

def paired_result(survival_rate)
  live_count = ITERATIONS * survival_rate / 100
  functions = compile_source(survival_source(ITERATIONS, live_count))
  sweep = run_once(functions, :sweep)
  compact = run_once(functions, :compact)
  raise "result mismatch" unless sweep.fetch(:result) == compact.fetch(:result)

  frag_reduction = sweep.fetch(:fragmentation) - compact.fetch(:fragmentation)
  compact_gc_extra_ms = compact.fetch(:gc_time_ms) - sweep.fetch(:gc_time_ms)
  compact_total_extra_ms = compact.fetch(:total_ms) - sweep.fetch(:total_ms)
  move_work = compact.fetch(:moved) + compact.fetch(:updated_refs)
  ms_per_move_work = move_work.zero? ? 0.0 : compact.fetch(:gc_time_ms).fdiv(move_work)
  ms_per_frag_percent = frag_reduction <= 0 ? 0.0 : compact_gc_extra_ms.fdiv(frag_reduction * 100.0)

  {
    survival_rate: survival_rate,
    live_count: live_count,
    sweep: sweep,
    compact: compact,
    frag_reduction: frag_reduction,
    compact_gc_extra_ms: compact_gc_extra_ms,
    compact_total_extra_ms: compact_total_extra_ms,
    move_work: move_work,
    ms_per_move_work: ms_per_move_work,
    ms_per_frag_percent: ms_per_frag_percent,
    suggested: suggest_strategy(compact_total_extra_ms, compact_gc_extra_ms, frag_reduction)
  }
end

def suggest_strategy(total_extra_ms, gc_extra_ms, frag_reduction)
  return "compact" if total_extra_ms <= 0
  return "compact" if frag_reduction >= 0.10 && gc_extra_ms <= 1.0

  "sweep"
end

def print_strategy_row(row, strategy)
  result = row.fetch(strategy)
  puts [
    row.fetch(:survival_rate),
    row.fetch(:live_count),
    strategy,
    result.fetch(:result),
    format("%.3f", result.fetch(:total_ms)),
    format("%.3f", result.fetch(:gc_time_ms)),
    result.fetch(:gc_count),
    result.fetch(:allocated),
    result.fetch(:collected),
    result.fetch(:moved),
    result.fetch(:updated_refs),
    result.fetch(:heap_slots),
    result.fetch(:live_objects),
    format("%.3f", result.fetch(:fragmentation)),
    strategy == :compact ? format("%.3f", row.fetch(:compact_gc_extra_ms)) : "",
    strategy == :compact ? row.fetch(:suggested) : ""
  ].join(",")
end

puts "# iterations=#{ITERATIONS}, threshold=#{THRESHOLD}, survival_rates=#{SURVIVAL_RATES.join(",")}"
puts "# suggested is a simple heuristic: compact if total time is not worse, or if fragmentation reduction >= 0.10 and extra GC time <= 1.0ms"
puts [
  "survival_percent",
  "live_count",
  "gc_strategy",
  "result",
  "total_ms",
  "gc_time_ms",
  "gc_count",
  "allocated",
  "collected",
  "moved",
  "updated_refs",
  "heap_slots",
  "live_objects",
  "fragmentation",
  "compact_gc_extra_ms",
  "suggested_strategy"
].join(",")

SURVIVAL_RATES.each do |survival_rate|
  row = paired_result(survival_rate)
  STRATEGIES.each { |strategy| print_strategy_row(row, strategy) }
end
