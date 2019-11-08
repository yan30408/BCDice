module Normalize
  # @param [String] op
  # @return [Symbol]
  # @return [nil]
  def normalize_operator(op)
    case op
    when /<=|=</
      return :<=
    when />=|=>/
      return :>=
    when /<>/
      return :"!="
    when /</
      return :<
    when />/
      return :>
    when /\=/
      return :==
    end

    return nil
  end

  # @param [String|nil] op
  # @return [Symbol]
  # @return [nil]
  def marshalSignOfInequality(op)
    case op
    when /<=|=</
      return "<="
    when />=|=>/
      return ">="
    when /<>/
      return "<>"
    when /</
      return "<"
    when />/
      return ">"
    when /\=/
      return "="
    end

    return op
  end

  def operator_to_s(op)
    case op
    when :"!="
      "<>"
    when :==
      "="
    else
      op.to_s
    end
  end
end
