module CloudProviders
  class Base
    def initialize(credential)
      @credential = credential
    end

    def regions
      raise NotImplementedError
    end

    def sizes
      raise NotImplementedError
    end

    def create_server(name:, region:, size:, ssh_key: nil)
      raise NotImplementedError
    end

    def delete_server(server_id)
      raise NotImplementedError
    end

    def server_status(server_id)
      raise NotImplementedError
    end

    private

    def api_get(path)
      uri = URI("#{api_base}#{path}")
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = auth_header
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      JSON.parse(http.request(req).body)
    end

    def api_post(path, body)
      uri = URI("#{api_base}#{path}")
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      req["Authorization"] = auth_header
      req.body = body.to_json
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      JSON.parse(http.request(req).body)
    end

    def api_delete(path)
      uri = URI("#{api_base}#{path}")
      req = Net::HTTP::Delete.new(uri)
      req["Authorization"] = auth_header
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.request(req)
    end

    def api_base
      CloudCredential::PROVIDERS[@credential.provider]["api_base"]
    end

    def auth_header
      raise NotImplementedError
    end
  end
end
