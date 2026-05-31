# frozen_string_literal: true

module Preview
  class EventDispatcher
    def self.handle(event)
      AppRecord.main_apps
               .where(git_provider: event.provider.to_s,
                      git_repo_full_name: event.repo_full_name,
                      preview_enabled: true)
               .find_each { |parent| dispatch_for(parent, event) }
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
