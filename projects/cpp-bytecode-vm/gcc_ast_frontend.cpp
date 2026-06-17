#include "gcc_ast_frontend.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <regex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {
namespace fs = std::filesystem;

struct GccNode {
  int id = 0;
  std::string kind;
  std::string raw;
  std::unordered_map<std::string, int> refs;
  std::vector<int> items;
  std::string string_value;
  int integer_value = 0;
  bool has_integer = false;
};

std::string trim(std::string value) {
  const auto first = value.find_first_not_of(' ');
  if (first == std::string::npos) {
    return "";
  }
  const auto last = value.find_last_not_of(' ');
  return value.substr(first, last - first + 1);
}

class GccAst {
 public:
  explicit GccAst(const fs::path& dump_path) { parse(dump_path); }

  const GccNode& node(int id) const {
    const auto found = nodes_.find(id);
    if (found == nodes_.end()) {
      throw std::runtime_error("missing GCC AST node @" + std::to_string(id));
    }
    return found->second;
  }

  int ref(int id, const std::string& key) const {
    const auto& refs = node(id).refs;
    const auto found = refs.find(key);
    return found == refs.end() ? 0 : found->second;
  }

  std::string identifier(int id) const {
    if (id == 0) {
      return "";
    }
    const GccNode& value = node(id);
    if (value.kind == "identifier_node") {
      return value.string_value;
    }
    return identifier(ref(id, "name"));
  }

  int find_main() const {
    for (const auto& entry : nodes_) {
      const GccNode& candidate = entry.second;
      if (candidate.kind == "function_decl" &&
          identifier(candidate.refs.count("name") ? candidate.refs.at("name") : 0) ==
              "main" &&
          candidate.refs.count("body") != 0) {
        return candidate.id;
      }
    }
    throw std::runtime_error("main function was not found in GCC AST");
  }

  void print(std::ostream& output) const {
    std::vector<int> ids;
    ids.reserve(nodes_.size());
    for (const auto& entry : nodes_) {
      ids.push_back(entry.first);
    }
    std::sort(ids.begin(), ids.end());
    for (const int id : ids) {
      const GccNode& value = node(id);
      output << '@' << id << ' ' << value.kind;
      if (!value.string_value.empty()) {
        output << " value=" << value.string_value;
      }
      if (value.has_integer) {
        output << " value=" << value.integer_value;
      }
      output << '\n';
    }
  }

 private:
  std::unordered_map<int, GccNode> nodes_;

  void parse(const fs::path& dump_path) {
    std::ifstream input(dump_path);
    if (!input) {
      throw std::runtime_error("cannot open GCC AST dump");
    }

    const std::regex header(R"(^@([0-9]+)\s+([a-zA-Z0-9_]+)\s*(.*)$)");
    std::string line;
    GccNode* current = nullptr;
    while (std::getline(input, line)) {
      std::smatch match;
      if (std::regex_match(line, match, header)) {
        const int id = std::stoi(match[1].str());
        GccNode value;
        value.id = id;
        value.kind = match[2].str();
        value.raw = match[3].str();
        nodes_[id] = std::move(value);
        current = &nodes_.at(id);
      } else if (current != nullptr) {
        current->raw += ' ' + trim(line);
      }
    }

    const std::regex reference(
        R"((name|body|vars|expr|chain|init|labl|fn|op\s+[0-9]+)\s*:\s*@([0-9]+))");
    const std::regex item(R"(([0-9]+)\s*:\s*@([0-9]+))");
    const std::regex string_value(R"(strg:\s*([^ ](?:.*?))\s+lngt:)");
    const std::regex integer_value(R"(int:\s*(-?[0-9]+))");
    for (auto& entry : nodes_) {
      GccNode& value = entry.second;
      for (std::sregex_iterator it(value.raw.begin(), value.raw.end(), reference), end;
           it != end; ++it) {
        value.refs[trim((*it)[1].str())] = std::stoi((*it)[2].str());
      }
      std::map<int, int> ordered_items;
      for (std::sregex_iterator it(value.raw.begin(), value.raw.end(), item), end;
           it != end; ++it) {
        ordered_items[std::stoi((*it)[1].str())] = std::stoi((*it)[2].str());
      }
      for (const auto& ordered : ordered_items) {
        value.items.push_back(ordered.second);
      }
      std::smatch match;
      if (std::regex_search(value.raw, match, string_value)) {
        value.string_value = trim(match[1].str());
      }
      if (std::regex_search(value.raw, match, integer_value)) {
        try {
          value.integer_value = std::stoi(match[1].str());
          value.has_integer = true;
        } catch (const std::out_of_range&) {
          value.has_integer = false;
        }
      }
    }
  }
};

