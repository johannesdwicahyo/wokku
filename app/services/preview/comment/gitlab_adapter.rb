module Preview
  module Comment
    class GitlabAdapter
      def initialize(parent_app, preview_app: nil)
        @parent  = parent_app
        @preview = preview_app
      end

      def add(pr_number:, body:)
        client = gitlab_client
        return nil unless client
        result = client.add_comment(@parent.git_repo_full_name, pr_number, body)
        @preview&.update_columns(preview_comment_mr_iid: pr_number) if result&.id
        result.id
      end

      def update(comment_id:, body:)
        client = gitlab_client
        return unless client
        return unless @preview&.preview_comment_mr_iid
        client.update_comment(@parent.git_repo_full_name, @preview.preview_comment_mr_iid, comment_id, body)
      end

      private

      def gitlab_client
        user = @parent.team.users.where.not(gitlab_access_token: nil).first
        return nil unless user
        Gitlab::Client.new(user)
      end
    end
  end
end
