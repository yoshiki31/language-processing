# frozen_string_literal: true

module MiniCpp
  module_function

  def tokenize(src)
    tokens = []
    source = src.dup

    until source.empty?
      case source
      when /\A\s+/
        # 空白と改行は読み飛ばす。
      when %r{\A//[^\n]*}
        # 行末までのコメントは読み飛ばす。
      when /\A\d+/
        tokens << [:int, Regexp.last_match(0).to_i]
      when /\A[a-zA-Z_]\w*/
        tokens << [:ident, Regexp.last_match(0)]
      when %r{\A(==|[+\-*/<>=;(),{}\[\]])}
        # == を = より先に調べて最長一致させる。
        tokens << [:op, Regexp.last_match(0)]
      else
        raise "字句解析エラー: #{source.inspect}"
      end

      source = Regexp.last_match.post_match
    end

    tokens << [:eof, nil]
  end
end
