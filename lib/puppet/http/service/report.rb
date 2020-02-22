class Puppet::HTTP::Service::Report < Puppet::HTTP::Service
  API = '/puppet/v3'.freeze

  def initialize(client, session, server, port)
    url = build_url(API, server || Puppet[:report_server], port || Puppet[:report_port])
    super(client, session, url)
  end

  def put_report(name, report, environment:, ssl_context: nil)
    formatter = Puppet::Network::FormatHandler.format_for(Puppet[:preferred_serialization_format])
    headers = add_puppet_headers('Accept' => get_mime_types(Puppet::Transaction::Report).join(', '))

    body, content_encoding = compress(serialize(formatter, report))
    headers['Content-Encoding'] = content_encoding if content_encoding

    response = @client.put(
      with_base_url("/report/#{name}"),
      headers: headers,
      params: { environment: environment },
      content_type: formatter.mime,
      body: body,
      ssl_context: ssl_context
    )

    process_response(response)

    if response.success?
      response
    elsif !@session.supports?(:report, 'json') && Puppet[:preferred_serialization_format] != 'pson'
      #TRANSLATORS "pson", "preferred_serialization_format", and "puppetserver" should not be translated
      raise Puppet::HTTP::ProtocolError.new(_("To submit reports to a server running puppetserver %{server_version}, set preferred_serialization_format to pson") % { server_version: response[Puppet::HTTP::HEADER_PUPPET_VERSION]})
    else
      raise Puppet::HTTP::ResponseError.new(response)
    end
  end

  protected

  def compress(body)
    require 'byebug'; byebug
    if @session.supports?(:report, 'gzip')
      io = StringIO.new
      io.binmode

      gz = Zlib::GzipWriter.new(io, encoding: Encoding::BINARY)
      begin
        gz.write(body)
      ensure
        gz.close
      end

      [io.string, 'gzip']
    else
      [body, nil]
    end
  end

  def process_response(response)
    @session.process_response(response)
  end
end
