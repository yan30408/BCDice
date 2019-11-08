#!/bin/ruby -Ku
# -*- coding: utf-8 -*-

require 'log'
require 'configBcDice.rb'
require 'utils/ArithmeticEvaluator.rb'

#============================== 起動法 ==============================
# 上記設定をしてダブルクリック、
# もしくはコマンドラインで
#
# ruby bcdice.rb
#
# とタイプして起動します。
#
# このとき起動オプションを指定することで、ソースを書き換えずに設定を変更出来ます。
#
# -s サーバ設定      「-s(サーバ):(ポート番号)」     (ex. -sirc.trpg.net:6667)
# -c チャンネル設定  「-c(チャンネル名)」            (ex. -c#CoCtest)
# -n Nick設定        「-n(Nick)」                    (ex. -nDicebot)
# -g ゲーム設定      「-g(ゲーム指定文字列)」        (ex. -gCthulhu)
# -m メッセージ設定  「-m(Notice_flgの番号)」        (ex. -m0)
# -e エクストラカード「-e(カードセットのファイル名)」(ex. -eTORG_SET.txt)
# -i IRC文字コード   「-i(文字コード名称)」          (ex. -iISO-2022-JP)
#
# ex. ruby bcdice.rb -sirc.trpg.net:6667 -c#CoCtest -gCthulhu
#
# プレイ環境ごとにバッチファイルを作っておくと便利です。
#
# 終了時はボットにTalkで「お疲れ様」と発言します。($quitCommandで変更出来ます。)
#====================================================================

require 'diceBot/DiceBot'
require 'diceBot/DiceBotLoader'
require 'diceBot/DiceBotLoaderList'
require 'dice/AddDice'
require 'dice/UpperDice'
require 'dice/RerollDice'
require 'dice/choice'
require 'utils/randomizer'

