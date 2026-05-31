module Preview
  class Commenter
    def initialize(preview_app)
      @preview = preview_app
      @parent  = preview_app.parent_app
    end

    def deployed!(url:, commit_sha:)
      adapter = Preview::Comment::Dispatcher.for(@parent, preview_app: @preview)
      return unless adapter

      body = deployed_body(url: url, commit_sha: commit_sha)

      if @preview.preview_comment_id
        adapter.update(comment_id: @preview.preview_comment_id, body: body)
      else
        comment_id = adapter.add(pr_number: @preview.pr_number, body: body)
        @preview.update_columns(preview_comment_id: comment_id) if comment_id
      end
    rescue StandardError => e
      Rails.logger.warn("Preview::Commenter: #{e.message}")
    end

    def self.cap_reached!(parent_app:, pr_number:)
      adapter = Preview::Comment::Dispatcher.for(parent_app)
      return unless adapter

      body = "**Preview cap reached** (#{Preview::CapEnforcer.cap} concurrent previews per team)\n\n" \
             "Close another preview, or merge an open PR, to free a slot. " \
             "Manage previews on your [Wokku dashboard](https://wokku.cloud/dashboard/apps/#{parent_app.id})."

      adapter.add(pr_number: pr_number, body: body)
    rescue StandardError => e
      Rails.logger.warn("Preview::Commenter.cap_reached!: #{e.message}")
    end

    private

    def deployed_body(url:, commit_sha:)
      <<~MD
        **Preview deployed!** :rocket:

        | | |
        |---|---|
        | **URL** | #{url} |
        | **Commit** | `#{commit_sha&.first(7)}` |
        | **App** | `#{@preview.name}` |

        _Deployed by [Wokku](https://wokku.cloud)_
      MD
    end
  end
end