class GccBytecodeCompiler {
 public:
  explicit GccBytecodeCompiler(const GccAst& ast) : ast_(ast) {}

  Function compile_main() {
    const int main_function = ast_.find_main();
    compile_statement(ast_.ref(main_function, "body"));
    patch_labels();
    if (code_.empty() || code_.back().op != OpCode::Ret) {
      code_.push_back(Instruction::push(0));
      code_.push_back(Instruction::simple(OpCode::Ret));
    }
    return {std::move(code_), 0, locals_.size()};
  }

 private:
  const GccAst& ast_;
  std::vector<Instruction> code_;
  std::unordered_map<int, std::size_t> locals_;
  std::unordered_map<int, std::size_t> labels_;
  std::vector<std::pair<std::size_t, int>> pending_jumps_;

  std::size_t local_index(int declaration) {
    const auto found = locals_.find(declaration);
    if (found != locals_.end()) {
      return found->second;
    }
    const std::size_t index = locals_.size();
    locals_[declaration] = index;
    return index;
  }

  void compile_declarations(int declaration) {
    for (int current = declaration; current != 0;
         current = ast_.ref(current, "chain")) {
      if (ast_.node(current).kind != "var_decl") {
        continue;
      }
      const int initializer = ast_.ref(current, "init");
      if (initializer != 0) {
        compile_expression(initializer);
        code_.push_back(
            Instruction::indexed(OpCode::SetLocal, local_index(current)));
        code_.push_back(Instruction::simple(OpCode::Pop));
      }
    }
  }

  void compile_statement(int id) {
    if (id == 0) {
      return;
    }
    const GccNode& node = ast_.node(id);
    if (node.kind == "statement_list") {
      for (const int child : node.items) {
        compile_statement(child);
      }
    } else if (node.kind == "bind_expr") {
      compile_declarations(ast_.ref(id, "vars"));
      compile_statement(ast_.ref(id, "body"));
    } else if (node.kind == "cleanup_point_expr" ||
               node.kind == "convert_expr") {
      compile_statement(ast_.ref(id, "op 0"));
    } else if (node.kind == "decl_expr") {
      return;
    } else if (node.kind == "expr_stmt") {
      compile_expression(ast_.ref(id, "expr"));
      code_.push_back(Instruction::simple(OpCode::Pop));
    } else if (node.kind == "return_expr") {
      const int expression = ast_.ref(id, "expr");
      const int value = ast_.node(expression).kind == "init_expr"
                            ? ast_.ref(expression, "op 1")
                            : expression;
      compile_expression(value);
      code_.push_back(Instruction::simple(OpCode::Ret));
    } else if (node.kind == "label_expr") {
      labels_[ast_.ref(id, "name")] = code_.size();
    } else if (node.kind == "goto_expr") {
      const std::size_t index = code_.size();
      code_.push_back(Instruction::jump(OpCode::Jump, 0));
      pending_jumps_.push_back({index, ast_.ref(id, "labl")});
    } else if (node.kind == "cond_expr") {
      compile_expression(ast_.ref(id, "op 0"));
      const std::size_t jump_false = code_.size();
      code_.push_back(Instruction::jump(OpCode::JumpIfFalse, 0));
      compile_statement(ast_.ref(id, "op 1"));
      const std::size_t jump_end = code_.size();
      code_.push_back(Instruction::jump(OpCode::Jump, 0));
      code_[jump_false].operand = static_cast<int>(code_.size());
      compile_statement(ast_.ref(id, "op 2"));
      code_[jump_end].operand = static_cast<int>(code_.size());
    } else {
      compile_expression(id);
      code_.push_back(Instruction::simple(OpCode::Pop));
    }
  }

