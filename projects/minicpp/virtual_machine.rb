# frozen_string_literal: true

module MiniCpp
  Frame = Struct.new(:func, :pc, :locals)

  class VM
    def initialize(functions)
      @functions = functions
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
          @stack.push(instr[1])
        when :pop
          @stack.pop
        when :add
          b, a = @stack.pop, @stack.pop
          @stack.push(a + b)
        when :sub
          b, a = @stack.pop, @stack.pop
          @stack.push(a - b)
        when :mul
          b, a = @stack.pop, @stack.pop
          @stack.push(a * b)
        when :div
          b, a = @stack.pop, @stack.pop
          @stack.push(a / b)
        when :lt
          b, a = @stack.pop, @stack.pop
          @stack.push(a < b ? 1 : 0)
        when :gt
          b, a = @stack.pop, @stack.pop
          @stack.push(a > b ? 1 : 0)
        when :eq
          b, a = @stack.pop, @stack.pop
          @stack.push(a == b ? 1 : 0)
        when :get_local
          @stack.push(frame.locals[instr[1]])
        when :set_local
          frame.locals[instr[1]] = @stack.last
        when :jump
          frame.pc = instr[1]
        when :jump_if_false
          frame.pc = instr[1] if @stack.pop == 0
        when :call
          result = do_call(instr[1], instr[2])
          @stack.push(result) if result
        when :ret
          do_return
          return @stack.pop if @frames.empty?
        end
      end
    end

    def do_call(name, argc)
      if name == "puts"
        raise "引数の個数が違います: puts" if argc != 1

        value = @stack.pop
        puts value
        return value
      end

      func = @functions[name] or raise "未定義の関数: #{name}"
      raise "引数の個数が違います: #{name}" if argc != func[:nparams]

      args = @stack.pop(argc)
      locals = Array.new(func[:nlocals], 0)
      args.each_with_index { |value, index| locals[index] = value }
      @frames.push(Frame.new(func, 0, locals))
      nil
    end

    def do_return
      retval = @stack.pop
      @frames.pop
      @stack.push(retval)
    end
  end

  module_function

  def execute(ast)
    functions = compile(ast)
    VM.new(functions).run
  end
end
