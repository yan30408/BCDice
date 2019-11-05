# -*- coding: utf-8 -*-

bcDiceRoot = File.expand_path(File.dirname(__FILE__))
unless $:.include?(bcDiceRoot)
  $:.unshift(bcDiceRoot)
end

require 'bcdiceCore.rb'

class CgiDiceBot
  def initialize
    @rollResult = ""
    @isSecret = false
    @rands = nil # テスト以外ではnilで良い。ダイス目操作パラメータ
    @isTest = false
    @bcdice = nil

    $SEND_STR_MAX = 99999 # 最大送信文字数(本来は500byte上限)
  end

  attr_reader :isSecret

  def rollFromCgi()
    cgi = CGI.new
    @cgiParams = @cgi.params

    rollFromCgiParams(cgiParams)
  end

  def rollFromCgiParamsDummy()
    @cgiParams = {
      'message' => 'STG20',
      # 'message' => 'S2d6',
      'gameType' => 'TORG',
      'channel' => '1',
      'state' => 'state',
      'sendto' => 'sendto',
      'color' => '999999',
    }

    rollFromCgiParams
  end

  def rollFromCgiParams
    message = @cgiParams['message']
    gameType = @cgiParams['gameType']
    gameType ||= 'diceBot'
    # $rand_seed = @cgiParams['randomSeed']

    result = ""

    result += "##>customBot BEGIN<##"
    result += getDiceBotParamText('channel')
    result += getDiceBotParamText('name')
    result += getDiceBotParamText('state')
    result += getDiceBotParamText('sendto')
    result += getDiceBotParamText('color')
    result += message
    rollResult, randResults = roll(message, gameType)
    result += rollResult
    result += "##>customBot END<##"

    return result
  end

  def getDiceBotParamText(paramName)
    param = @cgiParams[paramName]
    param ||= ''

    "#{param}\t"
  end

  def roll(message, gameType)
    rollResult, randResults, gameType = executeDiceBot(message, gameType)

    result = ""

    # 多言語対応のダイスボットは「GameType:Language」という書式なので、
    # ここで言語名を削って表示する。（内部的には必要だが、表示では不要のため）
    gameType = gameType.gsub(/:.+$/, '')

    unless rollResult.empty?
      result += "\n#{gameType} #{rollResult}"
    end

    return result, randResults
  end

  def setTest()
    @isTest = true
  end

  def setRandomValues(rands)
    @rands = rands
  end

  def executeDiceBot(message, gameType)
    bcdice = BCDice.new(:game_type => gameType, :rands => @rands, :test_mode => true)
    gameType = bcdice.getGameType

    result_text = bcdice.eval(message)
    randResults = bcdice.getRandResults

    return result_text, randResults, gameType
  end

  # Unused method
  def getGameCommandInfos(_dir, _prefix)
    return []
  end
end

if $0 === __FILE__
  bot = CgiDiceBot.new

  result = ''
  if !ARGV.empty?
    result, randResults = bot.roll(ARGV[0], ARGV[1])
  else
    result = bot.rollFromCgiParamsDummy
  end

  print(result + "\n")
end
