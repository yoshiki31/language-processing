# C++ Bytecode VM

G++の既存C++パーサでソースコードからGCC ASTを構築し、そのASTを
バイトコードへ変換して実行するC++17製スタックVMです。

```text
C++ソース
  -> G++パーサ・意味解析
  -> GCC AST
  -> VMバイトコード
  -> C++製インタプリタ型VM
```

`print(expression)` はVM組み込み出力として扱います。フロントエンドが
`extern int print(int);` の宣言を解析時に補います。

C++ソースを実行:

```console
$ g++ -std=c++17 -Wall -Wextra -pedantic \
    cpp_virtual_machine.cpp gcc_ast_frontend.cpp cpp_source_vm.cpp \
    -o cpp_source_vm
$ ./cpp_source_vm examples/03_control.cpp
120
```

GCC ASTも表示:

```console
$ ./cpp_source_vm --ast examples/01_arithmetic.cpp
```

対応範囲は整数変数、四則演算、比較、代入、`if`、`while`、`return`、
`print`です。クラス、ポインタ、配列、テンプレートなどは未対応です。

GCC ASTフロントエンドのテスト:

```console
$ g++ -std=c++17 -Wall -Wextra -pedantic \
    cpp_virtual_machine.cpp gcc_ast_frontend.cpp test_gcc_ast_frontend.cpp \
    -o test_gcc_ast_frontend
$ ./test_gcc_ast_frontend
```

## 手書き命令列の例

VMへ生成済み命令列を直接渡す従来例も残しています。

```console
$ g++ -std=c++17 -Wall -Wextra -pedantic \
    cpp_virtual_machine.cpp cpp_vm_example.cpp \
    -o cpp_vm_example
$ ./cpp_vm_example
55
```

テスト:

```console
$ g++ -std=c++17 -Wall -Wextra -pedantic \
    cpp_virtual_machine.cpp test_cpp_virtual_machine.cpp \
    -o test_cpp_vm
$ ./test_cpp_vm
```
