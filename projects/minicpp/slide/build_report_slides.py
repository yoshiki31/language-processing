#!/usr/bin/env python3
import html
import re
import zipfile
from pathlib import Path


BASE = Path(__file__).resolve().parent
TEMPLATE = BASE / "テンプレート.pptx"
OUTPUT = BASE / "minicpp_final_report.pptx"

SLIDE_W = 18_288_000
SLIDE_H = 10_287_000


slides = [
    {
        "kind": "title",
        "title": "MiniC++: GC方式を比較できる自作VM",
        "subtitle": "配列内参照・循環参照・Mark & Sweep / Mark & Compact・自動GC",
        "name": "言語処理系 最終レポート",
    },
    {
        "title": "今日の主張",
        "bullets": [
            "MiniC++は、C++風構文をバイトコードVMで実行する小さな言語処理系",
            "最低要件の関数・配列に加え、VMヒープとGCを実装した",
            "配列の中に配列参照を格納でき、循環参照も作れる",
            "Mark & Sweep と Mark & Compact を同じVMで比較できる",
            "自動GC・統計・ベンチマークにより、GC方式の違いを観察できる",
        ],
    },
    {
        "title": "処理系の全体像",
        "bullets": [
            "ソースコード -> 字句解析 -> 構文解析 -> AST -> バイトコード -> スタックVM",
            "VMは値スタックと関数フレームを持つ",
            "関数呼び出しは Frame(func, pc, locals) を積んで実行",
            "配列本体はVMヒープに置き、変数にはObjectRefを持つ",
        ],
        "code": [
            "MiniC++ source",
            "  -> tokens -> AST -> bytecode",
            "  -> stack VM + heap + GC",
        ],
    },
    {
        "title": "デモ対象の言語機能",
        "bullets": [
            "関数: 引数・戻り値・再帰呼び出し",
            "配列: new int[n], a[i], a[i] = value",
            "多段配列: int[][] arrays",
            "配列内参照: arrays[0] = values",
            "GC: gc(), compact_gc(), 閾値による自動GC",
        ],
        "code": [
            "int[][] arrays = new int[1];",
            "int[] values = new int[1];",
            "values[0] = 42;",
            "arrays[0] = values;",
            "return arrays[0][0];",
        ],
    },
    {
        "title": "Ruby GCではなくMiniC++ VMのGC",
        "two_col": [
            {
                "heading": "Ruby GC",
                "items": [
                    "Rubyオブジェクトの実メモリを管理",
                    "MiniC++の変数やVMスタックの意味は知らない",
                    "MiniC++仮想アドレスを詰め替えない",
                ],
            },
            {
                "heading": "MiniC++ GC",
                "items": [
                    "MiniC++のスタック・localsをルートにする",
                    "配列要素内のObjectRefも辿る",
                    "Compact時にObjectRef.addressを書き換える",
                ],
            },
        ],
    },
    {
        "title": "VMヒープと配列内参照",
        "heap_diagram": True,
        "bullets": [
            "変数は配列本体ではなく ObjectRef(address) を持つ",
            "配列要素には整数だけでなく ObjectRef も入る",
            "GCは stack -> locals -> array elements を再帰的に辿る",
            "mark済みなら再訪問しないので循環参照でも止まる",
        ],
    },
    {
        "title": "Mark & Sweep と Mark & Compact",
        "two_col": [
            {
                "heading": "Mark & Sweep",
                "items": [
                    "到達不能Entryをnilにする",
                    "オブジェクトは移動しない",
                    "参照更新が不要",
                    "ヒープに穴が残る",
                ],
            },
            {
                "heading": "Mark & Compact",
                "items": [
                    "生存Entryだけを前に詰める",
                    "古いaddress -> 新しいaddressを記録",
                    "stack / locals / 配列要素の参照を更新",
                    "断片化を0にできる",
                ],
            },
        ],
    },
    {
        "title": "自動GCと統計",
        "bullets": [
            "配列確保時にヒープ上の生存オブジェクト数を確認",
            "閾値以上なら sweep または compact を自動実行",
            "CLIから --gc-strategy sweep|compact と --gc-threshold を指定",
            "統計: GC回数、GC時間、回収数、移動数、参照更新数、断片化率",
        ],
        "code": [
            "ruby minicpp.rb --result --gc-stats \\",
            "  --gc-strategy compact --gc-threshold 128 \\",
            "  examples/10_compact_gc.mcpp",
        ],
    },
    {
        "title": "ベンチマーク結果",
        "bullets": [
            "条件: iterations=1000, threshold=128",
            "短命配列: すぐ不要になる配列を大量生成",
            "生存率10%: 一部の配列だけkeep配列から参照",
            "循環参照: 到達不能な a <-> b を大量生成",
        ],
        "code": [
            "case                 GC       total  gc_ms  collected  moved  upd_ref  frag",
            "short_lived          sweep    23.64  0.20   889        0      0      0.133",
            "short_lived          compact  17.86  0.21   889        7      7      0.000",
            "survival_10_percent  sweep    23.06  2.42   884        0      0      0.086",
            "survival_10_percent  compact  30.41  6.84   884        34     34     0.000",
            "cyclic_references    sweep    23.76  0.26   1890       0      0      0.141",
            "cyclic_references    compact  22.55  0.42   1890       30     30     0.000",
        ],
    },
    {
        "title": "短命オブジェクトベンチマーク",
        "short_lived_benchmark": True,
        "bullets": [
            "各ループで int[] を1個作り、次のループでは前の配列が不要になる",
            "同じ条件で5回実行し、平均・最小・最大を確認",
            "回収数は同じなので、違いは移動・参照更新・断片化に出る",
            "短命中心では生存オブジェクトが少なく、Compactの移動対象も少ない",
        ],
        "code": [
            "条件: iterations=1000, threshold=128, runs=5",
            "GC       avg_total  min-max total  avg_gc  collected  moved  upd_ref  heap/live  frag",
            "sweep    14.361     14.075-14.931  0.093   889        0      0        128/111   0.133",
            "compact  9.350      8.922-9.773    0.104   889        7      7        111/111   0.000",
            "",
            "考察: Compactは7個の移動と7個の参照更新で断片化を0にした。",
            "      Compact後はnil探索を省略し、次の確保は末尾追加にできる。",
        ],
    },
    {
        "title": "GC方式選択ベンチマーク",
        "strategy_decision_benchmark": True,
        "bullets": [
            "生存率10%,30%,50%でSweepとCompactのコストを比較",
            "条件: iterations=1000, threshold=256",
            "見る指標: Compact追加GC時間、断片化削減量、移動/参照更新数",
        ],
    },
    {
        "title": "ベンチマークの考察",
        "bullets": [
            "Compactは全ケースで断片化率0.000: ヒープの穴を消せている",
            "Compactは生存オブジェクトが多いほど移動・参照更新コストが増える",
            "Sweepは移動しないので軽いが、短命・循環ケースでヒープに穴が残る",
            "循環参照は参照カウントでは苦手だが、Mark系GCでは到達不能なら回収できる",
            "結論: Sweepは単純で軽い、Compactは高コストだがメモリ配置をきれいに保てる",
        ],
    },
    {
        "title": "発表デモ",
        "bullets": [
            "1. int[][] で配列内参照を実行: examples/09_nested_arrays.mcpp",
            "2. compact_gc() でヒープを詰めても arrays[0][0] が読める",
            "3. --gc-stats で moved_objects / updated_references を確認",
            "4. benchmarks/gc_benchmark.rb で Sweep と Compact を比較",
        ],
        "code": [
            "ruby minicpp.rb --result examples/09_nested_arrays.mcpp",
            "ruby minicpp.rb --result --gc-stats \\",
            "  --gc-strategy compact --gc-threshold 3 \\",
            "  examples/10_compact_gc.mcpp",
            "ruby benchmarks/gc_benchmark.rb 1000 128",
        ],
    },
    {
        "title": "今後の課題: 世代別GC",
        "bullets": [
            "世代別GCは「多くのオブジェクトは若くして死ぬ」という仮説を使う",
            "MiniC++で本格実装するなら young / old 世代、promotion、minor GC が必要",
            "配列内参照があるため old -> young 参照を記録する write barrier が必要",
            "今回の到達可能性・参照更新・統計基盤は、世代別GCへの土台になる",
            "最終的にはGC方式を切り替えて、停止時間・断片化・更新コストを比較したい",
        ],
    },
]


