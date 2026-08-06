module Api
  module V1
    module Serializers
      class PreviewApp
        def initialize(preview)
          @preview = preview
        end

        def call
          {
            id: @preview.id,
            name: @preview.name,
            pr_number: @preview.pr_number,
            branch: @preview.deploy_branch,
            status: @preview.status,
            url: url
          }
        end

        private

        def url
          host = @preview.preview_hostname
          host ? "https://#{host}" : nil
        end
      end
    end
  end
end