  void compile_expression(int id) {
    const GccNode& node = ast_.node(id);
    if (node.kind == "integer_cst") {
      code_.push_back(Instruction::push(node.integer_value));
    } else if (node.kind == "var_decl") {
      code_.push_back(
          Instruction::indexed(OpCode::GetLocal, local_index(id)));
    } else if (node.kind == "modify_expr" || node.kind == "init_expr") {
      const int target = ast_.ref(id, "op 0");
      compile_expression(ast_.ref(id, "op 1"));
      if (ast_.node(target).kind == "var_decl") {
        code_.push_back(
            Instruction::indexed(OpCode::SetLocal, local_index(target)));
      }
    } else if (node.kind == "convert_expr" || node.kind == "nop_expr") {
      compile_expression(ast_.ref(id, "op 0"));
    } else if (node.kind == "call_expr") {
      for (const int argument : node.items) {
        compile_expression(argument);
      }
      int function = ast_.ref(id, "fn");
      if (ast_.node(function).kind == "addr_expr") {
        function = ast_.ref(function, "op 0");
      }
      const std::string name = ast_.identifier(function);
      if (name != "print") {
        throw std::runtime_error("unsupported C++ function call: " + name);
      }
      code_.push_back(Instruction::call("puts", node.items.size()));
    } else {
      static const std::unordered_map<std::string, OpCode> binary_ops{
          {"plus_expr", OpCode::Add},       {"minus_expr", OpCode::Sub},
          {"mult_expr", OpCode::Mul},       {"trunc_div_expr", OpCode::Div},
          {"lt_expr", OpCode::Lt},          {"le_expr", OpCode::Le},
          {"gt_expr", OpCode::Gt},          {"ge_expr", OpCode::Ge},
          {"eq_expr", OpCode::Eq},          {"ne_expr", OpCode::Ne}};
      const auto operation = binary_ops.find(node.kind);
      if (operation == binary_ops.end()) {
        throw std::runtime_error("unsupported GCC AST node: " + node.kind);
      }
      compile_expression(ast_.ref(id, "op 0"));
      compile_expression(ast_.ref(id, "op 1"));
      code_.push_back(Instruction::simple(operation->second));
    }
  }

  void patch_labels() {
    for (const auto& pending : pending_jumps_) {
      const auto label = labels_.find(pending.second);
      if (label == labels_.end()) {
        throw std::runtime_error("unresolved GCC AST label");
      }
      code_[pending.first].operand = static_cast<int>(label->second);
    }
  }
};

fs::path create_temporary_directory() {
  const fs::path base = fs::temp_directory_path() / "cpp-vm-gcc-ast-XXXXXX";
  std::string pattern = base.string();
  std::vector<char> writable(pattern.begin(), pattern.end());
  writable.push_back('\0');
  char* created = mkdtemp(writable.data());
  if (created == nullptr) {
    throw std::runtime_error("cannot create temporary directory");
  }
  return created;
}
}  // namespace

FunctionTable compile_cpp_with_gcc_ast(const std::string& source_path,
                                       std::ostream* ast_output) {
  const fs::path temporary = create_temporary_directory();
  try {
    const fs::path copied_source = temporary / "input.cpp";
    std::ifstream source(source_path);
    if (!source) {
      throw std::runtime_error("cannot open C++ source file");
    }
    std::ofstream copied(copied_source);
    copied << "extern int print(int);\n" << source.rdbuf();
    copied.close();

    const std::string command = "cd \"" + temporary.string() +
                                "\" && g++ -std=c++17 -fdump-lang-raw "
                                "-fsyntax-only input.cpp";
    if (std::system(command.c_str()) != 0) {
      throw std::runtime_error("G++ failed to parse the C++ source");
    }

    fs::path dump_path;
    for (const auto& entry : fs::directory_iterator(temporary)) {
      if (entry.path().filename().string().find("input.cpp.") !=
              std::string::npos &&
          entry.path().extension() == ".raw") {
        dump_path = entry.path();
        break;
      }
    }
    if (dump_path.empty()) {
      throw std::runtime_error("cannot find GCC AST dump");
    }
    const GccAst ast(dump_path);
    if (ast_output != nullptr) {
      ast.print(*ast_output);
    }
    FunctionTable functions;
    functions["main"] = GccBytecodeCompiler(ast).compile_main();
    fs::remove_all(temporary);
    return functions;
  } catch (...) {
    fs::remove_all(temporary);
    throw;
  }
}
