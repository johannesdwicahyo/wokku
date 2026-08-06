class VitalsScriptController < ActionController::API
  SCRIPT_PATH = Wokku::Engine.root.join("vendor/javascript/wokku-vitals.js").freeze
  SCRIPT_BODY = SCRIPT_PATH.read.freeze
  ETAG        = Digest::SHA1.hexdigest(SCRIPT_BODY).freeze

  def show
    response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
    response.headers["ETag"]          = ETAG
    response.headers["Content-Type"]  = "application/javascript; charset=utf-8"
    render plain: SCRIPT_BODY
  end
end
