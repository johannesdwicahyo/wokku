require "uri"

# Rejects requests whose PATH can't be parsed as a URI with a clean 400,
# before they reach routing.
#
# Scanner bots probe garbage paths like "/shop/[category]/*" (the brackets
# are invalid URI characters). The www->apex redirect in routes.rb builds
# "https://wokku.cloud/<path>" and ActionDispatch::Routing::Redirect runs
# URI.parse on it, which raises URI::InvalidURIError deep in the framework →
# a 500 + Sentry noise for what is really a malformed client request.
#
# We validate only the incoming PATH_INFO here (not the query string, which
# legitimately contains brackets for Rails nested params like user[name]=x),
# so genuine URI bugs in business logic still surface as 500s.
class RejectMalformedUri
  def initialize(app)
    @app = app
  end

  def call(env)
    URI.parse(env["PATH_INFO"].to_s)
    @app.call(env)
  rescue URI::InvalidURIError
    [ 400, { "Content-Type" => "text/plain; charset=utf-8" }, [ "Bad Request\n" ] ]
  end
end
