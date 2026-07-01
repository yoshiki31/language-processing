# frozen_string_literal: true

module MiniCpp
  Frame = Struct.new(:func, :pc, :locals)

  class Value
    attr_reader :type

    def self.int(value)
      new(:int, value)
    end

    def self.object(value)
      new(:object, value)
    end

    def initialize(type, value)
      @type = type
      @value = value
    end

    def int?
      @type == :int
    end

    def object?
      @type == :object
    end

    def as_int
      raise "整数ではない値です: #{inspect}" unless int?

      @value
    end

    def as_object
      raise "オブジェクトではない値です: #{inspect}" unless object?

      @value
    end

    def to_ruby
      @value
    end

    def to_s
      @value.to_s
    end

    def inspect
      "#<MiniCpp::Value #{@type}=#{@value.inspect}>"
    end
  end

  class IntArray
    def initialize(size)
      raise "配列サイズが負です: #{size}" if size.negative?

      @elements = Array.new(size) { Value.int(0) }
    end

    def get(index)
      check_index(index)
      @elements[index]
    end

    def set(index, value)
      raise "配列にはMiniC++の値だけを格納できます: #{value.inspect}" unless value.is_a?(Value)

      check_index(index)
      @elements[index] = value
    end

    def each_value(&block)
      @elements.each(&block)
    end

    def inspect
      "#<MiniCpp::IntArray size=#{@elements.size}>"
    end

    private

    def check_index(index)
      return if index >= 0 && index < @elements.size

      raise "配列の添字が範囲外です: #{index}"
    end
  end

  class ObjectRef
    # Mark & Compact GCで参照先アドレスを書き換えるため、addressは更新可能にする。
    attr_accessor :address

    def initialize(address)
      @address = address
    end

    def inspect
      "#<MiniCpp::ObjectRef address=#{@address}>"
    end
  end

  class Heap
    Entry = Struct.new(:object, :marked)

    def initialize
      @objects = []
    end

    def allocate(object)
      address = @objects.index(nil)
      if address
        @objects[address] = Entry.new(object, false)
      else
        address = @objects.size
        @objects << Entry.new(object, false)
      end
      ObjectRef.new(address)
    end

    def fetch(ref)
      raise "ヒープ参照ではありません: #{ref.inspect}" unless ref.is_a?(ObjectRef)

      entry = @objects[ref.address]
      raise "不正なヒープ参照です: #{ref.inspect}" unless entry

      entry.object
    end

    def mark(ref)
      raise "ヒープ参照ではありません: #{ref.inspect}" unless ref.is_a?(ObjectRef)

      entry = @objects[ref.address]
      raise "不正なヒープ参照です: #{ref.inspect}" unless entry

      return false if entry.marked

      entry.marked = true
      true
    end

    def sweep
      collected = 0
      @objects.each_with_index do |entry, index|
        next unless entry

        if entry.marked
          entry.marked = false
        else
          @objects[index] = nil
          collected += 1
        end
      end
      collected
    end

    def size
      @objects.count { |entry| entry }
    end

    def each_object
      @objects.each do |entry|
        yield entry.object if entry
      end
    end

    def slots
      @objects.size
    end

    def compact
      # forwardingは「古いヒープアドレス -> compact後の新しいヒープアドレス」の対応表。
      # compact後にスタック、ローカル変数、配列要素のObjectRefを書き換えるために使う。
      forwarding = {}
      compacted = []
      collected = 0
      moved = 0
      old_slots = @objects.size

      @objects.each_with_index do |entry, old_address|
        next unless entry

        if entry.marked
          new_address = compacted.size
          forwarding[old_address] = new_address
          moved += 1 if old_address != new_address
          entry.marked = false
          # markedな生存オブジェクトだけを新しいヒープ配列へ前から詰める。
          compacted << entry
        else
          collected += 1
        end
      end

      @objects = compacted
      {
        collected: collected,
        moved: moved,
        old_slots: old_slots,
        new_slots: @objects.size,
        forwarding: forwarding
      }
    end
  end

  class VM
    GC_STRATEGIES = [:manual, :sweep, :compact].freeze

    attr_reader :heap, :gc_stats

    def initialize(functions, output: $stdout, gc_strategy: :manual, gc_threshold: nil)
      @functions = functions
      @output = output
      @stack = []
      @frames = []
      @heap = Heap.new
      @gc_strategy = gc_strategy.to_sym
      raise "未知のGC方式です: #{@gc_strategy}" unless GC_STRATEGIES.include?(@gc_strategy)

      @gc_threshold = gc_threshold
      @gc_stats = empty_gc_stats
    end

    def run
      do_call("main", 0)
      loop do
        frame = @frames.last
        instr = frame.func[:code][frame.pc]
        frame.pc += 1
        case instr[0]
        when :push
          @stack.push(Value.int(instr[1]))
        when :pop
          @stack.pop
        when :add
          b = @stack.pop.as_int
          a = @stack.pop.as_int
          @stack.push(Value.int(a + b))
        when :sub
          b = @stack.pop.as_int
          a = @stack.pop.as_int
          @stack.push(Value.int(a - b))
        when :mul
          b = @stack.pop.as_int
          a = @stack.pop.as_int
          @stack.push(Value.int(a * b))
        when :div
          b = @stack.pop.as_int
          a = @stack.pop.as_int
          @stack.push(Value.int(a / b))
        when :lt
          b = @stack.pop.as_int
          a = @stack.pop.as_int
          @stack.push(Value.int(a < b ? 1 : 0))
        when :gt
          b = @stack.pop.as_int
          a = @stack.pop.as_int
          @stack.push(Value.int(a > b ? 1 : 0))
        when :eq
          b = @stack.pop.as_int
          a = @stack.pop.as_int
          @stack.push(Value.int(a == b ? 1 : 0))
        when :new_int_array
          size = @stack.pop.as_int
          ref = allocate_int_array(size)
          @stack.push(Value.object(ref))
        when :array_get
          index = @stack.pop.as_int
          array = @heap.fetch(@stack.pop.as_object)
          @stack.push(array.get(index))
        when :array_set
          value = @stack.pop
          index = @stack.pop.as_int
          array = @heap.fetch(@stack.pop.as_object)
          array.set(index, value)
          @stack.push(value)
        when :get_local
          @stack.push(frame.locals[instr[1]])
        when :set_local
          frame.locals[instr[1]] = @stack.last
        when :jump
          frame.pc = instr[1]
        when :jump_if_false
          frame.pc = instr[1] if @stack.pop.as_int == 0
        when :call
          result = do_call(instr[1], instr[2])
          @stack.push(result) if result
        when :ret
          do_return
          return @stack.pop.to_ruby if @frames.empty?
        end
      end
    end

    def do_call(name, argc)
      if name == "puts"
        raise "引数の個数が違います: puts" if argc != 1

        value = @stack.pop
        @output.puts value
        return value
      end

      if name == "gc"
        raise "引数の個数が違います: gc" if argc != 0

        gc(reason: :manual)
        return Value.int(0)
      end

      if name == "compact_gc"
        raise "引数の個数が違います: compact_gc" if argc != 0

        compact_gc(reason: :manual)
        return Value.int(0)
      end

      func = @functions[name] or raise "未定義の関数: #{name}"
      raise "引数の個数が違います: #{name}" if argc != func[:nparams]

      args = @stack.pop(argc)
      locals = Array.new(func[:nlocals]) { Value.int(0) }
      args.each_with_index { |value, index| locals[index] = value }
      @frames.push(Frame.new(func, 0, locals))
      nil
    end

    def do_return
      retval = @stack.pop
      @frames.pop
      @stack.push(retval)
    end

    def gc(reason: :direct)
      stats = timed_gc(:sweep, reason) do
        mark_roots
        collected = @heap.sweep
        {
          collected: collected,
          moved: 0,
          updated_references: 0,
          old_slots: @heap.slots,
          new_slots: @heap.slots
        }
      end
      stats.fetch(:collected)
    end

    def compact_gc(reason: :direct)
      # 1. MiniC++のルート集合から到達可能なオブジェクトをmarkする。
      timed_gc(:compact, reason) do
        mark_roots
        # 2. markedなオブジェクトだけをヒープ先頭へ詰め、forwarding tableを作る。
        stats = @heap.compact
        # 3. 移動したオブジェクトを指すObjectRefのaddressを新しいアドレスへ更新する。
        stats.merge(updated_references: update_references(stats.fetch(:forwarding)))
      end
    end

    private

    def empty_gc_stats
      {
        allocated_objects: 0,
        gc_count: 0,
        auto_gc_count: 0,
        sweep_count: 0,
        compact_count: 0,
        gc_time_ms: 0.0,
        collected_objects: 0,
        moved_objects: 0,
        updated_references: 0,
        heap_slots_before_last_gc: 0,
        heap_slots_after_last_gc: 0,
        heap_size_after_last_gc: 0
      }
    end

    def allocate_int_array(size)
      run_auto_gc_if_needed
      @gc_stats[:allocated_objects] += 1
      @heap.allocate(IntArray.new(size))
    end

    def run_auto_gc_if_needed
      return if @gc_strategy == :manual
      return unless @gc_threshold
      return if @heap.size < @gc_threshold

      if @gc_strategy == :sweep
        gc(reason: :auto)
      else
        compact_gc(reason: :auto)
      end
    end

    def timed_gc(kind, reason)
      old_slots = @heap.slots
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stats = yield
      elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0
      record_gc_stats(kind, reason, stats, old_slots, elapsed_ms)
      stats
    end

    def record_gc_stats(kind, reason, stats, old_slots, elapsed_ms)
      @gc_stats[:gc_count] += 1
      @gc_stats[:auto_gc_count] += 1 if reason == :auto
      @gc_stats[:sweep_count] += 1 if kind == :sweep
      @gc_stats[:compact_count] += 1 if kind == :compact
      @gc_stats[:gc_time_ms] += elapsed_ms
      @gc_stats[:collected_objects] += stats.fetch(:collected, 0)
      @gc_stats[:moved_objects] += stats.fetch(:moved, 0)
      @gc_stats[:updated_references] += stats.fetch(:updated_references, 0)
      @gc_stats[:heap_slots_before_last_gc] = old_slots
      @gc_stats[:heap_slots_after_last_gc] = @heap.slots
      @gc_stats[:heap_size_after_last_gc] = @heap.size
    end

    def mark_roots
      # MiniC++ VMでのGCルートは、値スタックと各関数フレームのローカル変数。
      @stack.each { |value| mark_value(value) }
      @frames.each do |frame|
        frame.locals.each { |value| mark_value(value) }
      end
    end

    def mark_value(value)
      return unless value.object?

      ref = value.as_object
      return unless @heap.mark(ref)

      object = @heap.fetch(ref)
      # 配列の中に入っている配列参照も辿る。循環参照はHeap#markの再訪問防止で止まる。
      object.each_value { |element| mark_value(element) } if object.respond_to?(:each_value)
    end

    def update_references(forwarding)
      updated_refs = {}
      updates = 0

      # ヒープをcompactした後、MiniC++ VM上の全参照をforwarding tableに従って更新する。
      @stack.each { |value| updates += update_reference(value, forwarding, updated_refs) }
      @frames.each do |frame|
        frame.locals.each { |value| updates += update_reference(value, forwarding, updated_refs) }
      end
      @heap.each_object do |object|
        next unless object.respond_to?(:each_value)

        object.each_value { |value| updates += update_reference(value, forwarding, updated_refs) }
      end

      updates
    end

    def update_reference(value, forwarding, updated_refs)
      return 0 unless value.object?

      ref = value.as_object
      return 0 if updated_refs[ref.object_id]

      new_address = forwarding[ref.address]
      return 0 unless new_address

      updated_refs[ref.object_id] = true
      # ObjectRef自体を書き換えるので、同じ参照を共有している値はまとめて新アドレスを見る。
      changed = ref.address != new_address
      ref.address = new_address
      changed ? 1 : 0
    end

  end

  module_function

  def execute(ast, output: $stdout)
    functions = compile(ast)
    VM.new(functions, output: output).run
  end
end
