# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Transports::AsyncWebsocket do
  describe ".connect" do
    it "preserves dependency load errors for missing async gems" do
      transport_class = Riffer::Voice::Transports::AsyncWebsocket

      transport_class.define_singleton_method(:require) do |_name|
        raise LoadError, "cannot load such file -- async/http/endpoint"
      end

      error = expect {
        transport_class.connect(url: "wss://example.test/realtime")
      }.must_raise(Riffer::Helpers::Dependencies::LoadError)

      expect(error.message).must_include "Could not load async websocket dependencies"
    ensure
      transport_class.singleton_class.send(:remove_method, :require)
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
end
