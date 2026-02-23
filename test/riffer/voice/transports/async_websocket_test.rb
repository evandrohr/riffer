# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Transports::AsyncWebsocket do
  describe ".connect" do
    it "preserves dependency load errors for missing async gems" do
      transport_class = Riffer::Voice::Transports::AsyncWebsocket

      error = with_overridden_class_method(
        klass: transport_class,
        method_name: :depends_on,
        implementation: ->(*_args, **_kwargs) { raise Riffer::Helpers::Dependencies::LoadError, "Could not load async-http" }
      ) do
        expect {
          transport_class.connect(url: "wss://example.test/realtime")
        }.must_raise(Riffer::Helpers::Dependencies::LoadError)
      end

      expect(error.message).must_include "Could not load async websocket dependencies"
    end
  end

  describe ".connect_with_headers" do
    let(:endpoint) { Struct.new(:authority, :path).new("api.openai.com", "/v1/realtime") }
    let(:headers) { {"Authorization" => "Bearer test-key"} }

    it "uses keyword headers when supported by async-websocket" do
      received = []
      client = Object.new
      client.define_singleton_method(:connect) do |*args, **kwargs|
        received << {args: args, kwargs: kwargs}
        :connection
      end

      connection = Riffer::Voice::Transports::AsyncWebsocket.send(
        :connect_with_headers,
        client: client,
        endpoint: endpoint,
        headers: headers
      )

      expect(connection).must_equal :connection
      expect(received).must_equal [
        {
          args: ["api.openai.com", "/v1/realtime"],
          kwargs: {headers: {"Authorization" => "Bearer test-key"}}
        }
      ]
    end

    it "falls back to positional headers for legacy async-websocket versions" do
      received = []
      client = Object.new
      client.define_singleton_method(:connect) do |*args, **kwargs|
        if kwargs.any?
          raise ArgumentError, "unknown keyword: :headers"
        end

        received << {args: args, kwargs: kwargs}
        :connection
      end

      connection = Riffer::Voice::Transports::AsyncWebsocket.send(
        :connect_with_headers,
        client: client,
        endpoint: endpoint,
        headers: headers
      )

      expect(connection).must_equal :connection
      expect(received).must_equal [
        {
          args: ["api.openai.com", "/v1/realtime", {"Authorization" => "Bearer test-key"}],
          kwargs: {}
        }
      ]
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