def esc(text):
    return html.escape(str(text), quote=True)


def tag_text(shape_id, x, y, w, h, text, size=2800, color="1E1E1E", bold=False, align="l"):
    b = "1" if bold else "0"
    return f"""
<p:sp><p:nvSpPr><p:cNvPr id="{shape_id}" name="TextBox {shape_id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>
<p:txBody><a:bodyPr lIns="0" tIns="0" rIns="0" bIns="0" rtlCol="0" anchor="t"><a:spAutoFit/></a:bodyPr><a:lstStyle/>
<a:p><a:pPr algn="{align}"/><a:r><a:rPr lang="ja-JP" altLang="en-US" sz="{size}" b="{b}" dirty="0"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill><a:latin typeface="セザンヌ Bold"/><a:ea typeface="セザンヌ Bold"/><a:cs typeface="セザンヌ Bold"/></a:rPr><a:t>{esc(text)}</a:t></a:r></a:p>
</p:txBody></p:sp>"""


def bullet_box(shape_id, x, y, w, h, bullets, size=2600):
    paras = []
    for item in bullets:
        paras.append(
            f"""<a:p><a:pPr marL="390000" indent="-260000"><a:lnSpc><a:spcPct val="135000"/></a:lnSpc><a:spcBef><a:spcPts val="800"/></a:spcBef><a:buFont typeface="Arial"/><a:buChar char="•"/></a:pPr><a:r><a:rPr lang="ja-JP" altLang="en-US" sz="{size}" b="0" dirty="0"><a:solidFill><a:srgbClr val="1E1E1E"/></a:solidFill><a:latin typeface="セザンヌ Medium"/><a:ea typeface="セザンヌ Medium"/><a:cs typeface="セザンヌ Medium"/></a:rPr><a:t>{esc(item)}</a:t></a:r></a:p>"""
        )
    return f"""
<p:sp><p:nvSpPr><p:cNvPr id="{shape_id}" name="TextBox {shape_id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>
<p:txBody><a:bodyPr lIns="0" tIns="0" rIns="0" bIns="0" rtlCol="0" anchor="t"><a:spAutoFit/></a:bodyPr><a:lstStyle/>{''.join(paras)}</p:txBody></p:sp>"""


