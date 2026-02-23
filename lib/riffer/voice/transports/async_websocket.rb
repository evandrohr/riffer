# frozen_string_literal: true
# rbs_inline: enabled

# Async websocket transport for realtime voice drivers.
class Riffer::Voice::Transports::AsyncWebsocket
  extend Riffer::Helpers::Dependencies

  HTTP1_ALPN = ["http/1.1"].freeze #: Array[String]

  # Managed websocket connection handles.
  attr_reader :client #: untyped

  # Managed websocket stream.
  attr_reader :connection #: untyped

  #: (client: untyped, connection: untyped) -> void
  def initialize(client:, connection:)
    @client = client
    @connection = connection
  end

  #: (url: String, ?headers: Hash[String, String]) -> Riffer::Voice::Transports::AsyncWebsocket
  def self.connect(url:, headers: {})
    load_dependencies!

    endpoint = Async::HTTP::Endpoint.parse(
      url,
      protocol: Async::HTTP::Protocol::HTTP11,
      alpn_protocols: HTTP1_ALPN
    )

    client = Async::WebSocket::Client.open(endpoint)
    connection = if headers.empty?
      client.connect(endpoint.authority, endpoint.path)
    else
      connect_with_headers(client: client, endpoint: endpoint, headers: headers)
    end

    new(client: client, connection: connection)
  rescue Riffer::Helpers::Dependencies::LoadError
    raise
  rescue => error
    raise Riffer::Error, "Failed to establish websocket connection: #{error.message}"
  end

  #: (client: untyped, endpoint: untyped, headers: Hash[String, String]) -> untyped
  def self.connect_with_headers(client:, endpoint:, headers:)
    client.connect(endpoint.authority, endpoint.path, headers: headers)
  rescue ArgumentError => error
    # async-websocket < 0.30 expects headers as a positional third arg.
    raise unless error.message.include?("unknown keyword") || error.message.include?("wrong number of arguments")

    client.connect(endpoint.authority, endpoint.path, headers)
  end

  private_class_method :connect_with_headers

  #: () -> void
  def self.load_dependencies!
    depends_on "async"
    depends_on "async-http", req: "async/http/endpoint"
    require "async/http/protocol/https"
    depends_on "async-websocket", req: "async/websocket/client"
  rescue Riffer::Helpers::Dependencies::LoadError, LoadError
    raise Riffer::Helpers::Dependencies::LoadError,
      "Could not load async websocket dependencies. Add 'async', 'async-http', and 'async-websocket' to your Gemfile."
  end
  private_class_method :load_dependencies!

  #: () -> untyped
  def read
    @connection.read
  end

  #: (Hash[String, untyped]) -> void
  def write_json(payload)
    @connection.write(payload.to_json)
  end

  #: () -> void
  def close
    @connection.close
  ensure
    @client.close
  end
end
