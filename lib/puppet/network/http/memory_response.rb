class Puppet::Network::HTTP::MemoryResponse
  attr_reader :code
  attr_reader :type
  attr_reader :body

  def initialize
    @body = ""
  end

  def respond_with(code, type, body)
    @code = code
    @type = type
    @body += body
  end
end
