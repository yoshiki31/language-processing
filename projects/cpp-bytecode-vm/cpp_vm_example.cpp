#include "cpp_virtual_machine.hpp"

#include <iostream>

int main() {
  using I = Instruction;
  using O = OpCode;

  FunctionTable functions;

  // if n < 2, return n; otherwise return fib(n - 1) + fib(n - 2).
  functions["fib"] = Function{
      {
          I::indexed(O::GetLocal, 0),
          I::push(2),
          I::simple(O::Lt),
          I::jump(O::JumpIfFalse, 6),
          I::indexed(O::GetLocal, 0),
          I::simple(O::Ret),
          I::indexed(O::GetLocal, 0),
          I::push(1),
          I::simple(O::Sub),
          I::call("fib", 1),
          I::indexed(O::GetLocal, 0),
          I::push(2),
          I::simple(O::Sub),
          I::call("fib", 1),
          I::simple(O::Add),
          I::simple(O::Ret),
      },
      1,
      1,
  };

  functions["main"] = Function{
      {
          I::push(10),
          I::call("fib", 1),
          I::call("puts", 1),
          I::simple(O::Ret),
      },
      0,
      0,
  };

  VirtualMachine vm(std::move(functions), std::cout);
  vm.run();  // => 55
}
