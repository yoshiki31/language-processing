#include "cpp_virtual_machine.hpp"

#include <cassert>
#include <sstream>
#include <stdexcept>

namespace {
using I = Instruction;
using O = OpCode;

void test_arithmetic() {
  FunctionTable functions{
      {"main",
       Function{{I::push(10), I::push(3), I::simple(O::Sub), I::push(2),
                 I::simple(O::Div), I::simple(O::Ret)},
                0, 0}}};
  std::ostringstream output;
  VirtualMachine vm(std::move(functions), output);
  assert(vm.run() == 3);
}

void test_locals_and_jump() {
  FunctionTable functions{
      {"main",
       Function{{I::push(0), I::indexed(O::SetLocal, 0), I::simple(O::Pop),
                 I::indexed(O::GetLocal, 0), I::jump(O::JumpIfFalse, 8),
                 I::push(1), I::jump(O::Jump, 9), I::push(99), I::push(2),
                 I::simple(O::Ret)},
                0, 1}}};
  std::ostringstream output;
  VirtualMachine vm(std::move(functions), output);
  assert(vm.run() == 2);
}

void test_call_and_builtin_puts() {
  FunctionTable functions;
  functions["double"] = Function{
      {I::indexed(O::GetLocal, 0), I::push(2), I::simple(O::Mul),
       I::simple(O::Ret)},
      1,
      1};
  functions["main"] = Function{
      {I::push(21), I::call("double", 1), I::call("puts", 1),
       I::simple(O::Ret)},
      0,
      0};

  std::ostringstream output;
  VirtualMachine vm(std::move(functions), output);
  assert(vm.run() == 42);
  assert(output.str() == "42\n");
  assert(vm.max_frame_depth() == 2);
}

void test_errors() {
  FunctionTable functions{
      {"main", Function{{I::call("missing", 0), I::simple(O::Ret)}, 0, 0}}};
  std::ostringstream output;
  VirtualMachine vm(std::move(functions), output);

  bool raised = false;
  try {
    vm.run();
  } catch (const std::runtime_error&) {
    raised = true;
  }
  assert(raised);
}
}  // namespace

int main() {
  test_arithmetic();
  test_locals_and_jump();
  test_call_and_builtin_puts();
  test_errors();
}