def rect(shape_id, x, y, w, h, color, alpha=None, line=None, radius="roundRect"):
    alpha_xml = f"<a:alpha val=\"{alpha}\"/>" if alpha else ""
    line_xml = "<a:ln><a:noFill/></a:ln>" if not line else f"<a:ln w=\"16000\"><a:solidFill><a:srgbClr val=\"{line}\"/></a:solidFill></a:ln>"
    return f"""
<p:sp><p:nvSpPr><p:cNvPr id="{shape_id}" name="Shape {shape_id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm><a:prstGeom prst="{radius}"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="{color}">{alpha_xml}</a:srgbClr></a:solidFill>{line_xml}</p:spPr></p:sp>"""


def line(shape_id, x, y, w, color="003479"):
    return f"""
<p:sp><p:nvSpPr><p:cNvPr id="{shape_id}" name="Line {shape_id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="0"/></a:xfrm><a:prstGeom prst="line"><a:avLst/></a:prstGeom><a:ln w="19050" cap="flat"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill></a:ln></p:spPr></p:sp>"""


def arrow(shape_id, x, y, w, color="003479"):
    return f"""
<p:sp><p:nvSpPr><p:cNvPr id="{shape_id}" name="Arrow {shape_id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="0"/></a:xfrm><a:prstGeom prst="line"><a:avLst/></a:prstGeom><a:ln w="26000" cap="flat"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill><a:tailEnd type="triangle" w="sm" len="sm"/></a:ln></p:spPr></p:sp>"""


def decorative_bands(start_id):
    return (
        rect(start_id, 15_250_000, -1_200_000, 950_000, 4_000_000, "4DCAFF", "42000", radius="rect")
        + rect(start_id + 1, 16_250_000, -300_000, 720_000, 4_800_000, "00086D", "30000", radius="rect")
        + rect(start_id + 2, -550_000, 7_250_000, 700_000, 3_500_000, "4DCAFF", "36000", radius="rect")
        + rect(start_id + 3, 17_050_000, 7_300_000, 850_000, 3_500_000, "00086D", "26000", radius="rect")
    )


