Puppet::Type.newtype(:simple) do
  newparam(:name, namevar: true)
  ensurable
  newparam(:force, datatype: "Boolean")
  newproperty(:children, datatype: "Array[String[1]]")
  newproperty(:optional, datatype: "Optional[String[1]]")
  newproperty(:password, datatype: "Sensitive[String[1]]")

  def retrieve
    result = Puppet::Resource.new(self.class, title)

    current = provider.retrieve
    current.each_pair do |name, value|
      result[name] = value
    end

    result
  end
end
