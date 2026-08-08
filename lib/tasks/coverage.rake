# frozen_string_literal: true

namespace :coverage do
  desc "Merge parallel_tests SimpleCov results and enforce the 95% line gate"
  task :check do
    require "simplecov"

    resultset = File.join(SimpleCov.coverage_path, ".resultset.json")
    abort "coverage:check — no resultset. Run the suite first." unless File.exist?(resultset)

    # Collate all per-worker results (command_names RSpec, RSpec2, … all in
    # one .resultset.json) into a single merged, engine-only report.
    SimpleCov.collate [ resultset ] do
      enable_coverage :branch
      SimpleCov.skip "/spec/"
      SimpleCov.skip "/harness/"
      SimpleCov.skip "/vendor/"
      SimpleCov.skip "/db/"
      cover "{app,lib}/**/*.rb"
    end

    covered = SimpleCov.result.covered_percent.round(2)
    puts "Merged line coverage: #{covered}%"
    abort "❌ Coverage #{covered}% is below the 95% line gate." if covered < 95
    puts "✅ Coverage gate passed (#{covered}% ≥ 95%)."
  end
end
