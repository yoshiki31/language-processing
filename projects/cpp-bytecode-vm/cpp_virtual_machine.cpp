#include "cpp_virtual_machine.hpp"

#include <ostream>
#include <stdexcept>
#include <utility>

Instruction Instruction::push(int value) {
  return {OpCode::Push, value, {}};
}

Instruction Instruction::indexed(OpCode op, std::size_t index) {
  return {op, static_cast<int>(index), {}};
}

Instruction Instruction::jump(OpCode op, std::size_t address) {
  return {op, static_cast<int>(address), {}};
}

Instruction Instruction::call(std::string name, std::size_t argument_count) {
  return {OpCode::Call, static_cast<int>(argument_count), std::move(name)};
}

Instruction Instruction::simple(OpCode op) {
  return {op, 0, {}};
}

VirtualMachine::VirtualMachine(FunctionTable functions, std::ostream& output)
    : functions_(std::move(functions)), output_(output) {}

int VirtualMachine::run() {
  call_function("main", 0);

  while (!frames_.empty()) {
    Frame& frame = frames_.back();
    if (frame.pc >= frame.function->code.size()) {
      throw std::runtime_error("function ended without ret");
    }

    const Instruction instruction = frame.function->code[frame.pc++];
    switch (instruction.op) {
      case OpCode::Push:
        stack_.push_back(instruction.operand);
        break;
      case OpCode::Pop:
        pop_value();
        break;
      case OpCode::Print:
        output_ << pop_value() << '\n';
        break;
      case OpCode::Add:
      case OpCode::Sub:
      case OpCode::Mul:
      case OpCode::Div:
      case OpCode::Lt:
      case OpCode::Le:
      case OpCode::Gt:
      case OpCode::Ge:
      case OpCode::Eq:
      case OpCode::Ne:
        binary_operation(instruction.op);
        break;
      case OpCode::GetLocal:
        stack_.push_back(frame.locals.at(instruction.operand));
        break;
      case OpCode::SetLocal:
        if (stack_.empty()) {
          throw std::runtime_error("stack underflow");
        }
        frame.locals.at(instruction.operand) = stack_.back();
        break;
      case OpCode::Jump:
        frame.pc = instruction.operand;
        break;
      case OpCode::JumpIfFalse:
        if (pop_value() == 0) {
          frame.pc = instruction.operand;
        }
        break;
      case OpCode::Call:
        call_function(instruction.name, instruction.operand);
        break;
      case OpCode::Ret: {
        const int return_value = pop_value();
        frames_.pop_back();
        if (frames_.empty()) {
          return return_value;
        }
        stack_.push_back(return_value);
        break;
      }
    }
  }

  throw std::runtime_error("main returned no value");
}

std::size_t VirtualMachine::max_frame_depth() const {
  return max_frame_depth_;
}

int VirtualMachine::pop_value() {
  if (stack_.empty()) {
    throw std::runtime_error("stack underflow");
  }

  const int value = stack_.back();
  stack_.pop_back();
  return value;
}

void VirtualMachine::binary_operation(OpCode op) {
  const int right = pop_value();
  const int left = pop_value();

  switch (op) {
    case OpCode::Add:
      stack_.push_back(left + right);
      break;
    case OpCode::Sub:
      stack_.push_back(left - right);
      break;
    case OpCode::Mul:
      stack_.push_back(left * right);
      break;
    case OpCode::Div:
      stack_.push_back(left / right);
      break;
    case OpCode::Lt:
      stack_.push_back(left < right ? 1 : 0);
      break;
    case OpCode::Le:
      stack_.push_back(left <= right ? 1 : 0);
      break;
    case OpCode::Gt:
      stack_.push_back(left > right ? 1 : 0);
      break;
    case OpCode::Ge:
      stack_.push_back(left >= right ? 1 : 0);
      break;
    case OpCode::Eq:
      stack_.push_back(left == right ? 1 : 0);
      break;
    case OpCode::Ne:
      stack_.push_back(left != right ? 1 : 0);
      break;
    default:
      throw std::logic_error("not a binary operation");
  }
}

void VirtualMachine::call_function(const std::string& name,
                                   std::size_t argument_count) {
  if (name == "puts") {
    if (argument_count != 1) {
      throw std::invalid_argument("wrong number of arguments: puts");
    }
    const int value = pop_value();
    output_ << value << '\n';
    stack_.push_back(value);
    return;
  }

  const auto function_it = functions_.find(name);
  if (function_it == functions_.end()) {
    throw std::runtime_error("undefined function: " + name);
  }

  const Function& function = function_it->second;
  if (function.parameter_count != argument_count) {
    throw std::invalid_argument("wrong number of arguments: " + name);
  }
  if (stack_.size() < argument_count) {
    throw std::runtime_error("stack underflow");
  }

  std::vector<int> arguments(argument_count);
  for (std::size_t index = argument_count; index > 0; --index) {
    arguments[index - 1] = pop_value();
  }

  std::vector<int> locals(function.local_count, 0);
  for (std::size_t index = 0; index < argument_count; ++index) {
    locals[index] = arguments[index];
  }

  frames_.push_back(Frame{&function, 0, std::move(locals)});
  if (frames_.size() > max_frame_depth_) {
    max_frame_depth_ = frames_.size();
  }
}
