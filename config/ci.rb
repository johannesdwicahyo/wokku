# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Security: Secret scan",
    "sh", "-c", "bin/scan-secrets $(git ls-files -- '*.rb' '*.yml' '*.json' '*.js' '*.erb' | grep -vE 'test/|spec/|docs/content/')"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  # Minitest step removed 2026-05-25 — full migration to RSpec landed
  # with PRs #10 + #11, and the final 10 legacy Minitest files were
  # deleted in this PR (1.8 — legacy billing rail). Eliminates the
  # ~28-minute local-CI hang the Minitest system tests caused.
  step "Tests: RSpec", "bundle exec rspec"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
