#ifndef MINI_RUBY_CPP_VIRTUAL_MACHINE_HPP
#define MINI_RUBY_CPP_VIRTUAL_MACHINE_HPP

#include <cstddef>
#include <iosfwd>
#include <string>
#include <unordered_map>
#include <vector>

enum class OpCode {
  Push,
  Pop,
  Print,
  Add,
  Sub,
  Mul,
  Div,
  Lt,
  Le,
  Gt,
  Ge,
  Eq,
  Ne,
  GetLocal,
  SetLocal,
  Jump,
  JumpIfFalse,
  Call,
  Ret
};

struct Instruction {
  OpCode op;
  int operand = 0;
  std::string name;

  static Instruction push(int value);
  static Instruction indexed(OpCode op, std::size_t index);
  static Instruction jump(OpCode op, std::size_t address);
  static Instruction call(std::string name, std::size_t argument_count);
  static Instruction simple(OpCode op);
};

struct Function {
  std::vector<Instruction> code;
  std::size_t parameter_count = 0;
  std::size_t local_count = 0;
};

using FunctionTable = std::unordered_map<std::string, Function>;

class VirtualMachine {
 public:
  explicit VirtualMachine(FunctionTable functions, std::ostream& output);

  int run();
  std::size_t max_frame_depth() const;

 private:
  struct Frame {
    const Function* function;
    std::size_t pc;
    std::vector<int> locals;
  };

  FunctionTable functions_;
  std::ostream& output_;
  std::vector<int> stack_;
  std::vector<Frame> frames_;
  std::size_t max_frame_depth_ = 0;

  int pop_value();
  void binary_operation(OpCode op);
  void call_function(const std::string& name, std::size_t argument_count);
};

#endif