def slide_header(title, n, total):
    return (
        tag_text(2, 1_028_700, 647_701, 14_500_000, 600_000, title, 3200, "003479", True)
        + line(3, 1_028_700, 1_662_015, 16_230_600)
        + tag_text(90, 1_028_700, 9_780_000, 3_000_000, 250_000, "MiniC++ VM", 1100, "666666")
        + tag_text(91, 16_700_000, 9_780_000, 500_000, 250_000, str(n), 1100, "666666", align="r")
    )


def code_box(shape_id, x, y, w, h, lines):
    text = "\n".join(lines)
    font_size = 1300 if len(lines) > 5 else 1700
    return f"""
<p:sp><p:nvSpPr><p:cNvPr id="{shape_id}" name="Code {shape_id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm><a:prstGeom prst="roundRect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="F4F7FB"/></a:solidFill><a:ln w="12000"><a:solidFill><a:srgbClr val="C7D7EA"/></a:solidFill></a:ln></p:spPr>
<p:txBody><a:bodyPr lIns="180000" tIns="150000" rIns="180000" bIns="150000" rtlCol="0" anchor="t"><a:spAutoFit/></a:bodyPr><a:lstStyle/>
<a:p><a:r><a:rPr lang="en-US" sz="{font_size}" dirty="0"><a:solidFill><a:srgbClr val="1E1E1E"/></a:solidFill><a:latin typeface="Consolas"/><a:ea typeface="游ゴシック"/></a:rPr><a:t>{esc(text)}</a:t></a:r></a:p>
</p:txBody></p:sp>"""


def heap_diagram(slide):
    xml = []
    sid = 30

    xml.append(rect(sid, 1_100_000, 2_360_000, 4_400_000, 1_250_000, "EAF4FB", line="B7D7ED"))
    sid += 1
    xml.append(tag_text(sid, 1_420_000, 2_600_000, 3_760_000, 330_000, "スタック / ローカル変数", 1650, "003479", True, "ctr"))
    sid += 1
    xml.append(tag_text(sid, 1_430_000, 3_020_000, 3_740_000, 350_000, "Value.object(ObjectRef(address=0))", 1450, "1E1E1E", True, "ctr"))
    sid += 1

    xml.append(arrow(sid, 5_700_000, 3_000_000, 1_350_000))
    sid += 1
    xml.append(tag_text(sid, 5_780_000, 2_600_000, 1_250_000, 260_000, "address=0", 1150, "003479", True, "ctr"))
    sid += 1

    xml.append(rect(sid, 7_250_000, 2_020_000, 5_500_000, 2_250_000, "F7F9FC", line="CCD8E5"))
    sid += 1
    xml.append(tag_text(sid, 7_520_000, 2_250_000, 4_950_000, 320_000, "Heap インスタンス", 1700, "003479", True))
    sid += 1
    xml.append(tag_text(sid, 7_520_000, 2_710_000, 4_950_000, 280_000, "@objects は Ruby の配列", 1250, "666666"))
    sid += 1
    xml.append(rect(sid, 7_620_000, 3_170_000, 4_850_000, 780_000, "EAF4FB", line="B7D7ED"))
    sid += 1
    xml.append(tag_text(sid, 7_860_000, 3_395_000, 900_000, 250_000, "[0]", 1450, "003479", True, "ctr"))
    sid += 1
    xml.append(tag_text(sid, 8_760_000, 3_390_000, 3_350_000, 270_000, "Entry(object, marked=false)", 1450, "1E1E1E", True, "ctr"))
    sid += 1

    xml.append(arrow(sid, 12_950_000, 3_540_000, 1_000_000))
    sid += 1
    xml.append(tag_text(sid, 12_850_000, 3_170_000, 1_250_000, 250_000, "Entry.object", 1150, "003479", True, "ctr"))
    sid += 1

    xml.append(rect(sid, 14_050_000, 2_750_000, 3_250_000, 1_610_000, "FFF9E8", line="E5C96D"))
    sid += 1
    xml.append(tag_text(sid, 14_310_000, 3_000_000, 2_700_000, 310_000, "IntArray インスタンス", 1500, "9A6A00", True, "ctr"))
    sid += 1
    xml.append(tag_text(sid, 14_250_000, 3_430_000, 2_850_000, 250_000, "@elements", 1200, "666666", False, "ctr"))
    sid += 1
    xml.append(tag_text(sid, 14_250_000, 3_760_000, 2_850_000, 260_000, "[Value.int(0), Value.int(10), ...]", 1100, "1E1E1E", False, "ctr"))
    sid += 1

    xml.append(rect(sid, 1_150_000, 5_060_000, 16_000_000, 1_200_000, "F6F8FA", line="D6E0EA"))
    sid += 1
    xml.append(tag_text(sid, 1_520_000, 5_300_000, 15_250_000, 260_000, "ポイント", 1550, "003479", True))
    sid += 1
    xml.append(bullet_box(sid, 1_520_000, 5_650_000, 15_250_000, 420_000, slide["bullets"], 1250))
    sid += 1

    xml.append(rect(sid, 1_150_000, 6_820_000, 16_000_000, 1_200_000, "F4F7FB", line="C7D7EA"))
    sid += 1
    xml.append(tag_text(sid, 1_520_000, 7_080_000, 15_250_000, 250_000, "つまり: Value は配列本体ではなくヒープ上の場所を持つ", 1450, "003479", True))
    sid += 1
    xml.append(tag_text(sid, 1_520_000, 7_470_000, 15_250_000, 250_000, "GC は Heap の Entry.marked を見て、生きている配列だけを残す", 1350, "1E1E1E"))

    return "".join(xml)


