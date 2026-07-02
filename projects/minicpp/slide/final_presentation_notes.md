# MiniC++ 最終発表メモ（10分）

## 時間配分

- 1枚目: タイトル（20秒）
- 2枚目: 今日の主張（50秒）
- 3枚目: 処理系全体像（50秒）
- 4枚目: 言語機能とデモ対象（50秒）
- 5枚目: Ruby GCとの差別化（60秒）
- 6枚目: VMヒープと配列内参照（70秒）
- 7枚目: Mark & Sweep / Mark & Compact（80秒）
- 8枚目: 自動GCと統計（60秒）
- 9枚目: ベンチマーク結果（80秒）
- 10枚目: 考察（80秒）
- 11枚目: デモ（120秒）
- 12枚目: 今後の課題（40秒）

## 重点的に言うこと

今回の主張は「GCを1個作った」ではなく、「GC方式を比較できるVMを作った」こと。

Ruby GCとの差別化では、次を明確に言う。

- Ruby GCはRubyオブジェクトの実メモリ管理をする
- MiniC++ GCはMiniC++のVMスタック・ローカル変数・配列内参照をルートとして辿る
- Mark & CompactではMiniC++の仮想アドレスを移動し、ObjectRef.addressを書き換える
- これはRuby GCにはできない

ベンチマーク考察では、速さだけで勝敗を言わない。

- Sweepは参照更新が不要で単純
- Compactは移動と参照更新のコストがある
- しかしCompactは断片化率を0にできる
- 生存オブジェクトが多いほどCompactのコストが増える

## デモコマンド

```console
ruby minicpp.rb --result examples/09_nested_arrays.mcpp
```

```console
ruby minicpp.rb --result --gc-stats --gc-strategy compact --gc-threshold 3 examples/10_compact_gc.mcpp
```

```console
ruby benchmarks/gc_benchmark.rb 1000 128
```

## 質疑で聞かれそうな点

Q. RubyのGCではないのか？

A. 最終的なRubyオブジェクトのメモリ解放はRuby GCが行う可能性がある。ただし、MiniC++プログラムから到達可能かを判定し、MiniC++ヒープ上の仮想アドレスを詰め、ObjectRefを書き換えるのはMiniC++ VM側のGC。

Q. なぜ世代別GCまで実装しなかったのか？

A. 配列内に配列参照を格納できるため、世代別GCではold世代からyoung世代への参照を記録するwrite barrierが必要になる。今回はMark & Sweep / Mark & Compactの比較と、参照更新の正しさを優先した。

Q. Compactのほうが常に良いのか？

A. 良いとは限らない。断片化を消せる一方で、生存オブジェクトの移動と参照更新が必要なので、生存率が高いケースではコストが増える。
