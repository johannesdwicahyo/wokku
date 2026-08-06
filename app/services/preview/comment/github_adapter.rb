module Preview
  module Comment
    class GithubAdapter
      def initialize(parent_app)
        @parent = parent_app
      end

      def add(pr_number:, body:)
        client = github_client
        return nil unless client
        comment = client.add_comment(@parent.github_repo_full_name, pr_number, body)
        comment.id
      end

      def update(comment_id:, body:)
        client = github_client
        return unless client
        client.update_comment(@parent.github_repo_full_name, comment_id, body)
      end

      private

      def github_client
        installation_id = @parent.team.users.where.not(github_installation_id: nil).pick(:github_installation_id)
        return nil unless installation_id
        GithubApp.new(installation_id).client
      end
    end
  end
end
