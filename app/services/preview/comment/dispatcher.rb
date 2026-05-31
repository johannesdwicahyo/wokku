module Preview
  module Comment
    class Dispatcher
      def self.for(parent_app, preview_app: nil)
        provider = parent_app.git_provider
        return nil if provider.blank?

        case provider
        when "github"    then Preview::Comment::GithubAdapter.new(parent_app)
        when "gitlab"    then Preview::Comment::GitlabAdapter.new(parent_app, preview_app: preview_app)
        when "bitbucket" then Preview::Comment::BitbucketAdapter.new(parent_app, preview_app: preview_app)
        else raise ArgumentError, "unsupported git provider: #{provider}"
        end
      end
    end
  end
end
