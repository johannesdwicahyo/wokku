module Preview
  class PrEvent
    DEPLOY_ACTIONS  = %i[opened synchronize reopened].freeze
    CLEANUP_ACTIONS = %i[closed merged].freeze

    ATTRS = %i[provider action pr_number branch sha repo_full_name title installation_id author].freeze
    attr_reader(*ATTRS)

    def initialize(provider:, action:, pr_number:, branch:, sha:, repo_full_name:, title:, installation_id:, author:)
      @provider        = provider.to_sym
      @action          = action.to_sym
      @pr_number       = pr_number.to_i
      @branch          = branch.to_s
      @sha             = sha.to_s
      @repo_full_name  = repo_full_name.to_s
      @title           = title.to_s
      @installation_id = installation_id&.to_i
      @author          = author.to_s
      freeze
    end

    def deploy_action?  = DEPLOY_ACTIONS.include?(action)
    def cleanup_action? = CLEANUP_ACTIONS.include?(action)
  end
end
