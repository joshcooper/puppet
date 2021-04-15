require 'spec_helper'
require 'webmock/rspec'
require 'puppet/http'

describe Puppet::HTTP::Service::Ca do
  let(:ssl_context) { Puppet::SSL::SSLContext.new }
  let(:client) { Puppet::HTTP::Client.new(ssl_context: ssl_context) }
  let(:subject) { client.create_session.route_to(:ca) }

  before :each do
    Puppet[:ca_server] = 'www.example.com'
    Puppet[:ca_port] = 443
  end

  context 'when routing to the CA service' do
    let(:cert) { cert_fixture('ca.pem') }
    let(:pem) { cert.to_pem }

    it 'defaults the server and port based on settings' do
      Puppet[:ca_server] = 'ca.example.com'
      Puppet[:ca_port] = 8141

      stub_request(:get, "https://ca.example.com:8141/puppet-ca/v1/certificate/ca").to_return(body: pem)

      subject.get_certificate('ca')
    end

    it 'fallbacks to server and masterport' do
      Puppet[:ca_server] = nil
      Puppet[:ca_port] = nil
      Puppet[:server] = 'ca2.example.com'
      Puppet[:masterport] = 8142

      stub_request(:get, "https://ca2.example.com:8142/puppet-ca/v1/certificate/ca").to_return(body: pem)

      subject.get_certificate('ca')
    end
  end

  context 'when getting certificates' do
    let(:cert) { cert_fixture('ca.pem') }
    let(:pem) { cert.to_pem }
    let(:url) { "https://www.example.com/puppet-ca/v1/certificate/ca" }

    it 'gets a certificate from the "certificate" endpoint' do
      stub_request(:get, url).to_return(body: pem)

      expect(subject.get_certificate('ca')).to eq(pem)
    end

    it 'accepts text/plain responses' do
      stub_request(:get, url).with(headers: {'Accept' => 'text/plain'})

      subject.get_certificate('ca')
    end

    it 'raises a response error if unsuccessful' do
      stub_request(:get, url).to_return(status: [404, 'Not Found'])

      expect {
        subject.get_certificate('ca')
      }.to raise_error do |err|
        expect(err).to be_an_instance_of(Puppet::HTTP::ResponseError)
        expect(err.message).to eq("Not Found")
        expect(err.response.code).to eq(404)
      end
    end
  end

  context 'when getting CRLs' do
    let(:crl) { crl_fixture('crl.pem') }
    let(:pem) { crl.to_pem }
    let(:url) { "https://www.example.com/puppet-ca/v1/certificate_revocation_list/ca" }

    it 'gets a CRL from "certificate_revocation_list" endpoint' do
      stub_request(:get, url).to_return(body: pem)

      expect(subject.get_certificate_revocation_list).to eq(pem)
    end

    it 'accepts text/plain responses' do
      stub_request(:get, url).with(headers: {'Accept' => 'text/plain'})

      subject.get_certificate_revocation_list
    end

    it 'raises a response error if unsuccessful' do
      stub_request(:get, url).to_return(status: [404, 'Not Found'])

      expect {
        subject.get_certificate_revocation_list
      }.to raise_error do |err|
        expect(err).to be_an_instance_of(Puppet::HTTP::ResponseError)
        expect(err.message).to eq("Not Found")
        expect(err.response.code).to eq(404)
      end
    end

    it 'raises a 304 response error if it is unmodified' do
      stub_request(:get, url).to_return(status: [304, 'Not Modified'])

      expect {
        subject.get_certificate_revocation_list(if_modified_since: Time.now)
      }.to raise_error do |err|
        expect(err).to be_an_instance_of(Puppet::HTTP::ResponseError)
        expect(err.message).to eq("Not Modified")
        expect(err.response.code).to eq(304)
      end
    end
  end

  context 'when submitting a CSR' do
    let(:request) { request_fixture('request.pem') }
    let(:pem) { request.to_pem }
    let(:url) { "https://www.example.com/puppet-ca/v1/certificate_request/infinity" }

    it 'submits a CSR to the "certificate_request" endpoint' do
      stub_request(:put, url).with(body: pem, headers: { 'Content-Type' => 'text/plain' })

      subject.put_certificate_request('infinity', request)
    end

    it 'raises response error if unsuccessful' do
      stub_request(:put, url).to_return(status: [400, 'Bad Request'])

      expect {
        subject.put_certificate_request('infinity', request)
      }.to raise_error do |err|
        expect(err).to be_an_instance_of(Puppet::HTTP::ResponseError)
        expect(err.message).to eq('Bad Request')
        expect(err.response.code).to eq(400)
      end
    end
  end

  context 'when encoding' do
    context 'node name' do
      let(:cert) { cert_fixture('ca.pem') }
      let(:pem) { cert.to_pem }

      def expects_encoded_url(name, url)
        stub_request(:get, url).to_return(status: 200, body: pem)

        subject.get_certificate(name)
      end

      it 'passes through alphanumeric' do
        name = "node0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

        expects_encoded_url(name, "https://www.example.com/certificate/#{name}")
      end

      it 'passes through unreserved punctuation' do
        name = "node-._~"

        expects_encoded_url(name, "https://www.example.com/certificate/#{name}")
      end

      it 'passes through sub-delimiters' do
        name = "node!$&'()*+,;="

        expects_encoded_url(name, "https://www.example.com/certificate/#{name}")
      end

      it 'passes through other pchars' do
        name = "node:@"

        expects_encoded_url(name, "https://www.example.com/certificate/#{name}")
      end

      it 'encodes general delimiters and spaces' do
        pending "doesn't encode general delimiters"

        name = "node :/?#[]@"
        encoded = %w[%20 %3A %2F %3F %23 %5B %5D %40].join

        expects_encoded_url(name, "https://www.example.com/certificate/node#{encoded}")
      end

      it 'encodes non-pchar characters' do
        name = 'node"%<>^`{|}'
        encoded = %w[%22 %25 %3C %3E %5E %60 %7B %7C %7D].join

        expects_encoded_url(name, "https://www.example.com/certificate/node#{encoded}")
      end

      it 'encodes control characters 0x00-0x1F' do
        pending "we should reject control characters"

        name = "node\x00\x01\x02\x03\x04\x05\x06\a\b\t\n\v\f\r\x0E\x0F\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\e\x1C\x1D\x1E\x1F"
        encoded = "node%00%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F"

        expects_encoded_url(name, "https://www.example.com/certificate/node#{encoded}")
      end
    end
  end
end
