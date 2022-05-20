Puppet::Type.type(:simple).provide(:simple) do
  [resource_type.validproperties, resource_type.parameters].flatten.each do |attr|
    attr = attr.intern
    next if attr == :name
    define_method(attr) do
      @property_hash[attr]
    end

    define_method(attr.to_s + "=") do |val|
      @property_hash[attr] = val
    end
  end

  def create
  end

  def exists?
  end

  def delete
  end

  def retrieve
    { ensure: nil, children: ['a'], force: false }
  end

  def flush
    puts "simple { '#{resource[:name]}':"
    puts "  ensure => #{Puppet::Parameter.format_value_for_display(resource[:ensure])}"

    attr = [self.class.resource_type.validproperties, self.class.resource_type.parameters].flatten
    attr.delete(:ensure)
    attr.delete(:name)
    attr.sort.each do |attr|
      value = resource[attr]
      if value
        puts "  #{attr} => #{Puppet::Parameter.format_value_for_display(value)},"
      end
    end
    puts "}"
  end
end
