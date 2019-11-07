module Choice
  def self.roll(command, rand)
    m = /^\s*(S)?choice\[(.*)\]/i.match(command)
    unless m
      return nil
    end

    secret = !m[1].nil?
    items = m[2].split(',')

    index = rand.rand(items.length) - 1
    chosen = items[index]
    return ": (#{command}) ＞ #{chosen}", secret
  end
end
