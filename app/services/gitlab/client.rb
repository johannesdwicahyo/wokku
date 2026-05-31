require "net/http"
require "json"
require "erb"

module Gitlab
  class Client
    BASE_URL = "https://gitlab.com/api/v4"

    class ApiError < StandardError
      attr_reader :status
      def initialize(message, status:)
        @status = status
        super(message)
      end
    end

    Result = Struct.new(:id, :body, keyword_init: true)

    def initialize(user)
      @user = user
    end

    def add_comment(project_path, mr_iid, text)
      ensure_token!
      uri = URI("#{BASE_URL}/projects/#{ERB::Util.url_encode(project_path)}/merge_requests/#{mr_iid}/notes")
      data = post(uri, "body" => text)
      Result.new(id: data["id"], body: data["body"])
    end

    def update_comment(project_path, mr_iid, note_id, text)
      ensure_token!
      uri = URI("#{BASE_URL}/projects/#{ERB::Util.url_encode(project_path)}/merge_requests/#{mr_iid}/notes/#{note_id}")
      put(uri, "body" => text)
    end

    private

    def ensure_token!
      Gitlab::TokenRefresher.new(@user).refresh! if @user.gitlab_token_expired?
    end

    def post(uri, payload)
      req = Net::HTTP::Post.new(uri)
      auth!(req)
      req.set_form_data(payload)
      perform(uri, req)
    end

    def put(uri, payload)
      req = Net::HTTP::Put.new(uri)
      auth!(req)
      req.set_form_data(payload)
      perform(uri, req)
    end

    def auth!(req)
      req["Authorization"] = "Bearer #{@user.gitlab_access_token}"
    end

    def perform(uri, req)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
      raise ApiError.new("GitLab #{req.method} #{uri.path} returned #{res.code}", status: res.code.to_i) unless res.code.start_with?("2")
      res.body.empty? ? {} : JSON.parse(res.body)
    end
  end
end