def ppt_table(shape_id, x, y, widths, row_h, rows, header_rows=1, alignments=None):
    grid_cols = "".join(f'<a:gridCol w="{width}"/>' for width in widths)
    table_rows = []
    for row_index, row in enumerate(rows):
        cells = []
        is_header = row_index < header_rows
        fill = "003479" if is_header else ("F7F9FC" if row_index % 2 == 1 else "EAF4FB")
        color = "FFFFFF" if is_header else "1E1E1E"
        bold = "1" if is_header else "0"
        for col_index, text in enumerate(row):
            align = alignments[col_index] if alignments else "ctr"
            cells.append(f"""
<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>
<a:p><a:pPr algn="{align}"/><a:r><a:rPr lang="ja-JP" altLang="en-US" sz="1120" b="{bold}" dirty="0"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill><a:latin typeface="Aptos"/><a:ea typeface="游ゴシック"/></a:rPr><a:t>{esc(text)}</a:t></a:r></a:p>
</a:txBody><a:tcPr marL="45720" marR="45720" marT="45720" marB="45720"><a:solidFill><a:srgbClr val="{fill}"/></a:solidFill>
<a:lnL w="6350"><a:solidFill><a:srgbClr val="D6E0EA"/></a:solidFill></a:lnL>
<a:lnR w="6350"><a:solidFill><a:srgbClr val="D6E0EA"/></a:solidFill></a:lnR>
<a:lnT w="6350"><a:solidFill><a:srgbClr val="D6E0EA"/></a:solidFill></a:lnT>
<a:lnB w="6350"><a:solidFill><a:srgbClr val="D6E0EA"/></a:solidFill></a:lnB>
</a:tcPr></a:tc>""")
        table_rows.append(f'<a:tr h="{row_h}">{"".join(cells)}</a:tr>')

    width = sum(widths)
    height = row_h * len(rows)
    return f"""
<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="{shape_id}" name="Table {shape_id}"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>
<p:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{width}" cy="{height}"/></p:xfrm>
<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">
<a:tbl><a:tblPr firstRow="1" bandRow="1"><a:tableStyleId>{{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}}</a:tableStyleId></a:tblPr><a:tblGrid>{grid_cols}</a:tblGrid>{"".join(table_rows)}</a:tbl>
</a:graphicData></a:graphic></p:graphicFrame>"""


