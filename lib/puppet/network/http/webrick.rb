# frozen_string_literal: true

require 'webrick'
require 'webrick/https'

require 'puppet/network/http/webrick/rest'
require 'puppet/ssl/ssl_provider'

class Puppet::Network::HTTP::WEBrick
  def listen(address, port)
    ssl_provider = Puppet::SSL::SSLProvider.new
    ssl_context = ssl_provider.load_context(certname: Puppet[:certname])

    log_path = File.join(Puppet[:logdir], 'puppet-server.log')
    log = WEBrick::Log.new(log_path)
    access_log = [
      [log, WEBrick::AccessLog::COMBINED_LOG_FORMAT]
    ]

    arguments = {
      # HTTP
      BindAddress: address || '*',
      Port: port,
      DoNotReverseLookup: true,

      # SSL
      SSLEnable: true,
      SSLCiphers: Puppet[:ciphers],
      SSLCertificateStore: ssl_context.store,
      SSLCertificate: ssl_context.client_cert,
      SSLPrivateKey: ssl_context.private_key,
      SSLVerifyClient: OpenSSL::SSL::VERIFY_PEER,

      # Logging
      Logger: log,
      AccessLog: access_log,
    }

    # Disable authorization
    Puppet::Network::Authorization.authconfigloader_class = self

    server = WEBrick::HTTPServer.new(arguments)
    server.mount('/', Puppet::Network::HTTP::WEBrickREST)

    trap 'HUP' do
      log_file.reopen(log_path, 'a+')
    end

    trap 'INT' do
      server.shutdown
    end

    # This blocks the current thread
    server.start
  end
end
