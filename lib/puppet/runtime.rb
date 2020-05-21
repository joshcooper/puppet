require 'singleton'

# Provides access to runtime implementations.
#
# @api private
class Puppet::Runtime
  include Singleton

  def initialize
    @runtime_services = {
      http: proc do
        require 'puppet/http'
        klass = Puppet::Network::HttpPool.http_client_class
        if klass == Puppet::Network::HTTP::Connection ||
           klass == Puppet::Network::HTTP::ConnectionAdapter
          Puppet::HTTP::Client.new
        else
          Puppet::HTTP::ExternalClient.new(klass)
        end
      end,
      ssl: proc do
        require 'puppet/ssl'
        Puppet::SSL::SSLProvider.new
      end,
      certificates: proc do
        require 'puppet/x509'
        Puppet::X509::CertProvider.new
      end
    }
  end
  private :initialize

  # Get a runtime implementation.
  #
  # @param name [Symbol] the name of the implementation
  # @return [Object] the runtime implementation
  # @api private
  def [](name)
    service = @runtime_services[name]
    raise ArgumentError, "Unknown service #{name}" unless service

    if service.is_a?(Proc)
      @runtime_services[name] = service.call
    else
      service
    end
  end

  # Register a runtime implementation.
  #
  # @param name [Symbol] the name of the implementation
  # @param impl [Object] the runtime implementation
  # @api private
  def []=(name, impl)
    @runtime_services[name] = impl
  end

  # Clears all implementations. This is used for testing.
  #
  # @api private
  def clear
    initialize
  end
end