class BCDice
  VERSION = "2.03.04".freeze

  attr_reader :roll_result

  def initialize(game_type: "DiceBot", rands: nil, test_mode: false)
    @nick_e = ""
    @tnick = ""
    @isTest = test_mode

    @rand = rands ? StaticRands.new(rands) : Randomizer.new

    @channel = "" # dummy
    @roll_result = ""

    setGameByTitle(game_type)
  end

  def eval(command)
    setMessage(command)
    recievePublicMessage("")

    return @roll_result
  end

  def getGameType
    @diceBot.gameType
  end

  def setDiceBot(diceBot)
    return if  diceBot.nil?

    @diceBot = diceBot
    @diceBot.bcdice = self
    diceBot.randomizer = @rand
  end

  attr_reader :nick_e

  def setMessage(message)
    # 空白が含まれる場合、最初の部分だけを取り出す
    messageToSet = message.split(/\s/, 2).first

    debug("setMessage messageToSet", messageToSet)

    @messageOriginal = parren_killer(messageToSet)
    @message = @messageOriginal.upcase
    debug("@message", @message)
  end

  def getOriginalMessage
    @messageOriginal
  end

  # 直接TALKでは大文字小文字を考慮したいのでここでオリジナルの文字列に変更
  def changeMessageOriginal
    @message = @messageOriginal
  end

  def printErrorMessage(e)
    append_message("error " + e.to_s + e.backtrace.join("\n"))
  end

  def recievePublicMessage(nick_e)
    recievePublicMessageCatched(nick_e)
  rescue StandardError => e
    printErrorMessage(e)
  end

  def recievePublicMessageCatched(_nick_e)
    # ダイスロールの処理
    executeDiceRoll

    # 四則計算代行
    if /(^|\s)C([-\d]+)\s*$/i =~ @message
      output = Regexp.last_match(2)
      if output != ""
        append_message(": 計算結果 ＞ #{output}")
      end
    end

    # ここから大文字・小文字を考慮するようにメッセージを変更
    changeMessageOriginal

    debug("\non_public end")
  end

  def executeDiceRoll
    debug("executeDiceRoll begin")
    debug("channel", @channel)

    output, secret = dice_command

    unless  secret
      debug("executeDiceRoll @channel", @channel)
      append_message(output) if output != "1"
      return
    end

    # 隠しロール
    return if output == "1"

    if @isTest
      output += "###secret dice###"
    end

    broadmsg(output)
  end

  ###########################################################################
  # **                         各種コマンド処理
  ###########################################################################

  #=========================================================================
  # **                           コマンド分岐
  #=========================================================================
  def dice_command # ダイスコマンドの分岐処理
    arg = @message.upcase

    debug('dice_command arg', arg)

    output, secret = @diceBot.dice_command(@message, "")
    return output, secret if output != '1'

    output, secret = rollD66(arg)
    return output, secret unless output.nil?

    output, secret = checkAddRoll(arg)
    return output, secret unless output.nil?

    output, secret = checkBDice(arg)
    return output, secret unless output.nil?

    output, secret = checkRnDice(arg)
    return output, secret unless output.nil?

    output, secret = checkUpperRoll(arg)
    return output, secret unless output.nil?

    output, secret = Choice.roll(arg, @rand)
    return output, secret unless output.nil?

    output = '1'
    secret = false
    return output, secret
  end

  def checkAddRoll(arg)
    debug("check add roll")

    dice = AddDice.new(self, @diceBot)
    output = dice.rollDice(arg)
    return nil if output == '1'

    secret = (/S[-\d]+D[\d+-]+/ === arg)

    return output, secret
  end

  def checkBDice(arg)
    debug("check barabara roll")

    output = bdice(arg)
    return nil if output == '1'

    secret = (/S[\d]+B[\d]+/i === arg)

    return output, secret
  end

  def checkRnDice(arg)
    debug('check xRn roll arg', arg)

    return nil unless /(S)?[\d]+R[\d]+/i === arg

    secret = !Regexp.last_match(1).nil?

    output = @diceBot.dice_command_xRn(arg, "")
    return nil if  output.nil? || (output == '1')

    if output.empty?
      dice = RerollDice.new(self, @diceBot)
      output = dice.rollDice(arg)
    end

    return nil if output.nil? || (output == '1')

    debug('xRn output', output)

    return output, secret
  end

  def checkUpperRoll(arg)
    debug("check upper roll")

    return nil unless /(S)?[\d]+U[\d]+/i === arg

    secret = !Regexp.last_match(1).nil?

    dice = UpperDice.new(self, @diceBot)
    output = dice.rollDice(arg)
    return nil if output == '1'

    return output, secret
  end

  def getTableIndexDiceValueAndDiceText(dice)
    if /(\d+)D(\d+)/i === dice
      diceCount = Regexp.last_match(1)
      diceType = Regexp.last_match(2)
      value, diceText = roll(diceCount, diceType)
      return value, diceText
    end

    string, _secret, _count, swapMarker = getD66Infos(dice)
    unless  string.nil?
      value = getD66ValueByMarker(swapMarker)
      diceText = (value / 10).to_s + "," + (value % 10).to_s
      return value, diceText
    end

    return nil
  end

  def rollTableMessageDiceText(text)
    message = text.gsub(/(\d+)D(\d+)/) do
      m = $~
      diceCount = m[1]
      diceMax = m[2]
      value, = roll(diceCount, diceMax)
      "#{diceCount}D#{diceMax}(=>#{value})"
    end

    return message
  end

  #=========================================================================
  # **                           ランダマイザ
  #=========================================================================
  # ダイスロール
  def roll(dice_cnt, dice_max, dice_sort = 0, dice_add = 0, dice_ul = '', dice_diff = 0, dice_re = nil)
    dice_cnt = dice_cnt.to_i
    dice_max = dice_max.to_i
    dice_re = dice_re.to_i

    total = 0
    dice_str = ""
    numberSpot1 = 0
    cnt_max = 0
    n_max = 0
    cnt_suc = 0
    d9_on = false
    rerollCount = 0
    dice_result = []

    # dice_add = 0 if( ! dice_add )

    if (@diceBot.d66Type != 0) && (dice_max == 66)
      dice_sort = 0
      dice_cnt = 2
      dice_max = 6
    end

    if @diceBot.isD9 && (dice_max == 9)
      d9_on = true
      dice_max += 1
    end

    unless (dice_cnt <= $DICE_MAXCNT) && (dice_max <= $DICE_MAXNUM)
      return total, dice_str, numberSpot1, cnt_max, n_max, cnt_suc, rerollCount
    end

    dice_cnt.times do |i|
      i += 1
      dice_now = 0
      dice_n = 0
      dice_st_n = ""
      round = 0

      loop do
        dice_n = @rand.rand(dice_max)
        dice_n -= 1 if d9_on

        dice_now += dice_n

        debug('@diceBot.sendMode', @diceBot.sendMode)
        if @diceBot.sendMode >= 2
          dice_st_n += "," unless dice_st_n.empty?
          dice_st_n += dice_n.to_s
        end
        round += 1

        break unless (dice_add > 1) && (dice_n >= dice_add)
      end

      total += dice_now

      if dice_ul != ''
        suc = check_hit(dice_now, dice_ul, dice_diff)
        cnt_suc += suc
      end

      if dice_re
        rerollCount += 1 if dice_now >= dice_re
      end

      if (@diceBot.sendMode >= 2) && (round >= 2)
        dice_result.push("#{dice_now}[#{dice_st_n}]")
      else
        dice_result.push(dice_now)
      end

      numberSpot1 += 1 if dice_now == 1
      cnt_max += 1 if  dice_now == dice_max
      n_max = dice_now if dice_now > n_max
    end

    if dice_sort != 0
      dice_str = dice_result.sort_by { |a| dice_num(a) }.join(",")
    else
      dice_str = dice_result.join(",")
    end

    return total, dice_str, numberSpot1, cnt_max, n_max, cnt_suc, rerollCount
  end

  def getRandResults
    @rand.rand_results
  end

  def dice_num(dice_str)
    dice_str = dice_str.to_s
    return dice_str.sub(/\[[\d,]+\]/, '').to_i
  end

  #==========================================================================
  # **                            ダイスコマンド処理
  #==========================================================================

  ####################         バラバラダイス       ########################
  def bdice(string) # 個数判定型ダイスロール
    suc = 0
    signOfInequality = ""
    diff = 0
    output = ""

    string = string.gsub(/-[\d]+B[\d]+/, '') # バラバラダイスを引き算しようとしているのを除去

    unless /(^|\s)S?(([\d]+B[\d]+(\+[\d]+B[\d]+)*)(([<>=]+)([\d]+))?)($|\s)/ =~ string
      output = '1'
      return output
    end

    string = Regexp.last_match(2)
    if Regexp.last_match(5)
      diff = Regexp.last_match(7).to_i
      string = Regexp.last_match(3)
      signOfInequality = marshalSignOfInequality(Regexp.last_match(6))
    elsif  /([<>=]+)(\d+)/ =~ @diceBot.defaultSuccessTarget
      diff = Regexp.last_match(2).to_i
      signOfInequality = marshalSignOfInequality(Regexp.last_match(1))
    end

    dice_a = string.split(/\+/)
    dice_cnt_total = 0
    numberSpot1 = 0

    dice_a.each do |dice_o|
      dice_cnt, dice_max, = dice_o.split(/[bB]/)
      dice_cnt = dice_cnt.to_i
      dice_max = dice_max.to_i

      dice_dat = roll(dice_cnt, dice_max, (@diceBot.sortType & 2), 0, signOfInequality, diff)
      suc += dice_dat[5]
      output += "," if output != ""
      output += dice_dat[1]
      numberSpot1 += dice_dat[2]
      dice_cnt_total += dice_cnt
    end

    if signOfInequality != ""
      string += "#{signOfInequality}#{diff}"
      output = "#{output} ＞ 成功数#{suc}"
      output += @diceBot.getGrichText(numberSpot1, dice_cnt_total, suc)
    end
    output = ": (#{string}) ＞ #{output}"

    return output
  end

  ####################             D66ダイス        ########################
  def rollD66(string)
    return nil unless /^S?D66/i === string
    return nil if @diceBot.d66Type == 0

    debug("match D66 roll")
    output, secret = d66dice(string)

    return output, secret
  end

  def d66dice(string)
    string = string.upcase
    secret = false
    output = '1'

    string, secret, count, swapMarker = getD66Infos(string)
    return output, secret if string.nil?

    debug('d66dice count', count)

    d66List = []
    count.times do |_i|
      d66List << getD66ValueByMarker(swapMarker)
    end
    d66Text = d66List.join(',')
    debug('d66Text', d66Text)

    output = ": (#{string}) ＞ #{d66Text}"

    return output, secret
  end

  def getD66Infos(string)
    debug("getD66Infos, string", string)

    return nil unless /(^|\s)(S)?((\d+)?D66(N|S)?)(\s|$)/i === string

    secret = !Regexp.last_match(2).nil?
    string = Regexp.last_match(3)
    count = (Regexp.last_match(4) || 1).to_i
    swapMarker = (Regexp.last_match(5) || "").upcase

    return string, secret, count, swapMarker
  end

  def getD66ValueByMarker(swapMarker)
    case swapMarker
    when "S"
      isSwap = true
      getD66(isSwap)
    when "N"
      isSwap = false
      getD66(isSwap)
    else
      getD66Value()
    end
  end

  def getD66Value(mode = nil)
    mode ||= @diceBot.d66Type

    isSwap = (mode > 1)
    getD66(isSwap)
  end

  def getD66(isSwap)
    output = 0

    dice_a = @rand.rand(6)
    dice_b = @rand.rand(6)
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

  #==========================================================================
  # **                            結果判定関連
  #==========================================================================
  def getMarshaledSignOfInequality(text)
    return "" if text.nil?

    return marshalSignOfInequality(text)
  end

  def marshalSignOfInequality(signOfInequality) # 不等号の整列
    case signOfInequality
    when /(<=|=<)/
      return "<="
    when /(>=|=>)/
      return ">="
    when /(<>)/
      return "<>"
    when /[<]+/
      return "<"
    when /[>]+/
      return ">"
    when /[=]+/
      return "="
    end

    return signOfInequality
  end

  def check_hit(dice_now, signOfInequality, diff) # 成功数判定用
    suc = 0

    if  diff.is_a?(String)
      unless /\d/ =~ diff
        return suc
      end

      diff = diff.to_i
    end

    case signOfInequality
    when /(<=|=<)/
      if dice_now <= diff
        suc += 1
      end
    when /(>=|=>)/
      if dice_now >= diff
        suc += 1
      end
    when /(<>)/
      if dice_now != diff
        suc += 1
      end
    when /[<]+/
      if dice_now < diff
        suc += 1
      end
    when /[>]+/
      if dice_now > diff
        suc += 1
      end
    when /[=]+/
      if dice_now == diff
        suc += 1
      end
    end

    return suc
  end

  ####################       ゲーム別成功度判定      ########################
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
    debug('check_nDx begin diff', diff)
    success = check_hit(total_n, signOfInequality, diff)
    debug('check_nDx success', success)

    if success >= 1
      return " ＞ 成功"
    end

    return " ＞ 失敗"
  end

  ###########################################################################
  # **                              出力関連
  ###########################################################################

  def broadmsg(output)
    debug("broadmsg output, nick", output)

    if output == "1"
      return
    end

    append_message(output)
  end

  def append_message(message)
    @roll_result += message
  end

  ####################         テキスト前処理        ########################
  def parren_killer(string)
    debug("parren_killer input", string)

    while /^(.*?)\[(\d+[Dd]\d+)\](.*)/ =~ string
      str_before = ""
      str_after = ""
      dice_cmd = Regexp.last_match(2)
      str_before = Regexp.last_match(1) if Regexp.last_match(1)
      str_after = Regexp.last_match(3) if Regexp.last_match(3)
      rolled, = rollDiceAddingUp(dice_cmd)
      string = "#{str_before}#{rolled}#{str_after}"
    end

    string = changeRangeTextToNumberText(string)

    round_type = @diceBot.fractionType.to_sym
    string = string.gsub(%r{\([\d/\+\*\-\(\)]+\)}) do |expr|
      ArithmeticEvaluator.new.eval(expr, round_type)
    end

    debug("diceBot.changeText(string) begin", string)
    string = @diceBot.changeText(string)
    debug("diceBot.changeText(string) end", string)

    string = string.gsub(/([\d]+[dD])([^\w]|$)/) { "#{Regexp.last_match(1)}6#{Regexp.last_match(2)}" }

    debug("parren_killer output", string)

    return string
  end

  def rollDiceAddingUp(*arg)
    dice = AddDice.new(self, @diceBot)
    dice.rollDiceAddingUp(*arg)
  end

  # [1...4]D[2...7] -> 2D7 のように[n...m]をランダムな数値へ変換
  def changeRangeTextToNumberText(string)
    debug('[st...ed] before string', string)

    while /^(.*?)\[(\d+)[.]{3}(\d+)\](.*)/ =~ string
      beforeText = Regexp.last_match(1)
      beforeText ||= ""

      rangeBegin = Regexp.last_match(2).to_i
      rangeEnd = Regexp.last_match(3).to_i

      afterText = Regexp.last_match(4)
      afterText ||= ""

      next unless rangeBegin < rangeEnd

      range = (rangeEnd - rangeBegin + 1)
      debug('range', range)

      rolledNumber, = roll(1, range)
      resultNumber = rangeBegin - 1 + rolledNumber
      string = "#{beforeText}#{resultNumber}#{afterText}"
    end

    debug('[st...ed] after string', string)

    return string
  end

  # 指定したタイトルのゲームを設定する
  # @param [String] gameTitle ゲームタイトル
  # @return [String] ゲームを設定したことを示すメッセージ
  def setGameByTitle(gameTitle)
    debug('setGameByTitle gameTitle', gameTitle)

    loader = DiceBotLoaderList.find(gameTitle)
    diceBot =
      if loader
        loader.loadDiceBot
      else
        DiceBotLoader.loadUnknownGame(gameTitle) || DiceBot.new
      end

    setDiceBot(diceBot)
    diceBot.postSet

    message = "Game設定を#{diceBot.gameName}に設定しました"
    debug('setGameByTitle message', message)

    return message
  end
end
