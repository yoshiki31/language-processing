#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lexer"
require_relative "parser"
require_relative "compiler"
require_relative "virtual_machine"

def main(argv)
  if argv.length != 1
    warn "usage: ruby minicpp.rb <source-file>"
    return 1
  end

  source = File.read(argv.fetch(0))
  tokens = MiniCpp.tokenize(source)
  ast = MiniCpp.parse(tokens)
  MiniCpp.execute(ast)
  0
rescue Errno::ENOENT => e
  warn "error: #{e.message}"
  1
rescue RuntimeError => e
  warn "error: #{e.message}"
  1
end

exit main(ARGV) if $PROGRAM_NAME == __FILE__
