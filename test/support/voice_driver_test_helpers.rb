# frozen_string_literal: true

module VoiceDriverTestHelpers
  class FakeTransport
    attr_reader :writes

    def initialize(frames: [], fail_writes_after: nil, write_error: nil)
      @frames = frames.dup
      @writes = []
      @closed = false
      @fail_writes_after = fail_writes_after
      @write_error = write_error || RuntimeError.new("fake transport write failure")
      @write_count = 0
    end

    def read
      @frames.shift
    end

    def write_json(payload)
      @write_count += 1
      if !@fail_writes_after.nil? && @write_count > @fail_writes_after
        raise @write_error
      end

      @writes << payload
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end
  end

  class FakeChildTask
    attr_reader :annotation

    def initialize(annotation:, &block)
      @annotation = annotation
      @block = block
      @stopped = false
    end

    def run
      @block.call unless @stopped
    end

    def stop
      @stopped = true
    end
  end

  class FakeAsyncTask
    attr_reader :children

    def initialize
      @children = []
    end

    def async(annotation: nil, &block)
      child = FakeChildTask.new(annotation: annotation, &block)
      @children << child
      child
    end
  end

  class StubParser
    def initialize(events: [])
      @events = events
    end

    def call(_payload)
      @events
    end
  end
end
