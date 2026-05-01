class CloudCredential < ApplicationRecord
  belongs_to :team

  encrypts :api_key

  validates :provider, presence: true, inclusion: { in: %w[hetzner vultr digitalocean linode] }
  validates :api_key, presence: true

  PROVIDERS = {
    "hetzner" => { name: "Hetzner", api_base: "https://api.hetzner.cloud/v1" },
    "vultr" => { name: "Vultr", api_base: "https://api.vultr.com/v2" },
    "digitalocean" => { name: "DigitalOcean", api_base: "https://api.digitalocean.com/v2" },
    "linode" => { name: "Linode", api_base: "https://api.linode.com/v4" }
  }.freeze
end
