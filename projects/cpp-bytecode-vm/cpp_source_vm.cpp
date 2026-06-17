#include "gcc_ast_frontend.hpp"

#include <iostream>
#include <string>

int main(int argc, char* argv[]) {
  try {
    if (argc < 2 || argc > 3) {
      std::cerr << "usage: cpp_source_vm [--ast] <source.cpp>\n";
      return 1;
    }
    const bool show_ast = argc == 3 && std::string(argv[1]) == "--ast";
    if (argc == 3 && !show_ast) {
      std::cerr << "usage: cpp_source_vm [--ast] <source.cpp>\n";
      return 1;
    }

    const std::string path = argv[show_ast ? 2 : 1];
    FunctionTable functions =
        compile_cpp_with_gcc_ast(path, show_ast ? &std::cout : nullptr);
    VirtualMachine vm(std::move(functions), std::cout);
    return vm.run();
  } catch (const std::exception& error) {
    std::cerr << "error: " << error.what() << '\n';
    return 1;
  }
}
