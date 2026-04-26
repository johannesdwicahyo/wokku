class AiDebugger
  API_URL = "https://api.anthropic.com/v1/messages"
  MODEL = "claude-sonnet-4-20250514"

  def initialize(deploy)
    @deploy = deploy
  end

  def diagnose
    return { error: "No API key configured" } unless api_key_configured?
    return { error: "No deploy log available" } unless @deploy.log.present?

    response = call_api(build_prompt)
    { diagnosis: response }
  rescue => e
    { error: "AI diagnosis failed: #{e.message}" }
  end

  private

  def api_key_configured?
    ENV["ANTHROPIC_API_KEY"].present?
  end

  def build_prompt
    <<~PROMPT
      You are a DevOps expert. A deploy just failed on a Dokku-based PaaS (similar to Heroku).

      App: #{@deploy.app_record.name}
      Status: #{@deploy.status}
      #{@deploy.commit_sha ? "Commit: #{@deploy.commit_sha}" : ""}

      Deploy log (last 3000 chars):
      ```
      #{@deploy.log.to_s.last(3000)}
      ```

      Diagnose the failure in 2-3 sentences. Then provide 1-3 specific fix suggestions as bullet points. Be concise and actionable. Format as Markdown.
    PROMPT
  end

  def call_api(prompt)
    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri, {
      "Content-Type" => "application/json",
      "x-api-key" => ENV["ANTHROPIC_API_KEY"],
      "anthropic-version" => "2023-06-01"
    })

    request.body = {
      model: MODEL,
      max_tokens: 500,
      messages: [ { role: "user", content: prompt } ]
    }.to_json

    response = http.request(request)
    data = JSON.parse(response.body)

    if data["content"]&.any?
      data["content"].first["text"]
    else
      "Unable to diagnose: #{data['error']&.dig('message') || 'Unknown error'}"
    end
  end
end
