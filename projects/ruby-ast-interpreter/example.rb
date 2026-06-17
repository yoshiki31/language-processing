# frozen_string_literal: true

require_relative "interpreter"

# 5.2: Arithmetic and print
#
# program = [
#   [:print, [:add, [:int, 1], [:mul, [:int, 2], [:int, 3]]]]
# ]
#
# Interpreter.new.run(program) # => 7

# 5.3: Variables and control flow
#
# i = 1; result = 1
# while i < 6
#   result = result * i
#   i = i + 1
# end
# print(result)
# program = [
#   [:assign, "i", [:int, 1]],
#   [:assign, "result", [:int, 1]],
#   [:while, [:lt, [:var, "i"], [:int, 6]], [
#     [:assign, "result", [:mul, [:var, "result"], [:var, "i"]]],
#     [:assign, "i", [:add, [:var, "i"], [:int, 1]]]
#   ]],
#   [:print, [:var, "result"]]
# ]
#
# Interpreter.new.run(program) # => 120

# 5.4: Functions and recursion
#
# def fib(n)
#   if n < 2
#     n
#   else
#     fib(n - 1) + fib(n - 2)
#   end
# end
# puts fib(10)
# program = [
#   [:def, "fib", ["n"], [
#     [:if, [:lt, [:var, "n"], [:int, 2]],
#       [[:var, "n"]],
#       [[:add,
#         [:call, "fib", [[:sub, [:var, "n"], [:int, 1]]]],
#         [:call, "fib", [[:sub, [:var, "n"], [:int, 2]]]]]]]
#   ]],
#   [:call, "puts", [[:call, "fib", [[:int, 10]]]]]
# ]
#
# Interpreter.new.run(program) # => 55

# 5.5: Complete AST interpreter
#
# The final interpreter uses the nodes introduced in 5.2-5.4 together.
program = [
  [:def, "factorial", ["n"], [
    [:if, [:lt, [:var, "n"], [:int, 2]],
      [[:int, 1]],
      [[:mul,
        [:var, "n"],
        [:call, "factorial", [[:sub, [:var, "n"], [:int, 1]]]]]]]
  ]],
  [:assign, "value", [:call, "factorial", [[:int, 5]]]],
  [:call, "puts", [[:var, "value"]]]
]

Interpreter.new.run(program)
