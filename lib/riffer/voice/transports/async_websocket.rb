# frozen_string_literal: true
# rbs_inline: enabled

# Async websocket transport for realtime voice drivers.
class Riffer::Voice::Transports::AsyncWebsocket
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
    begin
      require "async/http/endpoint"
      require "async/http/protocol/https"
      require "async/websocket/client"
    rescue LoadError
      raise Riffer::Helpers::Dependencies::LoadError,
        "Could not load async websocket dependencies. Add 'async', 'async-http', and 'async-websocket' to your Gemfile."
    end

    endpoint = Async::HTTP::Endpoint.parse(
      url,
      protocol: Async::HTTP::Protocol::HTTP11,
      alpn_protocols: HTTP1_ALPN
    )

    client = Async::WebSocket::Client.open(endpoint)
    connection = if headers.empty?
      client.connect(endpoint.authority, endpoint.path)
    else
      client.connect(endpoint.authority, endpoint.path, headers)
    end

    new(client: client, connection: connection)
  rescue Riffer::Helpers::Dependencies::LoadError
    raise
  rescue => error
    raise Riffer::Error, "Failed to establish websocket connection: #{error.message}"
  end

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
