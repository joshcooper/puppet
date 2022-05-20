class Puppet::Parameter::Data < Puppet::Parameter
  class << self
    attr_reader :datatype

    def datatype=(type_string)
      # REMIND: loader
      @datatype = Puppet::Pops::Types::TypeParser.singleton.parse(type_string)
    end
  end

  def validate(value)
    raise ArgumentError unless self.class.datatype.instance?(value)
  end
end
