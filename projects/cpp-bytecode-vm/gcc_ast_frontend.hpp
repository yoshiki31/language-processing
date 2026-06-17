#ifndef GCC_AST_FRONTEND_HPP
#define GCC_AST_FRONTEND_HPP

#include "cpp_virtual_machine.hpp"

#include <iosfwd>
#include <string>

FunctionTable compile_cpp_with_gcc_ast(const std::string& source_path,
                                       std::ostream* ast_output = nullptr);

#endif
