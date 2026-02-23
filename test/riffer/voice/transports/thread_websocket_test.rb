# frozen_string_literal: true

require "test_helper"

class ThreadWebsocketFakeClient
  attr_reader :sent_payloads, :close_calls

  def initialize
    @handlers = {}
    @sent_payloads = []
    @close_calls = 0
  end

  def on(event, &block)
    @handlers[event] = block
  end

  def emit(event, payload = nil)
    handler = @handlers[event]
    handler&.call(payload)
  end

  def send(payload)
    @sent_payloads << payload
  end

  def close
    @close_calls += 1
  end
end

describe Riffer::Voice::Transports::ThreadWebsocket do
  describe ".connect" do
    it "preserves dependency load errors for missing thread websocket gem" do
      transport_class = Riffer::Voice::Transports::ThreadWebsocket

      error = with_overridden_class_method(
        klass: transport_class,
        method_name: :require,
        implementation: ->(_name) { raise LoadError, "cannot load such file -- websocket-client-simple" }
      ) do
        expect {
          transport_class.connect(url: "wss://example.test/realtime")
        }.must_raise(Riffer::Helpers::Dependencies::LoadError)
      end

      expect(error.message).must_include "Could not load thread websocket dependency"
    end

    it "wires callbacks and provides queue-backed read/write behavior" do
      transport_class = Riffer::Voice::Transports::ThreadWebsocket
      client = ThreadWebsocketFakeClient.new
      build_calls = []
      transport = nil

      with_overridden_class_method(klass: transport_class, method_name: :require, implementation: ->(_name) { true }) do
        with_overridden_class_method(
          klass: transport_class,
          method_name: :build_client,
          implementation: ->(url:, headers:) {
            build_calls << {url: url, headers: headers}
            client
          }
        ) do
          transport = transport_class.connect(
            url: "wss://example.test/realtime",
            headers: {"Authorization" => "Bearer test-key"}
          )
        end
      end

      expect(build_calls).must_equal [
        {
          url: "wss://example.test/realtime",
          headers: {"Authorization" => "Bearer test-key"}
        }
      ]

      client.emit(:message, Struct.new(:data).new("{\"type\":\"ok\"}"))
      expect(transport.read).must_equal "{\"type\":\"ok\"}"

      transport.write_json("type" => "ping")
      expect(client.sent_payloads).must_equal ["{\"type\":\"ping\"}"]

      client.emit(:error, "boom")
      error = expect { transport.read }.must_raise(Riffer::Error)
      expect(error.message).must_include "Thread websocket connection error: boom"

      transport.close
      expect(client.close_calls).must_equal 1
      expect(transport.read).must_be_nil
    end
  end

  private

  def with_overridden_class_method(klass:, method_name:, implementation:)
    singleton = klass.singleton_class
    had_original = singleton.method_defined?(method_name, false) ||
      singleton.private_method_defined?(method_name, false)
    original = singleton.instance_method(method_name) if had_original

    singleton.send(:remove_method, method_name) if had_original
    singleton.send(:define_method, method_name, implementation)
    yield
  ensure
    singleton.send(:remove_method, method_name)
    singleton.send(:define_method, method_name, original) if had_original
  end
end
