module Preview
  module Provider
    class Bitbucket < Base
      EVENT_KEY_MAP = {
        "pullrequest:created"   => :opened,
        "pullrequest:updated"   => :synchronize,
        "pullrequest:fulfilled" => :merged,
        "pullrequest:rejected"  => :closed
      }.freeze

      def self.parse(payload, event_key:)
        pr = payload["pullrequest"] || {}
        Preview::PrEvent.new(
          provider: :bitbucket,
          action: EVENT_KEY_MAP.fetch(event_key, event_key.to_s.to_sym),
          pr_number: pr["id"],
          branch: pr.dig("source", "branch", "name"),
          sha: pr.dig("source", "commit", "hash"),
          repo_full_name: payload.dig("repository", "full_name"),
          title: pr["title"],
          installation_id: nil,
          author: payload.dig("actor", "username")
        )
      end
    end
  end
end