def short_lived_benchmark_slide(slide):
    xml = []
    sid = 30

    xml.append(tag_text(sid, 1_250_000, 2_050_000, 15_600_000, 320_000, "条件: iterations=1000, threshold=128, runs=5", 1450, "555555", False))
    sid += 1

    headers = ["GC", "avg total", "avg GC", "collected", "moved", "updated", "heap/live", "frag"]
    rows = [
        ["Sweep", "14.361ms", "0.093ms", "889", "0", "0", "128/111", "0.133"],
        ["Compact", "9.350ms", "0.104ms", "889", "7", "7", "111/111", "0.000"],
    ]
    widths = [1_700_000, 2_050_000, 1_800_000, 1_700_000, 1_350_000, 1_550_000, 1_900_000, 1_350_000]
    x0 = 1_250_000
    y0 = 2_650_000
    h = 620_000
    xml.append(ppt_table(sid, x0, y0, widths, h, [headers, *rows]))
    sid += 1

    xml.append(tag_text(sid, 1_250_000, 4_760_000, 15_400_000, 350_000, "考察", 2100, "003479", True))
    sid += 1
    xml.append(rect(sid, 1_250_000, 5_220_000, 15_500_000, 2_950_000, "F6F8FA", line="D6E0EA"))
    sid += 1
    xml.append(bullet_box(sid, 1_620_000, 5_470_000, 14_850_000, 2_450_000, [
        "回収数はどちらも889個で同じ。不要オブジェクトの検出能力は同等。",
        "Sweepは移動・参照更新が0で単純だが、heap/live = 128/111 となり穴が残る。",
        "Compactは7個の移動と7個の参照更新を行い、heap/live = 111/111、断片化率0.000にできた。",
        "短命オブジェクト中心では生存数が少ないため、Compactの追加作業が小さく、断片化解消の効果が出やすい。",
        "実行時間はRuby上の測定で揺れるため、主張の中心は frag / moved / updated の構造的な差。",
    ], 1450))
    return "".join(xml)


def strategy_decision_benchmark_slide(slide):
    xml = []
    sid = 30

    xml.append(tag_text(sid, 1_250_000, 1_900_000, 15_600_000, 320_000, "目的: 低・中・高生存率でSweepとCompactの使い分け観点を見る", 1450, "555555", False))
    sid += 1

    headers = ["生存率", "方式", "total (ms)", "GC (ms)", "回収 (個)", "moved (個)", "updated (個)", "frag (率)"]
    rows = [
        ["10%", "Sweep", "24.551", "0.333", "770", "0", "0", "0.098"],
        ["10%", "Compact", "15.850", "0.697", "770", "5", "5", "0.000"],
        ["30%", "Sweep", "146.987", "108.784", "698", "0", "0", "0.000"],
        ["30%", "Compact", "296.646", "268.678", "698", "698", "698", "0.000"],
        ["50%", "Sweep", "218.224", "169.954", "498", "0", "0", "0.000"],
        ["50%", "Compact", "440.157", "404.119", "498", "498", "498", "0.000"],
    ]
    widths = [1_200_000, 1_550_000, 1_650_000, 1_550_000, 1_300_000, 1_350_000, 1_500_000, 1_200_000]
    x0 = 1_250_000
    y0 = 2_450_000
    h = 470_000
    alignments = ["ctr", "l", "r", "r", "r", "r", "r", "r"]
    xml.append(ppt_table(sid, x0, y0, widths, h, [headers, *rows], alignments=alignments))
    sid += 1

    xml.append(rect(sid, 1_250_000, 5_820_000, 15_500_000, 720_000, "F4F7FB", line="C7D7EA"))
    sid += 1
    xml.append(tag_text(sid, 1_520_000, 5_990_000, 14_950_000, 250_000, "ラベル: total=プログラム全体の実行時間、GC=GC処理の合計時間、frag=VMヒープ配列内の空きスロット率", 1150, "1E1E1E"))
    sid += 1
    xml.append(tag_text(sid, 1_250_000, 6_780_000, 15_400_000, 350_000, "考察", 2100, "003479", True))
    sid += 1
    xml.append(rect(sid, 1_250_000, 7_180_000, 15_500_000, 1_550_000, "F6F8FA", line="D6E0EA"))
    sid += 1
    xml.append(bullet_box(sid, 1_620_000, 7_400_000, 14_850_000, 1_100_000, [
        "10%ではCompactのmoved/updatedが5個で小さく、fragを0.098から0.000へ改善できた。",
        "30%ではSweepでもfragが0.000になり、Compactは698個の移動・参照更新だけが重く残る。",
        "50%ではCompactのGC時間が404.119msまで増え、Sweepの169.954msとの差がさらに大きい。",
        "この結果は実GCの基準そのものではなく、Compactの参照更新コストを観察する実験として位置づける。",
    ], 1120))
    return "".join(xml)


