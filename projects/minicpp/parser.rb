# frozen_string_literal: true

module MiniCpp
  class Parser
    def initialize(tokens)
      @tokens = tokens
      @pos = 0
    end

    #ソースコードの終端まで読み込み、[:program,functions]を返す
    def parse
      functions = []
      functions << parse_function until peek == [:eof, nil]
      [:program, functions]
    end

    private

    def peek
      @tokens[@pos]
    end

    def advance
      token = peek
      @pos += 1
      token
    end

    # function ::= type IDENT "(" params ")" block
    def parse_function
      parse_type
      name = expect_identifier
      expect_op("(")
      params = parse_params
      expect_op(")")
      [:function, name, params, parse_block]
    end

    # params ::= (type IDENT ("," type IDENT)*)?
    def parse_params
      params = []
      return params if peek == [:op, ")"]

      loop do
        parse_type
        params << expect_identifier
        break unless peek == [:op, ","]

        advance
      end
      params
    end

    # block ::= "{" statement* "}"
    def parse_block
      expect_op("{")
      statements = []
      statements << parse_statement until peek == [:op, "}"]
      expect_op("}")
      [:block, statements]
    end

    def parse_statement
      case peek
      when [:ident, "int"] then parse_variable_declaration
      when [:ident, "return"] then parse_return
      when [:ident, "if"] then parse_if
      when [:ident, "while"] then parse_while
      when [:op, "{"] then parse_block
      else parse_expression_statement
      end
    end

    # variable-declaration ::= type IDENT ("=" expression)? ";"
    def parse_variable_declaration
      parse_type
      name = expect_identifier
      value = nil
      if peek == [:op, "="]
        advance
        value = parse_expression
      end
      expect_op(";")
      [:var_decl, name, value]
    end

    # return ::= "return" expression ";"
    def parse_return
      expect_ident("return")
      value = parse_expression
      expect_op(";")
      [:return, value]
    end

    # if ::= "if" "(" expression ")" block ("else" block)?
    def parse_if
      expect_ident("if")
      expect_op("(")
      condition = parse_expression
      expect_op(")")
      then_block = parse_block
      else_block = nil
      if peek == [:ident, "else"]
        advance
        else_block = parse_block
      end
      [:if, condition, then_block, else_block]
    end

    # while ::= "while" "(" expression ")" block
    def parse_while
      expect_ident("while")
      expect_op("(")
      condition = parse_expression
      expect_op(")")
      [:while, condition, parse_block]
    end

    # expression-statement ::= expression ";"
    def parse_expression_statement
      expression = parse_expression
      expect_op(";")
      [:expr_stmt, expression]
    end

    # expression ::= assignment
    def parse_expression
      parse_assignment
    end

    # assignment ::= comparison ("=" assignment)?
    def parse_assignment
      node = parse_comparison
      return node unless peek == [:op, "="]

      advance
      value = parse_assignment
      case node[0]
      when :var
        [:assign, node[1], value]
      when :array_get
        [:array_set, node[1], node[2], value]
      else
        raise "代入の左辺には変数または配列要素が必要です"
      end
    end

    # comparison ::= add (("<" | ">" | "==") add)*
    def parse_comparison
      node = parse_add
      while [[:op, "<"], [:op, ">"], [:op, "=="]].include?(peek)
        operator = advance[1]
        right = parse_add
        kind = { "<" => :lt, ">" => :gt, "==" => :eq }.fetch(operator)
        node = [kind, node, right]
      end
      node
    end

    # add ::= mul (("+" | "-") mul)*
    def parse_add
      node = parse_mul
      while [[:op, "+"], [:op, "-"]].include?(peek)
        operator = advance[1]
        right = parse_mul
        node = [operator == "+" ? :add : :sub, node, right]
      end
      node
    end

    # mul ::= primary (("*" | "/") primary)*
    def parse_mul
      node = parse_primary
      while [[:op, "*"], [:op, "/"]].include?(peek)
        operator = advance[1]
        right = parse_primary
        node = [operator == "*" ? :mul : :div, node, right]
      end
      node
    end

    # primary ::= INT | IDENT | call | new-int-array | "(" expression ")"
    def parse_primary
      token = advance
      node = case token&.first
      when :int
        [:int, token[1]]
      when :ident
        if token[1] == "new"
          parse_new
        else
          peek == [:op, "("] ? parse_call(token[1]) : [:var, token[1]]
        end
      when :op
        raise "( を期待しました: #{token.inspect}" unless token[1] == "("

        node = parse_expression
        expect_op(")")
        node
      else
        raise "予期しないトークン: #{token.inspect}"
      end
      parse_postfix(node)
    end

    # call ::= IDENT "(" arguments ")"
    def parse_call(name)
      expect_op("(")
      arguments = []
      unless peek == [:op, ")"]
        arguments << parse_expression
        while peek == [:op, ","]
          advance
          arguments << parse_expression
        end
      end
      expect_op(")")
      [:call, name, arguments]
    end

    # new-int-array ::= "new" "int" "[" expression "]"
    def parse_new
      expect_ident("int")
      expect_op("[")
      size = parse_expression
      expect_op("]")
      [:new_int_array, size]
    end

    # postfix ::= primary ("[" expression "]")*
    def parse_postfix(node)
      while peek == [:op, "["]
        advance
        index = parse_expression
        expect_op("]")
        node = [:array_get, node, index]
      end
      node
    end

    def parse_type
      expect_ident("int")
      dimensions = 0
      while peek == [:op, "["]
        advance
        expect_op("]")
        dimensions += 1
      end
      dimensions.zero? ? :int : [:int_array, dimensions]
    end

    def expect_identifier
      token = advance
      raise "識別子を期待しました: #{token.inspect}" unless token&.first == :ident

      token[1]
    end

    def expect_ident(value)
      token = advance
      expected = [:ident, value]
      raise "#{expected.inspect} を期待しました: #{token.inspect}" unless token == expected

      token
    end

    def expect_op(value)
      token = advance
      expected = [:op, value]
      raise "#{expected.inspect} を期待しました: #{token.inspect}" unless token == expected

      token
    end
  end

  module_function

  def parse(tokens)
    Parser.new(tokens).parse
  end
end
