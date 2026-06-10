#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lexer"
require_relative "parser"

def main(argv)
  if argv.length != 1
    warn "usage: ruby minicpp.rb <source-file>"
    return 1
  end

  source = File.read(argv.fetch(0))
  tokens = MiniCpp.tokenize(source)
  puts MiniCpp.parse(tokens).inspect
  0
rescue Errno::ENOENT => e
  warn "error: #{e.message}"
  1
rescue RuntimeError => e
  warn "error: #{e.message}"
  1
end

exit main(ARGV) if $PROGRAM_NAME == __FILE__
