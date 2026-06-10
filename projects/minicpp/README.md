# MiniC++

Ruby版の処理系を段階的に実装しています。現在は字句解析と構文解析まで実装済みです。

```text
MiniC++ソースコード
  -> Ruby製字句解析器
  -> トークン列
  -> Ruby製構文解析器
  -> AST（抽象構文木）
```

実行:

```console
$ ruby minicpp.rb examples/01_arithmetic.mcpp
[:program, [[:function, "main", [], [:block, ...]]]]
```

テスト:

```console
$ ruby test_lexer.rb
$ ruby test_parser.rb
```

トークンは教材と同じRubyの配列 `[:種類, 値]` で保持します。例えば識別子
`abc` は `[:ident, "abc"]`、整数 `123` は `[:int, 123]` です。
