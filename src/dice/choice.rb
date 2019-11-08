module Choice
  # @return [String]
  # @return [nil]
  def eval_choice(command)
    m = /^\s*(S)?choice\[(.*)\]/i.match(command)
    unless m
      return nil
    end

    @secret = !m[1].nil?
    items = m[2].split(',')

    index = @randomizer.rand(items.length) - 1
    chosen = items[index]
    return ": (#{command}) ＞ #{chosen}"
  end
end
