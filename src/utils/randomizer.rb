class Randomizer
  def initialize
    @rand_results = []
    @rand_values = []
  end

  attr_reader :rand_results, :rand_values

  def roll(times, sides)
    roll_barabara(times, sides).sum()
  end

  def roll_barabara(times, sides)
    Array.new(times) { rand(sides) }
  end

  def rand(sides)
    ret = Kernel.rand(sides) + 1

    @rand_results.push([ret, sides])
    @rand_values.push(ret)
    return ret
  end
end

class StaticRands < Randomizer
  def initialize(rands)
    super()
    @rands = rands
  end

  def rand(sides)
    if @rands.nil? || @rands.empty?
      raise "nextRand is nil, so @rands is empty!! @rands:#{@rands.inspect}"
    end

    ret, expected_sides = @rands.shift
    if sides != expected_sides
      raise "invalid max value! [ #{ret} / #{sides} ] but NEED [ #{expected_sides} ] dice"
    end

    @rand_results.push([ret, sides])
    @rand_values.push(ret)

    return ret
  end
end
