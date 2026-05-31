require "net/http"
require "json"

module Bitbucket
  class Client
    BASE_URL = "https://api.bitbucket.org/2.0"

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

    def add_comment(repo_full_name, pr_id, text)
      ensure_token!
      uri = URI("#{BASE_URL}/repositories/#{repo_full_name}/pullrequests/#{pr_id}/comments")
      data = post(uri, { "content" => { "raw" => text } })
      Result.new(id: data["id"], body: data.dig("content", "raw"))
    end

    def update_comment(repo_full_name, pr_id, comment_id, text)
      ensure_token!
      uri = URI("#{BASE_URL}/repositories/#{repo_full_name}/pullrequests/#{pr_id}/comments/#{comment_id}")
      put(uri, { "content" => { "raw" => text } })
    end

    private

    def ensure_token!
      Bitbucket::TokenRefresher.new(@user).refresh! if @user.bitbucket_token_expired?
    end

    def post(uri, payload)
      req = Net::HTTP::Post.new(uri)
      auth!(req)
      req["Content-Type"] = "application/json"
      req.body = payload.to_json
      perform(uri, req)
    end

    def put(uri, payload)
      req = Net::HTTP::Put.new(uri)
      auth!(req)
      req["Content-Type"] = "application/json"
      req.body = payload.to_json
      perform(uri, req)
    end

    def auth!(req)
      req["Authorization"] = "Bearer #{@user.bitbucket_access_token}"
    end

    def perform(uri, req)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
      unless res.code.start_with?("2")
        raise ApiError.new("Bitbucket #{req.method} #{uri.path} returned #{res.code}", status: res.code.to_i)
      end
      res.body.empty? ? {} : JSON.parse(res.body)
    end
  end
end
