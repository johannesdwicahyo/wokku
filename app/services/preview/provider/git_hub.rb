module Preview
  module Provider
    class GitHub < Base
      def self.parse(payload)
        pr = payload["pull_request"] || {}
        action = normalize_action(payload["action"], merged: pr["merged"])

        Preview::PrEvent.new(
          provider: :github,
          action: action,
          pr_number: payload["number"],
          branch: pr.dig("head", "ref"),
          sha: pr.dig("head", "sha"),
          repo_full_name: payload.dig("repository", "full_name"),
          title: pr["title"],
          installation_id: payload.dig("installation", "id"),
          author: pr.dig("user", "login")
        )
      end
    end
  end
end