def normal_slide(slide, n, total):
    xml = [decorative_bands(20), slide_header(slide["title"], n, total)]
    sid = 30
    if "two_col" in slide:
        x_positions = [1_150_000, 9_350_000]
        for col, x in zip(slide["two_col"], x_positions):
            xml.append(rect(sid, x, 2_280_000, 7_250_000, 4_850_000, "F6F8FA", line="D6E0EA"))
            sid += 1
            xml.append(tag_text(sid, x + 360_000, 2_620_000, 6_500_000, 450_000, col["heading"], 2500, "003479", True))
            sid += 1
            xml.append(bullet_box(sid, x + 360_000, 3_250_000, 6_500_000, 3_600_000, col["items"], 2050))
            sid += 1
    elif slide.get("heap_diagram"):
        xml.append(heap_diagram(slide))
    elif slide.get("short_lived_benchmark"):
        xml.append(short_lived_benchmark_slide(slide))
    elif slide.get("strategy_decision_benchmark"):
        xml.append(strategy_decision_benchmark_slide(slide))
    elif "diagram" in slide:
        y = 2_230_000
        for left, right in slide["diagram"]:
            xml.append(rect(sid, 1_200_000, y, 5_050_000, 680_000, "EAF4FB", line="B7D7ED"))
            sid += 1
            xml.append(tag_text(sid, 1_440_000, y + 130_000, 4_600_000, 420_000, left, 1750, "003479", True))
            sid += 1
            xml.append(rect(sid, 6_850_000, y, 5_750_000, 680_000, "F7F9FC", line="CCD8E5"))
            sid += 1
            xml.append(tag_text(sid, 7_100_000, y + 130_000, 5_300_000, 420_000, right, 1750, "1E1E1E"))
            sid += 1
            y += 850_000
        xml.append(bullet_box(sid, 13_250_000, 2_240_000, 3_850_000, 4_500_000, slide["bullets"], 1650))
    else:
        bullet_h = 3_650_000 if "code" in slide else 5_600_000
        bullet_size = 2050 if "code" in slide else 2350
        xml.append(bullet_box(sid, 1_350_000, 2_220_000, 15_000_000, bullet_h, slide["bullets"], bullet_size))
        sid += 1
        if "code" in slide:
            code_y = 6_100_000
            code_h = 2_500_000
            xml.append(code_box(sid, 1_700_000, code_y, 14_600_000, code_h, slide["code"]))
    return make_slide_xml("".join(xml))


def title_slide(slide, n, total):
    body = (
        decorative_bands(10)
        + tag_text(2, 1_300_000, 3_350_000, 15_600_000, 950_000, slide["title"], 5400, "1E1E1E", True, "ctr")
        + tag_text(3, 1_450_000, 4_520_000, 15_300_000, 520_000, slide["subtitle"], 2300, "003479", True, "ctr")
        + tag_text(4, 6_600_000, 5_650_000, 5_200_000, 430_000, slide["name"], 1900, "444444", False, "ctr")
        + tag_text(5, 7_000_000, 6_160_000, 4_400_000, 350_000, "2026/7/1", 1500, "666666", False, "ctr")
    )
    return make_slide_xml(body, background=True)


def make_slide_xml(body, background=False):
    bg = ""
    if background:
        bg = """<p:bg><p:bgPr><a:gradFill rotWithShape="1"><a:gsLst><a:gs pos="0"><a:srgbClr val="FFFFFF"><a:alpha val="100000"/></a:srgbClr></a:gs><a:gs pos="100000"><a:srgbClr val="E8EAED"><a:alpha val="100000"/></a:srgbClr></a:gs></a:gsLst><a:path path="circle"><a:fillToRect l="50000" t="50000" r="50000" b="50000"/></a:path></a:gradFill></p:bgPr></p:bg>"""
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld>{bg}<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>{body}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"""


def slide_rels():
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout7.xml"/></Relationships>"""


