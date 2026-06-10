# frozen_string_literal: true

module MiniCpp
  class VirtualMachine
    Frame = Struct.new(:function, :pc, :locals)

    def initialize(functions, output: $stdout)
      @functions = functions
      @output = output
      @stack = []
      @frames = []
    end

    def run
      call_function("main", 0)

      loop do
        frame = @frames.last
        instruction = frame.function.fetch(:code)[frame.pc]
        raise "関数がreturnせず終了しました" unless instruction

        frame.pc += 1
        case instruction.first
        when :push
          @stack << instruction[1]
        when :pop
          pop_value
        when :get_local
          @stack << frame.locals.fetch(instruction[1])
        when :set_local
          frame.locals[instruction[1]] = @stack.last
        when :add
          binary_operation { |left, right| left + right }
        when :sub
          binary_operation { |left, right| left - right }
        when :mul
          binary_operation { |left, right| left * right }
        when :div
          binary_operation { |left, right| left / right }
        when :lt
          binary_operation { |left, right| left < right ? 1 : 0 }
        when :gt
          binary_operation { |left, right| left > right ? 1 : 0 }
        when :eq
          binary_operation { |left, right| left == right ? 1 : 0 }
        when :jump
          frame.pc = instruction[1]
        when :jump_if_false
          frame.pc = instruction[1] if pop_value == 0
        when :call
          result = call_function(instruction[1], instruction[2])
          @stack << result unless result.nil?
        when :ret
          result = return_from_function
          return result if @frames.empty?
        else
          raise "未知の命令です: #{instruction.inspect}"
        end
      end
    end

    private

    def binary_operation
      right = pop_value
      left = pop_value
      @stack << yield(left, right)
    end

    def pop_value
      raise "値スタックが空です" if @stack.empty?

      @stack.pop
    end

    def call_function(name, argc)
      return call_builtin_print(argc) if name == "print"

      function = @functions[name]
      raise "未定義の関数です: #{name}" unless function
      raise "引数の個数が違います: #{name}" unless argc == function.fetch(:nparams)

      arguments = @stack.pop(argc)
      locals = Array.new(function.fetch(:nlocals), 0)
      arguments.each_with_index { |value, index| locals[index] = value }
      @frames << Frame.new(function, 0, locals)
      nil
    end

    def call_builtin_print(argc)
      raise "引数の個数が違います: print" unless argc == 1

      value = pop_value
      @output.puts(value)
      value
    end

    def return_from_function
      value = pop_value
      @frames.pop
      @stack << value unless @frames.empty?
      value
    end
  end

  module_function

  def execute(ast, output: $stdout)
    functions = compile(ast)
    VirtualMachine.new(functions, output: output).run
  end
end
