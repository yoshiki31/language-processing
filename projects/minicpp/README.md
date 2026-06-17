# MiniC++

Ruby版の処理系を段階的に実装しています。現在はスタックマシンVMでMiniC++を実行できます。

```text
MiniC++ソースコード
  -> Ruby製字句解析器
  -> トークン列
  -> Ruby製構文解析器
  -> AST（抽象構文木）
  -> バイトコードコンパイラ
  -> スタックマシンVM
```

実行:

```console
$ ruby minicpp.rb examples/01_arithmetic.mcpp
7
```

`int` 配列:

```cpp
int main() {
  int[] values = new int[3];
  values[0] = 10;
  values[1] = values[0] + 5;
  return values[1];
}
```

各処理段階の結果をすべて表示:

```console
$ ruby minicpp.rb --all examples/01_arithmetic.mcpp
== 字句解析結果（トークン列） ==
...
== 構文解析結果（AST） ==
...
== コンパイル結果（バイトコード） ==
...
== 実行結果 ==
7
戻り値: 0
```

個別に確認する場合は `--tokens`、`--ast`、`--bytecode`、`--result` を指定します。
複数のオプションを同時に指定することもできます。

テスト:

```console
$ ruby test_lexer.rb
$ ruby test_parser.rb
$ ruby test_virtual_machine.rb
$ ruby test_minicpp.rb
```

VMは値スタックと関数呼び出し用のフレームスタックを持ちます。コンパイラはASTを
`push`、`get_local`、`set_local`、`add`、`jump`、`call`、`ret`などの命令へ変換します。

トークンは教材と同じRubyの配列 `[:種類, 値]` で保持します。例えば識別子
`abc` は `[:ident, "abc"]`、整数 `123` は `[:int, 123]` です。
