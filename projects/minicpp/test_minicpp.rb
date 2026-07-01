# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tempfile"
require_relative "minicpp"

class MiniCppCliTest < Minitest::Test
  def run_cli(source, *options)
    Tempfile.create(["program", ".mcpp"]) do |file|
      file.write(source)
      file.flush
      out = StringIO.new
      err = StringIO.new
      status = main([*options, file.path], out: out, err: err)
      return [status, out.string, err.string]
    end
  end

  def test_default_execution_only_prints_program_output
    status, out, err = run_cli("int main() { puts(7); return 0; }")

    assert_equal 0, status
    assert_equal "7\n", out
    assert_empty err
  end

  def test_all_displays_every_processing_stage
    status, out, err = run_cli("int main() { puts(1 + 2); return 4; }", "--all")

    assert_equal 0, status
    assert_includes out, "== 字句解析結果（トークン列） =="
    assert_includes out, "[:ident, \"main\"]"
    assert_includes out, "== 構文解析結果（AST） =="
    assert_includes out, "[:add, [:int, 1], [:int, 2]]"
    assert_includes out, "== コンパイル結果（バイトコード） =="
    assert_includes out, "0002: add"
    assert_includes out, "== 実行結果 ==\n3\n戻り値: 4\n"
    assert_empty err
  end

  def test_tokens_can_be_displayed_without_parsing
    status, out, err = run_cli("int main(", "--tokens")

    assert_equal 0, status
    assert_includes out, "[:ident, \"main\"]"
    assert_empty err
  end

  def test_individual_ast_option_does_not_execute_program
    status, out, err = run_cli("int main() { puts(9); return 0; }", "--ast")

    assert_equal 0, status
    assert_includes out, "== 構文解析結果（AST） =="
    refute_match(/^9$/, out)
    assert_empty err
  end

  def test_gc_stats_option_displays_automatic_gc_statistics
    source = <<~MINICPP
      int main() {
        int[] old_values = new int[1];
        int[] live_values = new int[1];
        old_values = live_values;
        int[] new_values = new int[1];
        return 0;
      }
    MINICPP

    status, out, err = run_cli(source, "--result", "--gc-stats", "--gc-strategy", "sweep", "--gc-threshold", "2")

    assert_equal 0, status
    assert_includes out, "== GC統計 =="
    assert_includes out, "auto_gc_count: 1"
    assert_includes out, "sweep_count: 1"
    assert_includes out, "collected_objects: 1"
    assert_empty err
  end
end
