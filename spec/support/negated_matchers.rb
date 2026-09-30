# frozen_string_literal: true

# Compound "nothing was created" assertions: expect { }.to not_change(...).and not_change(...)
RSpec::Matchers.define_negated_matcher :not_change, :change
RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job
