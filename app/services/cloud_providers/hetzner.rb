module CloudProviders
  class Hetzner < Base
    def regions
      data = api_get("/locations")
      (data["locations"] || []).map do |loc|
        { id: loc["name"], name: loc["description"], city: loc["city"], country: loc["country"] }
      end
    end

    def sizes
      [
        { id: "cx22", name: "CX22", vcpus: 2, ram_gb: 4, disk_gb: 40, monthly_cents: 400 },
        { id: "cx32", name: "CX32", vcpus: 4, ram_gb: 8, disk_gb: 80, monthly_cents: 800 },
        { id: "cx42", name: "CX42", vcpus: 8, ram_gb: 16, disk_gb: 160, monthly_cents: 1600 },
        { id: "cx52", name: "CX52", vcpus: 16, ram_gb: 32, disk_gb: 320, monthly_cents: 3200 }
      ]
    end

    def create_server(name:, region:, size:, ssh_key: nil)
      body = {
        name: name,
        server_type: size,
        location: region,
        image: "ubuntu-24.04",
        start_after_create: true
      }
      body[:ssh_keys] = [ssh_key] if ssh_key

      data = api_post("/servers", body)
      server = data["server"]
      {
        id: server["id"].to_s,
        ip: server["public_net"]["ipv4"]["ip"],
        status: server["status"]
      }
    end

    def delete_server(server_id)
      api_delete("/servers/#{server_id}")
    end

    def server_status(server_id)
      data = api_get("/servers/#{server_id}")
      data.dig("server", "status")
    end

    private

    def auth_header
      "Bearer #{@credential.api_key}"
    end
  end
end
