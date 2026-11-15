require "net/http"
require "json"
require "aws-sigv4"

module ObjectStorage
  # Signs (SigV4, service s3) calls to RustFS's S3 API and its admin API
  # (<endpoint>/rustfs/admin/v3, plain JSON bodies).
  class Client
    ADMIN = "/rustfs/admin/v3"

    def initialize(endpoint: nil, access_key: nil, secret_key: nil)
      cfg = Wokku.config.object_storage || {}
      @endpoint = URI(endpoint || cfg[:endpoint])
      @signer = Aws::Sigv4::Signer.new(
        service: "s3", region: "us-east-1",
        access_key_id: access_key || cfg[:access_key],
        secret_access_key: secret_key || cfg[:secret_key]
      )
    end

    def create_bucket(name)
      call(:put, "/#{name}", ok: [ 409 ], ok_code: "BucketAlreadyOwnedByYou")
    end

    # RustFS 1.0.4 honours x-rustfs-force-delete (verified live): empties + deletes.
    def delete_bucket!(name)
      call(:delete, "/#{name}", headers: { "x-rustfs-force-delete" => "true" })
    end

    def add_user(access_key, secret_key)
      admin(:put, "add-user", { accessKey: access_key }, { secretKey: secret_key, status: "enabled" })
    end

    def remove_user(access_key) = admin(:delete, "remove-user", { accessKey: access_key })

    def put_policy(name, bucket)
      policy = { Version: "2012-10-17", Statement: [ {
        Effect: "Allow", Action: [ "s3:*" ],
        Resource: [ "arn:aws:s3:::#{bucket}", "arn:aws:s3:::#{bucket}/*" ]
      } ] }
      admin(:put, "add-canned-policy", { name: name }, policy)
    end

    def remove_policy(name) = admin(:delete, "remove-canned-policy", { name: name })

    def attach_policy(name, access_key)
      admin(:put, "set-user-or-group-policy", { policyName: name, userOrGroup: access_key, isGroup: "false" })
    end

    def set_quota(bucket, gb)
      admin(:put, "set-bucket-quota", { bucket: bucket }, { quota: gb * 1024**3, quotatype: "hard" })
    end

    def usage
      body = JSON.parse(call(:get, "#{ADMIN}/datausageinfo", raw: true))
      (body["buckets_usage"] || {}).transform_values { |v| v["size"].to_i }
    end

    private

    def admin(verb, action, query = {}, body = nil)
      call(verb, "#{ADMIN}/#{action}", query: query, body: body && JSON.generate(body))
    end

    # Returns true (or the body when raw:). ok_code: treat an `ok` status with
    # that S3 error code as success.
    def call(verb, path, query: {}, body: nil, headers: {}, raw: false, ok: [], ok_code: nil)
      uri = @endpoint.dup
      uri.path = path
      uri.query = URI.encode_www_form(query) unless query.empty?
      payload = body.to_s
      signed = @signer.sign_request(http_method: verb.to_s.upcase, url: uri.to_s, headers: headers,
        body: payload).headers
      req = Net::HTTP.const_get(verb.to_s.capitalize).new(uri, headers.merge(signed))
      req["Content-Type"] = "application/json" if body
      req.body = payload if body
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 60) { |h| h.request(req) }
      code = res.code.to_i
      return (raw ? res.body : true) if code.between?(200, 299)
      return true if ok.include?(code) && res.body.to_s.include?("<Code>#{ok_code}</Code>")
      msg = res.body.to_s[%r{<Message>(.*?)</Message>}m, 1] || res.body.to_s[0, 200]
      raise Error, "RustFS #{verb.to_s.upcase} #{path} -> #{code}: #{msg}"
    end
  end
end
