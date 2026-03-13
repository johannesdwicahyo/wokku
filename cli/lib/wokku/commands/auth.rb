require "tty-prompt"
require "faraday"

module Wokku
  module Commands
    class Auth
      def login(api_url: nil)
        prompt = TTY::Prompt.new
        pastel = Pastel.new

        url = api_url || prompt.ask("API URL:", default: "https://wokku.dev")
        email = prompt.ask("Email:")
        password = prompt.mask("Password:")

        conn = Faraday.new(url: url) do |f|
          f.request :json
          f.response :json
        end

        response = conn.post("/api/v1/auth/login", { email: email, password: password })

        if response.status == 201
          data = response.body
          ConfigStore.set("api_url", url)
          ConfigStore.set("token", data["token"])
          puts pastel.green("Logged in as #{data.dig("user", "email")}")
        else
          error = response.body.is_a?(Hash) ? response.body["error"] : "Login failed"
          puts pastel.red("Error: #{error}")
          exit 1
        end
      end

      def logout
        pastel = Pastel.new
        begin
          client = ApiClient.new
          client.delete("auth/logout")
        rescue Error, ApiClient::ApiError
          # Ignore errors during logout
        end
        ConfigStore.clear
        puts pastel.green("Logged out")
      end

      def whoami
        pastel = Pastel.new
        client = ApiClient.new
        data = client.get("auth/whoami")
        puts "Email: #{pastel.bold(data["email"])}"
        puts "Role:  #{data["role"]}"
      end
    end
  end
end
