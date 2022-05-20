class Puppet::Property::Data < Puppet::Property
  class << self
    attr_reader :datatype

    def datatype=(type_string)
      # REMIND: loader
      @datatype = Puppet::Pops::Types::TypeParser.singleton.parse(type_string)
    end
  end

  def should=(values)
    @shouldorig = values
    validate(values)
    @should = munge(values)
  end

  def should
    unmunge(@should)
  end

  def validate(values)
    raise ArgumentError unless self.class.datatype.instance?(values)
  end
end
