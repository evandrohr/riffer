# frozen_string_literal: true
# rbs_inline: enabled

# Thread-backed websocket transport for realtime voice drivers.
class Riffer::Voice::Transports::ThreadWebsocket
  extend Riffer::Helpers::Dependencies

  CLOSE_SENTINEL = Object.new.freeze #: Object

  # Managed websocket client handle.
  attr_reader :client #: untyped

  #: (client: untyped, read_queue: Queue[untyped]) -> void
  def initialize(client:, read_queue:)
    @client = client
    @read_queue = read_queue
    @closed = false
  end

  #: (url: String, ?headers: Hash[String, String]) -> Riffer::Voice::Transports::ThreadWebsocket
  def self.connect(url:, headers: {})
    load_dependencies!

    queue = Queue.new
    client = build_client(url: url, headers: headers)
    transport = new(client: client, read_queue: queue)
    transport.send(:bind_client_callbacks)
    transport
  rescue Riffer::Helpers::Dependencies::LoadError
    raise
  rescue => error
    raise Riffer::Error, "Failed to establish websocket connection: #{error.message}"
  end

  #: (url: String, headers: Hash[String, String]) -> untyped
  def self.connect_with_headers(url:, headers:)
    WebSocket::Client::Simple.connect(url, headers: headers)
  rescue ArgumentError => error
    # Older websocket-client-simple versions may not accept keyword headers.
    raise unless error.message.include?("unknown keyword") || error.message.include?("wrong number of arguments")

    WebSocket::Client::Simple.connect(url, headers)
  end
  private_class_method :connect_with_headers

  #: (url: String, headers: Hash[String, String]) -> untyped
  def self.build_client(url:, headers:)
    return WebSocket::Client::Simple.connect(url) if headers.empty?

    connect_with_headers(url: url, headers: headers)
  end
  private_class_method :build_client

  #: () -> void
  def self.load_dependencies!
    depends_on "websocket-client-simple", req: "websocket-client-simple"
  rescue Riffer::Helpers::Dependencies::LoadError, LoadError
    raise Riffer::Helpers::Dependencies::LoadError,
      "Could not load thread websocket dependency. Add 'websocket-client-simple' to your Gemfile."
  end
  private_class_method :load_dependencies!

  #: () -> untyped
  def read
    frame = @read_queue.pop
    return nil if frame.equal?(CLOSE_SENTINEL)
    raise frame if frame.is_a?(Exception)

    frame
  end

  #: (Hash[String, untyped]) -> void
  def write_json(payload)
    @client.send(payload.to_json)
  end

  #: () -> void
  def close
    return if @closed

    @closed = true
    @client.close
  ensure
    @read_queue << CLOSE_SENTINEL
  end

  private

  #: () -> void
  def bind_client_callbacks
    @client.on(:message) { |message| @read_queue << extract_payload(message) }
    @client.on(:error) { |error| @read_queue << normalize_error(error) }
    @client.on(:close) { close }
  end

  #: (untyped) -> untyped
  def extract_payload(message)
    if message.respond_to?(:data)
      message.data
    else
      message
    end
  end

  #: (untyped) -> Exception
  def normalize_error(error)
    return error if error.is_a?(Exception)

    Riffer::Error.new("Thread websocket connection error: #{error}")
  end
end
