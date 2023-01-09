require_relative '../../../../puppet/util/network_device'
require_relative '../../../../puppet/util/network_device/transport'

class Puppet::Util::NetworkDevice::Transport::Base
  attr_accessor :user
  attr_accessor :password
  attr_accessor :host
  attr_accessor :port
  attr_accessor :default_prompt
  attr_accessor :timeout

  def initialize
    @timeout = 10
  end

  def send(cmd)
  end

  def expect(prompt)
  end

  def command(cmd, options = {})
    send(cmd)
    expect(options[:prompt] || default_prompt) do |output|
      yield output if block_given?
    end
  end

end
