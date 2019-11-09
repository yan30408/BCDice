# -*- coding: utf-8 -*-

require "utils/ArithmeticEvaluator"
require "utils/normalize"

class AddDice
  include Normalize

  def initialize(diceBot, randomizer)
    @diceBot = diceBot
    @randomizer = randomizer
  end

  ####################             加算ダイス        ########################

  def rollDice(string)
    debug("AddDice.rollDice() begin string", string)

    m = %r{(^|\s)S?(([\d\+\*\-]*[\d]+D[\d/UR@]*[\d\+\*\-D/UR]*)(([<>=]+)([?\-\d]+))?)($|\s)}i.match(string)
    return "1" unless m

    string = m[2]
    judgeText = m[4] # '>=10'といった成否判定文字
    judgeOperator = m[5] # '>=' といった判定の条件演算子 文字
    diffText = m[6]

    signOfInequality = ""
    isCheckSuccess = false

    if judgeText
      isCheckSuccess = true
      string = m[3]
      signOfInequality = marshalSignOfInequality(judgeOperator)
    end

    dice_cnt = 0
    dice_max = 0
    total_n = 0
    dice_n = 0
    output = ""
    n1 = 0
    n_max = 0

    addUpTextList = string.split("+")

    addUpTextList.each do |addUpText|
      subtractTextList = addUpText.split("-")

      subtractTextList.each_with_index do |subtractText, index|
        next if subtractText.empty?

        debug("begin rollDiceAddingUp(subtractText, isCheckSuccess)", subtractText, isCheckSuccess)
        dice_now, dice_n_wk, dice_str, n1_wk, n_max_wk, cnt_wk, max_wk = rollDiceAddingUp(subtractText, isCheckSuccess)
        debug("end rollDiceAddingUp(subtractText, isCheckSuccess) -> dice_now", dice_now)

        rate = (index == 0 ? 1 : -1)

        total_n += dice_now * rate
        dice_n += dice_n_wk * rate
        n1 += n1_wk
        n_max += n_max_wk
        dice_cnt += cnt_wk
        dice_max = max_wk if max_wk > dice_max

        next if @diceBot.sendMode == 0

        operatorText = getOperatorText(rate, output)
        output += "#{operatorText}#{dice_str}"
      end
    end

    if signOfInequality != ""
      string += "#{signOfInequality}#{diffText}"
    end

    @diceBot.setDiceText(output)
    @diceBot.setDiffText(diffText)

    # ダイス目による補正処理（現状ナイトメアハンターディープ専用）
    addText, revision = @diceBot.getDiceRevision(n_max, dice_max, total_n)
    debug('addText, revision', addText, revision)

    if @diceBot.sendMode > 0
      if output =~ /[^\d\[\]]+/
        output = ": (#{string}) ＞ #{output} ＞ #{total_n}#{addText}"
      else
        output = ": (#{string}) ＞ #{total_n}#{addText}"
      end
    else
      output = ": (#{string}) ＞ #{total_n}#{addText}"
    end

    total_n += revision

    if signOfInequality != "" # 成功度判定処理
      successText = check_suc(total_n, dice_n, signOfInequality, diffText, dice_cnt, dice_max, n1, n_max)
      debug("check_suc successText", successText)
      output += successText
    end

    # ダイスロールによるポイント等の取得処理用（T&T悪意、ナイトメアハンター・ディープ宿命、特命転校生エクストラパワーポイントなど）
    output += @diceBot.getDiceRolledAdditionalText(n1, n_max, dice_max)

    if (dice_cnt == 0) || (dice_max == 0)
      output = '1'
    end

    debug("AddDice.rollDice() end output", output)
    return output
  end

  def rollDiceAddingUp(string, isCheckSuccess = false) # 加算ダイスロール(個別処理)
    debug("rollDiceAddingUp() begin string", string)

    dice_max = 0
    dice_total = 1
    dice_n = 0
    output = ""
    n1 = 0
    n_max = 0
    dice_cnt_total = 0
    double_check = false

    if @diceBot.sameDiceRerollCount != 0 # 振り足しありのゲームでダイスが二個以上
      if @diceBot.sameDiceRerollType <= 0 # 判定のみ振り足し
        debug('判定のみ振り足し')
        double_check = true if isCheckSuccess
      elsif  @diceBot.sameDiceRerollType <= 1 # ダメージのみ振り足し
        debug('ダメージのみ振り足し')
        double_check = true unless isCheckSuccess
      else # 両方振り足し
        double_check = true
      end
    end

    debug("double_check", double_check)

    arithmethic = ArithmeticEvaluator.new
    while (m = /(^([\d]+\*[\d]+)\*(.+)|(.+)\*([\d]+\*[\d]+)$|(.+)\*([\d]+\*[\d]+)\*(.+))/.match(string))
      if  m[2]
        string = arithmethic.eval(m[2]).to_s + '*' + m[3]
      elsif  m[5]
        string = m[4] + '*' + arithmethic.eval(m[5]).to_s
      elsif  m[7]
        string = m[6] + '*' + arithmethic.eval(m[7]).to_s + '*' + m[8]
      end
    end

    debug("string", string)

    emptyResult = [dice_total, dice_n, output, n1, n_max, dice_cnt_total, dice_max]

    mul_cmd = string.split("*")
    mul_cmd.each do |mul_line|
      if (m = mul_line.match(%r{([\d]+)D([\d]+)(@(\d+))?(/\d+[UR]?)?}i))
        dice_count = m[1].to_i
        dice_max = m[2].to_i
        critical = m[4].to_i
        slashMark = m[5]

        return emptyResult if  (critical != 0) && !@diceBot.is2dCritical
        return emptyResult if  dice_max > $DICE_MAXNUM

        dice_max, dice_now, output_tmp, n1_count, max_number_tmp, result_dice_count =
          rollDiceAddingUpCommand(dice_count, dice_max, slashMark, double_check, isCheckSuccess, critical)

        output += "*" if output != ""
        output += output_tmp

        dice_total *= dice_now

        dice_n += dice_now
        dice_cnt_total += result_dice_count
        n1 += n1_count
        n_max += max_number_tmp

      else
        mul_line = mul_line.to_i
        debug('dice_total', dice_total)
        debug('mul_line', mul_line)

        dice_total *= mul_line

        unless output.empty?
          output += "*"
        end

        if mul_line < 0
          output += "(#{mul_line})"
        else
          output += mul_line.to_s
        end
      end
    end

    debug("rollDiceAddingUp() end output", dice_total, dice_n, output, n1, n_max, dice_cnt_total, dice_max)
    return dice_total, dice_n, output, n1, n_max, dice_cnt_total, dice_max
  end

  def rollDiceAddingUpCommand(dice_count, dice_max, slashMark, double_check, isCheckSuccess, critical)
    result_dice_count = 0
    dice_now = 0
    n1_count = 0
    max_number = 0
    dice_str = ""
    dice_arry = []
    dice_arry.push(dice_count)
    loop_count = 0

    debug("before while dice_arry", dice_arry)

    while !dice_arry.empty?
      debug("IN while dice_arry", dice_arry)

      dice_wk = dice_arry.shift
      result_dice_count += dice_wk

      debug('dice_wk', dice_wk)
      debug('dice_max', dice_max)
      debug('(sortType & 1)', (@diceBot.sortType & 1))

      dice_dat = rollLocal(dice_wk, dice_max, (@diceBot.sortType & 1))
      debug('dice_dat', dice_dat)

      dice_new = dice_dat[0]
      dice_now += dice_new

      debug('slashMark', slashMark)
      dice_now = getSlashedDice(slashMark, dice_now)

      dice_str += "][" if dice_str != ""
      debug('dice_str', dice_str)

      dice_str += dice_dat[1]
      n1_count += dice_dat[2]
      max_number += dice_dat[3]

      # 振り足しありでダイスが二個以上
      if double_check && (dice_wk >= 2)
        addDiceArrayByAddDiceCount(dice_dat, dice_max, dice_arry, dice_wk)
      end

      @diceBot.check2dCritical(critical, dice_new, dice_arry, loop_count)
      loop_count += 1
    end

    # ダイス目文字列からダイス値を変更する場合の処理（現状クトゥルフ・テック専用）
    dice_now = @diceBot.changeDiceValueByDiceText(dice_now, dice_str, isCheckSuccess, dice_max)

    output = ""
    if @diceBot.sendMode > 1
      output += "#{dice_now}[#{dice_str}]"
    elsif @diceBot.sendMode > 0
      output += dice_now.to_s
    end

    return dice_max, dice_now, output, n1_count, max_number, result_dice_count
  end

  def addDiceArrayByAddDiceCount(dice_dat, _dice_max, dice_queue, roll_times)
    values = dice_dat[1].split(",").map(&:to_i)
    count_bucket = {}

    values.each do |val|
      count_bucket[val] ||= 0
      count_bucket[val] += 1
    end

    reroll_threshold = @diceBot.sameDiceRerollCount == 1 ? roll_times : @diceBot.sameDiceRerollCount
    count_bucket.each do |_, num|
      if num >= reroll_threshold
        dice_queue.push(num)
      end
    end
  end

  def getSlashedDice(slashMark, lhs)
    m = %r{^/(\d+)(.)?$}i.match(slashMark)
    return lhs unless m

    rhs = m[1].to_i
    mark = m[2]

    return lhs if rhs == 0

    value = lhs.to_f / rhs

    if mark == "U"
      return value.ceil
    elsif mark == "R"
      return value.round
    else
      return value.floor
    end
  end

  # @return [Array<(Integer, String, Integer, Integer)>] 合計, ダイスのカンマ区切り, 出目1の数, 出目最大の数
  def rollLocal(times, sides, sort_type)
    if sides == 66
      return rollD66(times)
    end

    unless (times <= $DICE_MAXCNT) && (sides <= $DICE_MAXNUM)
      return 0, "", 0, 0
    end

    arr = @randomizer.roll_barabara(times, sides)
    if sort_type != 0
      arr = arr.sort()
    end

    value = arr.sum()
    text = arr.join(",")
    n1_count = arr.count(1)
    nsides_count = arr.count(sides)

    return value, text, n1_count, nsides_count
  end

  def rollD66(count)
    d66List = []

    count.times do
      d66List << getD66Value()
    end

    total = d66List.inject { |sum, i| sum + i }
    text = d66List.join(',')
    n1Count = d66List.count(1)
    nMaxCount = d66List.count(66)

    return [total, text, n1Count, nMaxCount, 0, 0, 0]
  end

  def getD66Value(mode = nil)
    mode ||= @diceBot.d66Type

    isSwap = (mode > 1)
    getD66(isSwap)
  end

  def getD66(isSwap)
    output = 0

    dice_a = @randomizer.rand(6)
    dice_b = @randomizer.rand(6)
    debug("dice_a", dice_a)
    debug("dice_b", dice_b)

    if isSwap && (dice_a > dice_b)
      # 大小でスワップするタイプ
      output = dice_a + dice_b * 10
    else
      # 出目そのまま
      output = dice_a * 10 + dice_b
    end

    debug("output", output)

    return output
  end

  def check_suc(*check_param)
    total_n, dice_n, signOfInequality, diff, dice_cnt, dice_max, n1, n_max = *check_param

    debug('check params : total_n, dice_n, signOfInequality, diff, dice_cnt, dice_max, n1, n_max',
          total_n, dice_n, signOfInequality, diff, dice_cnt, dice_max, n1, n_max)

    return "" unless /((\+|\-)?[\d]+)[)]?$/ =~ total_n.to_s

    total_n = Regexp.last_match(1).to_i
    diff = diff.to_i

    check_paramNew = [total_n, dice_n, signOfInequality, diff, dice_cnt, dice_max, n1, n_max]

    text = getSuccessText(*check_paramNew)
    text ||= ""

    if text.empty?
      if signOfInequality != ""
        debug('どれでもないけど判定するとき')
        return check_nDx(*check_param)
      end
    end

    return text
  end

  def getSuccessText(*check_param)
    debug('getSuccessText begin')

    _total_n, _dice_n, _signOfInequality, _diff, dice_cnt, dice_max, = *check_param

    debug("dice_max, dice_cnt", dice_max, dice_cnt)

    if (dice_max == 100) && (dice_cnt == 1)
      debug('1D100判定')
      return @diceBot.check_1D100(*check_param)
    end

    if (dice_max == 20) && (dice_cnt == 1)
      debug('1d20判定')
      return @diceBot.check_1D20(*check_param)
    end

    if dice_max == 10
      debug('d10ベース判定')
      return @diceBot.check_nD10(*check_param)
    end

    if dice_max == 6
      if dice_cnt == 2
        debug('2d6判定')
        result = @diceBot.check_2D6(*check_param)
        return result unless result.empty?
      end

      debug('xD6判定')
      return @diceBot.check_nD6(*check_param)
    end

    return ""
  end

  def check_nDx(total_n, _dice_n, signOfInequality, diff, _dice_cnt, _dice_max, _n1, _n_max) # ゲーム別成功度判定(ダイスごちゃ混ぜ系)
    operator_sym = normalize_operator(signOfInequality)

    target = to_i_if_integer(diff)
    if target && total_n.send(operator_sym, target)
      return " ＞ 成功"
    else
      return " ＞ 失敗"
    end
  end

  def to_i_if_integer(str)
    Integer(str)
  rescue ArgumentError
    nil
  end

  def getOperatorText(rate, output)
    if rate < 0
      '-'
    elsif output.empty?
      ''
    else
      "+"
    end
  end
end
