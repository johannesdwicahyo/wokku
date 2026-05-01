module CloudProviders
  class Vultr < Base
    def regions
      data = api_get("/regions")
      (data["regions"] || []).select { |r| r["options"]&.include?("in_dc_2") }.map do |r|
        { id: r["id"], name: "#{r['city']}, #{r['country']}", city: r["city"], country: r["country"] }
      end
    end

    def sizes
      [
        { id: "vc2-1c-1gb", name: "1 vCPU / 1 GB", vcpus: 1, ram_gb: 1, disk_gb: 25, monthly_cents: 600 },
        { id: "vc2-1c-2gb", name: "1 vCPU / 2 GB", vcpus: 1, ram_gb: 2, disk_gb: 55, monthly_cents: 1200 },
        { id: "vc2-2c-4gb", name: "2 vCPU / 4 GB", vcpus: 2, ram_gb: 4, disk_gb: 80, monthly_cents: 2400 },
        { id: "vc2-4c-8gb", name: "4 vCPU / 8 GB", vcpus: 4, ram_gb: 8, disk_gb: 160, monthly_cents: 4800 }
      ]
    end

    def create_server(name:, region:, size:, ssh_key: nil)
      body = {
        label: name,
        region: region,
        plan: size,
        os_id: 2284,  # Ubuntu 24.04
        hostname: name
      }
      body[:sshkey_id] = [ ssh_key ] if ssh_key

      data = api_post("/instances", body)
      instance = data["instance"]
      {
        id: instance["id"],
        ip: instance["main_ip"],
        status: instance["status"]
      }
    end

    def delete_server(server_id)
      api_delete("/instances/#{server_id}")
    end

    def server_status(server_id)
      data = api_get("/instances/#{server_id}")
      data.dig("instance", "status")
    end

    private

    def auth_header
      "Bearer #{@credential.api_key}"
    end
  end
end
