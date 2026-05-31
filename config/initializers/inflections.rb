# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# (No custom inflections required.) The Preview::Provider::GitHub class
# lives in `app/services/preview/provider/git_hub.rb` so Zeitwerk's
# default camelize (`git_hub` → `GitHub`) handles it without a global
# inflection rule. A `github` rule would conflict with eager-loading
# the existing `app/controllers/github/` namespace, which Zeitwerk
# would then try to load as `GitHub::CallbacksController`.
