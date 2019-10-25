require "utils/result.rb"

#
# 四則演算を評価するクラス
#
class AddDiceEvaluator
  # 四則演算を評価する
  # @param [String] expr 評価する式
  # @param [Symbol] round_type 端数処理の設定 :omit 切り捨て, :roundUp 切り上げ, :roundOff 四捨五入
  # @return [Integer]
  def eval(expr, sort_type, bcdice, dicebot, round_type = :omit)
    @tokens = tokenize(expr)
    @idx = 0
    @error = false
    @sort_type = sort_type
    @round_type = round_type
    @bcdice = bcdice
    @dicebot = dicebot

    @roll_times = 0
    @sides_max = 0
    @n1 = 0 # 出目１の回数
    @n_max = 0 # 出目の最大値
    @dice_total = 0 # 出目の合計

    return expr()
  end

  def error?
    @error
  end

  private

  def tokenize(expr)
    tokens = expr.upcase.gsub(%r{[\(\)\+\-\*\/DRUS\?]|[<>=!]+}) { |e| " #{e} " }.split(' ')
    if tokens[0] == "S"
      tokens.shift()
    end
    return tokens
  end

  ### Grammar ###
  # expr  := add (COND_OP add trail)?
  # add   := mul ("+" mul | "-" mul)*
  # add_  := mul_ ("+" mul_ | "-" mul_)*
  # mul   := d ("*" d | "/" d ("U"|"R")?)*
  # mul_  := d_ ("*" d_ | "/" d_ ("U"|"R")?)*
  # d     := unary
  #        | unary "D" term trail
  #        | unary "D" trail
  #        | "D" term trail
  # d_    := unary
  # unary := ("+" | "-")* term
  # term  := "(" add_ ")"
  #        | NUMBER
  # trail := ("@" unary)?
  # NUMBER  := [0..9]+
  # COND_OP := [><=!]+

  def expr
    ret = add(true)
    output = if ret.expr.match(/^\d+\[\d*\]$/)
      ret.value.to_s
    else
      "#{ret.expr} ＞ #{ret.value}"
    end

    condop = try_condop()
    if condop
      @dicebot.setDiceText(output)
      cond = consume("?") ? "?" : add(false).value

      msg = @bcdice.check_suc(ret.value, @dice_total, condop, cond, @roll_times, @sides_max, @n1, @n_max)
      output += msg
    end

    output += @dicebot.getDiceRolledAdditionalText(@n1, @n_max, @sides_max)

    return output
  end

  def add(allow_dice)
    ret = mul(allow_dice)

    loop do
      if consume("+")
        ret += mul(allow_dice)
      elsif consume("-")
        ret -= mul(allow_dice)
      else
        break
      end
    end

    return ret
  end

  def mul(allow_dice)
    ret = d(allow_dice)

    loop do
      if consume("*")
        ret *= d(allow_dice)
      elsif consume("/")
        a = d(allow_dice)
        ret = div(ret, a)
      else
        break
      end
    end

    return ret
  end

  def div(left, right)
    if right.zero?
      @error = true
      return Result.zero
    end

    if consume("U")
      round_type = :roundUp
    elsif consume("R")
      round_type = :roundOff
    else
      round_type = @round_type
    end

    case round_type
    when :roundUp
      return left.div_ceil(right, "U")
    when :roundOff
      return left.div_round(right, "R")
    else
      return left / right
    end
  end

  def d(allow_dice)
    unless allow_dice
      return unary()
    end

    if consume("D")
      sides = unary().value
      trail_params()

      value, text, n1_count, n_max = @bcdice.roll(1, sides, @sort_type)
      @roll_times += 1
      @sides_max = sides if @sides_max < sides
      @n1 += n1_count
      @n_max = n_max if n_max > @n_max
      @dice_total += value
      return Result.new(value, "#{value}[#{text}]")
    end

    ret = unary()
    if consume("D")
      times = ret.value
      sides = unary().value
      trail_params()

      value, text, n1_count, n_max = @bcdice.roll(times.abs(), sides, @sort_type)
      if times.negative?
        value = -value
      end
      @roll_times += times.abs()
      @sides_max = sides if @sides_max < sides
      @n1 += n1_count
      @n_max = n_max if n_max > @n_max
      @dice_total += value
      ret = Result.new(value, "#{value}[#{text}]")
    end

    return ret
  end

  def unary
    if consume("+")
      unary()
    elsif consume("-")
      -unary()
    else
      term()
    end
  end

  def try_term()
    if consume("(")
      ret = add(false)
      expect(")")
      return Result.new(ret.value, ret.value.to_s)
    else
      return try_number()
    end
  end

  def term
    ret = try_term()
    if ret.nil?
      @idx += 1
      @error = true
      return Result.zero
    end

    return ret
  end

  def trail_params
    if consume("@")
      @critical = unary().value
    end
  end

  def consume(str)
    if @tokens[@idx] != str
      return false
    end

    @idx += 1
    return true
  end

  def try_condop()
    unless /[<>=!]+/.match(@tokens[@idx])
      nil
    end

    ret = @bcdice.marshalSignOfInequality(@tokens[@idx])
    @idx += 1
    return ret
  end

  def nomalize_condop(condop)
    case condop
    when "<=", "=<"
      "<="
    when ">=", "=>"
      ">="
    when "<>"
      "!="
    when /<+/
      "<"
    when />+/
      ">"
    when /\=+/
      "=="
    else
      condop
    end
  end

  def expect(str)
    if @tokens[@idx] != str
      @error = true
    end

    @idx += 1
  end

  def try_number()
    unless integer?(@tokens[@idx])
      return nil
    end

    ret = @tokens[@idx].to_i
    @idx += 1
    return Result.new(ret, ret.to_s)
  end

  def integer?(str)
    # Ruby 1.9 以降では Kernel.#Integer を使うべき
    # Ruby 1.8 にもあるが、基数を指定できない問題がある
    !/^\d+$/.match(str).nil?
  end
end
