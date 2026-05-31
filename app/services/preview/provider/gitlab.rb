module Preview
  module Provider
    class Gitlab < Base
      ACTION_MAP = {
        "open"   => :opened,
        "reopen" => :reopened,
        "update" => :synchronize,
        "close"  => :closed,
        "merge"  => :merged
      }.freeze

      def self.parse(payload)
        attrs = payload["object_attributes"] || {}
        Preview::PrEvent.new(
          provider: :gitlab,
          action: ACTION_MAP.fetch(attrs["action"].to_s, attrs["action"].to_s.to_sym),
          pr_number: attrs["iid"],
          branch: attrs["source_branch"],
          sha: attrs.dig("last_commit", "id"),
          repo_full_name: payload.dig("project", "path_with_namespace"),
          title: attrs["title"],
          installation_id: nil,
          author: payload.dig("user", "username")
        )
      end
    end
  end
end
