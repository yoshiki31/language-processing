# frozen_string_literal: true

class Interpreter
  NODE_SIZES = {
    int: 2,
    var: 2,
    add: 3,
    sub: 3,
    mul: 3,
    div: 3,
    lt: 3,
    gt: 3,
    eq: 3,
    assign: 3,
    if: 4,
    while: 3,
    def: 4,
    call: 3
  }.freeze

  def initialize(output: $stdout)
    @output = output
    @functions = {}
  end

  # Evaluate one AST node under env and return its value.
  def eval(node, env = {})
    validate_node!(node)

    case node[0]
    when :int
      node[1]
    when :var
      name = node[1]
      raise NameError, "undefined variable: #{name}" unless env.key?(name)

      env[name]
    when :add
      eval(node[1], env) + eval(node[2], env)
    when :sub
      eval(node[1], env) - eval(node[2], env)
    when :mul
      eval(node[1], env) * eval(node[2], env)
    when :div
      eval(node[1], env) / eval(node[2], env)
    when :lt
      eval(node[1], env) < eval(node[2], env) ? 1 : 0
    when :gt
      eval(node[1], env) > eval(node[2], env) ? 1 : 0
    when :eq
      eval(node[1], env) == eval(node[2], env) ? 1 : 0
    when :assign
      env[node[1]] = eval(node[2], env)
    when :if
      body = eval(node[1], env) != 0 ? node[2] : (node[3] || [])
      eval_exprs(body, env)
    when :while
      eval_exprs(node[2], env) while eval(node[1], env) != 0
      nil
    when :def
      _, name, params, body = node
      @functions[name] = [params, body]
      nil
    when :call
      eval_call(node, env)
    else
      raise ArgumentError, "unknown node: #{node.inspect}"
    end
  end

  # Evaluate expressions in order and return the last value.
  def eval_exprs(expressions, env)
    unless expressions.is_a?(Array)
      raise ArgumentError, "expressions must be an array: #{expressions.inspect}"
    end

    expressions.reduce(nil) { |_result, expression| eval(expression, env) }
  end

  # Run a program in a new top-level environment.
  def run(program)
    unless program.is_a?(Array)
      raise ArgumentError, "program must be an array: #{program.inspect}"
    end

    eval_exprs(program, {})
  end

  private

  def eval_call(node, env)
    _, name, argument_expressions = node

    if name == "puts"
      unless argument_expressions.length == 1
        raise ArgumentError, "wrong number of arguments: #{name}"
      end

      value = eval(argument_expressions[0], env)
      @output.puts(value)
      return value
    end

    function = @functions[name]
    raise NameError, "undefined function: #{name}" unless function

    parameters, body = function
    unless parameters.length == argument_expressions.length
      raise ArgumentError, "wrong number of arguments: #{name}"
    end

    argument_values = argument_expressions.map { |expression| eval(expression, env) }
    local_env = parameters.zip(argument_values).to_h
    eval_exprs(body, local_env)
  end

  def validate_node!(node)
    unless node.is_a?(Array) && node[0].is_a?(Symbol)
      raise ArgumentError, "invalid AST node: #{node.inspect}"
    end

    expected_size = NODE_SIZES[node[0]]
    return unless expected_size
    return if node.length == expected_size

    raise ArgumentError, "invalid AST node: #{node.inspect}"
  end
end
