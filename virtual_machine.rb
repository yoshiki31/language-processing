# frozen_string_literal: true

class Compiler
  attr_reader :code, :locals

  def initialize
    @code = []
    @locals = []
  end

  def emit(*instruction)
    @code << instruction
  end

  # Compile an expression so that its value remains on top of the stack.
  def compile_expr(node)
    validate_node!(node)

    case node[0]
    when :int
      emit(:push, node[1])
    when :var
      emit(:get_local, local_index(node[1]))
    when :add, :sub, :mul, :div, :lt, :gt, :eq
      compile_expr(node[1])
      compile_expr(node[2])
      emit(node[0])
    when :call
      _, name, arguments = node
      arguments.each { |argument| compile_expr(argument) }
      emit(:call, name, arguments.length)
    else
      raise ArgumentError, "unknown expression: #{node.inspect}"
    end

    @code
  end

  def compile_stmt(node)
    validate_node!(node)

    case node[0]
    when :assign
      compile_expr(node[2])
      emit(:set_local, local_index(node[1]))
    when :return
      compile_expr(node[1])
      emit(:ret)
    when :if
      _, condition, then_body, else_body = node
      compile_expr(condition)
      jump_to_else = emit_placeholder(:jump_if_false)
      then_body.each { |statement| compile_stmt(statement) }
      jump_to_end = emit_placeholder(:jump)
      patch(jump_to_else, @code.length)
      (else_body || []).each { |statement| compile_stmt(statement) }
      patch(jump_to_end, @code.length)
    when :while
      _, condition, body = node
      loop_start = @code.length
      compile_expr(condition)
      jump_to_end = emit_placeholder(:jump_if_false)
      body.each { |statement| compile_stmt(statement) }
      emit(:jump, loop_start)
      patch(jump_to_end, @code.length)
    else
      compile_expr(node)
      emit(:pop)
    end

    @code
  end

  def local_index(name)
    @locals.index(name) || begin
      @locals << name
      @locals.length - 1
    end
  end

  def local_count
    @locals.length
  end

  alias nlocals local_count

  private

  def emit_placeholder(operation)
    @code << [operation, nil]
    @code.length - 1
  end

  def patch(index, address)
    @code[index][1] = address
  end

  def validate_node!(node)
    unless node.is_a?(Array) && node[0].is_a?(Symbol)
      raise ArgumentError, "invalid AST node: #{node.inspect}"
    end

    expected_size = case node[0]
                    when :int, :var, :return then 2
                    when :add, :sub, :mul, :div, :lt, :gt, :eq, :assign, :while, :call then 3
                    when :if then 4
                    end
    return unless expected_size
    return if node.length == expected_size

    raise ArgumentError, "invalid AST node: #{node.inspect}"
  end
end

def compile_function(parameters, body)
  compiler = Compiler.new
  parameters.each { |parameter| compiler.local_index(parameter) }
  body.each { |statement| compiler.compile_stmt(statement) }
  compiler.emit(:push, 0)
  compiler.emit(:ret)

  {
    code: compiler.code,
    nparams: parameters.length,
    nlocals: compiler.local_count
  }
end

def compile_program(program)
  unless program.is_a?(Hash) && program[:defs].is_a?(Array) && program[:main].is_a?(Array)
    raise ArgumentError, "invalid program: #{program.inspect}"
  end

  functions = {}
  program[:defs].each do |name, parameters, body|
    functions[name] = compile_function(parameters, body)
  end
  functions["main"] = compile_function([], program[:main])
  functions
end

Frame = Struct.new(:func, :pc, :locals)

class VM
  attr_reader :locals, :max_frame_depth

  def initialize(program, nlocals = 0, output: $stdout)
    @output = output
    @stack = []
    @frames = []
    @max_frame_depth = 0

    if program.is_a?(Hash)
      @functions = program
      @legacy_mode = false
    else
      @functions = {
        "main" => { code: program, nparams: 0, nlocals: nlocals }
      }
      @legacy_mode = true
    end
  end

  def run
    call_function("main", 0)

    loop do
      frame = @frames.last
      if frame.pc >= frame.func[:code].length
        @locals = frame.locals
        return @stack.last if @legacy_mode && @frames.length == 1

        raise RuntimeError, "function ended without ret"
      end

      instruction = frame.func[:code][frame.pc]
      frame.pc += 1
      result = execute(instruction, frame)
      return result.value if result.is_a?(ReturnValue)
    end
  end

  private

  ReturnValue = Struct.new(:value)

  def execute(instruction, frame)
    case instruction[0]
    when :push
      @stack.push(instruction[1])
    when :pop
      pop_value
    when :print
      @output.puts(pop_value)
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
    when :get_local
      @stack.push(frame.locals.fetch(instruction[1]))
    when :set_local
      raise RuntimeError, "stack underflow" if @stack.empty?

      frame.locals.fetch(instruction[1])
      frame.locals[instruction[1]] = @stack.last
    when :jump
      frame.pc = instruction[1]
    when :jump_if_false
      frame.pc = instruction[1] if pop_value == 0
    when :call
      call_function(instruction[1], instruction[2])
    when :ret
      return_from_function
    else
      raise ArgumentError, "unknown instruction: #{instruction.inspect}"
    end
  end

  def binary_operation
    right = pop_value
    left = pop_value
    @stack.push(yield(left, right))
  end

  def pop_value
    raise RuntimeError, "stack underflow" if @stack.empty?

    @stack.pop
  end

  def call_function(name, argument_count)
    if name == "puts"
      unless argument_count == 1
        raise ArgumentError, "wrong number of arguments: #{name}"
      end

      value = pop_value
      @output.puts(value)
      @stack.push(value)
      return
    end

    function = @functions[name]
    raise NameError, "undefined function: #{name}" unless function
    unless function[:nparams] == argument_count
      raise ArgumentError, "wrong number of arguments: #{name}"
    end
    raise RuntimeError, "stack underflow" if @stack.length < argument_count

    arguments = @stack.pop(argument_count)
    local_variables = Array.new(function[:nlocals], 0)
    arguments.each_with_index { |value, index| local_variables[index] = value }
    @frames << Frame.new(function, 0, local_variables)
    @max_frame_depth = [@max_frame_depth, @frames.length].max
  end

  def return_from_function
    return_value = pop_value
    finished_frame = @frames.pop
    @locals = finished_frame.locals if @frames.empty?

    return ReturnValue.new(return_value) if @frames.empty?

    @stack.push(return_value)
    nil
  end
end
