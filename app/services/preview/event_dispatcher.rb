# frozen_string_literal: true

module Preview
  class EventDispatcher
    def self.handle(event)
      parents_for(event).find_each { |parent| dispatch_for(parent, event) }
    end

    # GitHub connect stores the repo in github_repo_full_name and never sets
    # git_provider; GitLab/Bitbucket use the generic (git_provider, git_repo_full_name) pair.
    def self.parents_for(event)
      scope = AppRecord.main_apps.where(preview_enabled: true)
      if event.provider.to_s == "github"
        scope.where(github_repo_full_name: event.repo_full_name)
      else
        scope.where(git_provider: event.provider.to_s, git_repo_full_name: event.repo_full_name)
      end
    end

    def self.dispatch_for(parent, event)
      if event.deploy_action?
        if Preview::CapEnforcer.allow?(parent.team)
          Preview::DeployJob.perform_later(parent.id, event_to_h(event))
        else
          Preview::Commenter.cap_reached!(parent_app: parent, pr_number: event.pr_number)
        end
      elsif event.cleanup_action?
        if parent.preview_apps.exists?(pr_number: event.pr_number)
          Preview::CleanupJob.perform_later(parent.id, event.pr_number)
        end
      end
    end

    def self.event_to_h(event)
      Preview::PrEvent::ATTRS.each_with_object({}) { |k, h| h[k] = event.public_send(k) }
    end
  end
end
