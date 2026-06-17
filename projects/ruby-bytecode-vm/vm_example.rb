# frozen_string_literal: true

require_relative "virtual_machine"

# 6.3: Compile and run 1 + 2 * 3.
#
# ast = [:add, [:int, 1], [:mul, [:int, 2], [:int, 3]]]
#
# compiler = Compiler.new
# compiler.compile_expr(ast)
# compiler.emit(:print)
#
# VM.new(compiler.code).run # => 7

# 6.4: Local variables and control flow
#
# i = 1; result = 1
# while i < 6
#   result = result * i
#   i = i + 1
# end
# program = [
#   [:assign, "i", [:int, 1]],
#   [:assign, "result", [:int, 1]],
#   [:while, [:lt, [:var, "i"], [:int, 6]], [
#     [:assign, "result", [:mul, [:var, "result"], [:var, "i"]]],
#     [:assign, "i", [:add, [:var, "i"], [:int, 1]]]
#   ]]
# ]
#
# compiler = Compiler.new
# program.each { |statement| compiler.compile_stmt(statement) }
# compiler.emit(:get_local, compiler.local_index("result"))
# compiler.emit(:print)
#
# VM.new(compiler.code, compiler.local_count).run # => 120

# 6.5-6.7: Functions, call frames, and the complete VM
#
# def fib(n)
#   if n < 2
#     return n
#   else
#     return fib(n - 1) + fib(n - 2)
#   end
# end
# puts fib(10)
program = {
  defs: [
    ["fib", ["n"], [
      [:if, [:lt, [:var, "n"], [:int, 2]],
        [[:return, [:var, "n"]]],
        [[:return, [:add,
          [:call, "fib", [[:sub, [:var, "n"], [:int, 1]]]],
          [:call, "fib", [[:sub, [:var, "n"], [:int, 2]]]]]]]]
    ]]
  ],
  main: [
    [:call, "puts", [[:call, "fib", [[:int, 10]]]]]
  ]
}

VM.new(compile_program(program)).run # => 55
