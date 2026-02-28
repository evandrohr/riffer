# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "json"
require "shellwords"

Minitest::TestTask.create

require "standard/rake"
require "rdoc/task"

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = "doc"
  rdoc.title = "Riffer Documentation"
  rdoc.main = "README.md"

  # Explicitly include top-level docs and the library
  rdoc.rdoc_files.include("README.md", "CHANGELOG.md", "LICENSE.txt", "docs/**/*.md", "docs_providers/**/*.md")
  rdoc.rdoc_files.include("lib/**/*.rb")

  # Use Markdown where available and ensure UTF-8
  rdoc.options << "--charset" << "utf-8" << "--markup" << "markdown"
end

task docs: :rdoc

namespace :quality do
  def ensure_rubycritic_installed!
    return if Gem::Specification.find_all_by_name("rubycritic").any?

    abort "rubycritic gem is not installed. Install it with: bundle add rubycritic --group development"
  end

  def rubycritic_rating_rank(rating)
    ranks = {"A" => 5, "B" => 4, "C" => 3, "D" => 2, "E" => 1, "F" => 0}
    ranks.fetch(rating.to_s.upcase, -1)
  end

  def run_rubycritic(target:, output_path:, format: nil)
    format_flag = format.nil? ? "" : " --format #{Shellwords.escape(format)}"
    sh "RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubycritic --no-browser#{format_flag} --path #{Shellwords.escape(output_path)} #{Shellwords.escape(target)}"
  end

  desc "Run RubyCritic report for lib/ (output: tmp/rubycritic)"
  task :rubycritic do
    ensure_rubycritic_installed!

    output_path = ENV.fetch("RUBYCRITIC_OUTPUT", "tmp/rubycritic")
    target = ENV.fetch("RUBYCRITIC_TARGET", "lib")
    format = ENV.fetch("RUBYCRITIC_FORMAT", nil)

    run_rubycritic(target: target, output_path: output_path, format: format)
  end

  namespace :voice do
    desc "Run RubyCritic report for lib/riffer/voice/** (defaults to JSON output)"
    task :rubycritic do
      ensure_rubycritic_installed!

      output_path = ENV.fetch("RUBYCRITIC_OUTPUT", "tmp/rubycritic-voice")
      format = ENV.fetch("RUBYCRITIC_FORMAT", "json")
      run_rubycritic(target: "lib/riffer/voice", output_path: output_path, format: format)
    end

    desc "Summarize voice RubyCritic ratings (set RUBYCRITIC_ENFORCE=1 to fail on threshold miss)"
    task :gate do
      output_path = ENV.fetch("RUBYCRITIC_OUTPUT", "tmp/rubycritic-voice")
      minimum_rating = ENV.fetch("RUBYCRITIC_MIN_RATING", "B").upcase
      report_path = File.join(output_path, "report.json")

      unless File.exist?(report_path)
        abort "Missing #{report_path}. Run `bundle exec rake quality:voice:rubycritic` first."
      end

      report = JSON.parse(File.read(report_path))
      modules = Array(report["analysed_modules"]).select do |entry|
        entry["path"].to_s.start_with?("lib/riffer/voice/")
      end

      failing = modules.select do |entry|
        rubycritic_rating_rank(entry["rating"]) < rubycritic_rating_rank(minimum_rating)
      end

      if failing.empty?
        puts "Voice RubyCritic gate passed (minimum rating #{minimum_rating})."
        next
      end

      puts "Voice RubyCritic modules below #{minimum_rating}:"
      failing.sort_by { |entry| [entry["rating"].to_s, entry["path"].to_s] }.each do |entry|
        puts "  - #{entry["path"]} (#{entry["rating"]})"
      end

      abort "Voice RubyCritic gate failed" if ENV["RUBYCRITIC_ENFORCE"] == "1"
      puts "Non-blocking mode: set RUBYCRITIC_ENFORCE=1 to fail on threshold misses."
    end
  end
end

desc "Run RubyCritic quality report"
task rubycritic: "quality:rubycritic"

desc "Run RubyCritic quality report for realtime voice code"
task voice_rubycritic: "quality:voice:rubycritic"

namespace :rbs do
  desc "Generate RBS type signatures from inline annotations"
  task :generate do
    sh "bundle exec rbs-inline --output sig/generated lib"
  end

  desc "Watch lib/ for changes and regenerate RBS files"
  task :watch do
    require "guard"
    require "guard/commander"

    Guard.start(no_interactions: true)
  end
end

namespace :steep do
  desc "Run Steep type checker"
  task :check do
    sh "bundle exec steep check"
  end
end

task default: %i[test standard steep:check]
