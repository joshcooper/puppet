require 'spec_helper'
require 'puppet/face'
require 'puppet_spec/https'

describe "Puppet plugin face" do
  let(:command_line) { Puppet::Util::CommandLine.new('plugin', %w[download]) }
  let(:app) { Puppet::Application.find(:plugin).new(command_line) }

  it "processes a download request" do
    stub_request(:get, %r{/puppet/v3/file_metadatas/plugins}).and_return(status: 200, body: JSON.dump([]), headers: {'Content-Type' => 'application/json'})
    stub_request(:get, %r{/puppet/v3/file_metadatas/pluginfacts}).and_return(status: 200, body: JSON.dump([]), headers: {'Content-Type' => 'application/json'})
    stub_request(:get, %r{/puppet/v3/file_metadatas/locales}).and_return(status: 200, body: JSON.dump([]), headers: {'Content-Type' => 'application/json'})

#    expect {
    expect {
      ssl = Puppet::SSL::SSLProvider.new
      Puppet.override(:ssl_context => ssl.create_root_context(cacerts: [])) do
        app.run
      end
    }.to exit_with(0)
    #    }.to output(/No plugins downloaded/).to_stdout
  end
end
