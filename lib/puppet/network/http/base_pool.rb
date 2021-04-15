# frozen_string_literal: true

# Base pool for HTTP connections.
#
# @api private
class Puppet::Network::HTTP::BasePool
  def start(site, verifier, http)
    Puppet.debug("Starting connection for #{site}")
    if verifier
      verifier.setup_connection(http)
      begin
        http.start
        print_ssl_info(http) if Puppet::Util::Log.sendlevel?(:debug)
      rescue OpenSSL::SSL::SSLError => error
        verifier.handle_connection_error(http, error)
      end
    else
      http.start
    end
  end

  private

  def print_ssl_info(http)
    buffered_io = http.instance_variable_get(:@socket)
    return unless buffered_io

    socket = buffered_io.io
    return unless socket

    Puppet.debug("Using #{socket.ssl_version} with cipher #{socket.cipher.first}")
  end
end
