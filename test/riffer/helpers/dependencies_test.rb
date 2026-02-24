# frozen_string_literal: true

require "test_helper"

describe Riffer::Helpers::Dependencies do
  let(:subject_class) do
    Class.new { include Riffer::Helpers::Dependencies }
  end

  let(:instance) { subject_class.new }

  def with_singleton_stub(target, method_name, replacement)
    singleton_class = target.singleton_class
    method_defined = singleton_class.method_defined?(method_name) || singleton_class.private_method_defined?(method_name)
    original_method = target.method(method_name) if method_defined

    target.define_singleton_method(method_name) { replacement }
    yield
  ensure
    if method_defined
      target.define_singleton_method(method_name, original_method)
    else
      singleton_class.send(:remove_method, method_name)
    end
  end

  describe "#depends_on" do
    describe "when the gem is not installed" do
      it "raises LoadError" do
        assert_raises(Riffer::Helpers::Dependencies::LoadError) do
          instance.depends_on("nonexistent_gem_xyz_12345")
        end
      end

      it "includes gem name in error message" do
        error = assert_raises(Riffer::Helpers::Dependencies::LoadError) do
          instance.depends_on("nonexistent_gem_xyz_12345")
        end

        assert_includes(error.message, "Could not load nonexistent_gem_xyz_12345")
      end

      it "includes installation guidance in error message" do
        error = assert_raises(Riffer::Helpers::Dependencies::LoadError) do
          instance.depends_on("nonexistent_gem_xyz_12345")
        end

        assert_includes(error.message, "ensure that the nonexistent_gem_xyz_12345 gem is installed")
      end
    end

    describe "when Bundler is not defined" do
      before do
        instance.define_singleton_method(:gem) { |_name| true }
        instance.define_singleton_method(:defined?) { |_const| false }
      end

      it "returns true when req is true" do
        result = instance.depends_on("rake", req: true)
        expect(result).must_equal true
      end

      it "returns true when req is false" do
        result = instance.depends_on("rake", req: false)
        expect(result).must_equal true
      end

      it "returns true when req is a truthy value other than true or false" do
        instance.define_singleton_method(:require) { |_lib| true }
        result = instance.depends_on("rake", req: "custom_lib")
        expect(result).must_equal true
      end
    end

    describe "error classes" do
      it "defines LoadError as a subclass of ::LoadError" do
        expect(Riffer::Helpers::Dependencies::LoadError < ::LoadError).must_equal true
      end

      it "defines VersionError as a subclass of ScriptError" do
        expect(Riffer::Helpers::Dependencies::VersionError < ScriptError).must_equal true
      end
    end

    describe "with a real installed gem from Gemfile" do
      # Using "rake" which is a dev dependency in the Gemfile
      before do
        instance.define_singleton_method(:gem) { |_name| true }
        instance.define_singleton_method(:defined?) { |const| (const == "Bundler") ? "constant" : nil }
      end

      it "returns true when gem is in Gemfile and version matches" do
        result = instance.depends_on("rake", req: false)
        expect(result).must_equal true
      end

      it "returns true when req is a custom library name and require succeeds" do
        instance.define_singleton_method(:require) { |_lib| true }
        result = instance.depends_on("rake", req: "custom_lib")
        expect(result).must_equal true
      end
    end

    describe "when gem is only present in Bundler locked specs" do
      before do
        instance.define_singleton_method(:gem) { |_name| true }
        instance.define_singleton_method(:defined?) { |const| (const == "Bundler") ? "constant" : nil }
        instance.define_singleton_method(:require) { |_lib| true }
      end

      it "accepts transitive dependencies from Gemfile.lock" do
        gem_name = "transitive_only_gem"
        gem_version = Gem::Version.new("1.2.3")
        loaded_spec = Gem::Specification.new do |spec|
          spec.name = gem_name
          spec.version = gem_version
        end
        locked_spec = Gem::Specification.new do |spec|
          spec.name = gem_name
          spec.version = gem_version
        end
        bundler_definition = Struct.new(:dependencies).new([])
        bundler_locked = Struct.new(:specs).new([locked_spec])

        with_singleton_stub(Gem, :loaded_specs, {gem_name => loaded_spec}) do
          with_singleton_stub(Bundler, :load, bundler_definition) do
            with_singleton_stub(Bundler, :locked_gems, bundler_locked) do
              result = instance.depends_on(gem_name, req: false)
              expect(result).must_equal true
            end
          end
        end
      end
    end

    describe "when gem is installed but not in Gemfile or lockfile" do
      before do
        instance.define_singleton_method(:gem) { |_name| true }
        instance.define_singleton_method(:defined?) { |const| (const == "Bundler") ? "constant" : nil }
      end

      it "raises VersionError with Gemfile.lock guidance" do
        gem_name = "installed_but_not_locked_gem"
        loaded_spec = Gem::Specification.new do |spec|
          spec.name = gem_name
          spec.version = Gem::Version.new("1.0.0")
        end
        bundler_definition = Struct.new(:dependencies).new([])
        bundler_locked = Struct.new(:specs).new([])

        error = with_singleton_stub(Gem, :loaded_specs, {gem_name => loaded_spec}) do
          with_singleton_stub(Bundler, :load, bundler_definition) do
            with_singleton_stub(Bundler, :locked_gems, bundler_locked) do
              assert_raises(Riffer::Helpers::Dependencies::VersionError) do
                instance.depends_on(gem_name, req: false)
              end
            end
          end
        end

        assert_includes(error.message, "Gemfile or Gemfile.lock")
      end
    end
  end
end