def presentation_xml(count):
    ids = "".join(f'<p:sldId id="{255 + i}" r:id="rId{1 + i}"/>' for i in range(1, count + 1))
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" embedTrueTypeFonts="1" saveSubsetFonts="1"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId20"/></p:sldMasterIdLst><p:notesMasterIdLst><p:notesMasterId r:id="rId21"/></p:notesMasterIdLst><p:sldIdLst>{ids}</p:sldIdLst><p:sldSz cx="{SLIDE_W}" cy="{SLIDE_H}"/><p:notesSz cx="6858000" cy="9144000"/><p:defaultTextStyle><a:defPPr><a:defRPr lang="en-US"/></a:defPPr></p:defaultTextStyle></p:presentation>"""


def presentation_rels(count):
    rels = []
    for i in range(1, count + 1):
        rels.append(f'<Relationship Id="rId{i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide{i}.xml"/>')
    rels.extend([
        '<Relationship Id="rId20" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>',
        '<Relationship Id="rId21" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" Target="notesMasters/notesMaster1.xml"/>',
        '<Relationship Id="rId22" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/font" Target="fonts/font1.fntdata"/>',
        '<Relationship Id="rId23" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/font" Target="fonts/font2.fntdata"/>',
        '<Relationship Id="rId24" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/font" Target="fonts/font3.fntdata"/>',
        '<Relationship Id="rId25" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/font" Target="fonts/font4.fntdata"/>',
        '<Relationship Id="rId26" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>',
        '<Relationship Id="rId27" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps" Target="viewProps.xml"/>',
        '<Relationship Id="rId28" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>',
        '<Relationship Id="rId29" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles" Target="tableStyles.xml"/>',
    ])
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{''.join(rels)}</Relationships>"""


def content_types_xml(count, original):
    xml = re.sub(r'<Override PartName="/ppt/slides/slide\d+\.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide\+xml"/>', "", original)
    slide_overrides = "".join(f'<Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>' for i in range(1, count + 1))
    return xml.replace("</Types>", f"{slide_overrides}</Types>")


def app_xml(count, original):
    xml = re.sub(r"<Slides>\d+</Slides>", f"<Slides>{count}</Slides>", original)
    xml = re.sub(r"<Words>\d+</Words>", "<Words>220</Words>", xml)
    return xml


def build():
    slide_xmls = []
    total = len(slides)
    for i, slide in enumerate(slides, start=1):
        if slide.get("kind") == "title":
            slide_xmls.append(title_slide(slide, i, total))
        else:
            slide_xmls.append(normal_slide(slide, i, total))

    with zipfile.ZipFile(TEMPLATE, "r") as zin:
        originals = {name: zin.read(name) for name in zin.namelist()}

    with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for name, data in originals.items():
            if name.startswith("ppt/slides/slide") and name.endswith(".xml"):
                continue
            if name.startswith("ppt/slides/_rels/slide") and name.endswith(".xml.rels"):
                continue
            if name in {"ppt/presentation.xml", "ppt/_rels/presentation.xml.rels", "[Content_Types].xml", "docProps/app.xml"}:
                continue
            zout.writestr(name, data)

        for i, xml in enumerate(slide_xmls, start=1):
            zout.writestr(f"ppt/slides/slide{i}.xml", xml)
            zout.writestr(f"ppt/slides/_rels/slide{i}.xml.rels", slide_rels())

        zout.writestr("ppt/presentation.xml", presentation_xml(total))
        zout.writestr("ppt/_rels/presentation.xml.rels", presentation_rels(total))
        zout.writestr("[Content_Types].xml", content_types_xml(total, originals["[Content_Types].xml"].decode("utf-8")))
        zout.writestr("docProps/app.xml", app_xml(total, originals["docProps/app.xml"].decode("utf-8")))


if __name__ == "__main__":
    build()
    print(OUTPUT)
