# frozen_string_literal: true
# rbs_inline: enabled

# Helper module for lazy loading gem dependencies.
#
# Used by providers to load their required gems only when needed.
module Riffer::Helpers::Dependencies
  # Raised when a required gem cannot be loaded.
  class LoadError < ::LoadError; end

  # Raised when a gem version requirement is not satisfied.
  class VersionError < ScriptError; end

  # Declares a dependency on a gem.
  #
  # Verifies the gem is installed and satisfies version requirements,
  # then requires it.
  #
  # Raises LoadError if the gem is not installed.
  # Raises VersionError if the gem version does not satisfy requirements.
  #
  #: (String, ?req: (bool | String)) -> true
  def depends_on(gem_name, req: true)
    gem(gem_name)

    return true unless defined?(Bundler)

    gem_version = Gem.loaded_specs[gem_name].version
    gem_requirement = dependency_requirement(gem_name)
    unless gem_requirement
      raise VersionError,
        "The #{gem_name} gem is installed but not specified in your Bundler dependencies (Gemfile or Gemfile.lock)."
    end

    unless gem_requirement.satisfied_by?(gem_version)
      raise VersionError, "The #{gem_name} gem is installed, but version #{gem_requirement} is required. You have #{gem_version}."
    end

    lib_name = gem_name if req == true
    lib_name = req if req.is_a?(String)

    require(lib_name) if lib_name

    true
  rescue ::LoadError
    raise LoadError, "Could not load #{gem_name}. Please ensure that the #{gem_name} gem is installed."
  end

  private

  #: (String) -> Gem::Requirement?
  def dependency_requirement(gem_name)
    direct_dependency = Bundler.load.dependencies.find { |dependency| dependency.name == gem_name }
    return direct_dependency.requirement if direct_dependency

    locked_spec = Bundler.locked_gems&.specs&.find { |spec| spec.name == gem_name }
    return Gem::Requirement.new("= #{locked_spec.version}") if locked_spec

    nil
  rescue NoMethodError
    nil
  end
end
