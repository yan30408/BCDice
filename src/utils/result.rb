class Result
  def self.zero
    Result.new(0)
  end

  def initialize(value = 0, expr = nil)
    @value = value
    @expr = expr || value.to_s
  end

  attr_reader :value, :expr

  def +(other)
    Result.new(@value + other.value, "#{@expr}+#{other.expr}")
  end

  def -(other)
    Result.new(@value - other.value, "#{@expr}-#{other.expr}")
  end

  def *(other)
    Result.new(@value * other.value, "#{@expr}*#{other.expr}")
  end

  def /(other)
    Result.new(@value / other.value, "#{@expr}/#{other.expr}")
  end

  def div_ceil(other, suffix)
    Result.new((@value.to_f/other.value).ceil, "#{expr}/#{other.expr}#{suffix}")
  end

  def div_round(other, suffix)
    Result.new((@value.to_f/other.value).round, "#{expr}/#{other.expr}#{suffix}")
  end

  def -@
    Result.new(-@value, "-#{@expr}")
  end

  def zero?
    @value.zero?
  end
end
