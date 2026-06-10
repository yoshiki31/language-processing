# frozen_string_literal: true

module MiniCpp
  class Compiler
    def initialize
      @code = []
      @locals = []
    end

    attr_reader :code

    def nlocals
      @locals.size
    end

    def emit(*instruction)
      @code << instruction
    end

    # 式の並びをコンパイルし、最後の式の値だけをスタックに残す。
    def compile_exprs(exprs)
      if exprs.empty?
        emit(:push, 0)
        return
      end

      exprs.each_with_index do |expr, index|
        compile_expr(expr)
        emit(:pop) if index < exprs.size - 1
      end
    end

    # 式をコンパイルし、値を1つスタックに残す。
    def compile_expr(node)
      case node[0]
      when :int
        emit(:push, node[1])
      when :var
        index = @locals.index(node[1]) or raise "未定義の変数: #{node[1]}"
        emit(:get_local, index)
      when :add, :sub, :mul, :div, :lt, :gt, :eq
        compile_expr(node[1])
        compile_expr(node[2])
        emit(node[0])
      when :assign
        compile_expr(node[2])
        emit(:set_local, local_index(node[1]))
      when :if
        compile_if(node)
      when :while
        compile_while(node)
      when :call
        _, name, arguments = node
        arguments.each { |argument| compile_expr(argument) }
        emit(:call, name, arguments.size)
      when :block
        compile_exprs(node[1])
      when :expr_stmt
        compile_expr(node[1])
      when :var_decl
        compile_variable_declaration(node)
      when :return
        compile_expr(node[1])
        emit(:ret)
      else
        raise "未知の式: #{node.inspect}"
      end
    end

    def local_index(name)
      @locals.index(name) || begin
        @locals << name
        @locals.size - 1
      end
    end

    def emit_placeholder(operation)
      @code << [operation, nil]
      @code.size - 1
    end

    def patch(index, address)
      @code[index][1] = address
    end

    private

    def compile_if(node)
      _, condition, then_block, else_block = node
      compile_expr(condition)
      jump_if_false = emit_placeholder(:jump_if_false)
      compile_expr(then_block)
      jump_to_end = emit_placeholder(:jump)
      patch(jump_if_false, @code.size)
      else_block ? compile_expr(else_block) : emit(:push, 0)
      patch(jump_to_end, @code.size)
    end

    def compile_while(node)
      _, condition, body = node
      loop_start = @code.size
      compile_expr(condition)
      jump_if_false = emit_placeholder(:jump_if_false)
      compile_expr(body)
      emit(:pop)
      emit(:jump, loop_start)
      patch(jump_if_false, @code.size)
      emit(:push, 0)
    end

    def compile_variable_declaration(node)
      _, name, value = node
      raise "変数が重複しています: #{name}" if @locals.include?(name)

      index = local_index(name)
      value ? compile_expr(value) : emit(:push, 0)
      emit(:set_local, index)
    end
  end

  class ProgramCompiler
    def compile(ast)
      raise "programノードを期待しました" unless ast&.first == :program

      functions = {}
      ast[1].each do |node|
        name, function = compile_function(node)
        raise "関数が重複しています: #{name}" if functions.key?(name)

        functions[name] = function
      end
      functions
    end

    private

    def compile_function(node)
      kind, name, params, body = node
      raise "functionノードを期待しました: #{node.inspect}" unless kind == :function

      compiler = Compiler.new
      params.each { |param| compiler.local_index(param) }
      compiler.compile_expr(body)
      compiler.emit(:ret)

      [name, {
        name: name,
        code: compiler.code,
        nparams: params.size,
        nlocals: compiler.nlocals
      }]
    end
  end

  module_function

  def compile(ast)
    ProgramCompiler.new.compile(ast)
  end
end
