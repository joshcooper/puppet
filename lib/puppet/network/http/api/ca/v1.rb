# frozen_string_literal: true

require_relative '../../../../../puppet/x509'

module Puppet
  module Network
    module HTTP
      class API
        module CA
          class V1
            class BaseHandler
              def initialize
                @cert_provider = Puppet::X509::CertProvider.new
              end

              def response_ok(response, body)
                response.respond_with(200, "text/plain", body)
              end

              def response_bad_request(response)
                response.respond_with(400, "text/plain", "Bad Request")
              end

              def response_not_found(response)
                response.respond_with(404, "text/plain", "Not Found")
              end

              def response_server_error(response)
                response.respond_with(500, "text/plain", "Internal Server Error")
              end
            end

            class CertificateHandler < BaseHandler
              def call(request, response)
                name = request.path.delete_prefix("/puppet-ca/v1/certificate/")
                if name == 'ca'
                  cacerts = @cert_provider.load_cacerts(required: true)
                  body = cacerts.map(&:to_pem).join("\n")
                  response.respond_with(200, "text/plain", body)
                elsif name =~ Puppet::X509::CertProvider::VALID_CERTNAME
                  client_cert = @cert_provider.load_client_cert(name, required: false)
                  if client_cert
                    response_ok(response, client_cert.to_pem)
                  else
                    response_not_found(response)
                  end
                else
                  response_bad_request(response)
                end
              rescue => e
                $stderr.puts(e)
                response_server_error(response)
              end
            end

            class CSRHandler < BaseHandler
              def call(request, response)
                name = request.path.delete_prefix("/puppet-ca/v1/certificate_request/")
                if name == 'ca'
                  response_bad_request(response)
                elsif name =~ Puppet::X509::CertProvider::VALID_CERTNAME
                  csr = OpenSSL::X509::Request.new(request.body)
                  # REMIND: don't overwrite already saved csr
                  @cert_provider.save_request(name, csr)
                  response_ok(response, '')
                else
                  response_bad_request(response)
                end
              rescue => e
                $stderr.puts(e)
                response_server_error(response)
              end
            end

            class CRLHandler < BaseHandler
              def call(request, response)
                crls = @cert_provider.load_crls(required: true)
                body = crls.map(&:to_pem).join("\n")
                response_ok(response, body)
              rescue => e
                $stderr.puts(e)
                response_server_error(response)
              end
            end

            CERTIFICATE = Puppet::Network::HTTP::Route
                             .path(%r{^/certificate/})
                             .any(CertificateHandler.new)

            CSR = Puppet::Network::HTTP::Route
                             .path(%r{^/certificate_request/})
                             .any(CSRHandler.new)

            CRL = Puppet::Network::HTTP::Route
                  .path(%r{^/certificate_revocation_list/})
                  .any(CRLHandler.new)

            def self.routes
              Puppet::Network::HTTP::Route
                .path(/v1/)
                .any
                .chain(CERTIFICATE, CSR, CRL)
            end
          end
        end
      end
    end
  end
end
