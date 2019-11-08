# -*- coding: utf-8 -*-

require 'utils/ArithmeticEvaluator'
require 'utils/nomalize'

class UpperDice
  include Nomalize

  def initialize(diceBot, randomizer)
    @diceBot = diceBot
    @randomizer = randomizer
  end

  # 上方無限型ダイスロール
  def rollDice(string)
    debug('udice begin string', string)

    output = '1'

    string = string.gsub(/-[sS]?[\d]+[uU][\d]+/, '') # 上方無限の引き算しようとしてる部分をカット

    unless (m = /(^|\s)[sS]?(\d+[uU][\d\+\-uU]+)(\[(\d+)\])?([\+\-\d]*)(([<>=]+)(\d+))?(\@(\d+))?($|\s)/.match(string))
      return output
    end

    command = m[2]
    signOfInequalityText = m[7]
    diff = m[8].to_i
    upperTarget1 = m[4]
    upperTarget2 = m[10]

    modifier = m[5] || ''
    debug('modifier', modifier)

    debug('p $...', [m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10]])

    string = command

    @signOfInequality = nomalize_operator(signOfInequalityText)
    @upper = getAddRollUpperTarget(upperTarget1, upperTarget2)

    if @upper <= 1
      output = ": (#{string}\[#{@upper}\]#{modifier}) ＞ 無限ロールの条件がまちがっています"
      return output
    end

    diceCommands = string.split('+')

    bonusValue = getBonusValue(modifier)
    debug('bonusValue', bonusValue)

    diceDiff = diff - bonusValue

    totalDiceString, totalSuccessCount, totalDiceCount, maxDiceValue, totalValue = getUpperDiceCommandResult(diceCommands, diceDiff)

    output = "#{totalDiceString}#{formatBonus(bonusValue)}"

    maxValue = maxDiceValue + bonusValue
    totalValue += bonusValue

    string += "[#{@upper}]" + modifier

    if @diceBot.isPrintMaxDice && (totalDiceCount > 1)
      output = "#{output} ＞ #{totalValue}"
    end

    if @signOfInequality
      output = "#{output} ＞ 成功数#{totalSuccessCount}"
      string += "#{operator_to_s(@signOfInequality)}#{diff}"
    else
      output += getMaxAndTotalValueResultStirng(maxValue, totalValue, totalDiceCount)
    end

    output = ": (#{string}) ＞ #{output}"

    if output.length > $SEND_STR_MAX
      output = ": (#{string}) ＞ ... ＞ #{totalValue}"
      if @signOfInequality
        output += getMaxAndTotalValueResultStirng(maxValue, totalValue, totalDiceCount)
      end
    end

    return output
  end

  def getMaxAndTotalValueResultStirng(maxValue, totalValue, _totalDiceCount)
    return " ＞ #{maxValue}/#{totalValue}(最大/合計)"
  end

  def getAddRollUpperTarget(target1, target2)
    if  target1
      return target1.to_i
    end

    if  target2
      return target2.to_i
    end

    if @diceBot.upplerRollThreshold == "Max"
      return 2
    else
      return @diceBot.upplerRollThreshold
    end
  end

  # 入力の修正値の部分からボーナスの数値に変換する
  # @param [String] modifier 入力の修正値部分
  # @return [Integer] ボーナスの数値
  def getBonusValue(modifier)
    if modifier.empty?
      0
    else
      ArithmeticEvaluator.new.eval(modifier, @diceBot.fractionType.to_sym)
    end
  end

  def getUpperDiceCommandResult(diceCommands, diceDiff)
    success_count = 0
    diceStringList = []
    max_dice_value = 0

    diceCommands.each do |diceCommand|
      diceCount, diceMax = diceCommand.split(/[uU]/).collect { |s| s.to_i }
      diceCount = diceCount.to_i
      diceMax = diceMax.to_i

      if @diceBot.upplerRollThreshold == "Max"
        @upper = diceMax
      end

      ret = []
      diceCount.times do
        arr = roll_u_single(diceMax, @upper)
        val = arr.sum()
        if @signOfInequality && val.send(@signOfInequality, diceDiff)
          success_count += 1
        end
        if val > max_dice_value
          max_dice_value = val
        end

        text = arr.length == 1 ? val.to_s : "#{val}[#{arr.join(',')}]"
        ret.push([val, text])
      end

      if @diceBot.sortType & 2 != 0
        ret = ret.sort()
      end
      text = ret.map { |x| x[1] }.join(",")
      diceStringList.push(text)
    end

    totalDiceString = diceStringList.join(",")

    total_dice_count = @randomizer.rand_values.length
    total_value = @randomizer.rand_values.sum()

    return totalDiceString, success_count, total_dice_count, max_dice_value, total_value
  end

  # 出力用にボーナス値を整形する
  # @param [Integer] bonusValue ボーナス値
  # @return [String]
  def formatBonus(bonusValue)
    if bonusValue == 0
      ''
    elsif bonusValue > 0
      "+#{bonusValue}"
    else
      bonusValue.to_s
    end
  end

  # @result [Array<Integer>]
  def roll_u_single(sides, threshold)
    ret = []
    loop do
      val = @randomizer.rand(sides)
      ret.push(val)
      unless val >= threshold
        break
      end
    end
    return ret
  end
end
