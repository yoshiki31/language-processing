#include "gcc_ast_frontend.hpp"

#include <cassert>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace {
std::string execute(const std::string& source) {
  const auto path = std::filesystem::temp_directory_path() / "cpp_vm_test.cpp";
  std::ofstream output(path);
  output << source;
  output.close();

  std::ostringstream vm_output;
  VirtualMachine vm(compile_cpp_with_gcc_ast(path.string()), vm_output);
  assert(vm.run() == 0);
  std::filesystem::remove(path);
  return vm_output.str();
}
}  // namespace

int main() {
  assert(execute("int main(){ print(1 + 2 * 3); return 0; }") == "7\n");
  assert(execute("int main(){ int x=10; x=x+5; print(x); return 0; }") ==
         "15\n");
  assert(execute("int main(){ int i=1; int r=1; while(i<6){r=r*i; i=i+1;} "
                 "print(r); return 0; }") == "120\n");
}
