#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lexer"
require_relative "parser"
require_relative "compiler"
require_relative "virtual_machine"
require "optparse"
require "pp"
require "stringio"

DISPLAY_OPTIONS = {
  tokens: "字句解析結果（トークン列）",
  ast: "構文解析結果（AST）",
  bytecode: "コンパイル結果（バイトコード）",
  result: "実行結果"
}.freeze

def parse_options(argv)
  displays = []
  parser = OptionParser.new do |opts|
    opts.banner = "usage: ruby minicpp.rb [options] <source-file>"
    opts.on("--tokens", "字句解析結果を表示") { displays << :tokens }
    opts.on("--ast", "構文解析結果を表示") { displays << :ast }
    opts.on("--bytecode", "コンパイル結果を表示") { displays << :bytecode }
    opts.on("--result", "プログラムの出力と戻り値を表示") { displays << :result }
    opts.on("--all", "すべての処理結果を表示") { displays.replace(DISPLAY_OPTIONS.keys) }
  end
  parser.parse!(argv)
  [parser, displays.uniq]
end

def print_section(out, name)
  out.puts "== #{DISPLAY_OPTIONS.fetch(name)} =="
  yield
end

def print_bytecode(out, functions)
  functions.each_value do |function|
    out.puts "#{function[:name]} (引数: #{function[:nparams]}, ローカル変数: #{function[:nlocals]})"
    function[:code].each_with_index do |instruction, address|
      operands = instruction.drop(1).map(&:inspect)
      out.printf "  %04d: %s\n", address, ([instruction[0]] + operands).join(" ")
    end
  end
end

def main(argv, out: $stdout, err: $stderr)
  option_parser, displays = parse_options(argv)
  if argv.length != 1
    err.puts option_parser
    return 1
  end

  source = File.read(argv.fetch(0))
  tokens = MiniCpp.tokenize(source)
  if displays.include?(:tokens)
    print_section(out, :tokens) { PP.pp(tokens, out) }
  end

  return 0 if displays.any? && (displays & [:ast, :bytecode, :result]).empty?

  ast = MiniCpp.parse(tokens)
  if displays.include?(:ast)
    print_section(out, :ast) { PP.pp(ast, out) }
  end

  return 0 if displays.any? && (displays & [:bytecode, :result]).empty?

  functions = MiniCpp.compile(ast)
  if displays.include?(:bytecode)
    print_section(out, :bytecode) { print_bytecode(out, functions) }
  end

  return 0 if displays.any? && !displays.include?(:result)

  if displays.include?(:result)
    program_output = StringIO.new
    result = MiniCpp::VM.new(functions, output: program_output).run
    print_section(out, :result) do
      out.print program_output.string
      out.puts "戻り値: #{result.inspect}"
    end
  else
    MiniCpp::VM.new(functions, output: out).run
  end
  0
rescue OptionParser::ParseError => e
  err.puts "error: #{e.message}"
  err.puts "usage: ruby minicpp.rb [options] <source-file>"
  1
rescue Errno::ENOENT => e
  err.puts "error: #{e.message}"
  1
rescue RuntimeError => e
  err.puts "error: #{e.message}"
  1
end

exit main(ARGV) if $PROGRAM_NAME == __FILE__
