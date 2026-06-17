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

  class VM
    def initialize(functions, output: $stdout)
      @functions = functions
      @output = output
      @stack = []
      @frames = []
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
          binary_int { |a, b| a + b }
        when :sub
          binary_int { |a, b| a - b }
        when :mul
          binary_int { |a, b| a * b }
        when :div
          binary_int { |a, b| a / b }
        when :lt
          binary_int { |a, b| a < b ? 1 : 0 }
        when :gt
          binary_int { |a, b| a > b ? 1 : 0 }
        when :eq
          binary_int { |a, b| a == b ? 1 : 0 }
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

    private

    def binary_int
      b = @stack.pop.as_int
      a = @stack.pop.as_int
      @stack.push(Value.int(yield(a, b)))
    end
  end

  module_function

  def execute(ast, output: $stdout)
    functions = compile(ast)
    VM.new(functions, output: output).run
  end
end
