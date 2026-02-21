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
end
