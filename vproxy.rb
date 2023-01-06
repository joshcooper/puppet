#!/opt/puppetlabs/puppet/bin/ruby

require 'webrick'
require 'webrick/https'
require 'net/http'
require 'openssl'
require 'uri'
require 'json'

raise ArgumentError, "The VAULT_TOKEN environment variable must be set" unless ENV['VAULT_TOKEN']

ENV['VAULT_ADDR'] ||= 'http://127.0.0.1:8200'
fqdn = %x{facter fqdn}.chomp
cert = OpenSSL::X509::Certificate.new(File.read("/etc/puppetlabs/puppet/ssl/certs/#{fqdn}.pem"))
key = OpenSSL::PKey::RSA.new(File.read("/etc/puppetlabs/puppet/ssl/private_keys/#{fqdn}.pem"))

# map common names to serial numbers (as hex comma-delimited)
INVENTORY = {}

server = WEBrick::HTTPServer.new(
  :Port => 8150,
  :SSLEnable => true,
  :SSLCertificate => cert,
  :SSLPrivateKey => key,
)

class CAServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(req, res)
    uri = URI("#{ENV['VAULT_ADDR']}/v1/pki/cert/ca/raw/pem")
    vault = Net::HTTP.get_response(uri)
    res.status = vault.code
    res.body = vault.body
  end
end

class CertServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(req, res)
    certname = "CN=" + req.path.sub('/puppet-ca/v1/certificate/', '')

    # REMIND: this doesn't work if webrick is restarted between the time
    # the CSR was submitted and when the agent tries to retrieve the cert

    # REMIND: we're retrieving the last known serial number for the given
    # certname so collisions are possible
    serial = INVENTORY[certname]
    unless serial
      res.status = 404
      return
    end

    uri = URI("#{ENV['VAULT_ADDR']}/v1/pki/cert/#{serial}/raw/pem")
    vault = Net::HTTP.get_response(uri)
    res.status = vault.code
    res.body = vault.body
  end
end

class CRLServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(req, res)
    uri = URI("#{ENV['VAULT_ADDR']}/v1/pki/crl/pem")
    vault = Net::HTTP.get_response(uri)
    res.status = vault.code
    res.body = vault.body
  end
end

class CSRServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_PUT(req, res)
    certname = req.path.sub('/puppet-ca/v1/certificate_request/', '')

    # REMIND: vault will issue a new cert when one already exists (different serial number)
    uri = URI("#{ENV['VAULT_ADDR']}/v1/pki/sign/puppet")
    data = JSON.dump({
      "csr" => req.body,
      "alt_names" => certname
    })
    vault = Net::HTTP.post(uri, data, {'X-Vault-Token' => ENV['VAULT_TOKEN']})
    data = JSON.parse(vault.body)
    cert = data.dig('data', 'certificate')
    x509 = OpenSSL::X509::Certificate.new(cert)

    # convert OpenSSL::BN to hex encoded string delimited with colons, e.g. AB:CD
    serial = x509.serial
      .to_s(16)
      .scan(/../)
      .join(':')
      .upcase

    INVENTORY[x509.subject.to_utf8] = serial

    res.status = vault.code
    res.body = vault.body
  end
end

# Order matters
server.mount("/puppet-ca/v1/certificate/ca", CAServlet)
server.mount("/puppet-ca/v1/certificate/", CertServlet)
server.mount("/puppet-ca/v1/certificate_revocation_list/ca", CRLServlet)
server.mount("/puppet-ca/v1/certificate_request/", CSRServlet)

trap 'INT' do server.shutdown end

server.start
